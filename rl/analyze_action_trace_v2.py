"""Offline analysis of AgentInterface v2 action traces.

Reads a JSONL (or .jsonl.gz) action trace produced by ``action_trace_v2`` and
summarizes decision behavior: action/phase distributions, match-vs-pass_tick
competition, score gaps, consecutive ``match`` chains, and concrete examples of
small-margin ``match`` wins and losing-but-legal ``call_dutch`` decisions.

This is a read-only diagnostic. It trains nothing, runs no game, and never
reads a file at import time (only ``main`` / explicit calls touch the FS).
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import gzip
import json
from pathlib import Path
from statistics import mean
from typing import Any, Iterable


def load_trace(path: str | Path) -> list[dict[str, Any]]:
    """Load a JSONL or gzipped-JSONL action trace into a list of records."""

    src = Path(path)
    opener = gzip.open if src.suffix == ".gz" else open
    rows: list[dict[str, Any]] = []
    with opener(src, "rt", encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise ValueError(f"{src}:{line_no}: invalid JSONL") from exc
    return rows


def _selected_type(row: dict[str, Any]) -> Any:
    action = row.get("selected_action_v2") or {}
    return action.get("action_type")


def _legal_types(row: dict[str, Any]) -> list[str]:
    return [s.get("action_type") for s in (row.get("legal_action_scores") or [])]


def _legal_score(row: dict[str, Any], action_type: str) -> float | None:
    best: float | None = None
    for entry in row.get("legal_action_scores") or []:
        if entry.get("action_type") == action_type:
            score = float(entry["score"])
            if best is None or score > best:
                best = score
    return best


def _has_scores(rows: Iterable[dict[str, Any]]) -> bool:
    return any("legal_action_scores" in row for row in rows)


def analyze(rows: list[dict[str, Any]], *, top_k: int = 20) -> dict[str, Any]:
    """Compute the diagnostic summary from trace records."""

    if not rows:
        raise ValueError("empty trace: nothing to analyze")

    scores_present = _has_scores(rows)
    selected_dist = Counter(_selected_type(r) for r in rows)
    phase_dist = Counter(r.get("phase") for r in rows)
    micro_dist = Counter(r.get("micro_phase") for r in rows)

    # Legal-action counts and per-phase legal-action averages.
    legal_count_by_phase: dict[Any, list[int]] = defaultdict(list)
    legal_type_occurrences: Counter = Counter()
    score_samples_by_type: dict[str, list[float]] = defaultdict(list)
    gap_by_phase: dict[Any, list[float]] = defaultdict(list)
    for row in rows:
        legal = row.get("legal_action_scores")
        if legal is not None:
            legal_count_by_phase[row.get("phase")].append(len(legal))
            for entry in legal:
                legal_type_occurrences[entry.get("action_type")] += 1
                score_samples_by_type[entry.get("action_type")].append(float(entry["score"]))
        elif "legal_action_count" in row:
            legal_count_by_phase[row.get("phase")].append(int(row["legal_action_count"]))
        gap = row.get("score_gap")
        if gap is not None:
            gap_by_phase[row.get("phase")].append(float(gap))

    # match vs pass_tick when both legal.
    both_legal = [
        r for r in rows
        if "match" in _legal_types(r) and "pass_tick" in _legal_types(r)
    ]
    match_wins = sum(1 for r in both_legal if _selected_type(r) == "match")
    pass_wins = sum(1 for r in both_legal if _selected_type(r) == "pass_tick")
    match_scores = [s for r in both_legal if (s := _legal_score(r, "match")) is not None]
    pass_scores = [s for r in both_legal if (s := _legal_score(r, "pass_tick")) is not None]

    # call_dutch.
    dutch_legal = [r for r in rows if _legal_score(r, "call_dutch") is not None]
    dutch_chosen = [r for r in dutch_legal if _selected_type(r) == "call_dutch"]
    dutch_losing = [r for r in dutch_legal if _selected_type(r) != "call_dutch"]

    # Consecutive match chains, per episode in step order.
    chains = _match_chains(rows)

    # Progress sanity: step advances, rewards, done.
    reward_nonzero = sum(1 for r in rows if float(r.get("reward", 0.0)) != 0.0)
    done_true = sum(1 for r in rows if bool(r.get("done")))
    match_rows = [r for r in rows if _selected_type(r) == "match"]
    match_reward_nonzero = sum(1 for r in match_rows if float(r.get("reward", 0.0)) != 0.0)

    summary: dict[str, Any] = {
        "rows": len(rows),
        "episodes": sorted({r.get("episode_id") for r in rows}),
        "scores_present": scores_present,
        "selected_action_distribution": dict(selected_dist),
        "phase_distribution": dict(phase_dist),
        "micro_phase_distribution": dict(micro_dist),
        "legal_action_type_occurrences": dict(legal_type_occurrences),
        "avg_legal_actions_by_phase": {
            str(phase): round(mean(counts), 3) for phase, counts in legal_count_by_phase.items()
        },
        "mean_score_by_action_type": {
            atype: round(mean(vals), 5) for atype, vals in score_samples_by_type.items()
        },
        "mean_score_gap_by_phase": {
            str(phase): round(mean(vals), 5) for phase, vals in gap_by_phase.items() if vals
        },
        "match_legal_count": sum(1 for r in rows if "match" in _legal_types(r)),
        "pass_tick_legal_count": sum(1 for r in rows if "pass_tick" in _legal_types(r)),
        "both_match_and_pass_legal": len(both_legal),
        "both_legal_match_wins": match_wins,
        "both_legal_pass_wins": pass_wins,
        "mean_match_score_when_both_legal": round(mean(match_scores), 5) if match_scores else None,
        "mean_pass_tick_score_when_both_legal": round(mean(pass_scores), 5) if pass_scores else None,
        "call_dutch_legal_count": len(dutch_legal),
        "call_dutch_chosen_count": len(dutch_chosen),
        "call_dutch_legal_but_lost_count": len(dutch_losing),
        "mean_call_dutch_score_when_legal": (
            round(mean([_legal_score(r, "call_dutch") for r in dutch_legal]), 5)
            if dutch_legal else None
        ),
        "match_chain_max_length": chains["max_length"],
        "match_chain_length_distribution": chains["length_distribution"],
        "reward_nonzero_decisions": reward_nonzero,
        "match_decisions_with_nonzero_reward": match_reward_nonzero,
        "done_true_decisions": done_true,
        "small_margin_match_wins": _small_margin_match_wins(rows, top_k=top_k),
        "call_dutch_losing_examples": _dutch_losing_examples(dutch_losing, top_k=top_k),
    }
    return summary


def _match_chains(rows: list[dict[str, Any]]) -> dict[str, Any]:
    by_episode: dict[Any, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        by_episode[row.get("episode_id")].append(row)
    lengths: list[int] = []
    for episode_rows in by_episode.values():
        ordered = sorted(episode_rows, key=lambda r: r.get("step_index", 0))
        run = 0
        for row in ordered:
            if _selected_type(row) == "match":
                run += 1
            else:
                if run > 0:
                    lengths.append(run)
                run = 0
        if run > 0:
            lengths.append(run)
    return {
        "max_length": max(lengths) if lengths else 0,
        "length_distribution": dict(Counter(lengths)),
    }


def _small_margin_match_wins(rows: list[dict[str, Any]], *, top_k: int) -> list[dict[str, Any]]:
    candidates = [
        r for r in rows
        if _selected_type(r) == "match" and r.get("score_gap") is not None
    ]
    candidates.sort(key=lambda r: float(r["score_gap"]))
    out = []
    for row in candidates[:top_k]:
        out.append({
            "episode_id": row.get("episode_id"),
            "step_index": row.get("step_index"),
            "phase": row.get("phase"),
            "micro_phase": row.get("micro_phase"),
            "score_gap": round(float(row["score_gap"]), 6),
            "selected_score": round(float(row.get("selected_score", 0.0)), 6),
            "second_score": (
                None if row.get("second_score") is None else round(float(row["second_score"]), 6)
            ),
            "pass_tick_score": (
                None if _legal_score(row, "pass_tick") is None
                else round(_legal_score(row, "pass_tick"), 6)
            ),
            "legal_action_count": row.get("legal_action_count"),
        })
    return out


def _dutch_losing_examples(rows: list[dict[str, Any]], *, top_k: int) -> list[dict[str, Any]]:
    out = []
    for row in rows[:top_k]:
        dutch = _legal_score(row, "call_dutch")
        out.append({
            "episode_id": row.get("episode_id"),
            "step_index": row.get("step_index"),
            "phase": row.get("phase"),
            "selected_action_type": _selected_type(row),
            "selected_score": round(float(row.get("selected_score", 0.0)), 6),
            "call_dutch_score": None if dutch is None else round(dutch, 6),
            "selected_minus_dutch": (
                None if dutch is None else round(float(row.get("selected_score", 0.0)) - dutch, 6)
            ),
        })
    return out


def format_summary(summary: dict[str, Any]) -> str:
    lines = ["=== action trace analysis ==="]
    skip = {"small_margin_match_wins", "call_dutch_losing_examples"}
    for key, value in summary.items():
        if key in skip:
            continue
        lines.append(f"{key}: {value}")
    lines.append(f"small_margin_match_wins (top {len(summary['small_margin_match_wins'])}):")
    for item in summary["small_margin_match_wins"]:
        lines.append(f"  {item}")
    lines.append(f"call_dutch_losing_examples ({len(summary['call_dutch_losing_examples'])}):")
    for item in summary["call_dutch_losing_examples"]:
        lines.append(f"  {item}")
    return "\n".join(lines)


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trace", required=True)
    parser.add_argument("--top-k", type=int, default=20)
    parser.add_argument("--output-json", default=None)
    parser.add_argument("--print-summary", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)
    rows = load_trace(args.trace)
    summary = analyze(rows, top_k=args.top_k)
    if args.output_json:
        out = Path(args.output_json)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(summary, indent=2, sort_keys=True), encoding="utf-8")
    if args.print_summary or not args.output_json:
        print(format_summary(summary))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
