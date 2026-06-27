"""Callback SB3 pour collecter des épisodes gagnants Self-Imitation."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import numpy as np
from stable_baselines3.common.callbacks import BaseCallback

from self_imitation_buffer import SelfImitationBuffer


_BAD_TERMINAL_KEYS = (
    "runner_crashed",
    "runner_timeout",
    "engine_recoverable_error",
    "engine_internal_error",
)


@dataclass
class _WorkerEpisode:
    observations: list[np.ndarray] = field(default_factory=list)
    actions: list[int] = field(default_factory=list)
    action_masks: list[np.ndarray] = field(default_factory=list)
    infos: list[dict[str, Any]] = field(default_factory=list)

    def append(
        self,
        *,
        observation: np.ndarray,
        action: int,
        action_mask: np.ndarray,
        info: dict[str, Any],
    ) -> None:
        self.observations.append(np.asarray(observation, dtype=np.float32).copy())
        self.actions.append(int(action))
        self.action_masks.append(np.asarray(action_mask, dtype=np.float32).copy())
        self.infos.append(dict(info))

    def clear(self) -> None:
        self.observations.clear()
        self.actions.clear()
        self.action_masks.clear()
        self.infos.clear()


class SelfImitationCallback(BaseCallback):
    """Reconstruit les épisodes par worker et stocke seulement les victoires."""

    def __init__(
        self,
        *,
        buffer: SelfImitationBuffer,
        log_every_steps: int = 10_000,
    ) -> None:
        super().__init__()
        self.buffer = buffer
        self.log_every_steps = int(log_every_steps)
        self.winning_episodes_collected = 0
        self._episodes: list[_WorkerEpisode] = []
        self._next_log_step = 0

    def _on_training_start(self) -> None:
        n_envs = int(getattr(self.training_env, "num_envs", 1))
        self._episodes = [_WorkerEpisode() for _ in range(n_envs)]
        self._next_log_step = self.log_every_steps

    def _on_step(self) -> bool:
        infos = list(self.locals.get("infos", []))
        dones = self.locals.get("dones")
        actions = self.locals.get("actions")
        action_masks = self.locals.get("action_masks")
        observations = getattr(self.model, "_last_obs", None)

        if observations is None or actions is None:
            self._maybe_log()
            return True

        if dones is None:
            dones = [False] * len(infos)
        if action_masks is None:
            action_masks = np.ones((len(infos), int(self.model.action_space.n)), dtype=np.float32)

        actions_arr = np.asarray(actions).reshape(-1)
        obs_arr = np.asarray(observations)
        mask_arr = np.asarray(action_masks)

        n = min(len(infos), len(dones), len(actions_arr), len(obs_arr), len(mask_arr), len(self._episodes))
        for idx in range(n):
            info = dict(infos[idx])
            self._episodes[idx].append(
                observation=obs_arr[idx],
                action=int(actions_arr[idx]),
                action_mask=mask_arr[idx],
                info=info,
            )

            if bool(dones[idx]):
                if self._is_positive_terminal(info):
                    context = {"hard": bool(info.get("hard", False))}
                    added = self.buffer.add_episode(
                        observations=self._episodes[idx].observations,
                        actions=self._episodes[idx].actions,
                        action_masks=self._episodes[idx].action_masks,
                        context=context,
                        infos=self._episodes[idx].infos,
                    )
                    if added:
                        self.winning_episodes_collected += 1
                self._episodes[idx].clear()

        self._maybe_log()
        return True

    def _is_positive_terminal(self, info: dict[str, Any]) -> bool:
        if any(info.get(key) for key in _BAD_TERMINAL_KEYS):
            return False
        return info.get("won") is True

    def _maybe_log(self) -> None:
        if self.num_timesteps < self._next_log_step:
            return
        self.logger.record("sil/buffer_transitions", self.buffer.transition_count)
        self.logger.record("sil/winning_episodes", self.winning_episodes_collected)
        self.logger.record(
            "sil/context_episodes_hard_true",
            self.buffer.context_episode_count({"hard": True}),
        )
        self.logger.record(
            "sil/context_episodes_hard_false",
            self.buffer.context_episode_count({"hard": False}),
        )
        self.logger.record("sil/bc_active", 1.0 if self.buffer.bc_active else 0.0)
        while self._next_log_step <= self.num_timesteps:
            self._next_log_step += self.log_every_steps
