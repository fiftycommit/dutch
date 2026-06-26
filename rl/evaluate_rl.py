"""Évaluation d'un modèle RL Dutch'78 (MaskablePPO) sur des parties complètes.

Fait jouer un agent chargé depuis un ``.zip`` en mode DÉTERMINISTE (argmax) sur la
grille de conditions :

    skill adverse ∈ {bronze, silver, difficile}
  × num_players  ∈ {2, 3, 4, 5, 6}
  × poids MORL   ∈ {(1,0) vitesse, (0.5,0.5) mixte, (0,1) déstabilisation}
  = 45 conditions × ``--games`` parties.

Le comportement adverse est fixé (``OPPONENT_BEHAVIOR``) pour isoler la variable
« skill ». Les bots adverses occupent p1..pn ; p0 est le siège piloté par l'agent.

Métriques perturbatrices : les pouvoirs déstabilisateurs (Joker mélange, Valet
échange, 10 espionne) sont des ACTIONS de l'agent → décodées depuis l'action
choisie (``encoding.action_to_message``) AVANT ``env.step`` ; aucune information
supplémentaire n'est requise côté Dart. L'intensité de déstabilisation cumulée
vient du signal ``destab`` brut exposé par le runner (``info["rewards_raw"]``).

⚠ Ce script SUPPOSE que le binaire ``tool/rl_env_runner`` a été recompilé avec
l'extension d'éval (num_players / opponents). Un garde-fou le vérifie en tout
premier et ABORTE proprement sinon.

Usage :
    uv run python rl/evaluate_rl.py MODEL.zip [--games 1000] [--dry-run]
        [--exe ../tool/rl_env_runner] [--out report.csv]
        [--seed-base 0] [--timeout 30]
"""

from __future__ import annotations

import argparse
import csv
import io
import math
import sys
import time
from pathlib import Path
from typing import Any

from sb3_contrib import MaskablePPO

import encoding
from dutch_env import DutchEnv
from runner_process import RunnerCrashed, RunnerProcess, RunnerTimeout

# ── Constantes de la grille d'évaluation ────────────────────────────────────
OPPONENT_BEHAVIOR = "balanced"  # comportement adverse fixe (modifiable ici)
SKILLS = ["bronze", "silver", "difficile"]
NUM_PLAYERS = [2, 3, 4, 5, 6]
WEIGHTS: list[tuple[float, float]] = [(1.0, 0.0), (0.5, 0.5), (0.0, 1.0)]
MAX_TURNS = 500            # aligné sur l'entraînement
DRY_RUN_SAMPLE = 20        # parties chronométrées pour l'extrapolation
SAFETY_STEPS = 10_000      # garde-fou anti-boucle infinie par partie
WILSON_Z = 1.96            # IC 95 %

ABORT_KEYS = ("runner_crashed", "runner_timeout", "engine_recoverable_error")

CSV_COLUMNS = [
    "skill", "num_players", "w1", "w2", "seed",
    "aborted", "abort_reason",
    "won", "rank", "final_score_p0",
    "called_dutch", "dutch_caller", "dutch_success",
    "length", "steps",
    "n_joker", "n_swap", "n_spy", "n_look", "destab_sum",
]


# ── Statistiques sans dépendance externe ────────────────────────────────────
def wilson_interval(k: int, n: int, z: float = WILSON_Z) -> tuple[float, float, float]:
    """(p, borne basse, borne haute) — intervalle de Wilson 95 %. n=0 => (0,0,0)."""
    if n == 0:
        return (0.0, 0.0, 0.0)
    p = k / n
    denom = 1.0 + z * z / n
    center = (p + z * z / (2 * n)) / denom
    half = (z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))) / denom
    return (p, center - half, center + half)


def mean(values: list[float]) -> float:
    return (sum(values) / len(values)) if values else float("nan")


def fmt_duration(seconds: float) -> str:
    seconds = int(round(seconds))
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h}h{m:02d}m{s:02d}s"
    if m:
        return f"{m}m{s:02d}s"
    return f"{s}s"


# ── Garde-fou : binaire recompilé avec l'extension d'éval ? ─────────────────
def _abort_stale(reason: str) -> None:
    print(
        "\n[ABORT] Le binaire rl_env_runner n'est PAS à jour "
        f"({reason}).\n"
        "        Recompile-le AVANT d'évaluer :\n"
        "          dart compile exe tool/rl_env_runner.dart -o tool/rl_env_runner\n",
        file=sys.stderr,
    )
    sys.exit(2)


def assert_binary_up_to_date(exe_path: str | None, timeout: float) -> None:
    """Vérifie que le runner connaît l'extension (num_players / opponents).

    1. num_players=99 (hors borne) => DOIT répondre type=error code=INVALID_OPTIONS.
       L'ancien binaire ignore l'option et renvoie une observation => obsolète.
    2. num_players=6 forcé => obs.num_players DOIT valoir 6 (extension appliquée).
    """
    kwargs: dict[str, Any] = {"timeout": timeout}
    if exe_path is not None:
        kwargs["exe_path"] = exe_path
    runner = RunnerProcess(**kwargs)
    try:
        try:
            msg = runner.reset(0, extra_options={"num_players": 99})
        except (RunnerCrashed, RunnerTimeout) as e:
            _abort_stale(f"le témoin a échoué : {e}")
        if not (msg.get("type") == "error" and msg.get("code") == "INVALID_OPTIONS"):
            _abort_stale(
                "num_players=99 n'a pas été rejeté "
                f"(reçu type={msg.get('type')!r} code={msg.get('code')!r})"
            )
        try:
            msg = runner.reset(1, extra_options={"num_players": 6})
        except (RunnerCrashed, RunnerTimeout) as e:
            _abort_stale(f"le témoin a échoué : {e}")
        n = (msg.get("obs") or {}).get("num_players")
        if n != 6:
            _abort_stale(f"num_players forcé=6 mais le runner renvoie {n!r}")
    finally:
        runner.close(quiet=True)
    print("[OK] Binaire rl_env_runner à jour (extension d'éval détectée).")


# ── Une partie complète, agent déterministe ─────────────────────────────────
def play_one_game(
    env: DutchEnv, model: MaskablePPO, skill: str, num_players: int,
    weights: tuple[float, float],
) -> dict[str, Any]:
    """Joue une partie jusqu'à terminaison ; renvoie une ligne de résultat."""
    obs, info = env.reset()
    seed = info.get("seed")

    counts = {"joker": 0, "swap": 0, "spy": 0, "look": 0}
    destab_sum = 0.0
    steps = 0
    aborted = False
    abort_reason = ""
    terminal: dict[str, Any] = {}

    # Cas dégénéré : terminal dès le reset (rare). DutchEnv fusionne alors le
    # `info` terminal dans le retour de reset.
    if "final_ranks" in info or "won" in info:
        terminal = info
    else:
        done = False
        while not done and steps < SAFETY_STEPS:
            action, _ = model.predict(
                obs, deterministic=True, action_masks=env.action_masks()
            )
            action = int(action)
            kind = encoding.action_to_message(action).get("kind")
            if kind == "powerJoker":
                counts["joker"] += 1
            elif kind == "powerV_swap":
                counts["swap"] += 1
            elif kind == "power10_spy":
                counts["spy"] += 1
            elif kind == "power7_look":
                counts["look"] += 1

            obs, _reward, terminated, truncated, info = env.step(action)
            steps += 1
            rr = info.get("rewards_raw")
            if rr is not None:
                destab_sum += float(rr.get("destab", 0.0))

            if terminated or truncated:
                done = True
                reason = next((k for k in ABORT_KEYS if k in info), None)
                if reason is not None:
                    aborted = True
                    abort_reason = reason
                else:
                    terminal = info

    w1, w2 = weights
    row: dict[str, Any] = {
        "skill": skill,
        "num_players": num_players,
        "w1": w1,
        "w2": w2,
        "seed": seed,
        "aborted": aborted,
        "abort_reason": abort_reason,
        "won": None,
        "rank": None,
        "final_score_p0": None,
        "called_dutch": None,
        "dutch_caller": None,
        "dutch_success": None,
        "length": terminal.get("length") if not aborted else steps,
        "steps": steps,
        "n_joker": counts["joker"],
        "n_swap": counts["swap"],
        "n_spy": counts["spy"],
        "n_look": counts["look"],
        "destab_sum": round(destab_sum, 6),
    }
    if not aborted:
        won = bool(terminal.get("won"))
        called = bool(terminal.get("called_dutch"))
        row.update(
            won=won,
            rank=terminal.get("rank"),
            final_score_p0=(terminal.get("final_scores") or {}).get("p0"),
            called_dutch=called,
            # dutch_caller : id de l'appelant (peut être un adversaire) ou None.
            dutch_caller=terminal.get("dutch_caller"),
            # Définition principale : aucun champ "succès de l'appel" au-delà de
            # `won` n'est exposé par le runner (_finalize) => won & called_dutch.
            dutch_success=(won and called),
        )
    return row


# ── Agrégation par condition ─────────────────────────────────────────────────
def aggregate(rows: list[dict[str, Any]]) -> dict[str, Any]:
    """rows = lignes NON abandonnées d'une condition."""
    n = len(rows)
    wins = sum(1 for r in rows if r["won"])
    p, lo, hi = wilson_interval(wins, n)
    callers = [r for r in rows if r["called_dutch"]]
    n_called = len(callers)
    dutch_success_rate = (
        sum(1 for r in callers if r["dutch_success"]) / n_called if n_called else float("nan")
    )
    return {
        "n": n,
        "win_rate": p,
        "win_lo": lo,
        "win_hi": hi,
        "mean_rank": mean([r["rank"] for r in rows]),
        "mean_score": mean([r["final_score_p0"] for r in rows if r["final_score_p0"] is not None]),
        "dutch_call_rate": (n_called / n) if n else float("nan"),
        "dutch_success_rate": dutch_success_rate,
        "mean_length": mean([r["length"] for r in rows if r["length"] is not None]),
        "mean_joker": mean([r["n_joker"] for r in rows]),
        "mean_swap": mean([r["n_swap"] for r in rows]),
        "mean_spy": mean([r["n_spy"] for r in rows]),
        "mean_destab": mean([r["destab_sum"] for r in rows]),
    }


def _wlabel(w: tuple[float, float]) -> str:
    return f"({w[0]:g},{w[1]:g})"


# ── Rapport console ──────────────────────────────────────────────────────────
def print_report(
    all_rows: list[dict[str, Any]], aborted_total: int, games: int
) -> None:
    print("\n" + "=" * 110)
    print("RAPPORT D'ÉVALUATION — détail par condition (skill × num_players × poids)")
    print("=" * 110)
    header = (
        f"{'skill':<10} {'n':>2} {'poids':>9} {'parties':>7} {'win%':>6} "
        f"{'IC95':>13} {'rang':>5} {'score':>6} {'dutch%':>6} {'d.ok%':>6} "
        f"{'long':>5} {'jok':>4} {'swp':>4} {'spy':>4} {'destab':>7}"
    )
    print(header)
    print("-" * 110)

    def rows_for(skill: str, n: int, w: tuple[float, float]) -> list[dict[str, Any]]:
        return [
            r for r in all_rows
            if not r["aborted"] and r["skill"] == skill
            and r["num_players"] == n and r["w1"] == w[0] and r["w2"] == w[1]
        ]

    for skill in SKILLS:
        for n in NUM_PLAYERS:
            for w in WEIGHTS:
                rows = rows_for(skill, n, w)
                if not rows:
                    continue
                a = aggregate(rows)
                ic = f"[{a['win_lo']:.3f},{a['win_hi']:.3f}]"
                print(
                    f"{skill:<10} {n:>2} {_wlabel(w):>9} {a['n']:>7} "
                    f"{a['win_rate'] * 100:>5.1f}% {ic:>13} "
                    f"{a['mean_rank']:>5.2f} {a['mean_score']:>6.1f} "
                    f"{a['dutch_call_rate'] * 100:>5.1f}% {a['dutch_success_rate'] * 100:>5.1f}% "
                    f"{a['mean_length']:>5.1f} {a['mean_joker']:>4.2f} "
                    f"{a['mean_swap']:>4.2f} {a['mean_spy']:>4.2f} {a['mean_destab']:>7.3f}"
                )
        print("-" * 110)

    # ── Focus comparatif sur les 3 poids (macro-moyenne sur skill × num_players) ──
    print("\n" + "=" * 78)
    print("FOCUS POIDS MORL — macro-moyenne sur les 15 conditions (skill × num_players)")
    print("Objectif : (0.5,0.5) combine-t-il win-rate ÉLEVÉ ET déstabilisation ÉLEVÉE ?")
    print("=" * 78)
    print(f"{'poids':>9} {'win% macro':>11} {'destab macro':>13} {'perturb/partie':>15}")
    print("-" * 78)
    for w in WEIGHTS:
        rows = [
            r for r in all_rows
            if not r["aborted"] and r["w1"] == w[0] and r["w2"] == w[1]
        ]
        if not rows:
            continue
        win_macro = mean([1.0 if r["won"] else 0.0 for r in rows])
        destab_macro = mean([r["destab_sum"] for r in rows])
        perturb = mean([r["n_joker"] + r["n_swap"] + r["n_spy"] for r in rows])
        print(
            f"{_wlabel(w):>9} {win_macro * 100:>10.1f}% "
            f"{destab_macro:>13.3f} {perturb:>15.3f}"
        )
    print("-" * 78)
    print(
        "Lecture : 'perturb/partie' = nb moyen d'actions Joker+Valet+10 de l'agent ; "
        "'destab' = somme du signal de réduction de menace du leader."
    )
    if aborted_total:
        print(
            f"\n⚠ {aborted_total} partie(s) ABANDONNÉE(S) (crash/timeout/erreur récupérable) "
            "exclue(s) des agrégats — voir colonne 'aborted' du CSV."
        )
    else:
        print("\n✓ Aucune partie abandonnée.")


# ── Exécution de la grille complète ──────────────────────────────────────────
def make_env(skill: str, num_players: int, weights: tuple[float, float],
             seed_start: int, exe_path: str | None, timeout: float) -> DutchEnv:
    return DutchEnv(
        exe_path=exe_path,
        max_turns=MAX_TURNS,
        seed_start=seed_start,
        timeout=timeout,
        fixed_weights=weights,
        num_players=num_players,
        opponents={"skill": skill, "behavior": OPPONENT_BEHAVIOR},
    )


def run_condition(
    model: MaskablePPO, skill: str, num_players: int, weights: tuple[float, float],
    games: int, seed_start: int, exe_path: str | None, timeout: float,
    writer: "csv.DictWriter[str] | None", sink: list[dict[str, Any]],
) -> int:
    """Joue `games` parties d'une condition. Renvoie le nb de parties abandonnées."""
    env = make_env(skill, num_players, weights, seed_start, exe_path, timeout)
    aborted = 0
    try:
        for _ in range(games):
            row = play_one_game(env, model, skill, num_players, weights)
            if row["aborted"]:
                aborted += 1
            sink.append(row)
            if writer is not None:
                writer.writerow(row)
    finally:
        env.close()
    return aborted


def main() -> int:
    parser = argparse.ArgumentParser(description="Évaluation du modèle RL Dutch'78.")
    parser.add_argument("model", type=str, help="Chemin du .zip MaskablePPO.")
    parser.add_argument("--games", type=int, default=1000, help="Parties par condition.")
    parser.add_argument("--dry-run", action="store_true",
                        help="Chronométrer un échantillon, estimer total/ETA, puis sortir.")
    parser.add_argument("--exe", type=str, default=None,
                        help="Chemin du binaire runner (défaut : tool/rl_env_runner).")
    parser.add_argument("--out", type=str, default="report.csv",
                        help="CSV de sortie (une ligne par partie).")
    parser.add_argument("--seed-base", type=int, default=0,
                        help="Seed de base ; condition i => seeds [base+i*games, +games[.")
    parser.add_argument("--timeout", type=float, default=30.0,
                        help="Timeout d'inactivité du runner (s).")
    args = parser.parse_args()

    if args.games <= 0:
        raise SystemExit("--games doit être positif")

    model_path = Path(args.model)
    if not model_path.exists():
        raise SystemExit(f"Modèle introuvable : {model_path}")

    conditions = [
        (skill, n, w) for skill in SKILLS for n in NUM_PLAYERS for w in WEIGHTS
    ]
    total_games = len(conditions) * args.games

    # 1) Garde-fou binaire AVANT toute partie (le dry-run joue aussi de vraies parties).
    assert_binary_up_to_date(args.exe, args.timeout)

    # 2) Chargement du modèle (CPU ; espaces restaurés depuis le .zip).
    print(f"[load] {model_path}")
    model = MaskablePPO.load(str(model_path), device="cpu")

    # 3) Dry-run : chronométrer un échantillon sur une condition médiane.
    if args.dry_run:
        skill, n, w = ("silver", 4, (0.5, 0.5))
        sample = min(DRY_RUN_SAMPLE, args.games)
        print(f"\n[dry-run] chronométrage de {sample} parties sur "
              f"({skill}, {n}j, {_wlabel(w)})…")
        sink: list[dict[str, Any]] = []
        t0 = time.perf_counter()
        run_condition(model, skill, n, w, sample, args.seed_base, args.exe,
                      args.timeout, writer=None, sink=sink)
        elapsed = time.perf_counter() - t0
        done = len(sink)
        per_game = elapsed / done if done else float("nan")

        # Taille CSV : sérialiser l'échantillon en mémoire et extrapoler.
        buf = io.StringIO()
        w_tmp = csv.DictWriter(buf, fieldnames=CSV_COLUMNS)
        w_tmp.writeheader()
        for r in sink:
            w_tmp.writerow(r)
        header_bytes = len(buf.getvalue().splitlines()[0]) + 1
        body_bytes = len(buf.getvalue().encode("utf-8"))
        est_csv = header_bytes + (body_bytes / done) * total_games if done else 0.0

        print("\n" + "=" * 60)
        print("ESTIMATION DU RUN COMPLET")
        print("=" * 60)
        print(f"  conditions          : {len(conditions)} "
              f"(3 skill × 5 num_players × 3 poids)")
        print(f"  parties/condition   : {args.games}")
        print(f"  parties TOTAL       : {total_games}")
        print(f"  temps/partie mesuré : {per_game * 1000:.0f} ms "
              f"(sur {done} parties)")
        print(f"  ETA total           : {fmt_duration(per_game * total_games)}")
        print(f"  CSV estimé          : ~{est_csv / 1024:.0f} KiB")
        print("=" * 60)
        print("Dry-run terminé — relance SANS --dry-run pour exécuter le run complet.")
        return 0

    # 4) Run complet.
    out_path = Path(args.out)
    print(f"\n[run] {total_games} parties → CSV : {out_path}")
    all_rows: list[dict[str, Any]] = []
    aborted_total = 0
    t0 = time.perf_counter()
    with out_path.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=CSV_COLUMNS)
        writer.writeheader()
        for idx, (skill, n, w) in enumerate(conditions):
            seed_start = args.seed_base + idx * args.games
            aborted_total += run_condition(
                model, skill, n, w, args.games, seed_start, args.exe,
                args.timeout, writer, all_rows,
            )
            elapsed = time.perf_counter() - t0
            done = (idx + 1) * args.games
            eta = (elapsed / done) * (total_games - done) if done else 0.0
            print(f"  [{idx + 1:>2}/{len(conditions)}] {skill:<10} {n}j "
                  f"{_wlabel(w):>9} — {done}/{total_games} parties "
                  f"(ETA {fmt_duration(eta)})")

    print_report(all_rows, aborted_total, args.games)
    print(f"\n[done] {total_games} parties en {fmt_duration(time.perf_counter() - t0)} "
          f"— CSV écrit : {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
