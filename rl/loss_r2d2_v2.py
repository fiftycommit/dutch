"""TD loss for AgentInterface v2 recurrent Q models (R2D2 core).

This module owns the *single source of truth* for n-step TD targets used in
training: targets are built from the sampled sequence inside
:func:`compute_td_loss_v2`. ``dataset_v2.compute_n_step_returns`` is an offline
analysis helper only and is never used to feed the learner.

It contains no learner loop, optimizer step, or target-network management. It
aligns a v2 sequence batch, the recurrent model outputs, played actions,
rewards, dones and masks into a finite TD loss, with:
- factorized greedy bootstrap over the *legal next actions* (single or
  Double-Q), falling back to the action-type head only when per-position legal
  actions are unavailable;
- optional importance-sampling (PER) weighting per sequence;
- burn-in / padding exclusion through ``valid_mask = train_mask & ~padding``.

Burn-in convention (*burn-in complet*, no stored recurrent state): the model
warms its hidden state from a zero state across the burn-in positions; the loss
only scores ``train_mask`` positions. See ``replay_buffer_v2`` and
``model_r2d2_v2``.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import torch
import torch.nn.functional as F

import encoding_v2
import model_r2d2_v2
from replay_buffer_v2 import SequenceBatchV2


@dataclass(frozen=True)
class LossOutputV2:
    loss: torch.Tensor
    td_error: torch.Tensor
    q_taken: torch.Tensor
    target_q: torch.Tensor
    td_target: torch.Tensor
    valid_mask: torch.Tensor
    elementwise: torch.Tensor
    metrics: dict[str, float]


def select_action_q_from_output(
    output: model_r2d2_v2.R2D2OutputV2,
    actions_v2: list[list[dict[str, Any] | None]],
    legacy_action_ids: Any | None = None,
) -> torch.Tensor:
    """Select factorized Q-values for played structured actions.

    ``legacy_action_ids`` is accepted for alignment/debug compatibility but is
    not used unless the model eventually exposes a flat legacy head. The main
    architecture remains factorized around ``action_v2``.
    """

    del legacy_action_ids
    batch_size, total_len, _ = output.action_type_q.shape
    if len(actions_v2) != batch_size:
        raise ValueError(
            f"actions_v2 batch mismatch: {len(actions_v2)} != {batch_size}"
        )

    q_taken = torch.zeros(
        (batch_size, total_len),
        dtype=output.action_type_q.dtype,
        device=output.action_type_q.device,
    )

    for batch_idx, row in enumerate(actions_v2):
        if len(row) != total_len:
            raise ValueError(
                f"actions_v2 time mismatch at batch {batch_idx}: "
                f"{len(row)} != {total_len}"
            )
        for t, action in enumerate(row):
            if action is None:
                continue
            if not isinstance(action, dict):
                raise ValueError(
                    f"action_v2 at batch={batch_idx}, t={t} must be a dict or None"
                )
            q_taken[batch_idx, t] = _select_one_action_q(output, action, batch_idx, t)

    return q_taken


def compute_td_loss_v2(
    online_model: Any,
    target_model: Any,
    batch: SequenceBatchV2,
    *,
    gamma: float = 0.99,
    n_step: int = 1,
    double_q: bool = False,
    is_weights: Any | None = None,
) -> LossOutputV2:
    """Compute an n-step TD Huber loss for a v2 sequence batch.

    Convention:
    - ``valid_mask = train_mask & ~padding_mask``.
    - burn-in steps are excluded through ``train_mask``.
    - padded positions are excluded.
    - ``done`` cuts bootstrap (n-step targets never bootstrap past a terminal
      transition inside the window).
    - n-step targets are built inside the sampled sequence and never cross
      padding. Sequence construction already prevents episode crossing.

    Bootstrap:
    - when ``batch.legal_actions_v2`` is available, the bootstrap value at each
      state is taken over the *legal next actions* using the factorized
      Q-heads. With ``double_q=True`` the online network selects the greedy
      legal action and the target network evaluates it; otherwise the target
      network maxes over legal actions.
    - when ``batch.legal_actions_v2`` is ``None`` (e.g. synthetic batches), the
      loss falls back to the action-type head only. This fallback is explicit
      and tested; it never fabricates an illegal action.

    ``is_weights`` is an optional per-sequence importance-sampling weight vector
    (shape ``[batch]``). When provided, the loss is the weighted mean of the
    per-sequence mean TD losses; otherwise it is the plain mean over valid
    positions.
    """

    if gamma < 0.0:
        raise ValueError("gamma must be >= 0")
    if n_step <= 0:
        raise ValueError("n_step must be positive")

    online_output = online_model(batch, apply_masks=True)
    with torch.no_grad():
        target_output = target_model(batch, apply_masks=True)
        online_next_output = online_model(batch, apply_masks=True) if double_q else None

    q_taken = select_action_q_from_output(
        online_output,
        batch.actions_v2,
        batch.legacy_action_ids,
    )
    rewards = torch.as_tensor(batch.rewards, dtype=q_taken.dtype, device=q_taken.device)
    dones = torch.as_tensor(batch.dones, dtype=torch.bool, device=q_taken.device)
    train_mask = torch.as_tensor(batch.train_mask, dtype=torch.bool, device=q_taken.device)
    padding_mask = torch.as_tensor(batch.padding_mask, dtype=torch.bool, device=q_taken.device)
    valid_mask = train_mask & ~padding_mask
    if not bool(valid_mask.any()):
        raise ValueError("TD loss has no valid train positions")

    target_q = _bootstrap_q(
        target_output,
        online_next_output=online_next_output,
        batch=batch,
        double_q=double_q,
    )
    td_target = _build_n_step_targets(
        rewards=rewards,
        dones=dones,
        padding_mask=padding_mask,
        bootstrap_q=target_q,
        gamma=gamma,
        n_step=n_step,
    )

    td_error = q_taken - td_target
    elementwise = F.smooth_l1_loss(q_taken, td_target, reduction="none")

    loss, mean_is_weight, weighted = _reduce_loss(
        elementwise,
        valid_mask=valid_mask,
        is_weights=is_weights,
        device=q_taken.device,
        dtype=q_taken.dtype,
    )

    valid_td = td_error[valid_mask]
    metrics = {
        "loss": float(loss.detach().cpu().item()),
        "valid_count": float(valid_mask.sum().detach().cpu().item()),
        "mean_q_taken": float(q_taken[valid_mask].detach().cpu().mean().item()),
        "mean_td_target": float(td_target[valid_mask].detach().cpu().mean().item()),
        "mean_abs_td_error": float(valid_td.detach().cpu().abs().mean().item()),
        "max_abs_td_error": float(valid_td.detach().cpu().abs().max().item()),
        "mean_is_weight": float(mean_is_weight),
        "gamma": float(gamma),
        "n_step": float(n_step),
        "double_q": 1.0 if double_q else 0.0,
        "weighted": 1.0 if weighted else 0.0,
    }

    return LossOutputV2(
        loss=loss,
        td_error=td_error,
        q_taken=q_taken,
        target_q=target_q,
        td_target=td_target,
        valid_mask=valid_mask,
        elementwise=elementwise,
        metrics=metrics,
    )


def _reduce_loss(
    elementwise: torch.Tensor,
    *,
    valid_mask: torch.Tensor,
    is_weights: Any | None,
    device: torch.device,
    dtype: torch.dtype,
) -> tuple[torch.Tensor, float, bool]:
    """Reduce per-position TD losses to a scalar, optionally IS-weighted."""

    if is_weights is None:
        loss = elementwise[valid_mask].mean()
        return loss, 1.0, False

    weights = torch.as_tensor(is_weights, dtype=dtype, device=device)
    batch_size = elementwise.shape[0]
    if weights.ndim != 1 or weights.shape[0] != batch_size:
        raise ValueError(
            f"is_weights must have shape [{batch_size}], got {tuple(weights.shape)}"
        )
    valid = valid_mask.to(dtype)
    valid_counts = valid.sum(dim=1).clamp(min=1.0)
    seq_loss = (elementwise * valid).sum(dim=1) / valid_counts
    rows = valid_mask.any(dim=1)
    if not bool(rows.any()):
        raise ValueError("TD loss has no valid sequences to weight")
    loss = (weights * seq_loss)[rows].mean()
    mean_is_weight = float(weights[rows].detach().cpu().mean().item())
    return loss, mean_is_weight, True


def _select_one_action_q(
    output: model_r2d2_v2.R2D2OutputV2,
    action: dict[str, Any],
    batch_idx: int,
    t: int,
) -> torch.Tensor:
    action_type = action.get("action_type")
    if not isinstance(action_type, str):
        raise ValueError(f"action_v2 missing string action_type: {action!r}")
    try:
        action_idx = encoding_v2.ACTION_TYPES.index(action_type)
    except ValueError as exc:
        raise ValueError(f"unknown action_type {action_type!r}") from exc

    q = output.action_type_q[batch_idx, t, action_idx]
    if action_type in {"draw", "call_dutch", "post_draw_discard", "skip_power", "pass_tick"}:
        return q
    if action_type == "post_draw_replace":
        return q + _slot_q(output.own_slot_q, action, batch_idx, t, "slot", "own_slot")
    if action_type == "match":
        return q + _slot_q(output.match_slot_q, action, batch_idx, t, "slot", "match_slot")
    if action_type == "power_7_look":
        return q + _slot_q(output.own_slot_q, action, batch_idx, t, "slot", "own_slot")
    if action_type == "power_10_spy":
        player = _index(action, "target_player", "player", "target")
        target_slot = _index(action, "target_slot", "slot")
        return (
            q
            + output.target_player_q[batch_idx, t, player]
            + output.target_slot_q[batch_idx, t, player, target_slot]
        )
    if action_type == "joker":
        player = _index(action, "target_player", "player", "target")
        return q + output.target_player_q[batch_idx, t, player]
    if action_type == "jack_swap":
        player_a = _index(action, "player_a")
        slot_a = _index(action, "slot_a")
        player_b = _index(action, "player_b")
        slot_b = _index(action, "slot_b")
        return (
            q
            + output.jack_player_a_q[batch_idx, t, player_a]
            + output.jack_slot_a_q[batch_idx, t, player_a, slot_a]
            + output.jack_player_b_q[batch_idx, t, player_b]
            + output.jack_slot_b_q[batch_idx, t, player_b, slot_b]
        )

    raise ValueError(f"unhandled action_type {action_type!r}")


def _slot_q(
    values: torch.Tensor,
    action: dict[str, Any],
    batch_idx: int,
    t: int,
    *keys: str,
) -> torch.Tensor:
    slot = _index(action, *keys)
    return values[batch_idx, t, slot]


def _index(action: dict[str, Any], *keys: str) -> int:
    for key in keys:
        value = action.get(key)
        if value is not None:
            if not isinstance(value, int):
                raise ValueError(f"{key} must be an int in action_v2: {action!r}")
            if value < 0:
                raise ValueError(f"{key} must be >= 0 in action_v2: {action!r}")
            return int(value)
    raise ValueError(f"missing one of {keys} in action_v2: {action!r}")


def _bootstrap_q(
    target_output: model_r2d2_v2.R2D2OutputV2,
    *,
    online_next_output: model_r2d2_v2.R2D2OutputV2 | None,
    batch: SequenceBatchV2,
    double_q: bool,
) -> torch.Tensor:
    """Per-position bootstrap value V(s) used by the n-step target.

    Uses the factorized greedy action over legal next actions when available,
    otherwise the action-type-head fallback.
    """

    if batch.legal_actions_v2 is None:
        return _bootstrap_action_type_q(
            target_output,
            online_output=online_next_output,
            double_q=double_q,
        )
    return _bootstrap_factorized_q(
        target_output,
        online_next_output=online_next_output,
        batch=batch,
        double_q=double_q,
    )


def _bootstrap_factorized_q(
    target_output: model_r2d2_v2.R2D2OutputV2,
    *,
    online_next_output: model_r2d2_v2.R2D2OutputV2 | None,
    batch: SequenceBatchV2,
    double_q: bool,
) -> torch.Tensor:
    if double_q and online_next_output is None:
        raise ValueError("double_q=True requires online_next_output")

    batch_size, total_len, _ = target_output.action_type_q.shape
    bootstrap = torch.zeros(
        (batch_size, total_len),
        dtype=target_output.action_type_q.dtype,
        device=target_output.action_type_q.device,
    )
    legal_actions = batch.legal_actions_v2
    for b in range(batch_size):
        for t in range(total_len):
            if bool(batch.padding_mask[b][t]):
                continue
            legal = legal_actions[b][t]
            if not legal:
                raise ValueError(
                    f"position (batch={b}, t={t}) is non-padding but has no legal "
                    "action_v2 for the bootstrap"
                )
            if double_q:
                online_scores = torch.stack(
                    [_select_one_action_q(online_next_output, action, b, t) for action in legal]
                )
                best = int(torch.argmax(online_scores).item())
                bootstrap[b, t] = _select_one_action_q(target_output, legal[best], b, t)
            else:
                target_scores = torch.stack(
                    [_select_one_action_q(target_output, action, b, t) for action in legal]
                )
                bootstrap[b, t] = torch.max(target_scores)
    return bootstrap


def _bootstrap_action_type_q(
    target_output: model_r2d2_v2.R2D2OutputV2,
    *,
    online_output: model_r2d2_v2.R2D2OutputV2 | None,
    double_q: bool,
) -> torch.Tensor:
    if double_q:
        if online_output is None:
            raise ValueError("double_q=True requires online_output")
        next_action = online_output.action_type_q.argmax(dim=-1)
        return target_output.action_type_q.gather(
            dim=-1,
            index=next_action.unsqueeze(-1),
        ).squeeze(-1)
    return target_output.action_type_q.max(dim=-1).values


def _build_n_step_targets(
    *,
    rewards: torch.Tensor,
    dones: torch.Tensor,
    padding_mask: torch.Tensor,
    bootstrap_q: torch.Tensor,
    gamma: float,
    n_step: int,
) -> torch.Tensor:
    batch_size, total_len = rewards.shape
    target = torch.zeros_like(rewards)

    for offset in range(n_step):
        valid = torch.zeros_like(dones)
        if offset == 0:
            valid = ~padding_mask
        elif offset < total_len:
            prefix_done = _any_done_before(dones, padding_mask, offset)
            valid[:, : total_len - offset] = (
                ~padding_mask[:, offset:]
                & ~prefix_done[:, : total_len - offset]
            )
        if offset < total_len:
            target[:, : total_len - offset] += (
                (gamma**offset) * rewards[:, offset:] * valid[:, : total_len - offset]
            )

    bootstrap_offset = n_step
    if bootstrap_offset < total_len:
        prior_done = _any_done_before(dones, padding_mask, bootstrap_offset)
        bootstrap_valid = (
            ~padding_mask[:, bootstrap_offset:]
            & ~prior_done[:, : total_len - bootstrap_offset]
        )
        target[:, : total_len - bootstrap_offset] += (
            (gamma**bootstrap_offset)
            * bootstrap_q[:, bootstrap_offset:]
            * bootstrap_valid
        )

    return target


def _any_done_before(
    dones: torch.Tensor,
    padding_mask: torch.Tensor,
    offset: int,
) -> torch.Tensor:
    batch_size, total_len = dones.shape
    result = torch.zeros((batch_size, total_len), dtype=torch.bool, device=dones.device)
    if offset <= 0:
        return result
    for prior in range(offset):
        if prior >= total_len:
            break
        result[:, : total_len - prior] |= dones[:, prior:] | padding_mask[:, prior:]
    return result
