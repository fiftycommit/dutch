"""Reward scalarization for AgentInterface v2 / R2D2.

The Dart runner is still the gameplay authority. This module only turns the
runner's public reward components and public step events into the scalar reward
stored in ``TransitionV2.reward``.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any


FALSE_MATCH_PENALTY_REWARD = -0.05
SUCCESSFUL_MATCH_REWARD = 0.0
DESTAB_SCALE = 1.0 / 256.0
DESTAB_CAP = 2.0
RL_SEAT_ID = "p0"


@dataclass(frozen=True)
class RewardComponentsV2:
    principal: float = 0.0
    win_bonus: float = 0.0
    destab_raw: float = 0.0
    destab: float = 0.0
    false_match_penalty: float = 0.0
    successful_match: float = 0.0
    total: float = 0.0

    def to_dict(self) -> dict[str, float]:
        return {key: float(value) for key, value in asdict(self).items()}


def parse_reward_components_v2(
    msg: dict[str, Any],
    *,
    action_v2: dict[str, Any] | None = None,
    rl_seat_id: str = RL_SEAT_ID,
) -> RewardComponentsV2:
    """Parse and scalarize v2 reward components from one runner observation.

    ``recent_events`` is a rolling public buffer, not a per-step delta. Event
    shaping therefore only uses events whose ``step`` equals the emitted
    observation ``step``.
    """

    raw_rewards = msg.get("rewards")
    rewards = raw_rewards if isinstance(raw_rewards, dict) else {}
    principal = _float_or_zero(rewards.get("principal", msg.get("reward", 0.0)))
    win_bonus = _float_or_zero(rewards.get("win_bonus", 0.0))
    destab_raw = _float_or_zero(rewards.get("destab", 0.0))
    destab = _scale_destab(destab_raw)
    false_match_penalty = _false_match_penalty(msg, action_v2, rl_seat_id)
    successful_match = _successful_match_reward(msg, action_v2, rl_seat_id)
    total = scalarize_reward_v2(
        principal=principal,
        win_bonus=win_bonus,
        destab=destab,
        false_match_penalty=false_match_penalty,
        successful_match=successful_match,
    )
    return RewardComponentsV2(
        principal=principal,
        win_bonus=win_bonus,
        destab_raw=destab_raw,
        destab=destab,
        false_match_penalty=false_match_penalty,
        successful_match=successful_match,
        total=total,
    )


def scalarize_reward_v2(
    *,
    principal: float = 0.0,
    win_bonus: float = 0.0,
    destab: float = 0.0,
    false_match_penalty: float = 0.0,
    successful_match: float = 0.0,
) -> float:
    """Return the scalar reward optimized by R2D2 v2."""

    return float(
        principal
        + win_bonus
        + destab
        + false_match_penalty
        + successful_match
    )


def reward_from_message_v2(
    msg: dict[str, Any],
    *,
    action_v2: dict[str, Any] | None = None,
    rl_seat_id: str = RL_SEAT_ID,
) -> float:
    return parse_reward_components_v2(
        msg,
        action_v2=action_v2,
        rl_seat_id=rl_seat_id,
    ).total


def _scale_destab(value: float) -> float:
    clipped = max(-DESTAB_CAP, min(DESTAB_CAP, float(value)))
    return float(clipped * DESTAB_SCALE)


def _false_match_penalty(
    msg: dict[str, Any],
    action_v2: dict[str, Any] | None,
    rl_seat_id: str,
) -> float:
    if not _selected_action_type(action_v2, "match"):
        return 0.0
    if _has_current_step_event(
        msg,
        event_type="match_failure_penalty",
        actor=rl_seat_id,
    ):
        return FALSE_MATCH_PENALTY_REWARD
    return 0.0


def _successful_match_reward(
    msg: dict[str, Any],
    action_v2: dict[str, Any] | None,
    rl_seat_id: str,
) -> float:
    if SUCCESSFUL_MATCH_REWARD == 0.0 or not _selected_action_type(action_v2, "match"):
        return 0.0
    if _has_current_step_event(
        msg,
        event_type="discard_visible",
        actor=rl_seat_id,
        discard_reason="match_discard",
    ):
        return SUCCESSFUL_MATCH_REWARD
    return 0.0


def _has_current_step_event(
    msg: dict[str, Any],
    *,
    event_type: str,
    actor: str,
    discard_reason: str | None = None,
) -> bool:
    step = msg.get("step")
    for event in msg.get("recent_events") or []:
        if not isinstance(event, dict):
            continue
        if event.get("step") != step:
            continue
        if event.get("event_type") != event_type:
            continue
        if event.get("actor") != actor:
            continue
        if discard_reason is not None and event.get("discard_reason") != discard_reason:
            continue
        return True
    return False


def _selected_action_type(action_v2: dict[str, Any] | None, expected: str) -> bool:
    return isinstance(action_v2, dict) and action_v2.get("action_type") == expected


def _float_or_zero(value: Any) -> float:
    if isinstance(value, bool):
        return float(value)
    if isinstance(value, (int, float)):
        return float(value)
    return 0.0
