"""Tests for R2D2 v2 win-gated reward scalarization.

Run from rl/:
    uv run python test_reward_v2.py
"""

from __future__ import annotations

import tempfile
from pathlib import Path
from typing import Any

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


def _success_event(step: int = 1) -> dict[str, Any]:
    return {
        "step": step,
        "event_type": "discard_visible",
        "actor": "p0",
        "discard_reason": "match_discard",
    }


def _false_event(step: int = 1) -> dict[str, Any]:
    return {
        "step": step,
        "event_type": "match_failure_penalty",
        "actor": "p0",
    }


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
                    "action_v2": {"action_type": "match", "slot": 0},
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
        action_v2={"action_type": "match", "slot": 0},
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
        raise AssertionError(f"positive components should not pay immediately: {components}")


def test_scalarize_immediate_penalty_only() -> None:
    total = reward_v2.scalarize_reward_v2(
        immediate_penalty=reward_v2.FALSE_MATCH_PENALTY_REWARD
    )
    if total != reward_v2.FALSE_MATCH_PENALTY_REWARD:
        raise AssertionError(f"immediate penalty scalarization wrong: {total}")


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


def test_destab_is_win_gated_positive_potential() -> None:
    components = reward_v2.parse_reward_components_v2(_msg(destab=999.0))
    expected = reward_v2.DESTAB_CAP * reward_v2.DESTAB_SCALE
    if abs(components.destab_bonus_potential - expected) > 1e-12:
        raise AssertionError(f"destab cap/scale wrong: {components}")
    if components.total != 0.0:
        raise AssertionError(f"destab should not pay immediately: {components}")


def test_false_match_penalty_immediate_on_loss() -> None:
    components = reward_v2.parse_reward_components_v2(
        _msg(step=4, events=[_false_event(4)]),
        action_v2={"action_type": "match", "slot": 0},
    )
    if components.false_match_penalty != reward_v2.FALSE_MATCH_PENALTY_REWARD:
        raise AssertionError(f"false match penalty missing: {components}")
    if components.total != reward_v2.FALSE_MATCH_PENALTY_REWARD:
        raise AssertionError(f"false match total should be immediate: {components}")


def test_false_match_penalty_immediate_on_win() -> None:
    components = reward_v2.parse_reward_components_v2(
        _msg(
            step=4,
            done=True,
            info={"won": True, "rank": 1},
            events=[_false_event(4)],
        ),
        action_v2={"action_type": "match", "slot": 0},
    )
    expected = reward_v2.WIN_REWARD + reward_v2.FALSE_MATCH_PENALTY_REWARD
    if abs(components.total - expected) > 1e-12:
        raise AssertionError(f"false match penalty not kept on win: {components}")


def test_false_match_ignores_old_or_bot_events() -> None:
    components = reward_v2.parse_reward_components_v2(
        _msg(
            step=4,
            events=[
                {"step": 3, "event_type": "match_failure_penalty", "actor": "p0"},
                {"step": 4, "event_type": "match_failure_penalty", "actor": "p1"},
            ],
        ),
        action_v2={"action_type": "match", "slot": 0},
    )
    if components.false_match_penalty != 0.0 or components.total != 0.0:
        raise AssertionError(f"old/bot false match event was penalized: {components}")


def test_successful_match_lost_episode_pays_no_bonus() -> None:
    transitions = [
        _parsed_transition(
            _msg(step=1, events=[_success_event(1)]),
            action_v2={"action_type": "match", "slot": 0},
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
        raise AssertionError(f"lost episode paid match bonus: {finalized[-1]}")
    if _episode_total(finalized) != 0.0:
        raise AssertionError(f"lost episode should pay no positives: {finalized}")


def test_successful_match_won_episode_pays_terminal_bonus() -> None:
    transitions = [
        _parsed_transition(
            _msg(step=1, events=[_success_event(1)]),
            action_v2={"action_type": "match", "slot": 0},
            step_index=0,
        ),
        _parsed_transition(
            _msg(done=True, info={"won": True, "rank": 1}),
            action_v2={"action_type": "pass_tick"},
            step_index=1,
        ),
    ]
    finalized = rollout_v2.finalize_episode_rewards_v2(transitions)
    expected = reward_v2.WIN_REWARD + reward_v2.SUCCESSFUL_MATCH_BONUS_POTENTIAL
    if abs(finalized[-1].reward - expected) > 1e-12:
        raise AssertionError(f"winning match bonus not paid at terminal: {finalized[-1]}")
    if finalized[0].reward != 0.0:
        raise AssertionError("successful match bonus paid before terminal")


def test_multiple_successful_matches_accumulate_on_win() -> None:
    transitions = [
        _parsed_transition(
            _msg(step=1, events=[_success_event(1)]),
            action_v2={"action_type": "match", "slot": 0},
            step_index=0,
        ),
        _parsed_transition(
            _msg(step=2, events=[_success_event(2)]),
            action_v2={"action_type": "match", "slot": 0},
            step_index=1,
        ),
        _parsed_transition(
            _msg(done=True, info={"won": True, "rank": 1}),
            action_v2={"action_type": "pass_tick"},
            step_index=2,
        ),
    ]
    finalized = rollout_v2.finalize_episode_rewards_v2(transitions)
    expected_bonus = 2.0 * reward_v2.SUCCESSFUL_MATCH_BONUS_POTENTIAL
    if abs(finalized[-1].reward_components["paid_positive_bonus"] - expected_bonus) > 1e-12:
        raise AssertionError(f"match bonuses did not accumulate: {finalized[-1]}")


def test_multiple_successful_matches_do_not_pay_on_loss() -> None:
    transitions = [
        _parsed_transition(
            _msg(step=1, events=[_success_event(1)]),
            action_v2={"action_type": "match", "slot": 0},
            step_index=0,
        ),
        _parsed_transition(
            _msg(step=2, events=[_success_event(2)]),
            action_v2={"action_type": "match", "slot": 0},
            step_index=1,
        ),
        _parsed_transition(
            _msg(done=True, info={"won": False, "rank": 4}),
            action_v2={"action_type": "pass_tick"},
            step_index=2,
        ),
    ]
    finalized = rollout_v2.finalize_episode_rewards_v2(transitions)
    if _episode_total(finalized) != 0.0:
        raise AssertionError(f"lost match farm should not be rewarded: {finalized}")


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
            action_v2={"action_type": "match", "slot": 0},
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
            action_v2={"action_type": "match", "slot": 0},
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


def test_failed_dutch_pays_no_positive_bonus_and_penalizes_terminal() -> None:
    transitions = [
        _parsed_transition(
            _msg(step=1, events=[_success_event(1)]),
            action_v2={"action_type": "match", "slot": 0},
            step_index=0,
        ),
        _parsed_transition(
            _msg(done=True, principal=-1.0, info={"won": False, "rank": 6, "called_dutch": True}),
            action_v2={"action_type": "call_dutch"},
            step_index=1,
        ),
    ]
    finalized = rollout_v2.finalize_episode_rewards_v2(transitions)
    terminal = finalized[-1]
    if terminal.reward_components["paid_positive_bonus"] != 0.0:
        raise AssertionError(f"failed Dutch paid positives: {terminal}")
    if terminal.reward_components["terminal_failed_dutch_penalty"] != reward_v2.FAILED_DUTCH_PENALTY_REWARD:
        raise AssertionError(f"failed Dutch penalty missing: {terminal}")


def test_no_double_count_of_penalties_at_terminal() -> None:
    transitions = [
        _parsed_transition(
            _msg(step=1, events=[_false_event(1)]),
            action_v2={"action_type": "match", "slot": 0},
            step_index=0,
        ),
        _parsed_transition(
            _msg(done=True, info={"won": False, "rank": 6}),
            action_v2={"action_type": "pass_tick"},
            step_index=1,
        ),
    ]
    finalized = rollout_v2.finalize_episode_rewards_v2(transitions)
    if finalized[-1].reward != 0.0:
        raise AssertionError(f"terminal double-counted penalty: {finalized[-1]}")
    if _episode_total(finalized) != reward_v2.FALSE_MATCH_PENALTY_REWARD:
        raise AssertionError(f"episode penalty total wrong: {finalized}")


def test_missing_components_fallback_is_explicit_and_safe() -> None:
    components = reward_v2.parse_reward_components_v2({"reward": -0.2})
    if components.principal != -0.2 or components.total != 0.0:
        raise AssertionError(f"legacy fallback wrong: {components}")


def test_transition_reward_stores_finalized_reward_total() -> None:
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
        policy=lambda obs, rng: (obs["legal_action_v2"]["actions"][0]),
        max_steps=2,
    )
    terminal = transitions[-1]
    expected = reward_v2.WIN_REWARD + reward_v2.SUCCESSFUL_MATCH_BONUS_POTENTIAL
    if abs(terminal.reward - expected) > 1e-12:
        raise AssertionError(f"TransitionV2.reward did not store finalized total: {terminal}")
    if terminal.reward_components["total"] != terminal.reward:
        raise AssertionError("reward components were not finalized with the transition")


def test_dataset_jsonl_roundtrip_preserves_reward_components() -> None:
    components = {
        "principal": 0.0,
        "false_match_penalty": -0.05,
        "immediate_penalty": -0.05,
        "total": -0.05,
    }
    transition = _transition(reward=-0.05, components=components)
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "transitions.jsonl"
        rollout_v2.save_transitions_jsonl([transition], path)
        import dataset_v2

        loaded = dataset_v2.load_transitions_jsonl(path)[0]
    if loaded.reward != -0.05:
        raise AssertionError(f"reward_total did not roundtrip: {loaded.reward}")
    if loaded.reward_components != transition.reward_components:
        raise AssertionError(f"reward_components did not roundtrip: {loaded.reward_components}")


def test_dataset_loader_preserves_reward_total() -> None:
    transition = _transition(
        reward=1.02,
        components={
            "terminal_win_reward": 1.0,
            "paid_positive_bonus": 0.02,
            "total": 1.02,
        },
        done=True,
        info={"won": True, "rank": 1},
    )
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "transitions.jsonl"
        rollout_v2.save_transitions_jsonl([transition], path)
        import dataset_v2

        loaded = dataset_v2.load_transitions_jsonl(path)[0]
    if loaded.reward != 1.02 or loaded.reward_components["total"] != 1.02:
        raise AssertionError(f"dataset loader changed reward total: {loaded}")


def test_evaluate_reports_reward_total_and_components() -> None:
    record = type(
        "Record",
        (),
        {
            "transitions": [
                _transition(
                    reward=-0.05,
                    components={
                        "principal": 0.0,
                        "false_match_penalty": -0.05,
                        "immediate_penalty": -0.05,
                        "total": -0.05,
                    },
                )
            ],
            "completed": True,
            "truncated_by_max_steps": False,
        },
    )()
    metrics = evaluate_r2d2_v2.metrics_from_records([record])
    if metrics.total_reward != -0.05 or metrics.average_reward != -0.05:
        raise AssertionError(f"reward total metrics wrong: {metrics}")
    if metrics.total_reward_components.get("false_match_penalty") != -0.05:
        raise AssertionError(f"component metrics missing: {metrics.total_reward_components}")


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
        action_v2={"action_type": "match", "slot": 0},
    ).to_dict()
    leaked = forbidden.intersection(components.keys())
    if leaked:
        raise AssertionError(f"reward components leaked forbidden keys: {sorted(leaked)}")


def main() -> int:
    tests = [
        test_parse_reward_components_from_runner_json,
        test_scalarize_immediate_penalty_only,
        test_scalarize_includes_win_bonus_only_on_win,
        test_destab_is_win_gated_positive_potential,
        test_false_match_penalty_immediate_on_loss,
        test_false_match_penalty_immediate_on_win,
        test_false_match_ignores_old_or_bot_events,
        test_successful_match_lost_episode_pays_no_bonus,
        test_successful_match_won_episode_pays_terminal_bonus,
        test_multiple_successful_matches_accumulate_on_win,
        test_multiple_successful_matches_do_not_pay_on_loss,
        test_win_without_successful_match_gives_win_reward,
        test_loss_without_penalty_gives_zero_terminal_reward,
        test_loss_with_penalties_can_finish_negative,
        test_win_with_penalty_can_be_below_win_reward,
        test_failed_dutch_pays_no_positive_bonus_and_penalizes_terminal,
        test_no_double_count_of_penalties_at_terminal,
        test_missing_components_fallback_is_explicit_and_safe,
        test_transition_reward_stores_finalized_reward_total,
        test_dataset_jsonl_roundtrip_preserves_reward_components,
        test_dataset_loader_preserves_reward_total,
        test_evaluate_reports_reward_total_and_components,
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
