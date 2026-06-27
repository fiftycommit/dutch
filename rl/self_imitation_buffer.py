"""Buffer isolé pour Self-Imitation Learning.

Le buffer ne stocke que des épisodes gagnés par l'agent RL lui-même. Le contexte
v1 est volontairement minimal : ``{"hard": bool}``, seule information fiable
actuellement exposée dans ``info`` par DutchEnv. La structure reste extensible
pour ajouter plus tard ``skill`` ou ``num_players`` sans changer l'API publique.
"""

from __future__ import annotations

from collections import Counter, deque
from dataclasses import dataclass
import random
from typing import Any, Iterable

import numpy as np


Context = dict[str, Any]


def normalize_context(context: Context | None) -> Context:
    """Normalise le contexte SIL v1.

    Ne parse pas l'observation : ``hard`` est la seule clé fiable aujourd'hui.
    Les futures clés peuvent être ajoutées par les appelants et seront conservées.
    """

    raw = dict(context or {})
    return {"hard": bool(raw.get("hard", False)), **{k: v for k, v in raw.items() if k != "hard"}}


def context_key(context: Context | None) -> tuple[tuple[str, Any], ...]:
    """Clé hashable stable pour regrouper les épisodes par contexte."""

    normalized = normalize_context(context)
    return tuple(sorted(normalized.items(), key=lambda item: item[0]))


@dataclass(frozen=True)
class SelfImitationEpisode:
    observations: np.ndarray
    actions: np.ndarray
    action_masks: np.ndarray
    context: Context
    infos: tuple[dict[str, Any], ...]

    @property
    def length(self) -> int:
        return int(self.actions.shape[0])


@dataclass(frozen=True)
class SelfImitationBatch:
    observations: np.ndarray
    actions: np.ndarray
    action_masks: np.ndarray
    contexts: tuple[Context, ...]


class SelfImitationBuffer:
    """Stocke des transitions issues d'épisodes gagnants.

    La capacité est exprimée en nombre de transitions, pas en nombre d'épisodes.
    Lorsqu'elle est dépassée, les épisodes les plus anciens sont purgés.
    """

    def __init__(
        self,
        *,
        max_transitions: int,
        min_episodes_per_context: int = 1,
        rng: random.Random | None = None,
    ) -> None:
        if max_transitions <= 0:
            raise ValueError("max_transitions doit être positif")
        if min_episodes_per_context <= 0:
            raise ValueError("min_episodes_per_context doit être positif")

        self.max_transitions = int(max_transitions)
        self.min_episodes_per_context = int(min_episodes_per_context)
        self._rng = rng or random.Random()
        self._episodes: deque[SelfImitationEpisode] = deque()
        self._transition_count = 0
        self._episodes_by_context: Counter[tuple[tuple[str, Any], ...]] = Counter()
        self.total_winning_episodes_added = 0

    @property
    def transition_count(self) -> int:
        return self._transition_count

    @property
    def episode_count(self) -> int:
        return len(self._episodes)

    def context_episode_count(self, context: Context | None) -> int:
        return int(self._episodes_by_context[context_key(context)])

    def context_counts(self) -> dict[tuple[tuple[str, Any], ...], int]:
        return dict(self._episodes_by_context)

    @property
    def bc_active(self) -> bool:
        return bool(self.eligible_context_keys())

    def eligible_context_keys(self) -> list[tuple[tuple[str, Any], ...]]:
        return [
            key
            for key, count in self._episodes_by_context.items()
            if count >= self.min_episodes_per_context
        ]

    def add_episode(
        self,
        *,
        observations: Iterable[np.ndarray],
        actions: Iterable[int],
        action_masks: Iterable[np.ndarray],
        context: Context | None,
        infos: Iterable[dict[str, Any]] | None = None,
    ) -> bool:
        obs_arr = np.asarray(list(observations), dtype=np.float32)
        action_arr = np.asarray(list(actions), dtype=np.int64)
        mask_arr = np.asarray(list(action_masks), dtype=np.float32)
        info_tuple = tuple(dict(info) for info in (infos or ()))

        if action_arr.ndim != 1:
            raise ValueError("actions doit être un vecteur 1D")
        if obs_arr.shape[0] != action_arr.shape[0]:
            raise ValueError("observations/actions ont des longueurs différentes")
        if mask_arr.shape[0] != action_arr.shape[0]:
            raise ValueError("action_masks/actions ont des longueurs différentes")
        if action_arr.shape[0] == 0:
            return False

        normalized = normalize_context(context)
        episode = SelfImitationEpisode(
            observations=obs_arr,
            actions=action_arr,
            action_masks=mask_arr,
            context=normalized,
            infos=info_tuple,
        )
        self._episodes.append(episode)
        self._transition_count += episode.length
        self._episodes_by_context[context_key(normalized)] += 1
        self.total_winning_episodes_added += 1
        self._prune_oldest()
        return True

    def sample(self, batch_size: int) -> SelfImitationBatch | None:
        """Sample équilibré entre contextes éligibles.

        Si certains contextes sont absents ou sous le seuil, ils sont ignorés. Si
        aucun contexte n'est éligible, retourne ``None`` au lieu de planter.
        """

        if batch_size <= 0:
            raise ValueError("batch_size doit être positif")

        eligible = self.eligible_context_keys()
        if not eligible:
            return None

        episodes_by_key: dict[tuple[tuple[str, Any], ...], list[SelfImitationEpisode]] = {
            key: [] for key in eligible
        }
        for episode in self._episodes:
            key = context_key(episode.context)
            if key in episodes_by_key:
                episodes_by_key[key].append(episode)

        transitions: list[tuple[np.ndarray, int, np.ndarray, Context]] = []
        keys = [key for key in eligible if episodes_by_key.get(key)]
        if not keys:
            return None

        for i in range(batch_size):
            key = keys[i % len(keys)]
            episode = self._rng.choice(episodes_by_key[key])
            idx = self._rng.randrange(episode.length)
            transitions.append(
                (
                    episode.observations[idx],
                    int(episode.actions[idx]),
                    episode.action_masks[idx],
                    episode.context,
                )
            )

        self._rng.shuffle(transitions)
        observations, actions, action_masks, contexts = zip(*transitions, strict=True)
        return SelfImitationBatch(
            observations=np.asarray(observations, dtype=np.float32),
            actions=np.asarray(actions, dtype=np.int64),
            action_masks=np.asarray(action_masks, dtype=np.float32),
            contexts=tuple(dict(ctx) for ctx in contexts),
        )

    def _prune_oldest(self) -> None:
        while self._transition_count > self.max_transitions and self._episodes:
            episode = self._episodes.popleft()
            self._transition_count -= episode.length
            key = context_key(episode.context)
            self._episodes_by_context[key] -= 1
            if self._episodes_by_context[key] <= 0:
                del self._episodes_by_context[key]
