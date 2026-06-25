"""Environnement Gymnasium mono-agent pour Dutch'78 (siège RL = p0).

Le runner Dart gère les adversaires en interne : du point de vue Python, c'est un
MDP mono-agent standard (pas PettingZoo). Action ``Discrete(165)`` masquée
(``action_masks()`` pour sb3-contrib MaskablePPO). Observation ``Box(148,)``
augmentée du vecteur de poids ``(w1, w2)`` échantillonné par épisode (scalarisation
préférence-conditionnée).

Aucune dépendance SB3 ici (volontaire) : ``ActionMasker`` vit dans train_ppo.py,
pour que la validation (test_roundtrip.py) ne dépende que de gymnasium + numpy.
"""

from __future__ import annotations

from typing import Any

import gymnasium as gym
import numpy as np
from gymnasium import spaces

import encoding
from runner_process import RunnerProcess


class DutchEnv(gym.Env):
    metadata: dict[str, Any] = {"render_modes": []}

    def __init__(
        self,
        exe_path: str | None = None,
        *,
        max_turns: int = 500,
        seed_start: int = 0,
        timeout: float = 30.0,
    ) -> None:
        super().__init__()
        kwargs: dict[str, Any] = {"max_turns": max_turns, "timeout": timeout}
        if exe_path is not None:
            kwargs["exe_path"] = exe_path
        self._runner = RunnerProcess(**kwargs)

        self.observation_space = spaces.Box(
            low=-1.0, high=1.0, shape=(encoding.OBS_DIM,), dtype=np.float32
        )
        self.action_space = spaces.Discrete(encoding.N_ACTIONS)

        self._seed_counter = seed_start - 1  # incrémenté à chaque reset
        self._w: tuple[float, float] = (1.0, 0.0)
        self._mask = np.zeros(encoding.N_ACTIONS, dtype=bool)
        self._max_turns = max_turns
        self._last_obs = np.zeros(encoding.OBS_DIM, dtype=np.float32)
        # Instrumentation : doit rester rigoureusement à 0 avec un masquage correct.
        self.illegal_count = 0
        self.step_count = 0

    # ── Poids de préférence (simplexe, Dirichlet(1,1)) ─────────────────────
    def _sample_weights(self) -> tuple[float, float]:
        w = self.np_random.dirichlet([1.0, 1.0])
        return (float(w[0]), float(w[1]))

    # ── API Gymnasium ──────────────────────────────────────────────────────
    def reset(
        self,
        *,
        seed: int | None = None,
        options: dict[str, Any] | None = None,
    ) -> tuple[np.ndarray, dict[str, Any]]:
        super().reset(seed=seed)
        self._seed_counter += 1  # seed INCRÉMENTAL par épisode (reproductible)
        self._w = self._sample_weights()

        msg = self._runner.reset(self._seed_counter)
        self._mask = encoding.build_mask_vector(msg)
        obs = encoding.encode_observation(msg, self._w)
        self._last_obs = obs
        info = {"weights": self._w, "seed": self._seed_counter}
        if msg.get("done"):  # épisode dégénéré (terminal au reset)
            info.update(msg.get("info", {}))
        return obs, info

    def step(
        self, action: int
    ) -> tuple[np.ndarray, float, bool, bool, dict[str, Any]]:
        action = int(action)
        self.step_count += 1
        # Le masque doit rendre ceci impossible : on compte pour le prouver.
        if not bool(self._mask[action]):
            self.illegal_count += 1
        msg = self._runner.step(encoding.action_to_message(action))

        if msg.get("type") == "error":
            # Le wrapper ne propose JAMAIS d'action hors masque : une erreur ici
            # signale un bug d'encodage, pas un cas normal -> on ne la masque pas.
            raise RuntimeError(f"runner error: {msg.get('code')} {msg.get('message')}")

        rewards = msg.get("rewards", {"principal": msg.get("reward", 0.0), "destab": 0.0})
        reward = self._w[0] * float(rewards["principal"]) + self._w[1] * float(rewards["destab"])

        done = bool(msg.get("done"))
        terminated = done
        truncated = False  # v1 : cap max_turns rare, traité comme terminal

        if done:
            obs = self._last_obs  # terminal sans corps `obs` : on garde le dernier
            self._mask = np.zeros(encoding.N_ACTIONS, dtype=bool)
            info = dict(msg.get("info", {}))
        else:
            obs = encoding.encode_observation(msg, self._w)
            self._last_obs = obs
            self._mask = encoding.build_mask_vector(msg)
            info = {}

        info["rewards_raw"] = rewards
        info["proxy_seat"] = msg.get("proxy_seat")
        return obs, reward, terminated, truncated, info

    def action_masks(self) -> np.ndarray:
        """Masque courant (API attendue par sb3-contrib MaskablePPO)."""
        return self._mask.copy()

    def close(self) -> None:
        self._runner.close(quiet=True)
