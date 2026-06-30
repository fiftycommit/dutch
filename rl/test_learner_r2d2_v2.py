"""Smoke tests for the minimal AgentInterface v2 R2D2 learner.

Run from rl/:
    uv run python test_learner_r2d2_v2.py
"""

from __future__ import annotations

import dataclasses
from typing import Any

import numpy as np
import torch

import encoding_v2
import learner_r2d2_v2
import model_r2d2_v2
import replay_buffer_v2
import rollout_v2


def _obs(step: int) -> dict[str, Any]:
    return {
        "type": "observation",
        "done": False,
        "micro_phase": "reaction",
        "action_mask": {"pass_tick": True},
        "obs": {
            "phase": "reaction",
            "micro_phase": "reaction",
            "turn_count": step,
            "action_count": step,
            "num_players": 3,
            "deck_size": 30,
            "discard_size": 10,
            "top_discard_value": "7",
            "top_discard_points": 7,
            "dutch_called": False,
            "dutch_caller_is_me": False,
            "hand_size": 3,
            "opponents": [
                {"seat": "p1", "hand_size": 4},
                {"seat": "p2", "hand_size": 2},
            ],
        },
        "recent_events": [],
        "slot_stability": {
            "players": [
                {
                    "seat": 0,
                    "player_id": "p0",
                    "slots": [
                        {
                            "slot": 0,
                            "turns_since_changed": 1,
                            "actions_since_changed": step,
                            "changed_this_turn": False,
                            "last_changed_reason": "initial",
                        }
                    ],
                }
            ],
            "recent_changes": [],
        },
        "legal_private_memory": {
            "own_hand": {
                "slots": [
                    {
                        "slot": 0,
                        "known": True,
                        "believed_value": "7",
                        "believed_match_value": "7",
                        "believed_points": 7,
                        "valid": True,
                        "confidence": 1.0,
                        "age_actions": step,
                        "age_turns": 1,
                        "source": "mental_map",
                    }
                ]
            },
            "opponents": [],
        },
        "legal_action_v2": {
            "available_action_types": ["pass_tick"],
            "masks": {"action_type": {"pass_tick": True}},
            "actions": [
                {
                    "action_v2": {"action_type": "pass_tick"},
                    "legacy_action_id": 1,
                }
            ],
        },
    }


def _transition(
    episode_id: str,
    step: int,
    *,
    done: bool = False,
) -> rollout_v2.TransitionV2:
    obs = _obs(step)
    next_obs = None if done else _obs(step + 1)
    return rollout_v2.TransitionV2(
        obs_raw=obs,
        obs_encoded_v2=encoding_v2.encode_observation_v2(obs),
        action_v2={"action_type": "pass_tick"},
        legacy_action_id=1,
        reward=1.0 + float(step),
        done=done,
        next_obs_raw=next_obs,
        next_obs_encoded_v2=(
            None if next_obs is None else encoding_v2.encode_observation_v2(next_obs)
        ),
        info={},
        episode_id=episode_id,
        step_index=step,
    )


def _batch() -> replay_buffer_v2.SequenceBatchV2:
    buffer = replay_buffer_v2.ReplayBufferV2()
    buffer.add_episode(
        [
            _transition("ep-a", 0),
            _transition("ep-a", 1),
            _transition("ep-a", 2, done=True),
        ]
    )
    return buffer.sample_sequences(batch_size=1, seq_len=2, burn_in=1, seed=0)


def _prioritized_buffer() -> replay_buffer_v2.ReplayBufferV2:
    buffer = replay_buffer_v2.ReplayBufferV2(prioritized=True)
    buffer.add_episode(
        [
            _transition("ep-a", 0),
            _transition("ep-a", 1),
            _transition("ep-a", 2, done=True),
        ]
    )
    return buffer


def _model() -> model_r2d2_v2.R2D2AgentV2:
    torch.manual_seed(0)
    return model_r2d2_v2.R2D2AgentV2(hidden_dim=16, embed_dim=8)


def _learner(
    *,
    target_update_interval: int = 100,
    grad_clip_norm: float | None = 1.0,
) -> learner_r2d2_v2.R2D2LearnerV2:
    return learner_r2d2_v2.R2D2LearnerV2(
        online_model=_model(),
        config=learner_r2d2_v2.LearnerConfigV2(
            learning_rate=1.0e-3,
            gamma=0.9,
            n_step=1,
            grad_clip_norm=grad_clip_norm,
            target_update_interval=target_update_interval,
        ),
    )


def _state_clone(model: torch.nn.Module) -> dict[str, torch.Tensor]:
    return {
        name: param.detach().clone()
        for name, param in model.state_dict().items()
    }


def _states_equal(
    left: dict[str, torch.Tensor],
    right: dict[str, torch.Tensor],
) -> bool:
    return all(torch.equal(left[name], right[name]) for name in left.keys())


def _any_param_changed(
    before: dict[str, torch.Tensor],
    model: torch.nn.Module,
) -> bool:
    after = model.state_dict()
    return any(not torch.equal(before[name], after[name]) for name in before.keys())


def test_create_learner_without_crash() -> None:
    learner = _learner()
    if learner.state.step != 0:
        raise AssertionError("new learner step should be zero")
    if not _states_equal(
        _state_clone(learner.online_model),
        _state_clone(learner.target_model),
    ):
        raise AssertionError("target model was not initialized from online model")


def test_train_step_returns_finite_metrics() -> None:
    learner = _learner()
    metrics = learner.train_step(_batch())
    for key in ["loss", "grad_norm", "valid_steps", "mean_q_taken", "mean_td_target"]:
        if key not in metrics:
            raise AssertionError(f"missing metric {key}")
        if not torch.isfinite(torch.tensor(metrics[key])):
            raise AssertionError(f"metric {key} is not finite: {metrics[key]}")
    if learner.state.step != 1 or learner.state.last_loss != metrics["loss"]:
        raise AssertionError("learner state was not updated")


def test_train_step_changes_online_params() -> None:
    learner = _learner()
    before = _state_clone(learner.online_model)
    learner.train_step(_batch())
    if not _any_param_changed(before, learner.online_model):
        raise AssertionError("online parameters did not change after train_step")


def test_target_does_not_change_before_sync() -> None:
    learner = _learner(target_update_interval=100)
    before_target = _state_clone(learner.target_model)
    learner.train_step(_batch())
    after_target = _state_clone(learner.target_model)
    if not _states_equal(before_target, after_target):
        raise AssertionError("target model changed before scheduled sync")


def test_sync_target_copies_online_weights() -> None:
    learner = _learner(target_update_interval=100)
    learner.train_step(_batch())
    learner.sync_target()
    if not _states_equal(
        _state_clone(learner.online_model),
        _state_clone(learner.target_model),
    ):
        raise AssertionError("sync_target did not copy online weights")


def test_target_update_interval_syncs() -> None:
    learner = _learner(target_update_interval=1)
    metrics = learner.train_step(_batch())
    if metrics["target_synced"] != 1.0:
        raise AssertionError("target sync metric should be true")
    if not _states_equal(
        _state_clone(learner.online_model),
        _state_clone(learner.target_model),
    ):
        raise AssertionError("target_update_interval=1 did not sync target")


def test_grad_clipping_no_crash_and_valid_steps_positive() -> None:
    learner = _learner(grad_clip_norm=0.1)
    metrics = learner.train_step(_batch())
    if metrics["valid_steps"] <= 0:
        raise AssertionError("valid_steps should be positive")
    if metrics["grad_norm"] < 0:
        raise AssertionError("grad_norm should be non-negative")


def test_no_nan_in_loss_or_gradients() -> None:
    learner = _learner()
    metrics = learner.train_step(_batch())
    if not torch.isfinite(torch.tensor(metrics["loss"])):
        raise AssertionError("loss is not finite")
    for name, param in learner.online_model.named_parameters():
        if param.grad is not None and not torch.isfinite(param.grad).all():
            raise AssertionError(f"non-finite gradient in {name}")


def test_soft_update_target_smoke() -> None:
    learner = _learner(target_update_interval=100)
    learner.train_step(_batch())
    learner.soft_update_target(0.5)
    if learner.target_model.training:
        raise AssertionError("target model should stay eval after soft update")


def test_learner_does_not_read_raw_observation_fields() -> None:
    learner = _learner()
    learner.train_step(_batch())
    if hasattr(learner, "obs_raw") or hasattr(learner, "info"):
        raise AssertionError("learner leaked raw observation fields")


def _prioritized_learner(*, double_q: bool = False) -> learner_r2d2_v2.R2D2LearnerV2:
    return learner_r2d2_v2.R2D2LearnerV2(
        online_model=_model(),
        config=learner_r2d2_v2.LearnerConfigV2(
            learning_rate=1.0e-3,
            gamma=0.9,
            n_step=1,
            grad_clip_norm=1.0,
            target_update_interval=100,
            double_q=double_q,
            priority_eta=0.8,
        ),
    )


def test_prioritized_train_step_updates_buffer_priorities() -> None:
    buffer = _prioritized_buffer()
    batch = buffer.sample_sequences(batch_size=2, seq_len=2, burn_in=1, seed=0)
    if batch.is_weights is None or batch.sample_indices is None:
        raise AssertionError("prioritized batch missing PER fields")
    learner = _prioritized_learner()
    metrics = learner.train_step(batch, replay_buffer=buffer)
    if metrics["prioritized"] != 1.0:
        raise AssertionError("prioritized metric should be 1.0")
    if not buffer._priorities:
        raise AssertionError("buffer priorities were not updated from TD error")
    for value in buffer._priorities.values():
        if not np.isfinite(value) or value <= 0.0:
            raise AssertionError(f"stored priority is not positive-finite: {value}")


def test_is_weights_scale_learner_loss() -> None:
    buffer = _prioritized_buffer()
    batch = buffer.sample_sequences(batch_size=2, seq_len=2, burn_in=1, seed=0)
    ones = dataclasses.replace(batch, is_weights=np.ones_like(batch.is_weights))
    halved = dataclasses.replace(batch, is_weights=0.5 * np.ones_like(batch.is_weights))

    m_full = _prioritized_learner().train_step(ones)
    m_half = _prioritized_learner().train_step(halved)
    if abs(m_half["loss"] - 0.5 * m_full["loss"]) > 1e-6:
        raise AssertionError(
            f"IS weights did not scale learner loss: {m_half['loss']} vs {m_full['loss']}"
        )


def test_double_q_and_priority_eta_metrics_present() -> None:
    buffer = _prioritized_buffer()
    batch = buffer.sample_sequences(batch_size=2, seq_len=2, burn_in=1, seed=1)
    learner = _prioritized_learner(double_q=True)
    metrics = learner.train_step(batch, replay_buffer=buffer)
    expected = [
        "loss",
        "weighted_loss",
        "mean_td_error",
        "max_td_error",
        "mean_priority",
        "mean_is_weight",
        "grad_norm",
        "valid_steps",
        "target_synced",
        "learner_step",
        "double_q",
        "prioritized",
        "priority_eta",
    ]
    for key in expected:
        if key not in metrics:
            raise AssertionError(f"missing metric {key}")
        if not torch.isfinite(torch.tensor(metrics[key])):
            raise AssertionError(f"metric {key} not finite: {metrics[key]}")
    if metrics["double_q"] != 1.0:
        raise AssertionError("double_q metric should be 1.0 when enabled")
    if metrics["priority_eta"] != 0.8:
        raise AssertionError("priority_eta metric should reflect config")


def main() -> int:
    tests = [
        test_create_learner_without_crash,
        test_train_step_returns_finite_metrics,
        test_train_step_changes_online_params,
        test_target_does_not_change_before_sync,
        test_sync_target_copies_online_weights,
        test_target_update_interval_syncs,
        test_grad_clipping_no_crash_and_valid_steps_positive,
        test_no_nan_in_loss_or_gradients,
        test_soft_update_target_smoke,
        test_learner_does_not_read_raw_observation_fields,
        test_prioritized_train_step_updates_buffer_priorities,
        test_is_weights_scale_learner_loss,
        test_double_q_and_priority_eta_metrics_present,
    ]
    print("=== test_learner_r2d2_v2 ===")
    for test in tests:
        test()
        print(f"  [OK] {test.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
