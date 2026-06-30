"""Tests for the AgentInterface v2 action-trace logger.

Run from rl/:
    uv run python test_action_trace_v2.py
"""

from __future__ import annotations

import gzip
import json
from pathlib import Path
import random
import tempfile
from typing import Any

import torch

import action_trace_v2
import encoding_v2
import infer_r2d2_v2
import model_r2d2_v2
import policy_r2d2_v2


# --------------------------------------------------------------------------- #
# Helpers: deterministic model output + legal action set.
# --------------------------------------------------------------------------- #
def _output(
    action_q: dict[str, float],
    *,
    match_slot: dict[int, float] | None = None,
    hidden: float = 1.0,
) -> model_r2d2_v2.R2D2OutputV2:
    n = len(encoding_v2.ACTION_TYPES)
    a = torch.zeros(1, 1, n)
    for name, value in action_q.items():
        a[0, 0, encoding_v2.ACTION_TYPES.index(name)] = value
    ms = torch.zeros(1, 1, encoding_v2.MAX_SLOTS)
    for slot, value in (match_slot or {}).items():
        ms[0, 0, slot] = value
    tslot = torch.zeros(1, 1, encoding_v2.MAX_PLAYERS, encoding_v2.MAX_SLOTS)
    return model_r2d2_v2.R2D2OutputV2(
        action_type_q=a,
        own_slot_q=torch.zeros(1, 1, encoding_v2.MAX_SLOTS),
        match_slot_q=ms,
        target_player_q=torch.zeros(1, 1, encoding_v2.MAX_PLAYERS),
        target_slot_q=tslot,
        jack_player_a_q=torch.zeros(1, 1, encoding_v2.MAX_PLAYERS),
        jack_slot_a_q=tslot.clone(),
        jack_player_b_q=torch.zeros(1, 1, encoding_v2.MAX_PLAYERS),
        jack_slot_b_q=tslot.clone(),
        legacy_q=None,
        hidden_state=torch.full((1, 1, 8), hidden),
        burn_in_mask=torch.zeros(1, 1, dtype=torch.bool),
        train_mask=torch.ones(1, 1, dtype=torch.bool),
        padding_mask=torch.zeros(1, 1, dtype=torch.bool),
    )


def _legal(*types: tuple[str, dict[str, Any]]) -> dict[str, Any]:
    actions = []
    for index, (action_type, extra) in enumerate(types):
        av = {"action_type": action_type, **extra}
        actions.append(
            {"action_v2": av, "legacy_action_id": index, "legacy_kind": action_type}
        )
    return {
        "actions": actions,
        "available_action_types": [t for t, _ in types],
        "masks": {},
    }


def _obs() -> dict[str, Any]:
    return {
        "micro_phase": "dutchOrDraw",
        "obs": {"phase": "playing", "micro_phase": "dutchOrDraw", "hand_size": 4,
                "opponents": [{"hand_size": 5}], "deck_size": 20, "discard_size": 8,
                "dutch_called": False, "current_player": "p0"},
        "recent_events": [],
        "slot_stability": {"players": []},
        "legal_private_memory": {"own_hand": {"slots": []}, "opponents": []},
    }


def _scene() -> tuple[Any, Any, dict[str, Any], dict[str, Any]]:
    # pass_tick=1.0, draw=2.0 (greedy winner), call_dutch=0.5, match(slot0)=0.1+0.3=0.4
    output = _output(
        {"pass_tick": 1.0, "draw": 2.0, "call_dutch": 0.5, "match": 0.1},
        match_slot={0: 0.3},
    )
    legal = _legal(
        ("pass_tick", {}),
        ("draw", {}),
        ("call_dutch", {}),
        ("match", {"slot": 0}),
    )
    selected = policy_r2d2_v2.select_action_from_batch_output(
        output, batch_index=0, time_index=0, legal_action_v2=legal, epsilon=0.0
    )
    return output, selected, legal, _obs()


def _record(level: str, *, top_k: int | None = None) -> dict[str, Any]:
    output, selected, legal, obs = _scene()
    config = action_trace_v2.ActionTraceConfigV2(
        level=level, out_path=Path("unused"), top_k=top_k
    )
    return action_trace_v2.build_action_trace_record(
        config,
        output=output,
        selected=selected,
        legal_action_v2=legal,
        obs_raw=obs,
        reward=0.0,
        reward_components={"principal": 0.0, "total": 0.0},
        done=False,
        episode_id="ep",
        step_index=3,
        global_step=42,
        epsilon=0.0,
    )


# --------------------------------------------------------------------------- #
# Config validation.
# --------------------------------------------------------------------------- #
def test_trace_requires_out_path_when_enabled() -> None:
    try:
        action_trace_v2.ActionTraceConfigV2(level="selected", out_path=None)
    except ValueError as exc:
        if "action-trace-out" not in str(exc):
            raise AssertionError(f"unexpected error: {exc}") from exc
    else:
        raise AssertionError("enabled trace without out_path did not raise")


def test_none_level_needs_no_path() -> None:
    config = action_trace_v2.ActionTraceConfigV2(level="none")
    if config.enabled:
        raise AssertionError("none level should be disabled")


def test_gzip_auto_detected_from_suffix() -> None:
    config = action_trace_v2.ActionTraceConfigV2(level="selected", out_path=Path("t.jsonl.gz"))
    if not config.gzip_enabled:
        raise AssertionError("gzip should be auto-detected from .gz suffix")


# --------------------------------------------------------------------------- #
# Record content per level.
# --------------------------------------------------------------------------- #
def test_selected_record_fields() -> None:
    rec = _record("selected")
    for key in [
        "trace_level", "episode_id", "step_index", "global_step", "policy_type",
        "epsilon", "selected_action_v2", "selected_legacy_action_id",
        "selected_score", "selected_is_random", "reward", "done", "phase",
        "micro_phase", "legal_action_count",
    ]:
        if key not in rec:
            raise AssertionError(f"selected record missing {key}")
    if "legal_action_scores" in rec:
        raise AssertionError("selected level must not include legal_action_scores")
    if rec["selected_action_v2"] != {"action_type": "draw"}:
        raise AssertionError(f"greedy selected wrong: {rec['selected_action_v2']}")
    if rec["legal_action_count"] != 4:
        raise AssertionError("legal_action_count wrong")
    if rec["reward_components"] != {"principal": 0.0, "total": 0.0}:
        raise AssertionError(f"reward components missing: {rec['reward_components']}")


def test_legal_scores_lists_all_actions() -> None:
    rec = _record("legal_scores")
    scores = rec["legal_action_scores"]
    if len(scores) != 4:
        raise AssertionError(f"expected 4 scored legal actions, got {len(scores)}")
    types = {s["action_type"] for s in scores}
    if types != {"pass_tick", "draw", "call_dutch", "match"}:
        raise AssertionError(f"missing legal actions in scores: {types}")


def test_selected_action_present_in_legal_scores() -> None:
    rec = _record("legal_scores")
    sel = rec["selected_action_v2"]
    if not any(s["action_v2"] == sel for s in rec["legal_action_scores"]):
        raise AssertionError("selected action not present in legal_action_scores")


def test_selected_rank_is_one_for_greedy() -> None:
    rec = _record("legal_scores")
    if rec["selected_rank"] != 1:
        raise AssertionError(f"greedy selected_rank should be 1, got {rec['selected_rank']}")


def test_call_dutch_and_draw_scores_present() -> None:
    rec = _record("legal_scores")
    if abs(rec["call_dutch_score"] - 0.5) > 1e-6:
        raise AssertionError(f"call_dutch_score wrong: {rec['call_dutch_score']}")
    if abs(rec["draw_score"] - 2.0) > 1e-6:
        raise AssertionError(f"draw_score wrong: {rec['draw_score']}")


def test_score_gap_computed() -> None:
    rec = _record("legal_scores")
    # best draw=2.0, second pass_tick=1.0 -> gap 1.0
    if abs(rec["best_score"] - 2.0) > 1e-6 or abs(rec["second_score"] - 1.0) > 1e-6:
        raise AssertionError(f"best/second wrong: {rec['best_score']}/{rec['second_score']}")
    if abs(rec["score_gap"] - 1.0) > 1e-6:
        raise AssertionError(f"score_gap wrong: {rec['score_gap']}")


def test_top_k_limits_listed_actions() -> None:
    rec = _record("legal_scores", top_k=2)
    if len(rec["legal_action_scores"]) != 2:
        raise AssertionError("top_k did not limit listed actions")
    # still ranked by score desc
    if rec["legal_action_scores"][0]["action_type"] != "draw":
        raise AssertionError("top_k list not ranked by score")


def test_trace_scores_match_policy() -> None:
    output, selected, legal, _ = _scene()
    rec = _record("legal_scores")
    for entry in rec["legal_action_scores"]:
        policy_score = policy_r2d2_v2.score_legal_action_v2(
            output, entry["action_v2"], batch_index=0, time_index=0
        )
        if abs(entry["score"] - policy_score) > 1e-9:
            raise AssertionError(
                f"trace score {entry['score']} != policy score {policy_score} for {entry}"
            )
    if abs(rec["selected_score"] - selected.score) > 1e-9:
        raise AssertionError("selected_score in trace != policy selected score")


def test_full_level_adds_summary_and_diagnostics() -> None:
    rec = _record("full")
    if "obs_summary" not in rec or "action_type_q" not in rec or "hidden_state_norm" not in rec:
        raise AssertionError("full level missing diagnostics")
    summary = rec["obs_summary"]
    for key in ["phase", "hand_sizes", "available_action_types", "recent_events",
                "slot_stability", "legal_private_memory"]:
        if key not in summary:
            raise AssertionError(f"obs_summary missing {key}")
    # masked action types appear as None; legal ones as floats.
    atq = rec["action_type_q"]
    if atq["draw"] is None or abs(atq["draw"] - 2.0) > 1e-6:
        raise AssertionError("action_type_q draw value wrong")
    if rec["hidden_state_norm"] <= 0.0:
        raise AssertionError("hidden_state_norm should be positive")


# --------------------------------------------------------------------------- #
# Writer: anti-leak, gzip, jsonl.
# --------------------------------------------------------------------------- #
def test_writer_rejects_forbidden_keys() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "t.jsonl"
        with action_trace_v2.ActionTraceWriterV2(out, gzip_enabled=False) as writer:
            try:
                writer.write({"selected_action_v2": {"action_type": "draw"},
                              "leak": {"true_score": {"p1": 5}}})
            except ValueError as exc:
                if "forbidden" not in str(exc) or "true_score" not in str(exc):
                    raise AssertionError(f"unexpected error: {exc}") from exc
            else:
                raise AssertionError("forbidden key was not rejected")


def test_full_record_with_leaky_obs_is_rejected() -> None:
    # The obs_summary copies legal_private_memory wholesale. If a forbidden key
    # ever appears nested inside a copied block, the writer's scan must catch it
    # (defense in depth on top of the obs_summary allowlist).
    output, selected, legal, obs = _scene()
    obs = {**obs, "legal_private_memory": {"own_hand": {"slots": []},
                                           "opponent_hand": [{"value": "R"}]}}
    config = action_trace_v2.ActionTraceConfigV2(level="full", out_path=Path("x"))
    rec = action_trace_v2.build_action_trace_record(
        config, output=output, selected=selected, legal_action_v2=legal,
        obs_raw=obs, reward=0.0, done=False, episode_id="e", step_index=0,
        global_step=0, epsilon=0.0,
    )
    with tempfile.TemporaryDirectory() as tmp:
        with action_trace_v2.ActionTraceWriterV2(Path(tmp) / "t.jsonl", gzip_enabled=False) as w:
            try:
                w.write(rec)
            except ValueError as exc:
                if "opponent_hand" not in str(exc):
                    raise AssertionError(f"unexpected error: {exc}") from exc
            else:
                raise AssertionError("leaky full record was written silently")


def test_gzip_roundtrip_jsonl() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "trace.jsonl.gz"
        with action_trace_v2.ActionTraceWriterV2(out, gzip_enabled=True) as writer:
            writer.write(_record("legal_scores"))
            writer.write(_record("legal_scores"))
        if not out.exists():
            raise AssertionError("gzip trace file not created")
        with gzip.open(out, "rt", encoding="utf-8") as fh:
            lines = [json.loads(line) for line in fh if line.strip()]
        if len(lines) != 2:
            raise AssertionError(f"expected 2 gzip lines, got {len(lines)}")
        if "legal_action_scores" not in lines[0]:
            raise AssertionError("gzip line missing legal_action_scores")


# --------------------------------------------------------------------------- #
# Inference integration (MockRunner).
# --------------------------------------------------------------------------- #
def _runner_obs(step: int, *, done: bool = False) -> dict[str, Any]:
    o = _obs()
    return {
        "type": "observation",
        "done": done,
        "action_mask": {"pass_tick": True},
        **o,
        "legal_action_v2": _legal(("pass_tick", {}), ("draw", {}), ("call_dutch", {})),
    }


class MockRunner:
    def __init__(self, *, terminal_step: int = 3) -> None:
        self._step = 0
        self._terminal = terminal_step

    def reset(self, seed: int, episode_id: str | None = None,
              extra_options: dict[str, Any] | None = None) -> dict[str, Any]:
        self._step = 0
        return _runner_obs(0)

    def step(self, action_msg: dict[str, Any]) -> dict[str, Any]:
        self._step += 1
        done = self._step >= self._terminal
        return {**_runner_obs(self._step, done=done),
                "reward": 1.0 if done else 0.0, "rewards": {"principal": 1.0 if done else 0.0}}


class TraceModel:
    def __call__(self, batch: Any, hidden_state: Any = None, *, apply_masks: bool = True) -> Any:
        del apply_masks, hidden_state
        return _output({"pass_tick": 1.0, "draw": 2.0, "call_dutch": 0.5})


def test_none_level_creates_no_file() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "should_not_exist.jsonl"
        config = action_trace_v2.ActionTraceConfigV2(level="none")
        with action_trace_v2.maybe_open_writer(config) as writer:
            infer_r2d2_v2.infer_episode_v2(
                MockRunner(terminal_step=2), TraceModel(), seed=0, episode_id="e",
                epsilon=0.0, rng=random.Random(0), max_steps=5,
                trace_writer=writer, trace_config=config,
            )
        if out.exists():
            raise AssertionError("none level created a trace file")


def test_selected_writes_one_line_per_decision() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "trace.jsonl"
        config = action_trace_v2.ActionTraceConfigV2(level="selected", out_path=out)
        with action_trace_v2.maybe_open_writer(config) as writer:
            record = infer_r2d2_v2.infer_episode_v2(
                MockRunner(terminal_step=3), TraceModel(), seed=0, episode_id="ep-trace",
                epsilon=0.0, rng=random.Random(0), max_steps=5,
                trace_writer=writer, trace_config=config,
            )
        lines = out.read_text(encoding="utf-8").strip().splitlines()
        rows = [json.loads(line) for line in lines]
    if len(rows) != len(record.transitions):
        raise AssertionError(f"trace lines {len(rows)} != decisions {len(record.transitions)}")
    if rows[0]["episode_id"] != "ep-trace" or rows[0]["global_step"] != 0:
        raise AssertionError("trace record episode/global_step wrong")
    if rows[-1]["global_step"] != len(rows) - 1:
        raise AssertionError("global_step not advancing per decision")


def test_legal_scores_through_infer_has_call_dutch_score() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "trace.jsonl"
        config = action_trace_v2.ActionTraceConfigV2(level="legal_scores", out_path=out)
        with action_trace_v2.maybe_open_writer(config) as writer:
            infer_r2d2_v2.infer_episode_v2(
                MockRunner(terminal_step=2), TraceModel(), seed=0, episode_id="e",
                epsilon=0.0, rng=random.Random(0), max_steps=5,
                trace_writer=writer, trace_config=config,
            )
        rows = [json.loads(l) for l in out.read_text(encoding="utf-8").strip().splitlines()]
    if not rows or "legal_action_scores" not in rows[0]:
        raise AssertionError("legal_scores trace missing legal_action_scores")
    if abs(rows[0]["call_dutch_score"] - 0.5) > 1e-6:
        raise AssertionError("call_dutch_score not captured through infer")


def test_import_creates_no_file() -> None:
    # Importing the module and building a none-config must not touch the FS.
    with tempfile.TemporaryDirectory() as tmp:
        before = set(Path(tmp).iterdir())
        action_trace_v2.ActionTraceConfigV2(level="none")
        with action_trace_v2.maybe_open_writer(action_trace_v2.ActionTraceConfigV2(level="none")):
            pass
        if set(Path(tmp).iterdir()) != before:
            raise AssertionError("trace module created a file with no active trace")


def main() -> int:
    tests = [
        test_trace_requires_out_path_when_enabled,
        test_none_level_needs_no_path,
        test_gzip_auto_detected_from_suffix,
        test_selected_record_fields,
        test_legal_scores_lists_all_actions,
        test_selected_action_present_in_legal_scores,
        test_selected_rank_is_one_for_greedy,
        test_call_dutch_and_draw_scores_present,
        test_score_gap_computed,
        test_top_k_limits_listed_actions,
        test_trace_scores_match_policy,
        test_full_level_adds_summary_and_diagnostics,
        test_writer_rejects_forbidden_keys,
        test_full_record_with_leaky_obs_is_rejected,
        test_gzip_roundtrip_jsonl,
        test_none_level_creates_no_file,
        test_selected_writes_one_line_per_decision,
        test_legal_scores_through_infer_has_call_dutch_score,
        test_import_creates_no_file,
    ]
    print("=== test_action_trace_v2 ===")
    for test in tests:
        test()
        print(f"  [OK] {test.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
