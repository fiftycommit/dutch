"""Smoke tests for the structured AgentInterface v2 encoder.

Run from rl/:
    uv run python test_encoding_v2.py
"""

from __future__ import annotations

import numpy as np

import encoding_v2


def _sample_observation() -> dict:
    return {
        "type": "observation",
        "done": False,
        "micro_phase": "reaction",
        "action_mask": {
            "pass_tick": True,
            "match": [True, False, True],
        },
        "obs": {
            "phase": "reaction",
            "micro_phase": "reaction",
            "turn_count": 3,
            "action_count": 17,
            "num_players": 3,
            "deck_size": 31,
            "discard_size": 12,
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
                "step": 4,
                "turn_count": 3,
                "action_count": 16,
                "phase": "reaction",
                "event_type": "discard_visible",
                "actor": "p1",
                "card_visible": True,
                "card_value": "7",
                "card_match_value": "7",
                "card_points": 7,
                "slot": 2,
                "discard_reason": "match_discard",
                "replaced_slot": None,
            },
            {
                "step": 5,
                "turn_count": 3,
                "action_count": 17,
                "phase": "reaction",
                "event_type": "match_failure_penalty",
                "actor": "p2",
                "slot": 0,
                "penalty_card_count": 1,
            },
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
                            "actions_since_changed": 6,
                            "changed_this_turn": False,
                            "last_changed_reason": "initial",
                        },
                        {
                            "slot": 1,
                            "turns_since_changed": 0,
                            "actions_since_changed": 0,
                            "changed_this_turn": True,
                            "last_changed_reason": "exchange",
                        },
                    ],
                },
                {
                    "seat": 1,
                    "player_id": "p1",
                    "slots": [
                        {
                            "slot": 0,
                            "turns_since_changed": 2,
                            "actions_since_changed": 10,
                            "changed_this_turn": False,
                            "last_changed_reason": "jack_swap",
                        }
                    ],
                },
            ],
            "recent_changes": [
                {
                    "turn_count": 3,
                    "action_count": 16,
                    "player_id": "p1",
                    "seat": 1,
                    "slot": 2,
                    "reason": "match_removed",
                }
            ],
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
                        "age_actions": 5,
                        "age_turns": 1,
                        "source": "mental_map",
                    },
                    {
                        "slot": 1,
                        "known": False,
                        "believed_value": None,
                        "believed_match_value": None,
                        "believed_points": None,
                        "valid": False,
                        "confidence": 0.0,
                        "age_actions": None,
                        "age_turns": None,
                        "source": None,
                    },
                ]
            },
            "opponents": [
                {
                    "seat": 1,
                    "player_id": "p1",
                    "spied_slots": [
                        {
                            "slot": 3,
                            "known": True,
                            "believed_value": "D",
                            "believed_match_value": "D",
                            "believed_points": 12,
                            "valid": True,
                            "confidence": 1.0,
                            "age_actions": 8,
                            "age_turns": 2,
                            "source": "spy_memory",
                        }
                    ],
                }
            ],
        },
        "legal_action_v2": {
            "available_action_types": ["match", "pass_tick"],
            "masks": {
                "action_type": {"match": True, "pass_tick": True},
                "match_slot": [True, False, True],
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
                    "action_v2": {"action_type": "match", "slot": 2},
                    "legacy_action_id": 6188,
                    "legacy_kind": "match",
                },
            ],
            "legacy_action_ids": {
                "action_type=pass_tick": 6185,
                "action_type=match|slot=0": 6186,
                "action_type=match|slot=2": 6188,
            },
        },
    }


def _assert_shape(name: str, got: tuple[int, ...], expected: tuple[int, ...]) -> None:
    if got != expected:
        raise AssertionError(f"{name}: shape {got} != {expected}")


def test_minimal_observation() -> None:
    encoded = encoding_v2.encode_observation_v2({"obs": {}, "done": False})
    shapes = encoding_v2.shapes_v2()
    _assert_shape("public", encoded.public_features.shape, shapes["public_features"])
    _assert_shape(
        "private",
        encoded.private_memory_features.shape,
        shapes["private_memory_features"],
    )
    _assert_shape("events", encoded.event_features.shape, shapes["event_features"])
    _assert_shape(
        "slot_stability",
        encoded.slot_stability_features.shape,
        shapes["slot_stability_features"],
    )
    _assert_shape("action_type", encoded.action_type_mask.shape, shapes["action_type_mask"])


def test_complete_observation_shapes_and_masks() -> None:
    encoded = encoding_v2.encode_observation_v2(_sample_observation())
    shapes = encoding_v2.shapes_v2()
    _assert_shape("public", encoded.public_features.shape, shapes["public_features"])
    _assert_shape("events", encoded.event_features.shape, shapes["event_features"])
    _assert_shape(
        "slot_stability",
        encoded.slot_stability_features.shape,
        shapes["slot_stability_features"],
    )

    match_idx = encoding_v2.ACTION_TYPES.index("match")
    pass_idx = encoding_v2.ACTION_TYPES.index("pass_tick")
    if not encoded.action_type_mask[match_idx] or not encoded.action_type_mask[pass_idx]:
        raise AssertionError("action_type mask does not expose match/pass_tick")
    if not encoded.argument_masks["match_slot"][0]:
        raise AssertionError("match slot 0 should be legal")
    if encoded.argument_masks["match_slot"][1]:
        raise AssertionError("match slot 1 should be illegal")
    if encoded.legacy_action_mask is None:
        raise AssertionError("legacy action mask should be available")


def test_sequence_encoding() -> None:
    obs = _sample_observation()
    seq = encoding_v2.encode_sequence_v2([obs, obs])
    if seq["public_features"].shape[0] != 2:
        raise AssertionError("sequence public_features time dimension != 2")
    if seq["event_features"].shape[:2] != (
        2,
        encoding_v2.MAX_EVENTS,
    ):
        raise AssertionError("sequence event_features shape is invalid")
    if seq["argument_masks"]["match_slot"].shape != (2, encoding_v2.MAX_SLOTS):
        raise AssertionError("sequence match_slot mask shape is invalid")


def test_forbidden_keys_are_ignored() -> None:
    obs = _sample_observation()
    obs["true_scores"] = {"p1": 99}
    obs["full_hands"] = {"p1": ["A", "2"]}
    obs["hidden_deck"] = ["R"]
    obs["obs"]["opponent_hand"] = ["JOKER"]
    encoded = encoding_v2.encode_observation_v2(obs)
    if "true_scores" not in encoded.metadata["ignored_forbidden_keys"]:
        raise AssertionError("forbidden key tracking missed true_scores")
    arrays = [
        encoded.public_features,
        encoded.private_memory_features,
        encoded.event_features,
        encoded.slot_stability_features,
        encoded.action_type_mask.astype(np.float32),
    ]
    for arr in arrays:
        if not np.isfinite(arr).all():
            raise AssertionError("encoded array contains non-finite values")


def test_jack_factor_masks() -> None:
    obs = _sample_observation()
    obs["micro_phase"] = "power"
    obs["legal_action_v2"] = {
        "available_action_types": ["jack_swap"],
        "masks": {"action_type": {"jack_swap": True}},
        "actions": [
            {
                "action_v2": {
                    "action_type": "jack_swap",
                    "player_a": 1,
                    "slot_a": 0,
                    "player_b": 2,
                    "slot_b": 3,
                },
                "legacy_action_id": 100,
                "legacy_kind": "powerV_swap",
            }
        ],
        "legacy_action_ids": {},
    }
    encoded = encoding_v2.encode_observation_v2(obs)
    if not encoded.argument_masks["player_a"][1]:
        raise AssertionError("player_a mask missing p1")
    if not encoded.argument_masks["slot_a"][1, 0]:
        raise AssertionError("slot_a mask missing p1 slot 0")
    if not encoded.argument_masks["player_b"][2]:
        raise AssertionError("player_b mask missing p2")
    if not encoded.argument_masks["slot_b"][2, 3]:
        raise AssertionError("slot_b mask missing p2 slot 3")


def main() -> int:
    tests = [
        test_minimal_observation,
        test_complete_observation_shapes_and_masks,
        test_sequence_encoding,
        test_forbidden_keys_are_ignored,
        test_jack_factor_masks,
    ]
    print("=== test_encoding_v2 ===")
    for test in tests:
        test()
        print(f"  [OK] {test.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
