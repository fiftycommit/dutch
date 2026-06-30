"""Inference helpers for AgentInterface v2 recurrent Q outputs.

The policy never synthesizes actions from masks. It scores the concrete
``legal_action_v2.actions`` entries emitted by the runner and returns one of
those entries. This keeps inference aligned with the environment legality
checks while future learners are still under construction.
"""

from __future__ import annotations

from dataclasses import dataclass
import random
from typing import Any

import torch

import loss_r2d2_v2
import model_r2d2_v2


@dataclass(frozen=True)
class SelectedActionV2:
    action_v2: dict[str, Any]
    legacy_action_id: int | None
    score: float
    is_random: bool
    metadata: dict[str, Any]


@dataclass(frozen=True)
class ScoredActionV2:
    legal_index: int
    action_v2: dict[str, Any]
    legacy_action_id: int | None
    legacy_kind: Any
    score: float


def score_legal_actions_v2(
    output: model_r2d2_v2.R2D2OutputV2,
    legal_action_v2: dict[str, Any],
    *,
    batch_index: int = 0,
    time_index: int = 0,
) -> list[ScoredActionV2]:
    """Score every ``legal_action_v2.actions`` entry with the factorized Q.

    This is the single canonical scorer reused by the greedy selection and by
    the action-trace logger, so trace scores are identical to the scores the
    policy actually uses (same ``score_legal_action_v2`` per entry, same model
    output). It preserves the original ``legal_index`` ordering.
    """

    entries = _legal_entries(legal_action_v2)
    scored: list[ScoredActionV2] = []
    for index, entry in enumerate(entries):
        action = _entry_action(entry)
        score = score_legal_action_v2(
            output,
            action,
            batch_index=batch_index,
            time_index=time_index,
        )
        legacy_id = entry.get("legacy_action_id")
        if legacy_id is not None and not isinstance(legacy_id, int):
            raise ValueError(f"legacy_action_id must be int or null: {entry!r}")
        scored.append(
            ScoredActionV2(
                legal_index=index,
                action_v2=action,
                legacy_action_id=None if legacy_id is None else int(legacy_id),
                legacy_kind=entry.get("legacy_kind"),
                score=score,
            )
        )
    return scored


def score_legal_action_v2(
    output: model_r2d2_v2.R2D2OutputV2,
    action_v2: dict[str, Any],
    *,
    batch_index: int = 0,
    time_index: int = 0,
) -> float:
    """Return the factorized Q score for one structured action."""

    _check_index(output, batch_index, time_index)
    if not isinstance(action_v2, dict):
        raise ValueError("action_v2 must be a dict")

    batch_size, total_len, _ = output.action_type_q.shape
    actions: list[list[dict[str, Any] | None]] = [
        [None for _ in range(total_len)] for _ in range(batch_size)
    ]
    actions[batch_index][time_index] = dict(action_v2)
    q_values = loss_r2d2_v2.select_action_q_from_output(output, actions)
    value = q_values[batch_index, time_index]
    if torch.isnan(value):
        raise ValueError(f"action_v2 produced NaN score: {action_v2!r}")
    return float(value.detach().cpu().item())


def select_greedy_action_v2(
    output: model_r2d2_v2.R2D2OutputV2,
    legal_action_v2: dict[str, Any],
    *,
    batch_index: int = 0,
    time_index: int = 0,
) -> SelectedActionV2:
    """Select the highest-scoring entry from ``legal_action_v2.actions``."""

    entries = _legal_entries(legal_action_v2)
    best: SelectedActionV2 | None = None
    for index, entry in enumerate(entries):
        action = _entry_action(entry)
        score = score_legal_action_v2(
            output,
            action,
            batch_index=batch_index,
            time_index=time_index,
        )
        candidate = _selected(entry, action, score, is_random=False, index=index)
        if best is None or candidate.score > best.score:
            best = candidate
    if best is None:
        raise ValueError("legal_action_v2.actions is empty")
    return best


def select_epsilon_greedy_action_v2(
    output: model_r2d2_v2.R2D2OutputV2,
    legal_action_v2: dict[str, Any],
    *,
    epsilon: float,
    rng: random.Random | None = None,
    batch_index: int = 0,
    time_index: int = 0,
) -> SelectedActionV2:
    """Select greedy or random legal action according to epsilon."""

    if not 0.0 <= epsilon <= 1.0:
        raise ValueError("epsilon must be between 0 and 1")
    rng = rng or random.Random()
    entries = _legal_entries(legal_action_v2)
    if rng.random() < epsilon:
        index = rng.randrange(len(entries))
        entry = entries[index]
        action = _entry_action(entry)
        score = score_legal_action_v2(
            output,
            action,
            batch_index=batch_index,
            time_index=time_index,
        )
        return _selected(entry, action, score, is_random=True, index=index)
    return select_greedy_action_v2(
        output,
        legal_action_v2,
        batch_index=batch_index,
        time_index=time_index,
    )


def select_action_from_batch_output(
    output: model_r2d2_v2.R2D2OutputV2,
    *,
    batch_index: int,
    time_index: int,
    legal_action_v2: dict[str, Any],
    epsilon: float = 0.0,
    rng: random.Random | None = None,
) -> SelectedActionV2:
    """Convenience wrapper for recurrent output tensors with batch/time axes."""

    return select_epsilon_greedy_action_v2(
        output,
        legal_action_v2,
        epsilon=epsilon,
        rng=rng,
        batch_index=batch_index,
        time_index=time_index,
    )


def action_message_for_runner_v2(selected: SelectedActionV2) -> dict[str, Any]:
    """Convert a selected action into the runner input JSON shape."""

    return {"action_v2": dict(selected.action_v2)}


def _legal_entries(legal_action_v2: dict[str, Any]) -> list[dict[str, Any]]:
    if not isinstance(legal_action_v2, dict):
        raise ValueError("legal_action_v2 must be a dict")
    raw_entries = legal_action_v2.get("actions")
    if not isinstance(raw_entries, list) or not raw_entries:
        raise ValueError("legal_action_v2.actions must be a non-empty list")
    entries: list[dict[str, Any]] = []
    for item in raw_entries:
        if not isinstance(item, dict):
            raise ValueError(f"legal action entry must be a dict: {item!r}")
        entries.append(item)
    return entries


def _entry_action(entry: dict[str, Any]) -> dict[str, Any]:
    action = entry.get("action_v2")
    if not isinstance(action, dict):
        raise ValueError(f"legal action entry missing action_v2 dict: {entry!r}")
    return dict(action)


def _selected(
    entry: dict[str, Any],
    action: dict[str, Any],
    score: float,
    *,
    is_random: bool,
    index: int,
) -> SelectedActionV2:
    legacy_id = entry.get("legacy_action_id")
    if legacy_id is not None and not isinstance(legacy_id, int):
        raise ValueError(f"legacy_action_id must be int or null: {entry!r}")
    return SelectedActionV2(
        action_v2=dict(action),
        legacy_action_id=None if legacy_id is None else int(legacy_id),
        score=float(score),
        is_random=is_random,
        metadata={
            "legal_index": index,
            "legacy_kind": entry.get("legacy_kind"),
        },
    )


def _check_index(
    output: model_r2d2_v2.R2D2OutputV2,
    batch_index: int,
    time_index: int,
) -> None:
    batch_size, total_len, _ = output.action_type_q.shape
    if not 0 <= batch_index < batch_size:
        raise IndexError(f"batch_index out of range: {batch_index}")
    if not 0 <= time_index < total_len:
        raise IndexError(f"time_index out of range: {time_index}")
