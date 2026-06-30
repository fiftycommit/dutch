"""Smoke tests for the AgentInterface v2 sequential replay buffer.

Run from rl/:
    uv run python test_replay_buffer_v2.py
"""

from __future__ import annotations

from typing import Any

import encoding_v2
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
        "recent_events": [
            {
                "turn_count": step,
                "action_count": step,
                "phase": "reaction",
                "event_type": "discard_visible",
                "actor": "p1",
                "card_visible": True,
                "card_value": "7",
                "card_match_value": "7",
                "card_points": 7,
                "slot": 1,
                "discard_reason": "match_discard",
                "replaced_slot": None,
            }
        ],
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
                    "legacy_action_id": 6185,
                    "legacy_kind": "pass_tick",
                }
            ],
            "legacy_action_ids": {"action_type=pass_tick": 6185},
        },
    }


def _transition(
    episode_id: str,
    step: int,
    *,
    done: bool = False,
    reward: float | None = None,
) -> rollout_v2.TransitionV2:
    obs = _obs(step)
    next_obs = None if done else _obs(step + 1)
    return rollout_v2.TransitionV2(
        obs_raw=obs,
        obs_encoded_v2=encoding_v2.encode_observation_v2(obs),
        action_v2={"action_type": "pass_tick"},
        legacy_action_id=6185 + step,
        reward=float(step if reward is None else reward),
        done=done,
        next_obs_raw=next_obs,
        next_obs_encoded_v2=(
            None if next_obs is None else encoding_v2.encode_observation_v2(next_obs)
        ),
        info={},
        episode_id=episode_id,
        step_index=step,
    )


def _episode(episode_id: str, length: int, *, done_last: bool = True) -> list[rollout_v2.TransitionV2]:
    return [
        _transition(episode_id, step, done=(done_last and step == length - 1))
        for step in range(length)
    ]


def test_add_transition_increases_size() -> None:
    buffer = replay_buffer_v2.ReplayBufferV2()
    buffer.add_transition(_transition("ep", 0))
    if len(buffer) != 1:
        raise AssertionError("add_transition did not increase size")


def test_add_episode_preserves_episode_and_order() -> None:
    buffer = replay_buffer_v2.ReplayBufferV2()
    buffer.add_episode([_transition("ep", 2), _transition("ep", 0), _transition("ep", 1)])
    batch = buffer.sample_sequences(batch_size=1, seq_len=3, burn_in=0, seed=1)
    non_padded = [idx for idx in batch.step_indices[0].tolist() if idx >= 0]
    if non_padded != [0, 1, 2]:
        raise AssertionError(f"episode order not preserved: {non_padded}")


def test_sample_sequences_batch_size_and_total_len() -> None:
    buffer = replay_buffer_v2.ReplayBufferV2()
    buffer.add_episode(_episode("ep", 4))
    batch = buffer.sample_sequences(batch_size=3, seq_len=2, burn_in=1, seed=0)
    if batch.public_features.shape[:2] != (3, 3):
        raise AssertionError(f"bad batch/time shape: {batch.public_features.shape[:2]}")
    if batch.metadata["total_len"] != 3:
        raise AssertionError("total_len should be burn_in + seq_len")


def test_burn_in_train_and_padding_masks() -> None:
    buffer = replay_buffer_v2.ReplayBufferV2()
    buffer.add_episode([_transition("ep", 0, done=True)])
    batch = buffer.sample_sequences(batch_size=1, seq_len=3, burn_in=1, seed=0)
    if batch.burn_in_mask.tolist() != [[True, False, False, False]]:
        raise AssertionError(f"bad burn_in_mask: {batch.burn_in_mask}")
    if batch.train_mask.tolist() != [[False, False, False, False]]:
        raise AssertionError(f"bad train_mask with padding: {batch.train_mask}")
    if batch.padding_mask.tolist() != [[False, True, True, True]]:
        raise AssertionError(f"bad padding_mask: {batch.padding_mask}")


def test_done_mask_and_rewards_align() -> None:
    buffer = replay_buffer_v2.ReplayBufferV2()
    buffer.add_episode([_transition("ep", 0, reward=0.0), _transition("ep", 1, done=True, reward=5.0)])
    batch = buffer.sample_sequences(batch_size=1, seq_len=2, burn_in=0, seed=0)
    if batch.done_mask.tolist() != [[False, True]]:
        raise AssertionError(f"bad done_mask: {batch.done_mask}")
    if batch.rewards.tolist() != [[0.0, 5.0]]:
        raise AssertionError(f"bad rewards: {batch.rewards}")
    if batch.dones.tolist() != [[False, True]]:
        raise AssertionError(f"bad dones: {batch.dones}")


def test_no_sequence_crosses_episodes() -> None:
    buffer = replay_buffer_v2.ReplayBufferV2()
    buffer.add_episode(_episode("ep-a", 2))
    buffer.add_episode(_episode("ep-b", 2))
    batch = buffer.sample_sequences(batch_size=20, seq_len=3, burn_in=1, seed=2)
    for row in batch.episode_ids:
        seen = {episode_id for episode_id in row if episode_id is not None}
        if len(seen) > 1:
            raise AssertionError(f"sequence crossed episodes: {row}")


def test_actions_and_legacy_ids_align() -> None:
    buffer = replay_buffer_v2.ReplayBufferV2()
    buffer.add_episode([_transition("ep", 0), _transition("ep", 1, done=True)])
    batch = buffer.sample_sequences(batch_size=1, seq_len=2, burn_in=0, seed=0)
    if batch.actions_v2[0][0] != {"action_type": "pass_tick"}:
        raise AssertionError("action_v2 missing at step 0")
    if batch.legacy_action_ids.tolist() != [[6185, 6186]]:
        raise AssertionError(f"bad legacy ids: {batch.legacy_action_ids}")


def test_sampling_is_deterministic_with_seed() -> None:
    buffer = replay_buffer_v2.ReplayBufferV2()
    buffer.add_episode(_episode("ep", 5))
    a = buffer.sample_sequences(batch_size=4, seq_len=2, burn_in=1, seed=99)
    b = buffer.sample_sequences(batch_size=4, seq_len=2, burn_in=1, seed=99)
    if a.step_indices.tolist() != b.step_indices.tolist():
        raise AssertionError("sample_sequences is not deterministic for a fixed seed")


def test_feature_shapes_match_encoding_v2() -> None:
    buffer = replay_buffer_v2.ReplayBufferV2()
    buffer.add_episode(_episode("ep", 2))
    batch = buffer.sample_sequences(batch_size=1, seq_len=2, burn_in=1, seed=0)
    shapes = encoding_v2.shapes_v2()
    if batch.public_features.shape[2:] != shapes["public_features"]:
        raise AssertionError("public feature shape mismatch")
    if batch.event_features.shape[2:] != shapes["event_features"]:
        raise AssertionError("event feature shape mismatch")
    if batch.argument_masks["match_slot"].shape[2:] != shapes["argument_masks"]["match_slot"]:
        raise AssertionError("argument mask shape mismatch")


def test_anti_leak_rejects_forbidden_keys() -> None:
    buffer = replay_buffer_v2.ReplayBufferV2()
    obs = {**_obs(0), "true_score": {"p1": 42}}
    transition = rollout_v2.TransitionV2(
        obs_raw=obs,
        obs_encoded_v2=encoding_v2.encode_observation_v2(obs),
        action_v2={"action_type": "pass_tick"},
        legacy_action_id=6185,
        reward=0.0,
        done=False,
        next_obs_raw=_obs(1),
        next_obs_encoded_v2=encoding_v2.encode_observation_v2(_obs(1)),
        info={},
        episode_id="ep",
        step_index=0,
    )
    try:
        buffer.add_transition(transition)
    except ValueError as exc:
        if "true_score" not in str(exc):
            raise AssertionError(f"unexpected error: {exc}") from exc
    else:
        raise AssertionError("leaky transition was accepted")


def test_stats_and_clear() -> None:
    buffer = replay_buffer_v2.ReplayBufferV2(capacity=10)
    buffer.add_episode(_episode("ep", 2))
    stats = buffer.stats()
    if stats["transitions"] != 2 or stats["episodes"] != 1:
        raise AssertionError(f"bad stats: {stats}")
    buffer.clear()
    if len(buffer) != 0 or buffer.stats()["episodes"] != 0:
        raise AssertionError("clear did not empty buffer")


def test_uniform_batch_has_no_is_weights() -> None:
    buffer = replay_buffer_v2.ReplayBufferV2()
    buffer.add_episode(_episode("ep", 4))
    batch = buffer.sample_sequences(batch_size=2, seq_len=2, burn_in=1, seed=0)
    if batch.is_weights is not None:
        raise AssertionError("uniform sampling should not produce is_weights")
    if batch.sample_indices is None or len(batch.sample_indices) != 2:
        raise AssertionError("sample_indices should be present even in uniform mode")
    if batch.legal_actions_v2 is None:
        raise AssertionError("legal_actions_v2 should be populated from transitions")


def test_prioritized_is_weights_present_and_finite() -> None:
    buffer = replay_buffer_v2.ReplayBufferV2(prioritized=True)
    buffer.add_episode(_episode("ep", 5))
    batch = buffer.sample_sequences(batch_size=4, seq_len=2, burn_in=1, seed=0)
    if batch.is_weights is None or batch.is_weights.shape != (4,):
        raise AssertionError(f"bad is_weights shape: {batch.is_weights}")
    import numpy as np

    if not np.all(np.isfinite(batch.is_weights)):
        raise AssertionError("is_weights contains non-finite values")
    if np.any(batch.is_weights <= 0.0):
        raise AssertionError("is_weights must be strictly positive")
    if abs(float(batch.is_weights.max()) - 1.0) > 1e-6:
        raise AssertionError("is_weights should be normalized so max == 1")


def test_prioritized_sampling_favors_high_priority() -> None:
    buffer = replay_buffer_v2.ReplayBufferV2(
        prioritized=True,
        priority_alpha=1.0,
        priority_beta=0.0,
    )
    buffer.add_episode([_transition("hi", 0, done=True)])
    buffer.add_episode([_transition("lo", 0, done=True)])
    buffer.update_priorities([("hi", 0), ("lo", 0)], [100.0, 0.0])
    counts = {"hi": 0, "lo": 0}
    for seed in range(40):
        batch = buffer.sample_sequences(batch_size=8, seq_len=1, burn_in=0, seed=seed)
        for key in batch.sample_indices:
            counts[key[0]] += 1
    if counts["hi"] <= counts["lo"]:
        raise AssertionError(f"prioritized sampling did not favor high priority: {counts}")


def test_update_priorities_floors_and_validates() -> None:
    buffer = replay_buffer_v2.ReplayBufferV2(prioritized=True, priority_epsilon=1e-4)
    buffer.add_episode([_transition("ep", 0, done=True)])
    buffer.update_priorities([("ep", 0)], [0.0])
    if buffer._priorities[("ep", 0)] <= 0.0:
        raise AssertionError("priority was not floored above zero")
    # Sampling still works with a floored (non-zero) priority.
    buffer.sample_sequences(batch_size=1, seq_len=1, burn_in=0, seed=0)
    try:
        buffer.update_priorities([("ep", 0)], [1.0, 2.0])
    except ValueError:
        pass
    else:
        raise AssertionError("length mismatch was not rejected")


def test_prioritized_preserves_masks_and_no_episode_crossing() -> None:
    buffer = replay_buffer_v2.ReplayBufferV2(prioritized=True)
    buffer.add_episode(_episode("ep-a", 2))
    buffer.add_episode(_episode("ep-b", 2))
    batch = buffer.sample_sequences(batch_size=20, seq_len=3, burn_in=1, seed=3)
    if batch.burn_in_mask.shape != batch.train_mask.shape != batch.padding_mask.shape:
        raise AssertionError("mask shapes diverged under prioritized sampling")
    for row in batch.episode_ids:
        seen = {episode_id for episode_id in row if episode_id is not None}
        if len(seen) > 1:
            raise AssertionError(f"prioritized sequence crossed episodes: {row}")


def test_capacity_eviction_cleans_priorities() -> None:
    buffer = replay_buffer_v2.ReplayBufferV2(prioritized=True, capacity=2)
    buffer.add_episode(_episode("ep-a", 2))
    buffer.update_priorities([("ep-a", 0)], [5.0])
    buffer.add_episode(_episode("ep-b", 2))  # evicts ep-a transitions
    if any(key[0] == "ep-a" for key in buffer._priorities):
        raise AssertionError("evicted episode priorities were not cleaned up")


def test_beta_override_changes_is_weights() -> None:
    import numpy as np

    buffer = replay_buffer_v2.ReplayBufferV2(prioritized=True, priority_alpha=1.0)
    buffer.add_episode([_transition("hi", 0, done=True)])
    buffer.add_episode([_transition("lo", 0, done=True)])
    # Moderate ratio (4:1) + large batch so the sampled batch reliably contains
    # both priority levels, making beta's effect on IS weights observable.
    buffer.update_priorities([("hi", 0), ("lo", 0)], [4.0, 1.0])

    # Same seed -> identical sampled indices; only beta differs.
    b0 = buffer.sample_sequences(batch_size=30, seq_len=1, burn_in=0, seed=1, beta=0.0)
    b1 = buffer.sample_sequences(batch_size=30, seq_len=1, burn_in=0, seed=1, beta=1.0)
    if b0.sample_indices != b1.sample_indices:
        raise AssertionError("beta should not change which sequences are sampled")
    if {key[0] for key in b1.sample_indices} != {"hi", "lo"}:
        raise AssertionError("test setup expected a mix of both priority levels")
    if not np.allclose(b0.is_weights, 1.0):
        raise AssertionError("beta=0 should give uniform IS weights of 1")
    # beta>0 must produce non-uniform IS weights and really differ from beta=0.
    if len(np.unique(np.round(b1.is_weights, 6))) < 2:
        raise AssertionError("beta>0 did not produce non-uniform IS weights")
    if np.allclose(b0.is_weights, b1.is_weights):
        raise AssertionError("beta change did not affect IS weights")


def main() -> int:
    tests = [
        test_add_transition_increases_size,
        test_add_episode_preserves_episode_and_order,
        test_sample_sequences_batch_size_and_total_len,
        test_burn_in_train_and_padding_masks,
        test_done_mask_and_rewards_align,
        test_no_sequence_crosses_episodes,
        test_actions_and_legacy_ids_align,
        test_sampling_is_deterministic_with_seed,
        test_feature_shapes_match_encoding_v2,
        test_anti_leak_rejects_forbidden_keys,
        test_stats_and_clear,
        test_uniform_batch_has_no_is_weights,
        test_prioritized_is_weights_present_and_finite,
        test_prioritized_sampling_favors_high_priority,
        test_update_priorities_floors_and_validates,
        test_prioritized_preserves_masks_and_no_episode_crossing,
        test_capacity_eviction_cleans_priorities,
        test_beta_override_changes_is_weights,
    ]
    print("=== test_replay_buffer_v2 ===")
    for test in tests:
        test()
        print(f"  [OK] {test.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
