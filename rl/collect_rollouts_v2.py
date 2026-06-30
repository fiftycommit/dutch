"""Small AgentInterface v2 rollout collector.

This script launches the real Dart runner through ``RunnerProcess`` and records
short v2 transition sequences with a simple legal random policy. It is a smoke
pipeline for future DRQN/R2D2 work, not a training entrypoint.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import random
from pathlib import Path
from typing import Any

import encoding_v2
from runner_process import RunnerProcess
import rollout_v2
from rollout_v2 import TransitionV2


REQUIRED_V2_BLOCKS = [
    "recent_events",
    "slot_stability",
    "legal_private_memory",
    "legal_action_v2",
]


@dataclass(frozen=True)
class EpisodeRecordV2:
    episode_id: str
    seed: int
    transitions: list[TransitionV2]
    completed: bool
    truncated_by_max_steps: bool


def choose_legal_action_v2(
    obs_raw: dict[str, Any],
    rng: random.Random,
) -> dict[str, Any]:
    """Choose one action from ``legal_action_v2.actions`` when available."""

    validate_observation_v2(obs_raw)
    actions = list(((obs_raw.get("legal_action_v2") or {}).get("actions") or []))
    if actions:
        action = dict(rng.choice(actions))
        _assert_action_entry_is_legal(obs_raw, action)
        return action

    # Compatibility fallback for early runner messages. This path should be rare
    # now that AgentInterface v2 exposes legal_action_v2.
    return rollout_v2.random_legal_policy_v2(obs_raw, rng)


def collect_episode_v2(
    runner: rollout_v2.RunnerLike,
    *,
    seed: int,
    episode_id: str,
    rng: random.Random,
    max_steps: int,
    extra_options: dict[str, Any] | None = None,
) -> EpisodeRecordV2:
    if max_steps <= 0:
        raise ValueError("max_steps must be positive")

    obs = runner.reset(seed, episode_id=episode_id, extra_options=extra_options)
    transitions: list[TransitionV2] = []
    completed = bool(obs.get("done"))

    for step_index in range(max_steps):
        if completed:
            break

        validate_observation_v2(obs)
        encoded = encoding_v2.encode_observation_v2(obs)
        action_entry = choose_legal_action_v2(obs, rng)
        next_obs = runner.step(rollout_v2.action_message_for_runner(action_entry))

        if next_obs.get("type") == "error":
            raise RuntimeError(
                f"runner returned error: {next_obs.get('code')} {next_obs.get('message')}"
            )

        done = bool(next_obs.get("done"))
        next_encoded = (
            None if done else encoding_v2.encode_observation_v2(next_obs)
        )
        transitions.append(
            TransitionV2(
                obs_raw=obs,
                obs_encoded_v2=encoded,
                action_v2=_copy_action_v2(action_entry.get("action_v2")),
                legacy_action_id=_legacy_action_id(action_entry),
                reward=_reward_from_message(next_obs),
                done=done,
                next_obs_raw=next_obs,
                next_obs_encoded_v2=next_encoded,
                info=dict(next_obs.get("info") or {}),
                episode_id=episode_id,
                step_index=step_index,
            )
        )

        obs = next_obs
        completed = done

    return EpisodeRecordV2(
        episode_id=episode_id,
        seed=seed,
        transitions=transitions,
        completed=completed,
        truncated_by_max_steps=not completed,
    )


def collect_rollouts_v2(
    runner: rollout_v2.RunnerLike,
    *,
    episodes: int,
    seed: int,
    max_steps: int,
    out: str | Path | None = None,
    save: bool = False,
    players: int | None = None,
    verbose: bool = False,
) -> list[EpisodeRecordV2]:
    if episodes <= 0:
        raise ValueError("episodes must be positive")

    rng = random.Random(seed)
    extra_options = {"num_players": int(players)} if players is not None else None
    records: list[EpisodeRecordV2] = []
    all_transitions: list[TransitionV2] = []
    for index in range(episodes):
        episode_seed = seed + index
        episode_id = f"v2-smoke-{episode_seed}"
        record = collect_episode_v2(
            runner,
            seed=episode_seed,
            episode_id=episode_id,
            rng=rng,
            max_steps=max_steps,
            extra_options=extra_options,
        )
        records.append(record)
        all_transitions.extend(record.transitions)
        if verbose:
            status = "done" if record.completed else "truncated"
            print(f"{episode_id}: {len(record.transitions)} transitions ({status})")

    if save and out is not None:
        target = Path(out)
        target.parent.mkdir(parents=True, exist_ok=True)
        rollout_v2.save_transitions_jsonl(all_transitions, target)
        if verbose:
            print(f"saved {len(all_transitions)} transitions to {target}")

    return records


def validate_observation_v2(obs_raw: dict[str, Any]) -> None:
    missing = [key for key in REQUIRED_V2_BLOCKS if key not in obs_raw]
    if missing:
        raise ValueError(f"missing AgentInterface v2 blocks: {missing}")

    forbidden = _find_forbidden_keys(obs_raw)
    if forbidden:
        raise ValueError(f"forbidden policy keys in observation: {sorted(forbidden)}")

    encoding_v2.encode_observation_v2(obs_raw)


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--episodes", type=int, default=1)
    parser.add_argument("--max-steps", type=int, default=200)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--out", type=str, default=None)
    parser.add_argument("--no-save", action="store_true")
    parser.add_argument("--players", type=int, default=None)
    parser.add_argument("--verbose", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)
    save = bool(args.out) and not args.no_save
    with RunnerProcess(max_turns=max(args.max_steps, 1)) as runner:
        records = collect_rollouts_v2(
            runner,
            episodes=args.episodes,
            seed=args.seed,
            max_steps=args.max_steps,
            out=args.out,
            save=save,
            players=args.players,
            verbose=args.verbose,
        )

    transitions = sum(len(record.transitions) for record in records)
    completed = sum(1 for record in records if record.completed)
    print(
        "collect_rollouts_v2: "
        f"episodes={len(records)} completed={completed} transitions={transitions} "
        f"saved={save}"
    )
    return 0


def _assert_action_entry_is_legal(
    obs_raw: dict[str, Any],
    action_entry: dict[str, Any],
) -> None:
    legal = ((obs_raw.get("legal_action_v2") or {}).get("actions") or [])
    action_v2 = action_entry.get("action_v2")
    legacy_id = action_entry.get("legacy_action_id")
    for legal_entry in legal:
        if action_v2 is not None and legal_entry.get("action_v2") == action_v2:
            return
        if legacy_id is not None and legal_entry.get("legacy_action_id") == legacy_id:
            return
    raise ValueError(f"action not present in legal_action_v2.actions: {action_entry!r}")


def _reward_from_message(msg: dict[str, Any]) -> float:
    rewards = msg.get("rewards")
    if isinstance(rewards, dict):
        return float(rewards.get("principal", msg.get("reward", 0.0)))
    return float(msg.get("reward", 0.0))


def _copy_action_v2(value: Any) -> dict[str, Any] | None:
    return dict(value) if isinstance(value, dict) else None


def _legacy_action_id(action_entry: dict[str, Any]) -> int | None:
    value = action_entry.get("legacy_action_id")
    return int(value) if isinstance(value, int) else None


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


if __name__ == "__main__":
    raise SystemExit(main())
