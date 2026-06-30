"""Smoke tests for AgentInterface v2 JSONL dataset loading and n-step returns.

Run from rl/:
    uv run python test_dataset_v2.py
"""

from __future__ import annotations

from pathlib import Path
import tempfile
from typing import Any

import dataset_v2
import encoding_v2
import rollout_v2


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
            "num_players": 3,
            "deck_size": 30,
            "discard_size": 10,
            "top_discard_value": "7",
            "top_discard_points": 7,
            "dutch_called": False,
            "dutch_caller_is_me": False,
            "hand_size": 3,
            "opponents": [
                {"seat": "p1", "hand_size": 4},
                {"seat": "p2", "hand_size": 2},
            ],
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
            "available_action_types": ["pass_tick"],
            "masks": {"action_type": {"pass_tick": True}},
            "actions": [
                {
                    "action_v2": {"action_type": "pass_tick"},
                    "legacy_action_id": 6185,
                    "legacy_kind": "pass_tick",
                }
            ],
            "legacy_action_ids": {"action_type=pass_tick": 6185},
        },
    }


def _transition(
    episode_id: str,
    step: int,
    *,
    reward: float = 1.0,
    done: bool = False,
) -> rollout_v2.TransitionV2:
    obs = _obs(step)
    next_obs = None if done else _obs(step + 1)
    return rollout_v2.TransitionV2(
        obs_raw=obs,
        obs_encoded_v2=encoding_v2.encode_observation_v2(obs),
        action_v2={"action_type": "pass_tick"},
        legacy_action_id=6185 + step,
        reward=reward,
        done=done,
        next_obs_raw=next_obs,
        next_obs_encoded_v2=(
            None if next_obs is None else encoding_v2.encode_observation_v2(next_obs)
        ),
        info={},
        episode_id=episode_id,
        step_index=step,
    )


def _write_jsonl(transitions: list[rollout_v2.TransitionV2]) -> Path:
    tmp = tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False)
    tmp.close()
    path = Path(tmp.name)
    rollout_v2.save_transitions_jsonl(transitions, path)
    return path


def test_load_minimal_jsonl_reconstructs_transitions() -> None:
    path = _write_jsonl([_transition("ep", 0), _transition("ep", 1, done=True)])
    try:
        transitions = dataset_v2.load_transitions_jsonl(path)
    finally:
        path.unlink(missing_ok=True)
    if len(transitions) != 2:
        raise AssertionError("loader did not read both transitions")
    first = transitions[0]
    if first.action_v2 != {"action_type": "pass_tick"}:
        raise AssertionError("action_v2 was not preserved")
    if first.legacy_action_id != 6185:
        raise AssertionError("legacy_action_id was not preserved")
    if first.episode_id != "ep" or first.step_index != 0:
        raise AssertionError("episode_id/step_index was not preserved")
    if first.obs_encoded_v2.public_features.shape != encoding_v2.shapes_v2()["public_features"]:
        raise AssertionError("obs_raw was not re-encoded")
    if first.next_obs_encoded_v2 is None:
        raise AssertionError("next_obs_raw was not re-encoded")


def test_missing_required_field_errors() -> None:
    with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as f:
        f.write('{"obs_raw": {}}\n')
        path = Path(f.name)
    try:
        try:
            dataset_v2.load_transitions_jsonl(path)
        except ValueError as exc:
            if "missing required fields" not in str(exc):
                raise AssertionError(f"unexpected error: {exc}") from exc
        else:
            raise AssertionError("missing field did not raise")
    finally:
        path.unlink(missing_ok=True)


def test_n_step_one_is_immediate_reward() -> None:
    transitions = [_transition("ep", 0, reward=2.5), _transition("ep", 1, reward=9.0)]
    n_steps = dataset_v2.compute_n_step_returns(transitions, n_step=1, gamma=0.9)
    if n_steps[0].n_step_return != 2.5 or n_steps[0].actual_n != 1:
        raise AssertionError(f"bad one-step return: {n_steps[0]}")


def test_n_step_three_return() -> None:
    transitions = [
        _transition("ep", 0, reward=1.0),
        _transition("ep", 1, reward=2.0),
        _transition("ep", 2, reward=3.0),
    ]
    n_steps = dataset_v2.compute_n_step_returns(transitions, n_step=3, gamma=0.5)
    expected = 1.0 + 0.5 * 2.0 + 0.25 * 3.0
    if abs(n_steps[0].n_step_return - expected) > 1e-9:
        raise AssertionError(f"bad n-step return: {n_steps[0].n_step_return}")
    if n_steps[0].n_step_discount != 0.5**3:
        raise AssertionError("bad n-step discount")


def test_done_cuts_n_step_return() -> None:
    transitions = [
        _transition("ep", 0, reward=1.0),
        _transition("ep", 1, reward=2.0, done=True),
        _transition("ep", 2, reward=100.0),
    ]
    n_steps = dataset_v2.compute_n_step_returns(transitions, n_step=3, gamma=0.5)
    if n_steps[0].n_step_return != 2.0:
        raise AssertionError(f"done did not cut return: {n_steps[0].n_step_return}")
    if not n_steps[0].n_step_done:
        raise AssertionError("n_step_done should be true")
    if n_steps[0].actual_n != 2:
        raise AssertionError("actual_n should stop at done")


def test_n_step_does_not_cross_episodes() -> None:
    transitions = [
        _transition("ep-a", 0, reward=1.0),
        _transition("ep-b", 0, reward=100.0),
    ]
    n_steps = dataset_v2.compute_n_step_returns(transitions, n_step=2, gamma=0.5)
    if n_steps[0].n_step_return != 1.0:
        raise AssertionError("n-step crossed episode boundary")


def test_load_replay_buffer_from_jsonl_and_sample() -> None:
    path = _write_jsonl([_transition("ep", 0), _transition("ep", 1, done=True)])
    try:
        buffer = dataset_v2.load_replay_buffer_from_jsonl(path, n_step=2, gamma=0.9)
    finally:
        path.unlink(missing_ok=True)
    if len(buffer) != 2:
        raise AssertionError("replay buffer did not load transitions")
    batch = buffer.sample_sequences(batch_size=1, seq_len=2, burn_in=1, seed=0)
    if batch.public_features.shape[:2] != (1, 3):
        raise AssertionError("sample_sequences failed after loading")


def test_anti_leak_rejects_forbidden_keys() -> None:
    bad = _transition("ep", 0)
    payload = rollout_v2.transition_to_jsonable(bad)
    for key in [
        "true_score",
        "full_hand",
        "opponent_hand",
        "deck_order",
        "kept_card",
        "penalty_card",
        "swapped_card",
        "debug_eval_labels",
    ]:
        payload["obs_raw"] = {**bad.obs_raw, key: "leak"}
        with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as f:
            import json

            f.write(json.dumps(payload) + "\n")
            path = Path(f.name)
        try:
            try:
                dataset_v2.load_transitions_jsonl(path)
            except ValueError as exc:
                if key not in str(exc):
                    raise AssertionError(f"unexpected error for {key}: {exc}") from exc
            else:
                raise AssertionError(f"leak {key} did not raise")
        finally:
            path.unlink(missing_ok=True)


def main() -> int:
    tests = [
        test_load_minimal_jsonl_reconstructs_transitions,
        test_missing_required_field_errors,
        test_n_step_one_is_immediate_reward,
        test_n_step_three_return,
        test_done_cuts_n_step_return,
        test_n_step_does_not_cross_episodes,
        test_load_replay_buffer_from_jsonl_and_sample,
        test_anti_leak_rejects_forbidden_keys,
    ]
    print("=== test_dataset_v2 ===")
    for test in tests:
        test()
        print(f"  [OK] {test.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
