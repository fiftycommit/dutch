"""Smoke tests for the controlled R2D2 v2 training CLI.

Run from rl/:
    uv run python test_train_r2d2_v2.py
"""

from __future__ import annotations

from pathlib import Path
import tempfile
from typing import Any

import torch

import encoding_v2
import rollout_v2
import train_r2d2_v2


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
                    "legacy_action_id": 1,
                }
            ],
        },
    }


def _transition(
    episode_id: str,
    step: int,
    *,
    done: bool = False,
) -> rollout_v2.TransitionV2:
    obs = _obs(step)
    next_obs = None if done else _obs(step + 1)
    return rollout_v2.TransitionV2(
        obs_raw=obs,
        obs_encoded_v2=encoding_v2.encode_observation_v2(obs),
        action_v2={"action_type": "pass_tick"},
        legacy_action_id=1,
        reward=1.0 + float(step),
        done=done,
        next_obs_raw=next_obs,
        next_obs_encoded_v2=(
            None if next_obs is None else encoding_v2.encode_observation_v2(next_obs)
        ),
        info={},
        episode_id=episode_id,
        step_index=step,
    )


def _write_dataset(path: Path, *, count: int = 6) -> None:
    transitions = [
        _transition("ep", step, done=step == count - 1)
        for step in range(count)
    ]
    rollout_v2.save_transitions_jsonl(transitions, path)


def test_parser_cli_works() -> None:
    args = train_r2d2_v2.build_arg_parser().parse_args(
        [
            "--dataset",
            "sample.jsonl",
            "--steps",
            "2",
            "--batch-size",
            "1",
            "--seq-len",
            "2",
            "--burn-in",
            "1",
            "--allow-save",
            "--save-checkpoint",
            "model.pt",
        ]
    )
    config = train_r2d2_v2.config_from_args(args)
    if config.dataset != Path("sample.jsonl") or config.steps != 2:
        raise AssertionError("parser did not build expected config")
    if config.no_save:
        raise AssertionError("--allow-save should permit checkpoint saving")


def test_refuses_missing_dataset() -> None:
    config = train_r2d2_v2.TrainConfigV2(dataset=Path("/tmp/missing-r2d2-v2.jsonl"))
    try:
        train_r2d2_v2.run_training_smoke(config)
    except FileNotFoundError:
        pass
    else:
        raise AssertionError("missing dataset did not raise")


def test_refuses_too_many_steps_without_allow_long_run() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "data.jsonl"
        _write_dataset(path)
        config = train_r2d2_v2.TrainConfigV2(
            dataset=path,
            steps=train_r2d2_v2.MAX_SAFE_STEPS + 1,
        )
        try:
            train_r2d2_v2.run_training_smoke(config)
        except ValueError as exc:
            if "allow-long-run" not in str(exc):
                raise AssertionError(f"unexpected error: {exc}") from exc
        else:
            raise AssertionError("long run was not refused")


def test_run_minimal_training_on_tmp_jsonl() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "data.jsonl"
        _write_dataset(path, count=6)
        result = train_r2d2_v2.run_training_smoke(
            train_r2d2_v2.TrainConfigV2(
                dataset=path,
                steps=2,
                batch_size=2,
                seq_len=2,
                burn_in=1,
                n_step=1,
                learning_rate=1.0e-3,
                target_update_interval=2,
                seed=7,
            )
        )
    if result.steps != 2:
        raise AssertionError("training smoke did not run requested steps")
    if result.final_metrics.get("learner_step") != 2.0:
        raise AssertionError(f"learner_step metric wrong: {result.final_metrics}")
    if not torch.isfinite(torch.tensor(result.final_metrics["loss"])):
        raise AssertionError("loss metric is not finite")


def test_saves_checkpoint_if_requested() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        dataset = Path(tmp) / "data.jsonl"
        checkpoint = Path(tmp) / "checkpoint.pt"
        _write_dataset(dataset, count=4)
        result = train_r2d2_v2.run_training_smoke(
            train_r2d2_v2.TrainConfigV2(
                dataset=dataset,
                steps=1,
                batch_size=1,
                seq_len=2,
                burn_in=1,
                n_step=1,
                save_checkpoint=checkpoint,
                no_save=False,
            )
        )
        if result.checkpoint_path != str(checkpoint):
            raise AssertionError("checkpoint path not reported")
        if not checkpoint.exists():
            raise AssertionError("checkpoint was not written")
        payload = torch.load(checkpoint, map_location="cpu")
    for key in ["online_model", "target_model", "optimizer", "config", "learner_state"]:
        if key not in payload:
            raise AssertionError(f"missing checkpoint key {key}")


def test_no_save_by_default() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        dataset = Path(tmp) / "data.jsonl"
        checkpoint = Path(tmp) / "checkpoint.pt"
        _write_dataset(dataset, count=4)
        result = train_r2d2_v2.run_training_smoke(
            train_r2d2_v2.TrainConfigV2(
                dataset=dataset,
                steps=1,
                batch_size=1,
                seq_len=2,
                burn_in=1,
                n_step=1,
                save_checkpoint=checkpoint,
                no_save=True,
            )
        )
        if result.checkpoint_path is not None:
            raise AssertionError("checkpoint path should be None when no_save=True")
        if checkpoint.exists():
            raise AssertionError("checkpoint was written despite no_save=True")


def test_replay_buffer_too_small_errors() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "tiny.jsonl"
        _write_dataset(path, count=1)
        try:
            train_r2d2_v2.run_training_smoke(
                train_r2d2_v2.TrainConfigV2(
                    dataset=path,
                    steps=1,
                    batch_size=2,
                    seq_len=1,
                    burn_in=0,
                    n_step=1,
                )
            )
        except ValueError as exc:
            if "too small" not in str(exc):
                raise AssertionError(f"unexpected error: {exc}") from exc
        else:
            raise AssertionError("tiny replay buffer did not raise")


def test_import_has_no_training_side_effect() -> None:
    if not hasattr(train_r2d2_v2, "main"):
        raise AssertionError("train module missing guarded main")
    if hasattr(train_r2d2_v2, "RUN_STARTED"):
        raise AssertionError("module appears to start work at import")


def test_no_runner_dependency_or_raw_field_use() -> None:
    source_names = set(train_r2d2_v2.__dict__.keys())
    if "RunnerProcess" in source_names:
        raise AssertionError("training smoke should not import the runner")
    if "obs_raw" in source_names or "info" in source_names:
        raise AssertionError("training smoke should not expose raw policy fields")


def main() -> int:
    tests = [
        test_parser_cli_works,
        test_refuses_missing_dataset,
        test_refuses_too_many_steps_without_allow_long_run,
        test_run_minimal_training_on_tmp_jsonl,
        test_saves_checkpoint_if_requested,
        test_no_save_by_default,
        test_replay_buffer_too_small_errors,
        test_import_has_no_training_side_effect,
        test_no_runner_dependency_or_raw_field_use,
    ]
    print("=== test_train_r2d2_v2 ===")
    for test in tests:
        test()
        print(f"  [OK] {test.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
