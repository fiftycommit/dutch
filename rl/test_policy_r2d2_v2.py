"""Smoke tests for AgentInterface v2 action selection.

Run from rl/:
    uv run python test_policy_r2d2_v2.py
"""

from __future__ import annotations

from typing import Any
import random

import torch

import encoding_v2
import model_r2d2_v2
import policy_r2d2_v2
import replay_buffer_v2
import rollout_v2


def _fake_output(batch_size: int = 1, total_len: int = 1) -> model_r2d2_v2.R2D2OutputV2:
    action_q = torch.zeros(batch_size, total_len, len(encoding_v2.ACTION_TYPES))
    target_slot_shape = (
        batch_size,
        total_len,
        encoding_v2.MAX_PLAYERS,
        encoding_v2.MAX_SLOTS,
    )
    return model_r2d2_v2.R2D2OutputV2(
        action_type_q=action_q,
        own_slot_q=torch.zeros(batch_size, total_len, encoding_v2.MAX_SLOTS),
        match_slot_q=torch.zeros(batch_size, total_len, encoding_v2.MAX_SLOTS),
        target_player_q=torch.zeros(batch_size, total_len, encoding_v2.MAX_PLAYERS),
        target_slot_q=torch.zeros(*target_slot_shape),
        jack_player_a_q=torch.zeros(batch_size, total_len, encoding_v2.MAX_PLAYERS),
        jack_slot_a_q=torch.zeros(*target_slot_shape),
        jack_player_b_q=torch.zeros(batch_size, total_len, encoding_v2.MAX_PLAYERS),
        jack_slot_b_q=torch.zeros(*target_slot_shape),
        legacy_q=None,
        hidden_state=torch.zeros(1, batch_size, 8),
        burn_in_mask=torch.zeros(batch_size, total_len, dtype=torch.bool),
        train_mask=torch.ones(batch_size, total_len, dtype=torch.bool),
        padding_mask=torch.zeros(batch_size, total_len, dtype=torch.bool),
    )


def _entry(action: dict[str, Any], legacy_id: int) -> dict[str, Any]:
    return {
        "action_v2": action,
        "legacy_action_id": legacy_id,
        "legacy_kind": action["action_type"],
    }


def _legal(*entries: dict[str, Any]) -> dict[str, Any]:
    return {"actions": list(entries)}


def _set_action_type(output: model_r2d2_v2.R2D2OutputV2, action_type: str, value: float) -> None:
    output.action_type_q[0, 0, encoding_v2.ACTION_TYPES.index(action_type)] = value


def test_greedy_chooses_best_legal_score() -> None:
    output = _fake_output()
    _set_action_type(output, "draw", 1.0)
    _set_action_type(output, "call_dutch", 3.0)
    selected = policy_r2d2_v2.select_greedy_action_v2(
        output,
        _legal(
            _entry({"action_type": "draw"}, 10),
            _entry({"action_type": "call_dutch"}, 11),
        ),
    )
    if selected.action_v2 != {"action_type": "call_dutch"}:
        raise AssertionError(f"wrong greedy action: {selected}")
    if selected.legacy_action_id != 11 or selected.is_random:
        raise AssertionError(f"bad selected metadata: {selected}")


def test_never_selects_action_absent_from_legal_list() -> None:
    output = _fake_output()
    _set_action_type(output, "call_dutch", 99.0)
    _set_action_type(output, "draw", 1.0)
    selected = policy_r2d2_v2.select_greedy_action_v2(
        output,
        _legal(_entry({"action_type": "draw"}, 10)),
    )
    if selected.action_v2 != {"action_type": "draw"}:
        raise AssertionError("policy selected an action outside legal_action_v2.actions")


def test_epsilon_one_is_random_legal_and_seeded() -> None:
    output = _fake_output()
    legal = _legal(
        _entry({"action_type": "draw"}, 10),
        _entry({"action_type": "call_dutch"}, 11),
        _entry({"action_type": "pass_tick"}, 12),
    )
    first = policy_r2d2_v2.select_epsilon_greedy_action_v2(
        output,
        legal,
        epsilon=1.0,
        rng=random.Random(4),
    )
    second = policy_r2d2_v2.select_epsilon_greedy_action_v2(
        output,
        legal,
        epsilon=1.0,
        rng=random.Random(4),
    )
    legal_actions = [entry["action_v2"] for entry in legal["actions"]]
    if first.action_v2 != second.action_v2:
        raise AssertionError("seeded epsilon random was not deterministic")
    if first.action_v2 not in legal_actions or not first.is_random:
        raise AssertionError(f"random action was not legal/random: {first}")


def test_invalid_epsilon_errors() -> None:
    try:
        policy_r2d2_v2.select_epsilon_greedy_action_v2(
            _fake_output(),
            _legal(_entry({"action_type": "draw"}, 1)),
            epsilon=1.5,
        )
    except ValueError as exc:
        if "epsilon" not in str(exc):
            raise AssertionError(f"unexpected error: {exc}") from exc
    else:
        raise AssertionError("invalid epsilon did not raise")


def test_simple_actions_use_action_type_q() -> None:
    output = _fake_output()
    for action_type in ["draw", "call_dutch", "pass_tick", "skip_power"]:
        _set_action_type(output, action_type, 2.5)
        score = policy_r2d2_v2.score_legal_action_v2(
            output,
            {"action_type": action_type},
        )
        if score != 2.5:
            raise AssertionError(f"{action_type} did not use action_type_q")


def test_match_uses_match_slot_q() -> None:
    output = _fake_output()
    _set_action_type(output, "match", 1.0)
    output.match_slot_q[0, 0, 3] = 4.0
    score = policy_r2d2_v2.score_legal_action_v2(
        output,
        {"action_type": "match", "slot": 3},
    )
    if score != 5.0:
        raise AssertionError(f"bad match score: {score}")


def test_post_draw_replace_uses_own_slot_q() -> None:
    output = _fake_output()
    _set_action_type(output, "post_draw_replace", 1.0)
    output.own_slot_q[0, 0, 2] = 6.0
    score = policy_r2d2_v2.score_legal_action_v2(
        output,
        {"action_type": "post_draw_replace", "slot": 2},
    )
    if score != 7.0:
        raise AssertionError(f"bad replace score: {score}")


def test_power_7_uses_own_slot_q() -> None:
    output = _fake_output()
    _set_action_type(output, "power_7_look", 1.0)
    output.own_slot_q[0, 0, 4] = 5.0
    score = policy_r2d2_v2.score_legal_action_v2(
        output,
        {"action_type": "power_7_look", "slot": 4},
    )
    if score != 6.0:
        raise AssertionError(f"bad power 7 score: {score}")


def test_power_10_uses_target_heads() -> None:
    output = _fake_output()
    _set_action_type(output, "power_10_spy", 1.0)
    output.target_player_q[0, 0, 2] = 3.0
    output.target_slot_q[0, 0, 2, 5] = 9.0
    score = policy_r2d2_v2.score_legal_action_v2(
        output,
        {"action_type": "power_10_spy", "target_player": 2, "target_slot": 5},
    )
    if score != 13.0:
        raise AssertionError(f"bad power 10 score: {score}")


def test_joker_uses_target_player_q() -> None:
    output = _fake_output()
    _set_action_type(output, "joker", 1.0)
    output.target_player_q[0, 0, 3] = 8.0
    score = policy_r2d2_v2.score_legal_action_v2(
        output,
        {"action_type": "joker", "target_player": 3},
    )
    if score != 9.0:
        raise AssertionError(f"bad joker score: {score}")


def test_jack_swap_uses_jack_heads() -> None:
    output = _fake_output()
    _set_action_type(output, "jack_swap", 1.0)
    output.jack_player_a_q[0, 0, 1] = 2.0
    output.jack_slot_a_q[0, 0, 1, 3] = 4.0
    output.jack_player_b_q[0, 0, 2] = 8.0
    output.jack_slot_b_q[0, 0, 2, 5] = 16.0
    score = policy_r2d2_v2.score_legal_action_v2(
        output,
        {
            "action_type": "jack_swap",
            "player_a": 1,
            "slot_a": 3,
            "player_b": 2,
            "slot_b": 5,
        },
    )
    if score != 31.0:
        raise AssertionError(f"bad jack score: {score}")


def test_unknown_or_incomplete_action_errors() -> None:
    for action in [{"action_type": "unknown"}, {"action_type": "match"}]:
        try:
            policy_r2d2_v2.score_legal_action_v2(_fake_output(), action)
        except ValueError:
            pass
        else:
            raise AssertionError(f"bad action did not raise: {action}")


def test_legacy_action_id_is_preserved() -> None:
    output = _fake_output()
    _set_action_type(output, "draw", 1.0)
    selected = policy_r2d2_v2.select_greedy_action_v2(
        output,
        _legal(_entry({"action_type": "draw"}, 42)),
    )
    if selected.legacy_action_id != 42:
        raise AssertionError(f"legacy_action_id was not preserved: {selected}")


def test_action_message_uses_action_v2_only() -> None:
    selected = policy_r2d2_v2.SelectedActionV2(
        action_v2={"action_type": "draw"},
        legacy_action_id=1,
        score=0.0,
        is_random=False,
        metadata={},
    )
    msg = policy_r2d2_v2.action_message_for_runner_v2(selected)
    if msg != {"action_v2": {"action_type": "draw"}}:
        raise AssertionError(f"bad runner message: {msg}")


def _obs(step: int) -> dict[str, Any]:
    return {
        "type": "observation",
        "done": False,
        "micro_phase": "reaction",
        "action_mask": {"pass_tick": True, "match": [True]},
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
            "available_action_types": ["pass_tick", "match"],
            "masks": {
                "action_type": {"pass_tick": True, "match": True},
                "match_slot": [True],
            },
            "actions": [
                {
                    "action_v2": {"action_type": "pass_tick"},
                    "legacy_action_id": 1,
                },
                {
                    "action_v2": {"action_type": "match", "slot": 0},
                    "legacy_action_id": 2,
                },
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
        reward=0.0,
        done=done,
        next_obs_raw=next_obs,
        next_obs_encoded_v2=(
            None if next_obs is None else encoding_v2.encode_observation_v2(next_obs)
        ),
        info={},
        episode_id=episode_id,
        step_index=step,
    )


def test_compatible_with_real_model_output() -> None:
    buffer = replay_buffer_v2.ReplayBufferV2()
    buffer.add_episode([_transition("ep", 0), _transition("ep", 1, done=True)])
    batch = buffer.sample_sequences(batch_size=1, seq_len=1, burn_in=1, seed=0)
    model = model_r2d2_v2.R2D2AgentV2(hidden_dim=16, embed_dim=8)
    output = model(batch)
    legal = _obs(0)["legal_action_v2"]
    selected = policy_r2d2_v2.select_action_from_batch_output(
        output,
        batch_index=0,
        time_index=0,
        legal_action_v2=legal,
        epsilon=0.0,
    )
    legal_actions = [entry["action_v2"] for entry in legal["actions"]]
    if selected.action_v2 not in legal_actions:
        raise AssertionError("real model selection returned action outside legal list")


def test_policy_output_does_not_expose_raw_observation() -> None:
    selected = policy_r2d2_v2.select_greedy_action_v2(
        _fake_output(),
        _legal(_entry({"action_type": "draw"}, 1)),
    )
    if hasattr(selected, "obs_raw") or hasattr(selected, "info"):
        raise AssertionError("policy selection leaked raw observation fields")


def main() -> int:
    tests = [
        test_greedy_chooses_best_legal_score,
        test_never_selects_action_absent_from_legal_list,
        test_epsilon_one_is_random_legal_and_seeded,
        test_invalid_epsilon_errors,
        test_simple_actions_use_action_type_q,
        test_match_uses_match_slot_q,
        test_post_draw_replace_uses_own_slot_q,
        test_power_7_uses_own_slot_q,
        test_power_10_uses_target_heads,
        test_joker_uses_target_player_q,
        test_jack_swap_uses_jack_heads,
        test_unknown_or_incomplete_action_errors,
        test_legacy_action_id_is_preserved,
        test_action_message_uses_action_v2_only,
        test_compatible_with_real_model_output,
        test_policy_output_does_not_expose_raw_observation,
    ]
    print("=== test_policy_r2d2_v2 ===")
    for test in tests:
        test()
        print(f"  [OK] {test.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
