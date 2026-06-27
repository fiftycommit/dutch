"""Tests du curriculum d'entraînement (PISTE 1) — quota difficile × {4,5,6 joueurs}.

4 vérifications (toutes doivent être vertes) :
  (a) distribution ~70/30 (statistique) + réalisation conforme (num_players forcé
      dans {4,5,6}, opponents.skill = difficile) ;
  (b) info["hard"] terminal == condition réellement tirée pour l'épisode ;
  (c) ratio=0.0 => comportement historique (aucune option forcée, tables variées) ;
  (d) garde-fous : curriculum exclusif des options figées (num_players/opponents)
      et ratio ∈ [0, 1].

Le skill adverse n'est PAS exposé dans l'observation (anti-fuite), donc on vérifie
la condition « dure » via les options forcées passées au runner + num_players réel.

Lancer depuis rl/ :  python test_curriculum.py
"""

from __future__ import annotations

import random

import numpy as np

from dutch_env import (
    CURRICULUM_HARD_NUM_PLAYERS,
    CURRICULUM_HARD_SKILL,
    DutchEnv,
)


def _spy_reset(env: DutchEnv) -> list[tuple[dict | None, int]]:
    """Shadow l'instance `reset` du runner pour capturer (extra_options, num_players).

    Ne touche pas la classe : on remplace l'attribut d'instance, le `reset` de
    classe reste intact pour les autres environnements.
    """
    orig = env._runner.reset
    calls: list[tuple[dict | None, int]] = []

    def spy(seed, extra_options=None):  # type: ignore[no-untyped-def]
        msg = orig(seed, extra_options=extra_options)
        calls.append((extra_options, int(msg["obs"]["num_players"])))
        return msg

    env._runner.reset = spy  # type: ignore[assignment]
    return calls


# ── (a) distribution ~70/30 + réalisation ───────────────────────────────────
def check_distribution() -> tuple[bool, str]:
    ratio = 0.7
    n = 400
    env = DutchEnv(seed_start=0, curriculum_hard_ratio=ratio)
    calls = _spy_reset(env)
    try:
        for _ in range(n):
            env.reset()
    finally:
        env.close()

    hard = [(extra, npl) for (extra, npl) in calls if extra is not None]
    frac = len(hard) / n
    # tolérance ~3σ : σ = sqrt(0.7*0.3/400) ≈ 0.023 -> fenêtre ±0.07
    if not 0.63 <= frac <= 0.77:
        return False, f"fraction dure {frac:.1%} hors [63%,77%] (attendu ~70%)"
    for extra, npl in hard:
        if extra.get("opponents", {}).get("skill") != CURRICULUM_HARD_SKILL:
            return False, f"épisode dur sans skill '{CURRICULUM_HARD_SKILL}': {extra}"
        if npl not in CURRICULUM_HARD_NUM_PLAYERS:
            return False, (
                f"épisode dur num_players={npl} hors {CURRICULUM_HARD_NUM_PLAYERS}"
            )
    return True, (
        f"{frac:.1%} durs sur {n} (≈70%), tailles dures "
        f"{sorted({npl for _, npl in hard})} ⊆ {list(CURRICULUM_HARD_NUM_PLAYERS)}"
    )


# ── (b) info["hard"] terminal cohérent ──────────────────────────────────────
def check_info_hard() -> tuple[bool, str]:
    env = DutchEnv(seed_start=1234, curriculum_hard_ratio=0.5)
    rng = random.Random(0)
    checked = 0
    try:
        for ep in range(24):
            env.reset()
            expected = env._episode_hard
            term = trunc = False
            info: dict = {}
            steps = 0
            while not (term or trunc) and steps < 4000:
                legal = np.flatnonzero(env.action_masks())
                if legal.size == 0:
                    break
                _, _, term, trunc, info = env.step(int(rng.choice(legal)))
                steps += 1
            if trunc and not term:
                continue  # troncature (erreur récupérable) : pas de clé "hard" garantie
            if "hard" not in info:
                return False, f"ép {ep}: info terminal sans clé 'hard'"
            if bool(info["hard"]) != expected:
                return False, f"ép {ep}: info['hard']={info['hard']} != tiré {expected}"
            checked += 1
    finally:
        env.close()
    if checked == 0:
        return False, "aucun épisode terminal naturel observé"
    return True, f"info['hard'] cohérent avec la condition tirée ({checked} épisodes)"


# ── (c) ratio=0.0 == comportement historique ────────────────────────────────
def check_off_is_historical() -> tuple[bool, str]:
    env = DutchEnv(seed_start=7)  # ratio 0.0 par défaut
    calls = _spy_reset(env)
    hard_flags: list[bool] = []
    try:
        for _ in range(60):
            env.reset()
            hard_flags.append(env._episode_hard)
    finally:
        env.close()
    if any(extra is not None for extra, _ in calls):
        return False, "ratio=0.0 a forcé des options (attendu : aucune)"
    if any(hard_flags):
        return False, "ratio=0.0 a marqué des épisodes 'hard'"
    seen = sorted({npl for _, npl in calls})
    if len(seen) < 3:
        return False, f"diversité de tables trop faible : {seen}"
    return True, f"ratio=0.0 : aucune option forcée, tables variées {seen}"


# ── (d) garde-fous d'exclusivité / domaine ──────────────────────────────────
def check_guards() -> tuple[bool, str]:
    cases = [
        ("curriculum + num_players figé", dict(curriculum_hard_ratio=0.7, num_players=4)),
        (
            "curriculum + opponents figé",
            dict(curriculum_hard_ratio=0.7, opponents={"skill": "bronze"}),
        ),
        ("ratio > 1", dict(curriculum_hard_ratio=1.5)),
        ("ratio < 0", dict(curriculum_hard_ratio=-0.1)),
    ]
    for label, kw in cases:
        try:
            DutchEnv(seed_start=0, **kw)  # type: ignore[arg-type]
            return False, f"pas de ValueError pour : {label}"
        except ValueError:
            pass
    return True, "ValueError levée pour les 4 combinaisons interdites"


CHECKS = [
    ("a. distribution 70/30 + réalisation", check_distribution),
    ("b. info['hard'] terminal cohérent", check_info_hard),
    ("c. ratio=0.0 == historique", check_off_is_historical),
    ("d. garde-fous exclusivité/domaine", check_guards),
]


def main() -> int:
    all_ok = True
    print("=== test_curriculum : 4 vérifications (PISTE 1) ===")
    for name, fn in CHECKS:
        try:
            ok, detail = fn()
        except Exception as e:  # noqa: BLE001
            ok, detail = False, f"exception: {type(e).__name__}: {e}"
        all_ok = all_ok and ok
        print(f"  [{'OK ' if ok else 'FAIL'}] {name} — {detail}")
    print("=== " + ("TOUT VERT" if all_ok else "ÉCHEC") + " ===")
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
