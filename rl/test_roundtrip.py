"""Barrière de validation du wrapper Python AVANT tout entraînement PPO.

6 vérifications obligatoires (toutes doivent être vertes) :
  1. Aller-retour scripté (transitions de micro-phase, drawn_value, reward=0 hors terminal)
  2. Cohérence de la reward terminale Python <-> Dart (info.final_ranks)
  3. Déterminisme (même seed + mêmes actions => observations identiques)
  4. Honnêteté du masque (wrapper n'émet jamais hors masque ; forcer => ILLEGAL_ACTION)
  5. Formes fixes sur 2..6 joueurs (obs=OBS_DIM, masque=N_ACTIONS)
  6. Robustesse du process (kill => reset relance ; timeout => erreur claire)

Lancer depuis rl/ :  python test_roundtrip.py
"""

from __future__ import annotations

import json
import random
import sys

import numpy as np

import encoding
from dutch_env import DutchEnv
from runner_process import RunnerProcess, RunnerTimeout


def _legal_indices(mask: np.ndarray) -> list[int]:
    return [int(i) for i in np.flatnonzero(mask)]


# ── 1. Aller-retour scripté ────────────────────────────────────────────────
def check_scripted_roundtrip() -> tuple[bool, str]:
    with RunnerProcess() as rp:
        msg = rp.reset(1)
        steps = 0
        seen_postdraw = False
        while not msg.get("done") and steps < 2000:
            micro = msg["micro_phase"]
            obs = msg["obs"]
            drawn = obs.get("drawn_value")
            # drawn_value présent UNIQUEMENT en postDraw (après pioche, avant pose)
            if micro == "dutchOrDraw" and drawn is not None:
                return False, "drawn_value présent en dutchOrDraw"
            if micro == "postDraw":
                seen_postdraw = True
                if drawn is None:
                    return False, "drawn_value absent en postDraw"
            if micro == "power" and drawn is not None:
                return False, "drawn_value présent en power (devrait être posé)"
            # reward 0 hors terminal
            if msg.get("reward") != 0.0:
                return False, f"reward!=0 hors terminal (={msg.get('reward')})"
            # action scriptée : avancer
            kind = {
                "dutchOrDraw": "continue_draw",
                "postDraw": "discard_drawn",
                "reaction": "pass_tick",
            }.get(micro, "skip_power")
            msg = rp.step({"kind": kind})
            if msg.get("type") == "error":
                return False, f"erreur inattendue: {msg.get('message')}"
            steps += 1
        if not msg.get("done"):
            return False, "épisode non terminé"
        if not seen_postdraw:
            return False, "jamais passé en postDraw"
        return True, f"épisode terminé en {steps} steps, transitions cohérentes"


# ── 2. Reward terminale Python <-> Dart ────────────────────────────────────
def check_terminal_reward() -> tuple[bool, str]:
    checked = 0
    with RunnerProcess() as rp:
        for seed in range(8):
            msg = rp.reset(100 + seed)
            steps = 0
            while not msg.get("done") and steps < 2000:
                micro = msg["micro_phase"]
                kind = {
                    "dutchOrDraw": "continue_draw",
                    "postDraw": "discard_drawn",
                    "reaction": "pass_tick",
                }.get(micro, "skip_power")
                msg = rp.step({"kind": kind})
                steps += 1
            info = msg["info"]
            ranks = info["final_ranks"]
            n = len(ranks)
            rank = ranks["p0"]
            expected = 0.0 if n <= 1 else 1 - 2 * (rank - 1) / (n - 1)
            got = msg["rewards"]["principal"]
            if abs(got - expected) > 1e-9 or abs(msg["reward"] - expected) > 1e-9:
                return False, (
                    f"seed {seed}: principal={got} reward={msg['reward']} "
                    f"!= attendu {expected} (rank={rank}/{n})"
                )
            checked += 1
    return True, f"{checked} fins de partie cohérentes (principal == rang normalisé)"


# ── 3. Déterminisme ─────────────────────────────────────────────────────────
def check_determinism() -> tuple[bool, str]:
    def run(rp: RunnerProcess, seed: int) -> list[str]:
        msg = rp.reset(seed)
        fps = [json.dumps(msg["obs"], sort_keys=True)]
        steps = 0
        while not msg.get("done") and steps < 2000:
            micro = msg["micro_phase"]
            kind = {
                "dutchOrDraw": "continue_draw",
                "postDraw": "discard_drawn",
                "reaction": "pass_tick",
            }.get(micro, "skip_power")
            msg = rp.step({"kind": kind})
            if not msg.get("done"):
                fps.append(json.dumps(msg["obs"], sort_keys=True))
            steps += 1
        return fps

    with RunnerProcess() as rp:
        a = run(rp, 7)
        b = run(rp, 7)  # même seed, 2e fois (même process)
    if a != b:
        first = next((i for i in range(min(len(a), len(b))) if a[i] != b[i]), -1)
        return False, f"divergence au step {first} (len {len(a)} vs {len(b)})"
    return True, f"2 runs seed=7 identiques ({len(a)} observations)"


# ── 4. Honnêteté du masque ─────────────────────────────────────────────────
def check_mask_honesty() -> tuple[bool, str]:
    # (a) Le wrapper ne propose jamais d'action hors masque (sinon DutchEnv lève).
    rng = random.Random(0)
    env = DutchEnv(seed_start=0)
    try:
        for _ in range(8):
            env.reset()
            done = False
            steps = 0
            while not done and steps < 2000:
                legal = _legal_indices(env.action_masks())
                if not legal:
                    return False, "masque vide hors terminal"
                _, _, term, trunc, _ = env.step(rng.choice(legal))
                done = term or trunc
                steps += 1
    except RuntimeError as e:
        return False, f"le wrapper a émis une action rejetée: {e}"
    finally:
        env.close()

    # (b) Forcer une action masquée côté Dart -> ILLEGAL_ACTION.
    with RunnerProcess() as rp:
        msg = rp.reset(3)
        if msg["micro_phase"] != "dutchOrDraw":
            return False, "reset non en dutchOrDraw (cas non géré par le test)"
        forced = rp.step({"kind": "replace", "params": {"index": 0}})  # illégal ici
        if forced.get("type") != "error" or forced.get("code") != "ILLEGAL_ACTION":
            return False, f"action masquée non rejetée: {forced}"
    return True, "wrapper jamais hors masque ; action forcée => ILLEGAL_ACTION"


# ── 5. Formes fixes sur 2..6 joueurs ───────────────────────────────────────
def check_fixed_shapes() -> tuple[bool, str]:
    seen: set[int] = set()
    with RunnerProcess() as rp:
        for seed in range(60):
            msg = rp.reset(seed)
            seen.add(int(msg["obs"]["num_players"]))
            obs_vec = encoding.encode_observation(msg)
            mask = encoding.build_mask_vector(msg)
            if obs_vec.shape != (encoding.OBS_DIM,):
                return False, f"obs shape {obs_vec.shape} != ({encoding.OBS_DIM},)"
            if mask.shape != (encoding.N_ACTIONS,):
                return False, f"mask shape {mask.shape} != ({encoding.N_ACTIONS},)"
    missing = {2, 3, 4, 5, 6} - seen
    if missing:
        return False, f"tailles de table non couvertes: {sorted(missing)}"
    return True, (
        f"obs=({encoding.OBS_DIM},) mask=({encoding.N_ACTIONS},) sur tables {sorted(seen)}"
    )


# ── 6. Robustesse du process ───────────────────────────────────────────────
def check_process_robustness() -> tuple[bool, str]:
    # (a) kill en cours -> reset relance proprement
    env = DutchEnv(seed_start=0)
    try:
        env.reset()
        for _ in range(3):
            legal = _legal_indices(env.action_masks())
            if not legal:
                break
            # éviter call_dutch (index 0) qui terminerait l'épisode immédiatement
            act = next((i for i in legal if i != encoding._CALL_DUTCH), legal[0])
            _, _, term, trunc, _ = env.step(act)
            if term or trunc:
                break
        env._runner.proc.kill()  # type: ignore[union-attr]
        env._runner.proc.wait(timeout=2.0)  # type: ignore[union-attr]
        obs, _ = env.reset()  # doit relancer le binaire
        if obs.shape != (encoding.OBS_DIM,):
            return False, "reset après kill : obs invalide"
    except Exception as e:  # noqa: BLE001
        return False, f"reset après kill a échoué: {e}"
    finally:
        env.close()

    # (b) timeout : faux binaire qui ne répond jamais -> RunnerTimeout
    fake = RunnerProcess(
        timeout=2.0,
        _extra_args=[sys.executable, "-c", "import time; time.sleep(100)"],
    )
    try:
        fake.reset(0)
        return False, "aucun timeout sur un binaire muet"
    except RunnerTimeout:
        pass
    finally:
        fake.close(quiet=True)
    return True, "kill => reset relance ; binaire muet => RunnerTimeout"


CHECKS = [
    ("1. aller-retour scripté", check_scripted_roundtrip),
    ("2. reward terminale Python<->Dart", check_terminal_reward),
    ("3. déterminisme", check_determinism),
    ("4. honnêteté du masque", check_mask_honesty),
    ("5. formes fixes 2-6 joueurs", check_fixed_shapes),
    ("6. robustesse process (kill + timeout)", check_process_robustness),
]


def main() -> int:
    all_ok = True
    print("=== test_roundtrip : 6 vérifications ===")
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
