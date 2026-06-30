"""Minimal controlled training smoke for AgentInterface v2 R2D2 plumbing.

This is not a production learner. It only trains for a bounded number of steps
from an existing JSONL dataset to verify dataset -> replay -> learner wiring.
It never collects rollouts and never starts on import.
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
from pathlib import Path
import random
from typing import Any

import numpy as np
import torch

import dataset_v2
import learner_r2d2_v2
import model_r2d2_v2


MAX_SAFE_STEPS = 1000


@dataclass(frozen=True)
class TrainConfigV2:
    dataset: Path
    steps: int = 10
    batch_size: int = 4
    seq_len: int = 8
    burn_in: int = 4
    gamma: float = 0.99
    n_step: int = 3
    learning_rate: float = 1.0e-4
    target_update_interval: int = 10
    seed: int = 0
    device: str = "cpu"
    save_checkpoint: Path | None = None
    no_save: bool = True
    allow_long_run: bool = False


@dataclass(frozen=True)
class TrainResultV2:
    steps: int
    final_metrics: dict[str, float]
    checkpoint_path: str | None


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", type=str, required=True)
    parser.add_argument("--steps", type=int, default=10)
    parser.add_argument("--batch-size", type=int, default=4)
    parser.add_argument("--seq-len", type=int, default=8)
    parser.add_argument("--burn-in", type=int, default=4)
    parser.add_argument("--gamma", type=float, default=0.99)
    parser.add_argument("--n-step", type=int, default=3)
    parser.add_argument("--learning-rate", type=float, default=1.0e-4)
    parser.add_argument("--target-update-interval", type=int, default=10)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--device", type=str, default="cpu")
    parser.add_argument("--save-checkpoint", type=str, default=None)
    parser.add_argument("--no-save", action="store_true", default=True)
    parser.add_argument("--allow-save", action="store_true")
    parser.add_argument("--allow-long-run", action="store_true")
    return parser


def config_from_args(args: argparse.Namespace) -> TrainConfigV2:
    save_checkpoint = Path(args.save_checkpoint) if args.save_checkpoint else None
    return TrainConfigV2(
        dataset=Path(args.dataset),
        steps=int(args.steps),
        batch_size=int(args.batch_size),
        seq_len=int(args.seq_len),
        burn_in=int(args.burn_in),
        gamma=float(args.gamma),
        n_step=int(args.n_step),
        learning_rate=float(args.learning_rate),
        target_update_interval=int(args.target_update_interval),
        seed=int(args.seed),
        device=str(args.device),
        save_checkpoint=save_checkpoint,
        no_save=not bool(args.allow_save),
        allow_long_run=bool(args.allow_long_run),
    )


def run_training_smoke(config: TrainConfigV2) -> TrainResultV2:
    _validate_config(config)
    _seed_everything(config.seed)

    replay = dataset_v2.load_replay_buffer_from_jsonl(
        config.dataset,
        n_step=config.n_step,
        gamma=config.gamma,
    )
    _validate_replay_size(replay, config.batch_size)

    online_model = model_r2d2_v2.R2D2AgentV2()
    target_model = model_r2d2_v2.R2D2AgentV2()
    learner = learner_r2d2_v2.R2D2LearnerV2(
        online_model=online_model,
        target_model=target_model,
        config=learner_r2d2_v2.LearnerConfigV2(
            gamma=config.gamma,
            n_step=config.n_step,
            learning_rate=config.learning_rate,
            target_update_interval=config.target_update_interval,
            device=config.device,
        ),
    )

    final_metrics: dict[str, float] = {}
    for step in range(config.steps):
        batch = replay.sample_sequences(
            batch_size=config.batch_size,
            seq_len=config.seq_len,
            burn_in=config.burn_in,
            seed=config.seed + step,
        )
        final_metrics = learner.train_step(batch)
        print(
            "train_r2d2_v2 "
            f"step={step + 1}/{config.steps} "
            f"loss={final_metrics['loss']:.6f} "
            f"valid_steps={final_metrics['valid_steps']:.0f}"
        )

    checkpoint_path = None
    if config.save_checkpoint is not None and not config.no_save:
        checkpoint_path = str(config.save_checkpoint)
        _save_checkpoint(config.save_checkpoint, config, learner)

    return TrainResultV2(
        steps=config.steps,
        final_metrics=dict(final_metrics),
        checkpoint_path=checkpoint_path,
    )


def main(argv: list[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)
    config = config_from_args(args)
    result = run_training_smoke(config)
    print(
        "train_r2d2_v2 done: "
        f"steps={result.steps} checkpoint={result.checkpoint_path}"
    )
    return 0


def _validate_config(config: TrainConfigV2) -> None:
    if not config.dataset.exists():
        raise FileNotFoundError(f"dataset does not exist: {config.dataset}")
    if not config.dataset.is_file():
        raise ValueError(f"dataset is not a file: {config.dataset}")
    if config.steps <= 0:
        raise ValueError("steps must be positive")
    if config.steps > MAX_SAFE_STEPS and not config.allow_long_run:
        raise ValueError(
            f"refusing steps={config.steps}; pass --allow-long-run above {MAX_SAFE_STEPS}"
        )
    if config.batch_size <= 0:
        raise ValueError("batch_size must be positive")
    if config.seq_len <= 0:
        raise ValueError("seq_len must be positive")
    if config.burn_in < 0:
        raise ValueError("burn_in must be >= 0")
    if config.gamma < 0.0:
        raise ValueError("gamma must be >= 0")
    if config.n_step <= 0:
        raise ValueError("n_step must be positive")
    if config.learning_rate <= 0.0:
        raise ValueError("learning_rate must be positive")
    if config.target_update_interval <= 0:
        raise ValueError("target_update_interval must be positive")


def _validate_replay_size(replay: Any, batch_size: int) -> None:
    size = len(replay)
    if size <= 0:
        raise ValueError("replay buffer is empty")
    if size < batch_size:
        raise ValueError(
            f"replay buffer too small for batch_size={batch_size}: {size} transitions"
        )


def _seed_everything(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)


def _save_checkpoint(
    path: Path,
    config: TrainConfigV2,
    learner: learner_r2d2_v2.R2D2LearnerV2,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    torch.save(
        {
            "online_model": learner.online_model.state_dict(),
            "target_model": learner.target_model.state_dict(),
            "optimizer": learner.optimizer.state_dict(),
            "config": {
                **asdict(config),
                "dataset": str(config.dataset),
                "save_checkpoint": (
                    None if config.save_checkpoint is None else str(config.save_checkpoint)
                ),
            },
            "learner_state": {
                "step": learner.state.step,
                "last_loss": learner.state.last_loss,
                "metrics": dict(learner.state.metrics),
            },
        },
        path,
    )


if __name__ == "__main__":
    raise SystemExit(main())
