"""Tests for the safe heuristic v2 behavior policy and its CLI wiring.

Run from rl/:
    uv run python test_safe_heuristic_v2.py

These tests use synthetic legal observations only; they never launch a runner.
"""

from __future__ import annotations

import random
from typing import Any

import collect_rollouts_v2
import safe_heuristic_v2


# --- synthetic observation builders (legal blocks only) --------------------


def _base(actions: list[dict[str, Any]], **obs_fields: Any) -> dict[str, Any]:
    obs = {
        "phase": "playing",
        "num_players": 4,
        "hand_size": 4,
        "top_discard_value": "7",
        "top_discard_points": 7,
        "dutch_called": False,
        "opponents": [],
    }
    obs.update(obs_fields)
    return {
        "type": "observation",
        "done": False,
        "step": 0,
        "micro_phase": "playing",
        "obs": obs,
        "recent_events": [],
        "slot_stability": {"players": []},
        "legal_private_memory": {"own_hand": {"slots": []}, "opponents": []},
        "legal_action_v2": {"actions": actions},
    }


def _entry(action_type: str, legacy_id: int, **kwargs: Any) -> dict[str, Any]:
    action: dict[str, Any] = {"action_type": action_type}
    action.update(kwargs)
    return {"action_v2": action, "legacy_action_id": legacy_id}


def _own_slot(
    slot: int,
    *,
    known: bool = True,
    valid: bool = True,
    confidence: float = 1.0,
    match_value: str | None = "7",
    points: int | None = 7,
) -> dict[str, Any]:
    return {
        "slot": slot,
        "known": known,
        "valid": valid,
        "confidence": confidence,
        "believed_match_value": match_value,
        "believed_points": points,
        "believed_value": match_value,
    }


def _reaction_obs(match_slots: list[int], own_slots: list[dict[str, Any]], top: str = "7"):
    actions = [_entry("pass_tick", 6185)]
    for s in match_slots:
        actions.append(_entry("match", 6186 + s, slot=s))
    obs = _base(actions, top_discard_value=top, micro_phase="reaction")
    obs["micro_phase"] = "reaction"
    obs["obs"]["micro_phase"] = "reaction"
    obs["legal_private_memory"]["own_hand"]["slots"] = own_slots
    return obs


def _dutch_obs(unknown_count: int, believed_known_score: float):
    actions = [_entry("call_dutch", 100), _entry("draw", 101)]
    return _base(
        actions,
        micro_phase="dutchOrDraw",
        unknown_count=unknown_count,
        known_count=4 - unknown_count,
        believed_known_score=believed_known_score,
    )


def _postdraw_obs(drawn_points: int, own_slots: list[dict[str, Any]]):
    actions = [_entry("post_draw_discard", 200)]
    for s in own_slots:
        actions.append(_entry("post_draw_replace", 201 + s["slot"], slot=s["slot"]))
    obs = _base(actions, micro_phase="postDraw", drawn_points=drawn_points, drawn_value="X")
    obs["legal_private_memory"]["own_hand"]["slots"] = own_slots
    return obs


def _action_type(entry: dict[str, Any]) -> str:
    return (entry.get("action_v2") or {}).get("action_type")


# --- tests -----------------------------------------------------------------


def test_random_mode_unchanged() -> None:
    if collect_rollouts_v2.POLICIES["random"] is not collect_rollouts_v2.choose_legal_action_v2:
        raise AssertionError("random policy must remain choose_legal_action_v2")


def test_cli_exposes_policy_flag() -> None:
    parser = collect_rollouts_v2.build_arg_parser()
    default = parser.parse_args([])
    if default.policy != "random":
        raise AssertionError("default policy must be random")
    chosen = parser.parse_args(["--policy", "safe_heuristic"])
    if chosen.policy != "safe_heuristic":
        raise AssertionError("safe_heuristic must be selectable via CLI")


def test_never_returns_illegal_action() -> None:
    obs_list = [
        _reaction_obs([0, 1], [_own_slot(0), _own_slot(1, match_value="D", points=12)]),
        _dutch_obs(0, 5),
        _dutch_obs(2, 5),
        _postdraw_obs(2, [_own_slot(0, points=10)]),
        _postdraw_obs(11, [_own_slot(0, points=10)]),
    ]
    for obs in obs_list:
        legal = {repr(e["action_v2"]) for e in obs["legal_action_v2"]["actions"]}
        chosen = safe_heuristic_v2.safe_heuristic_policy_v2(obs, random.Random(0))
        if repr(chosen["action_v2"]) not in legal:
            raise AssertionError(f"chose illegal action: {chosen}")


def test_reaction_uncertain_passes() -> None:
    # Slot value does not match the top discard -> uncertain -> pass_tick.
    obs = _reaction_obs([0], [_own_slot(0, match_value="9", points=9)], top="7")
    chosen = safe_heuristic_v2.safe_heuristic_policy_v2(obs, random.Random(0))
    if _action_type(chosen) != "pass_tick":
        raise AssertionError(f"expected pass_tick, got {chosen}")


def test_reaction_certain_match() -> None:
    obs = _reaction_obs([0], [_own_slot(0, match_value="7", points=7)], top="7")
    chosen = safe_heuristic_v2.safe_heuristic_policy_v2(obs, random.Random(0))
    if _action_type(chosen) != "match" or chosen["action_v2"]["slot"] != 0:
        raise AssertionError(f"expected certain match slot 0, got {chosen}")


def test_no_match_when_confidence_low() -> None:
    obs = _reaction_obs([0], [_own_slot(0, confidence=0.5, match_value="7")], top="7")
    chosen = safe_heuristic_v2.safe_heuristic_policy_v2(obs, random.Random(0))
    if _action_type(chosen) != "pass_tick":
        raise AssertionError(f"low confidence must not match, got {chosen}")


def test_no_match_when_slot_invalid() -> None:
    obs = _reaction_obs([0], [_own_slot(0, valid=False, match_value="7")], top="7")
    chosen = safe_heuristic_v2.safe_heuristic_policy_v2(obs, random.Random(0))
    if _action_type(chosen) != "pass_tick":
        raise AssertionError(f"invalid slot must not match, got {chosen}")


def test_certain_match_prefers_highest_points() -> None:
    obs = _reaction_obs(
        [0, 1],
        [_own_slot(0, match_value="7", points=7), _own_slot(1, match_value="7", points=7)],
        top="7",
    )
    # Give slot 1 higher points to check tie-breaking on removal value.
    obs["legal_private_memory"]["own_hand"]["slots"][1]["believed_points"] = 13
    chosen = safe_heuristic_v2.safe_heuristic_policy_v2(obs, random.Random(0))
    if chosen["action_v2"]["slot"] != 1:
        raise AssertionError(f"should drop highest-points certain card, got {chosen}")


def test_no_dutch_when_unknown_present() -> None:
    obs = _dutch_obs(unknown_count=2, believed_known_score=5)
    chosen = safe_heuristic_v2.safe_heuristic_policy_v2(obs, random.Random(0))
    if _action_type(chosen) != "draw":
        raise AssertionError(f"must draw when hand not fully known, got {chosen}")


def test_no_dutch_when_score_high() -> None:
    obs = _dutch_obs(unknown_count=0, believed_known_score=12)
    chosen = safe_heuristic_v2.safe_heuristic_policy_v2(obs, random.Random(0))
    if _action_type(chosen) != "draw":
        raise AssertionError(f"must draw when known score too high, got {chosen}")


def test_dutch_when_known_and_low() -> None:
    obs = _dutch_obs(unknown_count=0, believed_known_score=8)
    chosen = safe_heuristic_v2.safe_heuristic_policy_v2(obs, random.Random(0))
    if _action_type(chosen) != "call_dutch":
        raise AssertionError(f"expected call_dutch, got {chosen}")


def test_postdraw_replace_when_improving() -> None:
    obs = _postdraw_obs(drawn_points=2, own_slots=[_own_slot(0, points=10), _own_slot(1, points=6)])
    chosen = safe_heuristic_v2.safe_heuristic_policy_v2(obs, random.Random(0))
    if _action_type(chosen) != "post_draw_replace" or chosen["action_v2"]["slot"] != 0:
        raise AssertionError(f"should replace highest known slot, got {chosen}")


def test_postdraw_discard_when_not_improving() -> None:
    obs = _postdraw_obs(drawn_points=11, own_slots=[_own_slot(0, points=10)])
    chosen = safe_heuristic_v2.safe_heuristic_policy_v2(obs, random.Random(0))
    if _action_type(chosen) != "post_draw_discard":
        raise AssertionError(f"should discard when not improving, got {chosen}")


def test_postdraw_discard_when_no_known_slot() -> None:
    obs = _postdraw_obs(drawn_points=2, own_slots=[_own_slot(0, known=False, points=None)])
    chosen = safe_heuristic_v2.safe_heuristic_policy_v2(obs, random.Random(0))
    if _action_type(chosen) != "post_draw_discard":
        raise AssertionError(f"no known slot -> discard, got {chosen}")


def test_power_7_uses_info_on_unknown_slot() -> None:
    actions = [
        _entry("skip_power", 300),
        _entry("power_7_look", 301, slot=0),
        _entry("power_7_look", 302, slot=1),
    ]
    obs = _base(actions, micro_phase="power")
    obs["legal_private_memory"]["own_hand"]["slots"] = [
        _own_slot(0, known=True),
        _own_slot(1, known=False, points=None),
    ]
    chosen = safe_heuristic_v2.safe_heuristic_policy_v2(obs, random.Random(0))
    if _action_type(chosen) != "power_7_look" or chosen["action_v2"]["slot"] != 1:
        raise AssertionError(f"power_7 should look at unknown slot, got {chosen}")


def test_power_10_uses_info() -> None:
    actions = [
        _entry("skip_power", 400),
        _entry("power_10_spy", 401, target_player=1, target_slot=0),
    ]
    obs = _base(actions, micro_phase="power")
    chosen = safe_heuristic_v2.safe_heuristic_policy_v2(obs, random.Random(0))
    if _action_type(chosen) != "power_10_spy":
        raise AssertionError(f"power_10 should be used for info, got {chosen}")


def test_jack_swap_is_skipped() -> None:
    actions = [
        _entry("skip_power", 500),
        _entry("jack_swap", 501, player_a=0, slot_a=0, player_b=1, slot_b=0),
    ]
    obs = _base(actions, micro_phase="power")
    chosen = safe_heuristic_v2.safe_heuristic_policy_v2(obs, random.Random(0))
    if _action_type(chosen) != "skip_power":
        raise AssertionError(f"jack_swap must be skipped, got {chosen}")


def test_joker_is_skipped() -> None:
    actions = [
        _entry("skip_power", 600),
        _entry("joker", 601, target_player=1, target_slot=0),
    ]
    obs = _base(actions, micro_phase="power")
    chosen = safe_heuristic_v2.safe_heuristic_policy_v2(obs, random.Random(0))
    if _action_type(chosen) != "skip_power":
        raise AssertionError(f"joker must be skipped, got {chosen}")


def test_ignores_forbidden_hidden_keys() -> None:
    # Injecting hidden keys must not change the decision, proving the policy
    # never reads them.
    clean = _reaction_obs([0], [_own_slot(0, match_value="9")], top="7")
    poisoned = _reaction_obs([0], [_own_slot(0, match_value="9")], top="7")
    poisoned["true_score"] = {"p1": 0}
    poisoned["obs"]["full_hand"] = ["A", "A", "A"]
    poisoned["legal_private_memory"]["opponent_hand"] = [["7"]]
    poisoned["deck_order"] = ["7", "7"]
    poisoned["debug_eval_labels"] = {"dutch_would_win": True}
    a = safe_heuristic_v2.safe_heuristic_policy_v2(clean, random.Random(0))
    b = safe_heuristic_v2.safe_heuristic_policy_v2(poisoned, random.Random(0))
    if a["action_v2"] != b["action_v2"]:
        raise AssertionError("hidden keys changed the decision (leak!)")


def test_deterministic_and_pure() -> None:
    obs = _dutch_obs(0, 8)
    first = safe_heuristic_v2.safe_heuristic_policy_v2(obs, random.Random(1))
    second = safe_heuristic_v2.safe_heuristic_policy_v2(obs, random.Random(999))
    if first["action_v2"] != second["action_v2"]:
        raise AssertionError("policy must be deterministic regardless of rng")


def test_empty_legal_actions_raises() -> None:
    obs = _base([])
    try:
        safe_heuristic_v2.safe_heuristic_policy_v2(obs, random.Random(0))
    except ValueError:
        return
    raise AssertionError("empty legal actions should raise")


def main() -> int:
    tests = [
        test_random_mode_unchanged,
        test_cli_exposes_policy_flag,
        test_never_returns_illegal_action,
        test_reaction_uncertain_passes,
        test_reaction_certain_match,
        test_no_match_when_confidence_low,
        test_no_match_when_slot_invalid,
        test_certain_match_prefers_highest_points,
        test_no_dutch_when_unknown_present,
        test_no_dutch_when_score_high,
        test_dutch_when_known_and_low,
        test_postdraw_replace_when_improving,
        test_postdraw_discard_when_not_improving,
        test_postdraw_discard_when_no_known_slot,
        test_power_7_uses_info_on_unknown_slot,
        test_power_10_uses_info,
        test_jack_swap_is_skipped,
        test_joker_is_skipped,
        test_ignores_forbidden_hidden_keys,
        test_deterministic_and_pure,
        test_empty_legal_actions_raises,
    ]
    print("=== test_safe_heuristic_v2 ===")
    for test in tests:
        test()
        print(f"  [OK] {test.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
