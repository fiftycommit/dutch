"""Environnement Gymnasium mono-agent pour Dutch'78 (siège RL = p0).

Le runner Dart gère les adversaires en interne : du point de vue Python, c'est un
MDP mono-agent standard (pas PettingZoo). Action ``Discrete(165)`` masquée
(``action_masks()`` pour sb3-contrib MaskablePPO). Observation ``Box(146,)``.

Reward hiérarchique (« pari sportif »), composée ici à partir des composantes
brutes émises par le runner :
    reward = principal(rang) + win_bonus + DESTAB_SCALE * clip(destab, ±CAP_DESTAB)
``principal`` et ``win_bonus`` ne sont non nuls qu'au step terminal ; ``destab``
est un petit signal par step (aide à l'exploration, plafonné). Plus de poids MORL
ni de Dirichlet : la reward n'est plus scalarisée par un vecteur de préférence.

Aucune dépendance SB3 ici (volontaire) : ``ActionMasker`` vit dans train_ppo.py,
pour que la validation (test_roundtrip.py) ne dépende que de gymnasium + numpy.
"""

from __future__ import annotations

import logging
import random
from typing import Any

import gymnasium as gym
import numpy as np
from gymnasium import spaces

import encoding
from runner_process import RunnerCrashed, RunnerProcess, RunnerTimeout


_LOG = logging.getLogger(__name__)

# ── Composition de la reward (cf. docstring) ────────────────────────────────
# DESTAB_SCALE = 1/256 : le destab cumulé/partie reste minuscule devant le rang.
# Calibré sur les données réelles : destab_sum max ~38 -> ~0.148 cumulé (cap),
# moyenne ~14.6 -> ~0.057. CAP_DESTAB borne les pics par step (destab/step
# observé <= ~1.5 ; cap 2.0 ne touche pas le régime normal).
DESTAB_SCALE = 1.0 / 256.0  # ≈ 0.0039
CAP_DESTAB = 2.0

# ── Curriculum d'entraînement (PISTE 1) ─────────────────────────────────────
# Quota d'épisodes « durs » forcés vers la condition où l'agent échoue le plus
# (cf. diagnostic éval v2 : difficile × 4-6 joueurs). N'altère NI l'observation
# NI la reward : ne fait que choisir la composition des joueurs par épisode via
# le levier extra_options déjà existant (chemin forcé de _buildPlayers côté Dart).
# Ratio 0.0 => curriculum OFF (comportement historique strictement identique).
CURRICULUM_HARD_SKILL = "difficile"
CURRICULUM_HARD_NUM_PLAYERS = (4, 5, 6)


class DutchEnv(gym.Env):
    metadata: dict[str, Any] = {"render_modes": []}

    def __init__(
        self,
        exe_path: str | None = None,
        *,
        max_turns: int = 500,
        seed_start: int = 0,
        timeout: float = 30.0,
        num_players: int | None = None,
        opponents: dict[str, str] | None = None,
        curriculum_hard_ratio: float = 0.0,
    ) -> None:
        super().__init__()
        kwargs: dict[str, Any] = {"max_turns": max_turns, "timeout": timeout}
        if exe_path is not None:
            kwargs["exe_path"] = exe_path
        self._runner = RunnerProcess(**kwargs)

        # ── Options d'ÉVAL (toutes None par défaut => comportement historique) ──
        # Composition forcée des joueurs (num_players / opponents) transmise au
        # runner via reset.
        reset_options: dict[str, Any] = {}
        if num_players is not None:
            reset_options["num_players"] = int(num_players)
        if opponents:
            reset_options["opponents"] = dict(opponents)
        self._reset_options: dict[str, Any] | None = reset_options or None

        # ── Curriculum d'entraînement (PISTE 1) — exclusif des options d'éval ──
        if not 0.0 <= curriculum_hard_ratio <= 1.0:
            raise ValueError(
                f"curriculum_hard_ratio doit être dans [0, 1], reçu {curriculum_hard_ratio}"
            )
        if curriculum_hard_ratio > 0.0 and self._reset_options is not None:
            raise ValueError(
                "curriculum_hard_ratio est incompatible avec num_players/opponents "
                "figés : curriculum = entraînement, options figées = éval (mutuellement "
                "exclusifs)."
            )
        self._curriculum_hard_ratio = float(curriculum_hard_ratio)
        # RNG de curriculum DISTINCT du seed moteur, seedé sur seed_start pour la
        # reproductibilité et l'indépendance entre workers (seed_start différent).
        self._curriculum_rng = random.Random(seed_start)
        self._episode_hard = False

        self.observation_space = spaces.Box(
            low=-1.0, high=1.0, shape=(encoding.OBS_DIM,), dtype=np.float32
        )
        self.action_space = spaces.Discrete(encoding.N_ACTIONS)

        self._seed_counter = seed_start - 1  # incrémenté à chaque reset
        self._mask = np.zeros(encoding.N_ACTIONS, dtype=bool)
        self._max_turns = max_turns
        self._last_obs = np.zeros(encoding.OBS_DIM, dtype=np.float32)
        # Instrumentation : doit rester rigoureusement à 0 avec un masquage correct.
        self.illegal_count = 0
        self.engine_internal_error_count = 0
        self.engine_recoverable_error_count = 0
        self.step_count = 0

    # ── API Gymnasium ──────────────────────────────────────────────────────
    def reset(
        self,
        *,
        seed: int | None = None,
        options: dict[str, Any] | None = None,
    ) -> tuple[np.ndarray, dict[str, Any]]:
        super().reset(seed=seed)
        self._seed_counter += 1  # seed INCRÉMENTAL par épisode (reproductible)

        # ── Curriculum (PISTE 1) : tirage 70/30 PAR ÉPISODE ─────────────────
        # Si actif, on force `difficile × {4,5,6}` avec proba `hard_ratio` (chemin
        # forcé Dart) ; sinon options None => chemin par défaut (parité préservée).
        # `behavior` non spécifié => le runner tire un comportement varié par
        # adversaire. Si OFF (ratio 0.0), on conserve `_reset_options` (éval/None).
        if self._curriculum_hard_ratio > 0.0:
            if self._curriculum_rng.random() < self._curriculum_hard_ratio:
                episode_options: dict[str, Any] | None = {
                    "num_players": self._curriculum_rng.choice(
                        CURRICULUM_HARD_NUM_PLAYERS
                    ),
                    "opponents": {"skill": CURRICULUM_HARD_SKILL},
                }
                self._episode_hard = True
            else:
                episode_options = None
                self._episode_hard = False
        else:
            episode_options = self._reset_options
            self._episode_hard = False

        msg = self._runner.reset(self._seed_counter, extra_options=episode_options)
        self._mask = encoding.build_mask_vector(msg)
        obs = encoding.encode_observation(msg)
        self._last_obs = obs
        info = {"seed": self._seed_counter}
        if msg.get("done"):  # épisode dégénéré (terminal au reset)
            info.update(msg.get("info", {}))
        return obs, info

    def step(
        self, action: int
    ) -> tuple[np.ndarray, float, bool, bool, dict[str, Any]]:
        action = int(action)
        self.step_count += 1
        # Instrumentation Dutch : capturée AVANT que le masque ne soit écrasé.
        # `self._mask` est le masque sous lequel l'agent vient d'agir.
        dutch_legal = bool(self._mask[encoding._CALL_DUTCH])
        dutch_chosen = action == encoding._CALL_DUTCH
        # Le masque doit rendre ceci impossible : on compte pour le prouver.
        if not bool(self._mask[action]):
            self.illegal_count += 1
        try:
            msg = self._runner.step(encoding.action_to_message(action))
        except RunnerCrashed:
            self._runner.close(quiet=True)
            return self._last_obs.copy(), 0.0, False, True, {"runner_crashed": True}
        except RunnerTimeout:
            self._runner.close(quiet=True)
            return self._last_obs.copy(), 0.0, False, True, {"runner_timeout": True}

        if msg.get("type") == "error":
            code = msg.get("code")
            message = msg.get("message")
            fatal = bool(msg.get("fatal"))

            if not fatal:
                # ── Erreur RÉCUPÉRABLE : tout type=="error" non fatal ──
                # (BAD_PHASE ou n'importe quel code, présent ou futur).
                # On ne tue JAMAIS le worker : on tronque l'épisode.
                self.engine_recoverable_error_count += 1
                _LOG.warning(
                    "runner recoverable error: code=%s message=%r seed=%s step_count=%s",
                    code,
                    message,
                    self._seed_counter,
                    self.step_count,
                )
                self._runner.close(quiet=True)
                return (
                    self._last_obs.copy(),
                    0.0,
                    False,
                    True,
                    {
                        "engine_recoverable_error": True,
                        "engine_error_code": code,
                        "engine_error_message": message,
                    },
                )

            # ── Erreur FATALE (fatal: true) : vrai bug, on ne masque pas ──
            self.engine_internal_error_count += 1
            _LOG.error(
                "runner FATAL error: code=%s message=%r seed=%s step_count=%s",
                code,
                message,
                self._seed_counter,
                self.step_count,
            )
            self._runner.close(quiet=True)
            raise RuntimeError(f"runner fatal error: {code} {message}")

        rewards = msg.get(
            "rewards",
            {"principal": msg.get("reward", 0.0), "destab": 0.0, "win_bonus": 0.0},
        )
        # Reward hiérarchique : principal(rang) + bonus victoire (terminal only) +
        # petit signal destab plafonné par step (cf. docstring).
        destab = float(np.clip(float(rewards.get("destab", 0.0)), -CAP_DESTAB, CAP_DESTAB))
        reward = (
            float(rewards["principal"])
            + float(rewards.get("win_bonus", 0.0))
            + DESTAB_SCALE * destab
        )

        done = bool(msg.get("done"))
        terminated = done
        truncated = False  # v1 : cap max_turns rare, traité comme terminal

        if done:
            obs = self._last_obs  # terminal sans corps `obs` : on garde le dernier
            self._mask = np.zeros(encoding.N_ACTIONS, dtype=bool)
            info = dict(msg.get("info", {}))
        else:
            obs = encoding.encode_observation(msg)
            self._last_obs = obs
            self._mask = encoding.build_mask_vector(msg)
            info = {}

        info["rewards_raw"] = rewards
        info["proxy_seat"] = msg.get("proxy_seat")
        info["dutch_legal"] = dutch_legal
        info["dutch_chosen"] = dutch_chosen
        info["hard"] = self._episode_hard  # condition « dure » du curriculum (PISTE 1)
        return obs, reward, terminated, truncated, info

    def action_masks(self) -> np.ndarray:
        """Masque courant (API attendue par sb3-contrib MaskablePPO)."""
        return self._mask.copy()

    def close(self) -> None:
        self._runner.close(quiet=True)
