"""Action-level trace logging for AgentInterface v2 inference/evaluation.

This is a diagnostic tool, not part of training. It writes one JSONL line per
agent decision so we can inspect *why* a greedy R2D2 v2 policy behaves the way
it does (e.g. stalling games, never calling Dutch): which action it picked, the
factorized Q score of every legal action, and an optional public/legal state
summary.

Design guarantees:
- scores are produced by ``policy_r2d2_v2.score_legal_actions_v2`` — the exact
  same factorized scorer the policy uses — never a divergent recomputation;
- the writer runs an anti-leak scan on every record and *raises* (never writes
  silently) if a forbidden key appears (true scores, full/opponent hands, deck
  order, hidden kept/penalty/swapped cards, debug labels);
- ``--trace-actions none`` (default) creates no file and adds no scoring cost.

Levels (increasing detail):
- ``none``         : disabled.
- ``selected``     : the chosen action + its score and minimal context.
- ``legal_scores`` : ``selected`` + every legal action's score, rank, gaps,
                     call_dutch/draw scores.
- ``full``         : ``legal_scores`` + a public/legal observation summary,
                     the masked action-type Q vector and the hidden-state norm.
"""

from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass
import gzip
import json
from pathlib import Path
from typing import Any, Iterator

import encoding_v2
import model_r2d2_v2
import policy_r2d2_v2


TRACE_LEVELS = ("none", "selected", "legal_scores", "full")
_SCORE_LEVELS = ("legal_scores", "full")


@dataclass(frozen=True)
class ActionTraceConfigV2:
    level: str = "none"
    out_path: Path | None = None
    gzip: bool = False
    top_k: int | None = None

    def __post_init__(self) -> None:
        if self.level not in TRACE_LEVELS:
            raise ValueError(
                f"trace level must be one of {TRACE_LEVELS}, got {self.level!r}"
            )
        if self.level != "none" and self.out_path is None:
            raise ValueError(
                "--action-trace-out is required when --trace-actions != none"
            )
        if self.top_k is not None and self.top_k <= 0:
            raise ValueError("top_k must be positive or None")

    @property
    def enabled(self) -> bool:
        return self.level != "none"

    @property
    def scores_enabled(self) -> bool:
        return self.level in _SCORE_LEVELS

    @property
    def gzip_enabled(self) -> bool:
        if self.out_path is None:
            return False
        return bool(self.gzip) or str(self.out_path).endswith(".gz")


class ActionTraceWriterV2:
    """JSONL (optionally gzipped) writer with a mandatory anti-leak scan."""

    def __init__(self, out_path: str | Path, *, gzip_enabled: bool) -> None:
        self.out_path = Path(out_path)
        self.gzip_enabled = bool(gzip_enabled)
        self._handle: Any | None = None
        self.count = 0

    def open(self) -> "ActionTraceWriterV2":
        self.out_path.parent.mkdir(parents=True, exist_ok=True)
        if self.gzip_enabled:
            self._handle = gzip.open(self.out_path, "wt", encoding="utf-8")
        else:
            self._handle = self.out_path.open("w", encoding="utf-8")
        return self

    def write(self, record: dict[str, Any]) -> None:
        if self._handle is None:
            raise RuntimeError("ActionTraceWriterV2.write called before open()")
        forbidden = _find_forbidden_keys(record)
        if forbidden:
            raise ValueError(
                f"action trace record contains forbidden keys: {sorted(forbidden)}"
            )
        self._handle.write(json.dumps(record, sort_keys=True) + "\n")
        self.count += 1

    def close(self) -> None:
        if self._handle is not None:
            self._handle.close()
            self._handle = None

    def __enter__(self) -> "ActionTraceWriterV2":
        return self.open()

    def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> None:
        del exc_type, exc, tb
        self.close()


@contextmanager
def maybe_open_writer(config: ActionTraceConfigV2) -> Iterator[ActionTraceWriterV2 | None]:
    """Open a writer if tracing is enabled, else yield ``None``."""

    if not config.enabled:
        yield None
        return
    assert config.out_path is not None
    writer = ActionTraceWriterV2(config.out_path, gzip_enabled=config.gzip_enabled)
    writer.open()
    try:
        yield writer
    finally:
        writer.close()


def build_action_trace_record(
    config: ActionTraceConfigV2,
    *,
    output: model_r2d2_v2.R2D2OutputV2,
    selected: policy_r2d2_v2.SelectedActionV2,
    legal_action_v2: dict[str, Any],
    obs_raw: dict[str, Any],
    reward: float,
    done: bool,
    episode_id: str,
    step_index: int,
    global_step: int,
    epsilon: float,
    batch_index: int = 0,
    time_index: int = 0,
) -> dict[str, Any]:
    """Build one trace record for the level configured in ``config``.

    Higher levels strictly extend lower levels. ``legal_scores``/``full`` reuse
    ``policy_r2d2_v2.score_legal_actions_v2`` so scores match the policy exactly.
    """

    entries = (legal_action_v2 or {}).get("actions") or []
    record: dict[str, Any] = {
        "trace_level": config.level,
        "episode_id": episode_id,
        "step_index": int(step_index),
        "global_step": int(global_step),
        "policy_type": "epsilon_greedy",
        "epsilon": float(epsilon),
        "selected_action_v2": dict(selected.action_v2),
        "selected_legacy_action_id": selected.legacy_action_id,
        "selected_score": float(selected.score),
        "selected_is_random": bool(selected.is_random),
        "reward": float(reward),
        "done": bool(done),
        "phase": _phase(obs_raw),
        "micro_phase": _micro_phase(obs_raw),
        "legal_action_count": len(entries),
    }

    if config.scores_enabled:
        scored = policy_r2d2_v2.score_legal_actions_v2(
            output,
            legal_action_v2,
            batch_index=batch_index,
            time_index=time_index,
        )
        ranked = sorted(scored, key=lambda item: item.score, reverse=True)
        selected_index = selected.metadata.get("legal_index")
        record["selected_rank"] = _selected_rank(ranked, selected_index)
        record["best_score"] = ranked[0].score
        record["second_score"] = ranked[1].score if len(ranked) > 1 else None
        record["score_gap"] = (
            ranked[0].score - ranked[1].score if len(ranked) > 1 else None
        )
        record["call_dutch_score"] = _score_for_type(scored, "call_dutch")
        record["draw_score"] = _score_for_type(scored, "draw")
        listed = ranked if config.top_k is None else ranked[: config.top_k]
        record["legal_action_scores"] = [_scored_to_dict(item) for item in listed]

    if config.level == "full":
        record["obs_summary"] = _obs_summary(obs_raw)
        record["action_type_q"] = _action_type_q(output, batch_index, time_index)
        record["hidden_state_norm"] = _hidden_state_norm(output)

    return record


def _scored_to_dict(item: policy_r2d2_v2.ScoredActionV2) -> dict[str, Any]:
    return {
        "legal_index": item.legal_index,
        "action_type": item.action_v2.get("action_type"),
        "action_v2": dict(item.action_v2),
        "legacy_action_id": item.legacy_action_id,
        "legacy_kind": item.legacy_kind,
        "score": float(item.score),
    }


def _selected_rank(
    ranked: list[policy_r2d2_v2.ScoredActionV2],
    selected_index: Any,
) -> int | None:
    if selected_index is None:
        return None
    for rank, item in enumerate(ranked, start=1):
        if item.legal_index == selected_index:
            return rank
    return None


def _score_for_type(
    scored: list[policy_r2d2_v2.ScoredActionV2],
    action_type: str,
) -> float | None:
    best: float | None = None
    for item in scored:
        if item.action_v2.get("action_type") == action_type:
            if best is None or item.score > best:
                best = item.score
    return best


def _phase(obs_raw: dict[str, Any]) -> Any:
    obs = obs_raw.get("obs") or {}
    return obs.get("phase") or obs_raw.get("phase")


def _micro_phase(obs_raw: dict[str, Any]) -> Any:
    obs = obs_raw.get("obs") or {}
    return obs_raw.get("micro_phase") or obs.get("micro_phase")


def _hand_sizes(obs: dict[str, Any]) -> list[Any]:
    sizes = [obs.get("hand_size")]
    for opponent in obs.get("opponents") or []:
        sizes.append(opponent.get("hand_size"))
    return sizes


def _obs_summary(obs_raw: dict[str, Any]) -> dict[str, Any]:
    """Public/legal-only state summary (no hidden information).

    Every field below is part of the AgentInterface v2 policy input, which is
    already anti-leak validated upstream; the writer additionally scans the full
    record for forbidden keys before writing.
    """

    obs = obs_raw.get("obs") or {}
    legal = obs_raw.get("legal_action_v2") or {}
    return {
        "phase": _phase(obs_raw),
        "micro_phase": _micro_phase(obs_raw),
        "current_player": obs.get("current_player"),
        "turn_count": obs.get("turn_count"),
        "action_count": obs.get("action_count"),
        "deck_size": obs.get("deck_size"),
        "discard_size": obs.get("discard_size"),
        "top_discard_value": obs.get("top_discard_value"),
        "dutch_called": obs.get("dutch_called"),
        "dutch_caller_is_me": obs.get("dutch_caller_is_me"),
        "hand_sizes": _hand_sizes(obs),
        "available_action_types": legal.get("available_action_types"),
        "recent_events": obs_raw.get("recent_events"),
        "slot_stability": obs_raw.get("slot_stability"),
        "legal_private_memory": obs_raw.get("legal_private_memory"),
    }


def _action_type_q(
    output: model_r2d2_v2.R2D2OutputV2,
    batch_index: int,
    time_index: int,
) -> dict[str, float | None]:
    values = output.action_type_q[batch_index, time_index].detach().cpu().tolist()
    threshold = model_r2d2_v2.MASK_VALUE / 2.0
    result: dict[str, float | None] = {}
    for name, value in zip(encoding_v2.ACTION_TYPES, values):
        result[name] = None if value <= threshold else float(value)
    return result


def _hidden_state_norm(output: model_r2d2_v2.R2D2OutputV2) -> float:
    return float(output.hidden_state.detach().norm(2).cpu().item())


def _find_forbidden_keys(value: Any) -> set[str]:
    found: set[str] = set()
    if isinstance(value, dict):
        for key, child in value.items():
            if key in encoding_v2.FORBIDDEN_POLICY_KEYS:
                found.add(str(key))
            found.update(_find_forbidden_keys(child))
    elif isinstance(value, list):
        for child in value:
            found.update(_find_forbidden_keys(child))
    return found
