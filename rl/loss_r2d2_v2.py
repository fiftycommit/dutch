"""Minimal TD loss plumbing for AgentInterface v2 recurrent Q models.

This module intentionally contains no learner loop, optimizer step, target
network management, or training script. It only verifies that a v2 sequence
batch, the recurrent model outputs, played actions, rewards, dones, and masks
can be aligned into a finite TD loss.
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
) -> LossOutputV2:
    """Compute a minimal n-step TD Huber loss for a v2 sequence batch.

    Convention:
    - ``valid_mask = train_mask & ~padding_mask``.
    - burn-in steps are excluded through ``train_mask``.
    - padded positions are excluded.
    - ``done`` cuts bootstrap.
    - n-step targets are built inside the sampled sequence and never cross
      padding. Sequence construction already prevents episode crossing.

    The bootstrap action currently uses the action-type head only. That keeps
    the loss deterministic while the full factorized greedy action selector is
    still a future learner concern.
    """

    if gamma < 0.0:
        raise ValueError("gamma must be >= 0")
    if n_step <= 0:
        raise ValueError("n_step must be positive")

    online_output = online_model(batch, apply_masks=True)
    with torch.no_grad():
        target_output = target_model(batch, apply_masks=True)
        if double_q:
            online_next_output = online_model(batch, apply_masks=True)
        else:
            online_next_output = None

    q_taken = select_action_q_from_output(
        online_output,
        batch.actions_v2,
        batch.legacy_action_ids,
    )
    rewards = torch.as_tensor(
        batch.rewards,
        dtype=q_taken.dtype,
        device=q_taken.device,
    )
    dones = torch.as_tensor(
        batch.dones,
        dtype=torch.bool,
        device=q_taken.device,
    )
    train_mask = torch.as_tensor(
        batch.train_mask,
        dtype=torch.bool,
        device=q_taken.device,
    )
    padding_mask = torch.as_tensor(
        batch.padding_mask,
        dtype=torch.bool,
        device=q_taken.device,
    )
    valid_mask = train_mask & ~padding_mask
    if not bool(valid_mask.any()):
        raise ValueError("TD loss has no valid train positions")

    target_q = _bootstrap_action_type_q(
        target_output,
        online_output=online_next_output,
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
    loss = elementwise[valid_mask].mean()

    valid_td = td_error[valid_mask]
    metrics = {
        "loss": float(loss.detach().cpu().item()),
        "valid_count": float(valid_mask.sum().detach().cpu().item()),
        "mean_q_taken": float(q_taken[valid_mask].detach().cpu().mean().item()),
        "mean_td_target": float(td_target[valid_mask].detach().cpu().mean().item()),
        "mean_abs_td_error": float(valid_td.detach().cpu().abs().mean().item()),
        "gamma": float(gamma),
        "n_step": float(n_step),
        "double_q": 1.0 if double_q else 0.0,
    }

    return LossOutputV2(
        loss=loss,
        td_error=td_error,
        q_taken=q_taken,
        target_q=target_q,
        td_target=td_target,
        valid_mask=valid_mask,
        metrics=metrics,
    )


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
