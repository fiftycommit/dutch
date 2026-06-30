"""Structured AgentInterface v2 encoder for future recurrent agents.

This module is intentionally separate from ``encoding.py``. The legacy encoder
keeps PPO compatibility with ``OBS_DIM=147`` and ``N_ACTIONS=6199``; this file
encodes the raw JSON blocks exposed by the Dart runner for sequence-based
agents such as DRQN/R2D2.

The encoder consumes legal observations only. Debug labels, true hands, true
scores and deck order are ignored by construction.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np

MAX_PLAYERS = 6
MAX_OPPONENTS = MAX_PLAYERS - 1
MAX_SLOTS = 13
MAX_EVENTS = 32

RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "V", "D", "R", "JOKER"]
PHASES = ["setup", "playing", "reaction", "specialPower", "dutchCalled", "ended"]
MICRO_PHASES = ["dutchOrDraw", "postDraw", "power", "reaction"]
EVENT_TYPES = [
    "draw_hidden",
    "discard_visible",
    "exchange_discard",
    "match_success",
    "match_failure_penalty",
    "power_7_look",
    "power_10_spy",
    "valet_swap",
    "joker_shuffle",
    "dutch_call",
    "round_end",
]
DISCARD_REASONS = ["drawn_discard", "exchange_discard", "match_discard"]
SLOT_CHANGE_REASONS = [
    "initial",
    "exchange",
    "match_removed",
    "penalty",
    "jack_swap",
    "joker_shuffle",
]
ACTION_TYPES = [
    "call_dutch",
    "draw",
    "post_draw_discard",
    "post_draw_replace",
    "skip_power",
    "power_7_look",
    "power_10_spy",
    "joker",
    "jack_swap",
    "pass_tick",
    "match",
]

PUBLIC_FEATURE_DIM = (
    len(PHASES)
    + len(MICRO_PHASES)
    + 5
    + 1
    + len(RANKS)
    + 1
    + 2
    + MAX_PLAYERS
)
PRIVATE_SLOT_FEATURE_DIM = 2 + len(RANKS) + 4
PRIVATE_MEMORY_DIM = (
    MAX_SLOTS * PRIVATE_SLOT_FEATURE_DIM
    + MAX_OPPONENTS * MAX_SLOTS * PRIVATE_SLOT_FEATURE_DIM
)
SLOT_STABILITY_FEATURE_DIM = 4 + len(SLOT_CHANGE_REASONS)
SLOT_STABILITY_DIM = MAX_PLAYERS * MAX_SLOTS * SLOT_STABILITY_FEATURE_DIM
EVENT_FEATURE_DIM = (
    len(EVENT_TYPES)
    + MAX_PLAYERS
    + MAX_PLAYERS
    + 1
    + len(RANKS)
    + 1
    + 1
    + len(DISCARD_REASONS)
    + 4
)

FORBIDDEN_POLICY_KEYS = {
    "true_score",
    "true_scores",
    "full_hand",
    "full_hands",
    "opponent_hand",
    "deck_order",
    "hidden_deck",
    "kept_card",
    "penalty_card",
    "swapped_card",
    "debug_eval_labels",
}


@dataclass(frozen=True)
class EncodedObservationV2:
    public_features: np.ndarray
    private_memory_features: np.ndarray
    event_features: np.ndarray
    slot_stability_features: np.ndarray
    action_type_mask: np.ndarray
    argument_masks: dict[str, np.ndarray]
    legacy_action_mask: np.ndarray | None
    metadata: dict[str, Any]


def encode_observation_v2(msg: dict[str, Any]) -> EncodedObservationV2:
    """Encode one raw runner observation into structured numpy arrays."""

    legacy_mask = _legacy_mask_or_none(msg)
    legal_action = msg.get("legal_action_v2") or {}

    metadata = {
        "done": bool(msg.get("done", False)),
        "micro_phase": msg.get("micro_phase"),
        "legacy_action_ids": dict(legal_action.get("legacy_action_ids") or {}),
        "shapes": shapes_v2(),
        "ignored_forbidden_keys": sorted(_find_forbidden_keys(msg)),
    }

    return EncodedObservationV2(
        public_features=_encode_public_features(msg),
        private_memory_features=_encode_private_memory(msg),
        event_features=_encode_recent_events(msg),
        slot_stability_features=_encode_slot_stability(msg),
        action_type_mask=_encode_action_type_mask(legal_action),
        argument_masks=_encode_argument_masks(legal_action),
        legacy_action_mask=legacy_mask,
        metadata=metadata,
    )


def encode_sequence_v2(observations: list[dict[str, Any]]) -> dict[str, Any]:
    """Encode an ordered observation sequence for recurrent agents.

    The returned arrays have time as the first dimension. Argument masks remain
    grouped by argument name.
    """

    encoded = [encode_observation_v2(obs) for obs in observations]
    if not encoded:
        return {
            "public_features": np.zeros((0, PUBLIC_FEATURE_DIM), dtype=np.float32),
            "private_memory_features": np.zeros((0, PRIVATE_MEMORY_DIM), dtype=np.float32),
            "event_features": np.zeros((0, MAX_EVENTS, EVENT_FEATURE_DIM), dtype=np.float32),
            "slot_stability_features": np.zeros((0, SLOT_STABILITY_DIM), dtype=np.float32),
            "action_type_mask": np.zeros((0, len(ACTION_TYPES)), dtype=bool),
            "argument_masks": {},
            "legacy_action_mask": None,
            "metadata": {"length": 0},
        }

    argument_names = sorted(
        {name for item in encoded for name in item.argument_masks.keys()}
    )
    argument_masks = {
        name: np.stack([item.argument_masks[name] for item in encoded])
        for name in argument_names
    }

    legacy_masks = [item.legacy_action_mask for item in encoded]
    legacy_action_mask = (
        None
        if any(mask is None for mask in legacy_masks)
        else np.stack([mask for mask in legacy_masks if mask is not None])
    )

    return {
        "public_features": np.stack([item.public_features for item in encoded]),
        "private_memory_features": np.stack(
            [item.private_memory_features for item in encoded]
        ),
        "event_features": np.stack([item.event_features for item in encoded]),
        "slot_stability_features": np.stack(
            [item.slot_stability_features for item in encoded]
        ),
        "action_type_mask": np.stack([item.action_type_mask for item in encoded]),
        "argument_masks": argument_masks,
        "legacy_action_mask": legacy_action_mask,
        "metadata": {"length": len(encoded), "item_shapes": shapes_v2()},
    }


def shapes_v2() -> dict[str, Any]:
    return {
        "public_features": (PUBLIC_FEATURE_DIM,),
        "private_memory_features": (PRIVATE_MEMORY_DIM,),
        "event_features": (MAX_EVENTS, EVENT_FEATURE_DIM),
        "slot_stability_features": (SLOT_STABILITY_DIM,),
        "action_type_mask": (len(ACTION_TYPES),),
        "argument_masks": {
            "own_slot": (MAX_SLOTS,),
            "match_slot": (MAX_SLOTS,),
            "target_player": (MAX_PLAYERS,),
            "target_slot": (MAX_PLAYERS, MAX_SLOTS),
            "player_a": (MAX_PLAYERS,),
            "slot_a": (MAX_PLAYERS, MAX_SLOTS),
            "player_b": (MAX_PLAYERS,),
            "slot_b": (MAX_PLAYERS, MAX_SLOTS),
        },
    }


def _encode_public_features(msg: dict[str, Any]) -> np.ndarray:
    obs = msg.get("obs") or {}
    top_value = obs.get("top_discard_value")
    values: list[float] = []
    values.extend(_one_hot(PHASES, obs.get("phase") or msg.get("phase")))
    values.extend(_one_hot(MICRO_PHASES, msg.get("micro_phase") or obs.get("micro_phase")))
    values.extend(
        [
            _norm(obs.get("turn_count"), 100.0),
            _norm(obs.get("action_count"), 500.0),
            _norm(obs.get("deck_size"), 54.0),
            _norm(obs.get("discard_size"), 54.0),
            _norm(obs.get("num_players"), float(MAX_PLAYERS)),
            1.0 if top_value is not None else 0.0,
        ]
    )
    values.extend(_one_hot(RANKS, top_value))
    values.append(_norm(obs.get("top_discard_points"), 13.0))
    values.append(1.0 if obs.get("dutch_called") else 0.0)
    values.append(1.0 if obs.get("dutch_caller_is_me") else 0.0)

    hand_sizes = [0.0] * MAX_PLAYERS
    hand_sizes[0] = _norm(obs.get("hand_size"), float(MAX_SLOTS))
    for i, opponent in enumerate(obs.get("opponents") or []):
        if i + 1 >= MAX_PLAYERS:
            break
        hand_sizes[i + 1] = _norm(opponent.get("hand_size"), float(MAX_SLOTS))
    values.extend(hand_sizes)

    return np.asarray(values, dtype=np.float32)


def _encode_private_memory(msg: dict[str, Any]) -> np.ndarray:
    memory = msg.get("legal_private_memory") or {}
    values: list[float] = []

    own_slots = ((memory.get("own_hand") or {}).get("slots") or [])[:MAX_SLOTS]
    by_slot = {int(slot.get("slot", -1)): slot for slot in own_slots}
    for slot_idx in range(MAX_SLOTS):
        values.extend(_encode_memory_slot(by_slot.get(slot_idx)))

    opponents = memory.get("opponents") or []
    by_player = {
        _player_index(opponent.get("player_id"), opponent.get("seat")): opponent
        for opponent in opponents
    }
    for player_idx in range(1, MAX_PLAYERS):
        opponent = by_player.get(player_idx) or {}
        spied = {
            int(slot.get("slot", -1)): slot
            for slot in (opponent.get("spied_slots") or [])
        }
        for slot_idx in range(MAX_SLOTS):
            values.extend(_encode_memory_slot(spied.get(slot_idx)))

    return np.asarray(values, dtype=np.float32)


def _encode_memory_slot(slot: dict[str, Any] | None) -> list[float]:
    if not slot:
        return [0.0] * PRIVATE_SLOT_FEATURE_DIM
    known = bool(slot.get("known") and slot.get("valid", True))
    return [
        1.0,
        1.0 if known else 0.0,
        *_one_hot(RANKS, slot.get("believed_match_value") or slot.get("believed_value")),
        _norm(slot.get("believed_points"), 13.0) if known else 0.0,
        _float(slot.get("confidence")) if known else 0.0,
        _norm(slot.get("age_actions"), 200.0) if known else 0.0,
        _norm(slot.get("age_turns"), 50.0) if known else 0.0,
    ]


def _encode_slot_stability(msg: dict[str, Any]) -> np.ndarray:
    stability = msg.get("slot_stability") or {}
    players = stability.get("players") or []
    by_player = {
        _player_index(player.get("player_id"), player.get("seat")): player
        for player in players
    }

    values: list[float] = []
    for player_idx in range(MAX_PLAYERS):
        player = by_player.get(player_idx) or {}
        slots = {int(slot.get("slot", -1)): slot for slot in (player.get("slots") or [])}
        for slot_idx in range(MAX_SLOTS):
            slot = slots.get(slot_idx)
            if not slot:
                values.extend([0.0] * SLOT_STABILITY_FEATURE_DIM)
                continue
            values.extend(
                [
                    1.0,
                    _norm(slot.get("turns_since_changed"), 50.0),
                    _norm(slot.get("actions_since_changed"), 200.0),
                    1.0 if slot.get("changed_this_turn") else 0.0,
                    *_one_hot(SLOT_CHANGE_REASONS, slot.get("last_changed_reason")),
                ]
            )
    return np.asarray(values, dtype=np.float32)


def _encode_recent_events(msg: dict[str, Any]) -> np.ndarray:
    events = list(msg.get("recent_events") or [])[-MAX_EVENTS:]
    rows = np.zeros((MAX_EVENTS, EVENT_FEATURE_DIM), dtype=np.float32)
    base_action = _float((msg.get("obs") or {}).get("action_count"))
    base_turn = _float((msg.get("obs") or {}).get("turn_count"))

    for row_idx, event in enumerate(events):
        values: list[float] = []
        values.extend(_one_hot(EVENT_TYPES, event.get("event_type")))
        values.extend(_seat_one_hot(event.get("actor")))
        values.extend(_seat_one_hot(event.get("target")))
        values.append(1.0 if event.get("card_visible") else 0.0)
        values.extend(_one_hot(RANKS, event.get("card_match_value") or event.get("card_value")))
        values.append(_norm(event.get("card_points"), 13.0))
        values.append(_slot_norm(event.get("slot")))
        values.extend(_one_hot(DISCARD_REASONS, event.get("discard_reason")))
        values.extend(
            [
                _slot_norm(event.get("replaced_slot")),
                _norm(event.get("penalty_card_count"), 5.0),
                _norm(_float(event.get("action_count")) - base_action, 200.0),
                _norm(_float(event.get("turn_count")) - base_turn, 50.0),
            ]
        )
        rows[row_idx, :] = np.asarray(values, dtype=np.float32)
    return rows


def _encode_action_type_mask(legal_action: dict[str, Any]) -> np.ndarray:
    mask = np.zeros(len(ACTION_TYPES), dtype=bool)
    action_mask = ((legal_action.get("masks") or {}).get("action_type") or {})
    for name, enabled in action_mask.items():
        if enabled and name in ACTION_TYPES:
            mask[ACTION_TYPES.index(name)] = True
    return mask


def _encode_argument_masks(legal_action: dict[str, Any]) -> dict[str, np.ndarray]:
    masks = legal_action.get("masks") or {}
    actions = legal_action.get("actions") or []
    out = {
        "own_slot": np.zeros(MAX_SLOTS, dtype=bool),
        "match_slot": np.zeros(MAX_SLOTS, dtype=bool),
        "target_player": np.zeros(MAX_PLAYERS, dtype=bool),
        "target_slot": np.zeros((MAX_PLAYERS, MAX_SLOTS), dtype=bool),
        "player_a": np.zeros(MAX_PLAYERS, dtype=bool),
        "slot_a": np.zeros((MAX_PLAYERS, MAX_SLOTS), dtype=bool),
        "player_b": np.zeros(MAX_PLAYERS, dtype=bool),
        "slot_b": np.zeros((MAX_PLAYERS, MAX_SLOTS), dtype=bool),
    }

    _fill_slot_mask(out["own_slot"], masks.get("own_slot"))
    _fill_slot_mask(out["match_slot"], masks.get("match_slot"))

    for key in (masks.get("target_player") or {}):
        idx = _player_index(None, key)
        if 0 <= idx < MAX_PLAYERS:
            out["target_player"][idx] = True

    target_slot = masks.get("target_slot") or {}
    if isinstance(target_slot, dict):
        for seat, arr in target_slot.items():
            player_idx = _player_index(seat, None)
            if 0 <= player_idx < MAX_PLAYERS:
                _fill_slot_mask(out["target_slot"][player_idx], arr)

    for entry in actions:
        action = entry.get("action_v2") or {}
        action_type = action.get("action_type")
        if action_type == "jack_swap":
            player_a = _player_index(None, action.get("player_a"))
            player_b = _player_index(None, action.get("player_b"))
            slot_a = action.get("slot_a")
            slot_b = action.get("slot_b")
            if 0 <= player_a < MAX_PLAYERS:
                out["player_a"][player_a] = True
                if isinstance(slot_a, int) and 0 <= slot_a < MAX_SLOTS:
                    out["slot_a"][player_a, slot_a] = True
            if 0 <= player_b < MAX_PLAYERS:
                out["player_b"][player_b] = True
                if isinstance(slot_b, int) and 0 <= slot_b < MAX_SLOTS:
                    out["slot_b"][player_b, slot_b] = True
        elif action_type in {"joker", "power_10_spy"}:
            target = _player_index(None, action.get("target_player"))
            if 0 <= target < MAX_PLAYERS:
                out["target_player"][target] = True
            slot = action.get("target_slot")
            if isinstance(slot, int) and 0 <= target < MAX_PLAYERS and 0 <= slot < MAX_SLOTS:
                out["target_slot"][target, slot] = True

    return out


def _legacy_mask_or_none(msg: dict[str, Any]) -> np.ndarray | None:
    action_mask = msg.get("action_mask")
    if action_mask is None:
        return None
    # Keep this intentionally simple: v2 does not own the 6199-action contract.
    try:
        import encoding  # Local import to avoid making v2 depend on PPO at import time.

        return encoding.build_mask_vector(msg)
    except Exception:  # noqa: BLE001
        return None


def _fill_slot_mask(target: np.ndarray, values: Any) -> None:
    if not isinstance(values, list):
        return
    for idx, enabled in enumerate(values[:MAX_SLOTS]):
        if enabled:
            target[idx] = True


def _one_hot(vocab: list[str], value: Any) -> list[float]:
    out = [0.0] * len(vocab)
    if value is None:
        return out
    key = str(value)
    if key in vocab:
        out[vocab.index(key)] = 1.0
    return out


def _seat_one_hot(value: Any) -> list[float]:
    out = [0.0] * MAX_PLAYERS
    idx = _player_index(value, None)
    if 0 <= idx < MAX_PLAYERS:
        out[idx] = 1.0
    return out


def _player_index(player_id: Any, seat: Any) -> int:
    value = player_id if player_id is not None else seat
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        if value.startswith("p") and value[1:].isdigit():
            return int(value[1:])
        if value.isdigit():
            return int(value)
    return -1


def _slot_norm(value: Any) -> float:
    if value is None:
        return 0.0
    return _norm(value, float(max(1, MAX_SLOTS - 1)))


def _norm(value: Any, denom: float) -> float:
    return _float(value) / denom if denom else 0.0


def _float(value: Any) -> float:
    try:
        return 0.0 if value is None else float(value)
    except (TypeError, ValueError):
        return 0.0


def _find_forbidden_keys(value: Any) -> set[str]:
    found: set[str] = set()
    if isinstance(value, dict):
        for key, child in value.items():
            if key in FORBIDDEN_POLICY_KEYS:
                found.add(str(key))
            found.update(_find_forbidden_keys(child))
    elif isinstance(value, list):
        for child in value:
            found.update(_find_forbidden_keys(child))
    return found
