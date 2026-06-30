"""Smoke tests for the real-runner v2 rollout collector helpers.

Run from rl/:
    uv run python test_collect_rollouts_v2.py
"""

from __future__ import annotations

from pathlib import Path
import random
import tempfile
from typing import Any

import collect_rollouts_v2
import rollout_v2


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
                            "actions_since_changed": 5,
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
                        "age_actions": 2,
                        "age_turns": 1,
                        "source": "mental_map",
                    }
                ]
            },
            "opponents": [],
        },
        "legal_action_v2": {
            "available_action_types": ["pass_tick", "match"],
            "masks": {"action_type": {"pass_tick": True, "match": True}},
            "actions": [
                {
                    "action_v2": {"action_type": "pass_tick"},
                    "legacy_action_id": 6185,
                    "legacy_kind": "pass_tick",
                },
                {
                    "action_v2": {"action_type": "match", "slot": 0},
                    "legacy_action_id": 6186,
                    "legacy_kind": "match",
                },
            ],
            "legacy_action_ids": {
                "action_type=pass_tick": 6185,
                "action_type=match|slot=0": 6186,
            },
        },
    }


class MockRunner:
    def __init__(self, *, terminal_step: int = 2) -> None:
        self.actions: list[dict[str, Any]] = []
        self.reset_calls: list[dict[str, Any]] = []
        self._step = 0
        self._terminal_step = terminal_step

    def reset(
        self,
        seed: int,
        episode_id: str | None = None,
        extra_options: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        self._step = 0
        self.reset_calls.append(
            {"seed": seed, "episode_id": episode_id, "extra_options": extra_options}
        )
        return _obs(0)

    def step(self, action_msg: dict[str, Any]) -> dict[str, Any]:
        self.actions.append(action_msg)
        self._step += 1
        done = self._step >= self._terminal_step
        return {
            **_obs(self._step, done=done),
            "reward": 1.0 if done else 0.0,
            "rewards": {"principal": 1.0 if done else 0.0},
        }


def test_policy_chooses_only_legal_action_v2() -> None:
    obs = _obs(0)
    legal = {
        repr(entry["action_v2"])
        for entry in obs["legal_action_v2"]["actions"]
    }
    for seed in range(10):
        action = collect_rollouts_v2.choose_legal_action_v2(obs, random.Random(seed))
        if repr(action["action_v2"]) not in legal:
            raise AssertionError(f"policy chose illegal action: {action}")


def test_collector_builds_valid_transitions() -> None:
    runner = MockRunner(terminal_step=2)
    record = collect_rollouts_v2.collect_episode_v2(
        runner,
        seed=10,
        episode_id="ep-test",
        rng=random.Random(0),
        max_steps=5,
    )
    if len(record.transitions) != 2:
        raise AssertionError("collector did not stop on done")
    first = record.transitions[0]
    if first.obs_encoded_v2.public_features.shape[0] == 0:
        raise AssertionError("obs_encoded_v2 is empty")
    if first.action_v2 is None:
        raise AssertionError("action_v2 was not preserved")
    if first.legacy_action_id not in {6185, 6186}:
        raise AssertionError(f"unexpected legacy_action_id: {first.legacy_action_id}")


def test_max_steps_cuts_cleanly() -> None:
    record = collect_rollouts_v2.collect_episode_v2(
        MockRunner(terminal_step=100),
        seed=10,
        episode_id="ep-max",
        rng=random.Random(0),
        max_steps=3,
    )
    if len(record.transitions) != 3:
        raise AssertionError("max_steps did not cap transition count")
    if record.completed:
        raise AssertionError("record should not be completed")
    if not record.truncated_by_max_steps:
        raise AssertionError("record should be marked truncated")


def test_done_cuts_episode() -> None:
    record = collect_rollouts_v2.collect_episode_v2(
        MockRunner(terminal_step=1),
        seed=10,
        episode_id="ep-done",
        rng=random.Random(0),
        max_steps=10,
    )
    if len(record.transitions) != 1 or not record.completed:
        raise AssertionError("done did not stop the episode")


def test_save_jsonl_when_out_provided() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "v2.jsonl"
        records = collect_rollouts_v2.collect_rollouts_v2(
            MockRunner(terminal_step=1),
            episodes=1,
            seed=0,
            max_steps=5,
            out=out,
            save=True,
        )
        if not out.exists():
            raise AssertionError("collector did not write JSONL")
        lines = out.read_text(encoding="utf-8").strip().splitlines()
    if len(lines) != sum(len(record.transitions) for record in records):
        raise AssertionError("JSONL line count mismatch")


def test_no_save_without_out() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "missing.jsonl"
        collect_rollouts_v2.collect_rollouts_v2(
            MockRunner(terminal_step=1),
            episodes=1,
            seed=0,
            max_steps=5,
            out=out,
            save=False,
        )
        if out.exists():
            raise AssertionError("collector wrote JSONL despite save=False")


def test_anti_leak_rejects_forbidden_policy_key() -> None:
    obs = {**_obs(0), "true_score": {"p1": 42}}
    try:
        collect_rollouts_v2.validate_observation_v2(obs)
    except ValueError as exc:
        if "true_score" not in str(exc):
            raise AssertionError(f"unexpected error: {exc}") from exc
    else:
        raise AssertionError("leaky observation was not rejected")


def test_build_sequences_compatible() -> None:
    record = collect_rollouts_v2.collect_episode_v2(
        MockRunner(terminal_step=2),
        seed=10,
        episode_id="ep-seq",
        rng=random.Random(0),
        max_steps=5,
    )
    sequences = rollout_v2.build_sequences(record.transitions, seq_len=2, burn_in=1)
    if len(sequences) != 1:
        raise AssertionError("expected one sequence")
    if sequences[0].done_mask != [False, True]:
        raise AssertionError(f"bad done mask: {sequences[0].done_mask}")


def main() -> int:
    tests = [
        test_policy_chooses_only_legal_action_v2,
        test_collector_builds_valid_transitions,
        test_max_steps_cuts_cleanly,
        test_done_cuts_episode,
        test_save_jsonl_when_out_provided,
        test_no_save_without_out,
        test_anti_leak_rejects_forbidden_policy_key,
        test_build_sequences_compatible,
    ]
    print("=== test_collect_rollouts_v2 ===")
    for test in tests:
        test()
        print(f"  [OK] {test.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
