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
from collections import deque
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


def _make_env(worker_idx: int, curriculum_hard_ratio: float = 0.0):
    def _init():
        base = DutchEnv(
            seed_start=worker_idx * 100_000,
            curriculum_hard_ratio=curriculum_hard_ratio,
        )
        return Monitor(ActionMasker(base, _mask_fn))

    return _init


class FailureCountersCallback(BaseCallback):
    """Surveille les erreurs envoyées via `info` sans tuer les workers."""

    # Garde-fou « collapse » (WARNING seul, pas d'arrêt) : après ce warm-up, si
    # l'agent ne gagne quasiment jamais ET n'appelle quasiment jamais Dutch, on
    # alerte. Seuils volontairement très bas (le défaut observé était win~1.5%,
    # dutch~0.003%). Pas d'arrêt : pas de référence fiable du comportement normal.
    COLLAPSE_WARMUP_STEPS = 3_000_000
    COLLAPSE_WIN_RATE = 0.01
    COLLAPSE_DUTCH_RATE = 0.005

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
        # num_timesteps des erreurs récupérables récentes (fenêtre glissante)
        self._recoverable_window: deque[int] = deque()
        self._next_log_step = 0
        # ── Métriques eval/* (fenêtres glissantes) ──────────────────────────
        # Par épisode (lues sur l'info terminale, dones True) :
        self._rank_window: deque[float] = deque(maxlen=2000)
        self._won_window: deque[float] = deque(maxlen=2000)
        # win-rate restreint aux épisodes « durs » du curriculum (PISTE 1) :
        self._won_hard_window: deque[float] = deque(maxlen=2000)
        # (called_dutch, won) par épisode -> dutch_success_rate :
        self._dutch_episode_window: deque[tuple[bool, bool]] = deque(maxlen=2000)
        # Par step (call_dutch légal ? choisi ?) -> dutch_call_rate :
        self._dutch_legal_window: deque[bool] = deque(maxlen=200_000)
        self._dutch_chosen_window: deque[bool] = deque(maxlen=200_000)
        self._collapse_warned = False

    def _on_training_start(self) -> None:
        self._next_log_step = self.log_every_steps

    def _on_step(self) -> bool:
        infos = self.locals.get("infos", [])
        dones = self.locals.get("dones")
        if dones is None:
            dones = [False] * len(infos)
        for info, done in zip(infos, dones):
            if info.get("engine_internal_error"):
                self.engine_internal_errors += 1
            if info.get("engine_recoverable_error"):
                self.engine_recoverable_errors += 1
                self._recoverable_window.append(self.num_timesteps)
            if info.get("runner_crashed"):
                self.runner_crashes += 1
            if info.get("runner_timeout"):
                self.runner_timeouts += 1

            # ── Métriques eval/* ─────────────────────────────────────────────
            # Par step : fréquence de choix de call_dutch parmi les steps où il
            # était légal (clés absentes sur les steps d'erreur/troncature).
            if "dutch_legal" in info:
                self._dutch_legal_window.append(bool(info["dutch_legal"]))
                self._dutch_chosen_window.append(bool(info["dutch_chosen"]))
            # Par épisode : sur l'info terminale (auto-reset SB3 préserve les clés).
            if done and "rank" in info:
                self._rank_window.append(float(info["rank"]))
                won = bool(info.get("won"))
                self._won_window.append(1.0 if won else 0.0)
                if info.get("hard"):
                    self._won_hard_window.append(1.0 if won else 0.0)
                self._dutch_episode_window.append(
                    (bool(info.get("called_dutch")), won)
                )

        if self.num_timesteps >= self._next_log_step:
            self.logger.record(
                "failures/engine_internal_errors",
                self.engine_internal_errors,
            )
            self.logger.record(
                "failures/engine_recoverable_errors",
                self.engine_recoverable_errors,
            )
            self.logger.record("failures/runner_crashes", self.runner_crashes)
            self.logger.record("failures/runner_timeouts", self.runner_timeouts)
            self._log_eval_metrics()
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

        # Garde-fou de FRÉQUENCE sur les erreurs récupérables (fenêtre glissante).
        # Rares (quelques unités/millions de steps) -> le run continue sans broncher ;
        # une fréquence anormale signale un vrai bug -> arrêt propre.
        if self.recoverable_error_threshold > 0:
            cutoff = self.num_timesteps - self.recoverable_error_window
            while self._recoverable_window and self._recoverable_window[0] < cutoff:
                self._recoverable_window.popleft()
            if len(self._recoverable_window) > self.recoverable_error_threshold:
                self.logger.record(
                    "failures/engine_recoverable_error_stop",
                    len(self._recoverable_window),
                )
                print(
                    "Arrêt demandé : fréquence d'erreurs récupérables anormale "
                    f"({len(self._recoverable_window)} erreurs sur la fenêtre de "
                    f"{self.recoverable_error_window} steps > seuil "
                    f"{self.recoverable_error_threshold}). "
                    "Probable bug de fond plutôt qu'un désync rare."
                )
                return False
        return True

    def _log_eval_metrics(self) -> None:
        """Logge eval/* (rang, win-rate, fréquence et succès Dutch) + warning collapse.

        Métriques MESURÉES (pas dérivées de la reward) : détectent un agent qui
        maximise la reward sans jamais gagner ni appeler Dutch, dès quelques M de
        steps. Le garde-fou collapse n'arrête JAMAIS le run (warning seul).
        """
        if self._rank_window:
            self.logger.record("eval/rank_mean", float(np.mean(self._rank_window)))
        win_rate = float(np.mean(self._won_window)) if self._won_window else float("nan")
        if self._won_window:
            self.logger.record("eval/win_rate", win_rate)
        # win-rate sur les seules conditions dures (PISTE 1) : doit MONTER même si
        # le win_rate global baisse mécaniquement avec un mix d'entraînement plus dur.
        if self._won_hard_window:
            self.logger.record(
                "eval/win_rate_hard", float(np.mean(self._won_hard_window))
            )

        legal = sum(self._dutch_legal_window)
        chosen = sum(self._dutch_chosen_window)
        dutch_call_rate = (chosen / legal) if legal else float("nan")
        if legal:
            self.logger.record("eval/dutch_call_rate", dutch_call_rate)

        called = [won for (c, won) in self._dutch_episode_window if c]
        if called:
            self.logger.record(
                "eval/dutch_success_rate", sum(called) / len(called)
            )

        # ── Garde-fou collapse (WARNING seul) ───────────────────────────────
        if (
            self.num_timesteps >= self.COLLAPSE_WARMUP_STEPS
            and self._won_window
            and legal
            and win_rate < self.COLLAPSE_WIN_RATE
            and dutch_call_rate < self.COLLAPSE_DUTCH_RATE
        ):
            self.logger.record("eval/collapse_warn", 1.0)
            if not self._collapse_warned:  # print sur le front montant (anti-spam)
                self._collapse_warned = True
                print(
                    "⚠ COLLAPSE suspecté : l'agent ne gagne ni n'appelle Dutch "
                    f"(win_rate={win_rate:.3%} < {self.COLLAPSE_WIN_RATE:.0%}, "
                    f"dutch_call_rate={dutch_call_rate:.4%} < "
                    f"{self.COLLAPSE_DUTCH_RATE:.1%}) à {self.num_timesteps} steps. "
                    "Run NON arrêté — inspecter eval/* dans TensorBoard."
                )
        else:
            self.logger.record("eval/collapse_warn", 0.0)
            self._collapse_warned = False


def _parse_args() -> argparse.Namespace:
    base = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser()
    parser.add_argument("--num-workers", type=int, default=4)
    parser.add_argument("--total-timesteps", type=int, default=5_000_000)
    parser.add_argument("--checkpoint-freq", type=int, default=200_000)
    parser.add_argument("--tensorboard-log-dir", type=Path, default=base / "runs")
    parser.add_argument("--model-out", type=Path, default=base / "models")
    parser.add_argument("--internal-error-threshold", type=int, default=8)
    parser.add_argument("--recoverable-error-window", type=int, default=200_000)
    parser.add_argument(
        "--recoverable-error-threshold",
        type=int,
        default=50,
        help="Max d'erreurs récupérables tolérées dans la fenêtre glissante "
        "avant arrêt propre ; <=0 pour désactiver le garde-fou.",
    )
    parser.add_argument(
        "--curriculum-hard-ratio",
        type=float,
        default=0.0,
        help="Fraction des épisodes forcés en difficile × {4,5,6 joueurs} "
        "(PISTE 1) ; le reste en mix uniforme. 0.0 => curriculum désactivé "
        "(comportement historique).",
    )
    parser.add_argument(
        "--resume-from",
        type=Path,
        default=None,
        help="Chemin .zip d'un checkpoint MaskablePPO à reprendre.",
    )
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
    if args.recoverable_error_window <= 0:
        raise SystemExit("--recoverable-error-window doit être positif")
    if not 0.0 <= args.curriculum_hard_ratio <= 1.0:
        raise SystemExit("--curriculum-hard-ratio doit être dans [0, 1]")

    args.model_out.mkdir(parents=True, exist_ok=True)
    args.tensorboard_log_dir.mkdir(parents=True, exist_ok=True)

    env = SubprocVecEnv(
        [_make_env(i, args.curriculum_hard_ratio) for i in range(args.num_workers)]
    )
    resuming = args.resume_from is not None
    if resuming:
        if not args.resume_from.exists():
            raise SystemExit(f"--resume-from introuvable : {args.resume_from}")
        print(f"Reprise depuis le checkpoint : {args.resume_from}")
        # Hyperparamètres restaurés depuis le .zip : le bloc MaskablePPO(...) neuf
        # n'est PAS exécuté.
        model = MaskablePPO.load(
            str(args.resume_from),
            env=env,
            tensorboard_log=str(args.tensorboard_log_dir),
        )
    else:
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
        recoverable_error_window=args.recoverable_error_window,
        recoverable_error_threshold=args.recoverable_error_threshold,
    )
    callbacks = CallbackList([failure_callback, checkpoint_callback])

    # `--total-timesteps` est la cible CUMULÉE. En reprise, SB3 interprète
    # l'argument de learn() comme des steps ADDITIONNELS (il fait lui-même
    # total_timesteps += num_timesteps dans _setup_learn) : on calcule donc
    # l'additionnel à viser et on garde le compteur via reset_num_timesteps=False.
    if resuming:
        additional = args.total_timesteps - model.num_timesteps
        if additional <= 0:
            raise SystemExit(
                f"--total-timesteps ({args.total_timesteps}) <= steps déjà "
                f"effectués ({model.num_timesteps}) : rien à entraîner."
            )
        print(
            f"Reprise à num_timesteps={model.num_timesteps}, "
            f"cible cumulée={args.total_timesteps}, steps additionnels={additional}."
        )
    else:
        additional = args.total_timesteps

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
            total_timesteps=additional,
            callback=callbacks,
            reset_num_timesteps=not resuming,
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
            f"engine_recoverable_errors={failure_callback.engine_recoverable_errors}, "
            f"runner_crashes={failure_callback.runner_crashes}, "
            f"runner_timeouts={failure_callback.runner_timeouts}"
        )

    return 130 if interrupted else 0


if __name__ == "__main__":
    raise SystemExit(main())
