"""Tests for R2D2 v2 reward scalarization.

Run from rl/:
    uv run python test_reward_v2.py
"""

from __future__ import annotations

import json
import tempfile
from pathlib import Path
from typing import Any

import action_trace_v2
import encoding_v2
import evaluate_r2d2_v2
import reward_v2
import rollout_v2


def _msg(
    *,
    step: int = 1,
    principal: float = 0.0,
    win_bonus: float = 0.0,
    destab: float = 0.0,
    events: list[dict[str, Any]] | None = None,
    done: bool = False,
    info: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "type": "observation",
        "step": step,
        "done": done,
        "reward": principal,
        "rewards": {
            "principal": principal,
            "win_bonus": win_bonus,
            "destab": destab,
        },
        "recent_events": events or [],
        "info": info or {},
    }


def _success_event(step: int = 1, *, actor: str = "p0") -> dict[str, Any]:
    return {
        "step": step,
        "event_type": "discard_visible",
        "actor": actor,
        "discard_reason": "match_discard",
    }


def _false_event(step: int = 1, *, actor: str = "p0") -> dict[str, Any]:
    return {
        "step": step,
        "event_type": "match_failure_penalty",
        "actor": actor,
    }


def _match_action() -> dict[str, Any]:
    return {"action_type": "match", "slot": 0}


def _obs(step: int, *, done: bool = False) -> dict[str, Any]:
    return {
        "type": "observation",
        "done": done,
        "micro_phase": "reaction",
        "action_mask": {"pass_tick": True},
        "obs": {
            "phase": "reaction",
            "micro_phase": "reaction",
            "turn_count": step,
            "action_count": step,
            "num_players": 2,
            "deck_size": 20,
            "discard_size": 5,
            "top_discard_value": "7",
            "top_discard_points": 7,
            "dutch_called": False,
            "dutch_caller_is_me": False,
            "hand_size": 2,
            "opponents": [{"seat": "p1", "hand_size": 3}],
        },
        "recent_events": [],
        "slot_stability": {
            "players": [
                {
                    "seat": 0,
                    "player_id": "p0",
                    "slots": [
                        {
                            "slot": 0,
                            "turns_since_changed": 1,
                            "actions_since_changed": step,
                            "changed_this_turn": False,
                            "last_changed_reason": "initial",
                        }
                    ],
                }
            ],
            "recent_changes": [],
        },
        "legal_private_memory": {
            "own_hand": {
                "slots": [
                    {
                        "slot": 0,
                        "known": True,
                        "believed_value": "7",
                        "believed_match_value": "7",
                        "believed_points": 7,
                        "valid": True,
                        "confidence": 1.0,
                        "age_actions": step,
                        "age_turns": 1,
                        "source": "mental_map",
                    }
                ]
            },
            "opponents": [],
        },
        "legal_action_v2": {
            "available_action_types": ["match"],
            "masks": {"action_type": {"match": True}},
            "actions": [
                {
                    "action_v2": _match_action(),
                    "legacy_action_id": 6186,
                    "legacy_kind": "match",
                }
            ],
            "legacy_action_ids": {"action_type=match|slot=0": 6186},
        },
    }


def _transition(
    *,
    reward: float,
    components: dict[str, float] | None = None,
    done: bool = False,
    info: dict[str, Any] | None = None,
    step_index: int = 0,
) -> rollout_v2.TransitionV2:
    obs = _obs(step_index)
    next_obs = _obs(step_index + 1, done=done)
    return rollout_v2.TransitionV2(
        obs_raw=obs,
        obs_encoded_v2=encoding_v2.encode_observation_v2(obs),
        action_v2=_match_action(),
        legacy_action_id=6186,
        reward=reward,
        done=done,
        next_obs_raw=next_obs,
        next_obs_encoded_v2=None if done else encoding_v2.encode_observation_v2(next_obs),
        info=info or {},
        episode_id="ep",
        step_index=step_index,
        reward_components=components,
    )


def _parsed_transition(
    msg: dict[str, Any],
    *,
    action_v2: dict[str, Any] | None = None,
    step_index: int = 0,
) -> rollout_v2.TransitionV2:
    components = reward_v2.parse_reward_components_v2(msg, action_v2=action_v2)
    return _transition(
        reward=components.total,
        components=components.to_dict(),
        done=bool(msg.get("done")),
        info=dict(msg.get("info") or {}),
        step_index=step_index,
    )


def _episode_total(transitions: list[rollout_v2.TransitionV2]) -> float:
    return sum(float(transition.reward) for transition in transitions)


def test_parse_reward_components_from_runner_json() -> None:
    components = reward_v2.parse_reward_components_v2(
        _msg(principal=0.5, win_bonus=0.25, destab=1.0)
    )
    if components.principal != 0.5 or components.win_bonus != 0.25:
        raise AssertionError(f"base components wrong: {components}")
    if abs(components.destab_bonus_potential - reward_v2.DESTAB_SCALE) > 1e-12:
        raise AssertionError(f"destab potential wrong: {components}")
    if components.total != 0.0:
        raise AssertionError(f"positive potential should not pay immediately: {components}")


def test_scalarize_principal_only_stays_zero() -> None:
    total = reward_v2.scalarize_reward_v2(principal=-1.0)
    if total != 0.0:
        raise AssertionError(f"principal should be diagnostic only: {total}")


def test_scalarize_immediate_match_aliases_work() -> None:
    direct = reward_v2.scalarize_reward_v2(
        immediate_reward=reward_v2.SUCCESSFUL_MATCH_REWARD
    )
    alias = reward_v2.scalarize_reward_v2(
        successful_match=reward_v2.SUCCESSFUL_MATCH_REWARD
    )
    if direct != reward_v2.SUCCESSFUL_MATCH_REWARD or alias != direct:
        raise AssertionError(f"successful match scalarization wrong: {direct}, {alias}")


def test_scalarize_includes_win_bonus_only_on_win() -> None:
    components = reward_v2.parse_reward_components_v2(
        _msg(done=True, info={"won": True, "rank": 1}, win_bonus=0.3)
    )
    expected = reward_v2.WIN_REWARD + 0.3
    if abs(components.total - expected) > 1e-12:
        raise AssertionError(f"win_bonus was not paid on win: {components}")
    lost = reward_v2.parse_reward_components_v2(
        _msg(done=True, info={"won": False, "rank": 6}, win_bonus=0.3)
    )
    if lost.total != reward_v2.TERMINAL_LOSS_REWARD:
        raise AssertionError(f"win_bonus paid on loss: {lost}")


def test_destab_remains_win_gated_positive_potential() -> None:
    components = reward_v2.parse_reward_components_v2(_msg(destab=999.0))
    expected = reward_v2.DESTAB_CAP * reward_v2.DESTAB_SCALE
    if abs(components.destab_bonus_potential - expected) > 1e-12:
        raise AssertionError(f"destab cap/scale wrong: {components}")
    if components.positive_bonus_potential != expected:
        raise AssertionError(f"destab should be the only positive potential: {components}")
    if components.total != 0.0:
        raise AssertionError(f"destab should not pay immediately: {components}")


def test_p0_successful_match_gives_immediate_reward() -> None:
    components = reward_v2.parse_reward_components_v2(
        _msg(step=4, events=[_success_event(4)]),
        action_v2=_match_action(),
    )
    if components.successful_match_reward != reward_v2.SUCCESSFUL_MATCH_REWARD:
        raise AssertionError(f"successful match reward missing: {components}")
    if components.total != reward_v2.SUCCESSFUL_MATCH_REWARD:
        raise AssertionError(f"successful match total should be immediate: {components}")
    if components.positive_bonus_potential != 0.0:
        raise AssertionError(f"successful match should not be win-gated: {components}")


def test_p0_false_match_gives_immediate_penalty() -> None:
    components = reward_v2.parse_reward_components_v2(
        _msg(step=4, events=[_false_event(4)]),
        action_v2=_match_action(),
    )
    if components.false_match_penalty != reward_v2.FALSE_MATCH_PENALTY_REWARD:
        raise AssertionError(f"false match penalty missing: {components}")
    if components.total != reward_v2.FALSE_MATCH_PENALTY_REWARD:
        raise AssertionError(f"false match total should be immediate: {components}")


def test_false_match_costs_more_than_successful_match_rewards() -> None:
    if abs(reward_v2.FALSE_MATCH_PENALTY_REWARD) <= reward_v2.SUCCESSFUL_MATCH_REWARD:
        raise AssertionError(
            "false match must cost more than successful match rewards"
        )


def test_opponent_successful_match_is_public_but_gives_no_p0_reward() -> None:
    event = _success_event(4, actor="p1")
    msg = _msg(step=4, events=[event])
    components = reward_v2.parse_reward_components_v2(msg, action_v2={"action_type": "pass_tick"})
    if msg["recent_events"][0]["actor"] != "p1":
        raise AssertionError("opponent actor was not public in recent_events")
    if components.successful_match_reward != 0.0 or components.total != 0.0:
        raise AssertionError(f"opponent success rewarded p0: {components}")


def test_opponent_false_match_is_public_but_gives_no_p0_penalty() -> None:
    event = _false_event(4, actor="p1")
    msg = _msg(step=4, events=[event])
    components = reward_v2.parse_reward_components_v2(msg, action_v2={"action_type": "pass_tick"})
    if msg["recent_events"][0]["actor"] != "p1":
        raise AssertionError("opponent actor was not public in recent_events")
    if components.false_match_penalty != 0.0 or components.total != 0.0:
        raise AssertionError(f"opponent false match penalized p0: {components}")


def test_old_or_bot_events_are_ignored_for_p0_match_reward() -> None:
    components = reward_v2.parse_reward_components_v2(
        _msg(
            step=4,
            events=[
                _success_event(3, actor="p0"),
                _false_event(3, actor="p0"),
                _success_event(4, actor="p1"),
                _false_event(4, actor="p1"),
            ],
        ),
        action_v2=_match_action(),
    )
    if components.successful_match_reward != 0.0 or components.false_match_penalty != 0.0:
        raise AssertionError(f"old/bot event affected p0 reward: {components}")
    if components.total != 0.0:
        raise AssertionError(f"old/bot event changed p0 total: {components}")


def test_successful_match_is_not_win_gated() -> None:
    components = reward_v2.parse_reward_components_v2(
        _msg(step=1, events=[_success_event(1)]),
        action_v2=_match_action(),
    )
    if components.total != reward_v2.SUCCESSFUL_MATCH_REWARD:
        raise AssertionError(f"successful match did not pay immediately: {components}")
    if components.paid_positive_bonus != 0.0:
        raise AssertionError(f"successful match should not be paid later: {components}")


def test_successful_match_in_lost_episode_pays_immediately() -> None:
    transitions = [
        _parsed_transition(
            _msg(step=1, events=[_success_event(1)]),
            action_v2=_match_action(),
            step_index=0,
        ),
        _parsed_transition(
            _msg(done=True, info={"won": False, "rank": 2}),
            action_v2={"action_type": "pass_tick"},
            step_index=1,
        ),
    ]
    finalized = rollout_v2.finalize_episode_rewards_v2(transitions)
    if finalized[-1].reward_components["paid_positive_bonus"] != 0.0:
        raise AssertionError(f"lost episode paid win-gated positives: {finalized[-1]}")
    if abs(_episode_total(finalized) - reward_v2.SUCCESSFUL_MATCH_REWARD) > 1e-12:
        raise AssertionError(f"lost successful match should remain paid: {finalized}")


def test_false_match_in_won_episode_penalizes_immediately() -> None:
    transitions = [
        _parsed_transition(
            _msg(step=1, events=[_false_event(1)]),
            action_v2=_match_action(),
            step_index=0,
        ),
        _parsed_transition(
            _msg(done=True, info={"won": True, "rank": 1}),
            action_v2={"action_type": "pass_tick"},
            step_index=1,
        ),
    ]
    finalized = rollout_v2.finalize_episode_rewards_v2(transitions)
    expected = reward_v2.WIN_REWARD + reward_v2.FALSE_MATCH_PENALTY_REWARD
    if abs(_episode_total(finalized) - expected) > 1e-12:
        raise AssertionError(f"winning false-match penalty wrong: {finalized}")


def test_no_double_count_successful_match_at_terminal() -> None:
    terminal = _parsed_transition(
        _msg(step=1, done=True, info={"won": True, "rank": 1}, events=[_success_event(1)]),
        action_v2=_match_action(),
        step_index=0,
    )
    finalized = rollout_v2.finalize_episode_rewards_v2([terminal])
    expected = reward_v2.WIN_REWARD + reward_v2.SUCCESSFUL_MATCH_REWARD
    if abs(finalized[0].reward - expected) > 1e-12:
        raise AssertionError(f"terminal successful match double-counted/dropped: {finalized}")
    if finalized[0].reward_components["paid_positive_bonus"] != 0.0:
        raise AssertionError(f"terminal match was paid as positive potential: {finalized}")


def test_no_double_count_false_match_at_terminal() -> None:
    terminal = _parsed_transition(
        _msg(step=1, done=True, info={"won": False, "rank": 6}, events=[_false_event(1)]),
        action_v2=_match_action(),
        step_index=0,
    )
    finalized = rollout_v2.finalize_episode_rewards_v2([terminal])
    expected = reward_v2.FALSE_MATCH_PENALTY_REWARD
    if abs(finalized[0].reward - expected) > 1e-12:
        raise AssertionError(f"terminal false match double-counted/dropped: {finalized}")


def test_win_without_successful_match_gives_win_reward() -> None:
    components = reward_v2.parse_reward_components_v2(
        _msg(done=True, info={"won": True, "rank": 1})
    )
    if components.total != reward_v2.WIN_REWARD:
        raise AssertionError(f"win without shaping wrong: {components}")


def test_loss_without_penalty_gives_zero_terminal_reward() -> None:
    components = reward_v2.parse_reward_components_v2(
        _msg(done=True, principal=-1.0, info={"won": False, "rank": 6})
    )
    if components.total != 0.0:
        raise AssertionError(f"loss should be zero terminal reward: {components}")


def test_loss_with_penalties_can_finish_negative() -> None:
    transitions = [
        _parsed_transition(
            _msg(step=1, events=[_false_event(1)]),
            action_v2=_match_action(),
            step_index=0,
        ),
        _parsed_transition(
            _msg(done=True, info={"won": False, "rank": 6}),
            action_v2={"action_type": "pass_tick"},
            step_index=1,
        ),
    ]
    finalized = rollout_v2.finalize_episode_rewards_v2(transitions)
    if abs(_episode_total(finalized) - reward_v2.FALSE_MATCH_PENALTY_REWARD) > 1e-12:
        raise AssertionError(f"loss with penalty should be negative: {finalized}")


def test_win_with_penalty_can_be_below_win_reward() -> None:
    transitions = [
        _parsed_transition(
            _msg(step=1, events=[_false_event(1)]),
            action_v2=_match_action(),
            step_index=0,
        ),
        _parsed_transition(
            _msg(done=True, info={"won": True, "rank": 1}),
            action_v2={"action_type": "pass_tick"},
            step_index=1,
        ),
    ]
    finalized = rollout_v2.finalize_episode_rewards_v2(transitions)
    expected = reward_v2.WIN_REWARD + reward_v2.FALSE_MATCH_PENALTY_REWARD
    if abs(_episode_total(finalized) - expected) > 1e-12:
        raise AssertionError(f"win penalty was double-counted or dropped: {finalized}")


def test_destab_bonus_pays_only_on_win() -> None:
    transitions = [
        _parsed_transition(_msg(step=1, destab=2.0), action_v2={"action_type": "pass_tick"}),
        _parsed_transition(
            _msg(done=True, info={"won": True, "rank": 1}),
            action_v2={"action_type": "pass_tick"},
            step_index=1,
        ),
    ]
    finalized = rollout_v2.finalize_episode_rewards_v2(transitions)
    expected_bonus = reward_v2.DESTAB_CAP * reward_v2.DESTAB_SCALE
    if abs(finalized[-1].reward_components["paid_positive_bonus"] - expected_bonus) > 1e-12:
        raise AssertionError(f"destab bonus did not pay on win: {finalized[-1]}")


def test_failed_dutch_pays_no_win_gated_bonus_and_penalizes_terminal() -> None:
    transitions = [
        _parsed_transition(
            _msg(done=True, principal=-1.0, info={"won": False, "rank": 6, "called_dutch": True}),
            action_v2={"action_type": "call_dutch"},
            step_index=0,
        ),
    ]
    finalized = rollout_v2.finalize_episode_rewards_v2(transitions)
    terminal = finalized[-1]
    if terminal.reward_components["paid_positive_bonus"] != 0.0:
        raise AssertionError(f"failed Dutch paid positives: {terminal}")
    if terminal.reward_components["terminal_failed_dutch_penalty"] != reward_v2.FAILED_DUTCH_PENALTY_REWARD:
        raise AssertionError(f"failed Dutch penalty missing: {terminal}")
    if terminal.reward != reward_v2.FAILED_DUTCH_PENALTY_REWARD:
        raise AssertionError(f"failed Dutch terminal total wrong: {terminal}")


def test_failed_dutch_is_worse_than_normal_loss() -> None:
    normal = reward_v2.parse_reward_components_v2(
        _msg(done=True, info={"won": False, "rank": 5, "called_dutch": False}),
        action_v2={"action_type": "pass_tick"},
    )
    failed = reward_v2.parse_reward_components_v2(
        _msg(done=True, info={"won": False, "rank": 6, "called_dutch": True}),
        action_v2={"action_type": "call_dutch"},
    )
    if normal.total != 0.0:
        raise AssertionError(f"normal loss should be zero terminal: {normal}")
    if failed.total != reward_v2.FAILED_DUTCH_PENALTY_REWARD:
        raise AssertionError(f"failed Dutch penalty wrong: {failed}")
    if failed.total >= normal.total:
        raise AssertionError(f"failed Dutch should be worse than normal loss: {failed}")


def test_failed_dutch_is_worse_than_isolated_false_match() -> None:
    failed = reward_v2.parse_reward_components_v2(
        _msg(done=True, info={"won": False, "rank": 6, "called_dutch": True}),
        action_v2={"action_type": "call_dutch"},
    )
    false_match = reward_v2.parse_reward_components_v2(
        _msg(step=1, events=[_false_event(1)]),
        action_v2=_match_action(),
    )
    if failed.total >= false_match.total:
        raise AssertionError(
            f"failed Dutch should be worse than isolated false match: {failed}, {false_match}"
        )


def test_successful_dutch_win_remains_positive() -> None:
    components = reward_v2.parse_reward_components_v2(
        _msg(done=True, info={"won": True, "rank": 1, "called_dutch": True}),
        action_v2={"action_type": "call_dutch"},
    )
    if components.terminal_failed_dutch_penalty != 0.0:
        raise AssertionError(f"successful Dutch was penalized: {components}")
    if components.total != reward_v2.WIN_REWARD:
        raise AssertionError(f"successful Dutch win should stay positive: {components}")


def test_opponent_failed_dutch_does_not_penalize_p0() -> None:
    components = reward_v2.parse_reward_components_v2(
        _msg(
            done=True,
            info={
                "won": False,
                "rank": 2,
                "called_dutch": False,
                "dutch_caller": "p1",
            },
        ),
        action_v2={"action_type": "pass_tick"},
    )
    if components.terminal_failed_dutch_penalty != 0.0 or components.total != 0.0:
        raise AssertionError(f"opponent failed Dutch penalized p0: {components}")


def test_terminal_lost_call_dutch_detected_when_called_flag_missing() -> None:
    components = reward_v2.parse_reward_components_v2(
        _msg(done=True, info={"won": False, "rank": 6}),
        action_v2={"action_type": "call_dutch"},
    )
    if components.terminal_failed_dutch_penalty != reward_v2.FAILED_DUTCH_PENALTY_REWARD:
        raise AssertionError(f"ambiguous terminal call_dutch was not penalized: {components}")


def test_failed_dutch_penalty_not_double_counted() -> None:
    components = reward_v2.parse_reward_components_v2(
        _msg(done=True, info={"won": False, "rank": 6, "called_dutch": True}),
        action_v2={"action_type": "call_dutch"},
    )
    if components.total != reward_v2.FAILED_DUTCH_PENALTY_REWARD:
        raise AssertionError(f"failed Dutch was double-counted: {components}")


def test_missing_components_fallback_is_explicit_and_safe() -> None:
    components = reward_v2.parse_reward_components_v2({"reward": -0.2})
    if components.principal != -0.2 or components.total != 0.0:
        raise AssertionError(f"legacy fallback wrong: {components}")


def test_transition_reward_stores_direct_match_reward_total() -> None:
    class Runner:
        def __init__(self) -> None:
            self.step_index = 0

        def reset(
            self,
            seed: int,
            episode_id: str | None = None,
            extra_options: dict[str, Any] | None = None,
        ) -> dict[str, Any]:
            del seed, episode_id, extra_options
            self.step_index = 0
            return _obs(0)

        def step(self, action_msg: dict[str, Any]) -> dict[str, Any]:
            del action_msg
            self.step_index += 1
            if self.step_index == 1:
                return {
                    **_obs(1),
                    "step": 1,
                    "rewards": {"principal": 0.0, "win_bonus": 0.0, "destab": 0.0},
                    "recent_events": [_success_event(1)],
                }
            return {
                **_obs(2, done=True),
                "step": 2,
                "done": True,
                "rewards": {"principal": 1.0, "win_bonus": 0.0, "destab": 0.0},
                "info": {"won": True, "rank": 1},
            }

    transitions = rollout_v2.record_episode_v2(
        Runner(),
        seed=0,
        policy=lambda obs, rng: obs["legal_action_v2"]["actions"][0],
        max_steps=2,
    )
    if transitions[0].reward != reward_v2.SUCCESSFUL_MATCH_REWARD:
        raise AssertionError(f"TransitionV2.reward missed direct match: {transitions[0]}")
    if transitions[-1].reward != reward_v2.WIN_REWARD:
        raise AssertionError(f"terminal reward wrong: {transitions[-1]}")
    if transitions[0].reward_components["total"] != transitions[0].reward:
        raise AssertionError("reward components total diverged from transition reward")


def test_dataset_jsonl_roundtrip_preserves_reward_components() -> None:
    components = {
        "principal": 0.0,
        "successful_match_reward": 0.5,
        "immediate_reward": 0.5,
        "false_match_penalty": 0.0,
        "immediate_penalty": 0.0,
        "total": 0.5,
    }
    transition = _transition(reward=0.5, components=components)
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "transitions.jsonl"
        rollout_v2.save_transitions_jsonl([transition], path)
        import dataset_v2

        loaded = dataset_v2.load_transitions_jsonl(path)[0]
    if loaded.reward != 0.5:
        raise AssertionError(f"reward_total did not roundtrip: {loaded.reward}")
    if loaded.reward_components != transition.reward_components:
        raise AssertionError(f"reward_components did not roundtrip: {loaded.reward_components}")


def test_dataset_loader_preserves_reward_total() -> None:
    transition = _transition(
        reward=1.5,
        components={
            "terminal_win_reward": 1.0,
            "successful_match_reward": 0.5,
            "immediate_reward": 0.5,
            "total": 1.5,
        },
        done=True,
        info={"won": True, "rank": 1},
    )
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "transitions.jsonl"
        rollout_v2.save_transitions_jsonl([transition], path)
        import dataset_v2

        loaded = dataset_v2.load_transitions_jsonl(path)[0]
    if loaded.reward != 1.5 or loaded.reward_components["total"] != 1.5:
        raise AssertionError(f"dataset loader changed reward total: {loaded}")


def test_evaluate_reports_reward_total_and_components() -> None:
    record = type(
        "Record",
        (),
        {
            "transitions": [
                _transition(
                    reward=-0.7,
                    components={
                        "principal": 0.0,
                        "false_match_penalty": -0.7,
                        "immediate_penalty": -0.7,
                        "total": -0.7,
                    },
                ),
                _transition(
                    reward=-1.0,
                    components={
                        "terminal_failed_dutch_penalty": -1.0,
                        "total": -1.0,
                    },
                    done=True,
                    info={"won": False, "rank": 6, "called_dutch": True},
                    step_index=2,
                ),
                _transition(
                    reward=0.5,
                    components={
                        "principal": 0.0,
                        "successful_match_reward": 0.5,
                        "immediate_reward": 0.5,
                        "total": 0.5,
                    },
                    step_index=3,
                ),
            ],
            "completed": True,
            "truncated_by_max_steps": False,
        },
    )()
    metrics = evaluate_r2d2_v2.metrics_from_records([record])
    if abs(metrics.total_reward + 1.2) > 1e-12 or abs(metrics.average_reward + 1.2) > 1e-12:
        raise AssertionError(f"reward total metrics wrong: {metrics}")
    if metrics.total_reward_components.get("false_match_penalty") != -0.7:
        raise AssertionError(f"false component metrics missing: {metrics.total_reward_components}")
    if metrics.total_reward_components.get("successful_match_reward") != 0.5:
        raise AssertionError(f"success component metrics missing: {metrics.total_reward_components}")
    if metrics.total_reward_components.get("terminal_failed_dutch_penalty") != -1.0:
        raise AssertionError(f"Dutch component metrics missing: {metrics.total_reward_components}")


def test_action_trace_can_write_direct_reward_components_without_leak() -> None:
    record = {
        "reward": -1.0,
        "reward_components": {
            "terminal_failed_dutch_penalty": -1.0,
            "total": -1.0,
        },
    }
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "trace.jsonl"
        with action_trace_v2.ActionTraceWriterV2(path, gzip_enabled=False) as writer:
            writer.write(record)
        loaded = json.loads(path.read_text(encoding="utf-8").strip())
    if loaded["reward_components"]["terminal_failed_dutch_penalty"] != -1.0:
        raise AssertionError(f"trace lost failed Dutch component: {loaded}")


def test_import_has_no_collection_or_training_side_effect() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        before = set(Path(tmp).iterdir())
        _ = reward_v2.FALSE_MATCH_PENALTY_REWARD
        reward_v2.scalarize_reward_v2(immediate_penalty=0.0)
        if set(Path(tmp).iterdir()) != before:
            raise AssertionError("reward_v2 import/helper created files")


def test_reward_components_have_no_forbidden_trace_keys() -> None:
    forbidden = encoding_v2.FORBIDDEN_POLICY_KEYS
    components = reward_v2.parse_reward_components_v2(
        _msg(step=1, events=[_false_event(1)]),
        action_v2=_match_action(),
    ).to_dict()
    leaked = forbidden.intersection(components.keys())
    if leaked:
        raise AssertionError(f"reward components leaked forbidden keys: {sorted(leaked)}")


def main() -> int:
    tests = [
        test_parse_reward_components_from_runner_json,
        test_scalarize_principal_only_stays_zero,
        test_scalarize_immediate_match_aliases_work,
        test_scalarize_includes_win_bonus_only_on_win,
        test_destab_remains_win_gated_positive_potential,
        test_p0_successful_match_gives_immediate_reward,
        test_p0_false_match_gives_immediate_penalty,
        test_false_match_costs_more_than_successful_match_rewards,
        test_opponent_successful_match_is_public_but_gives_no_p0_reward,
        test_opponent_false_match_is_public_but_gives_no_p0_penalty,
        test_old_or_bot_events_are_ignored_for_p0_match_reward,
        test_successful_match_is_not_win_gated,
        test_successful_match_in_lost_episode_pays_immediately,
        test_false_match_in_won_episode_penalizes_immediately,
        test_no_double_count_successful_match_at_terminal,
        test_no_double_count_false_match_at_terminal,
        test_win_without_successful_match_gives_win_reward,
        test_loss_without_penalty_gives_zero_terminal_reward,
        test_loss_with_penalties_can_finish_negative,
        test_win_with_penalty_can_be_below_win_reward,
        test_destab_bonus_pays_only_on_win,
        test_failed_dutch_pays_no_win_gated_bonus_and_penalizes_terminal,
        test_failed_dutch_is_worse_than_normal_loss,
        test_failed_dutch_is_worse_than_isolated_false_match,
        test_successful_dutch_win_remains_positive,
        test_opponent_failed_dutch_does_not_penalize_p0,
        test_terminal_lost_call_dutch_detected_when_called_flag_missing,
        test_failed_dutch_penalty_not_double_counted,
        test_missing_components_fallback_is_explicit_and_safe,
        test_transition_reward_stores_direct_match_reward_total,
        test_dataset_jsonl_roundtrip_preserves_reward_components,
        test_dataset_loader_preserves_reward_total,
        test_evaluate_reports_reward_total_and_components,
        test_action_trace_can_write_direct_reward_components_without_leak,
        test_import_has_no_collection_or_training_side_effect,
        test_reward_components_have_no_forbidden_trace_keys,
    ]
    print("=== test_reward_v2 ===")
    for test in tests:
        test()
        print(f"  [OK] {test.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
