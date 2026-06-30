"""Smoke inference pipeline for the AgentInterface v2 recurrent model.

This script is not a trainer. It runs an untrained ``R2D2AgentV2`` through the
real runner to verify the end-to-end path:

raw observation -> encoding_v2 -> model -> policy_r2d2_v2 -> action_v2 -> runner
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import random
from pathlib import Path
from typing import Any

import numpy as np
import torch

import action_trace_v2
import collect_rollouts_v2
import encoding_v2
import model_r2d2_v2
import policy_r2d2_v2
import reward_v2
from runner_process import RunnerProcess
import rollout_v2
import schedules_v2
from rollout_v2 import TransitionV2
from replay_buffer_v2 import SequenceBatchV2


@dataclass(frozen=True)
class InferenceEpisodeV2:
    episode_id: str
    seed: int
    transitions: list[TransitionV2]
    completed: bool
    truncated_by_max_steps: bool


def observation_batch_v2(obs_raw: dict[str, Any]) -> SequenceBatchV2:
    """Build a single-step recurrent batch from one raw v2 observation."""

    collect_rollouts_v2.validate_observation_v2(obs_raw)
    encoded = encoding_v2.encode_observation_v2(obs_raw)
    batch_size = 1
    total_len = 1
    legacy_mask = (
        None
        if encoded.legacy_action_mask is None
        else np.expand_dims(np.expand_dims(encoded.legacy_action_mask, axis=0), axis=0)
    )

    return SequenceBatchV2(
        public_features=encoded.public_features.reshape(batch_size, total_len, -1),
        private_memory_features=encoded.private_memory_features.reshape(
            batch_size,
            total_len,
            -1,
        ),
        event_features=encoded.event_features.reshape(
            batch_size,
            total_len,
            *encoded.event_features.shape,
        ),
        slot_stability_features=encoded.slot_stability_features.reshape(
            batch_size,
            total_len,
            -1,
        ),
        action_type_mask=encoded.action_type_mask.reshape(batch_size, total_len, -1),
        argument_masks={
            name: mask.reshape(batch_size, total_len, *mask.shape)
            for name, mask in encoded.argument_masks.items()
        },
        legacy_action_mask=legacy_mask,
        actions_v2=[[None]],
        legacy_action_ids=np.full((batch_size, total_len), -1, dtype=np.int64),
        rewards=np.zeros((batch_size, total_len), dtype=np.float32),
        dones=np.zeros((batch_size, total_len), dtype=bool),
        done_mask=np.zeros((batch_size, total_len), dtype=bool),
        burn_in_mask=np.zeros((batch_size, total_len), dtype=bool),
        train_mask=np.ones((batch_size, total_len), dtype=bool),
        padding_mask=np.zeros((batch_size, total_len), dtype=bool),
        episode_ids=[["inference"]],
        step_indices=np.zeros((batch_size, total_len), dtype=np.int64),
        metadata={"batch_size": batch_size, "total_len": total_len, "mode": "inference"},
    )


def infer_episode_v2(
    runner: rollout_v2.RunnerLike,
    model: Any,
    *,
    seed: int,
    episode_id: str,
    epsilon: float,
    rng: random.Random,
    max_steps: int,
    extra_options: dict[str, Any] | None = None,
    epsilon_schedule: schedules_v2.LinearScheduleV2 | None = None,
    global_step_offset: int = 0,
    trace_writer: action_trace_v2.ActionTraceWriterV2 | None = None,
    trace_config: action_trace_v2.ActionTraceConfigV2 | None = None,
    verbose: bool = False,
) -> InferenceEpisodeV2:
    if max_steps <= 0:
        raise ValueError("max_steps must be positive")
    if global_step_offset < 0:
        raise ValueError("global_step_offset must be >= 0")
    trace_enabled = (
        trace_writer is not None
        and trace_config is not None
        and trace_config.enabled
    )

    obs = runner.reset(seed, episode_id=episode_id, extra_options=extra_options)
    transitions: list[TransitionV2] = []
    completed = bool(obs.get("done"))
    hidden_state: torch.Tensor | None = None

    for step_index in range(max_steps):
        if completed:
            break

        collect_rollouts_v2.validate_observation_v2(obs)
        encoded = encoding_v2.encode_observation_v2(obs)
        batch = observation_batch_v2(obs)
        with torch.no_grad():
            output = model(batch, hidden_state=hidden_state, apply_masks=True)
        hidden_state = output.hidden_state.detach()

        # Epsilon is annealed on the *global* policy-decision step so it keeps
        # decaying across episode boundaries (the caller advances the offset).
        current_epsilon = (
            epsilon
            if epsilon_schedule is None
            else epsilon_schedule.value_at(global_step_offset + step_index)
        )
        selected = policy_r2d2_v2.select_action_from_batch_output(
            output,
            batch_index=0,
            time_index=0,
            legal_action_v2=obs.get("legal_action_v2") or {},
            epsilon=current_epsilon,
            rng=rng,
        )
        next_obs = runner.step(policy_r2d2_v2.action_message_for_runner_v2(selected))

        if next_obs.get("type") == "error":
            raise RuntimeError(
                f"runner returned error: {next_obs.get('code')} {next_obs.get('message')}"
            )

        done = bool(next_obs.get("done"))
        reward_components = reward_v2.parse_reward_components_v2(
            next_obs,
            action_v2=dict(selected.action_v2),
        )
        reward = reward_components.total

        if trace_enabled:
            record = action_trace_v2.build_action_trace_record(
                trace_config,
                output=output,
                selected=selected,
                legal_action_v2=obs.get("legal_action_v2") or {},
                obs_raw=obs,
                reward=reward,
                reward_components=reward_components.to_dict(),
                done=done,
                episode_id=episode_id,
                step_index=step_index,
                global_step=global_step_offset + step_index,
                epsilon=current_epsilon,
            )
            trace_writer.write(record)

        next_encoded = (
            None if done else encoding_v2.encode_observation_v2(next_obs)
        )
        transitions.append(
            TransitionV2(
                obs_raw=obs,
                obs_encoded_v2=encoded,
                action_v2=dict(selected.action_v2),
                legacy_action_id=selected.legacy_action_id,
                reward=reward,
                done=done,
                next_obs_raw=next_obs,
                next_obs_encoded_v2=next_encoded,
                info={
                    **dict(next_obs.get("info") or {}),
                    "inference_score": selected.score,
                    "inference_is_random": selected.is_random,
                    "inference_epsilon": float(current_epsilon),
                },
                episode_id=episode_id,
                step_index=step_index,
                reward_components=reward_components.to_dict(),
            )
        )

        if verbose:
            print(
                f"{episode_id} step={step_index} "
                f"action={selected.action_v2} score={selected.score:.4f} done={done}"
            )

        obs = next_obs
        completed = done

    return InferenceEpisodeV2(
        episode_id=episode_id,
        seed=seed,
        transitions=transitions,
        completed=completed,
        truncated_by_max_steps=not completed,
    )


def infer_rollouts_v2(
    runner: rollout_v2.RunnerLike,
    model: Any,
    *,
    episodes: int,
    seed: int,
    max_steps: int,
    epsilon: float,
    epsilon_schedule: schedules_v2.LinearScheduleV2 | None = None,
    trace_writer: action_trace_v2.ActionTraceWriterV2 | None = None,
    trace_config: action_trace_v2.ActionTraceConfigV2 | None = None,
    save_transitions: str | Path | None = None,
    save: bool = False,
    players: int | None = None,
    verbose: bool = False,
) -> list[InferenceEpisodeV2]:
    if episodes <= 0:
        raise ValueError("episodes must be positive")
    rng = random.Random(seed)
    extra_options = {"num_players": int(players)} if players is not None else None
    records: list[InferenceEpisodeV2] = []
    all_transitions: list[TransitionV2] = []
    global_step = 0

    for index in range(episodes):
        episode_seed = seed + index
        episode_id = f"r2d2-v2-infer-{episode_seed}"
        record = infer_episode_v2(
            runner,
            model,
            seed=episode_seed,
            episode_id=episode_id,
            epsilon=epsilon,
            rng=rng,
            max_steps=max_steps,
            extra_options=extra_options,
            epsilon_schedule=epsilon_schedule,
            global_step_offset=global_step,
            trace_writer=trace_writer,
            trace_config=trace_config,
            verbose=verbose,
        )
        records.append(record)
        all_transitions.extend(record.transitions)
        global_step += len(record.transitions)

    if save and save_transitions is not None:
        target = Path(save_transitions)
        target.parent.mkdir(parents=True, exist_ok=True)
        rollout_v2.save_transitions_jsonl(all_transitions, target)
        if verbose:
            print(f"saved {len(all_transitions)} transitions to {target}")

    return records


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--episodes", type=int, default=1)
    parser.add_argument("--max-steps", type=int, default=20)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--epsilon", type=float, default=0.0)
    parser.add_argument("--epsilon-start", type=float, default=None)
    parser.add_argument("--epsilon-end", type=float, default=None)
    parser.add_argument("--epsilon-steps", type=int, default=None)
    parser.add_argument("--players", type=int, default=6)
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--save-transitions", type=str, default=None)
    parser.add_argument("--no-save", action="store_true")
    parser.add_argument(
        "--trace-actions",
        choices=list(action_trace_v2.TRACE_LEVELS),
        default="none",
    )
    parser.add_argument("--action-trace-out", type=str, default=None)
    parser.add_argument("--action-trace-gzip", action="store_true")
    parser.add_argument("--action-trace-top-k", type=int, default=None)
    return parser


def trace_config_from_args(args: argparse.Namespace) -> action_trace_v2.ActionTraceConfigV2:
    return action_trace_v2.ActionTraceConfigV2(
        level=args.trace_actions,
        out_path=Path(args.action_trace_out) if args.action_trace_out else None,
        gzip=bool(args.action_trace_gzip),
        top_k=args.action_trace_top_k,
    )


def main(argv: list[str] | None = None) -> int:
    args = build_arg_parser().parse_args(argv)
    torch.manual_seed(args.seed)
    model = model_r2d2_v2.R2D2AgentV2()
    model.eval()
    save = bool(args.save_transitions) and not args.no_save

    epsilon_schedule = schedules_v2.build_optional_schedule(
        args.epsilon_start,
        args.epsilon_end,
        args.epsilon_steps,
        name="epsilon",
        minimum=0.0,
        maximum=1.0,
    )
    trace_config = trace_config_from_args(args)

    with action_trace_v2.maybe_open_writer(trace_config) as trace_writer:
        with RunnerProcess(max_turns=max(args.max_steps, 1)) as runner:
            records = infer_rollouts_v2(
                runner,
                model,
                episodes=args.episodes,
                seed=args.seed,
                max_steps=args.max_steps,
                epsilon=args.epsilon,
                epsilon_schedule=epsilon_schedule,
                trace_writer=trace_writer,
                trace_config=trace_config,
                save_transitions=args.save_transitions,
                save=save,
                players=args.players,
                verbose=args.verbose,
            )

    transitions = sum(len(record.transitions) for record in records)
    completed = sum(1 for record in records if record.completed)
    epsilon_desc = (
        f"epsilon={args.epsilon}"
        if epsilon_schedule is None
        else (
            f"epsilon_schedule={epsilon_schedule.start_value}->{epsilon_schedule.end_value}"
            f"@{epsilon_schedule.duration_steps}"
        )
    )
    print(
        "infer_r2d2_v2: "
        f"episodes={len(records)} completed={completed} transitions={transitions} "
        f"{epsilon_desc} saved={save}"
    )
    return 0


def _reward_from_message(
    msg: dict[str, Any],
    action_v2: dict[str, Any] | None = None,
) -> float:
    return reward_v2.reward_from_message_v2(msg, action_v2=action_v2)


if __name__ == "__main__":
    raise SystemExit(main())
