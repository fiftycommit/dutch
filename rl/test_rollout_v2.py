"""Smoke tests for the AgentInterface v2 rollout recorder.

Run from rl/:
    uv run python test_rollout_v2.py
"""

from __future__ import annotations

from pathlib import Path
import random
import tempfile
from typing import Any

import encoding_v2
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
        "recent_events": [
            {
                "turn_count": step,
                "action_count": step,
                "phase": "reaction",
                "event_type": "discard_visible",
                "actor": "p1",
                "card_visible": True,
                "card_value": "7",
                "card_match_value": "7",
                "card_points": 7,
                "slot": 1,
                "discard_reason": "match_discard",
                "replaced_slot": None,
            }
        ],
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
            "opponents": [
                {
                    "seat": 1,
                    "player_id": "p1",
                    "spied_slots": [
                        {
                            "slot": 2,
                            "known": True,
                            "believed_value": "D",
                            "believed_match_value": "D",
                            "believed_points": 12,
                            "valid": True,
                            "confidence": 1.0,
                            "age_actions": 4,
                            "age_turns": 1,
                            "source": "spy_memory",
                        }
                    ],
                }
            ],
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


class MockRunner:
    def __init__(self) -> None:
        self.actions: list[dict[str, Any]] = []
        self._next = 0
        self._messages = [
            _obs(0),
            {**_obs(1), "reward": 0.0, "rewards": {"principal": 0.0}},
            {**_obs(2), "reward": 1.0, "rewards": {"principal": 1.0}, "done": True},
        ]

    def reset(
        self,
        seed: int,
        episode_id: str | None = None,
        extra_options: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        self._next = 1
        return self._messages[0]

    def step(self, action_msg: dict[str, Any]) -> dict[str, Any]:
        self.actions.append(action_msg)
        msg = self._messages[self._next]
        self._next += 1
        return msg


def _assert_no_forbidden_keys(value: Any) -> None:
    forbidden = encoding_v2.FORBIDDEN_POLICY_KEYS
    found: set[str] = set()

    def visit(child: Any) -> None:
        if isinstance(child, dict):
            for key, sub in child.items():
                if key in forbidden:
                    found.add(str(key))
                visit(sub)
        elif isinstance(child, list):
            for sub in child:
                visit(sub)

    visit(value)
    if found:
        raise AssertionError(f"forbidden keys leaked: {sorted(found)}")


def test_transition_minimal() -> None:
    obs = _obs(0)
    transition = rollout_v2.TransitionV2(
        obs_raw=obs,
        obs_encoded_v2=encoding_v2.encode_observation_v2(obs),
        action_v2={"action_type": "pass_tick"},
        legacy_action_id=6185,
        reward=0.0,
        done=False,
        next_obs_raw=_obs(1),
        next_obs_encoded_v2=encoding_v2.encode_observation_v2(_obs(1)),
        info={},
        episode_id="ep-test",
        step_index=0,
    )
    if transition.action_v2 != {"action_type": "pass_tick"}:
        raise AssertionError("action_v2 was not preserved")
    if transition.legacy_action_id != 6185:
        raise AssertionError("legacy_action_id was not preserved")


def test_record_episode_with_mock_runner() -> None:
    runner = MockRunner()
    transitions = rollout_v2.record_episode_v2(
        runner,
        seed=1,
        episode_id="ep-mock",
        rng=random.Random(1),
    )
    if len(transitions) != 2:
        raise AssertionError(f"expected 2 transitions, got {len(transitions)}")
    if runner.actions != [
        {"action_v2": {"action_type": "pass_tick"}},
        {"action_v2": {"action_type": "pass_tick"}},
    ]:
        raise AssertionError(f"unexpected runner actions: {runner.actions}")
    if not transitions[-1].done:
        raise AssertionError("last transition should be terminal")
    if transitions[-1].next_obs_encoded_v2 is not None:
        raise AssertionError("terminal next_obs_encoded_v2 should be None")


def test_sequence_fixed_length_and_done_mask() -> None:
    transitions = rollout_v2.record_episode_v2(
        MockRunner(),
        seed=1,
        episode_id="ep-seq",
        rng=random.Random(1),
    )
    sequences = rollout_v2.build_sequences(transitions, seq_len=2, burn_in=1)
    if len(sequences) != 1:
        raise AssertionError(f"expected 1 sequence, got {len(sequences)}")
    seq = sequences[0]
    if seq.burn_in != 1:
        raise AssertionError("burn_in was not preserved")
    if seq.done_mask != [False, True]:
        raise AssertionError(f"bad done mask: {seq.done_mask}")


def test_jsonl_roundtrip_payload_is_raw_and_readable() -> None:
    transitions = rollout_v2.record_episode_v2(
        MockRunner(),
        seed=1,
        episode_id="ep-jsonl",
        rng=random.Random(1),
    )
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "rollout.jsonl"
        rollout_v2.save_transitions_jsonl(transitions, path)
        lines = path.read_text(encoding="utf-8").strip().splitlines()
    if len(lines) != len(transitions):
        raise AssertionError("JSONL line count does not match transitions")
    if "public_features" in lines[0]:
        raise AssertionError("encoded arrays should not be dumped into JSONL")


def test_forbidden_keys_are_rejected() -> None:
    class LeakyRunner(MockRunner):
        def reset(
            self,
            seed: int,
            episode_id: str | None = None,
            extra_options: dict[str, Any] | None = None,
        ) -> dict[str, Any]:
            obs = super().reset(seed, episode_id, extra_options)
            return {**obs, "true_score": {"p1": 42}}

    try:
        rollout_v2.record_episode_v2(LeakyRunner(), seed=1)
    except ValueError as exc:
        if "true_score" not in str(exc):
            raise AssertionError(f"unexpected error: {exc}") from exc
    else:
        raise AssertionError("leaky observation was not rejected")


def test_policy_payload_has_no_forbidden_keys() -> None:
    transitions = rollout_v2.record_episode_v2(
        MockRunner(),
        seed=1,
        episode_id="ep-clean",
        rng=random.Random(1),
    )
    for transition in transitions:
        _assert_no_forbidden_keys(transition.obs_raw)
        if transition.next_obs_raw is not None:
            _assert_no_forbidden_keys(transition.next_obs_raw)


def main() -> int:
    tests = [
        test_transition_minimal,
        test_record_episode_with_mock_runner,
        test_sequence_fixed_length_and_done_mask,
        test_jsonl_roundtrip_payload_is_raw_and_readable,
        test_forbidden_keys_are_rejected,
        test_policy_payload_has_no_forbidden_keys,
    ]
    print("=== test_rollout_v2 ===")
    for test in tests:
        test()
        print(f"  [OK] {test.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
