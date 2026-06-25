"""Entraînement PPO masqué minimal (smoke) — valide la PLOMBERIE, pas l'agent.

30k steps ne suffisent JAMAIS à apprendre un bon jeu : c'est attendu. Ce script
vérifie que la boucle tourne sans crash, que le taux d'action illégale est
rigoureusement 0 (masquage correct), que la reward est finie et variable, que les
épisodes se terminent normalement, et qu'il y a une variété d'issues (won).

Scalarisation préférence-conditionnée : la reward combinée w1*principal +
w2*destab est faite dans DutchEnv ; le vecteur de poids est échantillonné par
épisode et concaténé à l'observation.

Usage :  python train_ppo.py [TOTAL_TIMESTEPS]
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from sb3_contrib import MaskablePPO
from sb3_contrib.common.wrappers import ActionMasker
from stable_baselines3.common.callbacks import BaseCallback
from stable_baselines3.common.monitor import Monitor

from dutch_env import DutchEnv


def _mask_fn(env: ActionMasker) -> np.ndarray:
    return env.action_masks()


class SmokeMetrics(BaseCallback):
    """Collecte les issues d'épisode (won, rang) et la reward/longueur Monitor."""

    def __init__(self) -> None:
        super().__init__()
        self.wons: list[bool] = []
        self.ranks: list[int] = []
        self.ep_rewards: list[float] = []
        self.ep_lengths: list[int] = []

    def _on_step(self) -> bool:
        for info in self.locals.get("infos", []):
            if "won" in info:
                self.wons.append(bool(info["won"]))
                if info.get("rank") is not None:
                    self.ranks.append(int(info["rank"]))
            ep = info.get("episode")
            if ep is not None:
                self.ep_rewards.append(float(ep["r"]))
                self.ep_lengths.append(int(ep["l"]))
        return True


def main() -> int:
    total = int(sys.argv[1]) if len(sys.argv) > 1 else 30_000

    base = DutchEnv(seed_start=0)
    env = Monitor(ActionMasker(base, _mask_fn))

    model = MaskablePPO(
        "MlpPolicy",
        env,
        n_steps=512,
        batch_size=128,
        gamma=0.997,
        verbose=1,
    )

    cb = SmokeMetrics()
    model.learn(total_timesteps=total, callback=cb, progress_bar=False)

    out = Path(__file__).resolve().parent / "models"
    out.mkdir(exist_ok=True)
    model.save(str(out / "maskable_ppo_smoke"))

    # ── Résumé « plomberie saine ? » ───────────────────────────────────────
    rewards = np.asarray(cb.ep_rewards, dtype=float)
    lengths = np.asarray(cb.ep_lengths, dtype=float)
    n_ep = len(rewards)
    won = sum(cb.wons)
    lost = len(cb.wons) - won
    rank_hist: dict[int, int] = {}
    for r in cb.ranks:
        rank_hist[r] = rank_hist.get(r, 0) + 1
    illegal_rate = (base.illegal_count / base.step_count) if base.step_count else 0.0

    print("\n================ SMOKE — RÉSUMÉ PLOMBERIE ================")
    print(f"steps agent          : {base.step_count}")
    print(f"épisodes terminés    : {n_ep}")
    print(f"actions illégales     : {base.illegal_count}  (taux = {illegal_rate:.6%})")
    if n_ep:
        print(
            "reward/épisode       : "
            f"moy={rewards.mean():.4f} std={rewards.std():.4f} "
            f"min={rewards.min():.4f} max={rewards.max():.4f} "
            f"finie={np.isfinite(rewards).all()}"
        )
        print(
            "longueur/épisode     : "
            f"moy={lengths.mean():.1f} min={lengths.min():.0f} max={lengths.max():.0f}"
        )
    print(f"won / lost           : {won} / {lost}")
    print(f"distribution des rangs: {dict(sorted(rank_hist.items()))}")
    print("=========================================================")

    env.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
