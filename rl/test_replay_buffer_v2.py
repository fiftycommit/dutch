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
    ]
    print("=== test_replay_buffer_v2 ===")
    for test in tests:
        test()
        print(f"  [OK] {test.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
