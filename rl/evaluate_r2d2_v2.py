"""Controlled v2 evaluation smoke for random legal policy vs R2D2 checkpoint.

This is a small benchmark harness, not a full evaluation suite. It keeps runs
bounded, never trains, and saves only a compact JSON summary when explicitly
requested.
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path
from typing import Any, Callable

import torch

import collect_rollouts_v2
import infer_r2d2_v2
import model_r2d2_v2
from runner_process import RunnerProcess


MAX_SAFE_EPISODES = 100
MAX_SAFE_STEPS = 5000


@dataclass(frozen=True)
class EvalConfigV2:
    checkpoint: Path
    episodes: int = 5
    max_steps: int = 200
    players: int = 6
    seed: int = 0
    epsilon: float = 0.0
    compare_random: bool = False
    device: str = "cpu"
    output_json: Path | None = None
    no_save: bool = False
    allow_long_run: bool = False


@dataclass(frozen=True)
class PolicyMetricsV2:
    episodes: int
    completed_episodes: int
    total_steps: int
    average_steps: float
    average_episode_length: float
    total_reward: float
    average_reward: float
    dutch_calls: int
    successful_dutch_calls: int | None
    failed_dutch_calls: int | None
    wins: int | None
    losses: int | None
    draws: int | None
    win_rate: float | None
    final_ranks: list[int] | None
    average_final_rank: float | None
    final_scores_p0: list[float] | None
    average_final_score_p0: float | None
    episode_done_reasons: dict[str, int]
    reached_max_steps: int
    illegal_action_errors: int
    completed_without_crash: bool


@dataclass(frozen=True)
class EvaluationSummaryV2:
    model: PolicyMetricsV2
    random: PolicyMetricsV2 | None
    checkpoint: str
    seed: int
    output_json: str | None


InferFn = Callable[..., list[Any]]
CollectFn = Callable[..., list[Any]]


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", type=str, required=True)
    parser.add_argument("--episodes", type=int, default=5)
    parser.add_argument("--max-steps", type=int, default=200)
    parser.add_argument("--players", type=int, default=6)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--epsilon", type=float, default=0.0)
    parser.add_argument("--compare-random", action="store_true")
    parser.add_argument("--device", type=str, default="cpu")
    parser.add_argument("--output-json", type=str, default=None)
    parser.add_argument("--no-save", action="store_true")
    parser.add_argument("--allow-long-run", action="store_true")
    return parser


def config_from_args(args: argparse.Namespace) -> EvalConfigV2:
    return EvalConfigV2(
        checkpoint=Path(args.checkpoint),
        episodes=int(args.episodes),
        max_steps=int(args.max_steps),
        players=int(args.players),
        seed=int(args.seed),
        epsilon=float(args.epsilon),
        compare_random=bool(args.compare_random),
        device=str(args.device),
        output_json=Path(args.output_json) if args.output_json else None,
        no_save=bool(args.no_save),
        allow_long_run=bool(args.allow_long_run),
    )


def run_evaluation_v2(
    config: EvalConfigV2,
    *,
    runner_factory: Callable[[int], Any] | None = None,
    infer_fn: InferFn = infer_r2d2_v2.infer_rollouts_v2,
    collect_fn: CollectFn = collect_rollouts_v2.collect_rollouts_v2,
) -> EvaluationSummaryV2:
    _validate_config(config)
    runner_factory = runner_factory or (lambda max_turns: RunnerProcess(max_turns=max_turns))
    model = load_checkpoint_model_v2(config.checkpoint, device=config.device)

    try:
        with runner_factory(max(config.max_steps, 1)) as runner:
            model_records = infer_fn(
                runner,
                model,
                episodes=config.episodes,
                seed=config.seed,
                max_steps=config.max_steps,
                epsilon=config.epsilon,
                players=config.players,
                verbose=False,
            )
        model_metrics = metrics_from_records(model_records)
    except Exception:
        model_metrics = _crash_metrics(config.episodes)
        raise

    random_metrics = None
    if config.compare_random:
        with runner_factory(max(config.max_steps, 1)) as runner:
            random_records = collect_fn(
                runner,
                episodes=config.episodes,
                seed=config.seed,
                max_steps=config.max_steps,
                players=config.players,
                verbose=False,
            )
        random_metrics = metrics_from_records(random_records)

    summary = EvaluationSummaryV2(
        model=model_metrics,
        random=random_metrics,
        checkpoint=str(config.checkpoint),
        seed=config.seed,
        output_json=(None if config.output_json is None else str(config.output_json)),
    )
    if config.output_json is not None and not config.no_save:
        _write_summary_json(config.output_json, summary)
    return summary


def load_checkpoint_model_v2(path: Path, *, device: str) -> model_r2d2_v2.R2D2AgentV2:
    if not path.exists():
        raise FileNotFoundError(f"checkpoint does not exist: {path}")
    payload = torch.load(path, map_location=device)
    if not isinstance(payload, dict) or "online_model" not in payload:
        raise ValueError(f"invalid R2D2 v2 checkpoint: {path}")
    model = model_r2d2_v2.R2D2AgentV2()
    model.load_state_dict(payload["online_model"])
    model.to(torch.device(device))
    model.eval()
    return model


def metrics_from_records(records: list[Any]) -> PolicyMetricsV2:
    episodes = len(records)
    completed = sum(1 for record in records if bool(getattr(record, "completed", False)))
    transitions = [
        transition
        for record in records
        for transition in list(getattr(record, "transitions", []))
    ]
    total_steps = len(transitions)
    total_reward = sum(float(getattr(transition, "reward", 0.0)) for transition in transitions)
    terminal_infos = _terminal_infos(records)
    wins = _extract_wins(terminal_infos)
    losses = _extract_losses(terminal_infos)
    final_ranks = _extract_final_ranks(terminal_infos)
    final_scores = _extract_final_scores_p0(terminal_infos)
    successful_dutch, failed_dutch = _extract_dutch_results(terminal_infos)
    completed_with_results = None if wins is None else max(wins + (losses or 0), 0)
    return PolicyMetricsV2(
        episodes=episodes,
        completed_episodes=completed,
        total_steps=total_steps,
        average_episode_length=(float(total_steps) / episodes if episodes else 0.0),
        average_steps=(float(total_steps) / episodes if episodes else 0.0),
        total_reward=float(total_reward),
        average_reward=(float(total_reward) / episodes if episodes else 0.0),
        dutch_calls=_count_dutch_calls(transitions),
        successful_dutch_calls=successful_dutch,
        failed_dutch_calls=failed_dutch,
        wins=wins,
        losses=losses,
        draws=_extract_draws(terminal_infos),
        win_rate=(
            None
            if wins is None or not completed_with_results
            else float(wins) / float(completed_with_results)
        ),
        final_ranks=final_ranks,
        average_final_rank=_average(final_ranks),
        final_scores_p0=final_scores,
        average_final_score_p0=_average(final_scores),
        episode_done_reasons=_episode_done_reasons(records),
        reached_max_steps=sum(
            1 for record in records if bool(getattr(record, "truncated_by_max_steps", False))
        ),
        illegal_action_errors=0,
        completed_without_crash=True,
    )


def main(argv: list[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)
    summary = run_evaluation_v2(config_from_args(args))
    print(
        "evaluate_r2d2_v2: "
        f"model_steps={summary.model.total_steps} "
        f"model_reward={summary.model.total_reward:.3f} "
        f"model_wins={summary.model.wins} "
        f"model_win_rate={summary.model.win_rate} "
        f"model_avg_final_score={summary.model.average_final_score_p0} "
        f"random_steps={None if summary.random is None else summary.random.total_steps} "
        f"random_wins={None if summary.random is None else summary.random.wins} "
        f"saved={summary.output_json is not None and not args.no_save}"
    )
    return 0


def _validate_config(config: EvalConfigV2) -> None:
    if not config.checkpoint.exists():
        raise FileNotFoundError(f"checkpoint does not exist: {config.checkpoint}")
    if config.episodes <= 0:
        raise ValueError("episodes must be positive")
    if config.episodes > MAX_SAFE_EPISODES and not config.allow_long_run:
        raise ValueError(
            f"refusing episodes={config.episodes}; pass --allow-long-run above "
            f"{MAX_SAFE_EPISODES}"
        )
    if config.max_steps <= 0:
        raise ValueError("max_steps must be positive")
    if config.max_steps > MAX_SAFE_STEPS and not config.allow_long_run:
        raise ValueError(
            f"refusing max_steps={config.max_steps}; pass --allow-long-run above "
            f"{MAX_SAFE_STEPS}"
        )
    if config.players <= 0:
        raise ValueError("players must be positive")
    if not 0.0 <= config.epsilon <= 1.0:
        raise ValueError("epsilon must be between 0 and 1")


def _write_summary_json(path: Path, summary: EvaluationSummaryV2) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(_summary_to_json(summary), indent=2), encoding="utf-8")


def _summary_to_json(summary: EvaluationSummaryV2) -> dict[str, Any]:
    return {
        "model": asdict(summary.model),
        "random": None if summary.random is None else asdict(summary.random),
        "checkpoint": summary.checkpoint,
        "seed": summary.seed,
    }


def _count_dutch_calls(transitions: list[Any]) -> int:
    count = 0
    for transition in transitions:
        action = getattr(transition, "action_v2", None)
        if isinstance(action, dict) and action.get("action_type") == "call_dutch":
            count += 1
        obs = getattr(transition, "obs_raw", {}) or {}
        for event in obs.get("recent_events") or []:
            if isinstance(event, dict) and event.get("event_type") == "dutch_call":
                count += 1
    return count


def _terminal_infos(records: list[Any]) -> list[dict[str, Any]]:
    infos: list[dict[str, Any]] = []
    for record in records:
        transitions = list(getattr(record, "transitions", []))
        if not transitions:
            continue
        info = getattr(transitions[-1], "info", {}) or {}
        if isinstance(info, dict):
            infos.append(info)
    return infos


def _extract_wins(infos: list[dict[str, Any]]) -> int | None:
    values: list[bool] = []
    for info in infos:
        for key in ["won", "win", "is_winner"]:
            if key in info and isinstance(info[key], bool):
                values.append(bool(info[key]))
                break
        else:
            rank = _rank_from_info(info)
            if rank is not None:
                values.append(rank == 1)
    if not values:
        return None
    return sum(1 for value in values if value)


def _extract_losses(infos: list[dict[str, Any]]) -> int | None:
    values: list[bool] = []
    for info in infos:
        won = _won_from_info(info)
        if won is not None:
            values.append(not won)
            continue
        rank = _rank_from_info(info)
        if rank is not None:
            values.append(rank != 1)
    if not values:
        return None
    return sum(1 for value in values if value)


def _extract_draws(infos: list[dict[str, Any]]) -> int | None:
    values: list[bool] = []
    for info in infos:
        rank = _rank_from_info(info)
        ranks = info.get("final_ranks")
        if rank is None or not isinstance(ranks, dict):
            continue
        values.append(sum(1 for value in ranks.values() if value == rank) > 1)
    if not values:
        return None
    return sum(1 for value in values if value)


def _extract_final_ranks(infos: list[dict[str, Any]]) -> list[int] | None:
    values = [rank for info in infos if (rank := _rank_from_info(info)) is not None]
    return values or None


def _extract_final_scores_p0(infos: list[dict[str, Any]]) -> list[float] | None:
    values: list[float] = []
    for info in infos:
        scores = info.get("final_scores")
        if isinstance(scores, dict):
            raw = scores.get("p0") if "p0" in scores else scores.get("principal")
            if isinstance(raw, (int, float)):
                values.append(float(raw))
    return values or None


def _extract_dutch_results(
    infos: list[dict[str, Any]],
) -> tuple[int | None, int | None]:
    values: list[bool] = []
    for info in infos:
        called = info.get("called_dutch")
        if not isinstance(called, bool) or not called:
            continue
        won = _won_from_info(info)
        if won is not None:
            values.append(won)
    if not values:
        return None, None
    return (
        sum(1 for value in values if value),
        sum(1 for value in values if not value),
    )


def _episode_done_reasons(records: list[Any]) -> dict[str, int]:
    reasons: dict[str, int] = {}
    for record in records:
        transitions = list(getattr(record, "transitions", []))
        info = getattr(transitions[-1], "info", {}) if transitions else {}
        reason = None
        if isinstance(info, dict):
            raw = info.get("done_reason") or info.get("episode_done_reason")
            if isinstance(raw, str) and raw:
                reason = raw
        if reason is None:
            reason = (
                "max_steps"
                if bool(getattr(record, "truncated_by_max_steps", False))
                else "completed"
                if bool(getattr(record, "completed", False))
                else "unknown"
            )
        reasons[reason] = reasons.get(reason, 0) + 1
    return reasons


def _won_from_info(info: dict[str, Any]) -> bool | None:
    for key in ["won", "win", "is_winner"]:
        value = info.get(key)
        if isinstance(value, bool):
            return value
    return None


def _rank_from_info(info: dict[str, Any]) -> int | None:
    value = info.get("rank") or info.get("final_rank")
    return int(value) if isinstance(value, int) else None


def _average(values: list[int] | list[float] | None) -> float | None:
    if not values:
        return None
    return float(sum(values)) / float(len(values))


def _crash_metrics(episodes: int) -> PolicyMetricsV2:
    return PolicyMetricsV2(
        episodes=episodes,
        completed_episodes=0,
        total_steps=0,
        average_steps=0.0,
        average_episode_length=0.0,
        total_reward=0.0,
        average_reward=0.0,
        dutch_calls=0,
        successful_dutch_calls=None,
        failed_dutch_calls=None,
        wins=None,
        losses=None,
        draws=None,
        win_rate=None,
        final_ranks=None,
        average_final_rank=None,
        final_scores_p0=None,
        average_final_score_p0=None,
        episode_done_reasons={"crash": 1},
        reached_max_steps=0,
        illegal_action_errors=1,
        completed_without_crash=False,
    )


if __name__ == "__main__":
    raise SystemExit(main())
