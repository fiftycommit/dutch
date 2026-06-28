"""Évaluation comportementale offline pour Dutch'78 RL.

V1 volontairement ultra sûre : ce script ne modifie ni l'observation, ni la
reward, ni le runner Dart. Il consomme uniquement les informations déjà
disponibles côté Python (`DutchEnv`, masques d'action, observation encodée et
infos terminales).

Conséquence importante : les opportunités Dutch manquées réelles et les deltas
réels de swap/discard nécessitent les scores/cartes privées courantes côté
runner. Ils sont listés dans le rapport comme métriques V2 indisponibles, et ne
sont pas simulés ici.
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
from dutch_env import DutchEnv


DEFAULT_SKILLS = ("bronze", "silver", "difficile")
DEFAULT_NUM_PLAYERS = (2, 3, 4, 5, 6)
OPPONENT_BEHAVIOR = "balanced"
MAX_TURNS = 500
DEFAULT_GAMES = 1
DEFAULT_OUT = "behavior_report.csv"
ABORT_KEYS = ("runner_crashed", "runner_timeout", "engine_recoverable_error")

# Indices d'observation confirmés dans encoding.encode_observation().
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
    "discard_drawn_count",
    "discarded_drawn_points_mean",
    "replace_count",
    "discarded_better_than_known_hand_proxy",
    "known_replace_proxy_good",
    "known_replace_proxy_bad",
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
    """Proxy strict : ne juge un replace que si la carte remplacée est connue."""
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
    """Proxy : discard d'une pioche meilleure que la pire carte connue."""
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


def play_one_game(
    env: DutchEnv,
    model: MaskablePPO,
    *,
    skill: str,
    num_players: int,
    episode_index: int,
    deterministic: bool,
    max_steps_per_game: int,
) -> dict[str, Any]:
    obs, info = env.reset()
    seed = info.get("seed")

    known_score_start = _obs_known_score(obs)
    estimated_score_start = _obs_estimated_score(obs)
    known_score_end = known_score_start
    estimated_score_end = estimated_score_start

    dutch_legal_decisions = 0
    dutch_calls = 0
    discard_drawn_count = 0
    discarded_drawn_points: list[float] = []
    replace_count = 0
    discarded_better_proxy = 0
    known_replace_proxy_good = 0
    known_replace_proxy_bad = 0

    special_available_count = 0
    special_used_count = 0
    power_available = {"look": 0, "spy": 0, "swap_power": 0, "joker": 0}
    power_used = {"look": 0, "spy": 0, "swap_power": 0, "joker": 0}

    steps = 0
    aborted = False
    abort_reason = ""
    terminal: dict[str, Any] = {}

    if "final_ranks" in info or "won" in info:
        terminal = info
    else:
        done = False
        while not done and steps < max_steps_per_game:
            mask = env.action_masks()
            if bool(mask[encoding._CALL_DUTCH]):
                dutch_legal_decisions += 1

            availability = _power_availability(mask)
            if availability["special"]:
                special_available_count += 1
            for name in power_available:
                if availability[name]:
                    power_available[name] += 1

            action, _ = model.predict(
                obs,
                deterministic=deterministic,
                action_masks=mask,
            )
            action = int(action)
            kind = encoding.action_to_message(action).get("kind")

            if action == encoding._CALL_DUTCH:
                dutch_calls += 1
            elif action == encoding._DISCARD_DRAWN:
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

            obs, _reward, terminated, truncated, info = env.step(action)
            steps += 1
            known_score_end = _obs_known_score(obs)
            estimated_score_end = _obs_estimated_score(obs)

            if terminated or truncated:
                done = True
                reason = next((k for k in ABORT_KEYS if info.get(k)), None)
                if reason is not None:
                    aborted = True
                    abort_reason = reason
                else:
                    terminal = info

        if not done:
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
        "dutch_call_rate_when_legal": _safe_rate(
            dutch_calls, dutch_legal_decisions
        ),
        "called_dutch": called_dutch,
        "dutch_success": dutch_success,
        "dutch_bad_call": call_metrics["dutch_bad_call"],
        "dutch_margin_at_call": call_metrics["dutch_margin_at_call"],
        "self_score_at_call": call_metrics["self_score_at_call"],
        "best_opponent_score_at_call": call_metrics["best_opponent_score_at_call"],
        "discard_drawn_count": discard_drawn_count,
        "discarded_drawn_points_mean": _finite_mean(discarded_drawn_points),
        "replace_count": replace_count,
        "discarded_better_than_known_hand_proxy": discarded_better_proxy,
        "known_replace_proxy_good": known_replace_proxy_good,
        "known_replace_proxy_bad": known_replace_proxy_bad,
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
        "estimated_score_delta": estimated_score_end - estimated_score_start,
    }


def make_env(
    *,
    skill: str,
    num_players: int,
    seed_start: int,
    exe_path: str | None,
    timeout: float,
) -> DutchEnv:
    return DutchEnv(
        exe_path=exe_path,
        max_turns=MAX_TURNS,
        seed_start=seed_start,
        timeout=timeout,
        num_players=num_players,
        opponents={"skill": skill, "behavior": OPPONENT_BEHAVIOR},
    )


def _aggregate(rows: list[dict[str, Any]]) -> dict[str, Any]:
    valid = [r for r in rows if not r["aborted"]]
    calls = [r for r in valid if r["called_dutch"]]
    special_available = sum(int(r["special_available_count"]) for r in valid)

    def count_true(key: str, source: list[dict[str, Any]] = valid) -> int:
        return sum(1 for r in source if r.get(key) is True)

    return {
        "games": len(valid),
        "aborted": len(rows) - len(valid),
        "win_rate": _finite_mean([1.0 if r["won"] else 0.0 for r in valid]),
        "mean_rank": _finite_mean([r["rank"] for r in valid]),
        "dutch_call_rate_when_legal": _safe_rate(
            sum(int(r["dutch_calls"]) for r in valid),
            sum(int(r["dutch_legal_decisions"]) for r in valid),
        ),
        "dutch_success_rate_when_called": _safe_rate(
            count_true("dutch_success", calls),
            len(calls),
        ),
        "dutch_bad_call_rate": _safe_rate(
            count_true("dutch_bad_call", calls),
            len(calls),
        ),
        "mean_dutch_margin_at_call": _finite_mean(
            [r["dutch_margin_at_call"] for r in calls]
        ),
        "mean_self_score_at_call": _finite_mean([r["self_score_at_call"] for r in calls]),
        "mean_best_opponent_score_at_call": _finite_mean(
            [r["best_opponent_score_at_call"] for r in calls]
        ),
        "special_usage_rate_when_available": _safe_rate(
            sum(int(r["special_used_count"]) for r in valid),
            special_available,
        ),
        "look_usage_rate": _safe_rate(
            sum(int(r["look_used_count"]) for r in valid),
            sum(int(r["look_available_count"]) for r in valid),
        ),
        "spy_usage_rate": _safe_rate(
            sum(int(r["spy_used_count"]) for r in valid),
            sum(int(r["spy_available_count"]) for r in valid),
        ),
        "swap_power_usage_rate": _safe_rate(
            sum(int(r["swap_power_used_count"]) for r in valid),
            sum(int(r["swap_power_available_count"]) for r in valid),
        ),
        "joker_usage_rate": _safe_rate(
            sum(int(r["joker_used_count"]) for r in valid),
            sum(int(r["joker_available_count"]) for r in valid),
        ),
        "estimated_score_delta": _finite_mean(
            [r["estimated_score_delta"] for r in valid]
        ),
    }


def _fmt_pct(value: float | None) -> str:
    return "n/a" if value is None else f"{100.0 * value:5.1f}%"


def _fmt_num(value: float | None, digits: int = 2) -> str:
    return "n/a" if value is None else f"{value:.{digits}f}"


def print_report(rows: list[dict[str, Any]], skills: list[str], nums: list[int]) -> None:
    print("\n" + "=" * 110)
    print("RAPPORT COMPORTEMENTAL V1 - métriques réelles disponibles côté Python")
    print("=" * 110)
    print(
        f"{'skill':<10} {'n':>2} {'games':>5} {'win%':>7} {'rank':>6} "
        f"{'dutch/legal':>12} {'d.ok%':>7} {'bad%':>7} {'margin':>8} "
        f"{'self':>7} {'bestOpp':>8} {'spec%':>7} {'estΔ':>7}"
    )
    print("-" * 110)

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
                f"{_fmt_pct(agg['dutch_call_rate_when_legal']):>12} "
                f"{_fmt_pct(agg['dutch_success_rate_when_called']):>7} "
                f"{_fmt_pct(agg['dutch_bad_call_rate']):>7} "
                f"{_fmt_num(agg['mean_dutch_margin_at_call']):>8} "
                f"{_fmt_num(agg['mean_self_score_at_call']):>7} "
                f"{_fmt_num(agg['mean_best_opponent_score_at_call']):>8} "
                f"{_fmt_pct(agg['special_usage_rate_when_available']):>7} "
                f"{_fmt_num(agg['estimated_score_delta']):>7}"
            )
        print("-" * 110)

    global_agg = _aggregate(rows)
    print("\nGLOBAL")
    print(f"  games valides                  : {global_agg['games']}")
    print(f"  parties abandonnées            : {global_agg['aborted']}")
    print(f"  win_rate                       : {_fmt_pct(global_agg['win_rate'])}")
    print(f"  mean_rank                      : {_fmt_num(global_agg['mean_rank'])}")
    print(
        "  dutch_call_rate_when_legal     : "
        f"{_fmt_pct(global_agg['dutch_call_rate_when_legal'])}"
    )
    print(
        "  dutch_success_rate_when_called : "
        f"{_fmt_pct(global_agg['dutch_success_rate_when_called'])}"
    )
    print(f"  dutch_bad_call_rate            : {_fmt_pct(global_agg['dutch_bad_call_rate'])}")
    print(
        "  mean_dutch_margin_at_call      : "
        f"{_fmt_num(global_agg['mean_dutch_margin_at_call'])}"
    )
    print(
        "  special_usage_rate_when_avail  : "
        f"{_fmt_pct(global_agg['special_usage_rate_when_available'])}"
    )
    print(f"  look_usage_rate                : {_fmt_pct(global_agg['look_usage_rate'])}")
    print(f"  spy_usage_rate                 : {_fmt_pct(global_agg['spy_usage_rate'])}")
    print(
        "  swap_power_usage_rate          : "
        f"{_fmt_pct(global_agg['swap_power_usage_rate'])}"
    )
    print(f"  joker_usage_rate               : {_fmt_pct(global_agg['joker_usage_rate'])}")
    print(f"  estimated_score_delta moyen    : {_fmt_num(global_agg['estimated_score_delta'])}")

    print("\nPROXIES V1")
    print("  Colonnes avec suffixe _proxy : diagnostics issus de l'observation/croyance.")
    print("  Elles ne sont pas des vérités terrain et ne doivent pas être utilisées comme reward.")

    print("\nINDISPONIBLE EN V1 - nécessite diagnostics runner Dart")
    print("  - dutch_missed_opportunity_count réel")
    print("  - dutch_margin_when_available réel")
    print("  - swap_delta_real_score")
    print("  - discard quality réelle quand la carte remplacée est inconnue")
    print("  - valeur réelle robuste des pouvoirs V/Joker")


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_COLUMNS)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Évaluation comportementale offline V1 pour Dutch'78 RL."
    )
    parser.add_argument("--model", required=True, help="Chemin du checkpoint .zip.")
    parser.add_argument("--games", type=int, default=DEFAULT_GAMES,
                        help="Parties par condition. Défaut: 1.")
    parser.add_argument("--out", default=DEFAULT_OUT,
                        help=f"CSV de sortie. Défaut: {DEFAULT_OUT}.")
    parser.add_argument("--skills", default=",".join(DEFAULT_SKILLS),
                        help="Liste CSV parmi bronze,silver,difficile.")
    parser.add_argument("--num-players", default=",".join(map(str, DEFAULT_NUM_PLAYERS)),
                        help="Liste CSV de nombres de joueurs entre 2 et 6.")
    parser.add_argument("--seed", type=int, default=0, help="Seed de base.")
    parser.add_argument("--deterministic", action=argparse.BooleanOptionalAction,
                        default=True, help="Prédiction déterministe. Défaut: true.")
    parser.add_argument("--max-steps-per-game", type=int, default=10_000,
                        help="Garde-fou anti-boucle par partie.")
    parser.add_argument("--exe", default=None,
                        help="Chemin du binaire runner. Défaut: tool/rl_env_runner.")
    parser.add_argument("--timeout", type=float, default=30.0,
                        help="Timeout runner en secondes.")
    args = parser.parse_args()

    if args.games <= 0:
        raise SystemExit("--games doit être positif")
    if args.max_steps_per_game <= 0:
        raise SystemExit("--max-steps-per-game doit être positif")

    model_path = Path(args.model)
    if not model_path.exists():
        raise SystemExit(f"Modèle introuvable: {model_path}")

    skills = _parse_csv_values(args.skills, DEFAULT_SKILLS, name="skills")
    nums = _parse_num_players(args.num_players)

    print("Métriques V1: observation/masques/infos terminales uniquement.")
    print("Aucune modification runner, observation ou reward.")
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
            env = make_env(
                skill=skill,
                num_players=num_players,
                seed_start=seed_start,
                exe_path=args.exe,
                timeout=args.timeout,
            )
            try:
                for _ in range(args.games):
                    row = play_one_game(
                        env,
                        model,
                        skill=skill,
                        num_players=num_players,
                        episode_index=episode_index,
                        deterministic=bool(args.deterministic),
                        max_steps_per_game=int(args.max_steps_per_game),
                    )
                    rows.append(row)
                    episode_index += 1
            finally:
                env.close()

    out_path = Path(args.out)
    write_csv(out_path, rows)
    print_report(rows, skills, nums)
    print(f"\nCSV écrit: {out_path} ({len(rows)} lignes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
