"""Dataset helpers for AgentInterface v2 JSONL rollouts.

The loader is intentionally separate from PPO and training code. It rebuilds
``TransitionV2`` objects from readable JSONL and loads them into a
``ReplayBufferV2`` for sequence sampling.

Single source of truth for n-step TD: training n-step targets are built in
``loss_r2d2_v2`` from each sampled sequence. ``compute_n_step_returns`` below is
an *offline analysis helper* (diagnostics, tests, dataset inspection); it is not
used by ``load_replay_buffer_from_jsonl`` and never feeds the learner. Keeping a
single live path avoids two ambiguous n-step computations.
"""

from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any

import encoding_v2
from replay_buffer_v2 import ReplayBufferV2
from rollout_v2 import TransitionV2


REQUIRED_TRANSITION_FIELDS = {
    "obs_raw",
    "action_v2",
    "legacy_action_id",
    "reward",
    "done",
    "next_obs_raw",
    "info",
    "episode_id",
    "step_index",
}


@dataclass(frozen=True)
class TransitionNStepV2:
    transition: TransitionV2
    n_step_return: float
    n_step_discount: float
    n_step_done: bool
    n_step_next_obs_raw: dict[str, Any] | None
    n_step_next_obs_encoded_v2: encoding_v2.EncodedObservationV2 | None
    actual_n: int


def load_transitions_jsonl(path: str | Path) -> list[TransitionV2]:
    transitions: list[TransitionV2] = []
    source = Path(path)
    with source.open("r", encoding="utf-8") as f:
        for line_no, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                payload = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"{source}:{line_no}: invalid JSONL") from exc
            transitions.append(_transition_from_payload(payload, source, line_no))

    _assert_episode_order(transitions)
    return transitions


def compute_n_step_returns(
    transitions: list[TransitionV2],
    *,
    n_step: int,
    gamma: float,
) -> list[TransitionNStepV2]:
    if n_step <= 0:
        raise ValueError("n_step must be positive")
    if gamma < 0.0:
        raise ValueError("gamma must be >= 0")

    ordered = _group_by_episode(transitions)
    results: list[TransitionNStepV2] = []
    for episode in ordered.values():
        for idx, transition in enumerate(episode):
            total = 0.0
            discount = 1.0
            actual_n = 0
            done = False
            next_obs_raw: dict[str, Any] | None = transition.next_obs_raw
            for offset in range(n_step):
                j = idx + offset
                if j >= len(episode):
                    break
                item = episode[j]
                total += discount * float(item.reward)
                actual_n += 1
                next_obs_raw = item.next_obs_raw
                if item.done:
                    done = True
                    break
                discount *= gamma

            n_step_discount = gamma**actual_n
            next_encoded = (
                None
                if done or next_obs_raw is None
                else encoding_v2.encode_observation_v2(next_obs_raw)
            )
            results.append(
                TransitionNStepV2(
                    transition=transition,
                    n_step_return=total,
                    n_step_discount=float(n_step_discount),
                    n_step_done=done,
                    n_step_next_obs_raw=next_obs_raw,
                    n_step_next_obs_encoded_v2=next_encoded,
                    actual_n=actual_n,
                )
            )
    return results


def load_replay_buffer_from_jsonl(
    path: str | Path,
    *,
    n_step: int | None = None,
    gamma: float = 0.99,
    prioritized: bool = False,
    priority_alpha: float = 0.6,
    priority_beta: float = 0.4,
    priority_epsilon: float = 1.0e-6,
) -> ReplayBufferV2:
    """Load a JSONL rollout file into a ``ReplayBufferV2``.

    ``n_step`` and ``gamma`` describe the horizon the learner/loss will use and
    are validated here for caller convenience; they do *not* mutate the buffer,
    which stores raw single-step transitions. The single source of truth for
    n-step TD targets is ``loss_r2d2_v2`` (computed per sampled sequence).
    """

    if n_step is not None and n_step <= 0:
        raise ValueError("n_step must be positive")
    if gamma < 0.0:
        raise ValueError("gamma must be >= 0")

    transitions = load_transitions_jsonl(path)
    buffer = ReplayBufferV2(
        prioritized=prioritized,
        priority_alpha=priority_alpha,
        priority_beta=priority_beta,
        priority_epsilon=priority_epsilon,
    )
    for episode in _group_by_episode(transitions).values():
        buffer.add_episode(episode)
    return buffer


def _transition_from_payload(
    payload: Any,
    source: Path,
    line_no: int,
) -> TransitionV2:
    if not isinstance(payload, dict):
        raise ValueError(f"{source}:{line_no}: transition must be a JSON object")

    missing = sorted(REQUIRED_TRANSITION_FIELDS - payload.keys())
    if missing:
        raise ValueError(f"{source}:{line_no}: missing required fields: {missing}")

    obs_raw = _require_dict(payload["obs_raw"], source, line_no, "obs_raw")
    next_obs_raw = payload["next_obs_raw"]
    if next_obs_raw is not None:
        next_obs_raw = _require_dict(next_obs_raw, source, line_no, "next_obs_raw")
    info = _require_dict(payload["info"], source, line_no, "info")
    _assert_no_forbidden_keys(obs_raw, source, line_no, "obs_raw")
    if next_obs_raw is not None:
        _assert_no_forbidden_keys(next_obs_raw, source, line_no, "next_obs_raw")
    _assert_no_forbidden_keys(info, source, line_no, "info")

    done = bool(payload["done"])
    obs_encoded = encoding_v2.encode_observation_v2(obs_raw)
    next_encoded = (
        None
        if done or next_obs_raw is None
        else encoding_v2.encode_observation_v2(next_obs_raw)
    )

    return TransitionV2(
        obs_raw=obs_raw,
        obs_encoded_v2=obs_encoded,
        action_v2=_copy_action_v2(payload["action_v2"]),
        legacy_action_id=_legacy_action_id(payload["legacy_action_id"]),
        reward=float(payload["reward"]),
        done=done,
        next_obs_raw=next_obs_raw,
        next_obs_encoded_v2=next_encoded,
        info=info,
        episode_id=str(payload["episode_id"]),
        step_index=int(payload["step_index"]),
    )


def _group_by_episode(
    transitions: list[TransitionV2],
) -> dict[str, list[TransitionV2]]:
    episodes: dict[str, list[TransitionV2]] = {}
    for transition in transitions:
        episodes.setdefault(transition.episode_id, []).append(transition)
    for episode in episodes.values():
        episode.sort(key=lambda item: item.step_index)
    return episodes


def _assert_episode_order(transitions: list[TransitionV2]) -> None:
    for episode_id, episode in _group_by_episode(transitions).items():
        expected = sorted(item.step_index for item in episode)
        actual = [item.step_index for item in episode]
        if actual != expected:
            raise ValueError(f"episode {episode_id} is not sorted by step_index")


def _require_dict(value: Any, source: Path, line_no: int, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{source}:{line_no}: {field} must be an object")
    return value


def _copy_action_v2(value: Any) -> dict[str, Any] | None:
    if value is None:
        return None
    if not isinstance(value, dict):
        raise ValueError(f"action_v2 must be an object or null, got {type(value).__name__}")
    return dict(value)


def _legacy_action_id(value: Any) -> int | None:
    if value is None:
        return None
    if not isinstance(value, int):
        raise ValueError("legacy_action_id must be an integer or null")
    return int(value)


def _assert_no_forbidden_keys(
    value: Any,
    source: Path,
    line_no: int,
    field: str,
) -> None:
    forbidden = _find_forbidden_keys(value)
    if forbidden:
        raise ValueError(
            f"{source}:{line_no}: forbidden keys in {field}: {sorted(forbidden)}"
        )


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
