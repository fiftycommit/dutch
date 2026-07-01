"""Split a v2 rollout JSONL dataset into RAM-sized shards, episode-complete.

Motivation: ``train_r2d2_v2.py`` loads a whole dataset into RAM. The large 6p
curriculum files (86k / 127k transitions) risk OOM on a 15 GB machine. Sharding a
big file into episode-complete shards that each fit in RAM lets us train the
curriculum sequentially with ``--resume-from`` between shards, without a streaming
replay loader (future work).

Guarantees:
- an episode (all transitions sharing ``episode_id``) is NEVER split across shards;
- concatenating the shards reproduces the source exactly (line-for-line);
- transition/episode counts are preserved (asserted);
- a JSON manifest records per-shard and total stats.

This is a pure file utility: no runner, no training, no reward logic. Outputs go
wherever the caller points (intended: ``/tmp``), never the repo.
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
from typing import Any


def _line_stats(line: str) -> tuple[str, str | None, float, bool, bool]:
    """Return (episode_id, action_type, reward, is_false_match, is_succ_match)."""
    t = json.loads(line)
    ep = t.get("episode_id")
    if not isinstance(ep, str):
        raise ValueError(f"transition without string episode_id: {line[:120]!r}")
    action = t.get("action_v2") or {}
    at = action.get("action_type") if isinstance(action, dict) else None
    reward = t.get("reward", 0.0)
    reward = float(reward) if isinstance(reward, (int, float)) else 0.0
    rc = t.get("reward_components") or {}
    is_false = isinstance(rc, dict) and rc.get("false_match_penalty", 0) not in (0, 0.0)
    is_succ = at == "match" and isinstance(rc, dict) and rc.get(
        "successful_match_reward", 0
    ) not in (0, 0.0)
    return ep, at, reward, is_false, is_succ


class _ShardWriter:
    def __init__(self, out_dir: Path, base: str) -> None:
        self.out_dir = out_dir
        self.base = base
        self.idx = 0
        self.fh = None
        self.tr = 0
        self.eps = 0
        self.reward = 0.0
        self.acts: Counter[str | None] = Counter()
        self.false_m = 0
        self.succ_m = 0
        self.shards: list[dict[str, Any]] = []
        self._path: Path | None = None

    def _open_new(self) -> None:
        self._close()
        self.idx += 1
        self._path = self.out_dir / f"{self.base}_shard_{self.idx:03d}.jsonl"
        self.fh = self._path.open("w", encoding="utf-8")
        self.tr = self.eps = 0
        self.reward = 0.0
        self.acts = Counter()
        self.false_m = self.succ_m = 0

    def _close(self) -> None:
        if self.fh is not None:
            self.fh.close()
            self.shards.append({
                "shard": self._path.name,
                "episodes": self.eps,
                "transitions": self.tr,
                "reward_sum": round(self.reward, 6),
                "false_match": self.false_m,
                "successful_match": self.succ_m,
                "action_counts": {str(k): v for k, v in self.acts.most_common()},
            })
            self.fh = None

    def write_episode(self, lines: list[str], stats: list[tuple], max_tr: int) -> None:
        if self.fh is None or (self.tr > 0 and self.tr + len(lines) > max_tr):
            self._open_new()
        for line in lines:
            self.fh.write(line)
        self.tr += len(lines)
        self.eps += 1
        for _ep, at, reward, is_false, is_succ in stats:
            self.reward += reward
            self.acts[at] += 1
            if is_false:
                self.false_m += 1
            if is_succ:
                self.succ_m += 1

    def finish(self) -> None:
        self._close()


def shard_dataset(
    input_path: str | Path,
    out_dir: str | Path,
    *,
    max_transitions: int,
    manifest_path: str | Path | None = None,
) -> dict[str, Any]:
    input_path = Path(input_path)
    out_dir = Path(out_dir)
    if not input_path.exists() or not input_path.is_file():
        raise FileNotFoundError(f"input dataset not found: {input_path}")
    if max_transitions <= 0:
        raise ValueError("max_transitions must be positive")
    out_dir.mkdir(parents=True, exist_ok=True)
    base = input_path.stem

    writer = _ShardWriter(out_dir, base)
    total_tr = 0
    total_eps = 0
    total_reward = 0.0
    total_acts: Counter[str | None] = Counter()

    cur_ep: str | None = None
    ep_lines: list[str] = []
    ep_stats: list[tuple] = []

    def flush() -> None:
        nonlocal total_eps
        if not ep_lines:
            return
        # Un épisode entier ne doit jamais tenir sur plusieurs shards, mais il peut
        # à lui seul dépasser max_transitions : on l'écrit alors dans son propre
        # shard (jamais coupé). write_episode gère la rotation.
        writer.write_episode(ep_lines, ep_stats, max_transitions)
        total_eps += 1

    with input_path.open(encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            ep, at, reward, is_false, is_succ = _line_stats(line)
            total_tr += 1
            total_reward += reward
            total_acts[at] += 1
            if ep != cur_ep:
                flush()
                ep_lines = []
                ep_stats = []
                cur_ep = ep
            ep_lines.append(line)
            ep_stats.append((ep, at, reward, is_false, is_succ))
        flush()
    writer.finish()

    # Vérif conservation.
    shard_tr = sum(s["transitions"] for s in writer.shards)
    shard_eps = sum(s["episodes"] for s in writer.shards)
    if shard_tr != total_tr:
        raise AssertionError(f"transition mismatch: shards={shard_tr} src={total_tr}")
    if shard_eps != total_eps:
        raise AssertionError(f"episode mismatch: shards={shard_eps} src={total_eps}")

    manifest = {
        "source_file": input_path.name,
        "base": base,
        "max_transitions": max_transitions,
        "total_episodes": total_eps,
        "total_transitions": total_tr,
        "total_reward_sum": round(total_reward, 6),
        "total_action_counts": {str(k): v for k, v in total_acts.most_common()},
        "num_shards": len(writer.shards),
        "shards": writer.shards,
        "sum_check_ok": True,
    }
    mpath = Path(manifest_path) if manifest_path else out_dir / f"{base}_manifest.json"
    mpath.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    manifest["manifest_path"] = str(mpath)
    return manifest


def build_arg_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input", required=True, help="v2 rollout JSONL to shard")
    p.add_argument("--out-dir", required=True, help="output dir (intended: /tmp)")
    p.add_argument("--max-transitions", type=int, default=45000,
                   help="max transitions per shard (episodes never split)")
    p.add_argument("--manifest", default=None)
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)
    m = shard_dataset(
        args.input, args.out_dir,
        max_transitions=args.max_transitions, manifest_path=args.manifest,
    )
    print(
        f"shard_dataset_v2: {m['source_file']} -> {m['num_shards']} shards "
        f"(ep={m['total_episodes']} tr={m['total_transitions']}) "
        f"manifest={m['manifest_path']}"
    )
    for s in m["shards"]:
        print(f"  {s['shard']}: ep={s['episodes']} tr={s['transitions']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
