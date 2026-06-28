"""Évaluation comportementale V3 avec diagnostics décisionnels eval-only.

Ce script parle directement au runner NDJSON au lieu de passer par `DutchEnv`,
afin de consommer les diagnostics non terminaux (`diagnostics`) sans modifier
le training, l'observation ou la reward.
"""

from __future__ import annotations

import argparse
import csv
import math
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable

import numpy as np
from sb3_contrib import MaskablePPO

import encoding
from runner_process import RunnerCrashed, RunnerProcess, RunnerTimeout


DEFAULT_SKILLS = ("bronze", "silver", "difficile")
DEFAULT_NUM_PLAYERS = (2, 3, 4, 5, 6)
OPPONENT_BEHAVIOR = "balanced"
DEFAULT_GAMES = 1
DEFAULT_OUT = "behavior_report_v3.csv"
MAX_TURNS = 500

OBS_DRAWN_PRESENT = 20
OBS_DRAWN_POINTS = 21
OBS_KNOWN_SCORE = 40
OBS_ESTIMATED_SCORE = 45
OBS_SLOTS_START = 48
OBS_SLOT_STRIDE = 6
OBS_SLOT_KNOWN_OFFSET = 1
OBS_SLOT_POINTS_OFFSET = 2

CSV_COLUMNS = [
    "skill",
    "num_players",
    "seed",
    "episode_index",
    "aborted",
    "abort_reason",
    "won",
    "rank",
    "final_score_p0",
    "episode_length",
    "steps",
    "dutch_legal_decisions",
    "dutch_calls",
    "dutch_call_rate_when_legal",
    "called_dutch",
    "dutch_success",
    "dutch_bad_call",
    "dutch_margin_at_call",
    "self_score_at_call",
    "best_opponent_score_at_call",
    "dutch_real_win_opportunities",
    "dutch_real_top_half_opportunities",
    "dutch_missed_win_opportunities",
    "dutch_missed_top_half_opportunities",
    "dutch_call_when_winning_opportunity",
    "dutch_call_when_losing_position",
    "mean_dutch_margin_when_legal",
    "mean_dutch_margin_when_missed",
    "max_dutch_margin_missed",
    "mean_natural_rank_when_legal",
    "mean_natural_rank_when_missed",
    "dutch_win_opportunities_early",
    "dutch_win_opportunities_mid",
    "dutch_win_opportunities_late",
    "missed_win_opportunities_early",
    "missed_win_opportunities_mid",
    "missed_win_opportunities_late",
    "missed_win_rate_early",
    "missed_win_rate_mid",
    "missed_win_rate_late",
    "mean_margin_missed_early",
    "mean_margin_missed_mid",
    "mean_margin_missed_late",
    "max_margin_missed_early",
    "max_margin_missed_mid",
    "max_margin_missed_late",
    "known_full_hand_win_opportunities",
    "missed_known_full_hand_win_opportunities",
    "missed_known_full_hand_win_rate",
    "partial_known_hand_win_opportunities",
    "missed_partial_known_hand_win_opportunities",
    "missed_partial_known_hand_win_rate",
    "low_known_hand_win_opportunities",
    "missed_low_known_hand_win_opportunities",
    "missed_low_known_hand_win_rate",
    "known_full_hand_win_opportunities_late",
    "missed_known_full_hand_win_late",
    "missed_known_full_hand_win_rate_late",
    "mean_margin_missed_known_full_hand_late",
    "justified_non_call_count",
    "cautious_non_call_count",
    "clear_missed_non_call_count",
    "discard_drawn_count",
    "discarded_drawn_points_mean",
    "replace_count",
    "discarded_better_than_known_hand_proxy",
    "known_replace_proxy_good",
    "known_replace_proxy_bad",
    "drawn_decisions",
    "replace_rate_when_drawn",
    "discard_drawn_rate",
    "mean_drawn_points_replaced",
    "mean_drawn_points_discarded",
    "good_swap_count",
    "bad_swap_count",
    "neutral_swap_count",
    "mean_swap_real_delta_score",
    "bad_swap_rate",
    "discard_good_drawn_count",
    "discard_bad_drawn_count",
    "mean_discarded_drawn_improvement_if_swapped",
    "valid_known_slot_count_start",
    "valid_known_slot_count_end",
    "valid_known_slot_count_mean",
    "stale_known_slot_count_mean",
    "ever_seen_current_hand_count_mean",
    "current_card_seen_by_agent_count_mean",
    "p0_known_card_invalidated_by_opponent",
    "p0_memory_disruption_count",
    "score_estimate_error_valid_known_only_mean",
    "score_estimate_error_all_hand_mean",
    "memory_truth_accuracy_mean",
    "times_p0_cards_changed_by_opponents",
    "mean_score_delta_from_opponent_actions",
    "agent_spy_uses",
    "agent_swap_power_uses",
    "agent_joker_uses",
    "agent_offensive_actions_count",
    "agent_targets_unique_opponents",
    "mean_agent_score_delta_from_power",
    "mean_opponent_score_delta_from_power",
    "self_damage_actions",
    "self_damage_score_delta",
    "known_replace_real_good",
    "known_replace_real_bad",
    "unknown_to_known_swap_count",
    "known_to_known_swap_count",
    "known_to_unknown_swap_count",
    "unknown_to_unknown_swap_count",
    "swap_reduced_uncertainty_count",
    "swap_increased_uncertainty_count",
    "swap_kept_uncertainty_same_count",
    "mean_swap_information_delta",
    "swap_real_good_and_info_good_count",
    "swap_real_bad_but_info_good_count",
    "swap_real_good_but_info_bad_count",
    "swap_real_bad_and_info_bad_count",
    "discard_drawn_when_unknown_slots_available",
    "discard_drawn_that_would_reduce_uncertainty",
    "discard_drawn_good_score_or_info_opportunity",
    "discard_drawn_best_target_delta_score_mean",
    "discard_drawn_best_target_info_delta_mean",
    "special_available_count",
    "special_used_count",
    "look_available_count",
    "look_used_count",
    "spy_available_count",
    "spy_used_count",
    "swap_power_available_count",
    "swap_power_used_count",
    "joker_available_count",
    "joker_used_count",
    "known_score_start",
    "known_score_end",
    "estimated_score_start",
    "estimated_score_end",
    "estimated_score_delta",
    "diagnostics_seen",
    "obs_dim",
    "reward_seen",
]


def _parse_csv_values(raw: str, allowed: Iterable[str], *, name: str) -> list[str]:
    allowed_set = set(allowed)
    values = [v.strip() for v in raw.split(",") if v.strip()]
    if not values:
        raise SystemExit(f"--{name} ne peut pas être vide")
    invalid = [v for v in values if v not in allowed_set]
    if invalid:
        raise SystemExit(
            f"--{name} contient des valeurs invalides: {invalid}. "
            f"Valeurs attendues: {sorted(allowed_set)}"
        )
    return values


def _parse_num_players(raw: str) -> list[int]:
    values: list[int] = []
    for part in raw.split(","):
        part = part.strip()
        if not part:
            continue
        try:
            n = int(part)
        except ValueError as exc:
            raise SystemExit(f"--num-players invalide: {part!r}") from exc
        if n < 2 or n > 6:
            raise SystemExit("--num-players doit contenir des entiers entre 2 et 6")
        values.append(n)
    if not values:
        raise SystemExit("--num-players ne peut pas être vide")
    return values


def _finite_mean(values: list[float | int | None]) -> float | None:
    nums = [float(v) for v in values if v is not None and math.isfinite(float(v))]
    return (sum(nums) / len(nums)) if nums else None


def _safe_rate(num: int, den: int) -> float | None:
    return (num / den) if den else None


def _obs_known_score(obs: np.ndarray) -> float:
    return float(obs[OBS_KNOWN_SCORE]) * 80.0


def _obs_estimated_score(obs: np.ndarray) -> float:
    return float(obs[OBS_ESTIMATED_SCORE]) * 100.0


def _obs_drawn_points(obs: np.ndarray) -> float | None:
    if float(obs[OBS_DRAWN_PRESENT]) <= 0.5:
        return None
    return float(obs[OBS_DRAWN_POINTS]) * 13.0


def _known_slot_points(obs: np.ndarray) -> list[float]:
    points: list[float] = []
    for i in range(encoding.MAX_HAND):
        base = OBS_SLOTS_START + i * OBS_SLOT_STRIDE
        known = float(obs[base + OBS_SLOT_KNOWN_OFFSET]) > 0.5
        if known:
            points.append(float(obs[base + OBS_SLOT_POINTS_OFFSET]) * 13.0)
    return points


def _is_known_replace_proxy_good(obs: np.ndarray, action: int) -> bool | None:
    if not (encoding._REPLACE <= action < encoding._REPLACE + encoding.MAX_HAND):
        return None
    drawn = _obs_drawn_points(obs)
    if drawn is None:
        return None
    slot = action - encoding._REPLACE
    base = OBS_SLOTS_START + slot * OBS_SLOT_STRIDE
    known = float(obs[base + OBS_SLOT_KNOWN_OFFSET]) > 0.5
    if not known:
        return None
    replaced_points = float(obs[base + OBS_SLOT_POINTS_OFFSET]) * 13.0
    return drawn <= replaced_points


def _discard_better_than_known_hand_proxy(obs: np.ndarray) -> bool | None:
    drawn = _obs_drawn_points(obs)
    known_points = _known_slot_points(obs)
    if drawn is None or not known_points:
        return None
    return drawn < max(known_points)


def _mask_any(mask: np.ndarray, start: int, stop: int) -> bool:
    return bool(np.any(mask[start:stop]))


def _power_availability(mask: np.ndarray) -> dict[str, bool]:
    look = _mask_any(mask, encoding._POWER7, encoding._POWER7 + encoding.MAX_HAND)
    spy = _mask_any(
        mask,
        encoding._POWER10,
        encoding._POWER10 + encoding.MAX_OPP * encoding.MAX_HAND,
    )
    swap = _mask_any(
        mask,
        encoding._POWERV,
        encoding._POWERV + encoding.MAX_HAND * encoding.MAX_OPP,
    )
    joker = _mask_any(mask, encoding._POWERJOKER, encoding._POWERJOKER + encoding.MAX_OPP)
    return {
        "look": look,
        "spy": spy,
        "swap_power": swap,
        "joker": joker,
        "special": look or spy or swap or joker,
    }


def _terminal_call_metrics(
    terminal: dict[str, Any], *, agent_called_dutch: bool
) -> dict[str, Any]:
    scores = terminal.get("final_scores") or {}
    self_score = scores.get("p0")
    opp_scores = [
        score for seat, score in scores.items()
        if seat != "p0" and isinstance(score, (int, float))
    ]
    best_opp = min(opp_scores) if opp_scores else None
    margin = None
    if (
        agent_called_dutch
        and isinstance(self_score, (int, float))
        and best_opp is not None
    ):
        margin = float(best_opp) - float(self_score)
    return {
        "self_score_at_call": self_score if agent_called_dutch else None,
        "best_opponent_score_at_call": best_opp if agent_called_dutch else None,
        "dutch_margin_at_call": margin,
        "dutch_bad_call": (margin < 0.0) if margin is not None else None,
    }


def _require_observation(msg: dict[str, Any]) -> tuple[np.ndarray, np.ndarray, dict[str, Any]]:
    if msg.get("done"):
        raise ValueError("message terminal inattendu")
    diagnostics = msg.get("diagnostics")
    if not isinstance(diagnostics, dict):
        raise ValueError("diagnostics absents: compiler le runner behavior et passer eval_diagnostics")
    obs = encoding.encode_observation(msg)
    if obs.shape != (encoding.OBS_DIM,):
        raise ValueError(f"obs shape invalide: {obs.shape}")
    mask = encoding.build_mask_vector(msg)
    return obs, mask, diagnostics


def play_one_game(
    runner: RunnerProcess,
    model: MaskablePPO,
    *,
    skill: str,
    num_players: int,
    seed: int,
    episode_index: int,
    deterministic: bool,
    max_steps_per_game: int,
) -> dict[str, Any]:
    try:
        msg = runner.reset(
            seed,
            extra_options={
                "num_players": num_players,
                "opponents": {"skill": skill, "behavior": OPPONENT_BEHAVIOR},
                "eval_diagnostics": True,
            },
        )
    except (RunnerCrashed, RunnerTimeout) as exc:
        return _aborted_row(skill, num_players, seed, episode_index, str(exc))

    if msg.get("type") == "error":
        return _aborted_row(skill, num_players, seed, episode_index, str(msg))

    steps = 0
    aborted = False
    abort_reason = ""
    terminal: dict[str, Any] = {}
    diagnostics_seen = 0
    reward_seen = 0

    dutch_legal_decisions = 0
    dutch_calls = 0
    dutch_real_win_opportunities = 0
    dutch_real_top_half_opportunities = 0
    dutch_missed_win_opportunities = 0
    dutch_missed_top_half_opportunities = 0
    dutch_call_when_winning_opportunity = 0
    dutch_call_when_losing_position = 0
    justified_non_call_count = 0
    cautious_non_call_count = 0
    clear_missed_non_call_count = 0
    margins_when_legal: list[float] = []
    margins_when_missed: list[float] = []
    ranks_when_legal: list[float] = []
    ranks_when_missed: list[float] = []
    buckets = ("early", "mid", "late")
    win_opportunities_by_bucket = {bucket: 0 for bucket in buckets}
    missed_opportunities_by_bucket = {bucket: 0 for bucket in buckets}
    missed_margins_by_bucket: dict[str, list[float]] = {
        bucket: [] for bucket in buckets
    }
    known_full_hand_win_opportunities = 0
    missed_known_full_hand_win_opportunities = 0
    partial_known_hand_win_opportunities = 0
    missed_partial_known_hand_win_opportunities = 0
    low_known_hand_win_opportunities = 0
    missed_low_known_hand_win_opportunities = 0
    known_full_hand_win_opportunities_late = 0
    missed_known_full_hand_win_late = 0
    missed_known_full_hand_late_margins: list[float] = []

    discard_drawn_count = 0
    discarded_drawn_points: list[float] = []
    replace_count = 0
    discarded_better_proxy = 0
    known_replace_proxy_good = 0
    known_replace_proxy_bad = 0
    drawn_decisions = 0
    drawn_points_replaced: list[float] = []
    swap_real_deltas: list[float] = []
    good_swap_count = 0
    bad_swap_count = 0
    neutral_swap_count = 0
    discard_good_drawn_count = 0
    discard_bad_drawn_count = 0
    discarded_drawn_improvements: list[float] = []
    valid_known_samples: list[float] = []
    stale_known_samples: list[float] = []
    ever_seen_samples: list[float] = []
    current_seen_samples: list[float] = []
    err_valid_samples: list[float] = []
    err_all_samples: list[float] = []
    memory_accuracy_samples: list[float] = []
    score_deltas_from_opponents: list[float] = []
    agent_power_self_deltas: list[float] = []
    agent_power_opponent_deltas: list[float] = []
    self_damage_actions = 0
    self_damage_score_delta = 0.0
    known_replace_real_good = 0
    known_replace_real_bad = 0
    unknown_to_known_swap_count = 0
    known_to_known_swap_count = 0
    known_to_unknown_swap_count = 0
    unknown_to_unknown_swap_count = 0
    swap_reduced_uncertainty_count = 0
    swap_increased_uncertainty_count = 0
    swap_kept_uncertainty_same_count = 0
    swap_information_deltas: list[float] = []
    swap_real_good_and_info_good_count = 0
    swap_real_bad_but_info_good_count = 0
    swap_real_good_but_info_bad_count = 0
    swap_real_bad_and_info_bad_count = 0
    discard_drawn_when_unknown_slots_available = 0
    discard_drawn_that_would_reduce_uncertainty = 0
    discard_drawn_good_score_or_info_opportunity = 0
    discard_drawn_best_target_delta_scores: list[float] = []
    discard_drawn_best_target_info_deltas: list[float] = []
    agent_spy_uses = 0
    agent_swap_power_uses = 0
    agent_joker_uses = 0
    last_episode_diag: dict[str, Any] = {}

    def collect_diagnostics(diag: dict[str, Any]) -> None:
        nonlocal good_swap_count, bad_swap_count, neutral_swap_count
        nonlocal discard_good_drawn_count, discard_bad_drawn_count
        nonlocal self_damage_actions, self_damage_score_delta
        nonlocal known_replace_real_good, known_replace_real_bad
        nonlocal agent_spy_uses, agent_swap_power_uses, agent_joker_uses
        nonlocal unknown_to_known_swap_count, known_to_known_swap_count
        nonlocal known_to_unknown_swap_count, unknown_to_unknown_swap_count
        nonlocal swap_reduced_uncertainty_count, swap_increased_uncertainty_count
        nonlocal swap_kept_uncertainty_same_count
        nonlocal swap_real_good_and_info_good_count
        nonlocal swap_real_bad_but_info_good_count
        nonlocal swap_real_good_but_info_bad_count
        nonlocal swap_real_bad_and_info_bad_count
        nonlocal discard_drawn_when_unknown_slots_available
        nonlocal discard_drawn_that_would_reduce_uncertainty
        nonlocal discard_drawn_good_score_or_info_opportunity
        nonlocal last_episode_diag

        def add_sample(key: str, sink: list[float]) -> None:
            value = diag.get(key)
            if isinstance(value, (int, float)):
                sink.append(float(value))

        add_sample("memory_valid_known_slot_count", valid_known_samples)
        add_sample("memory_stale_known_slot_count", stale_known_samples)
        add_sample("memory_ever_seen_current_hand_count", ever_seen_samples)
        add_sample("memory_current_card_seen_count", current_seen_samples)
        add_sample("score_estimate_error_valid_known_only", err_valid_samples)
        add_sample("score_estimate_error_all_hand", err_all_samples)
        add_sample("memory_truth_accuracy", memory_accuracy_samples)

        episode_diag = diag.get("episode_diagnostics")
        if isinstance(episode_diag, dict):
            last_episode_diag = episode_diag

        action_diag = diag.get("last_action_diagnostics")
        if not isinstance(action_diag, dict):
            return

        kind = action_diag.get("kind")
        delta = action_diag.get("self_score_delta")
        if isinstance(delta, (int, float)):
            if action_diag.get("p0_hand_changed_by_opponent") is True:
                score_deltas_from_opponents.append(float(delta))
            if kind in {"power7_look", "power10_spy", "powerV_swap", "powerJoker"}:
                agent_power_self_deltas.append(float(delta))
            if kind in {"replace", "powerV_swap"}:
                swap_real_deltas.append(float(delta))
                if delta < 0:
                    good_swap_count += 1
                    if kind == "replace" and action_diag.get("replace_current_card_seen_by_agent"):
                        known_replace_real_good += 1
                elif delta > 0:
                    bad_swap_count += 1
                    self_damage_actions += 1
                    self_damage_score_delta += float(delta)
                    if kind == "replace" and action_diag.get("replace_current_card_seen_by_agent"):
                        known_replace_real_bad += 1
                else:
                    neutral_swap_count += 1

        if kind == "replace":
            info_delta = action_diag.get("swap_information_delta")
            if isinstance(info_delta, (int, float)):
                info_delta_f = float(info_delta)
                swap_information_deltas.append(info_delta_f)
                if info_delta_f > 0:
                    swap_reduced_uncertainty_count += 1
                elif info_delta_f < 0:
                    swap_increased_uncertainty_count += 1
                else:
                    swap_kept_uncertainty_same_count += 1
                if isinstance(delta, (int, float)):
                    if delta < 0 and info_delta_f > 0:
                        swap_real_good_and_info_good_count += 1
                    elif delta > 0 and info_delta_f > 0:
                        swap_real_bad_but_info_good_count += 1
                    elif delta < 0 and info_delta_f < 0:
                        swap_real_good_but_info_bad_count += 1
                    elif delta > 0 and info_delta_f < 0:
                        swap_real_bad_and_info_bad_count += 1

            info_class = action_diag.get("swap_information_class")
            if info_class == "unknown_to_known":
                unknown_to_known_swap_count += 1
            elif info_class == "known_to_known":
                known_to_known_swap_count += 1
            elif info_class == "known_to_unknown":
                known_to_unknown_swap_count += 1
            elif info_class == "unknown_to_unknown":
                unknown_to_unknown_swap_count += 1

            drawn = action_diag.get("drawn_card")
            if isinstance(drawn, dict) and isinstance(drawn.get("points"), (int, float)):
                drawn_points_replaced.append(float(drawn["points"]))
        elif kind == "discard_drawn":
            best_delta = action_diag.get("discarded_drawn_improvement_if_swapped")
            if isinstance(best_delta, (int, float)):
                discarded_drawn_improvements.append(float(best_delta))
                if best_delta < 0:
                    discard_good_drawn_count += 1
                else:
                    discard_bad_drawn_count += 1
            best_target_delta = action_diag.get("discard_drawn_best_target_delta_score")
            if isinstance(best_target_delta, (int, float)):
                discard_drawn_best_target_delta_scores.append(float(best_target_delta))
            best_info_delta = action_diag.get("discard_drawn_best_target_info_delta")
            if isinstance(best_info_delta, (int, float)):
                discard_drawn_best_target_info_deltas.append(float(best_info_delta))
            if action_diag.get("unknown_slots_available_before") is True:
                discard_drawn_when_unknown_slots_available += 1
            if action_diag.get("discard_drawn_would_reduce_uncertainty") is True:
                discard_drawn_that_would_reduce_uncertainty += 1
            if action_diag.get("discard_drawn_good_score_or_info_opportunity") is True:
                discard_drawn_good_score_or_info_opportunity += 1

        if kind == "power10_spy":
            agent_spy_uses += 1
        elif kind == "powerV_swap":
            agent_swap_power_uses += 1
        elif kind == "powerJoker":
            agent_joker_uses += 1

        opponent_deltas = action_diag.get("opponent_score_deltas")
        if isinstance(opponent_deltas, dict) and opponent_deltas:
            vals = [float(v) for v in opponent_deltas.values()
                    if isinstance(v, (int, float))]
            if vals:
                agent_power_opponent_deltas.append(sum(vals) / len(vals))

    special_available_count = 0
    special_used_count = 0
    power_available = {"look": 0, "spy": 0, "swap_power": 0, "joker": 0}
    power_used = {"look": 0, "spy": 0, "swap_power": 0, "joker": 0}

    obs: np.ndarray | None = None
    known_score_start: float | None = None
    estimated_score_start: float | None = None
    known_score_end: float | None = None
    estimated_score_end: float | None = None

    done = bool(msg.get("done"))
    if done:
        terminal = msg.get("info", {})
    else:
        obs, mask, diagnostics = _require_observation(msg)
        diagnostics_seen += 1
        collect_diagnostics(diagnostics)
        if msg.get("rewards") is not None:
            reward_seen += 1
        known_score_start = _obs_known_score(obs)
        estimated_score_start = _obs_estimated_score(obs)
        known_score_end = known_score_start
        estimated_score_end = estimated_score_start

    while not done and steps < max_steps_per_game:
        assert obs is not None
        assert known_score_end is not None
        assert estimated_score_end is not None

        availability = _power_availability(mask)
        if _obs_drawn_points(obs) is not None:
            drawn_decisions += 1
        if availability["special"]:
            special_available_count += 1
        for name in power_available:
            if availability[name]:
                power_available[name] += 1

        dutch_legal = bool(mask[encoding._CALL_DUTCH])
        if dutch_legal:
            dutch_legal_decisions += 1
            margin = diagnostics.get("dutch_margin_now")
            natural_rank = diagnostics.get("natural_rank_now")
            maturity_bucket = str(diagnostics.get("maturity_bucket") or "unknown")
            if maturity_bucket not in win_opportunities_by_bucket:
                maturity_bucket = "late"
            if isinstance(margin, (int, float)):
                margins_when_legal.append(float(margin))
            if isinstance(natural_rank, (int, float)):
                ranks_when_legal.append(float(natural_rank))
            if diagnostics.get("dutch_would_win_now") is True:
                dutch_real_win_opportunities += 1
                win_opportunities_by_bucket[maturity_bucket] += 1
                if diagnostics.get("p0_full_hand_known") is True:
                    known_full_hand_win_opportunities += 1
                    if maturity_bucket == "late":
                        known_full_hand_win_opportunities_late += 1
                elif diagnostics.get("p0_partial_hand_known") is True:
                    partial_known_hand_win_opportunities += 1
                elif diagnostics.get("p0_low_hand_known") is True:
                    low_known_hand_win_opportunities += 1
            if diagnostics.get("top_half_now") is True:
                dutch_real_top_half_opportunities += 1

        action, _ = model.predict(
            obs,
            deterministic=deterministic,
            action_masks=mask,
        )
        action = int(action)
        kind = encoding.action_to_message(action).get("kind")
        agent_called_now = action == encoding._CALL_DUTCH

        if dutch_legal:
            would_win = diagnostics.get("dutch_would_win_now") is True
            top_half = diagnostics.get("top_half_now") is True
            maturity_bucket = str(diagnostics.get("maturity_bucket") or "unknown")
            if maturity_bucket not in missed_opportunities_by_bucket:
                maturity_bucket = "late"
            if agent_called_now:
                dutch_calls += 1
                if would_win:
                    dutch_call_when_winning_opportunity += 1
                else:
                    dutch_call_when_losing_position += 1
            else:
                margin = diagnostics.get("dutch_margin_now")
                natural_rank = diagnostics.get("natural_rank_now")
                if isinstance(margin, (int, float)):
                    margins_when_missed.append(float(margin))
                if isinstance(natural_rank, (int, float)):
                    ranks_when_missed.append(float(natural_rank))
                if would_win:
                    dutch_missed_win_opportunities += 1
                    missed_opportunities_by_bucket[maturity_bucket] += 1
                    if isinstance(margin, (int, float)):
                        missed_margins_by_bucket[maturity_bucket].append(float(margin))
                    if diagnostics.get("p0_full_hand_known") is True:
                        missed_known_full_hand_win_opportunities += 1
                        if maturity_bucket == "late":
                            missed_known_full_hand_win_late += 1
                            if isinstance(margin, (int, float)):
                                missed_known_full_hand_late_margins.append(
                                    float(margin)
                                )
                    elif diagnostics.get("p0_partial_hand_known") is True:
                        missed_partial_known_hand_win_opportunities += 1
                    elif diagnostics.get("p0_low_hand_known") is True:
                        missed_low_known_hand_win_opportunities += 1
                    clear_missed_non_call_count += 1
                elif top_half:
                    cautious_non_call_count += 1
                else:
                    justified_non_call_count += 1
                if top_half:
                    dutch_missed_top_half_opportunities += 1

        if action == encoding._DISCARD_DRAWN:
            discard_drawn_count += 1
            drawn = _obs_drawn_points(obs)
            if drawn is not None:
                discarded_drawn_points.append(drawn)
            proxy = _discard_better_than_known_hand_proxy(obs)
            if proxy is True:
                discarded_better_proxy += 1
        elif encoding._REPLACE <= action < encoding._REPLACE + encoding.MAX_HAND:
            replace_count += 1
            proxy_good = _is_known_replace_proxy_good(obs, action)
            if proxy_good is True:
                known_replace_proxy_good += 1
            elif proxy_good is False:
                known_replace_proxy_bad += 1

        if kind == "power7_look":
            special_used_count += 1
            power_used["look"] += 1
        elif kind == "power10_spy":
            special_used_count += 1
            power_used["spy"] += 1
        elif kind == "powerV_swap":
            special_used_count += 1
            power_used["swap_power"] += 1
        elif kind == "powerJoker":
            special_used_count += 1
            power_used["joker"] += 1

        try:
            msg = runner.step(encoding.action_to_message(action))
        except (RunnerCrashed, RunnerTimeout) as exc:
            aborted = True
            abort_reason = str(exc)
            break

        steps += 1
        if msg.get("type") == "error":
            aborted = True
            abort_reason = str(msg)
            break
        done = bool(msg.get("done"))
        if done:
            terminal = msg.get("info", {})
            terminal_diag = msg.get("diagnostics")
            if isinstance(terminal_diag, dict):
                collect_diagnostics(terminal_diag)
            if msg.get("rewards") is not None:
                reward_seen += 1
            break

        obs, mask, diagnostics = _require_observation(msg)
        diagnostics_seen += 1
        collect_diagnostics(diagnostics)
        if msg.get("rewards") is not None:
            reward_seen += 1
        known_score_end = _obs_known_score(obs)
        estimated_score_end = _obs_estimated_score(obs)

    if not done and not aborted:
        aborted = True
        abort_reason = "max_steps_per_game"

    agent_called_dutch = dutch_calls > 0
    call_metrics = (
        _terminal_call_metrics(terminal, agent_called_dutch=agent_called_dutch)
        if not aborted
        else {
            "self_score_at_call": None,
            "best_opponent_score_at_call": None,
            "dutch_margin_at_call": None,
            "dutch_bad_call": None,
        }
    )
    called_dutch = agent_called_dutch if not aborted else None
    won = bool(terminal.get("won")) if not aborted else None
    dutch_success = (won and called_dutch) if not aborted else None

    return {
        "skill": skill,
        "num_players": num_players,
        "seed": seed,
        "episode_index": episode_index,
        "aborted": aborted,
        "abort_reason": abort_reason,
        "won": won,
        "rank": terminal.get("rank") if not aborted else None,
        "final_score_p0": (terminal.get("final_scores") or {}).get("p0")
        if not aborted else None,
        "episode_length": terminal.get("length") if not aborted else steps,
        "steps": steps,
        "dutch_legal_decisions": dutch_legal_decisions,
        "dutch_calls": dutch_calls,
        "dutch_call_rate_when_legal": _safe_rate(dutch_calls, dutch_legal_decisions),
        "called_dutch": called_dutch,
        "dutch_success": dutch_success,
        "dutch_bad_call": call_metrics["dutch_bad_call"],
        "dutch_margin_at_call": call_metrics["dutch_margin_at_call"],
        "self_score_at_call": call_metrics["self_score_at_call"],
        "best_opponent_score_at_call": call_metrics["best_opponent_score_at_call"],
        "dutch_real_win_opportunities": dutch_real_win_opportunities,
        "dutch_real_top_half_opportunities": dutch_real_top_half_opportunities,
        "dutch_missed_win_opportunities": dutch_missed_win_opportunities,
        "dutch_missed_top_half_opportunities": dutch_missed_top_half_opportunities,
        "dutch_call_when_winning_opportunity": dutch_call_when_winning_opportunity,
        "dutch_call_when_losing_position": dutch_call_when_losing_position,
        "mean_dutch_margin_when_legal": _finite_mean(margins_when_legal),
        "mean_dutch_margin_when_missed": _finite_mean(margins_when_missed),
        "max_dutch_margin_missed": max(margins_when_missed)
        if margins_when_missed else None,
        "mean_natural_rank_when_legal": _finite_mean(ranks_when_legal),
        "mean_natural_rank_when_missed": _finite_mean(ranks_when_missed),
        "dutch_win_opportunities_early": win_opportunities_by_bucket["early"],
        "dutch_win_opportunities_mid": win_opportunities_by_bucket["mid"],
        "dutch_win_opportunities_late": win_opportunities_by_bucket["late"],
        "missed_win_opportunities_early": missed_opportunities_by_bucket["early"],
        "missed_win_opportunities_mid": missed_opportunities_by_bucket["mid"],
        "missed_win_opportunities_late": missed_opportunities_by_bucket["late"],
        "missed_win_rate_early": _safe_rate(
            missed_opportunities_by_bucket["early"],
            win_opportunities_by_bucket["early"],
        ),
        "missed_win_rate_mid": _safe_rate(
            missed_opportunities_by_bucket["mid"],
            win_opportunities_by_bucket["mid"],
        ),
        "missed_win_rate_late": _safe_rate(
            missed_opportunities_by_bucket["late"],
            win_opportunities_by_bucket["late"],
        ),
        "mean_margin_missed_early": _finite_mean(
            missed_margins_by_bucket["early"]
        ),
        "mean_margin_missed_mid": _finite_mean(missed_margins_by_bucket["mid"]),
        "mean_margin_missed_late": _finite_mean(
            missed_margins_by_bucket["late"]
        ),
        "max_margin_missed_early": max(missed_margins_by_bucket["early"])
        if missed_margins_by_bucket["early"] else None,
        "max_margin_missed_mid": max(missed_margins_by_bucket["mid"])
        if missed_margins_by_bucket["mid"] else None,
        "max_margin_missed_late": max(missed_margins_by_bucket["late"])
        if missed_margins_by_bucket["late"] else None,
        "known_full_hand_win_opportunities": known_full_hand_win_opportunities,
        "missed_known_full_hand_win_opportunities":
            missed_known_full_hand_win_opportunities,
        "missed_known_full_hand_win_rate": _safe_rate(
            missed_known_full_hand_win_opportunities,
            known_full_hand_win_opportunities,
        ),
        "partial_known_hand_win_opportunities": partial_known_hand_win_opportunities,
        "missed_partial_known_hand_win_opportunities":
            missed_partial_known_hand_win_opportunities,
        "missed_partial_known_hand_win_rate": _safe_rate(
            missed_partial_known_hand_win_opportunities,
            partial_known_hand_win_opportunities,
        ),
        "low_known_hand_win_opportunities": low_known_hand_win_opportunities,
        "missed_low_known_hand_win_opportunities":
            missed_low_known_hand_win_opportunities,
        "missed_low_known_hand_win_rate": _safe_rate(
            missed_low_known_hand_win_opportunities,
            low_known_hand_win_opportunities,
        ),
        "known_full_hand_win_opportunities_late":
            known_full_hand_win_opportunities_late,
        "missed_known_full_hand_win_late": missed_known_full_hand_win_late,
        "missed_known_full_hand_win_rate_late": _safe_rate(
            missed_known_full_hand_win_late,
            known_full_hand_win_opportunities_late,
        ),
        "mean_margin_missed_known_full_hand_late": _finite_mean(
            missed_known_full_hand_late_margins
        ),
        "justified_non_call_count": justified_non_call_count,
        "cautious_non_call_count": cautious_non_call_count,
        "clear_missed_non_call_count": clear_missed_non_call_count,
        "discard_drawn_count": discard_drawn_count,
        "discarded_drawn_points_mean": _finite_mean(discarded_drawn_points),
        "replace_count": replace_count,
        "discarded_better_than_known_hand_proxy": discarded_better_proxy,
        "known_replace_proxy_good": known_replace_proxy_good,
        "known_replace_proxy_bad": known_replace_proxy_bad,
        "drawn_decisions": drawn_decisions,
        "replace_rate_when_drawn": _safe_rate(replace_count, drawn_decisions),
        "discard_drawn_rate": _safe_rate(discard_drawn_count, drawn_decisions),
        "mean_drawn_points_replaced": _finite_mean(drawn_points_replaced),
        "mean_drawn_points_discarded": _finite_mean(discarded_drawn_points),
        "good_swap_count": good_swap_count,
        "bad_swap_count": bad_swap_count,
        "neutral_swap_count": neutral_swap_count,
        "mean_swap_real_delta_score": _finite_mean(swap_real_deltas),
        "bad_swap_rate": _safe_rate(
            bad_swap_count,
            good_swap_count + bad_swap_count + neutral_swap_count,
        ),
        "discard_good_drawn_count": discard_good_drawn_count,
        "discard_bad_drawn_count": discard_bad_drawn_count,
        "mean_discarded_drawn_improvement_if_swapped": _finite_mean(
            discarded_drawn_improvements
        ),
        "valid_known_slot_count_start": valid_known_samples[0]
        if valid_known_samples else None,
        "valid_known_slot_count_end": valid_known_samples[-1]
        if valid_known_samples else None,
        "valid_known_slot_count_mean": _finite_mean(valid_known_samples),
        "stale_known_slot_count_mean": _finite_mean(stale_known_samples),
        "ever_seen_current_hand_count_mean": _finite_mean(ever_seen_samples),
        "current_card_seen_by_agent_count_mean": _finite_mean(current_seen_samples),
        "p0_known_card_invalidated_by_opponent": last_episode_diag.get(
            "p0_known_card_invalidated_by_opponent"
        ),
        "p0_memory_disruption_count": last_episode_diag.get(
            "p0_memory_disruption_count"
        ),
        "score_estimate_error_valid_known_only_mean": _finite_mean(
            err_valid_samples
        ),
        "score_estimate_error_all_hand_mean": _finite_mean(err_all_samples),
        "memory_truth_accuracy_mean": _finite_mean(memory_accuracy_samples),
        "times_p0_cards_changed_by_opponents": last_episode_diag.get(
            "p0_cards_changed_by_opponents"
        ),
        "mean_score_delta_from_opponent_actions": _finite_mean(
            score_deltas_from_opponents
        ),
        "agent_spy_uses": agent_spy_uses,
        "agent_swap_power_uses": agent_swap_power_uses,
        "agent_joker_uses": agent_joker_uses,
        "agent_offensive_actions_count": last_episode_diag.get(
            "agent_offensive_actions"
        ),
        "agent_targets_unique_opponents": last_episode_diag.get(
            "agent_targets_unique_opponents"
        ),
        "mean_agent_score_delta_from_power": _finite_mean(agent_power_self_deltas),
        "mean_opponent_score_delta_from_power": _finite_mean(
            agent_power_opponent_deltas
        ),
        "self_damage_actions": self_damage_actions,
        "self_damage_score_delta": self_damage_score_delta,
        "known_replace_real_good": known_replace_real_good,
        "known_replace_real_bad": known_replace_real_bad,
        "unknown_to_known_swap_count": unknown_to_known_swap_count,
        "known_to_known_swap_count": known_to_known_swap_count,
        "known_to_unknown_swap_count": known_to_unknown_swap_count,
        "unknown_to_unknown_swap_count": unknown_to_unknown_swap_count,
        "swap_reduced_uncertainty_count": swap_reduced_uncertainty_count,
        "swap_increased_uncertainty_count": swap_increased_uncertainty_count,
        "swap_kept_uncertainty_same_count": swap_kept_uncertainty_same_count,
        "mean_swap_information_delta": _finite_mean(swap_information_deltas),
        "swap_real_good_and_info_good_count": swap_real_good_and_info_good_count,
        "swap_real_bad_but_info_good_count": swap_real_bad_but_info_good_count,
        "swap_real_good_but_info_bad_count": swap_real_good_but_info_bad_count,
        "swap_real_bad_and_info_bad_count": swap_real_bad_and_info_bad_count,
        "discard_drawn_when_unknown_slots_available":
            discard_drawn_when_unknown_slots_available,
        "discard_drawn_that_would_reduce_uncertainty":
            discard_drawn_that_would_reduce_uncertainty,
        "discard_drawn_good_score_or_info_opportunity":
            discard_drawn_good_score_or_info_opportunity,
        "discard_drawn_best_target_delta_score_mean": _finite_mean(
            discard_drawn_best_target_delta_scores
        ),
        "discard_drawn_best_target_info_delta_mean": _finite_mean(
            discard_drawn_best_target_info_deltas
        ),
        "special_available_count": special_available_count,
        "special_used_count": special_used_count,
        "look_available_count": power_available["look"],
        "look_used_count": power_used["look"],
        "spy_available_count": power_available["spy"],
        "spy_used_count": power_used["spy"],
        "swap_power_available_count": power_available["swap_power"],
        "swap_power_used_count": power_used["swap_power"],
        "joker_available_count": power_available["joker"],
        "joker_used_count": power_used["joker"],
        "known_score_start": known_score_start,
        "known_score_end": known_score_end,
        "estimated_score_start": estimated_score_start,
        "estimated_score_end": estimated_score_end,
        "estimated_score_delta": (
            estimated_score_end - estimated_score_start
            if estimated_score_start is not None and estimated_score_end is not None
            else None
        ),
        "diagnostics_seen": diagnostics_seen,
        "obs_dim": encoding.OBS_DIM,
        "reward_seen": reward_seen,
    }


def _aborted_row(
    skill: str, num_players: int, seed: int, episode_index: int, reason: str
) -> dict[str, Any]:
    row = {key: None for key in CSV_COLUMNS}
    row.update(
        skill=skill,
        num_players=num_players,
        seed=seed,
        episode_index=episode_index,
        aborted=True,
        abort_reason=reason,
        diagnostics_seen=0,
        obs_dim=encoding.OBS_DIM,
        reward_seen=0,
    )
    return row


def _aggregate(rows: list[dict[str, Any]]) -> dict[str, Any]:
    valid = [r for r in rows if not r["aborted"]]
    calls = [r for r in valid if r["called_dutch"]]

    def isum(key: str) -> int:
        return sum(int(r[key] or 0) for r in valid)

    def count_true(key: str, source: list[dict[str, Any]] = valid) -> int:
        return sum(1 for r in source if r.get(key) is True)

    special_available = isum("special_available_count")
    return {
        "games": len(valid),
        "aborted": len(rows) - len(valid),
        "win_rate": _finite_mean([1.0 if r["won"] else 0.0 for r in valid]),
        "mean_rank": _finite_mean([r["rank"] for r in valid]),
        "dutch_call_rate_when_legal": _safe_rate(
            isum("dutch_calls"), isum("dutch_legal_decisions")
        ),
        "dutch_success_rate_when_called": _safe_rate(
            count_true("dutch_success", calls), len(calls)
        ),
        "dutch_bad_call_rate": _safe_rate(count_true("dutch_bad_call", calls), len(calls)),
        "real_win_opportunities": isum("dutch_real_win_opportunities"),
        "missed_win_opportunities": isum("dutch_missed_win_opportunities"),
        "missed_win_rate": _safe_rate(
            isum("dutch_missed_win_opportunities"),
            isum("dutch_real_win_opportunities"),
        ),
        "top_half_opportunities": isum("dutch_real_top_half_opportunities"),
        "missed_top_half_opportunities": isum("dutch_missed_top_half_opportunities"),
        "justified_non_calls": isum("justified_non_call_count"),
        "cautious_non_calls": isum("cautious_non_call_count"),
        "clear_missed_non_calls": isum("clear_missed_non_call_count"),
        "mean_margin_legal": _finite_mean(
            [r["mean_dutch_margin_when_legal"] for r in valid]
        ),
        "mean_margin_missed": _finite_mean(
            [r["mean_dutch_margin_when_missed"] for r in valid]
        ),
        "max_margin_missed": max(
            [float(r["max_dutch_margin_missed"]) for r in valid
             if r["max_dutch_margin_missed"] is not None],
            default=None,
        ),
        "mean_natural_rank_legal": _finite_mean(
            [r["mean_natural_rank_when_legal"] for r in valid]
        ),
        "win_opp_early": isum("dutch_win_opportunities_early"),
        "win_opp_mid": isum("dutch_win_opportunities_mid"),
        "win_opp_late": isum("dutch_win_opportunities_late"),
        "missed_early": isum("missed_win_opportunities_early"),
        "missed_mid": isum("missed_win_opportunities_mid"),
        "missed_late": isum("missed_win_opportunities_late"),
        "missed_rate_early": _safe_rate(
            isum("missed_win_opportunities_early"),
            isum("dutch_win_opportunities_early"),
        ),
        "missed_rate_mid": _safe_rate(
            isum("missed_win_opportunities_mid"),
            isum("dutch_win_opportunities_mid"),
        ),
        "missed_rate_late": _safe_rate(
            isum("missed_win_opportunities_late"),
            isum("dutch_win_opportunities_late"),
        ),
        "mean_margin_missed_early": _finite_mean(
            [r["mean_margin_missed_early"] for r in valid]
        ),
        "mean_margin_missed_mid": _finite_mean(
            [r["mean_margin_missed_mid"] for r in valid]
        ),
        "mean_margin_missed_late": _finite_mean(
            [r["mean_margin_missed_late"] for r in valid]
        ),
        "max_margin_missed_early": max(
            [float(r["max_margin_missed_early"]) for r in valid
             if r["max_margin_missed_early"] is not None],
            default=None,
        ),
        "max_margin_missed_mid": max(
            [float(r["max_margin_missed_mid"]) for r in valid
             if r["max_margin_missed_mid"] is not None],
            default=None,
        ),
        "max_margin_missed_late": max(
            [float(r["max_margin_missed_late"]) for r in valid
             if r["max_margin_missed_late"] is not None],
            default=None,
        ),
        "known_full_hand_win_opportunities": isum(
            "known_full_hand_win_opportunities"
        ),
        "missed_known_full_hand_win_opportunities": isum(
            "missed_known_full_hand_win_opportunities"
        ),
        "missed_known_full_hand_win_rate": _safe_rate(
            isum("missed_known_full_hand_win_opportunities"),
            isum("known_full_hand_win_opportunities"),
        ),
        "partial_known_hand_win_opportunities": isum(
            "partial_known_hand_win_opportunities"
        ),
        "missed_partial_known_hand_win_opportunities": isum(
            "missed_partial_known_hand_win_opportunities"
        ),
        "low_known_hand_win_opportunities": isum("low_known_hand_win_opportunities"),
        "missed_low_known_hand_win_opportunities": isum(
            "missed_low_known_hand_win_opportunities"
        ),
        "known_full_hand_win_opportunities_late": isum(
            "known_full_hand_win_opportunities_late"
        ),
        "missed_known_full_hand_win_late": isum(
            "missed_known_full_hand_win_late"
        ),
        "missed_known_full_hand_win_rate_late": _safe_rate(
            isum("missed_known_full_hand_win_late"),
            isum("known_full_hand_win_opportunities_late"),
        ),
        "mean_margin_missed_known_full_hand_late": _finite_mean(
            [r["mean_margin_missed_known_full_hand_late"] for r in valid]
        ),
        "replace_rate": _safe_rate(isum("replace_count"), isum("drawn_decisions")),
        "good_swap_rate": _safe_rate(
            isum("good_swap_count"),
            isum("good_swap_count") + isum("bad_swap_count") + isum("neutral_swap_count"),
        ),
        "bad_swap_rate": _safe_rate(
            isum("bad_swap_count"),
            isum("good_swap_count") + isum("bad_swap_count") + isum("neutral_swap_count"),
        ),
        "discard_good_drawn_rate": _safe_rate(
            isum("discard_good_drawn_count"),
            isum("discard_good_drawn_count") + isum("discard_bad_drawn_count"),
        ),
        "mean_swap_delta": _finite_mean(
            [r["mean_swap_real_delta_score"] for r in valid]
        ),
        "mean_estimation_error": _finite_mean(
            [r["score_estimate_error_all_hand_mean"] for r in valid]
        ),
        "valid_known_slot_count_mean": _finite_mean(
            [r["valid_known_slot_count_mean"] for r in valid]
        ),
        "stale_known_slot_count_mean": _finite_mean(
            [r["stale_known_slot_count_mean"] for r in valid]
        ),
        "p0_disruption_count": isum("p0_memory_disruption_count"),
        "memory_invalidations": isum("p0_known_card_invalidated_by_opponent"),
        "offensive_action_rate": _safe_rate(
            isum("agent_offensive_actions_count"), isum("special_available_count")
        ),
        "self_damage_rate": _safe_rate(
            isum("self_damage_actions"),
            isum("replace_count") + isum("agent_swap_power_uses"),
        ),
        "unknown_to_known_swap_count": isum("unknown_to_known_swap_count"),
        "known_to_known_swap_count": isum("known_to_known_swap_count"),
        "known_to_unknown_swap_count": isum("known_to_unknown_swap_count"),
        "unknown_to_unknown_swap_count": isum("unknown_to_unknown_swap_count"),
        "swap_reduced_uncertainty_count": isum("swap_reduced_uncertainty_count"),
        "swap_increased_uncertainty_count": isum(
            "swap_increased_uncertainty_count"
        ),
        "swap_kept_uncertainty_same_count": isum(
            "swap_kept_uncertainty_same_count"
        ),
        "mean_swap_information_delta": _finite_mean(
            [r["mean_swap_information_delta"] for r in valid]
        ),
        "swap_real_good_and_info_good_count": isum(
            "swap_real_good_and_info_good_count"
        ),
        "swap_real_bad_but_info_good_count": isum(
            "swap_real_bad_but_info_good_count"
        ),
        "swap_real_good_but_info_bad_count": isum(
            "swap_real_good_but_info_bad_count"
        ),
        "swap_real_bad_and_info_bad_count": isum(
            "swap_real_bad_and_info_bad_count"
        ),
        "discard_drawn_when_unknown_slots_available": isum(
            "discard_drawn_when_unknown_slots_available"
        ),
        "discard_drawn_that_would_reduce_uncertainty": isum(
            "discard_drawn_that_would_reduce_uncertainty"
        ),
        "discard_drawn_good_score_or_info_opportunity": isum(
            "discard_drawn_good_score_or_info_opportunity"
        ),
        "discard_drawn_best_target_delta_score_mean": _finite_mean(
            [r["discard_drawn_best_target_delta_score_mean"] for r in valid]
        ),
        "discard_drawn_best_target_info_delta_mean": _finite_mean(
            [r["discard_drawn_best_target_info_delta_mean"] for r in valid]
        ),
        "special_usage_rate_when_available": _safe_rate(
            isum("special_used_count"), special_available
        ),
        "estimated_score_delta": _finite_mean(
            [r["estimated_score_delta"] for r in valid]
        ),
        "diagnostics_seen": isum("diagnostics_seen"),
        "reward_seen": isum("reward_seen"),
    }


def _fmt_pct(value: float | None) -> str:
    return "n/a" if value is None else f"{100.0 * value:5.1f}%"


def _fmt_num(value: float | None, digits: int = 2) -> str:
    return "n/a" if value is None else f"{value:.{digits}f}"


def print_report(rows: list[dict[str, Any]], skills: list[str], nums: list[int]) -> None:
    print("\n" + "=" * 150)
    print("RAPPORT COMPORTEMENTAL V3 - diagnostics décisionnels eval-only")
    print("=" * 150)
    print(
        f"{'skill':<10} {'n':>2} {'games':>5} {'win%':>7} {'rank':>6} "
        f"{'missE/M/L':>11} {'missFull':>8} {'missLate':>8} "
        f"{'unk2kn':>6} {'info+':>6} {'bad+info':>8} {'discInfo':>8} "
        f"{'infoΔ':>7} {'swΔ':>7} {'err':>7}"
    )
    print("-" * 150)

    grouped: dict[tuple[str, int], list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        grouped[(str(row["skill"]), int(row["num_players"]))].append(row)

    for skill in skills:
        for num_players in nums:
            agg = _aggregate(grouped[(skill, num_players)])
            print(
                f"{skill:<10} {num_players:>2} {agg['games']:>5} "
                f"{_fmt_pct(agg['win_rate']):>7} "
                f"{_fmt_num(agg['mean_rank']):>6} "
                f"{agg['missed_early']}/{agg['missed_mid']}/{agg['missed_late']:>3} "
                f"{agg['missed_known_full_hand_win_opportunities']:>8} "
                f"{agg['missed_known_full_hand_win_late']:>8} "
                f"{agg['unknown_to_known_swap_count']:>6} "
                f"{agg['swap_reduced_uncertainty_count']:>6} "
                f"{agg['swap_real_bad_but_info_good_count']:>8} "
                f"{agg['discard_drawn_good_score_or_info_opportunity']:>8} "
                f"{_fmt_num(agg['mean_swap_information_delta']):>7} "
                f"{_fmt_num(agg['mean_swap_delta']):>7} "
                f"{_fmt_num(agg['mean_estimation_error']):>7}"
            )
        print("-" * 150)

    global_agg = _aggregate(rows)
    print("\nGLOBAL")
    print(f"  games valides                    : {global_agg['games']}")
    print(f"  parties abandonnées              : {global_agg['aborted']}")
    print(f"  win_rate                         : {_fmt_pct(global_agg['win_rate'])}")
    print(f"  mean_rank                        : {_fmt_num(global_agg['mean_rank'])}")
    print(
        "  dutch_call_rate_when_legal       : "
        f"{_fmt_pct(global_agg['dutch_call_rate_when_legal'])}"
    )
    print(f"  real win opportunities           : {global_agg['real_win_opportunities']}")
    print(f"  missed win opportunities         : {global_agg['missed_win_opportunities']}")
    print(f"  missed win opportunity rate      : {_fmt_pct(global_agg['missed_win_rate'])}")
    print(
        "  missed win early/mid/late        : "
        f"{global_agg['missed_early']} / {global_agg['missed_mid']} / "
        f"{global_agg['missed_late']}"
    )
    print(
        "  missed win rate early/mid/late   : "
        f"{_fmt_pct(global_agg['missed_rate_early'])} / "
        f"{_fmt_pct(global_agg['missed_rate_mid'])} / "
        f"{_fmt_pct(global_agg['missed_rate_late'])}"
    )
    print(
        "  mean missed margin early/mid/late: "
        f"{_fmt_num(global_agg['mean_margin_missed_early'])} / "
        f"{_fmt_num(global_agg['mean_margin_missed_mid'])} / "
        f"{_fmt_num(global_agg['mean_margin_missed_late'])}"
    )
    print(
        "  max missed margin early/mid/late : "
        f"{_fmt_num(global_agg['max_margin_missed_early'])} / "
        f"{_fmt_num(global_agg['max_margin_missed_mid'])} / "
        f"{_fmt_num(global_agg['max_margin_missed_late'])}"
    )
    print(
        "  known-full win opp/missed        : "
        f"{global_agg['known_full_hand_win_opportunities']} / "
        f"{global_agg['missed_known_full_hand_win_opportunities']}"
    )
    print(
        "  known-full late opp/missed       : "
        f"{global_agg['known_full_hand_win_opportunities_late']} / "
        f"{global_agg['missed_known_full_hand_win_late']}"
    )
    print(
        "  missed known-full late margin    : "
        f"{_fmt_num(global_agg['mean_margin_missed_known_full_hand_late'])}"
    )
    print(f"  real top-half opportunities      : {global_agg['top_half_opportunities']}")
    print(
        "  missed top-half opportunities    : "
        f"{global_agg['missed_top_half_opportunities']}"
    )
    print(f"  justified non-calls              : {global_agg['justified_non_calls']}")
    print(f"  cautious non-calls               : {global_agg['cautious_non_calls']}")
    print(f"  clear missed non-calls           : {global_agg['clear_missed_non_calls']}")
    print(f"  mean margin when legal           : {_fmt_num(global_agg['mean_margin_legal'])}")
    print(f"  mean margin when missed          : {_fmt_num(global_agg['mean_margin_missed'])}")
    print(f"  max margin missed                : {_fmt_num(global_agg['max_margin_missed'])}")
    print(
        "  mean natural rank when legal     : "
        f"{_fmt_num(global_agg['mean_natural_rank_legal'])}"
    )
    print(
        "  special_usage_rate_when_avail    : "
        f"{_fmt_pct(global_agg['special_usage_rate_when_available'])}"
    )
    print(f"  estimated_score_delta moyen      : {_fmt_num(global_agg['estimated_score_delta'])}")
    print(f"  replace_rate                     : {_fmt_pct(global_agg['replace_rate'])}")
    print(f"  good_swap_rate                   : {_fmt_pct(global_agg['good_swap_rate'])}")
    print(f"  bad_swap_rate                    : {_fmt_pct(global_agg['bad_swap_rate'])}")
    print(
        "  discard_good_drawn_rate          : "
        f"{_fmt_pct(global_agg['discard_good_drawn_rate'])}"
    )
    print(f"  mean_swap_delta                  : {_fmt_num(global_agg['mean_swap_delta'])}")
    print(
        "  mean_estimation_error            : "
        f"{_fmt_num(global_agg['mean_estimation_error'])}"
    )
    print(
        "  valid_known_slot_count_mean      : "
        f"{_fmt_num(global_agg['valid_known_slot_count_mean'])}"
    )
    print(
        "  stale_known_slot_count_mean      : "
        f"{_fmt_num(global_agg['stale_known_slot_count_mean'])}"
    )
    print(f"  p0_disruption_count              : {global_agg['p0_disruption_count']}")
    print(f"  memory_invalidations             : {global_agg['memory_invalidations']}")
    print(f"  offensive_action_rate            : {_fmt_pct(global_agg['offensive_action_rate'])}")
    print(f"  self_damage_rate                 : {_fmt_pct(global_agg['self_damage_rate'])}")
    print(
        "  unknown_to_known_swaps           : "
        f"{global_agg['unknown_to_known_swap_count']}"
    )
    print(
        "  swap_reduced_uncertainty         : "
        f"{global_agg['swap_reduced_uncertainty_count']}"
    )
    print(
        "  swap_real_bad_but_info_good      : "
        f"{global_agg['swap_real_bad_but_info_good_count']}"
    )
    print(
        "  mean_swap_information_delta      : "
        f"{_fmt_num(global_agg['mean_swap_information_delta'])}"
    )
    print(
        "  discard_drawn_info_opportunity   : "
        f"{global_agg['discard_drawn_good_score_or_info_opportunity']}"
    )
    print(
        "  discard_drawn_reduce_uncertainty : "
        f"{global_agg['discard_drawn_that_would_reduce_uncertainty']}"
    )
    print(f"  diagnostics_seen                 : {global_agg['diagnostics_seen']}")
    print(f"  reward_seen                      : {global_agg['reward_seen']}")


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_COLUMNS)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Évaluation comportementale V3 avec diagnostics décisionnels."
    )
    parser.add_argument("--model", required=True, help="Chemin du checkpoint .zip.")
    parser.add_argument("--exe", required=True, help="Binaire behavior runner.")
    parser.add_argument("--games", type=int, default=DEFAULT_GAMES)
    parser.add_argument("--out", default=DEFAULT_OUT)
    parser.add_argument("--skills", default=",".join(DEFAULT_SKILLS))
    parser.add_argument("--num-players", default=",".join(map(str, DEFAULT_NUM_PLAYERS)))
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--deterministic", action=argparse.BooleanOptionalAction,
                        default=True)
    parser.add_argument("--max-steps-per-game", type=int, default=10_000)
    parser.add_argument("--timeout", type=float, default=30.0)
    args = parser.parse_args()

    if args.games <= 0:
        raise SystemExit("--games doit être positif")
    if args.max_steps_per_game <= 0:
        raise SystemExit("--max-steps-per-game doit être positif")
    if encoding.OBS_DIM != 146:
        raise SystemExit(f"OBS_DIM inattendu: {encoding.OBS_DIM}")

    model_path = Path(args.model)
    exe_path = Path(args.exe)
    if not model_path.exists():
        raise SystemExit(f"Modèle introuvable: {model_path}")
    if not exe_path.exists():
        raise SystemExit(f"Runner behavior introuvable: {exe_path}")

    skills = _parse_csv_values(args.skills, DEFAULT_SKILLS, name="skills")
    nums = _parse_num_players(args.num_players)

    print("Métriques V3: diagnostics décisionnels eval-only, hors observation/reward.")
    print(f"OBS_DIM={encoding.OBS_DIM}")
    print(f"[load] {model_path}")
    model = MaskablePPO.load(str(model_path), device="cpu")
    model_obs_dim = int(model.observation_space.shape[0])
    if model_obs_dim != encoding.OBS_DIM:
        raise SystemExit(
            f"Checkpoint incompatible: obs_dim={model_obs_dim}, "
            f"OBS_DIM courant={encoding.OBS_DIM}."
        )

    rows: list[dict[str, Any]] = []
    episode_index = 0
    for skill_i, skill in enumerate(skills):
        for num_i, num_players in enumerate(nums):
            seed_start = args.seed + (skill_i * len(nums) + num_i) * args.games
            runner = RunnerProcess(exe_path=exe_path, max_turns=MAX_TURNS,
                                   timeout=args.timeout)
            try:
                for game_i in range(args.games):
                    row = play_one_game(
                        runner,
                        model,
                        skill=skill,
                        num_players=num_players,
                        seed=seed_start + game_i,
                        episode_index=episode_index,
                        deterministic=bool(args.deterministic),
                        max_steps_per_game=int(args.max_steps_per_game),
                    )
                    rows.append(row)
                    episode_index += 1
            finally:
                runner.close(quiet=True)

    out_path = Path(args.out)
    write_csv(out_path, rows)
    print_report(rows, skills, nums)
    print(f"\nCSV écrit: {out_path} ({len(rows)} lignes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
