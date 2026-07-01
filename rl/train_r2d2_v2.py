"""Minimal controlled training smoke for AgentInterface v2 R2D2 plumbing.

This is not a production learner. It only trains for a bounded number of steps
from an existing JSONL dataset to verify dataset -> replay -> learner wiring.
It never collects rollouts and never starts on import.
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import random
from typing import Any

import numpy as np
import torch

import dataset_v2
import learner_r2d2_v2
import model_r2d2_v2
import schedules_v2


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
    double_q: bool = False
    prioritized_replay: bool = False
    priority_alpha: float = 0.6
    priority_beta: float = 0.4
    priority_epsilon: float = 1.0e-6
    priority_eta: float = 0.9
    # Optional linear annealing for priority_beta. When the three are set the
    # schedule overrides the constant priority_beta at sample time. Requires
    # prioritized_replay (otherwise beta would not influence anything).
    priority_beta_start: float | None = None
    priority_beta_end: float | None = None
    priority_beta_steps: int | None = None
    seed: int = 0
    device: str = "cpu"
    save_checkpoint: Path | None = None
    no_save: bool = True
    allow_long_run: bool = False
    # Optional per-step metrics export (JSONL, one line per train step). This is
    # diagnostics only: it is independent from the checkpoint save guard and is
    # written wherever the caller points it (intended: a run dir outside the repo).
    metrics_out: Path | None = None
    # Optional resume: load network (+ optimizer if present) from an existing
    # checkpoint before training. None => train from scratch (unchanged). Used for
    # sequential curriculum (P1 -> P2 -> P3). Does not touch reward or dataset.
    resume_from: Path | None = None


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
    parser.add_argument("--double-q", action="store_true")
    parser.add_argument("--prioritized-replay", action="store_true")
    parser.add_argument("--priority-alpha", type=float, default=0.6)
    parser.add_argument("--priority-beta", type=float, default=0.4)
    parser.add_argument("--priority-epsilon", type=float, default=1.0e-6)
    parser.add_argument("--priority-eta", type=float, default=0.9)
    parser.add_argument("--priority-beta-start", type=float, default=None)
    parser.add_argument("--priority-beta-end", type=float, default=None)
    parser.add_argument("--priority-beta-steps", type=int, default=None)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--device", type=str, default="cpu")
    parser.add_argument("--save-checkpoint", type=str, default=None)
    parser.add_argument("--no-save", action="store_true", default=True)
    parser.add_argument("--allow-save", action="store_true")
    parser.add_argument("--allow-long-run", action="store_true")
    parser.add_argument("--metrics-out", type=str, default=None)
    parser.add_argument(
        "--resume-from",
        type=str,
        default=None,
        help="resume network (+ optimizer if present) from this checkpoint "
        "before training (sequential curriculum). Omit = train from scratch.",
    )
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
        double_q=bool(args.double_q),
        prioritized_replay=bool(args.prioritized_replay),
        priority_alpha=float(args.priority_alpha),
        priority_beta=float(args.priority_beta),
        priority_epsilon=float(args.priority_epsilon),
        priority_eta=float(args.priority_eta),
        priority_beta_start=(
            None if args.priority_beta_start is None else float(args.priority_beta_start)
        ),
        priority_beta_end=(
            None if args.priority_beta_end is None else float(args.priority_beta_end)
        ),
        priority_beta_steps=(
            None if args.priority_beta_steps is None else int(args.priority_beta_steps)
        ),
        seed=int(args.seed),
        device=str(args.device),
        save_checkpoint=save_checkpoint,
        no_save=not bool(args.allow_save),
        allow_long_run=bool(args.allow_long_run),
        metrics_out=Path(args.metrics_out) if args.metrics_out else None,
        resume_from=Path(args.resume_from) if args.resume_from else None,
    )


def run_training_smoke(config: TrainConfigV2) -> TrainResultV2:
    _validate_config(config)
    _seed_everything(config.seed)

    replay = dataset_v2.load_replay_buffer_from_jsonl(
        config.dataset,
        n_step=config.n_step,
        gamma=config.gamma,
        prioritized=config.prioritized_replay,
        priority_alpha=config.priority_alpha,
        priority_beta=config.priority_beta,
        priority_epsilon=config.priority_epsilon,
    )
    _validate_replay_size(replay, config.batch_size)

    beta_schedule = schedules_v2.build_optional_schedule(
        config.priority_beta_start,
        config.priority_beta_end,
        config.priority_beta_steps,
        name="priority-beta",
        minimum=0.0,
    )
    if beta_schedule is not None and not config.prioritized_replay:
        raise ValueError(
            "priority-beta schedule requires --prioritized-replay (beta only "
            "affects prioritized importance weights)"
        )

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
            double_q=config.double_q,
            priority_eta=config.priority_eta,
            device=config.device,
        ),
    )

    if config.resume_from is not None:
        _resume_from_checkpoint(learner, config.resume_from, config.device)

    metrics_file = None
    if config.metrics_out is not None:
        config.metrics_out.parent.mkdir(parents=True, exist_ok=True)
        metrics_file = config.metrics_out.open("w", encoding="utf-8")

    final_metrics: dict[str, float] = {}
    try:
        for step in range(config.steps):
            beta_current = (
                config.priority_beta
                if beta_schedule is None
                else beta_schedule.value_at(step)
            )
            batch = replay.sample_sequences(
                batch_size=config.batch_size,
                seq_len=config.seq_len,
                burn_in=config.burn_in,
                seed=config.seed + step,
                beta=beta_current,
            )
            final_metrics = learner.train_step(batch, replay_buffer=replay)
            # The annealed beta is applied at sample time above and therefore
            # really shapes the importance weights consumed by this train_step.
            final_metrics["priority_beta_current"] = float(beta_current)
            final_metrics["schedule_step"] = float(step)
            if metrics_file is not None:
                metrics_file.write(json.dumps({"step": step, **final_metrics}) + "\n")
                metrics_file.flush()
            print(
                "train_r2d2_v2 "
                f"step={step + 1}/{config.steps} "
                f"loss={final_metrics['loss']:.6f} "
                f"valid_steps={final_metrics['valid_steps']:.0f} "
                f"beta={beta_current:.4f}"
            )
    finally:
        if metrics_file is not None:
            metrics_file.close()

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
    if config.resume_from is not None:
        if not config.resume_from.exists():
            raise FileNotFoundError(
                f"resume checkpoint does not exist: {config.resume_from}"
            )
        if not config.resume_from.is_file():
            raise ValueError(
                f"resume checkpoint is not a file: {config.resume_from}"
            )
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
    if config.priority_alpha < 0.0:
        raise ValueError("priority_alpha must be >= 0")
    if config.priority_beta < 0.0:
        raise ValueError("priority_beta must be >= 0")
    if config.priority_epsilon <= 0.0:
        raise ValueError("priority_epsilon must be positive")
    if not 0.0 <= config.priority_eta <= 1.0:
        raise ValueError("priority_eta must be between 0 and 1")


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


def _resume_from_checkpoint(
    learner: learner_r2d2_v2.R2D2LearnerV2,
    path: Path,
    device: str,
) -> None:
    """Load network (+ optimizer/step if present) from an existing checkpoint.

    Restores the online and target networks. The optimizer state is restored only
    if the checkpoint contains it (checkpoints written by ``_save_checkpoint`` do);
    otherwise a fresh optimizer is kept and a clear notice is printed. Raises a
    clear error if the checkpoint is unreadable or missing the network weights.
    Reward and dataset are untouched.
    """

    try:
        ckpt = torch.load(path, map_location=device, weights_only=True)
    except Exception as exc:  # noqa: BLE001
        raise ValueError(
            f"invalid resume checkpoint {path}: cannot torch.load ({exc})"
        ) from exc
    if not isinstance(ckpt, dict) or "online_model" not in ckpt:
        raise ValueError(
            f"invalid resume checkpoint {path}: missing 'online_model' state_dict"
        )

    learner.online_model.load_state_dict(ckpt["online_model"])
    if "target_model" in ckpt:
        learner.target_model.load_state_dict(ckpt["target_model"])
    else:
        # No target snapshot: mirror the online weights (standard init).
        learner.target_model.load_state_dict(learner.online_model.state_dict())
    learner.target_model.eval()

    if "optimizer" in ckpt:
        learner.optimizer.load_state_dict(ckpt["optimizer"])
        opt_note = "optimizer restored"
    else:
        opt_note = "optimizer NOT in checkpoint -> fresh optimizer"

    resumed_step = 0
    learner_state = ckpt.get("learner_state")
    if isinstance(learner_state, dict) and isinstance(learner_state.get("step"), int):
        learner.state.step = int(learner_state["step"])
        resumed_step = learner.state.step

    print(
        f"train_r2d2_v2 resumed from {path}: networks restored, {opt_note}, "
        f"learner_step={resumed_step}"
    )


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
            # Stringify EVERY Path field (dataset, save_checkpoint, metrics_out,
            # resume_from, …) so the checkpoint stays loadable under
            # torch.load(weights_only=True) — a pickled PosixPath is rejected.
            "config": {
                k: (str(v) if isinstance(v, Path) else v)
                for k, v in asdict(config).items()
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
