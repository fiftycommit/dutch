"""Smoke tests for the AgentInterface v2 TD loss plumbing.

Run from rl/:
    uv run python test_loss_r2d2_v2.py
"""

from __future__ import annotations

import dataclasses
from typing import Any

import numpy as np
import torch

import dataset_v2
import encoding_v2
import loss_r2d2_v2
import model_r2d2_v2
import replay_buffer_v2
import rollout_v2


def _empty_batch(
    *,
    actions_v2: list[list[dict[str, Any] | None]],
    rewards: list[list[float]],
    dones: list[list[bool]],
    train_mask: list[list[bool]],
    padding_mask: list[list[bool]] | None = None,
    burn_in_mask: list[list[bool]] | None = None,
) -> replay_buffer_v2.SequenceBatchV2:
    batch_size = len(actions_v2)
    total_len = len(actions_v2[0])
    shapes = encoding_v2.shapes_v2()
    padding = padding_mask or [[False] * total_len for _ in range(batch_size)]
    burn_in = burn_in_mask or [[False] * total_len for _ in range(batch_size)]
    return replay_buffer_v2.SequenceBatchV2(
        public_features=np.zeros(
            (batch_size, total_len, *shapes["public_features"]),
            dtype=np.float32,
        ),
        private_memory_features=np.zeros(
            (batch_size, total_len, *shapes["private_memory_features"]),
            dtype=np.float32,
        ),
        event_features=np.zeros(
            (batch_size, total_len, *shapes["event_features"]),
            dtype=np.float32,
        ),
        slot_stability_features=np.zeros(
            (batch_size, total_len, *shapes["slot_stability_features"]),
            dtype=np.float32,
        ),
        action_type_mask=np.ones(
            (batch_size, total_len, *shapes["action_type_mask"]),
            dtype=bool,
        ),
        argument_masks={
            name: np.ones((batch_size, total_len, *shape), dtype=bool)
            for name, shape in shapes["argument_masks"].items()
        },
        legacy_action_mask=None,
        actions_v2=actions_v2,
        legacy_action_ids=np.zeros((batch_size, total_len), dtype=np.int64),
        rewards=np.asarray(rewards, dtype=np.float32),
        dones=np.asarray(dones, dtype=bool),
        done_mask=np.asarray(dones, dtype=bool),
        burn_in_mask=np.asarray(burn_in, dtype=bool),
        train_mask=np.asarray(train_mask, dtype=bool),
        padding_mask=np.asarray(padding, dtype=bool),
        episode_ids=[["ep"] * total_len for _ in range(batch_size)],
        step_indices=np.tile(np.arange(total_len, dtype=np.int64), (batch_size, 1)),
        metadata={"batch_size": batch_size, "total_len": total_len},
    )


def _fake_output(batch_size: int = 1, total_len: int = 2) -> model_r2d2_v2.R2D2OutputV2:
    action_q = torch.zeros(batch_size, total_len, len(encoding_v2.ACTION_TYPES))
    own_slot_q = torch.zeros(batch_size, total_len, encoding_v2.MAX_SLOTS)
    match_slot_q = torch.zeros(batch_size, total_len, encoding_v2.MAX_SLOTS)
    target_player_q = torch.zeros(batch_size, total_len, encoding_v2.MAX_PLAYERS)
    target_slot_q = torch.zeros(
        batch_size,
        total_len,
        encoding_v2.MAX_PLAYERS,
        encoding_v2.MAX_SLOTS,
    )
    jack_slot_shape = (
        batch_size,
        total_len,
        encoding_v2.MAX_PLAYERS,
        encoding_v2.MAX_SLOTS,
    )
    return model_r2d2_v2.R2D2OutputV2(
        action_type_q=action_q,
        own_slot_q=own_slot_q,
        match_slot_q=match_slot_q,
        target_player_q=target_player_q,
        target_slot_q=target_slot_q,
        jack_player_a_q=torch.zeros(batch_size, total_len, encoding_v2.MAX_PLAYERS),
        jack_slot_a_q=torch.zeros(*jack_slot_shape),
        jack_player_b_q=torch.zeros(batch_size, total_len, encoding_v2.MAX_PLAYERS),
        jack_slot_b_q=torch.zeros(*jack_slot_shape),
        legacy_q=None,
        hidden_state=torch.zeros(1, batch_size, 8),
        burn_in_mask=torch.zeros(batch_size, total_len, dtype=torch.bool),
        train_mask=torch.ones(batch_size, total_len, dtype=torch.bool),
        padding_mask=torch.zeros(batch_size, total_len, dtype=torch.bool),
    )


class FixedModel:
    def __init__(self, *, action_value: float, max_value: float = 0.0) -> None:
        self.action_value = action_value
        self.max_value = max_value

    def __call__(
        self,
        batch: replay_buffer_v2.SequenceBatchV2,
        *,
        apply_masks: bool = True,
    ) -> model_r2d2_v2.R2D2OutputV2:
        del apply_masks
        batch_size, total_len = batch.rewards.shape
        output = _fake_output(batch_size, total_len)
        pass_idx = encoding_v2.ACTION_TYPES.index("pass_tick")
        draw_idx = encoding_v2.ACTION_TYPES.index("draw")
        output.action_type_q[:, :, pass_idx] = self.action_value
        output.action_type_q[:, :, draw_idx] = self.max_value
        return output


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
            "deck_size": 30,
            "discard_size": 1,
            "top_discard_value": "7",
            "top_discard_points": 7,
            "dutch_called": False,
            "dutch_caller_is_me": False,
            "opponents": [],
        },
        "recent_events": [],
        "slot_stability": {"players": [], "recent_changes": []},
        "legal_private_memory": {"own_hand": {"slots": []}, "opponents": []},
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


def _transition(episode_id: str, step: int, *, done: bool = False) -> rollout_v2.TransitionV2:
    obs = _obs(step)
    next_obs = None if done else _obs(step + 1)
    return rollout_v2.TransitionV2(
        obs_raw=obs,
        obs_encoded_v2=encoding_v2.encode_observation_v2(obs),
        action_v2={"action_type": "pass_tick"},
        legacy_action_id=1,
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


def test_select_action_type_simple() -> None:
    output = _fake_output()
    idx = encoding_v2.ACTION_TYPES.index("pass_tick")
    output.action_type_q[0, 0, idx] = 3.5
    q = loss_r2d2_v2.select_action_q_from_output(
        output,
        [[{"action_type": "pass_tick"}, None]],
    )
    if float(q[0, 0]) != 3.5 or float(q[0, 1]) != 0.0:
        raise AssertionError(f"bad simple q selection: {q}")


def test_select_action_type_match_slot() -> None:
    output = _fake_output()
    idx = encoding_v2.ACTION_TYPES.index("match")
    output.action_type_q[0, 0, idx] = 2.0
    output.match_slot_q[0, 0, 3] = 5.0
    q = loss_r2d2_v2.select_action_q_from_output(
        output,
        [[{"action_type": "match", "slot": 3}, None]],
    )
    if float(q[0, 0]) != 7.0:
        raise AssertionError(f"bad match q selection: {q[0, 0]}")


def test_select_action_type_post_draw_replace_slot() -> None:
    output = _fake_output()
    idx = encoding_v2.ACTION_TYPES.index("post_draw_replace")
    output.action_type_q[0, 0, idx] = 1.0
    output.own_slot_q[0, 0, 4] = 6.0
    q = loss_r2d2_v2.select_action_q_from_output(
        output,
        [[{"action_type": "post_draw_replace", "slot": 4}, None]],
    )
    if float(q[0, 0]) != 7.0:
        raise AssertionError(f"bad replace q selection: {q[0, 0]}")


def test_select_action_type_jack_swap() -> None:
    output = _fake_output()
    idx = encoding_v2.ACTION_TYPES.index("jack_swap")
    output.action_type_q[0, 0, idx] = 1.0
    output.jack_player_a_q[0, 0, 1] = 2.0
    output.jack_slot_a_q[0, 0, 1, 3] = 4.0
    output.jack_player_b_q[0, 0, 2] = 8.0
    output.jack_slot_b_q[0, 0, 2, 5] = 16.0
    q = loss_r2d2_v2.select_action_q_from_output(
        output,
        [
            [
                {
                    "action_type": "jack_swap",
                    "player_a": 1,
                    "slot_a": 3,
                    "player_b": 2,
                    "slot_b": 5,
                },
                None,
            ]
        ],
    )
    if float(q[0, 0]) != 31.0:
        raise AssertionError(f"bad jack q selection: {q[0, 0]}")


def test_select_action_unknown_format_errors() -> None:
    try:
        loss_r2d2_v2.select_action_q_from_output(
            _fake_output(),
            [[{"action_type": "match"}, None]],
        )
    except ValueError as exc:
        if "missing" not in str(exc):
            raise AssertionError(f"unexpected error: {exc}") from exc
    else:
        raise AssertionError("invalid action_v2 did not raise")


def test_compute_td_loss_returns_finite_scalar() -> None:
    batch = _empty_batch(
        actions_v2=[[{"action_type": "pass_tick"}, {"action_type": "pass_tick"}]],
        rewards=[[1.0, 0.0]],
        dones=[[False, True]],
        train_mask=[[True, True]],
    )
    result = loss_r2d2_v2.compute_td_loss_v2(
        FixedModel(action_value=0.5),
        FixedModel(action_value=0.0, max_value=2.0),
        batch,
        gamma=0.5,
    )
    if result.loss.ndim != 0 or not torch.isfinite(result.loss):
        raise AssertionError(f"loss is not a finite scalar: {result.loss}")
    if result.td_error.shape != (1, 2):
        raise AssertionError(f"bad td_error shape: {result.td_error.shape}")


def test_loss_ignores_burn_in_mask() -> None:
    batch = _empty_batch(
        actions_v2=[
            [
                {"action_type": "pass_tick"},
                {"action_type": "pass_tick"},
                {"action_type": "pass_tick"},
            ]
        ],
        rewards=[[100.0, 1.0, 1.0]],
        dones=[[False, False, False]],
        burn_in_mask=[[True, False, False]],
        train_mask=[[False, True, True]],
    )
    result = loss_r2d2_v2.compute_td_loss_v2(
        FixedModel(action_value=0.0),
        FixedModel(action_value=0.0),
        batch,
    )
    if bool(result.valid_mask[0, 0]):
        raise AssertionError("burn-in step was included in valid_mask")


def test_loss_ignores_padding_mask() -> None:
    batch = _empty_batch(
        actions_v2=[[{"action_type": "pass_tick"}, None]],
        rewards=[[1.0, 99.0]],
        dones=[[False, False]],
        train_mask=[[True, True]],
        padding_mask=[[False, True]],
    )
    result = loss_r2d2_v2.compute_td_loss_v2(
        FixedModel(action_value=0.0),
        FixedModel(action_value=0.0),
        batch,
    )
    if bool(result.valid_mask[0, 1]):
        raise AssertionError("padding step was included in valid_mask")


def test_done_cuts_bootstrap() -> None:
    batch = _empty_batch(
        actions_v2=[[{"action_type": "pass_tick"}, {"action_type": "pass_tick"}]],
        rewards=[[2.0, 0.0]],
        dones=[[True, False]],
        train_mask=[[True, False]],
    )
    result = loss_r2d2_v2.compute_td_loss_v2(
        FixedModel(action_value=0.0),
        FixedModel(action_value=0.0, max_value=10.0),
        batch,
        gamma=0.5,
    )
    if float(result.td_target[0, 0]) != 2.0:
        raise AssertionError(f"done did not cut bootstrap: {result.td_target[0, 0]}")


def test_n_step_target_inside_sequence() -> None:
    batch = _empty_batch(
        actions_v2=[
            [
                {"action_type": "pass_tick"},
                {"action_type": "pass_tick"},
                {"action_type": "pass_tick"},
                {"action_type": "pass_tick"},
            ]
        ],
        rewards=[[1.0, 2.0, 4.0, 8.0]],
        dones=[[False, False, False, False]],
        train_mask=[[True, False, False, False]],
    )
    result = loss_r2d2_v2.compute_td_loss_v2(
        FixedModel(action_value=0.0),
        FixedModel(action_value=0.0, max_value=10.0),
        batch,
        gamma=0.5,
        n_step=3,
    )
    expected = 1.0 + 0.5 * 2.0 + 0.25 * 4.0 + 0.125 * 10.0
    if abs(float(result.td_target[0, 0]) - expected) > 1e-6:
        raise AssertionError(
            f"bad n-step target: {result.td_target[0, 0]} != {expected}"
        )


def test_valid_mask_and_no_nan() -> None:
    batch = _empty_batch(
        actions_v2=[[{"action_type": "pass_tick"}, {"action_type": "pass_tick"}]],
        rewards=[[1.0, 2.0]],
        dones=[[False, False]],
        train_mask=[[True, True]],
    )
    result = loss_r2d2_v2.compute_td_loss_v2(
        FixedModel(action_value=0.0),
        FixedModel(action_value=0.0),
        batch,
    )
    if result.valid_mask.shape != (1, 2) or not bool(result.valid_mask.all()):
        raise AssertionError(f"bad valid_mask: {result.valid_mask}")
    for tensor in [result.loss, result.td_error, result.q_taken, result.td_target]:
        if torch.isnan(tensor).any():
            raise AssertionError("loss output contains NaN")


def test_compatible_with_replay_buffer_batch() -> None:
    buffer = replay_buffer_v2.ReplayBufferV2()
    buffer.add_episode(
        [
            _transition("ep", 0),
            _transition("ep", 1),
            _transition("ep", 2, done=True),
        ]
    )
    batch = buffer.sample_sequences(batch_size=1, seq_len=2, burn_in=1, seed=0)
    model = model_r2d2_v2.R2D2AgentV2(hidden_dim=16, embed_dim=8)
    result = loss_r2d2_v2.compute_td_loss_v2(model, model, batch)
    if not torch.isfinite(result.loss):
        raise AssertionError("loss is not finite on ReplayBufferV2 batch")


def _two_action_legal(total_len: int) -> list[list[list[dict[str, Any]]]]:
    actions = [{"action_type": "pass_tick"}, {"action_type": "draw"}]
    return [[list(actions) for _ in range(total_len)]]


def test_double_q_selects_online_and_evaluates_target() -> None:
    # Online prefers "draw" (5 > 1); target values "draw" at 0 and "pass" at 10.
    # Single-Q bootstraps target's max over legal actions -> 10.
    # Double-Q bootstraps target at the online-greedy action ("draw") -> 0.
    batch = _empty_batch(
        actions_v2=[[{"action_type": "pass_tick"}, {"action_type": "pass_tick"}]],
        rewards=[[0.0, 0.0]],
        dones=[[False, False]],
        train_mask=[[True, False]],
    )
    batch = dataclasses.replace(batch, legal_actions_v2=_two_action_legal(2))
    online = FixedModel(action_value=1.0, max_value=5.0)
    target = FixedModel(action_value=10.0, max_value=0.0)

    single = loss_r2d2_v2.compute_td_loss_v2(
        online, target, batch, gamma=1.0, n_step=1, double_q=False
    )
    double = loss_r2d2_v2.compute_td_loss_v2(
        online, target, batch, gamma=1.0, n_step=1, double_q=True
    )
    if float(single.td_target[0, 0]) != 10.0:
        raise AssertionError(f"single-Q bootstrap wrong: {single.td_target[0, 0]}")
    if float(double.td_target[0, 0]) != 0.0:
        raise AssertionError(f"double-Q bootstrap wrong: {double.td_target[0, 0]}")


def test_factorized_bootstrap_uses_match_slot_head() -> None:
    # A single legal "match" action whose factorized target value is 2 + 5 = 7.
    legal = [[[{"action_type": "match", "slot": 3}], [{"action_type": "match", "slot": 3}]]]
    batch = _empty_batch(
        actions_v2=[[{"action_type": "match", "slot": 3}, {"action_type": "match", "slot": 3}]],
        rewards=[[0.0, 0.0]],
        dones=[[False, False]],
        train_mask=[[True, False]],
    )
    batch = dataclasses.replace(batch, legal_actions_v2=legal)

    class MatchModel:
        def __call__(self, b: Any, *, apply_masks: bool = True) -> model_r2d2_v2.R2D2OutputV2:
            del apply_masks
            out = _fake_output(1, 2)
            out.action_type_q[:, :, encoding_v2.ACTION_TYPES.index("match")] = 2.0
            out.match_slot_q[:, :, 3] = 5.0
            return out

    result = loss_r2d2_v2.compute_td_loss_v2(
        MatchModel(), MatchModel(), batch, gamma=1.0, n_step=1, double_q=False
    )
    if float(result.td_target[0, 0]) != 7.0:
        raise AssertionError(f"factorized match bootstrap wrong: {result.td_target[0, 0]}")


def test_n_step_done_cuts_bootstrap() -> None:
    batch = _empty_batch(
        actions_v2=[[{"action_type": "pass_tick"}] * 4],
        rewards=[[1.0, 1.0, 1.0, 1.0]],
        dones=[[False, False, True, False]],
        train_mask=[[True, False, False, False]],
    )
    result = loss_r2d2_v2.compute_td_loss_v2(
        FixedModel(action_value=0.0),
        FixedModel(action_value=0.0, max_value=10.0),
        batch,
        gamma=1.0,
        n_step=3,
    )
    # Reward accumulates r0+r1+r2 (=3) and the done at t=2 cuts the bootstrap.
    if float(result.td_target[0, 0]) != 3.0:
        raise AssertionError(f"n_step_done did not cut bootstrap: {result.td_target[0, 0]}")


def test_is_weights_scale_loss() -> None:
    batch = _empty_batch(
        actions_v2=[[{"action_type": "pass_tick"}, {"action_type": "pass_tick"}]],
        rewards=[[1.0, 0.0]],
        dones=[[False, True]],
        train_mask=[[True, True]],
    )
    unweighted = loss_r2d2_v2.compute_td_loss_v2(
        FixedModel(action_value=0.5), FixedModel(action_value=0.0, max_value=2.0), batch, gamma=0.5
    )
    weighted = loss_r2d2_v2.compute_td_loss_v2(
        FixedModel(action_value=0.5),
        FixedModel(action_value=0.0, max_value=2.0),
        batch,
        gamma=0.5,
        is_weights=np.asarray([0.25], dtype=np.float32),
    )
    expected = 0.25 * float(unweighted.loss)
    if abs(float(weighted.loss) - expected) > 1e-6:
        raise AssertionError(
            f"is_weights did not scale the loss: {weighted.loss} != {expected}"
        )
    if weighted.elementwise.shape != (1, 2):
        raise AssertionError("elementwise loss tensor missing or wrong shape")


def test_n_step_target_matches_dataset_helper() -> None:
    # With a zero-valued bootstrap, the loss n-step target must equal the
    # offline dataset n-step return (single source of truth cross-check).
    transitions = [_transition("ep", step) for step in range(4)]
    n_steps = dataset_v2.compute_n_step_returns(transitions, n_step=3, gamma=0.5)
    rewards = [[float(step) for step in range(4)]]
    batch = _empty_batch(
        actions_v2=[[{"action_type": "pass_tick"}] * 4],
        rewards=rewards,
        dones=[[False, False, False, False]],
        train_mask=[[True, False, False, False]],
    )
    result = loss_r2d2_v2.compute_td_loss_v2(
        FixedModel(action_value=0.0),
        FixedModel(action_value=0.0, max_value=0.0),
        batch,
        gamma=0.5,
        n_step=3,
    )
    if abs(float(result.td_target[0, 0]) - n_steps[0].n_step_return) > 1e-6:
        raise AssertionError(
            f"loss n-step {result.td_target[0, 0]} != dataset {n_steps[0].n_step_return}"
        )


def test_loss_output_does_not_expose_raw_observation() -> None:
    batch = _empty_batch(
        actions_v2=[[{"action_type": "pass_tick"}]],
        rewards=[[1.0]],
        dones=[[True]],
        train_mask=[[True]],
    )
    result = loss_r2d2_v2.compute_td_loss_v2(
        FixedModel(action_value=0.0),
        FixedModel(action_value=0.0),
        batch,
    )
    if hasattr(result, "obs_raw") or hasattr(result, "info"):
        raise AssertionError("loss output leaked raw policy/debug fields")


def main() -> int:
    tests = [
        test_select_action_type_simple,
        test_select_action_type_match_slot,
        test_select_action_type_post_draw_replace_slot,
        test_select_action_type_jack_swap,
        test_select_action_unknown_format_errors,
        test_compute_td_loss_returns_finite_scalar,
        test_loss_ignores_burn_in_mask,
        test_loss_ignores_padding_mask,
        test_done_cuts_bootstrap,
        test_n_step_target_inside_sequence,
        test_valid_mask_and_no_nan,
        test_compatible_with_replay_buffer_batch,
        test_double_q_selects_online_and_evaluates_target,
        test_factorized_bootstrap_uses_match_slot_head,
        test_n_step_done_cuts_bootstrap,
        test_is_weights_scale_loss,
        test_n_step_target_matches_dataset_helper,
        test_loss_output_does_not_expose_raw_observation,
    ]
    print("=== test_loss_r2d2_v2 ===")
    for test in tests:
        test()
        print(f"  [OK] {test.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
