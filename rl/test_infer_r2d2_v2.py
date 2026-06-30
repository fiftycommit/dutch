"""Smoke tests for untrained R2D2 v2 inference plumbing.

Run from rl/:
    uv run python test_infer_r2d2_v2.py
"""

from __future__ import annotations

from pathlib import Path
import random
import tempfile
from typing import Any

import torch

import encoding_v2
import infer_r2d2_v2
import model_r2d2_v2


def _obs(step: int, *, done: bool = False) -> dict[str, Any]:
    return {
        "type": "observation",
        "done": done,
        "micro_phase": "reaction",
        "action_mask": {"pass_tick": True, "match": [True]},
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
            "masks": {
                "action_type": {"pass_tick": True, "match": True},
                "match_slot": [True],
            },
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


class RecordingModel:
    def __init__(self) -> None:
        self.hidden_inputs: list[torch.Tensor | None] = []
        self.grad_enabled: list[bool] = []
        self.calls = 0

    def __call__(
        self,
        batch: Any,
        hidden_state: torch.Tensor | None = None,
        *,
        apply_masks: bool = True,
    ) -> model_r2d2_v2.R2D2OutputV2:
        del apply_masks
        self.hidden_inputs.append(hidden_state)
        self.grad_enabled.append(torch.is_grad_enabled())
        self.calls += 1
        batch_size, total_len = batch.rewards.shape
        action_q = torch.zeros(batch_size, total_len, len(encoding_v2.ACTION_TYPES))
        action_q[:, :, encoding_v2.ACTION_TYPES.index("pass_tick")] = 2.0
        action_q[:, :, encoding_v2.ACTION_TYPES.index("match")] = 1.0
        hidden = torch.full((1, batch_size, 8), float(self.calls))
        target_slot_shape = (
            batch_size,
            total_len,
            encoding_v2.MAX_PLAYERS,
            encoding_v2.MAX_SLOTS,
        )
        return model_r2d2_v2.R2D2OutputV2(
            action_type_q=action_q,
            own_slot_q=torch.zeros(batch_size, total_len, encoding_v2.MAX_SLOTS),
            match_slot_q=torch.zeros(batch_size, total_len, encoding_v2.MAX_SLOTS),
            target_player_q=torch.zeros(batch_size, total_len, encoding_v2.MAX_PLAYERS),
            target_slot_q=torch.zeros(*target_slot_shape),
            jack_player_a_q=torch.zeros(batch_size, total_len, encoding_v2.MAX_PLAYERS),
            jack_slot_a_q=torch.zeros(*target_slot_shape),
            jack_player_b_q=torch.zeros(batch_size, total_len, encoding_v2.MAX_PLAYERS),
            jack_slot_b_q=torch.zeros(*target_slot_shape),
            legacy_q=None,
            hidden_state=hidden,
            burn_in_mask=torch.zeros(batch_size, total_len, dtype=torch.bool),
            train_mask=torch.ones(batch_size, total_len, dtype=torch.bool),
            padding_mask=torch.zeros(batch_size, total_len, dtype=torch.bool),
        )


def test_constructs_model_and_encodes_observation() -> None:
    model = model_r2d2_v2.R2D2AgentV2(hidden_dim=16, embed_dim=8)
    batch = infer_r2d2_v2.observation_batch_v2(_obs(0))
    output = model(batch)
    if output.action_type_q.shape[:2] != (1, 1):
        raise AssertionError(f"bad inference output shape: {output.action_type_q.shape}")


def test_policy_produces_legal_action_and_runner_message() -> None:
    model = RecordingModel()
    batch = infer_r2d2_v2.observation_batch_v2(_obs(0))
    with torch.no_grad():
        output = model(batch, hidden_state=None)
    selected = infer_r2d2_v2.policy_r2d2_v2.select_action_from_batch_output(
        output,
        batch_index=0,
        time_index=0,
        legal_action_v2=_obs(0)["legal_action_v2"],
    )
    legal = [entry["action_v2"] for entry in _obs(0)["legal_action_v2"]["actions"]]
    if selected.action_v2 not in legal:
        raise AssertionError("selected action is not legal")
    msg = infer_r2d2_v2.policy_r2d2_v2.action_message_for_runner_v2(selected)
    if msg != {"action_v2": selected.action_v2}:
        raise AssertionError(f"bad action message: {msg}")


def test_hidden_state_is_propagated() -> None:
    model = RecordingModel()
    record = infer_r2d2_v2.infer_episode_v2(
        MockRunner(terminal_step=2),
        model,
        seed=0,
        episode_id="ep-hidden",
        epsilon=0.0,
        rng=random.Random(0),
        max_steps=5,
    )
    if len(record.transitions) != 2:
        raise AssertionError("mock episode should have two transitions")
    if model.hidden_inputs[0] is not None:
        raise AssertionError("first hidden_state should be None")
    if model.hidden_inputs[1] is None:
        raise AssertionError("second hidden_state was not propagated")
    if any(model.grad_enabled):
        raise AssertionError("inference forward was not under torch.no_grad")


def test_hidden_state_resets_between_episodes() -> None:
    model = RecordingModel()
    records = infer_r2d2_v2.infer_rollouts_v2(
        MockRunner(terminal_step=1),
        model,
        episodes=2,
        seed=0,
        max_steps=5,
        epsilon=0.0,
    )
    if len(records) != 2:
        raise AssertionError("expected two records")
    if model.hidden_inputs[0] is not None or model.hidden_inputs[1] is not None:
        raise AssertionError("hidden_state was not reset between episodes")


def test_epsilon_one_remains_legal() -> None:
    model = RecordingModel()
    record = infer_r2d2_v2.infer_episode_v2(
        MockRunner(terminal_step=1),
        model,
        seed=0,
        episode_id="ep-epsilon",
        epsilon=1.0,
        rng=random.Random(4),
        max_steps=5,
    )
    selected_action = record.transitions[0].action_v2
    legal = [entry["action_v2"] for entry in _obs(0)["legal_action_v2"]["actions"]]
    if selected_action not in legal:
        raise AssertionError(f"epsilon action was not legal: {selected_action}")


def test_no_save_without_save_flag() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "should_not_exist.jsonl"
        infer_r2d2_v2.infer_rollouts_v2(
            MockRunner(terminal_step=1),
            RecordingModel(),
            episodes=1,
            seed=0,
            max_steps=5,
            epsilon=0.0,
            save_transitions=out,
            save=False,
        )
        if out.exists():
            raise AssertionError("inference saved transitions despite save=False")


def test_optional_save_jsonl() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "inference.jsonl"
        records = infer_r2d2_v2.infer_rollouts_v2(
            MockRunner(terminal_step=1),
            RecordingModel(),
            episodes=1,
            seed=0,
            max_steps=5,
            epsilon=0.0,
            save_transitions=out,
            save=True,
        )
        if not out.exists():
            raise AssertionError("inference did not save requested JSONL")
        lines = out.read_text(encoding="utf-8").strip().splitlines()
    if len(lines) != sum(len(record.transitions) for record in records):
        raise AssertionError("saved JSONL line count mismatch")


def test_collects_multiple_transitions_with_mock_runner() -> None:
    runner = MockRunner(terminal_step=3)
    record = infer_r2d2_v2.infer_episode_v2(
        runner,
        RecordingModel(),
        seed=0,
        episode_id="ep-multi",
        epsilon=0.0,
        rng=random.Random(0),
        max_steps=5,
    )
    if len(record.transitions) != 3 or len(runner.actions) != 3:
        raise AssertionError("mock runner did not collect expected transitions")
    if not record.completed or record.truncated_by_max_steps:
        raise AssertionError("record completion flags are wrong")


def test_no_raw_fields_in_model_input_or_record() -> None:
    batch = infer_r2d2_v2.observation_batch_v2(_obs(0))
    if hasattr(batch, "obs_raw") or hasattr(batch, "info"):
        raise AssertionError("inference batch leaked raw fields")
    record = infer_r2d2_v2.infer_episode_v2(
        MockRunner(terminal_step=1),
        RecordingModel(),
        seed=0,
        episode_id="ep-clean",
        epsilon=0.0,
        rng=random.Random(0),
        max_steps=5,
    )
    transition = record.transitions[0]
    if "true_score" in str(transition.obs_raw) or "full_hand" in str(transition.obs_raw):
        raise AssertionError("forbidden fields leaked into transition observation")


def main() -> int:
    tests = [
        test_constructs_model_and_encodes_observation,
        test_policy_produces_legal_action_and_runner_message,
        test_hidden_state_is_propagated,
        test_hidden_state_resets_between_episodes,
        test_epsilon_one_remains_legal,
        test_no_save_without_save_flag,
        test_optional_save_jsonl,
        test_collects_multiple_transitions_with_mock_runner,
        test_no_raw_fields_in_model_input_or_record,
    ]
    print("=== test_infer_r2d2_v2 ===")
    for test in tests:
        test()
        print(f"  [OK] {test.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
