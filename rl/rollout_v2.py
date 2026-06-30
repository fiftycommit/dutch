"""Rollout recorder for AgentInterface v2 observations.

This module is intentionally separate from ``dutch_env.py`` and the PPO
training path. It records raw runner observations plus structured encodings so
future recurrent agents can build sequence replay without depending on the
legacy ``OBS_DIM`` vector.
"""

from __future__ import annotations

from dataclasses import dataclass, field, replace
import json
import random
from pathlib import Path
from typing import Any, Callable, Protocol

import encoding_v2
from encoding_v2 import EncodedObservationV2
import reward_v2


ActionPolicyV2 = Callable[[dict[str, Any], random.Random], dict[str, Any]]


class RunnerLike(Protocol):
    def reset(
        self,
        seed: int,
        episode_id: str | None = None,
        extra_options: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        ...

    def step(self, action_msg: dict[str, Any]) -> dict[str, Any]:
        ...


@dataclass(frozen=True)
class TransitionV2:
    obs_raw: dict[str, Any]
    obs_encoded_v2: EncodedObservationV2
    action_v2: dict[str, Any] | None
    legacy_action_id: int | None
    reward: float
    done: bool
    next_obs_raw: dict[str, Any] | None
    next_obs_encoded_v2: EncodedObservationV2 | None
    info: dict[str, Any]
    episode_id: str
    step_index: int
    reward_components: dict[str, float] | None = None


@dataclass(frozen=True)
class SequenceV2:
    transitions: list[TransitionV2]
    burn_in: int
    episode_id: str
    start_step: int
    done_mask: list[bool] = field(default_factory=list)


def random_legal_policy_v2(
    obs_raw: dict[str, Any],
    rng: random.Random,
) -> dict[str, Any]:
    """Pick one legal action from ``legal_action_v2`` or legacy mask fallback."""

    legal_action = obs_raw.get("legal_action_v2") or {}
    actions = list(legal_action.get("actions") or [])
    if actions:
        return dict(rng.choice(actions))

    mask = obs_raw.get("action_mask") or {}
    legacy_id = _first_legacy_id_from_mask(mask)
    if legacy_id is None:
        raise ValueError("observation has no legal action_v2 and no legacy action")
    return {
        "action_v2": None,
        "legacy_action_id": legacy_id,
        "legacy_kind": "legacy_fallback",
    }


def action_message_for_runner(action_entry: dict[str, Any]) -> dict[str, Any]:
    """Convert a legal action entry into the runner input format."""

    action_v2 = action_entry.get("action_v2")
    if isinstance(action_v2, dict):
        return {"action_v2": action_v2}

    legacy_id = action_entry.get("legacy_action_id")
    if isinstance(legacy_id, int):
        return {"action_id": legacy_id}

    raise ValueError(f"invalid action entry: {action_entry!r}")


def record_episode_v2(
    runner: RunnerLike,
    *,
    seed: int,
    episode_id: str | None = None,
    policy: ActionPolicyV2 = random_legal_policy_v2,
    rng: random.Random | None = None,
    max_steps: int = 2000,
    extra_options: dict[str, Any] | None = None,
) -> list[TransitionV2]:
    """Record one raw v2 episode from a runner-like process.

    This does not train a model. The policy is only used to advance the game.
    """

    if max_steps <= 0:
        raise ValueError("max_steps must be positive")

    episode_key = episode_id or f"ep{seed}"
    rng = rng or random.Random(seed)
    obs = runner.reset(seed, episode_id=episode_key, extra_options=extra_options)
    transitions: list[TransitionV2] = []

    for step_index in range(max_steps):
        if bool(obs.get("done")):
            break

        _assert_no_forbidden_policy_keys(obs)
        encoded = encoding_v2.encode_observation_v2(obs)
        action_entry = policy(obs, rng)
        action_msg = action_message_for_runner(action_entry)
        next_obs = runner.step(action_msg)

        if next_obs.get("type") == "error":
            raise RuntimeError(
                f"runner returned error: {next_obs.get('code')} {next_obs.get('message')}"
            )

        done = bool(next_obs.get("done"))
        reward_components = reward_v2.parse_reward_components_v2(
            next_obs,
            action_v2=_copy_action_v2(action_entry.get("action_v2")),
        )
        reward = reward_components.total
        next_encoded = (
            None if done else encoding_v2.encode_observation_v2(next_obs)
        )

        transitions.append(
            TransitionV2(
                obs_raw=obs,
                obs_encoded_v2=encoded,
                action_v2=_copy_action_v2(action_entry.get("action_v2")),
                legacy_action_id=_legacy_action_id(action_entry),
                reward=reward,
                done=done,
                next_obs_raw=next_obs,
                next_obs_encoded_v2=next_encoded,
                info=dict(next_obs.get("info") or {}),
                episode_id=episode_key,
                step_index=step_index,
                reward_components=reward_components.to_dict(),
            )
        )

        obs = next_obs
        if done:
            break
    else:
        raise RuntimeError(f"episode {episode_key} exceeded max_steps={max_steps}")

    return finalize_episode_rewards_v2(transitions)


def finalize_episode_rewards_v2(transitions: list[TransitionV2]) -> list[TransitionV2]:
    """Pay positive reward potential on the terminal transition only after wins."""

    if not transitions:
        return []

    terminal_index = None
    for index in range(len(transitions) - 1, -1, -1):
        if transitions[index].done:
            terminal_index = index
            break
    if terminal_index is None:
        return list(transitions)

    terminal = transitions[terminal_index]
    won = reward_v2.is_terminal_win_v2(terminal.info, terminal.next_obs_raw)
    paid_bonus = 0.0
    if won:
        paid_bonus = sum(
            reward_v2.positive_bonus_potential_from_components_v2(
                item.reward_components
            )
            for item in transitions[: terminal_index + 1]
        )

    terminal_components = reward_v2.apply_paid_positive_bonus_v2(
        terminal.reward_components,
        paid_bonus,
    )
    finalized = list(transitions)
    finalized[terminal_index] = replace(
        terminal,
        reward=terminal_components["total"],
        reward_components=terminal_components,
    )
    return finalized


def build_sequences(
    transitions: list[TransitionV2],
    *,
    seq_len: int,
    burn_in: int = 0,
) -> list[SequenceV2]:
    """Slice ordered transitions into fixed-length per-episode windows."""

    if seq_len <= 0:
        raise ValueError("seq_len must be positive")
    if burn_in < 0:
        raise ValueError("burn_in must be >= 0")

    sequences: list[SequenceV2] = []
    for episode_id, episode in _group_by_episode(transitions).items():
        start = 0
        while start < len(episode):
            window = episode[start : start + seq_len]
            if len(window) < seq_len:
                break
            sequences.append(
                SequenceV2(
                    transitions=window,
                    burn_in=min(burn_in, len(window)),
                    episode_id=episode_id,
                    start_step=window[0].step_index,
                    done_mask=[item.done for item in window],
                )
            )
            start += seq_len
    return sequences


def save_transitions_jsonl(
    transitions: list[TransitionV2],
    path: str | Path,
) -> None:
    """Save transitions as readable JSONL.

    Encoded arrays are not serialized; they are deterministic products of the
    raw observations and can be regenerated with ``encoding_v2`` on load.
    """

    target = Path(path)
    with target.open("w", encoding="utf-8") as f:
        for transition in transitions:
            f.write(json.dumps(transition_to_jsonable(transition), sort_keys=True))
            f.write("\n")


def transition_to_jsonable(transition: TransitionV2) -> dict[str, Any]:
    return {
        "episode_id": transition.episode_id,
        "step_index": transition.step_index,
        "obs_raw": transition.obs_raw,
        "action_v2": transition.action_v2,
        "legacy_action_id": transition.legacy_action_id,
        "reward": transition.reward,
        "done": transition.done,
        "next_obs_raw": transition.next_obs_raw,
        "info": transition.info,
        "reward_components": transition.reward_components,
    }


def _reward_from_message(
    msg: dict[str, Any],
    action_v2: dict[str, Any] | None = None,
) -> float:
    return reward_v2.reward_from_message_v2(msg, action_v2=action_v2)


def _copy_action_v2(value: Any) -> dict[str, Any] | None:
    return dict(value) if isinstance(value, dict) else None


def _legacy_action_id(action_entry: dict[str, Any]) -> int | None:
    value = action_entry.get("legacy_action_id")
    return int(value) if isinstance(value, int) else None


def _group_by_episode(
    transitions: list[TransitionV2],
) -> dict[str, list[TransitionV2]]:
    episodes: dict[str, list[TransitionV2]] = {}
    for transition in transitions:
        episodes.setdefault(transition.episode_id, []).append(transition)
    return episodes


def _first_legacy_id_from_mask(mask: Any) -> int | None:
    if not isinstance(mask, dict):
        return None
    action_type_order = [
        ("call_dutch", 0),
        ("continue_draw", 1),
        ("discard_drawn", 2),
        ("skip_power", 3),
        ("pass_tick", 6185),
    ]
    for key, legacy_id in action_type_order:
        if mask.get(key):
            return legacy_id
    return None


def _assert_no_forbidden_policy_keys(obs_raw: dict[str, Any]) -> None:
    found = _find_forbidden_keys(obs_raw)
    if found:
        raise ValueError(f"forbidden policy keys in observation: {sorted(found)}")


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
