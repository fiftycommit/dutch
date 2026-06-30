"""Tests for the AgentInterface v2 action-trace analyzer.

Run from rl/:
    uv run python test_analyze_action_trace_v2.py
"""

from __future__ import annotations

import gzip
import json
from pathlib import Path
import tempfile
from typing import Any

import analyze_action_trace_v2 as ana


def _row(
    *,
    episode: str,
    step: int,
    selected: str,
    legal: list[tuple[str, float]],
    phase: str = "reaction",
    reward: float = 0.0,
    done: bool = False,
) -> dict[str, Any]:
    scores = [
        {"action_type": t, "action_v2": {"action_type": t}, "score": s, "legal_index": i}
        for i, (t, s) in enumerate(legal)
    ]
    ranked = sorted(scores, key=lambda x: x["score"], reverse=True)
    best = ranked[0]["score"]
    second = ranked[1]["score"] if len(ranked) > 1 else None
    sel_score = next(x["score"] for x in scores if x["action_type"] == selected)
    return {
        "episode_id": episode,
        "step_index": step,
        "global_step": step,
        "phase": phase,
        "micro_phase": "reaction",
        "selected_action_v2": {"action_type": selected},
        "selected_score": sel_score,
        "legal_action_scores": ranked,
        "legal_action_count": len(legal),
        "best_score": best,
        "second_score": second,
        "score_gap": None if second is None else best - second,
        "reward": reward,
        "done": done,
    }


def _sample_rows() -> list[dict[str, Any]]:
    # Episode A: three consecutive match wins (over pass_tick), then a pass_tick.
    rows = [
        _row(episode="A", step=0, selected="match", legal=[("match", 1.0), ("pass_tick", 0.9)]),
        _row(episode="A", step=1, selected="match", legal=[("match", 1.0), ("pass_tick", 0.5)]),
        _row(episode="A", step=2, selected="match", legal=[("match", 1.0), ("pass_tick", 0.99)]),
        _row(episode="A", step=3, selected="pass_tick", legal=[("pass_tick", 2.0), ("match", 1.0)]),
        # call_dutch legal but match chosen (losing dutch).
        _row(episode="A", step=4, selected="match",
             legal=[("match", 1.5), ("call_dutch", 0.2), ("pass_tick", 0.1)], phase="playing"),
    ]
    return rows


def _write(rows: list[dict[str, Any]], path: Path, *, gz: bool) -> None:
    opener = gzip.open if gz else open
    with opener(path, "wt", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row) + "\n")


def test_loads_plain_jsonl() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "t.jsonl"
        _write(_sample_rows(), path, gz=False)
        rows = ana.load_trace(path)
    if len(rows) != 5:
        raise AssertionError(f"plain jsonl row count wrong: {len(rows)}")


def test_loads_gzipped_jsonl() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "t.jsonl.gz"
        _write(_sample_rows(), path, gz=True)
        rows = ana.load_trace(path)
    if len(rows) != 5:
        raise AssertionError(f"gzip jsonl row count wrong: {len(rows)}")


def test_counts_actions_and_phases() -> None:
    summary = ana.analyze(_sample_rows(), top_k=10)
    if summary["selected_action_distribution"] != {"match": 4, "pass_tick": 1}:
        raise AssertionError(f"bad action distribution: {summary['selected_action_distribution']}")
    if summary["phase_distribution"] != {"reaction": 4, "playing": 1}:
        raise AssertionError(f"bad phase distribution: {summary['phase_distribution']}")


def test_match_vs_pass_tick_competition() -> None:
    summary = ana.analyze(_sample_rows(), top_k=10)
    # All 5 rows have both match and pass_tick legal.
    if summary["both_match_and_pass_legal"] != 5:
        raise AssertionError("both-legal count wrong")
    if summary["both_legal_match_wins"] != 4 or summary["both_legal_pass_wins"] != 1:
        raise AssertionError("match/pass win counts wrong")
    if summary["mean_match_score_when_both_legal"] is None:
        raise AssertionError("mean match score missing")


def test_detects_consecutive_match_chains() -> None:
    summary = ana.analyze(_sample_rows(), top_k=10)
    # Episode A: matches at steps 0,1,2 (chain of 3), then match at step 4 (chain of 1).
    if summary["match_chain_max_length"] != 3:
        raise AssertionError(f"chain max length wrong: {summary['match_chain_max_length']}")
    if summary["match_chain_length_distribution"] != {3: 1, 1: 1}:
        raise AssertionError(f"chain distribution wrong: {summary['match_chain_length_distribution']}")


def test_detects_call_dutch_legal_but_losing() -> None:
    summary = ana.analyze(_sample_rows(), top_k=10)
    if summary["call_dutch_legal_count"] != 1:
        raise AssertionError("call_dutch legal count wrong")
    if summary["call_dutch_legal_but_lost_count"] != 1:
        raise AssertionError("call_dutch losing count wrong")
    if summary["call_dutch_chosen_count"] != 0:
        raise AssertionError("call_dutch chosen count wrong")
    examples = summary["call_dutch_losing_examples"]
    if not examples or examples[0]["selected_action_type"] != "match":
        raise AssertionError("losing dutch example wrong")


def test_small_margin_match_wins_sorted() -> None:
    summary = ana.analyze(_sample_rows(), top_k=10)
    margins = [item["score_gap"] for item in summary["small_margin_match_wins"]]
    if margins != sorted(margins):
        raise AssertionError("small-margin match wins not sorted ascending by gap")
    # The tightest match win is step 2 (gap 0.01).
    if summary["small_margin_match_wins"][0]["step_index"] != 2:
        raise AssertionError("tightest match win not identified")


def test_empty_trace_raises() -> None:
    try:
        ana.analyze([], top_k=5)
    except ValueError:
        pass
    else:
        raise AssertionError("empty trace did not raise")


def test_import_reads_no_file() -> None:
    import importlib

    module = importlib.import_module("analyze_action_trace_v2")
    if hasattr(module, "RUN_STARTED"):
        raise AssertionError("module appears to read a file at import")
    if not hasattr(module, "main"):
        raise AssertionError("module missing guarded main")


def main() -> int:
    tests = [
        test_loads_plain_jsonl,
        test_loads_gzipped_jsonl,
        test_counts_actions_and_phases,
        test_match_vs_pass_tick_competition,
        test_detects_consecutive_match_chains,
        test_detects_call_dutch_legal_but_losing,
        test_small_margin_match_wins_sorted,
        test_empty_trace_raises,
        test_import_reads_no_file,
    ]
    print("=== test_analyze_action_trace_v2 ===")
    for test in tests:
        test()
        print(f"  [OK] {test.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
