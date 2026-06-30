"""Reward scalarization for AgentInterface v2 / R2D2.

The Dart runner is still the gameplay authority. This module only turns the
runner's public reward components and public step events into the scalar reward
stored in ``TransitionV2.reward``.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any


FALSE_MATCH_PENALTY_REWARD = -0.05
SUCCESSFUL_MATCH_BONUS_POTENTIAL = 0.02
WIN_REWARD = 1.0
TERMINAL_LOSS_REWARD = 0.0
FAILED_DUTCH_PENALTY_REWARD = -0.25
DESTAB_SCALE = 1.0 / 256.0
DESTAB_CAP = 2.0
RL_SEAT_ID = "p0"


@dataclass(frozen=True)
class RewardComponentsV2:
    principal: float = 0.0
    win_bonus: float = 0.0
    destab_raw: float = 0.0
    destab_bonus_potential: float = 0.0
    successful_match_bonus_potential: float = 0.0
    positive_bonus_potential: float = 0.0
    paid_positive_bonus: float = 0.0
    false_match_penalty: float = 0.0
    immediate_penalty: float = 0.0
    terminal_win_reward: float = 0.0
    terminal_loss_reward: float = 0.0
    terminal_win_bonus: float = 0.0
    terminal_failed_dutch_penalty: float = 0.0
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
    destab_bonus_potential = _destab_bonus_potential(destab_raw)
    successful_match_bonus_potential = _successful_match_bonus_potential(
        msg,
        action_v2,
        rl_seat_id,
    )
    positive_bonus_potential = (
        destab_bonus_potential + successful_match_bonus_potential
    )
    false_match_penalty = _false_match_penalty(msg, action_v2, rl_seat_id)
    immediate_penalty = false_match_penalty
    terminal_win_reward = _terminal_win_reward(msg)
    terminal_loss_reward = _terminal_loss_reward(msg)
    terminal_win_bonus = _terminal_win_bonus(msg, win_bonus)
    terminal_failed_dutch_penalty = _terminal_failed_dutch_penalty(msg, action_v2)
    total = scalarize_reward_v2(
        immediate_penalty=immediate_penalty,
        terminal_win_reward=terminal_win_reward,
        terminal_loss_reward=terminal_loss_reward,
        terminal_win_bonus=terminal_win_bonus,
        terminal_failed_dutch_penalty=terminal_failed_dutch_penalty,
    )
    return RewardComponentsV2(
        principal=principal,
        win_bonus=win_bonus,
        destab_raw=destab_raw,
        destab_bonus_potential=destab_bonus_potential,
        successful_match_bonus_potential=successful_match_bonus_potential,
        positive_bonus_potential=positive_bonus_potential,
        paid_positive_bonus=0.0,
        false_match_penalty=false_match_penalty,
        immediate_penalty=immediate_penalty,
        terminal_win_reward=terminal_win_reward,
        terminal_loss_reward=terminal_loss_reward,
        terminal_win_bonus=terminal_win_bonus,
        terminal_failed_dutch_penalty=terminal_failed_dutch_penalty,
        total=total,
    )


def scalarize_reward_v2(
    *,
    principal: float = 0.0,
    win_bonus: float = 0.0,
    destab: float = 0.0,
    false_match_penalty: float = 0.0,
    successful_match: float = 0.0,
    immediate_penalty: float = 0.0,
    terminal_win_reward: float = 0.0,
    terminal_loss_reward: float = 0.0,
    terminal_win_bonus: float = 0.0,
    terminal_failed_dutch_penalty: float = 0.0,
    paid_positive_bonus: float = 0.0,
) -> float:
    """Return the scalar reward optimized by R2D2 v2."""

    del principal, win_bonus, destab, false_match_penalty, successful_match
    return float(
        immediate_penalty
        + terminal_win_reward
        + terminal_loss_reward
        + terminal_win_bonus
        + terminal_failed_dutch_penalty
        + paid_positive_bonus
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


def apply_paid_positive_bonus_v2(
    components: dict[str, float] | None,
    paid_positive_bonus: float,
) -> dict[str, float]:
    """Return terminal reward components with win-gated positive bonus paid."""

    out = _float_components(components)
    out["paid_positive_bonus"] = float(paid_positive_bonus)
    out["total"] = scalarize_reward_v2(
        immediate_penalty=out.get("immediate_penalty", 0.0),
        terminal_win_reward=out.get("terminal_win_reward", 0.0),
        terminal_loss_reward=out.get("terminal_loss_reward", 0.0),
        terminal_win_bonus=out.get("terminal_win_bonus", 0.0),
        terminal_failed_dutch_penalty=out.get("terminal_failed_dutch_penalty", 0.0),
        paid_positive_bonus=out.get("paid_positive_bonus", 0.0),
    )
    return out


def positive_bonus_potential_from_components_v2(
    components: dict[str, float] | None,
) -> float:
    return _float_components(components).get("positive_bonus_potential", 0.0)


def is_terminal_win_v2(info: dict[str, Any] | None, next_obs_raw: dict[str, Any] | None) -> bool:
    """Return whether p0 won, using terminal info first and legacy rewards second."""

    info = info if isinstance(info, dict) else {}
    won = _won_from_info(info)
    if won is not None:
        return won
    rank = _rank_from_info(info)
    if rank is not None:
        return rank == 1
    if isinstance(next_obs_raw, dict):
        won = _terminal_won(next_obs_raw)
        if won is not None:
            return won
    return False


def _destab_bonus_potential(value: float) -> float:
    clipped = max(0.0, min(DESTAB_CAP, float(value)))
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


def _successful_match_bonus_potential(
    msg: dict[str, Any],
    action_v2: dict[str, Any] | None,
    rl_seat_id: str,
) -> float:
    if (
        SUCCESSFUL_MATCH_BONUS_POTENTIAL == 0.0
        or not _selected_action_type(action_v2, "match")
    ):
        return 0.0
    if _has_current_step_event(
        msg,
        event_type="discard_visible",
        actor=rl_seat_id,
        discard_reason="match_discard",
    ):
        return SUCCESSFUL_MATCH_BONUS_POTENTIAL
    return 0.0


def _terminal_win_reward(msg: dict[str, Any]) -> float:
    if not bool(msg.get("done")):
        return 0.0
    won = _terminal_won(msg)
    if won is True:
        return WIN_REWARD
    return 0.0


def _terminal_loss_reward(msg: dict[str, Any]) -> float:
    if not bool(msg.get("done")):
        return 0.0
    won = _terminal_won(msg)
    if won is False:
        return TERMINAL_LOSS_REWARD
    return 0.0


def _terminal_win_bonus(msg: dict[str, Any], win_bonus: float) -> float:
    if bool(msg.get("done")) and _terminal_won(msg) is True:
        return max(0.0, float(win_bonus))
    return 0.0


def _terminal_failed_dutch_penalty(
    msg: dict[str, Any],
    action_v2: dict[str, Any] | None,
) -> float:
    if not bool(msg.get("done")):
        return 0.0
    info = msg.get("info")
    info = info if isinstance(info, dict) else {}
    called = info.get("called_dutch")
    won = _terminal_won(msg)
    if called is True and won is False:
        return FAILED_DUTCH_PENALTY_REWARD
    if called is None and _selected_action_type(action_v2, "call_dutch") and won is False:
        return FAILED_DUTCH_PENALTY_REWARD
    return 0.0


def _terminal_won(msg: dict[str, Any]) -> bool | None:
    info = msg.get("info")
    info = info if isinstance(info, dict) else {}
    won = _won_from_info(info)
    if won is not None:
        return won
    rank = _rank_from_info(info)
    if rank is not None:
        return rank == 1
    if bool(msg.get("done")):
        raw_rewards = msg.get("rewards")
        rewards = raw_rewards if isinstance(raw_rewards, dict) else {}
        principal = _float_or_zero(rewards.get("principal", msg.get("reward", 0.0)))
        if principal > 0.0:
            return True
        if principal < 0.0:
            return False
    return None


def _won_from_info(info: dict[str, Any]) -> bool | None:
    for key in ("won", "win", "is_winner"):
        value = info.get(key)
        if isinstance(value, bool):
            return bool(value)
    return None


def _rank_from_info(info: dict[str, Any]) -> int | None:
    value = info.get("rank") or info.get("final_rank")
    return int(value) if isinstance(value, int) else None


def _float_components(components: dict[str, float] | None) -> dict[str, float]:
    if not isinstance(components, dict):
        return {}
    return {
        str(key): float(value)
        for key, value in components.items()
        if isinstance(value, (int, float))
    }


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
