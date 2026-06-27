"""Tests courts pour la piste Self-Imitation Learning."""

from __future__ import annotations

import importlib
import random
from types import SimpleNamespace

import gymnasium as gym
import numpy as np
from gymnasium import spaces

from self_imitation_buffer import SelfImitationBuffer
from self_imitation_callback import SelfImitationCallback
from self_imitation_ppo import SelfImitationPPO


def _episode(length: int, obs_dim: int = 4, n_actions: int = 3):
    observations = [np.full(obs_dim, i, dtype=np.float32) for i in range(length)]
    actions = [i % n_actions for i in range(length)]
    masks = [np.ones(n_actions, dtype=np.float32) for _ in range(length)]
    return observations, actions, masks


def test_buffer_adds_and_samples() -> None:
    buffer = SelfImitationBuffer(
        max_transitions=10,
        min_episodes_per_context=1,
        rng=random.Random(0),
    )
    obs, actions, masks = _episode(3)

    assert buffer.add_episode(
        observations=obs,
        actions=actions,
        action_masks=masks,
        context={"hard": True},
        infos=[{"won": True}],
    )
    batch = buffer.sample(5)

    assert buffer.transition_count == 3
    assert buffer.episode_count == 1
    assert batch is not None
    assert batch.observations.shape == (5, 4)
    assert batch.actions.shape == (5,)
    assert batch.action_masks.shape == (5, 3)


def test_callback_does_not_store_lost_episode() -> None:
    buffer = SelfImitationBuffer(max_transitions=10, min_episodes_per_context=1)
    callback = SelfImitationCallback(buffer=buffer)
    fake_model = SimpleNamespace(
        num_timesteps=1,
        action_space=spaces.Discrete(3),
        logger=SimpleNamespace(record=lambda *args, **kwargs: None),
        get_env=lambda: SimpleNamespace(num_envs=1),
        _last_obs=np.asarray([[1.0, 0.0, 0.0, 0.0]], dtype=np.float32),
    )
    callback.init_callback(fake_model)
    callback.on_training_start({}, {})
    callback.locals = {
        "infos": [{"won": False, "rank": 2, "hard": True}],
        "dones": [True],
        "actions": np.asarray([1]),
        "action_masks": np.asarray([[1, 1, 0]], dtype=np.float32),
    }

    assert callback._on_step()
    assert buffer.episode_count == 0
    assert buffer.transition_count == 0


def test_min_episodes_per_context_blocks_activation() -> None:
    buffer = SelfImitationBuffer(max_transitions=10, min_episodes_per_context=2)
    obs, actions, masks = _episode(2)

    buffer.add_episode(
        observations=obs,
        actions=actions,
        action_masks=masks,
        context={"hard": True},
    )

    assert not buffer.bc_active
    assert buffer.sample(4) is None


def test_balanced_sampling_with_missing_context() -> None:
    buffer = SelfImitationBuffer(
        max_transitions=20,
        min_episodes_per_context=1,
        rng=random.Random(1),
    )
    obs, actions, masks = _episode(3)
    buffer.add_episode(
        observations=obs,
        actions=actions,
        action_masks=masks,
        context={"hard": False},
    )

    batch = buffer.sample(8)

    assert batch is not None
    assert batch.observations.shape == (8, 4)
    assert all(ctx["hard"] is False for ctx in batch.contexts)


def test_imports() -> None:
    assert importlib.import_module("self_imitation_buffer")
    assert importlib.import_module("self_imitation_callback")
    assert importlib.import_module("self_imitation_ppo")
    assert importlib.import_module("train_self_imitation")


class _TinyDiscreteEnv(gym.Env):
    metadata = {"render_modes": []}

    def __init__(self) -> None:
        self.observation_space = spaces.Box(-1.0, 1.0, shape=(4,), dtype=np.float32)
        self.action_space = spaces.Discrete(3)

    def reset(self, *, seed=None, options=None):  # type: ignore[override]
        super().reset(seed=seed)
        return np.zeros(4, dtype=np.float32), {}

    def step(self, action):  # type: ignore[override]
        return np.zeros(4, dtype=np.float32), 0.0, True, False, {}


def test_bc_effective_loss_is_capped() -> None:
    buffer = SelfImitationBuffer(max_transitions=10, min_episodes_per_context=1)
    obs, actions, masks = _episode(4)
    buffer.add_episode(
        observations=obs,
        actions=actions,
        action_masks=masks,
        context={"hard": False},
    )
    cap = 0.0001
    model = SelfImitationPPO(
        "MlpPolicy",
        _TinyDiscreteEnv(),
        n_steps=2,
        batch_size=2,
        self_imitation_buffer=buffer,
        bc_coef=1.0,
        bc_batch_size=4,
        bc_effective_loss_cap=cap,
    )

    bc_loss, bc_effective = model._compute_bc_losses()

    assert bc_loss is not None
    assert bc_effective is not None
    assert float(bc_effective.detach().cpu().item()) <= cap + 1e-12


CHECKS = [
    ("buffer ajoute/sample correctement", test_buffer_adds_and_samples),
    ("épisode perdu non stocké", test_callback_does_not_store_lost_episode),
    ("seuil min_episodes bloque l'activation", test_min_episodes_per_context_blocks_activation),
    ("sampling équilibré avec contexte manquant", test_balanced_sampling_with_missing_context),
    ("imports SIL", test_imports),
    ("cap bc_effective_loss", test_bc_effective_loss_is_capped),
]


def main() -> int:
    all_ok = True
    print("=== test_self_imitation : 6 vérifications ===")
    for name, fn in CHECKS:
        try:
            fn()
            ok = True
            detail = "ok"
        except Exception as e:  # noqa: BLE001
            ok = False
            detail = f"{type(e).__name__}: {e}"
        all_ok = all_ok and ok
        print(f"  [{'OK ' if ok else 'FAIL'}] {name} — {detail}")
    print("=== " + ("TOUT VERT" if all_ok else "ÉCHEC") + " ===")
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
