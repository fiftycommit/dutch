"""Tests for shard_dataset_v2 (episode-complete sharding + manifest).

Run from rl/:
    uv run python test_shard_dataset_v2.py
"""

from __future__ import annotations

import json
import tempfile
from pathlib import Path

import shard_dataset_v2


def _write_dataset(path: Path, ep_lengths: list[int]) -> tuple[int, int]:
    """Write a synthetic v2-ish JSONL. Returns (total_eps, total_tr)."""
    total_tr = 0
    with path.open("w", encoding="utf-8") as f:
        for k, n in enumerate(ep_lengths):
            for i in range(n):
                t = {
                    "episode_id": f"ep{k}",
                    "step_index": i,
                    "action_v2": {"action_type": "draw" if i % 2 else "match"},
                    "reward": 0.5 if i == n - 1 else 0.0,
                    "reward_components": {
                        "false_match_penalty": -0.7 if (k == 1 and i == 0) else 0.0,
                        "successful_match_reward": 0.5 if i % 2 == 0 else 0.0,
                    },
                    "done": i == n - 1,
                }
                f.write(json.dumps(t) + "\n")
                total_tr += 1
    return len(ep_lengths), total_tr


def _shard_episode_ids(shard_path: Path) -> set[str]:
    ids = set()
    for line in shard_path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            ids.add(json.loads(line)["episode_id"])
    return ids


def test_never_splits_an_episode() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "src.jsonl"
        out = Path(tmp) / "shards"
        _write_dataset(src, [5, 8, 3, 7, 4, 6, 9, 2])
        m = shard_dataset_v2.shard_dataset(src, out, max_transitions=10)
        seen: set[str] = set()
        for s in m["shards"]:
            ids = _shard_episode_ids(out / s["shard"])
            if seen & ids:
                raise AssertionError(f"episode split across shards: {seen & ids}")
            seen |= ids
        if seen != {f"ep{k}" for k in range(8)}:
            raise AssertionError("not all episodes present across shards")


def test_counts_preserved() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "src.jsonl"
        out = Path(tmp) / "shards"
        eps, tr = _write_dataset(src, [4, 4, 4, 4, 4, 4])
        m = shard_dataset_v2.shard_dataset(src, out, max_transitions=9)
        if m["total_episodes"] != eps or m["total_transitions"] != tr:
            raise AssertionError("total counts wrong")
        if sum(s["transitions"] for s in m["shards"]) != tr:
            raise AssertionError("shard transition sum != source")
        if sum(s["episodes"] for s in m["shards"]) != eps:
            raise AssertionError("shard episode sum != source")


def test_concat_reproduces_source() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "src.jsonl"
        out = Path(tmp) / "shards"
        _write_dataset(src, [3, 6, 5, 2, 7])
        m = shard_dataset_v2.shard_dataset(src, out, max_transitions=8)
        rebuilt = "".join(
            (out / s["shard"]).read_text(encoding="utf-8") for s in m["shards"]
        )
        if rebuilt != src.read_text(encoding="utf-8"):
            raise AssertionError("concatenated shards != source (line drift)")


def test_manifest_correct() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "p3_diff6p.jsonl"
        out = Path(tmp) / "shards"
        _write_dataset(src, [5, 5, 5, 5])
        m = shard_dataset_v2.shard_dataset(src, out, max_transitions=8)
        mf = json.loads(Path(m["manifest_path"]).read_text(encoding="utf-8"))
        if mf["source_file"] != "p3_diff6p.jsonl":
            raise AssertionError("manifest source_file wrong")
        if mf["num_shards"] != len(mf["shards"]):
            raise AssertionError("manifest num_shards mismatch")
        if not mf["sum_check_ok"]:
            raise AssertionError("manifest sum_check not ok")
        # action counts total must equal total transitions
        if sum(mf["total_action_counts"].values()) != mf["total_transitions"]:
            raise AssertionError("action counts != transitions")


def test_big_single_episode_gets_own_shard() -> None:
    # Un épisode plus grand que max_transitions n'est JAMAIS coupé.
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "src.jsonl"
        out = Path(tmp) / "shards"
        _write_dataset(src, [3, 20, 3])  # ep1 = 20 > max 8
        m = shard_dataset_v2.shard_dataset(src, out, max_transitions=8)
        for s in m["shards"]:
            ids = _shard_episode_ids(out / s["shard"])
            if "ep1" in ids and len(ids) == 1 and s["transitions"] != 20:
                raise AssertionError("big episode truncated")
        # ep1 doit être entier dans un seul shard
        holders = [s for s in m["shards"]
                   if "ep1" in _shard_episode_ids(out / s["shard"])]
        if len(holders) != 1 or holders[0]["transitions"] < 20:
            raise AssertionError("big episode split or truncated")


def test_missing_input_raises() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        try:
            shard_dataset_v2.shard_dataset(
                Path(tmp) / "nope.jsonl", Path(tmp) / "out", max_transitions=10
            )
        except FileNotFoundError:
            return
        raise AssertionError("missing input did not raise")


def test_invalid_line_raises() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "bad.jsonl"
        src.write_text('{"no_episode_id": true}\n', encoding="utf-8")
        try:
            shard_dataset_v2.shard_dataset(src, Path(tmp) / "out", max_transitions=10)
        except ValueError:
            return
        raise AssertionError("invalid line (no episode_id) did not raise")


def test_cli_parser() -> None:
    args = shard_dataset_v2.build_arg_parser().parse_args(
        ["--input", "a.jsonl", "--out-dir", "/tmp/x", "--max-transitions", "50000"]
    )
    if args.max_transitions != 50000 or args.input != "a.jsonl":
        raise AssertionError("CLI parse wrong")


def main() -> int:
    tests = [
        test_never_splits_an_episode,
        test_counts_preserved,
        test_concat_reproduces_source,
        test_manifest_correct,
        test_big_single_episode_gets_own_shard,
        test_missing_input_raises,
        test_invalid_line_raises,
        test_cli_parser,
    ]
    print("=== test_shard_dataset_v2 ===")
    for t in tests:
        t()
        print(f"  [OK] {t.__name__}")
    print("=== TOUT VERT ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
