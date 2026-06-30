"""Smoke tests for the end-to-end R2D2 v2 orchestration script.

Run from rl/:
    uv run python test_smoke_r2d2_v2.py
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import tempfile
from typing import Any

import torch

import smoke_r2d2_v2
import train_r2d2_v2


@dataclass(frozen=True)
class Record:
    transitions: list[int]
    completed: bool = False


class MockRunner:
    def __init__(self, max_turns: int, calls: list[str]) -> None:
        self.max_turns = max_turns
        self.calls = calls

    def __enter__(self) -> "MockRunner":
        self.calls.append(f"runner_enter:{self.max_turns}")
        return self

    def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> None:
        self.calls.append("runner_exit")


class MockFns:
    def __init__(
        self,
        *,
        collect_transitions: int = 3,
        write_checkpoint: bool = True,
        infer_transitions: int = 2,
    ) -> None:
        self.calls: list[str] = []
        self.collect_transitions = collect_transitions
        self.write_checkpoint = write_checkpoint
        self.infer_transitions = infer_transitions

    def runner_factory(self, max_turns: int) -> MockRunner:
        return MockRunner(max_turns, self.calls)

    def collect(self, *args: Any, **kwargs: Any) -> list[Record]:
        del args
        self.calls.append("collect")
        out = Path(kwargs["out"])
        if self.collect_transitions > 0:
            out.write_text("transition\n" * self.collect_transitions, encoding="utf-8")
        return [Record(list(range(self.collect_transitions)), completed=True)]

    def train(self, config: train_r2d2_v2.TrainConfigV2) -> train_r2d2_v2.TrainResultV2:
        self.calls.append("train")
        if self.write_checkpoint and config.save_checkpoint is not None:
            model = smoke_r2d2_v2.model_r2d2_v2.R2D2AgentV2()
            torch.save({"online_model": model.state_dict()}, config.save_checkpoint)
        return train_r2d2_v2.TrainResultV2(
            steps=config.steps,
            final_metrics={"loss": 1.25},
            checkpoint_path=(
                None if config.save_checkpoint is None else str(config.save_checkpoint)
            ),
        )

    def infer(self, *args: Any, **kwargs: Any) -> list[Record]:
        del args, kwargs
        self.calls.append("infer")
        return [Record(list(range(self.infer_transitions)), completed=False)]


def test_parser_cli_works() -> None:
    args = smoke_r2d2_v2.build_arg_parser().parse_args(
        [
            "--episodes",
            "2",
            "--collect-max-steps",
            "50",
            "--train-steps",
            "3",
            "--batch-size",
            "2",
            "--seq-len",
            "4",
            "--burn-in",
            "2",
            "--seed",
            "9",
            "--players",
            "6",
            "--epsilon",
            "0.1",
        ]
    )
    config = smoke_r2d2_v2.config_from_args(args)
    if config.episodes != 2 or config.train_steps != 3 or config.epsilon != 0.1:
        raise AssertionError(f"bad parser config: {config}")


def test_parser_epsilon_schedule_flags() -> None:
    args = smoke_r2d2_v2.build_arg_parser().parse_args(
        [
            "--epsilon-start",
            "1.0",
            "--epsilon-end",
            "0.1",
            "--epsilon-steps",
            "5",
        ]
    )
    config = smoke_r2d2_v2.config_from_args(args)
    if config.epsilon_start != 1.0 or config.epsilon_end != 0.1 or config.epsilon_steps != 5:
        raise AssertionError(f"epsilon schedule flags not parsed: {config}")


def test_epsilon_schedule_passed_to_infer() -> None:
    captured: dict[str, Any] = {}

    fns = MockFns()
    real_infer = fns.infer

    def infer_capture(*args: Any, **kwargs: Any) -> list[Record]:
        captured["epsilon_schedule"] = kwargs.get("epsilon_schedule")
        return real_infer(*args, **kwargs)

    smoke_r2d2_v2.run_smoke_v2(
        smoke_r2d2_v2.SmokeConfigV2(
            epsilon_start=1.0,
            epsilon_end=0.1,
            epsilon_steps=5,
        ),
        runner_factory=fns.runner_factory,
        collect_fn=fns.collect,
        train_fn=fns.train,
        infer_fn=infer_capture,
    )
    schedule = captured.get("epsilon_schedule")
    if schedule is None or schedule.duration_steps != 5:
        raise AssertionError("smoke did not pass the epsilon schedule to infer")


def test_limits_refuse_long_runs() -> None:
    for config in [
        smoke_r2d2_v2.SmokeConfigV2(
            collect_max_steps=smoke_r2d2_v2.MAX_SAFE_COLLECT_STEPS + 1
        ),
        smoke_r2d2_v2.SmokeConfigV2(
            train_steps=smoke_r2d2_v2.MAX_SAFE_TRAIN_STEPS + 1
        ),
    ]:
        try:
            smoke_r2d2_v2.run_smoke_v2(
                config,
                runner_factory=MockFns().runner_factory,
                collect_fn=MockFns().collect,
                train_fn=MockFns().train,
                infer_fn=MockFns().infer,
            )
        except ValueError as exc:
            if "allow-long-run" not in str(exc):
                raise AssertionError(f"unexpected error: {exc}") from exc
        else:
            raise AssertionError("long run was not refused")


def test_tempdir_used_and_removed_by_default() -> None:
    fns = MockFns()
    summary = smoke_r2d2_v2.run_smoke_v2(
        smoke_r2d2_v2.SmokeConfigV2(),
        runner_factory=fns.runner_factory,
        collect_fn=fns.collect,
        train_fn=fns.train,
        infer_fn=fns.infer,
    )
    if summary.kept_artifacts:
        raise AssertionError("artifacts should not be kept by default")
    if Path(summary.artifact_dir).exists():
        raise AssertionError("temporary artifact directory was not removed")


def test_keep_artifacts_requires_and_uses_output_dir() -> None:
    try:
        smoke_r2d2_v2.run_smoke_v2(
            smoke_r2d2_v2.SmokeConfigV2(keep_artifacts=True),
            runner_factory=MockFns().runner_factory,
            collect_fn=MockFns().collect,
            train_fn=MockFns().train,
            infer_fn=MockFns().infer,
        )
    except ValueError as exc:
        if "output-dir" not in str(exc):
            raise AssertionError(f"unexpected error: {exc}") from exc
    else:
        raise AssertionError("keep_artifacts without output_dir did not raise")

    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "artifacts"
        fns = MockFns()
        summary = smoke_r2d2_v2.run_smoke_v2(
            smoke_r2d2_v2.SmokeConfigV2(output_dir=out, keep_artifacts=True),
            runner_factory=fns.runner_factory,
            collect_fn=fns.collect,
            train_fn=fns.train,
            infer_fn=fns.infer,
        )
        if not out.exists():
            raise AssertionError("output_dir was not kept")
        if not Path(summary.dataset_path).exists() or not Path(summary.checkpoint_path).exists():
            raise AssertionError("expected kept artifacts are missing")


def test_pipeline_order_and_summary() -> None:
    fns = MockFns(collect_transitions=4, infer_transitions=2)
    summary = smoke_r2d2_v2.run_smoke_v2(
        smoke_r2d2_v2.SmokeConfigV2(train_steps=5),
        runner_factory=fns.runner_factory,
        collect_fn=fns.collect,
        train_fn=fns.train,
        infer_fn=fns.infer,
    )
    order = [item for item in fns.calls if item in {"collect", "train", "infer"}]
    if order != ["collect", "train", "infer"]:
        raise AssertionError(f"bad pipeline order: {fns.calls}")
    if summary.collected_transitions != 4:
        raise AssertionError(f"bad collected count: {summary}")
    if summary.train_steps != 5 or summary.infer_steps != 2:
        raise AssertionError(f"bad summary step counts: {summary}")


def test_zero_transitions_errors() -> None:
    try:
        smoke_r2d2_v2.run_smoke_v2(
            smoke_r2d2_v2.SmokeConfigV2(),
            runner_factory=MockFns(collect_transitions=0).runner_factory,
            collect_fn=MockFns(collect_transitions=0).collect,
            train_fn=MockFns().train,
            infer_fn=MockFns().infer,
        )
    except RuntimeError as exc:
        if "zero transitions" not in str(exc):
            raise AssertionError(f"unexpected error: {exc}") from exc
    else:
        raise AssertionError("zero transition collect did not raise")


def test_missing_checkpoint_errors() -> None:
    fns = MockFns(write_checkpoint=False)
    try:
        smoke_r2d2_v2.run_smoke_v2(
            smoke_r2d2_v2.SmokeConfigV2(),
            runner_factory=fns.runner_factory,
            collect_fn=fns.collect,
            train_fn=fns.train,
            infer_fn=fns.infer,
        )
    except RuntimeError as exc:
        if "checkpoint" not in str(exc):
            raise AssertionError(f"unexpected error: {exc}") from exc
    else:
        raise AssertionError("missing checkpoint did not raise")


def test_import_has_no_pipeline_side_effect() -> None:
    if not hasattr(smoke_r2d2_v2, "main"):
        raise AssertionError("smoke module missing guarded main")
    if hasattr(smoke_r2d2_v2, "RUN_STARTED"):
        raise AssertionError("module appears to run pipeline at import")


def test_no_repo_artifacts_created_by_mock_smoke() -> None:
    before = set(Path(".").iterdir())
    fns = MockFns()
    smoke_r2d2_v2.run_smoke_v2(
        smoke_r2d2_v2.SmokeConfigV2(),
        runner_factory=fns.runner_factory,
        collect_fn=fns.collect,
        train_fn=fns.train,
        infer_fn=fns.infer,
    )
    after = set(Path(".").iterdir())
    if before != after:
        raise AssertionError("mock smoke created files in current directory")


def main() -> int:
    tests = [
        test_parser_cli_works,
        test_parser_epsilon_schedule_flags,
        test_epsilon_schedule_passed_to_infer,
        test_limits_refuse_long_runs,
        test_tempdir_used_and_removed_by_default,
        test_keep_artifacts_requires_and_uses_output_dir,
        test_pipeline_order_and_summary,
        test_zero_transitions_errors,
        test_missing_checkpoint_errors,
        test_import_has_no_pipeline_side_effect,
        test_no_repo_artifacts_created_by_mock_smoke,
    ]
    print("=== test_smoke_r2d2_v2 ===")
    for test in tests:
        test()
        print(f"  [OK] {test.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
