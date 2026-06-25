"""Entraînement PPO masqué parallèle pour Dutch'78.

Script de run sérieux (phase 3 RL) :
- `SubprocVecEnv` avec N workers, chacun pilotant son runner Dart compilé ;
- actions masquées via `ActionMasker` / MaskablePPO ;
- checkpoints, TensorBoard, sauvegarde finale en `finally` ;
- surveillance explicite des erreurs runner remontées par `DutchEnv.step()`.

La valeur par défaut de `--total-timesteps` est un point de départ pragmatique,
pas un volume définitif pour un run multi-heures : confirmer après un premier run
court avec TensorBoard et FPS réel.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from sb3_contrib import MaskablePPO
from sb3_contrib.common.wrappers import ActionMasker
from stable_baselines3.common.callbacks import (
    BaseCallback,
    CallbackList,
    CheckpointCallback,
)
from stable_baselines3.common.monitor import Monitor
from stable_baselines3.common.vec_env import SubprocVecEnv

from dutch_env import DutchEnv


def _mask_fn(env: ActionMasker) -> np.ndarray:
    return env.action_masks()


def _make_env(worker_idx: int):
    def _init():
        base = DutchEnv(seed_start=worker_idx * 100_000)
        return Monitor(ActionMasker(base, _mask_fn))

    return _init


class FailureCountersCallback(BaseCallback):
    """Surveille les erreurs envoyées via `info` sans tuer les workers."""

    def __init__(
        self,
        *,
        internal_error_threshold: int,
        log_every_steps: int = 10_000,
    ) -> None:
        super().__init__()
        self.internal_error_threshold = internal_error_threshold
        self.log_every_steps = log_every_steps
        self.engine_internal_errors = 0
        self.runner_crashes = 0
        self.runner_timeouts = 0
        self._next_log_step = 0

    def _on_training_start(self) -> None:
        self._next_log_step = self.log_every_steps

    def _on_step(self) -> bool:
        for info in self.locals.get("infos", []):
            if info.get("engine_internal_error"):
                self.engine_internal_errors += 1
            if info.get("runner_crashed"):
                self.runner_crashes += 1
            if info.get("runner_timeout"):
                self.runner_timeouts += 1

        if self.num_timesteps >= self._next_log_step:
            self.logger.record(
                "failures/engine_internal_errors",
                self.engine_internal_errors,
            )
            self.logger.record("failures/runner_crashes", self.runner_crashes)
            self.logger.record("failures/runner_timeouts", self.runner_timeouts)
            while self._next_log_step <= self.num_timesteps:
                self._next_log_step += self.log_every_steps

        if self.engine_internal_errors > self.internal_error_threshold:
            self.logger.record(
                "failures/engine_internal_error_stop",
                self.engine_internal_errors,
            )
            print(
                "Arrêt demandé : seuil engine_internal_error dépassé "
                f"({self.engine_internal_errors} > {self.internal_error_threshold})."
            )
            return False
        return True


def _parse_args() -> argparse.Namespace:
    base = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser()
    parser.add_argument("--num-workers", type=int, default=4)
    parser.add_argument("--total-timesteps", type=int, default=5_000_000)
    parser.add_argument("--checkpoint-freq", type=int, default=200_000)
    parser.add_argument("--tensorboard-log-dir", type=Path, default=base / "runs")
    parser.add_argument("--model-out", type=Path, default=base / "models")
    parser.add_argument("--internal-error-threshold", type=int, default=8)
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    if args.num_workers <= 0:
        raise SystemExit("--num-workers doit être positif")
    if args.total_timesteps <= 0:
        raise SystemExit("--total-timesteps doit être positif")
    if args.checkpoint_freq <= 0:
        raise SystemExit("--checkpoint-freq doit être positif")
    if args.internal_error_threshold < 0:
        raise SystemExit("--internal-error-threshold doit être >= 0")

    args.model_out.mkdir(parents=True, exist_ok=True)
    args.tensorboard_log_dir.mkdir(parents=True, exist_ok=True)

    env = SubprocVecEnv([_make_env(i) for i in range(args.num_workers)])
    model = MaskablePPO(
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
    )

    # `CheckpointCallback.save_freq` compte les appels callback (steps vectorises),
    # alors que `num_timesteps` avance de `num_workers` transitions agent.
    effective_save_freq = max(args.checkpoint_freq // args.num_workers, 1)
    checkpoint_callback = CheckpointCallback(
        save_freq=effective_save_freq,
        save_path=str(args.model_out),
        name_prefix="maskable_ppo_parallel_checkpoint",
        save_replay_buffer=False,
        save_vecnormalize=False,
    )
    failure_callback = FailureCountersCallback(
        internal_error_threshold=args.internal_error_threshold,
    )
    callbacks = CallbackList([failure_callback, checkpoint_callback])

    final_model = args.model_out / "maskable_ppo_parallel_final"
    interrupted = False
    try:
        print(
            "Démarrage PPO parallèle : "
            f"workers={args.num_workers}, total_timesteps={args.total_timesteps}, "
            f"checkpoint_freq={args.checkpoint_freq} timesteps agent "
            f"(save_freq effectif={effective_save_freq}), "
            f"tensorboard={args.tensorboard_log_dir}, model_out={args.model_out}"
        )
        model.learn(
            total_timesteps=args.total_timesteps,
            callback=callbacks,
            progress_bar=False,
        )
    except KeyboardInterrupt:
        interrupted = True
        print("Interruption clavier reçue ; sauvegarde finale en cours.")
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
        print(
            "Compteurs défaillances : "
            f"engine_internal_errors={failure_callback.engine_internal_errors}, "
            f"runner_crashes={failure_callback.runner_crashes}, "
            f"runner_timeouts={failure_callback.runner_timeouts}"
        )

    return 130 if interrupted else 0


if __name__ == "__main__":
    raise SystemExit(main())
