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


def test_parser_prioritized_and_double_q_flags() -> None:
    args = train_r2d2_v2.build_arg_parser().parse_args(
        [
            "--dataset",
            "sample.jsonl",
            "--prioritized-replay",
            "--double-q",
            "--priority-alpha",
            "0.7",
            "--priority-beta",
            "0.5",
            "--priority-epsilon",
            "1e-5",
            "--priority-eta",
            "0.8",
        ]
    )
    config = train_r2d2_v2.config_from_args(args)
    if not config.prioritized_replay or not config.double_q:
        raise AssertionError("prioritized/double-q flags not parsed")
    if config.priority_alpha != 0.7 or config.priority_beta != 0.5:
        raise AssertionError("priority alpha/beta not parsed")
    if config.priority_epsilon != 1e-5 or config.priority_eta != 0.8:
        raise AssertionError("priority epsilon/eta not parsed")


def test_run_minimal_prioritized_training() -> None:
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
                prioritized_replay=True,
                seed=7,
            )
        )
    if result.final_metrics.get("prioritized") != 1.0:
        raise AssertionError("prioritized training did not report prioritized=1.0")
    if not torch.isfinite(torch.tensor(result.final_metrics["loss"])):
        raise AssertionError("prioritized loss not finite")


def test_run_minimal_double_q_training() -> None:
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
                n_step=2,
                double_q=True,
                seed=7,
            )
        )
    if result.final_metrics.get("double_q") != 1.0:
        raise AssertionError("double-q training did not report double_q=1.0")
    if not torch.isfinite(torch.tensor(result.final_metrics["loss"])):
        raise AssertionError("double-q loss not finite")


def test_run_prioritized_double_q_checkpoint_loadable() -> None:
    import model_r2d2_v2

    with tempfile.TemporaryDirectory() as tmp:
        dataset = Path(tmp) / "data.jsonl"
        checkpoint = Path(tmp) / "checkpoint.pt"
        _write_dataset(dataset, count=6)
        train_r2d2_v2.run_training_smoke(
            train_r2d2_v2.TrainConfigV2(
                dataset=dataset,
                steps=2,
                batch_size=2,
                seq_len=2,
                burn_in=1,
                n_step=2,
                prioritized_replay=True,
                double_q=True,
                save_checkpoint=checkpoint,
                no_save=False,
                seed=3,
            )
        )
        payload = torch.load(checkpoint, map_location="cpu")
        model = model_r2d2_v2.R2D2AgentV2()
        model.load_state_dict(payload["online_model"])


def test_parser_beta_schedule_flags() -> None:
    args = train_r2d2_v2.build_arg_parser().parse_args(
        [
            "--dataset",
            "sample.jsonl",
            "--prioritized-replay",
            "--priority-beta-start",
            "0.2",
            "--priority-beta-end",
            "0.9",
            "--priority-beta-steps",
            "100",
        ]
    )
    config = train_r2d2_v2.config_from_args(args)
    if config.priority_beta_start != 0.2 or config.priority_beta_end != 0.9:
        raise AssertionError("beta schedule start/end not parsed")
    if config.priority_beta_steps != 100:
        raise AssertionError("beta schedule steps not parsed")


def test_beta_schedule_requires_prioritized_replay() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "data.jsonl"
        _write_dataset(path, count=6)
        config = train_r2d2_v2.TrainConfigV2(
            dataset=path,
            steps=1,
            batch_size=2,
            seq_len=2,
            burn_in=1,
            n_step=1,
            prioritized_replay=False,
            priority_beta_start=0.0,
            priority_beta_end=1.0,
            priority_beta_steps=2,
        )
        try:
            train_r2d2_v2.run_training_smoke(config)
        except ValueError as exc:
            if "prioritized-replay" not in str(exc):
                raise AssertionError(f"unexpected error: {exc}") from exc
        else:
            raise AssertionError("beta schedule without prioritized did not raise")


def test_beta_schedule_anneals_and_reports_current_beta() -> None:
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
                prioritized_replay=True,
                priority_beta_start=0.0,
                priority_beta_end=1.0,
                priority_beta_steps=1,
                seed=7,
            )
        )
    # Last step is index 1; duration 1 means beta has reached the end value.
    if abs(result.final_metrics["priority_beta_current"] - 1.0) > 1e-9:
        raise AssertionError(
            f"beta did not reach beta_end: {result.final_metrics.get('priority_beta_current')}"
        )
    if result.final_metrics.get("schedule_step") != 1.0:
        raise AssertionError("schedule_step metric missing or wrong")


def test_constant_beta_reported_without_schedule() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "data.jsonl"
        _write_dataset(path, count=6)
        result = train_r2d2_v2.run_training_smoke(
            train_r2d2_v2.TrainConfigV2(
                dataset=path,
                steps=1,
                batch_size=2,
                seq_len=2,
                burn_in=1,
                n_step=1,
                prioritized_replay=True,
                priority_beta=0.37,
                seed=7,
            )
        )
    if abs(result.final_metrics["priority_beta_current"] - 0.37) > 1e-9:
        raise AssertionError("constant beta not reported as priority_beta_current")


def test_checkpoint_config_includes_beta_schedule() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        dataset = Path(tmp) / "data.jsonl"
        checkpoint = Path(tmp) / "checkpoint.pt"
        _write_dataset(dataset, count=6)
        train_r2d2_v2.run_training_smoke(
            train_r2d2_v2.TrainConfigV2(
                dataset=dataset,
                steps=1,
                batch_size=2,
                seq_len=2,
                burn_in=1,
                n_step=1,
                prioritized_replay=True,
                priority_beta_start=0.2,
                priority_beta_end=0.9,
                priority_beta_steps=5,
                save_checkpoint=checkpoint,
                no_save=False,
                seed=3,
            )
        )
        payload = torch.load(checkpoint, map_location="cpu")
    for key in ["priority_beta_start", "priority_beta_end", "priority_beta_steps"]:
        if key not in payload["config"]:
            raise AssertionError(f"checkpoint config missing {key}")
    if payload["config"]["priority_beta_steps"] != 5:
        raise AssertionError("checkpoint config did not persist schedule value")


def test_metrics_out_writes_jsonl_per_step() -> None:
    import json

    with tempfile.TemporaryDirectory() as tmp:
        dataset = Path(tmp) / "data.jsonl"
        metrics = Path(tmp) / "metrics.jsonl"
        _write_dataset(dataset, count=6)
        train_r2d2_v2.run_training_smoke(
            train_r2d2_v2.TrainConfigV2(
                dataset=dataset,
                steps=3,
                batch_size=2,
                seq_len=2,
                burn_in=1,
                n_step=1,
                prioritized_replay=True,
                double_q=True,
                priority_beta_start=0.4,
                priority_beta_end=1.0,
                priority_beta_steps=3,
                metrics_out=metrics,
                seed=5,
            )
        )
        if not metrics.exists():
            raise AssertionError("metrics-out did not write a file")
        lines = metrics.read_text(encoding="utf-8").strip().splitlines()
    if len(lines) != 3:
        raise AssertionError(f"expected one metrics line per step, got {len(lines)}")
    rows = [json.loads(line) for line in lines]
    required = [
        "step",
        "loss",
        "grad_norm",
        "mean_td_error",
        "max_td_error",
        "mean_priority",
        "mean_is_weight",
        "priority_beta_current",
        "schedule_step",
        "prioritized",
        "double_q",
    ]
    for row in rows:
        for key in required:
            if key not in row:
                raise AssertionError(f"metrics line missing key {key}: {row}")
    if rows[0]["step"] != 0 or rows[-1]["step"] != 2:
        raise AssertionError("metrics step indices wrong")
    # Beta really anneals across the written rows (start 0.4 -> end 1.0).
    if rows[0]["priority_beta_current"] >= rows[-1]["priority_beta_current"]:
        raise AssertionError("beta did not increase across metrics rows")


def test_checkpoint_with_metrics_out_loads_weights_only() -> None:
    # Regression guard: a checkpoint saved while --metrics-out is set must stay
    # loadable under torch.load(weights_only=True) (no pickled pathlib.Path in
    # the serialized config), which is how evaluate_r2d2_v2 loads checkpoints.
    with tempfile.TemporaryDirectory() as tmp:
        dataset = Path(tmp) / "data.jsonl"
        checkpoint = Path(tmp) / "checkpoint.pt"
        metrics = Path(tmp) / "metrics.jsonl"
        _write_dataset(dataset, count=6)
        train_r2d2_v2.run_training_smoke(
            train_r2d2_v2.TrainConfigV2(
                dataset=dataset,
                steps=1,
                batch_size=1,
                seq_len=2,
                burn_in=1,
                n_step=1,
                save_checkpoint=checkpoint,
                no_save=False,
                metrics_out=metrics,
            )
        )
        payload = torch.load(checkpoint, map_location="cpu", weights_only=True)
    if not isinstance(payload["config"]["metrics_out"], str):
        raise AssertionError("metrics_out was not stringified in checkpoint config")
    if "online_model" not in payload:
        raise AssertionError("checkpoint missing online_model under weights_only load")


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


def _fresh_learner() -> Any:
    return train_r2d2_v2.learner_r2d2_v2.R2D2LearnerV2(
        online_model=train_r2d2_v2.model_r2d2_v2.R2D2AgentV2(),
        target_model=train_r2d2_v2.model_r2d2_v2.R2D2AgentV2(),
        config=train_r2d2_v2.learner_r2d2_v2.LearnerConfigV2(
            gamma=0.99,
            n_step=1,
            learning_rate=1.0e-4,
            target_update_interval=10,
            double_q=False,
            priority_eta=0.9,
            device="cpu",
        ),
    )


def _make_checkpoint(tmp: Path) -> Path:
    dataset = tmp / "data.jsonl"
    checkpoint = tmp / "checkpoint.pt"
    _write_dataset(dataset, count=4)
    train_r2d2_v2.run_training_smoke(
        train_r2d2_v2.TrainConfigV2(
            dataset=dataset, steps=1, batch_size=1, seq_len=2, burn_in=1,
            n_step=1, save_checkpoint=checkpoint, no_save=False,
        )
    )
    return checkpoint


def test_from_scratch_default_resume_none() -> None:
    # Sans --resume-from, resume_from est None et le from-scratch marche.
    args = train_r2d2_v2.build_arg_parser().parse_args(["--dataset", "x.jsonl"])
    if train_r2d2_v2.config_from_args(args).resume_from is not None:
        raise AssertionError("resume_from should default to None")
    with tempfile.TemporaryDirectory() as tmp:
        dataset = Path(tmp) / "data.jsonl"
        _write_dataset(dataset, count=4)
        res = train_r2d2_v2.run_training_smoke(
            train_r2d2_v2.TrainConfigV2(
                dataset=dataset, steps=1, batch_size=1, seq_len=2, burn_in=1,
                n_step=1,
            )
        )
        if res.steps != 1:
            raise AssertionError("from-scratch training regressed")


def test_resume_restores_weights_optimizer_step() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        checkpoint = _make_checkpoint(Path(tmp))
        saved = torch.load(checkpoint, map_location="cpu")
        learner = _fresh_learner()
        train_r2d2_v2._resume_from_checkpoint(learner, checkpoint, "cpu")
        # Poids en ligne identiques au checkpoint.
        online = learner.online_model.state_dict()
        for k, v in saved["online_model"].items():
            if not torch.equal(online[k], v):
                raise AssertionError(f"online weight {k} not restored")
        # Optimizer momentum restauré (Adam a un state non vide après 1 step).
        if not learner.optimizer.state_dict()["state"]:
            raise AssertionError("optimizer state not restored")
        # learner_step restauré.
        if learner.state.step != saved["learner_state"]["step"]:
            raise AssertionError("learner step not restored")


def test_resume_end_to_end_run() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        checkpoint = _make_checkpoint(Path(tmp))
        dataset = Path(tmp) / "data.jsonl"  # créé par _make_checkpoint
        res = train_r2d2_v2.run_training_smoke(
            train_r2d2_v2.TrainConfigV2(
                dataset=dataset, steps=1, batch_size=1, seq_len=2, burn_in=1,
                n_step=1, resume_from=checkpoint,
            )
        )
        if res.steps != 1:
            raise AssertionError("resume end-to-end run failed")


def test_resume_missing_checkpoint_raises() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        dataset = Path(tmp) / "data.jsonl"
        _write_dataset(dataset, count=4)
        try:
            train_r2d2_v2.run_training_smoke(
                train_r2d2_v2.TrainConfigV2(
                    dataset=dataset, steps=1, batch_size=1, seq_len=2, burn_in=1,
                    n_step=1, resume_from=Path(tmp) / "nope.pt",
                )
            )
        except FileNotFoundError:
            return
        raise AssertionError("missing resume checkpoint did not raise")


def test_resume_invalid_checkpoint_raises() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        dataset = Path(tmp) / "data.jsonl"
        _write_dataset(dataset, count=4)
        bad = Path(tmp) / "bad.pt"
        bad.write_text("not a torch checkpoint")
        try:
            train_r2d2_v2.run_training_smoke(
                train_r2d2_v2.TrainConfigV2(
                    dataset=dataset, steps=1, batch_size=1, seq_len=2, burn_in=1,
                    n_step=1, resume_from=bad,
                )
            )
        except ValueError:
            return
        raise AssertionError("invalid resume checkpoint did not raise ValueError")


def main() -> int:
    tests = [
        test_parser_cli_works,
        test_refuses_missing_dataset,
        test_refuses_too_many_steps_without_allow_long_run,
        test_run_minimal_training_on_tmp_jsonl,
        test_saves_checkpoint_if_requested,
        test_no_save_by_default,
        test_replay_buffer_too_small_errors,
        test_parser_prioritized_and_double_q_flags,
        test_run_minimal_prioritized_training,
        test_run_minimal_double_q_training,
        test_run_prioritized_double_q_checkpoint_loadable,
        test_parser_beta_schedule_flags,
        test_beta_schedule_requires_prioritized_replay,
        test_beta_schedule_anneals_and_reports_current_beta,
        test_constant_beta_reported_without_schedule,
        test_checkpoint_config_includes_beta_schedule,
        test_metrics_out_writes_jsonl_per_step,
        test_checkpoint_with_metrics_out_loads_weights_only,
        test_import_has_no_training_side_effect,
        test_no_runner_dependency_or_raw_field_use,
        test_from_scratch_default_resume_none,
        test_resume_restores_weights_optimizer_step,
        test_resume_end_to_end_run,
        test_resume_missing_checkpoint_raises,
        test_resume_invalid_checkpoint_raises,
    ]
    print("=== test_train_r2d2_v2 ===")
    for test in tests:
        test()
        print(f"  [OK] {test.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
