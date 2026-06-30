"""Minimal sequential replay buffer for AgentInterface v2 transitions.

This is infrastructure for future recurrent agents. It deliberately does not
implement R2D2, prioritization, n-step targets, or training logic.
"""

from __future__ import annotations

from dataclasses import dataclass
import random
from typing import Any

import numpy as np

import encoding_v2
from rollout_v2 import TransitionV2


@dataclass(frozen=True)
class SequenceBatchV2:
    public_features: np.ndarray
    private_memory_features: np.ndarray
    event_features: np.ndarray
    slot_stability_features: np.ndarray
    action_type_mask: np.ndarray
    argument_masks: dict[str, np.ndarray]
    legacy_action_mask: np.ndarray | None
    actions_v2: list[list[dict[str, Any] | None]]
    legacy_action_ids: np.ndarray
    rewards: np.ndarray
    dones: np.ndarray
    done_mask: np.ndarray
    burn_in_mask: np.ndarray
    train_mask: np.ndarray
    padding_mask: np.ndarray
    episode_ids: list[list[str | None]]
    step_indices: np.ndarray
    metadata: dict[str, Any]


class ReplayBufferV2:
    """Simple episode-aware replay buffer for v2 recurrent rollouts.

    Convention:
    - ``total_len = burn_in + seq_len``.
    - the first ``burn_in`` positions have ``burn_in_mask=True`` and are not
      training targets.
    - the last ``seq_len`` positions have ``train_mask=True`` unless padded.
    - sequences never cross episode boundaries.
    - short suffixes are padded with zeros and ``padding_mask=True``.
    """

    def __init__(self, *, capacity: int | None = None) -> None:
        if capacity is not None and capacity <= 0:
            raise ValueError("capacity must be positive or None")
        self.capacity = capacity
        self._episodes: dict[str, list[TransitionV2]] = {}
        self._episode_order: list[str] = []
        self._size = 0

    def add_transition(self, transition: TransitionV2) -> None:
        _assert_transition_clean(transition)
        episode = self._episodes.setdefault(transition.episode_id, [])
        if transition.episode_id not in self._episode_order:
            self._episode_order.append(transition.episode_id)
        episode.append(transition)
        episode.sort(key=lambda item: item.step_index)
        self._size += 1
        self._enforce_capacity()

    def add_episode(self, transitions: list[TransitionV2]) -> None:
        if not transitions:
            return
        episode_ids = {transition.episode_id for transition in transitions}
        if len(episode_ids) != 1:
            raise ValueError(f"episode contains multiple ids: {sorted(episode_ids)}")
        for transition in sorted(transitions, key=lambda item: item.step_index):
            self.add_transition(transition)

    def __len__(self) -> int:
        return self._size

    def clear(self) -> None:
        self._episodes.clear()
        self._episode_order.clear()
        self._size = 0

    def stats(self) -> dict[str, Any]:
        return {
            "transitions": self._size,
            "episodes": len(self._episodes),
            "capacity": self.capacity,
            "episode_lengths": {
                episode_id: len(transitions)
                for episode_id, transitions in self._episodes.items()
            },
        }

    def sample_sequences(
        self,
        *,
        batch_size: int,
        seq_len: int,
        burn_in: int = 0,
        seed: int | None = None,
    ) -> SequenceBatchV2:
        if batch_size <= 0:
            raise ValueError("batch_size must be positive")
        if seq_len <= 0:
            raise ValueError("seq_len must be positive")
        if burn_in < 0:
            raise ValueError("burn_in must be >= 0")
        if self._size == 0:
            raise ValueError("cannot sample from an empty replay buffer")

        rng = random.Random(seed)
        candidates = self._candidate_starts()
        windows = []
        for _ in range(batch_size):
            episode_id, start = rng.choice(candidates)
            windows.append((episode_id, self._episodes[episode_id], start))
        return _make_batch(windows, seq_len=seq_len, burn_in=burn_in)

    def _candidate_starts(self) -> list[tuple[str, int]]:
        candidates: list[tuple[str, int]] = []
        for episode_id in self._episode_order:
            episode = self._episodes.get(episode_id) or []
            for start in range(len(episode)):
                if episode[start].done and len(episode) > 1:
                    continue
                candidates.append((episode_id, start))
        return candidates

    def _enforce_capacity(self) -> None:
        if self.capacity is None:
            return
        while self._size > self.capacity and self._episode_order:
            first_id = self._episode_order[0]
            episode = self._episodes[first_id]
            episode.pop(0)
            self._size -= 1
            if not episode:
                self._episode_order.pop(0)
                del self._episodes[first_id]


def _make_batch(
    windows: list[tuple[str, list[TransitionV2], int]],
    *,
    seq_len: int,
    burn_in: int,
) -> SequenceBatchV2:
    total_len = burn_in + seq_len
    batch_size = len(windows)
    shapes = encoding_v2.shapes_v2()

    public = np.zeros((batch_size, total_len, *shapes["public_features"]), dtype=np.float32)
    private = np.zeros(
        (batch_size, total_len, *shapes["private_memory_features"]),
        dtype=np.float32,
    )
    events = np.zeros((batch_size, total_len, *shapes["event_features"]), dtype=np.float32)
    stability = np.zeros(
        (batch_size, total_len, *shapes["slot_stability_features"]),
        dtype=np.float32,
    )
    action_type = np.zeros((batch_size, total_len, *shapes["action_type_mask"]), dtype=bool)
    argument_masks = {
        name: np.zeros((batch_size, total_len, *shape), dtype=bool)
        for name, shape in shapes["argument_masks"].items()
    }

    legacy_mask_items: list[np.ndarray | None] = []
    actions_v2: list[list[dict[str, Any] | None]] = []
    legacy_ids = np.full((batch_size, total_len), -1, dtype=np.int64)
    rewards = np.zeros((batch_size, total_len), dtype=np.float32)
    dones = np.zeros((batch_size, total_len), dtype=bool)
    done_mask = np.zeros((batch_size, total_len), dtype=bool)
    burn_in_mask = np.zeros((batch_size, total_len), dtype=bool)
    train_mask = np.zeros((batch_size, total_len), dtype=bool)
    padding_mask = np.ones((batch_size, total_len), dtype=bool)
    step_indices = np.full((batch_size, total_len), -1, dtype=np.int64)
    episode_ids: list[list[str | None]] = []

    for batch_idx, (episode_id, episode, start) in enumerate(windows):
        row_actions: list[dict[str, Any] | None] = [None] * total_len
        row_episode_ids: list[str | None] = [None] * total_len
        window = episode[start : start + total_len]
        for t, transition in enumerate(window):
            _assert_transition_clean(transition)
            encoded = transition.obs_encoded_v2 or encoding_v2.encode_observation_v2(
                transition.obs_raw
            )
            public[batch_idx, t] = encoded.public_features
            private[batch_idx, t] = encoded.private_memory_features
            events[batch_idx, t] = encoded.event_features
            stability[batch_idx, t] = encoded.slot_stability_features
            action_type[batch_idx, t] = encoded.action_type_mask
            for name, mask in encoded.argument_masks.items():
                argument_masks[name][batch_idx, t] = mask
            legacy_mask_items.append(encoded.legacy_action_mask)
            row_actions[t] = dict(transition.action_v2) if transition.action_v2 else None
            legacy_ids[batch_idx, t] = (
                int(transition.legacy_action_id)
                if transition.legacy_action_id is not None
                else -1
            )
            rewards[batch_idx, t] = float(transition.reward)
            dones[batch_idx, t] = bool(transition.done)
            done_mask[batch_idx, t] = bool(transition.done)
            padding_mask[batch_idx, t] = False
            row_episode_ids[t] = episode_id
            step_indices[batch_idx, t] = int(transition.step_index)

            if transition.done:
                break

        burn_in_mask[batch_idx, :burn_in] = ~padding_mask[batch_idx, :burn_in]
        train_mask[batch_idx, burn_in:] = ~padding_mask[batch_idx, burn_in:]
        actions_v2.append(row_actions)
        episode_ids.append(row_episode_ids)

    legacy_action_mask = None
    if legacy_mask_items and all(mask is not None for mask in legacy_mask_items):
        legacy_shape = legacy_mask_items[0].shape  # type: ignore[union-attr]
        legacy_action_mask = np.zeros((batch_size, total_len, *legacy_shape), dtype=bool)
        cursor = 0
        for batch_idx, (_, episode, start) in enumerate(windows):
            window = episode[start : start + total_len]
            for t, _transition in enumerate(window):
                mask = legacy_mask_items[cursor]
                cursor += 1
                if mask is not None:
                    legacy_action_mask[batch_idx, t] = mask

    return SequenceBatchV2(
        public_features=public,
        private_memory_features=private,
        event_features=events,
        slot_stability_features=stability,
        action_type_mask=action_type,
        argument_masks=argument_masks,
        legacy_action_mask=legacy_action_mask,
        actions_v2=actions_v2,
        legacy_action_ids=legacy_ids,
        rewards=rewards,
        dones=dones,
        done_mask=done_mask,
        burn_in_mask=burn_in_mask,
        train_mask=train_mask,
        padding_mask=padding_mask,
        episode_ids=episode_ids,
        step_indices=step_indices,
        metadata={
            "batch_size": batch_size,
            "seq_len": seq_len,
            "burn_in": burn_in,
            "total_len": total_len,
        },
    )


def _assert_transition_clean(transition: TransitionV2) -> None:
    forbidden = _find_forbidden_keys(transition.obs_raw)
    if transition.next_obs_raw is not None:
        forbidden.update(_find_forbidden_keys(transition.next_obs_raw))
    forbidden.update(_find_forbidden_keys(transition.info))
    if forbidden:
        raise ValueError(
            f"forbidden policy/debug keys in transition: {sorted(forbidden)}"
        )


def _find_forbidden_keys(value: Any) -> set[str]:
    found: set[str] = set()
    if isinstance(value, dict):
        for key, child in value.items():
            if key in encoding_v2.FORBIDDEN_POLICY_KEYS:
                found.add(str(key))
            found.update(_find_forbidden_keys(child))
    elif isinstance(value, list):
        for child in value:
            found.update(_find_forbidden_keys(child))
    return found
