"""Smoke tests for the AgentInterface v2 recurrent Q-network skeleton.

Run from rl/:
    uv run python test_model_r2d2_v2.py
"""

from __future__ import annotations

from typing import Any

import torch

import encoding_v2
import model_r2d2_v2
import replay_buffer_v2
import rollout_v2


def _obs(step: int) -> dict[str, Any]:
    return {
        "type": "observation",
        "done": False,
        "micro_phase": "reaction",
        "action_mask": {"pass_tick": True, "match": [True, False]},
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
            "hand_size": 2,
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
            "available_action_types": ["pass_tick", "match", "jack_swap"],
            "masks": {
                "action_type": {"pass_tick": True, "match": True, "jack_swap": True},
                "match_slot": [True, False],
            },
            "actions": [
                {
                    "action_v2": {"action_type": "pass_tick"},
                    "legacy_action_id": 6185,
                    "legacy_kind": "pass_tick",
                },
                {
                    "action_v2": {"action_type": "match", "slot": 0},
                    "legacy_action_id": 6186,
                    "legacy_kind": "match",
                },
                {
                    "action_v2": {
                        "action_type": "jack_swap",
                        "player_a": 1,
                        "slot_a": 0,
                        "player_b": 2,
                        "slot_b": 1,
                    },
                    "legacy_action_id": 100,
                    "legacy_kind": "powerV_swap",
                },
            ],
            "legacy_action_ids": {"action_type=pass_tick": 6185},
        },
    }


def _transition(episode_id: str, step: int, *, done: bool = False) -> rollout_v2.TransitionV2:
    obs = _obs(step)
    next_obs = None if done else _obs(step + 1)
    return rollout_v2.TransitionV2(
        obs_raw=obs,
        obs_encoded_v2=encoding_v2.encode_observation_v2(obs),
        action_v2={"action_type": "pass_tick"},
        legacy_action_id=6185 + step,
        reward=float(step),
        done=done,
        next_obs_raw=next_obs,
        next_obs_encoded_v2=(
            None if next_obs is None else encoding_v2.encode_observation_v2(next_obs)
        ),
        info={},
        episode_id=episode_id,
        step_index=step,
    )


def _batch(*, batch_size: int = 2, seq_len: int = 2, burn_in: int = 1) -> replay_buffer_v2.SequenceBatchV2:
    buffer = replay_buffer_v2.ReplayBufferV2()
    buffer.add_episode([_transition("ep-a", 0), _transition("ep-a", 1), _transition("ep-a", 2, done=True)])
    buffer.add_episode([_transition("ep-b", 0), _transition("ep-b", 1, done=True)])
    return buffer.sample_sequences(
        batch_size=batch_size,
        seq_len=seq_len,
        burn_in=burn_in,
        seed=7,
    )


def _model() -> model_r2d2_v2.R2D2AgentV2:
    torch.manual_seed(0)
    return model_r2d2_v2.R2D2AgentV2(hidden_dim=32, embed_dim=16)


def test_import_torch_and_create_model() -> None:
    model = _model()
    if not isinstance(model, torch.nn.Module):
        raise AssertionError("model is not a torch module")


def test_forward_shapes() -> None:
    batch = _batch(batch_size=2, seq_len=2, burn_in=1)
    output = _model()(batch)
    if output.action_type_q.shape != (2, 3, len(encoding_v2.ACTION_TYPES)):
        raise AssertionError(f"bad action_type_q shape: {output.action_type_q.shape}")
    if output.own_slot_q.shape != (2, 3, 13):
        raise AssertionError(f"bad own_slot_q shape: {output.own_slot_q.shape}")
    if output.match_slot_q.shape != (2, 3, 13):
        raise AssertionError(f"bad match_slot_q shape: {output.match_slot_q.shape}")
    if output.target_player_q.shape != (2, 3, 6):
        raise AssertionError(f"bad target_player_q shape: {output.target_player_q.shape}")
    if output.target_slot_q.shape != (2, 3, 6, 13):
        raise AssertionError(f"bad target_slot_q shape: {output.target_slot_q.shape}")
    if output.jack_player_a_q.shape != (2, 3, 6):
        raise AssertionError(f"bad jack_player_a_q shape: {output.jack_player_a_q.shape}")
    if output.jack_slot_a_q.shape != (2, 3, 6, 13):
        raise AssertionError(f"bad jack_slot_a_q shape: {output.jack_slot_a_q.shape}")
    if output.jack_player_b_q.shape != (2, 3, 6):
        raise AssertionError(f"bad jack_player_b_q shape: {output.jack_player_b_q.shape}")
    if output.jack_slot_b_q.shape != (2, 3, 6, 13):
        raise AssertionError(f"bad jack_slot_b_q shape: {output.jack_slot_b_q.shape}")


def test_no_nan_and_hidden_state() -> None:
    batch = _batch()
    model = _model()
    hidden = model.initial_state(batch_size=2)
    output = model(batch, hidden_state=hidden)
    for tensor in [
        output.action_type_q,
        output.match_slot_q,
        output.target_slot_q,
        output.jack_slot_a_q,
    ]:
        if torch.isnan(tensor).any():
            raise AssertionError("model output contains NaN")
    if output.hidden_state.shape != (1, 2, 32):
        raise AssertionError(f"bad hidden_state shape: {output.hidden_state.shape}")


def test_masks_are_returned_and_accepted() -> None:
    batch = _batch()
    output = _model()(batch)
    if output.burn_in_mask.shape != (2, 3):
        raise AssertionError("burn_in_mask not returned")
    if output.train_mask.shape != (2, 3):
        raise AssertionError("train_mask not returned")
    if output.padding_mask.shape != (2, 3):
        raise AssertionError("padding_mask not returned")


def test_action_type_mask_applied() -> None:
    batch = _batch(batch_size=1)
    output = _model()(batch, apply_masks=True)
    draw_idx = encoding_v2.ACTION_TYPES.index("draw")
    pass_idx = encoding_v2.ACTION_TYPES.index("pass_tick")
    if output.action_type_q[0, 0, draw_idx] > model_r2d2_v2.MASK_VALUE / 2:
        raise AssertionError("illegal action type was not masked")
    if output.action_type_q[0, 0, pass_idx] <= model_r2d2_v2.MASK_VALUE / 2:
        raise AssertionError("legal action type was masked")


def test_argument_masks_applied() -> None:
    batch = _batch(batch_size=1)
    output = _model()(batch, apply_masks=True)
    if output.match_slot_q[0, 0, 1] > model_r2d2_v2.MASK_VALUE / 2:
        raise AssertionError("illegal match slot was not masked")
    if output.match_slot_q[0, 0, 0] <= model_r2d2_v2.MASK_VALUE / 2:
        raise AssertionError("legal match slot was masked")
    if output.jack_player_a_q[0, 0, 1] <= model_r2d2_v2.MASK_VALUE / 2:
        raise AssertionError("legal jack player_a was masked")
    if output.jack_slot_a_q[0, 0, 1, 0] <= model_r2d2_v2.MASK_VALUE / 2:
        raise AssertionError("legal jack slot_a was masked")
    if output.jack_slot_a_q[0, 0, 1, 1] > model_r2d2_v2.MASK_VALUE / 2:
        raise AssertionError("illegal jack slot_a was not masked")


def test_apply_masks_false_keeps_finite_values() -> None:
    batch = _batch(batch_size=1)
    output = _model()(batch, apply_masks=False)
    draw_idx = encoding_v2.ACTION_TYPES.index("draw")
    if output.action_type_q[0, 0, draw_idx] <= model_r2d2_v2.MASK_VALUE / 2:
        raise AssertionError("apply_masks=False still forced mask value")
    if not torch.isfinite(output.action_type_q).all():
        raise AssertionError("unmasked output is not finite")


def test_padding_positions_masked() -> None:
    buffer = replay_buffer_v2.ReplayBufferV2()
    buffer.add_episode([_transition("ep-short", 0, done=True)])
    batch = buffer.sample_sequences(batch_size=1, seq_len=3, burn_in=1, seed=0)
    output = _model()(batch, apply_masks=True)
    if not torch.all(output.action_type_q[0, 1:] <= model_r2d2_v2.MASK_VALUE / 2):
        raise AssertionError("padding positions were not masked")


def test_batch_to_tensors_and_no_raw_input() -> None:
    batch = _batch(batch_size=1)
    tensors = model_r2d2_v2.batch_to_tensors(batch)
    if not isinstance(tensors.public_features, torch.Tensor):
        raise AssertionError("batch_to_tensors did not create tensors")
    output = _model()(tensors)
    if hasattr(output, "obs_raw") or hasattr(output, "info"):
        raise AssertionError("model output leaked raw observation fields")


def main() -> int:
    tests = [
        test_import_torch_and_create_model,
        test_forward_shapes,
        test_no_nan_and_hidden_state,
        test_masks_are_returned_and_accepted,
        test_action_type_mask_applied,
        test_argument_masks_applied,
        test_apply_masks_false_keeps_finite_values,
        test_padding_positions_masked,
        test_batch_to_tensors_and_no_raw_input,
    ]
    print("=== test_model_r2d2_v2 ===")
    for test in tests:
        test()
        print(f"  [OK] {test.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
