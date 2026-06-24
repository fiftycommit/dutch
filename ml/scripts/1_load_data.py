"""
Script 1 — Ingestion brute du dataset self-play Dutch'78.

Rôle (UNIQUEMENT ingestion — aucun filtrage/engineering de features ici, cf. script 2) :
  1. Lit tous les JSON de `ml/data/raw/games/` (un fichier = un *record* = un bot sur une partie).
  2. Aplatit en DataFrame : UNE LIGNE PAR SNAPSHOT (= une entrée de `actions`, càd un tour de
     décision du bot), en rattachant à chaque snapshot les infos du *record parent* (cible,
     identité bot, contexte partie).
  3. Contrôles de cohérence (nombre de lignes, records perdus, champs manquants, anomalies).
  4. Sauvegarde le DataFrame brut en parquet dans `ml/data/processed/` (rechargement rapide).

================================================================================
SCHÉMA RÉEL OBSERVÉ (généré par tool/ml_dataset_generator.dart, seed=42, 20 000 parties)
================================================================================

NIVEAU RECORD (un fichier game_<seed>_<g>_p<seat>.json) — 34 champs :
  Identité / contexte :
    gameId(str), botId(str), botName(str), botBehavior(str), botSkillLevel(str),
    numberOfPlayers(int), gameMode(str), usedSBMM(bool), startTime(str ISO), endTime(str ISO),
    initialHandSize(int), opponents(list[dict{id,name,isHuman,behavior,skillLevel}])
  Cible / résultat :
    finalRank(int 1..N), finalScore(int), calledDutch(bool), wonDutch(bool),
    cardsAtDutch(int), scoreAtDutch(int), totalTurns(int)
  Statistiques record :
    avgDecisionTime(float), powerUsesCount(int), goodDecisions(int), badDecisions(int)
  Liste des snapshots :
    actions(list[dict]) — voir niveau snapshot ci-dessous

  Champs TOUJOURS NULL en self-play (pas d'humain dans le générateur all-bots) — DROPPÉS ici,
  documentés pour mémoire :
    humanFinalScore, humanFinalHandSize, botFinalHandSize, pBeatHuman, initialDeck,
    turnsBeforeDutch, discardsPerRound, triageDecisions, initialHandScore, initialHandRank,
    initialHandRankFromWorst

NIVEAU SNAPSHOT (une entrée de `actions`) :
  Méta action : actionType(str: 'play_turn'|'call_dutch'), turnNumber(int), timestamp(str ISO)
  result : believedScoreAfter(int) — NULL pour 'call_dutch' (pas d'estimation post-action) : normal.
  actionDetails : toujours {} (vide) — droppé.
  gameState (l'état observable par le bot à ce tour — 30 champs, c'est le cœur des features) :
    turnCount, actionCount, phase(str), numberOfPlayers, botSeatIndex, deckSize, discardPileSize,
    topDiscardValue(str rang carte), topDiscardPoints, botHandSize, opponentsHandSizes(list[int]),
    minOpponentHandSize, expectedDeckCardValue(float), discardedRanks(dict rang->count),
    dutchCalledAlready(bool), knownCardCount, unknownCardCount, memoryConfidence(float),
    believedKnownScore, maxKnownCardValue, hasDoublon(bool), doublonCount,
    expectedUnknownValueSum(float), believedTotalScoreEstimate(float), spiedOpponentCardsCount,
    bestMatchProbability(float), botBehavior, botSkillLevel, usedSBMM, aiParams(toujours null)

================================================================================
CONVENTIONS DE NOMMAGE DU DATAFRAME APLATI
================================================================================
  rec_*  : champ provenant du record parent (métadonnée / cible / stat record).
  gs_*   : champ provenant de gameState (état par-snapshot = futures features brutes).
  (sans préfixe) : champs identifiant le snapshot (actionType, turnNumber, timestamp,
                   snapshot_index, believedScoreAfter) + la cible dérivée `won`.

  Cible dérivée : won(int) = 1 si rec_finalRank == 1 sinon 0.
  Champs imbriqués préservés sans perte :
    gs_opponentsHandSizes : colonne liste (list[int]) — pyarrow gère nativement.
    gs_discardedRanks_json, rec_opponents_json : sérialisés en JSON (str) pour parquet.

Exécution :  uv run scripts/1_load_data.py
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import pandas as pd

# --- Chemins (résolus relativement à l'emplacement du script, robustes au cwd) ---
ML_DIR = Path(__file__).resolve().parents[1]
RAW_DIR = ML_DIR / "data" / "raw" / "games"
PROCESSED_DIR = ML_DIR / "data" / "processed"
OUT_PARQUET = PROCESSED_DIR / "snapshots_raw.parquet"

EXPECTED_ROWS = 563_632  # référence annoncée par le générateur (sum len(actions))
EXPECTED_RECORDS = 60_033

# Champs record toujours null en self-play — droppés, listés pour la doc/contrôle.
ALWAYS_NULL_RECORD_FIELDS = [
    "humanFinalScore", "humanFinalHandSize", "botFinalHandSize", "pBeatHuman",
    "initialDeck", "turnsBeforeDutch", "discardsPerRound", "triageDecisions",
    "initialHandScore", "initialHandRank", "initialHandRankFromWorst",
]

# Champs record conservés (préfixés rec_ dans le DataFrame).
RECORD_FIELDS = [
    "gameId", "botId", "botName", "botBehavior", "botSkillLevel",
    "numberOfPlayers", "gameMode", "usedSBMM", "startTime", "endTime",
    "initialHandSize", "finalScore", "finalRank", "calledDutch", "wonDutch",
    "cardsAtDutch", "scoreAtDutch", "totalTurns", "avgDecisionTime",
    "powerUsesCount", "goodDecisions", "badDecisions",
]

# Champs gameState scalaires conservés tels quels (préfixés gs_).
GS_SCALAR_FIELDS = [
    "turnCount", "actionCount", "phase", "numberOfPlayers", "botSeatIndex",
    "deckSize", "discardPileSize", "topDiscardValue", "topDiscardPoints",
    "botHandSize", "minOpponentHandSize", "expectedDeckCardValue",
    "dutchCalledAlready", "knownCardCount", "unknownCardCount", "memoryConfidence",
    "believedKnownScore", "maxKnownCardValue", "hasDoublon", "doublonCount",
    "expectedUnknownValueSum", "believedTotalScoreEstimate", "spiedOpponentCardsCount",
    "bestMatchProbability", "botBehavior", "botSkillLevel", "usedSBMM", "aiParams",
]


def log(msg: str) -> None:
    print(msg, flush=True)


def main() -> int:
    if not RAW_DIR.is_dir():
        log(f"[ERREUR] répertoire introuvable : {RAW_DIR}")
        return 1

    files = sorted(RAW_DIR.glob("*.json"))
    n_files = len(files)
    log(f"[1_load_data] répertoire : {RAW_DIR}")
    log(f"[1_load_data] fichiers JSON trouvés : {n_files}")
    if n_files == 0:
        log("[ERREUR] aucun fichier JSON.")
        return 1

    rows: list[dict] = []
    parse_errors: list[tuple[str, str]] = []
    records_ok = 0
    records_zero_actions = 0
    missing_record_fields: dict[str, int] = {}
    missing_gs_fields: dict[str, int] = {}
    nonempty_action_details = 0

    t0 = time.perf_counter()
    for idx, fp in enumerate(files):
        try:
            with fp.open() as f:
                rec = json.load(f)
        except (json.JSONDecodeError, OSError) as exc:
            parse_errors.append((fp.name, str(exc)))
            continue
        records_ok += 1

        # Base record-level (commune à tous les snapshots de ce record).
        base: dict = {}
        for k in RECORD_FIELDS:
            if k not in rec:
                missing_record_fields[k] = missing_record_fields.get(k, 0) + 1
            base[f"rec_{k}"] = rec.get(k)
        base["rec_opponents_json"] = json.dumps(rec.get("opponents"), ensure_ascii=False)
        # Cible dérivée.
        final_rank = rec.get("finalRank")
        base["won"] = 1 if final_rank == 1 else 0

        actions = rec.get("actions") or []
        if len(actions) == 0:
            records_zero_actions += 1

        for s_idx, act in enumerate(actions):
            row = dict(base)
            row["snapshot_index"] = s_idx
            row["actionType"] = act.get("actionType")
            row["turnNumber"] = act.get("turnNumber")
            row["timestamp"] = act.get("timestamp")
            result = act.get("result") or {}
            row["believedScoreAfter"] = result.get("believedScoreAfter")
            if act.get("actionDetails"):
                nonempty_action_details += 1

            gs = act.get("gameState") or {}
            for k in GS_SCALAR_FIELDS:
                if k not in gs:
                    missing_gs_fields[k] = missing_gs_fields.get(k, 0) + 1
                row[f"gs_{k}"] = gs.get(k)
            # Champs imbriqués préservés.
            row["gs_opponentsHandSizes"] = gs.get("opponentsHandSizes")
            row["gs_discardedRanks_json"] = json.dumps(
                gs.get("discardedRanks"), ensure_ascii=False
            )
            rows.append(row)

        if (idx + 1) % 10_000 == 0:
            log(f"  ... {idx + 1}/{n_files} fichiers lus "
                f"({len(rows)} snapshots, {time.perf_counter() - t0:.1f}s)")

    log(f"[1_load_data] lecture terminée en {time.perf_counter() - t0:.1f}s")

    # --- Construction du DataFrame ---
    df = pd.DataFrame(rows)

    # --- CONTRÔLES DE COHÉRENCE ---
    log("\n========== CONTRÔLES DE COHÉRENCE ==========")
    log(f"fichiers trouvés         : {n_files}")
    log(f"records parsés OK        : {records_ok}  (attendu {EXPECTED_RECORDS})")
    log(f"erreurs de parsing       : {len(parse_errors)}")
    if parse_errors:
        for name, err in parse_errors[:10]:
            log(f"    - {name}: {err}")
    log(f"records sans action ([]) : {records_zero_actions}")
    log(f"lignes (snapshots)       : {len(df)}  (attendu {EXPECTED_ROWS})")

    delta_rows = len(df) - EXPECTED_ROWS
    delta_rec = records_ok - EXPECTED_RECORDS
    log(f"écart lignes vs attendu  : {delta_rows:+d}")
    log(f"écart records vs attendu : {delta_rec:+d}")

    log(f"actionDetails non vides  : {nonempty_action_details} (attendu 0)")
    log(f"champs record manquants  : {missing_record_fields or 'aucun'}")
    log(f"champs gameState manquants: {missing_gs_fields or 'aucun'}")

    # believedScoreAfter null doit correspondre aux 'call_dutch' (pas de résultat).
    null_bsa = int(df["believedScoreAfter"].isna().sum())
    n_call_dutch = int((df["actionType"] == "call_dutch").sum())
    n_play_turn = int((df["actionType"] == "play_turn").sum())
    log(f"\nactionType: play_turn={n_play_turn}, call_dutch={n_call_dutch}, "
        f"distinct={sorted(df['actionType'].dropna().unique().tolist())}")
    log(f"believedScoreAfter nulls : {null_bsa}  "
        f"(≈ call_dutch={n_call_dutch} ? {'OK' if null_bsa == n_call_dutch else 'À VÉRIFIER'})")
    log(f"gs_phase distinct        : {sorted(df['gs_phase'].dropna().unique().tolist())}")

    # Sanity cible : la distribution won au niveau record (1 record = 1 finalRank).
    # Clé unique d'un record = (gameId, botName) : botName porte le suffixe de siège
    # (_0/_1/_2), alors que botId est l'archétype et peut se répéter dans une partie.
    rec_level = df.drop_duplicates(subset=["rec_gameId", "rec_botName"])
    won_rate_records = rec_level["won"].mean()
    log(f"\nrecords distincts (gameId+botId) : {len(rec_level)}")
    log(f"won==1 (niveau record)   : {won_rate_records:.4f}  (attendu ≈0.334)")
    by_lvl = rec_level.groupby("rec_botSkillLevel")["won"].agg(["count", "mean"])
    log("win-rate par niveau (record) :")
    for lvl, r in by_lvl.iterrows():
        log(f"    {lvl:<10} n={int(r['count']):>6}  win-rate={r['mean']:.4f}")

    anomalies = []
    if len(parse_errors) > 0:
        anomalies.append(f"{len(parse_errors)} erreurs de parsing")
    if delta_rows != 0:
        anomalies.append(f"écart lignes {delta_rows:+d}")
    if delta_rec != 0:
        anomalies.append(f"écart records {delta_rec:+d}")
    if records_zero_actions > 0:
        anomalies.append(f"{records_zero_actions} records sans action")
    if nonempty_action_details > 0:
        anomalies.append(f"{nonempty_action_details} actionDetails non vides")
    if null_bsa != n_call_dutch:
        anomalies.append("believedScoreAfter nulls != call_dutch")
    log(f"\n>>> ANOMALIES : {anomalies if anomalies else 'AUCUNE'}")

    # --- Sauvegarde parquet ---
    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    df.to_parquet(OUT_PARQUET, engine="pyarrow", index=False)
    size_mb = OUT_PARQUET.stat().st_size / (1024 * 1024)
    log(f"\n[1_load_data] parquet écrit : {OUT_PARQUET} ({size_mb:.1f} MB)")

    # --- Aperçus demandés ---
    log("\n========== df.shape ==========")
    log(str(df.shape))
    log("\n========== df.info() ==========")
    df.info(verbose=True, show_counts=True)
    log("\n========== df.head() ==========")
    with pd.option_context("display.max_columns", None, "display.width", 200):
        log(df.head().to_string())

    return 0


if __name__ == "__main__":
    sys.exit(main())
