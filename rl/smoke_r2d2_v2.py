"""End-to-end smoke for the AgentInterface v2 R2D2 pipeline.

This script is intentionally bounded and temporary-artifact oriented. It checks:

collect real v2 rollouts -> train a few steps -> save/reload checkpoint -> infer

It is not a production training entrypoint and never runs on import.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
import shutil
import tempfile
from typing import Any, Callable, Iterator

import torch

import collect_rollouts_v2
import infer_r2d2_v2
import model_r2d2_v2
from runner_process import RunnerProcess
import schedules_v2
import train_r2d2_v2


MAX_SAFE_COLLECT_STEPS = 5000
MAX_SAFE_TRAIN_STEPS = 1000


@dataclass(frozen=True)
class SmokeConfigV2:
    output_dir: Path | None = None
    episodes: int = 1
    collect_max_steps: int = 100
    infer_max_steps: int = 20
    train_steps: int = 5
    batch_size: int = 2
    seq_len: int = 4
    burn_in: int = 2
    seed: int = 0
    players: int = 6
    epsilon: float = 0.0
    epsilon_start: float | None = None
    epsilon_end: float | None = None
    epsilon_steps: int | None = None
    keep_artifacts: bool = False
    device: str = "cpu"
    verbose: bool = False
    allow_long_run: bool = False


@dataclass(frozen=True)
class SmokeSummaryV2:
    artifact_dir: str
    kept_artifacts: bool
    dataset_path: str
    checkpoint_path: str
    collected_transitions: int
    train_steps: int
    infer_steps: int
    train_loss: float
    completed_collect_episodes: int
    completed_infer_episodes: int


CollectFn = Callable[..., list[Any]]
TrainFn = Callable[[train_r2d2_v2.TrainConfigV2], train_r2d2_v2.TrainResultV2]
InferFn = Callable[..., list[Any]]


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=str, default=None)
    parser.add_argument("--episodes", type=int, default=1)
    parser.add_argument("--collect-max-steps", type=int, default=100)
    parser.add_argument("--infer-max-steps", type=int, default=20)
    parser.add_argument("--train-steps", type=int, default=5)
    parser.add_argument("--batch-size", type=int, default=2)
    parser.add_argument("--seq-len", type=int, default=4)
    parser.add_argument("--burn-in", type=int, default=2)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--players", type=int, default=6)
    parser.add_argument("--epsilon", type=float, default=0.0)
    parser.add_argument("--epsilon-start", type=float, default=None)
    parser.add_argument("--epsilon-end", type=float, default=None)
    parser.add_argument("--epsilon-steps", type=int, default=None)
    parser.add_argument("--keep-artifacts", action="store_true")
    parser.add_argument("--device", type=str, default="cpu")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--allow-long-run", action="store_true")
    return parser


def config_from_args(args: argparse.Namespace) -> SmokeConfigV2:
    return SmokeConfigV2(
        output_dir=Path(args.output_dir) if args.output_dir else None,
        episodes=int(args.episodes),
        collect_max_steps=int(args.collect_max_steps),
        infer_max_steps=int(args.infer_max_steps),
        train_steps=int(args.train_steps),
        batch_size=int(args.batch_size),
        seq_len=int(args.seq_len),
        burn_in=int(args.burn_in),
        seed=int(args.seed),
        players=int(args.players),
        epsilon=float(args.epsilon),
        epsilon_start=(None if args.epsilon_start is None else float(args.epsilon_start)),
        epsilon_end=(None if args.epsilon_end is None else float(args.epsilon_end)),
        epsilon_steps=(None if args.epsilon_steps is None else int(args.epsilon_steps)),
        keep_artifacts=bool(args.keep_artifacts),
        device=str(args.device),
        verbose=bool(args.verbose),
        allow_long_run=bool(args.allow_long_run),
    )


def run_smoke_v2(
    config: SmokeConfigV2,
    *,
    runner_factory: Callable[[int], Any] | None = None,
    collect_fn: CollectFn = collect_rollouts_v2.collect_rollouts_v2,
    train_fn: TrainFn = train_r2d2_v2.run_training_smoke,
    infer_fn: InferFn = infer_r2d2_v2.infer_rollouts_v2,
) -> SmokeSummaryV2:
    _validate_config(config)
    epsilon_schedule = schedules_v2.build_optional_schedule(
        config.epsilon_start,
        config.epsilon_end,
        config.epsilon_steps,
        name="epsilon",
        minimum=0.0,
        maximum=1.0,
    )
    runner_factory = runner_factory or (lambda max_turns: RunnerProcess(max_turns=max_turns))

    with _artifact_dir(config) as artifact_dir:
        dataset_path = artifact_dir / "rollouts_v2.jsonl"
        checkpoint_path = artifact_dir / "r2d2_v2_smoke.pt"

        with runner_factory(max(config.collect_max_steps, 1)) as runner:
            collect_records = collect_fn(
                runner,
                episodes=config.episodes,
                seed=config.seed,
                max_steps=config.collect_max_steps,
                out=dataset_path,
                save=True,
                players=config.players,
                verbose=config.verbose,
            )
        collected_transitions = _count_transitions(collect_records)
        if collected_transitions <= 0:
            raise RuntimeError("collect step produced zero transitions")
        if not dataset_path.exists() or dataset_path.stat().st_size == 0:
            raise RuntimeError(f"collect step did not write dataset: {dataset_path}")

        train_result = train_fn(
            train_r2d2_v2.TrainConfigV2(
                dataset=dataset_path,
                steps=config.train_steps,
                batch_size=config.batch_size,
                seq_len=config.seq_len,
                burn_in=config.burn_in,
                seed=config.seed,
                device=config.device,
                save_checkpoint=checkpoint_path,
                no_save=False,
                allow_long_run=config.allow_long_run,
            )
        )
        if train_result.checkpoint_path is None:
            raise RuntimeError("training smoke did not report a checkpoint path")
        if not checkpoint_path.exists():
            raise RuntimeError(f"training smoke did not write checkpoint: {checkpoint_path}")

        model = _load_checkpoint_model(checkpoint_path, device=config.device)
        with runner_factory(max(config.infer_max_steps, 1)) as runner:
            infer_records = infer_fn(
                runner,
                model,
                episodes=1,
                seed=config.seed,
                max_steps=config.infer_max_steps,
                epsilon=config.epsilon,
                epsilon_schedule=epsilon_schedule,
                players=config.players,
                verbose=config.verbose,
            )
        infer_steps = _count_transitions(infer_records)
        if infer_steps <= 0:
            raise RuntimeError("inference smoke produced zero transitions")

        return SmokeSummaryV2(
            artifact_dir=str(artifact_dir),
            kept_artifacts=config.keep_artifacts,
            dataset_path=str(dataset_path),
            checkpoint_path=str(checkpoint_path),
            collected_transitions=collected_transitions,
            train_steps=int(train_result.steps),
            infer_steps=infer_steps,
            train_loss=float(train_result.final_metrics.get("loss", float("nan"))),
            completed_collect_episodes=_count_completed(collect_records),
            completed_infer_episodes=_count_completed(infer_records),
        )


def main(argv: list[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)
    summary = run_smoke_v2(config_from_args(args))
    print(
        "smoke_r2d2_v2 done: "
        f"collected={summary.collected_transitions} "
        f"train_steps={summary.train_steps} "
        f"infer_steps={summary.infer_steps} "
        f"loss={summary.train_loss:.6f} "
        f"artifacts={'kept' if summary.kept_artifacts else 'removed'}"
    )
    if summary.kept_artifacts:
        print(f"artifact_dir={summary.artifact_dir}")
    return 0


def _validate_config(config: SmokeConfigV2) -> None:
    if config.episodes <= 0:
        raise ValueError("episodes must be positive")
    if config.collect_max_steps <= 0:
        raise ValueError("collect_max_steps must be positive")
    if config.infer_max_steps <= 0:
        raise ValueError("infer_max_steps must be positive")
    if config.train_steps <= 0:
        raise ValueError("train_steps must be positive")
    if config.collect_max_steps > MAX_SAFE_COLLECT_STEPS and not config.allow_long_run:
        raise ValueError(
            f"refusing collect_max_steps={config.collect_max_steps}; "
            f"pass --allow-long-run above {MAX_SAFE_COLLECT_STEPS}"
        )
    if config.train_steps > MAX_SAFE_TRAIN_STEPS and not config.allow_long_run:
        raise ValueError(
            f"refusing train_steps={config.train_steps}; "
            f"pass --allow-long-run above {MAX_SAFE_TRAIN_STEPS}"
        )
    if config.batch_size <= 0:
        raise ValueError("batch_size must be positive")
    if config.seq_len <= 0:
        raise ValueError("seq_len must be positive")
    if config.burn_in < 0:
        raise ValueError("burn_in must be >= 0")
    if config.players <= 0:
        raise ValueError("players must be positive")
    if not 0.0 <= config.epsilon <= 1.0:
        raise ValueError("epsilon must be between 0 and 1")
    if config.keep_artifacts and config.output_dir is None:
        raise ValueError("--keep-artifacts requires --output-dir")


@contextmanager
def _artifact_dir(config: SmokeConfigV2) -> Iterator[Path]:
    if config.keep_artifacts:
        assert config.output_dir is not None
        target = config.output_dir
        target.mkdir(parents=True, exist_ok=True)
        yield target
        return

    root = Path(tempfile.mkdtemp(prefix="dutch_r2d2_v2_smoke_"))
    try:
        yield root
    finally:
        shutil.rmtree(root, ignore_errors=True)


def _load_checkpoint_model(path: Path, *, device: str) -> model_r2d2_v2.R2D2AgentV2:
    payload = torch.load(path, map_location=device)
    if not isinstance(payload, dict) or "online_model" not in payload:
        raise RuntimeError(f"invalid checkpoint payload: {path}")
    model = model_r2d2_v2.R2D2AgentV2()
    model.load_state_dict(payload["online_model"])
    model.to(torch.device(device))
    model.eval()
    return model


def _count_transitions(records: list[Any]) -> int:
    return sum(len(getattr(record, "transitions", [])) for record in records)


def _count_completed(records: list[Any]) -> int:
    return sum(1 for record in records if bool(getattr(record, "completed", False)))


if __name__ == "__main__":
    raise SystemExit(main())
