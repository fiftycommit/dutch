"""Tests for the existing_bot (bot_auto) collection path.

Run from rl/:
    uv run python test_existing_bot_v2.py

Uses a mock runner only; never launches the Dart runner. Verifies the CLI flag,
the bot_auto plumbing (Python records the runner-applied action), the legality
guard, and that random / safe_heuristic remain untouched.
"""

from __future__ import annotations

import random
from typing import Any

import collect_rollouts_v2


def _obs(
    *,
    legal: list[dict[str, Any]],
    micro: str = "dutchOrDraw",
    done: bool = False,
    applied: dict[str, Any] | None = None,
    step: int = 0,
) -> dict[str, Any]:
    msg: dict[str, Any] = {
        "type": "observation",
        "done": done,
        "step": step,
        "micro_phase": micro,
        "obs": {
            "phase": "playing",
            "micro_phase": micro,
            "num_players": 3,
            "top_discard_value": "7",
            "top_discard_points": 7,
            "hand_size": 3,
            "opponents": [],
        },
        "recent_events": [],
        "slot_stability": {"players": []},
        "legal_private_memory": {"own_hand": {"slots": []}, "opponents": []},
        "legal_action_v2": {"actions": legal},
    }
    if applied is not None:
        msg["applied_action_v2"] = applied
    if done:
        msg["info"] = {"rank": 2, "won": False, "final_scores": {"p0": 10}}
        msg["rewards"] = {"principal": 0.0}
    return msg


def _entry(action_type: str, **kwargs: Any) -> dict[str, Any]:
    action = {"action_type": action_type}
    action.update(kwargs)
    return {"action_v2": action, "legacy_action_id": 0, "legacy_kind": action_type}


DRAW_STEP = [_entry("call_dutch"), _entry("draw")]
DISCARD_STEP = [_entry("post_draw_discard"), _entry("post_draw_replace", slot=0)]


class BotAutoMockRunner:
    """Mock runner that plays a fixed 2-primitive p0 turn via bot_auto."""

    def __init__(self, *, applied_illegal: bool = False) -> None:
        self.reset_calls: list[dict[str, Any]] = []
        self.step_msgs: list[dict[str, Any]] = []
        self._i = 0
        self._applied_illegal = applied_illegal

    def reset(self, seed, episode_id=None, extra_options=None):
        self._i = 0
        self.reset_calls.append({"seed": seed, "extra_options": extra_options})
        return _obs(legal=DRAW_STEP, micro="dutchOrDraw")

    def step(self, action_msg):
        self.step_msgs.append(action_msg)
        self._i += 1
        if self._i == 1:
            applied = (
                {"action_type": "match", "slot": 9}  # not in DRAW_STEP legal
                if self._applied_illegal
                else {"action_type": "draw"}
            )
            return _obs(
                legal=DISCARD_STEP, micro="postDraw", applied=applied, step=1
            )
        return _obs(
            legal=[],
            done=True,
            applied={"action_type": "post_draw_discard"},
            step=2,
        )


def test_cli_exposes_existing_bot() -> None:
    parser = collect_rollouts_v2.build_arg_parser()
    args = parser.parse_args(["--policy", "existing_bot"])
    if args.policy != "existing_bot":
        raise AssertionError("existing_bot not selectable")
    if args.bot_difficulty is not None:
        raise AssertionError("bot_difficulty should default to None")
    hard = parser.parse_args(["--policy", "existing_bot", "--bot-difficulty", "hard"])
    if hard.bot_difficulty != "hard":
        raise AssertionError("bot_difficulty hard not accepted")
    het = parser.parse_args(
        ["--policy", "existing_bot", "--opponent-bot-difficulty", "bronze"]
    )
    if het.opponent_bot_difficulty != "bronze":
        raise AssertionError("opponent-bot-difficulty not accepted")


def test_random_and_safe_unchanged() -> None:
    # existing_bot must NOT be added to POLICIES (it is runner-driven).
    if "existing_bot" in collect_rollouts_v2.POLICIES:
        raise AssertionError("existing_bot must not be a Python POLICY")
    if collect_rollouts_v2.POLICIES["random"] is not collect_rollouts_v2.choose_legal_action_v2:
        raise AssertionError("random policy changed")
    if "safe_heuristic" not in collect_rollouts_v2.POLICIES:
        raise AssertionError("safe_heuristic policy missing")


def test_bot_auto_records_applied_action() -> None:
    runner = BotAutoMockRunner()
    record = collect_rollouts_v2.collect_episode_v2(
        runner,
        seed=0,
        episode_id="eb",
        rng=random.Random(0),
        max_steps=10,
        bot_auto=True,
    )
    # Every step must have sent the bot_auto sentinel, never a chosen action.
    if any(m != {"kind": "bot_auto"} for m in runner.step_msgs):
        raise AssertionError(f"non-bot_auto messages sent: {runner.step_msgs}")
    types = [(t.action_v2 or {}).get("action_type") for t in record.transitions]
    if types != ["draw", "post_draw_discard"]:
        raise AssertionError(f"unexpected captured actions: {types}")
    if not record.completed:
        raise AssertionError("episode should complete")


def test_bot_auto_rejects_illegal_applied_action() -> None:
    runner = BotAutoMockRunner(applied_illegal=True)
    try:
        collect_rollouts_v2.collect_episode_v2(
            runner,
            seed=0,
            episode_id="eb-bad",
            rng=random.Random(0),
            max_steps=10,
            bot_auto=True,
        )
    except RuntimeError as exc:
        if "not in obs_before legal set" not in str(exc):
            raise AssertionError(f"unexpected error: {exc}") from exc
    else:
        raise AssertionError("illegal applied_action_v2 was not rejected")


def test_extra_options_force_hard() -> None:
    runner = BotAutoMockRunner()
    collect_rollouts_v2.collect_rollouts_v2(
        runner,
        episodes=1,
        seed=0,
        max_steps=10,
        players=6,
        bot_auto=True,
    )
    opts = runner.reset_calls[0]["extra_options"]
    if opts.get("p0_policy") != "existing_bot":
        raise AssertionError(f"p0_policy not forwarded: {opts}")
    if opts.get("bot_difficulty") != "hard":
        raise AssertionError(f"bot_difficulty default not hard: {opts}")
    if opts.get("num_players") != 6:
        raise AssertionError(f"num_players not forwarded: {opts}")


def test_extra_options_explicit_difficulty() -> None:
    runner = BotAutoMockRunner()
    collect_rollouts_v2.collect_rollouts_v2(
        runner,
        episodes=1,
        seed=0,
        max_steps=10,
        bot_auto=True,
        bot_difficulty="difficile",
    )
    opts = runner.reset_calls[0]["extra_options"]
    if opts.get("bot_difficulty") != "difficile":
        raise AssertionError(f"explicit difficulty not forwarded: {opts}")


def test_extra_options_opponent_difficulty() -> None:
    runner = BotAutoMockRunner()
    collect_rollouts_v2.collect_rollouts_v2(
        runner,
        episodes=1,
        seed=0,
        max_steps=10,
        players=6,
        bot_auto=True,
        opponent_bot_difficulty="bronze",
    )
    opts = runner.reset_calls[0]["extra_options"]
    if opts.get("bot_difficulty") != "hard":
        raise AssertionError(f"p0 should stay hard: {opts}")
    if opts.get("opponent_bot_difficulty") != "bronze":
        raise AssertionError(f"opponent difficulty not forwarded: {opts}")


def test_no_opponent_key_when_homogeneous() -> None:
    runner = BotAutoMockRunner()
    collect_rollouts_v2.collect_rollouts_v2(
        runner, episodes=1, seed=0, max_steps=10, bot_auto=True
    )
    opts = runner.reset_calls[0]["extra_options"]
    if "opponent_bot_difficulty" in opts:
        raise AssertionError(f"homogeneous must not set opponent key: {opts}")


def main() -> int:
    tests = [
        test_cli_exposes_existing_bot,
        test_random_and_safe_unchanged,
        test_bot_auto_records_applied_action,
        test_bot_auto_rejects_illegal_applied_action,
        test_extra_options_force_hard,
        test_extra_options_explicit_difficulty,
        test_extra_options_opponent_difficulty,
        test_no_opponent_key_when_homogeneous,
    ]
    print("=== test_existing_bot_v2 ===")
    for test in tests:
        test()
        print(f"  [OK] {test.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
