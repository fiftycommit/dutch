"""Entraînement PPO masqué avec Self-Imitation Learning isolé.

Ce script ne remplace pas ``train_parallel.py`` et ne doit pas être utilisé par
le run en cours. Il recopie localement les helpers de training nécessaires pour
éviter une dépendance fragile au script principal actif.
"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

import numpy as np
from sb3_contrib.common.wrappers import ActionMasker
from stable_baselines3.common.callbacks import BaseCallback, CallbackList, CheckpointCallback
from stable_baselines3.common.monitor import Monitor
from stable_baselines3.common.vec_env import SubprocVecEnv

from dutch_env import DutchEnv
from self_imitation_buffer import SelfImitationBuffer
from self_imitation_callback import SelfImitationCallback
from self_imitation_ppo import SelfImitationPPO


def _mask_fn(env: ActionMasker) -> np.ndarray:
    return env.action_masks()


def _make_env(worker_idx: int, curriculum_hard_ratio: float = 0.0):
    def _init():
        base = DutchEnv(
            seed_start=worker_idx * 100_000,
            curriculum_hard_ratio=curriculum_hard_ratio,
        )
        return Monitor(ActionMasker(base, _mask_fn))

    return _init


class SelfImitationFailureCountersCallback(BaseCallback):
    """Surveillance minimale locale, sans importer le script principal."""

    def __init__(
        self,
        *,
        internal_error_threshold: int,
        recoverable_error_window: int,
        recoverable_error_threshold: int,
        log_every_steps: int = 10_000,
    ) -> None:
        super().__init__()
        self.internal_error_threshold = internal_error_threshold
        self.recoverable_error_window = recoverable_error_window
        self.recoverable_error_threshold = recoverable_error_threshold
        self.log_every_steps = log_every_steps
        self.engine_internal_errors = 0
        self.engine_recoverable_errors = 0
        self.runner_crashes = 0
        self.runner_timeouts = 0
        self._recoverable_window: deque[int] = deque()
        self._next_log_step = 0

    def _on_training_start(self) -> None:
        self._next_log_step = self.log_every_steps

    def _on_step(self) -> bool:
        for info in self.locals.get("infos", []):
            if info.get("engine_internal_error"):
                self.engine_internal_errors += 1
            if info.get("engine_recoverable_error"):
                self.engine_recoverable_errors += 1
                self._recoverable_window.append(self.num_timesteps)
            if info.get("runner_crashed"):
                self.runner_crashes += 1
            if info.get("runner_timeout"):
                self.runner_timeouts += 1

        if self.num_timesteps >= self._next_log_step:
            self.logger.record("failures/engine_internal_errors", self.engine_internal_errors)
            self.logger.record("failures/engine_recoverable_errors", self.engine_recoverable_errors)
            self.logger.record("failures/runner_crashes", self.runner_crashes)
            self.logger.record("failures/runner_timeouts", self.runner_timeouts)
            while self._next_log_step <= self.num_timesteps:
                self._next_log_step += self.log_every_steps

        if self.engine_internal_errors > self.internal_error_threshold:
            print(
                "Arrêt demandé : seuil engine_internal_error dépassé "
                f"({self.engine_internal_errors} > {self.internal_error_threshold})."
            )
            return False

        if self.recoverable_error_threshold > 0:
            cutoff = self.num_timesteps - self.recoverable_error_window
            while self._recoverable_window and self._recoverable_window[0] < cutoff:
                self._recoverable_window.popleft()
            if len(self._recoverable_window) > self.recoverable_error_threshold:
                print(
                    "Arrêt demandé : fréquence d'erreurs récupérables anormale "
                    f"({len(self._recoverable_window)} erreurs sur "
                    f"{self.recoverable_error_window} steps)."
                )
                return False
        return True


def _parse_args() -> argparse.Namespace:
    base = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser()
    parser.add_argument("--num-workers", type=int, default=4)
    parser.add_argument("--total-timesteps", type=int, default=5_000_000)
    parser.add_argument("--checkpoint-freq", type=int, default=200_000)
    parser.add_argument("--tensorboard-log-dir", type=Path, default=base / "runs_sil")
    parser.add_argument("--model-out", type=Path, default=base / "models_sil")
    parser.add_argument("--internal-error-threshold", type=int, default=8)
    parser.add_argument("--recoverable-error-window", type=int, default=200_000)
    parser.add_argument("--recoverable-error-threshold", type=int, default=50)
    parser.add_argument("--curriculum-hard-ratio", type=float, default=0.0)
    parser.add_argument("--resume-from", type=Path, default=None)
    parser.add_argument("--bc-coef", type=float, default=0.001)
    parser.add_argument("--bc-effective-loss-cap", type=float, default=0.005)
    parser.add_argument("--sil-buffer-size", type=int, default=50_000)
    parser.add_argument("--sil-min-episodes-per-context", type=int, default=3)
    parser.add_argument("--sil-batch-size", type=int, default=128)
    parser.add_argument("--disable-self-imitation", action="store_true")
    return parser.parse_args()


def _validate_args(args: argparse.Namespace) -> None:
    if args.num_workers <= 0:
        raise SystemExit("--num-workers doit être positif")
    if args.total_timesteps <= 0:
        raise SystemExit("--total-timesteps doit être positif")
    if args.checkpoint_freq <= 0:
        raise SystemExit("--checkpoint-freq doit être positif")
    if args.internal_error_threshold < 0:
        raise SystemExit("--internal-error-threshold doit être >= 0")
    if args.recoverable_error_window <= 0:
        raise SystemExit("--recoverable-error-window doit être positif")
    if not 0.0 <= args.curriculum_hard_ratio <= 1.0:
        raise SystemExit("--curriculum-hard-ratio doit être dans [0, 1]")
    if args.bc_coef < 0:
        raise SystemExit("--bc-coef doit être >= 0")
    if args.bc_effective_loss_cap < 0:
        raise SystemExit("--bc-effective-loss-cap doit être >= 0")
    if args.sil_buffer_size <= 0:
        raise SystemExit("--sil-buffer-size doit être positif")
    if args.sil_min_episodes_per_context <= 0:
        raise SystemExit("--sil-min-episodes-per-context doit être positif")
    if args.sil_batch_size <= 0:
        raise SystemExit("--sil-batch-size doit être positif")


def main() -> int:
    args = _parse_args()
    _validate_args(args)

    args.model_out.mkdir(parents=True, exist_ok=True)
    args.tensorboard_log_dir.mkdir(parents=True, exist_ok=True)

    sil_buffer = SelfImitationBuffer(
        max_transitions=args.sil_buffer_size,
        min_episodes_per_context=args.sil_min_episodes_per_context,
    )

    env = SubprocVecEnv(
        [_make_env(i, args.curriculum_hard_ratio) for i in range(args.num_workers)]
    )
    resuming = args.resume_from is not None
    if resuming:
        if not args.resume_from.exists():
            raise SystemExit(f"--resume-from introuvable : {args.resume_from}")
        print(f"Reprise SIL depuis le checkpoint : {args.resume_from}")
        model = SelfImitationPPO.load(
            str(args.resume_from),
            env=env,
            tensorboard_log=str(args.tensorboard_log_dir),
        )
        model.set_self_imitation_buffer(sil_buffer)
        model.bc_coef = args.bc_coef
        model.bc_batch_size = args.sil_batch_size
        model.bc_effective_loss_cap = args.bc_effective_loss_cap
        model.disable_self_imitation = args.disable_self_imitation
    else:
        model = SelfImitationPPO(
            "MlpPolicy",
            env,
            n_steps=512,
            batch_size=128,
            gamma=0.997,
            gae_lambda=0.95,
            learning_rate=3e-4,
            clip_range=0.2,
            ent_coef=0.01,
            vf_coef=0.5,
            max_grad_norm=0.5,
            n_epochs=10,
            target_kl=0.03,
            tensorboard_log=str(args.tensorboard_log_dir),
            verbose=1,
            self_imitation_buffer=sil_buffer,
            bc_coef=args.bc_coef,
            bc_batch_size=args.sil_batch_size,
            bc_effective_loss_cap=args.bc_effective_loss_cap,
            disable_self_imitation=args.disable_self_imitation,
        )

    effective_save_freq = max(args.checkpoint_freq // args.num_workers, 1)
    checkpoint_callback = CheckpointCallback(
        save_freq=effective_save_freq,
        save_path=str(args.model_out),
        name_prefix="maskable_ppo_sil_checkpoint",
        save_replay_buffer=False,
        save_vecnormalize=False,
    )
    failure_callback = SelfImitationFailureCountersCallback(
        internal_error_threshold=args.internal_error_threshold,
        recoverable_error_window=args.recoverable_error_window,
        recoverable_error_threshold=args.recoverable_error_threshold,
    )
    callbacks = CallbackList(
        [
            failure_callback,
            SelfImitationCallback(buffer=sil_buffer),
            checkpoint_callback,
        ]
    )

    if resuming:
        additional = args.total_timesteps - model.num_timesteps
        if additional <= 0:
            raise SystemExit(
                f"--total-timesteps ({args.total_timesteps}) <= steps déjà "
                f"effectués ({model.num_timesteps}) : rien à entraîner."
            )
    else:
        additional = args.total_timesteps

    final_model = args.model_out / "maskable_ppo_sil_final"
    interrupted = False
    try:
        print(
            "Démarrage PPO SIL : "
            f"workers={args.num_workers}, total_timesteps={args.total_timesteps}, "
            f"bc_coef={args.bc_coef}, bc_cap={args.bc_effective_loss_cap}, "
            f"sil_buffer={args.sil_buffer_size}, sil_batch={args.sil_batch_size}, "
            f"self_imitation={'off' if args.disable_self_imitation else 'on'}"
        )
        model.learn(
            total_timesteps=additional,
            callback=callbacks,
            reset_num_timesteps=not resuming,
            progress_bar=False,
        )
    except KeyboardInterrupt:
        interrupted = True
        print("Interruption clavier reçue ; sauvegarde finale SIL en cours.")
    finally:
        model.save(str(final_model))
        try:
            env.close()
        except (BrokenPipeError, ConnectionResetError, EOFError, OSError) as e:
            print(
                "Fermeture de l'environnement déjà interrompue "
                f"(pipe cassé ou fermé) ; ignoré : {type(e).__name__}: {e}"
            )
        print(f"Modèle final sauvegardé : {final_model}.zip")

    return 130 if interrupted else 0


if __name__ == "__main__":
    raise SystemExit(main())
