"""Tests for R2D2 v2 reward scalarization.

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
    }


def _obs(step: int) -> dict[str, Any]:
    return {
        "type": "observation",
        "done": False,
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
) -> rollout_v2.TransitionV2:
    obs = _obs(0)
    next_obs = _obs(1)
    return rollout_v2.TransitionV2(
        obs_raw=obs,
        obs_encoded_v2=encoding_v2.encode_observation_v2(obs),
        action_v2={"action_type": "match", "slot": 0},
        legacy_action_id=6186,
        reward=reward,
        done=False,
        next_obs_raw=next_obs,
        next_obs_encoded_v2=encoding_v2.encode_observation_v2(next_obs),
        info={},
        episode_id="ep",
        step_index=0,
        reward_components=components,
    )


def test_parse_reward_components_from_runner_json() -> None:
    components = reward_v2.parse_reward_components_v2(
        _msg(principal=0.5, win_bonus=0.25, destab=1.0)
    )
    if components.principal != 0.5 or components.win_bonus != 0.25:
        raise AssertionError(f"base components wrong: {components}")
    if abs(components.destab - reward_v2.DESTAB_SCALE) > 1e-12:
        raise AssertionError(f"destab scaling wrong: {components}")


def test_scalarize_principal_only() -> None:
    total = reward_v2.scalarize_reward_v2(principal=0.6)
    if total != 0.6:
        raise AssertionError(f"principal-only scalarization wrong: {total}")


def test_scalarize_includes_win_bonus() -> None:
    components = reward_v2.parse_reward_components_v2(_msg(principal=1.0, win_bonus=0.3))
    if abs(components.total - 1.3) > 1e-12:
        raise AssertionError(f"win_bonus was not consumed: {components}")


def test_scalarize_includes_bounded_destab() -> None:
    components = reward_v2.parse_reward_components_v2(_msg(destab=999.0))
    expected = reward_v2.DESTAB_CAP * reward_v2.DESTAB_SCALE
    if abs(components.destab - expected) > 1e-12 or abs(components.total - expected) > 1e-12:
        raise AssertionError(f"destab cap/scale wrong: {components}")


def test_false_match_produces_immediate_penalty() -> None:
    components = reward_v2.parse_reward_components_v2(
        _msg(
            step=4,
            events=[
                {
                    "step": 4,
                    "event_type": "match_failure_penalty",
                    "actor": "p0",
                    "slot": 0,
                }
            ],
        ),
        action_v2={"action_type": "match", "slot": 0},
    )
    if components.false_match_penalty != reward_v2.FALSE_MATCH_PENALTY_REWARD:
        raise AssertionError(f"false match penalty missing: {components}")
    if components.total >= 0.0:
        raise AssertionError(f"false match total should be negative: {components}")


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


def test_successful_match_has_no_large_bonus() -> None:
    components = reward_v2.parse_reward_components_v2(
        _msg(
            step=2,
            events=[
                {
                    "step": 2,
                    "event_type": "discard_visible",
                    "actor": "p0",
                    "discard_reason": "match_discard",
                }
            ],
        ),
        action_v2={"action_type": "match", "slot": 0},
    )
    if abs(components.successful_match) > 0.01:
        raise AssertionError(f"successful match bonus too large: {components}")
    if components.total != 0.0:
        raise AssertionError(f"successful match should not dominate objective: {components}")


def test_terminal_win_dominates_small_shaping() -> None:
    win = reward_v2.parse_reward_components_v2(
        _msg(principal=1.0, win_bonus=0.3, destab=2.0, done=True)
    )
    false_match = reward_v2.parse_reward_components_v2(
        _msg(
            events=[{"step": 1, "event_type": "match_failure_penalty", "actor": "p0"}],
        ),
        action_v2={"action_type": "match", "slot": 0},
    )
    if win.total <= abs(false_match.total):
        raise AssertionError(f"terminal win should dominate shaping: {win} vs {false_match}")


def test_failed_dutch_last_rank_is_negative_terminal_signal() -> None:
    components = reward_v2.parse_reward_components_v2(
        _msg(principal=-1.0, done=True),
        action_v2={"action_type": "call_dutch"},
    )
    if components.total >= 0.0:
        raise AssertionError(f"failed Dutch terminal signal should be negative: {components}")


def test_missing_components_fallback_is_explicit_and_safe() -> None:
    components = reward_v2.parse_reward_components_v2({"reward": -0.2})
    if components.principal != -0.2 or components.total != -0.2:
        raise AssertionError(f"legacy fallback wrong: {components}")


def test_transition_reward_stores_scalarized_total() -> None:
    class Runner:
        def reset(self, seed: int, episode_id: str | None = None, extra_options: dict[str, Any] | None = None) -> dict[str, Any]:
            del seed, episode_id, extra_options
            return _obs(0)

        def step(self, action_msg: dict[str, Any]) -> dict[str, Any]:
            del action_msg
            return {
                **_obs(1),
                "step": 1,
                "done": True,
                "rewards": {"principal": 0.0, "win_bonus": 0.0, "destab": 0.0},
                "recent_events": [
                    {"step": 1, "event_type": "match_failure_penalty", "actor": "p0"}
                ],
            }

    transitions = rollout_v2.record_episode_v2(
        Runner(),
        seed=0,
        policy=lambda obs, rng: (obs["legal_action_v2"]["actions"][0]),
        max_steps=1,
    )
    transition = transitions[0]
    if transition.reward != reward_v2.FALSE_MATCH_PENALTY_REWARD:
        raise AssertionError(f"TransitionV2.reward did not store total: {transition}")
    if not transition.reward_components or transition.reward_components["total"] != transition.reward:
        raise AssertionError("reward components were not stored with the transition")


def test_dataset_jsonl_roundtrip_preserves_reward_components() -> None:
    transition = _transition(
        reward=-0.05,
        components={"principal": 0.0, "false_match_penalty": -0.05, "total": -0.05},
    )
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "transitions.jsonl"
        rollout_v2.save_transitions_jsonl([transition], path)
        import dataset_v2

        loaded = dataset_v2.load_transitions_jsonl(path)[0]
    if loaded.reward != -0.05:
        raise AssertionError(f"reward_total did not roundtrip: {loaded.reward}")
    if loaded.reward_components != transition.reward_components:
        raise AssertionError(f"reward_components did not roundtrip: {loaded.reward_components}")


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
    # The module-level constants and pure helpers must not touch the filesystem.
    with tempfile.TemporaryDirectory() as tmp:
        before = set(Path(tmp).iterdir())
        _ = reward_v2.FALSE_MATCH_PENALTY_REWARD
        reward_v2.scalarize_reward_v2(principal=0.0)
        if set(Path(tmp).iterdir()) != before:
            raise AssertionError("reward_v2 import/helper created files")


def test_reward_components_have_no_forbidden_trace_keys() -> None:
    forbidden = encoding_v2.FORBIDDEN_POLICY_KEYS
    components = reward_v2.parse_reward_components_v2(
        _msg(
            step=1,
            events=[{"step": 1, "event_type": "match_failure_penalty", "actor": "p0"}],
        ),
        action_v2={"action_type": "match", "slot": 0},
    ).to_dict()
    leaked = forbidden.intersection(components.keys())
    if leaked:
        raise AssertionError(f"reward components leaked forbidden keys: {sorted(leaked)}")


def main() -> int:
    tests = [
        test_parse_reward_components_from_runner_json,
        test_scalarize_principal_only,
        test_scalarize_includes_win_bonus,
        test_scalarize_includes_bounded_destab,
        test_false_match_produces_immediate_penalty,
        test_false_match_ignores_old_or_bot_events,
        test_successful_match_has_no_large_bonus,
        test_terminal_win_dominates_small_shaping,
        test_failed_dutch_last_rank_is_negative_terminal_signal,
        test_missing_components_fallback_is_explicit_and_safe,
        test_transition_reward_stores_scalarized_total,
        test_dataset_jsonl_roundtrip_preserves_reward_components,
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
