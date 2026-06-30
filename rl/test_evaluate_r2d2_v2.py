"""Smoke tests for controlled R2D2 v2 evaluation.

Run from rl/:
    uv run python test_evaluate_r2d2_v2.py
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import tempfile
from typing import Any

import torch

import collect_rollouts_v2
import evaluate_r2d2_v2
import model_r2d2_v2


@dataclass
class FakeTransition:
    reward: float
    action_v2: dict[str, Any] | None = None
    obs_raw: dict[str, Any] = field(default_factory=dict)
    info: dict[str, Any] = field(default_factory=dict)


@dataclass
class FakeRecord:
    transitions: list[FakeTransition]
    completed: bool = True
    truncated_by_max_steps: bool = False


class FakeRunner:
    def __init__(self, max_turns: int) -> None:
        self.max_turns = max_turns
        self.entered = False
        self.exited = False

    def __enter__(self) -> "FakeRunner":
        self.entered = True
        return self

    def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> None:
        del exc_type, exc, tb
        self.exited = True


def _checkpoint(path: Path) -> None:
    model = model_r2d2_v2.R2D2AgentV2()
    torch.save({"online_model": model.state_dict()}, path)


def _records(prefix: str, reward: float = 1.0) -> list[FakeRecord]:
    return [
        FakeRecord(
            transitions=[
                FakeTransition(
                    reward=reward,
                    action_v2={"action_type": "call_dutch"} if prefix == "model" else None,
                    obs_raw={"recent_events": [{"event_type": "dutch_call"}]},
                    info={},
                ),
                FakeTransition(
                    reward=reward + 1.0,
                    action_v2={"action_type": "pass_tick"},
                    obs_raw={},
                    info={},
                ),
            ],
            completed=True,
        )
    ]


def test_parser_cli_works() -> None:
    args = evaluate_r2d2_v2.build_arg_parser().parse_args(
        [
            "--checkpoint",
            "model.pt",
            "--episodes",
            "2",
            "--max-steps",
            "30",
            "--players",
            "4",
            "--epsilon",
            "0.2",
            "--compare-random",
            "--output-json",
            "summary.json",
            "--no-save",
        ]
    )
    config = evaluate_r2d2_v2.config_from_args(args)
    if config.checkpoint != Path("model.pt") or config.episodes != 2:
        raise AssertionError("parser did not build expected config")
    if not config.compare_random or config.output_json != Path("summary.json"):
        raise AssertionError("parser missed comparison/output flags")


def test_parser_epsilon_schedule_flags() -> None:
    args = evaluate_r2d2_v2.build_arg_parser().parse_args(
        [
            "--checkpoint",
            "model.pt",
            "--epsilon-start",
            "1.0",
            "--epsilon-end",
            "0.1",
            "--epsilon-steps",
            "200",
        ]
    )
    config = evaluate_r2d2_v2.config_from_args(args)
    if config.epsilon_start != 1.0 or config.epsilon_end != 0.1 or config.epsilon_steps != 200:
        raise AssertionError("epsilon schedule flags not parsed in evaluate")


def test_epsilon_schedule_passed_to_infer() -> None:
    captured: dict[str, Any] = {}

    def infer_fn(*args: Any, **kwargs: Any) -> list[FakeRecord]:
        del args
        captured["epsilon_schedule"] = kwargs.get("epsilon_schedule")
        return _records("model")

    with tempfile.TemporaryDirectory() as tmp:
        checkpoint = Path(tmp) / "model.pt"
        _checkpoint(checkpoint)
        evaluate_r2d2_v2.run_evaluation_v2(
            evaluate_r2d2_v2.EvalConfigV2(
                checkpoint=checkpoint,
                episodes=1,
                max_steps=5,
                epsilon_start=1.0,
                epsilon_end=0.0,
                epsilon_steps=10,
            ),
            runner_factory=FakeRunner,
            infer_fn=infer_fn,
        )
    schedule = captured.get("epsilon_schedule")
    if schedule is None or schedule.duration_steps != 10:
        raise AssertionError("evaluate did not pass the epsilon schedule to infer")


def test_refuses_missing_checkpoint() -> None:
    config = evaluate_r2d2_v2.EvalConfigV2(
        checkpoint=Path("/tmp/missing-r2d2-v2-checkpoint.pt")
    )
    try:
        evaluate_r2d2_v2.run_evaluation_v2(config)
    except FileNotFoundError:
        pass
    else:
        raise AssertionError("missing checkpoint did not raise")


def test_refuses_long_runs_without_allow_long_run() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        checkpoint = Path(tmp) / "model.pt"
        _checkpoint(checkpoint)
        config = evaluate_r2d2_v2.EvalConfigV2(
            checkpoint=checkpoint,
            episodes=evaluate_r2d2_v2.MAX_SAFE_EPISODES + 1,
        )
        try:
            evaluate_r2d2_v2.run_evaluation_v2(
                config,
                runner_factory=FakeRunner,
                infer_fn=lambda *args, **kwargs: [],
            )
        except ValueError as exc:
            if "allow-long-run" not in str(exc):
                raise AssertionError(f"unexpected error: {exc}") from exc
        else:
            raise AssertionError("long evaluation was not refused")


def test_metrics_aggregate_steps_rewards_and_missing_wins() -> None:
    metrics = evaluate_r2d2_v2.metrics_from_records(_records("model", reward=2.0))
    if metrics.episodes != 1 or metrics.completed_episodes != 1:
        raise AssertionError(f"episode metrics wrong: {metrics}")
    if metrics.total_steps != 2 or metrics.total_reward != 5.0:
        raise AssertionError(f"step/reward metrics wrong: {metrics}")
    if metrics.dutch_calls != 2:
        raise AssertionError(f"dutch call count wrong: {metrics.dutch_calls}")
    if metrics.wins is not None:
        raise AssertionError("wins should stay null when not exposed")
    if metrics.final_scores_p0 is not None:
        raise AssertionError("final score should stay null when not exposed")
    if metrics.successful_dutch_calls is not None or metrics.failed_dutch_calls is not None:
        raise AssertionError("dutch result split should stay null when not exposed")


def test_metrics_aggregate_terminal_results_when_exposed() -> None:
    records = [
        FakeRecord(
            transitions=[
                FakeTransition(
                    reward=1.0,
                    action_v2={"action_type": "call_dutch"},
                    info={
                        "won": True,
                        "rank": 1,
                        "called_dutch": True,
                        "final_scores": {"p0": 12, "p1": 20},
                        "final_ranks": {"p0": 1, "p1": 2},
                        "done_reason": "round_end",
                    },
                )
            ],
            completed=True,
        ),
        FakeRecord(
            transitions=[
                FakeTransition(
                    reward=-1.0,
                    info={
                        "won": False,
                        "rank": 3,
                        "called_dutch": True,
                        "final_scores": {"p0": 44, "p1": 10},
                        "final_ranks": {"p0": 3, "p1": 1},
                    },
                )
            ],
            completed=True,
        ),
    ]
    metrics = evaluate_r2d2_v2.metrics_from_records(records)
    if metrics.wins != 1 or metrics.losses != 1:
        raise AssertionError(f"win/loss aggregation wrong: {metrics}")
    if metrics.win_rate != 0.5:
        raise AssertionError(f"win rate wrong: {metrics.win_rate}")
    if metrics.final_ranks != [1, 3] or metrics.average_final_rank != 2.0:
        raise AssertionError(f"rank aggregation wrong: {metrics}")
    if metrics.final_scores_p0 != [12.0, 44.0] or metrics.average_final_score_p0 != 28.0:
        raise AssertionError(f"score aggregation wrong: {metrics}")
    if metrics.successful_dutch_calls != 1 or metrics.failed_dutch_calls != 1:
        raise AssertionError(f"dutch result split wrong: {metrics}")
    if metrics.episode_done_reasons != {"round_end": 1, "completed": 1}:
        raise AssertionError(f"done reasons wrong: {metrics.episode_done_reasons}")


def test_metrics_detect_draws_when_final_ranks_tie() -> None:
    records = [
        FakeRecord(
            transitions=[
                FakeTransition(
                    reward=1.0,
                    info={
                        "rank": 1,
                        "final_ranks": {"p0": 1, "p1": 1, "p2": 3},
                    },
                )
            ],
            completed=True,
        )
    ]
    metrics = evaluate_r2d2_v2.metrics_from_records(records)
    if metrics.draws != 1:
        raise AssertionError(f"draw count wrong: {metrics.draws}")


def test_reached_max_steps_is_counted_from_record_flag() -> None:
    records = [
        FakeRecord(transitions=[FakeTransition(reward=0.0)], completed=False, truncated_by_max_steps=True)
    ]
    metrics = evaluate_r2d2_v2.metrics_from_records(records)
    if metrics.reached_max_steps != 1:
        raise AssertionError(f"max step count wrong: {metrics.reached_max_steps}")
    if metrics.episode_done_reasons != {"max_steps": 1}:
        raise AssertionError(f"done reason wrong: {metrics.episode_done_reasons}")


def test_run_evaluation_calls_model_and_random_pipelines() -> None:
    calls: list[str] = []

    def infer_fn(*args: Any, **kwargs: Any) -> list[FakeRecord]:
        del args, kwargs
        calls.append("infer")
        return _records("model", reward=1.0)

    def collect_fn(*args: Any, **kwargs: Any) -> list[FakeRecord]:
        del args, kwargs
        calls.append("collect")
        return _records("random", reward=0.0)

    with tempfile.TemporaryDirectory() as tmp:
        checkpoint = Path(tmp) / "model.pt"
        _checkpoint(checkpoint)
        summary = evaluate_r2d2_v2.run_evaluation_v2(
            evaluate_r2d2_v2.EvalConfigV2(
                checkpoint=checkpoint,
                episodes=1,
                max_steps=5,
                compare_random=True,
            ),
            runner_factory=FakeRunner,
            infer_fn=infer_fn,
            collect_fn=collect_fn,
        )

    if calls != ["infer", "collect"]:
        raise AssertionError(f"wrong pipeline order: {calls}")
    if summary.random is None or summary.random.total_steps != 2:
        raise AssertionError(f"random summary missing: {summary}")
    if summary.model.total_reward != 3.0:
        raise AssertionError(f"model reward wrong: {summary.model}")


def test_output_json_only_when_requested_and_not_no_save() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        checkpoint = Path(tmp) / "model.pt"
        summary_path = Path(tmp) / "summary.json"
        _checkpoint(checkpoint)
        evaluate_r2d2_v2.run_evaluation_v2(
            evaluate_r2d2_v2.EvalConfigV2(
                checkpoint=checkpoint,
                output_json=summary_path,
                no_save=True,
            ),
            runner_factory=FakeRunner,
            infer_fn=lambda *args, **kwargs: _records("model"),
        )
        if summary_path.exists():
            raise AssertionError("no_save should prevent writing the summary")

        evaluate_r2d2_v2.run_evaluation_v2(
            evaluate_r2d2_v2.EvalConfigV2(
                checkpoint=checkpoint,
                output_json=summary_path,
                no_save=False,
            ),
            runner_factory=FakeRunner,
            infer_fn=lambda *args, **kwargs: _records("model"),
        )
        if not summary_path.exists():
            raise AssertionError("summary file was not written")
        data = summary_path.read_text(encoding="utf-8")
        if (
            '"model"' not in data
            or '"random"' not in data
            or '"average_final_score_p0"' not in data
            or '"episode_done_reasons"' not in data
        ):
            raise AssertionError(f"summary content incomplete: {data}")


def test_random_policy_helper_chooses_only_legal_actions() -> None:
    import random

    obs = {
        "recent_events": [],
        "slot_stability": {},
        "legal_private_memory": {},
        "legal_action_v2": {
            "actions": [
                {"action_v2": {"action_type": "pass_tick"}, "legacy_action_id": 1},
                {
                    "action_v2": {"action_type": "match", "slot": 0},
                    "legacy_action_id": 2,
                },
            ]
        },
        "obs": {},
    }
    chosen = collect_rollouts_v2.choose_legal_action_v2(obs, random.Random(7))
    if chosen not in obs["legal_action_v2"]["actions"]:
        raise AssertionError(f"random policy chose illegal action: {chosen}")


def test_checkpoint_loader_requires_online_model() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        checkpoint = Path(tmp) / "bad.pt"
        torch.save({"not_online_model": {}}, checkpoint)
        try:
            evaluate_r2d2_v2.load_checkpoint_model_v2(checkpoint, device="cpu")
        except ValueError as exc:
            if "invalid R2D2 v2 checkpoint" not in str(exc):
                raise AssertionError(f"unexpected error: {exc}") from exc
        else:
            raise AssertionError("invalid checkpoint did not raise")


if __name__ == "__main__":
    test_parser_cli_works()
    test_parser_epsilon_schedule_flags()
    test_epsilon_schedule_passed_to_infer()
    test_refuses_missing_checkpoint()
    test_refuses_long_runs_without_allow_long_run()
    test_metrics_aggregate_steps_rewards_and_missing_wins()
    test_metrics_aggregate_terminal_results_when_exposed()
    test_metrics_detect_draws_when_final_ranks_tie()
    test_reached_max_steps_is_counted_from_record_flag()
    test_run_evaluation_calls_model_and_random_pipelines()
    test_output_json_only_when_requested_and_not_no_save()
    test_random_policy_helper_chooses_only_legal_actions()
    test_checkpoint_loader_requires_online_model()
    print("test_evaluate_r2d2_v2.py: ok")
