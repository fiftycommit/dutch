"""Safe heuristic behavior policy for AgentInterface v2 rollout collection.

Random legal play is a toxic teacher for Dutch'78: the game rewards memory,
certainty and timing, so a uniform legal policy produces mostly false matches,
failed Dutch calls and catastrophic trajectories. An off-policy learner trained
on that data concludes that "continuing to play is worse than a Dutch suicide".

This module provides a minimal, cautious behavior policy — a "basic human"
teacher — used only to *collect* cleaner data. It is NOT the final bot and it
never trains anything. It plays strictly from ``legal_action_v2.actions`` and
reads only legal, non-hidden observation fields.

Design (validated settings):

- reaction: match only a slot that is ``known && valid && confidence >= 1.0``
  and whose ``believed_match_value`` equals ``top_discard_value``; otherwise
  ``pass_tick``. Never a random match.
- dutch: ``call_dutch`` only when ``unknown_count == 0`` and
  ``believed_known_score <= DUTCH_SCORE_MAX``; otherwise ``draw``.
- post-draw: ``post_draw_replace`` the known/valid slot with the highest
  ``believed_points`` when ``drawn_points`` strictly improves it; otherwise
  ``post_draw_discard``. Never a random replace.
- powers: use info powers (``power_7_look``, ``power_10_spy``); skip risky swaps
  (``jack_swap``, ``joker``) via ``skip_power`` in this first version.

The policy signature matches ``rollout_v2.ActionPolicyV2`` so it is a drop-in
behavior policy for ``collect_rollouts_v2``.
"""

from __future__ import annotations

import random
from typing import Any

import encoding_v2


# Cautious Dutch threshold: only call Dutch with a fully known, low hand.
DUTCH_SCORE_MAX = 8.0
# Confidence required to treat an own slot as certain enough to match.
MATCH_CONFIDENCE_MIN = 1.0


def safe_heuristic_policy_v2(
    obs_raw: dict[str, Any],
    rng: random.Random | None = None,
) -> dict[str, Any]:
    """Pick one cautious legal action entry from ``legal_action_v2.actions``.

    The returned value is always a copy of an entry already present in
    ``legal_action_v2.actions`` (never a fabricated action). ``rng`` is accepted
    for ``ActionPolicyV2`` compatibility but the policy is deterministic.
    """

    del rng  # deterministic; kept only for ActionPolicyV2 signature

    entries = list(((obs_raw.get("legal_action_v2") or {}).get("actions") or []))
    if not entries:
        raise ValueError("safe_heuristic_policy_v2 requires legal_action_v2.actions")

    by_type: dict[str, list[dict[str, Any]]] = {}
    for entry in entries:
        action_type = ((entry.get("action_v2") or {}).get("action_type"))
        if action_type is not None:
            by_type.setdefault(str(action_type), []).append(entry)

    chosen = _decide(obs_raw, entries, by_type)
    _assert_entry_is_legal(entries, chosen)
    return dict(chosen)


def _decide(
    obs_raw: dict[str, Any],
    entries: list[dict[str, Any]],
    by_type: dict[str, list[dict[str, Any]]],
) -> dict[str, Any]:
    # Phases are disjoint in the runner, so branching on the offered action
    # types is robust and avoids depending on phase spelling.

    # 1. Dutch-or-draw.
    if "call_dutch" in by_type or "draw" in by_type:
        if "call_dutch" in by_type and _should_call_dutch(obs_raw):
            return by_type["call_dutch"][0]
        if "draw" in by_type:
            return by_type["draw"][0]
        return by_type["call_dutch"][0]

    # 2. Post-draw.
    if "post_draw_replace" in by_type or "post_draw_discard" in by_type:
        replace = _best_replace_entry(obs_raw, by_type.get("post_draw_replace", []))
        if replace is not None:
            return replace
        if "post_draw_discard" in by_type:
            return by_type["post_draw_discard"][0]
        return by_type["post_draw_replace"][0]

    # 3. Special powers: use info powers, skip risky swaps.
    if "power_7_look" in by_type:
        return _pick_power_7(obs_raw, by_type["power_7_look"])
    if "power_10_spy" in by_type:
        return _pick_power_10(obs_raw, by_type["power_10_spy"])
    if ("jack_swap" in by_type or "joker" in by_type) and "skip_power" in by_type:
        return by_type["skip_power"][0]

    # 4. Reaction: certain match or pass.
    if "match" in by_type:
        match = _pick_certain_match(obs_raw, by_type["match"])
        if match is not None:
            return match
        if "pass_tick" in by_type:
            return by_type["pass_tick"][0]

    # 5. Safe fallbacks that never gamble.
    if "pass_tick" in by_type:
        return by_type["pass_tick"][0]
    if "skip_power" in by_type:
        return by_type["skip_power"][0]
    return entries[0]


def _should_call_dutch(obs_raw: dict[str, Any]) -> bool:
    obs = _obs_block(obs_raw)
    unknown = _as_int(obs.get("unknown_count"))
    score = _as_float(obs.get("believed_known_score"))
    if unknown is None or score is None:
        return False
    return unknown == 0 and score <= DUTCH_SCORE_MAX


def _pick_certain_match(
    obs_raw: dict[str, Any],
    match_entries: list[dict[str, Any]],
) -> dict[str, Any] | None:
    own = _own_slots_by_index(obs_raw)
    top = _obs_block(obs_raw).get("top_discard_value")
    if top is None:
        return None
    top_key = str(top)

    best: dict[str, Any] | None = None
    best_points = -1.0
    for entry in match_entries:
        slot = _as_int((entry.get("action_v2") or {}).get("slot"))
        if slot is None:
            continue
        memory = own.get(slot)
        if not _slot_is_certain(memory):
            continue
        if str(memory.get("believed_match_value")) != top_key:
            continue
        points = _as_float(memory.get("believed_points")) or 0.0
        if points > best_points:
            best_points = points
            best = entry
    return best


def _best_replace_entry(
    obs_raw: dict[str, Any],
    replace_entries: list[dict[str, Any]],
) -> dict[str, Any] | None:
    drawn = _as_float(_obs_block(obs_raw).get("drawn_points"))
    if drawn is None or not replace_entries:
        return None

    own = _own_slots_by_index(obs_raw)
    candidate: dict[str, Any] | None = None
    max_points = -1.0
    for entry in replace_entries:
        slot = _as_int((entry.get("action_v2") or {}).get("slot"))
        if slot is None:
            continue
        memory = own.get(slot)
        if not _slot_is_known(memory):
            continue
        points = _as_float(memory.get("believed_points"))
        if points is None:
            continue
        if points > max_points:
            max_points = points
            candidate = entry
    if candidate is not None and drawn < max_points:
        return candidate
    return None


def _pick_power_7(
    obs_raw: dict[str, Any],
    entries: list[dict[str, Any]],
) -> dict[str, Any]:
    own = _own_slots_by_index(obs_raw)
    for entry in entries:
        slot = _as_int((entry.get("action_v2") or {}).get("slot"))
        if slot is None:
            continue
        if not _slot_is_known(own.get(slot)):
            return entry  # prefer looking at an unknown own card
    return entries[0]


def _pick_power_10(
    obs_raw: dict[str, Any],
    entries: list[dict[str, Any]],
) -> dict[str, Any]:
    known_targets = _spied_known_targets(obs_raw)
    for entry in entries:
        action = entry.get("action_v2") or {}
        target = (_as_int(action.get("target_player")), _as_int(action.get("target_slot")))
        if target not in known_targets:
            return entry  # prefer spying a card we do not already know
    return entries[0]


def _own_slots_by_index(obs_raw: dict[str, Any]) -> dict[int, dict[str, Any]]:
    memory = obs_raw.get("legal_private_memory") or {}
    slots = ((memory.get("own_hand") or {}).get("slots") or [])
    by_index: dict[int, dict[str, Any]] = {}
    for slot in slots:
        if not isinstance(slot, dict):
            continue
        idx = _as_int(slot.get("slot"))
        if idx is not None:
            by_index[idx] = slot
    return by_index


def _spied_known_targets(obs_raw: dict[str, Any]) -> set[tuple[int | None, int | None]]:
    memory = obs_raw.get("legal_private_memory") or {}
    targets: set[tuple[int | None, int | None]] = set()
    for opponent in (memory.get("opponents") or []):
        if not isinstance(opponent, dict):
            continue
        player_idx = _player_index(opponent.get("player_id"), opponent.get("seat"))
        for slot in (opponent.get("spied_slots") or []):
            if not isinstance(slot, dict):
                continue
            if _slot_is_known(slot):
                targets.add((player_idx, _as_int(slot.get("slot"))))
    return targets


def _slot_is_known(memory: dict[str, Any] | None) -> bool:
    if not isinstance(memory, dict):
        return False
    return bool(memory.get("known")) and bool(memory.get("valid", True))


def _slot_is_certain(memory: dict[str, Any] | None) -> bool:
    if not _slot_is_known(memory):
        return False
    confidence = _as_float(memory.get("confidence"))
    return confidence is not None and confidence >= MATCH_CONFIDENCE_MIN


def _obs_block(obs_raw: dict[str, Any]) -> dict[str, Any]:
    obs = obs_raw.get("obs")
    return obs if isinstance(obs, dict) else {}


def _player_index(player_id: Any, seat: Any) -> int | None:
    value = player_id if player_id is not None else seat
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        if value.startswith("p") and value[1:].isdigit():
            return int(value[1:])
        if value.isdigit():
            return int(value)
    return None


def _assert_entry_is_legal(
    entries: list[dict[str, Any]],
    chosen: dict[str, Any],
) -> None:
    chosen_action = chosen.get("action_v2")
    chosen_legacy = chosen.get("legacy_action_id")
    for entry in entries:
        if chosen_action is not None and entry.get("action_v2") == chosen_action:
            return
        if chosen_legacy is not None and entry.get("legacy_action_id") == chosen_legacy:
            return
    raise ValueError(f"safe_heuristic chose action outside legal set: {chosen!r}")


def _as_int(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return None


def _as_float(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    return None


# Sanity: the whitelisted fields this policy reads must not overlap the hidden
# keys the encoder forbids. Kept as a module-level invariant for auditability.
_READS_ONLY_LEGAL_FIELDS = {
    "obs.top_discard_value",
    "obs.unknown_count",
    "obs.believed_known_score",
    "obs.drawn_points",
    "legal_private_memory.own_hand.slots",
    "legal_private_memory.opponents.spied_slots",
    "legal_action_v2.actions",
}
assert not (
    {field.split(".")[-1] for field in _READS_ONLY_LEGAL_FIELDS}
    & encoding_v2.FORBIDDEN_POLICY_KEYS
), "safe_heuristic must not read forbidden hidden keys"
