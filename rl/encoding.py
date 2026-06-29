"""Encodage observation→vecteur fixe et action_idx→message NDJSON.

Côté observation : message Dart → vecteur ``float32`` de dimension fixe
``OBS_DIM`` (146), agrégats pour les adversaires (pas de slots bruts).
(Les poids de préférence MORL ont été retirés : la reward n'est plus scalarisée
par un vecteur de poids — cf. dutch_env.py.)

Côté action : ``Discrete(N_ACTIONS)`` masqué, les ``kind`` aplatis avec
``MAX_HAND=13`` et un ``powerV_swap`` factorisé en (own_index, target_seat) — le
``target_index`` est canonique = 0. Les actions de réaction sont ajoutées en fin
de table pour préserver les indices historiques.
"""

from __future__ import annotations

from typing import Any

import numpy as np

# ── Constantes de bornage ──────────────────────────────────────────────────
MAX_HAND = 13
MAX_OPP = 5
RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "V", "D", "R"]

# Dimension d'observation figée (37 global + 12 self-agg + 78 slots + 20 opp).
OBS_DIM = 37 + 12 + (6 * MAX_HAND) + (4 * MAX_OPP)  # = 147

# ── Table d'indices d'action (blocs contigus) ──────────────────────────────
_CALL_DUTCH = 0
_CONTINUE_DRAW = 1
_DISCARD_DRAWN = 2
_SKIP_POWER = 3
_REPLACE = 4                       # 4 .. 4+13
_POWER7 = _REPLACE + MAX_HAND      # 17 .. 17+13
_POWER10 = _POWER7 + MAX_HAND      # 30 .. 30+65   (opp*13 + i)
_POWERV = _POWER10 + MAX_OPP * MAX_HAND  # 95 .. 95+65 (own*5 + opp)
_POWERJOKER = _POWERV + MAX_HAND * MAX_OPP  # 160 .. 160+5
_PASS_TICK = _POWERJOKER + MAX_OPP  # 165
_MATCH = _PASS_TICK + 1             # 166 .. 166+13
N_ACTIONS = _MATCH + MAX_HAND      # 179

MICRO_PHASES = ["dutchOrDraw", "postDraw", "power", "reaction"]


def _seat(opp_idx: int) -> str:
    """opp_idx 0..4 -> siège adverse 'p1'..'p5' (le siège RL est 'p0')."""
    return f"p{opp_idx + 1}"


def seat_to_opp(seat: str) -> int:
    """'p3' -> 2."""
    return int(seat[1:]) - 1


# ── action_idx -> message NDJSON ───────────────────────────────────────────
def action_to_message(idx: int) -> dict[str, Any]:
    if idx == _CALL_DUTCH:
        return {"kind": "call_dutch"}
    if idx == _CONTINUE_DRAW:
        return {"kind": "continue_draw"}
    if idx == _DISCARD_DRAWN:
        return {"kind": "discard_drawn"}
    if idx == _SKIP_POWER:
        return {"kind": "skip_power"}
    if _REPLACE <= idx < _REPLACE + MAX_HAND:
        return {"kind": "replace", "params": {"index": idx - _REPLACE}}
    if _POWER7 <= idx < _POWER7 + MAX_HAND:
        return {"kind": "power7_look", "params": {"index": idx - _POWER7}}
    if _POWER10 <= idx < _POWER10 + MAX_OPP * MAX_HAND:
        rel = idx - _POWER10
        opp, i = divmod(rel, MAX_HAND)
        return {"kind": "power10_spy",
                "params": {"target_seat": _seat(opp), "index": i}}
    if _POWERV <= idx < _POWERV + MAX_HAND * MAX_OPP:
        rel = idx - _POWERV
        own, opp = divmod(rel, MAX_OPP)
        return {"kind": "powerV_swap",
                "params": {"own_index": own, "target_seat": _seat(opp),
                           "target_index": 0}}  # canonique
    if _POWERJOKER <= idx < _POWERJOKER + MAX_OPP:
        return {"kind": "powerJoker",
                "params": {"target_seat": _seat(idx - _POWERJOKER)}}
    if idx == _PASS_TICK:
        return {"kind": "pass_tick"}
    if _MATCH <= idx < _MATCH + MAX_HAND:
        return {"kind": "match", "params": {"index": idx - _MATCH}}
    raise ValueError(f"index d'action hors borne: {idx}")


# ── action_mask Dart -> vecteur booléen (165) ──────────────────────────────
def build_mask_vector(msg: dict[str, Any]) -> np.ndarray:
    mask = np.zeros(N_ACTIONS, dtype=bool)
    if msg.get("done"):
        return mask  # terminal : aucune action
    dm = msg.get("action_mask")
    if dm is None:
        return mask
    micro = msg.get("micro_phase")

    if micro == "dutchOrDraw":
        mask[_CALL_DUTCH] = bool(dm.get("call_dutch", False))
        mask[_CONTINUE_DRAW] = bool(dm.get("continue_draw", False))
        return mask

    if micro == "postDraw":
        mask[_DISCARD_DRAWN] = bool(dm.get("discard_drawn", False))
        for i, ok in enumerate(dm.get("replace", [])):
            if i < MAX_HAND and ok:
                mask[_REPLACE + i] = True
        return mask

    if micro == "reaction":
        mask[_PASS_TICK] = bool(dm.get("pass_tick", dm.get("no_match", False)))
        for i, ok in enumerate(dm.get("match", [])):
            if i < MAX_HAND and ok:
                mask[_MATCH + i] = True
        return mask

    # micro == "power"
    mask[_SKIP_POWER] = bool(dm.get("skip_power", False))
    if "power7_look" in dm:
        for i, ok in enumerate(dm["power7_look"]):
            if i < MAX_HAND and ok:
                mask[_POWER7 + i] = True
    elif "power10_spy" in dm:
        for seat, arr in dm["power10_spy"].items():
            opp = seat_to_opp(seat)
            if opp >= MAX_OPP:
                continue
            for i, ok in enumerate(arr):
                if i < MAX_HAND and ok:
                    mask[_POWER10 + opp * MAX_HAND + i] = True
    elif "powerV_swap" in dm:
        own_arr = dm["powerV_swap"]["own"]
        targets = dm["powerV_swap"]["targets"]
        for own, own_ok in enumerate(own_arr):
            if own >= MAX_HAND or not own_ok:
                continue
            for seat, t_arr in targets.items():
                opp = seat_to_opp(seat)
                # target_index canonique = 0 -> légal si la cible a >=1 carte.
                if opp < MAX_OPP and len(t_arr) > 0 and t_arr[0]:
                    mask[_POWERV + own * MAX_OPP + opp] = True
    elif "powerJoker" in dm:
        for seat, ok in dm["powerJoker"].items():
            opp = seat_to_opp(seat)
            if opp < MAX_OPP and ok:
                mask[_POWERJOKER + opp] = True
    return mask


# ── Observation Dart -> vecteur float32 (OBS_DIM) ──────────────────────────
def _f(x: Any, default: float = 0.0) -> float:
    return float(x) if x is not None else default


def encode_observation(msg: dict[str, Any]) -> np.ndarray:
    """Encode l'observation Dart en vecteur float32 de dimension OBS_DIM."""
    o = msg.get("obs", {})
    vec: list[float] = []

    # ── (36) Global ────────────────────────────────────────────────────────
    vec.append(_f(o.get("turn_count")) / 50.0)
    vec.append(_f(o.get("action_count")) / 200.0)
    vec.append(_f(o.get("deck_size")) / 54.0)
    vec.append(_f(o.get("discard_size")) / 54.0)
    vec.append(1.0 if o.get("top_discard_value") is not None else 0.0)
    vec.append(_f(o.get("top_discard_points")) / 13.0)
    vec.append(1.0 if o.get("dutch_called") else 0.0)
    vec.append(1.0 if o.get("dutch_caller_is_me") else 0.0)
    vec.append(_f(o.get("expected_deck_card_value")) / 13.0)
    # num_players one-hot (2..6)
    npl = int(_f(o.get("num_players"), 2))
    onehot_n = [0.0] * 5
    if 2 <= npl <= 6:
        onehot_n[npl - 2] = 1.0
    vec.extend(onehot_n)
    # micro_phase one-hot
    micro = msg.get("micro_phase")
    onehot_m = [0.0] * len(MICRO_PHASES)
    if micro in MICRO_PHASES:
        onehot_m[MICRO_PHASES.index(micro)] = 1.0
    vec.extend(onehot_m)
    vec.append(_f(o.get("seat_index")) / 5.0)
    vec.append(_f(msg.get("proxy_threat")) / 110.0)
    vec.append(_f(o.get("min_opponent_hand_size")) / 13.0)
    vec.append(1.0 if o.get("drawn_value") is not None else 0.0)
    vec.append(_f(o.get("drawn_points")) / 13.0)
    # discarded_ranks (13)
    dr = o.get("discarded_ranks", {}) or {}
    for r in RANKS:
        vec.append(min(_f(dr.get(r)) / 4.0, 1.0))
    # overflow flag
    hand_size = int(_f(o.get("hand_size")))
    vec.append(1.0 if hand_size > MAX_HAND else 0.0)

    # ── (12) Self agrégats ─────────────────────────────────────────────────
    vec.append(_f(o.get("hand_size")) / MAX_HAND)
    vec.append(_f(o.get("known_count")) / MAX_HAND)
    vec.append(_f(o.get("unknown_count")) / MAX_HAND)
    vec.append(_f(o.get("memory_confidence")))
    vec.append(_f(o.get("believed_known_score")) / 80.0)
    vec.append(_f(o.get("max_known_value")) / 13.0)
    vec.append(1.0 if o.get("has_doublon") else 0.0)
    vec.append(_f(o.get("doublon_count")) / 4.0)
    vec.append(_f(o.get("expected_unknown_value_sum")) / 80.0)
    vec.append(_f(o.get("believed_total_score_estimate")) / 100.0)
    vec.append(_f(o.get("spied_opponent_cards_count")) / 20.0)
    vec.append(_f(o.get("best_match_probability")))

    # ── (78) Self slots, paddés à MAX_HAND ─────────────────────────────────
    slots = o.get("slots", []) or []
    for i in range(MAX_HAND):
        if i < len(slots):
            s = slots[i]
            vec.append(1.0)  # present
            vec.append(1.0 if s.get("known") else 0.0)
            vec.append(_f(s.get("believed_points")) / 13.0)
            vec.append(_f(s.get("hint_quality")))            # déjà -1..1
            vec.append(_f(s.get("hint_confidence")))
            vec.append(min(_f(s.get("hint_age")) / 20.0, 1.0))
        else:
            vec.extend([0.0] * 6)

    # ── (20) Opp agrégats, paddés à MAX_OPP ────────────────────────────────
    opps = o.get("opponents", []) or []
    for i in range(MAX_OPP):
        if i < len(opps):
            op = opps[i]
            vec.append(1.0)  # present
            vec.append(_f(op.get("hand_size")) / MAX_HAND)
            spied = op.get("spied", {}) or {}
            vec.append(min(len(spied) / MAX_HAND, 1.0))
            ago = op.get("last_targeted_ago")
            vec.append(min(_f(ago) / 20.0, 1.0) if ago is not None else 0.0)
        else:
            vec.extend([0.0] * 4)

    arr = np.asarray(vec, dtype=np.float32)
    assert arr.shape[0] == OBS_DIM, f"OBS_DIM={OBS_DIM} != {arr.shape[0]}"
    return arr
