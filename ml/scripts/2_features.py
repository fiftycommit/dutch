"""
Script 2 — Feature engineering anti-leakage + split groupé par partie.

Charge `data/processed/snapshots_raw.parquet` (sortie du script 1, 1 ligne = 1 snapshot),
construit la matrice de features X et la cible y = `won` (déjà dérivée de `finalRank == 1`),
puis un split train/test 80/20 GROUPÉ PAR PARTIE (`rec_gameId`) via GroupShuffleSplit.

================================================================================
RÈGLE D'OR : seuls les champs `gs_*` (état observable par le bot AU MOMENT de décider,
capturé dans `actions[i].gameState`) sont des features candidates légitimes. Tout `rec_*`
est une métadonnée ou un résultat de fin de partie, donc exclu par construction — sauf
`rec_gameId`, gardé à part comme clé de groupe pour le split (jamais comme feature).
================================================================================

--------------------------------------------------------------------------------
BLOCKLIST EXPLICITE (jamais en feature — cf. BLOCKLIST ci-dessous pour le détail) :
--------------------------------------------------------------------------------
  - won                         : LA CIBLE.
  - rec_finalScore, rec_finalRank, rec_calledDutch, rec_wonDutch, rec_cardsAtDutch,
    rec_scoreAtDutch, rec_totalTurns, rec_avgDecisionTime, rec_powerUsesCount,
    rec_goodDecisions, rec_badDecisions
                                : résultats/stats connus seulement EN FIN de partie → fuite.
  - believedScoreAfter          : champ `result.*` = état APRÈS l'action → fuite (la cible
                                    de chaque snapshot doit ignorer ce qui se passe après lui).
  - actionType                  : DISCUTÉ, exclu par défaut (voir section dédiée plus bas) —
                                    pas une fuite au sens strict (c'est une action observable
                                    au temps t), mais un proxy de décision (annoncer Dutch
                                    encode déjà "je crois être en tête") plutôt qu'un état de
                                    plateau brut ; les features de croyance (b) capturent déjà
                                    cette information de façon plus granulaire.
  - timestamp, rec_startTime, rec_endTime
                                : horloge virtuelle déterministe du générateur, aucun sens
                                    prédictif réel (cf. README).
  - rec_gameId, rec_botId, rec_botName, snapshot_index
                                : identifiants. `rec_gameId` est gardé À PART comme clé de
                                    groupe pour le split, jamais comme colonne de X.
  - rec_botBehavior, rec_botSkillLevel, rec_numberOfPlayers, rec_gameMode, rec_usedSBMM,
    rec_initialHandSize, rec_opponents_json
                                : hors scope (règle "uniquement gs_*") — gs_botBehavior et
                                    gs_botSkillLevel sont les équivalents utilisés ; les
                                    autres seraient des features légitimes (notamment le
                                    profil des adversaires via rec_opponents_json) mais ne
                                    sont PAS demandés dans la spec de cette itération.

--------------------------------------------------------------------------------
CONTRADICTIONS DONNÉES RÉELLES vs SPEC DEMANDÉE (vérifiées empiriquement, voir
investigation préalable) — SIGNALÉES ICI, le code/les données font foi :
--------------------------------------------------------------------------------
  - `turnsSinceDutch` (demandé en feature (a)) : IMPOSSIBLE À DÉRIVER. Le générateur ne
    logge un snapshot que pendant `GamePhase.playing` (`gs_phase` est constant à 'playing'
    sur les 563 632 lignes) ; aucun snapshot n'est jamais pris après qu'un Dutch a été
    appelé. `gs_dutchCalledAlready` est donc également **constant à False** sur l'intégralité
    du dataset (vérifié : 0/60 033 records montrent une transition False→True). Les deux
    champs sont exclus : `turnsSinceDutch` n'existe nulle part dans les données, et
    `dutchCalledAlready` a une variance nulle (aucune information).
  - `relativePosition` (demandé en feature (a)) : n'existe pas comme champ brut. Dérivé de
    `gs_botSeatIndex` (constant par record, vérifié) et `gs_numberOfPlayers` (qui varie
    réellement : 2/3/4 joueurs selon la partie, vérifié via crosstab) :
        relative_seat_position = botSeatIndex / (numberOfPlayers - 1)  ∈ [0, 1]
    Normalisation nécessaire car le siège brut n'est pas comparable entre tables de tailles
    différentes.
  - `gs_phase`, `gs_usedSBMM`, `gs_aiParams` (demandés/listés) : variance nulle dans ce
    dataset (constants 'playing' / False / null) → droppés, zéro information mais pas une
    fuite. À surveiller si un futur dataset mélange SBMM on/off ou plusieurs phases logguées.

Exécution :  uv run scripts/2_features.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.model_selection import GroupShuffleSplit

ML_DIR = Path(__file__).resolve().parents[1]
PROCESSED_DIR = ML_DIR / "data" / "processed"
IN_PARQUET = PROCESSED_DIR / "snapshots_raw.parquet"
OUT_TRAIN = PROCESSED_DIR / "features_train.parquet"
OUT_TEST = PROCESSED_DIR / "features_test.parquet"

TARGET = "won"
GROUP_KEY = "rec_gameId"
TEST_SIZE = 0.2
RANDOM_STATE = 42

# Champs rec_* dont la fuite est explicitement vérifiée et documentée (résultat de fin
# de partie). Présents dans le parquet mais jamais dans X.
BLOCKLIST_LEAKAGE_REC = [
    "rec_finalScore", "rec_finalRank", "rec_calledDutch", "rec_wonDutch",
    "rec_cardsAtDutch", "rec_scoreAtDutch", "rec_totalTurns", "rec_avgDecisionTime",
    "rec_powerUsesCount", "rec_goodDecisions", "rec_badDecisions",
]
BLOCKLIST_LEAKAGE_OTHER = ["believedScoreAfter"]
BLOCKLIST_DISCUSSED_EXCLUDED = ["actionType"]
BLOCKLIST_NO_PREDICTIVE_VALUE = ["timestamp", "rec_startTime", "rec_endTime"]
BLOCKLIST_IDENTIFIERS = ["rec_gameId", "rec_botId", "rec_botName", "snapshot_index"]
BLOCKLIST_OUT_OF_SCOPE_REC = [
    "rec_botBehavior", "rec_botSkillLevel", "rec_numberOfPlayers", "rec_gameMode",
    "rec_usedSBMM", "rec_initialHandSize", "rec_opponents_json",
]
# Champs gs_* candidats mais retirés car non dérivables ou variance nulle (constatation
# empirique, cf. docstring).
DROPPED_GS_ZERO_VARIANCE = {
    "gs_phase": "constant 'playing' (aucun snapshot post-Dutch loggué)",
    "gs_usedSBMM": "constant False dans ce dataset self-play",
    "gs_aiParams": "toujours null",
    "gs_dutchCalledAlready": "constant False (jamais de transition observée)",
}
NOT_DERIVABLE = {
    "turnsSinceDutch": "aucun snapshot post-Dutch dans les données (cf. gs_dutchCalledAlready)",
}


def log(msg: str = "") -> None:
    print(msg, flush=True)


def build_features(df: pd.DataFrame) -> tuple[pd.DataFrame, list[str]]:
    """Construit X à partir des seules colonnes gs_* + dérivés numériques explicites."""
    feats = pd.DataFrame(index=df.index)
    notes: list[str] = []

    # --- (a) état public ---
    feats["gs_turnCount"] = df["gs_turnCount"].astype("int32")
    feats["gs_actionCount"] = df["gs_actionCount"].astype("int32")
    feats["gs_numberOfPlayers"] = df["gs_numberOfPlayers"].astype("int8")

    # relativePosition dérivé (n'existe pas en brut, cf. docstring).
    feats["relative_seat_position"] = (
        df["gs_botSeatIndex"] / (df["gs_numberOfPlayers"] - 1)
    ).astype("float32")

    feats["gs_deckSize"] = df["gs_deckSize"].astype("int32")
    feats["gs_discardPileSize"] = df["gs_discardPileSize"].astype("int32")
    feats["gs_topDiscardPoints"] = df["gs_topDiscardPoints"].astype("int32")
    feats["gs_botHandSize"] = df["gs_botHandSize"].astype("int32")
    feats["gs_minOpponentHandSize"] = df["gs_minOpponentHandSize"].astype("int32")

    # opponentsHandSizes (liste brute interdite) -> agrégats numériques uniquement.
    opp_hands = df["gs_opponentsHandSizes"]
    opp_min = opp_hands.apply(np.min).astype("int32")
    opp_max = opp_hands.apply(np.max).astype("int32")
    opp_mean = opp_hands.apply(np.mean).astype("float32")
    mismatch = int((opp_min != df["gs_minOpponentHandSize"]).sum())
    if mismatch:
        notes.append(
            f"ANOMALIE: opp_hand_min dérivé != gs_minOpponentHandSize sur {mismatch} lignes"
        )
    else:
        notes.append(
            "sanity OK: min(gs_opponentsHandSizes) == gs_minOpponentHandSize sur 100% des lignes "
            "-> gs_minOpponentHandSize gardé, opp_hand_min dérivé non dupliqué"
        )
    feats["opp_hand_max"] = opp_max
    feats["opp_hand_mean"] = opp_mean

    feats["gs_expectedDeckCardValue"] = df["gs_expectedDeckCardValue"].astype("float32")

    # discardedRanks (JSON brut interdit) -> résumé numérique uniquement.
    discarded = df["gs_discardedRanks_json"].apply(json.loads)
    feats["discarded_total_count"] = discarded.apply(lambda d: sum(d.values())).astype("int32")
    feats["discarded_distinct_ranks"] = discarded.apply(len).astype("int8")

    # --- (b) état de croyance ---
    feats["gs_knownCardCount"] = df["gs_knownCardCount"].astype("int32")
    feats["gs_unknownCardCount"] = df["gs_unknownCardCount"].astype("int32")
    feats["gs_memoryConfidence"] = df["gs_memoryConfidence"].astype("float32")
    feats["gs_believedKnownScore"] = df["gs_believedKnownScore"].astype("int32")
    feats["gs_maxKnownCardValue"] = df["gs_maxKnownCardValue"].astype("int32")
    feats["gs_hasDoublon"] = df["gs_hasDoublon"].astype("int8")
    feats["gs_doublonCount"] = df["gs_doublonCount"].astype("int32")
    feats["gs_expectedUnknownValueSum"] = df["gs_expectedUnknownValueSum"].astype("float32")
    feats["gs_believedTotalScoreEstimate"] = df["gs_believedTotalScoreEstimate"].astype("float32")
    feats["gs_spiedOpponentCardsCount"] = df["gs_spiedOpponentCardsCount"].astype("int32")
    feats["gs_bestMatchProbability"] = df["gs_bestMatchProbability"].astype("float32")

    # --- (c) params bot (catégoriels -> one-hot) ---
    dummies_topdiscard = pd.get_dummies(df["gs_topDiscardValue"], prefix="gs_topDiscardValue")
    dummies_behavior = pd.get_dummies(df["gs_botBehavior"], prefix="gs_botBehavior")
    dummies_skill = pd.get_dummies(df["gs_botSkillLevel"], prefix="gs_botSkillLevel")
    for d in (dummies_topdiscard, dummies_behavior, dummies_skill):
        for col in d.columns:
            feats[col] = d[col].astype("int8")

    for line in notes:
        log(f"  [build_features] {line}")

    return feats, notes


def main() -> int:
    if not IN_PARQUET.exists():
        log(f"[ERREUR] introuvable : {IN_PARQUET} (lancer 1_load_data.py d'abord)")
        return 1

    df = pd.read_parquet(IN_PARQUET)
    log(f"[2_features] snapshots_raw chargé : {df.shape}")

    log("\n========== BLOCKLIST (jamais en feature) ==========")
    log(f"fuite (rec_* résultat fin de partie) : {BLOCKLIST_LEAKAGE_REC}")
    log(f"fuite (result.* post-action)         : {BLOCKLIST_LEAKAGE_OTHER}")
    log(f"discuté, exclu par défaut             : {BLOCKLIST_DISCUSSED_EXCLUDED}")
    log(f"sans valeur prédictive (horloge)      : {BLOCKLIST_NO_PREDICTIVE_VALUE}")
    log(f"identifiants (gameId = clé de groupe) : {BLOCKLIST_IDENTIFIERS}")
    log(f"rec_* hors scope (règle 'uniquement gs_*') : {BLOCKLIST_OUT_OF_SCOPE_REC}")
    log("\n========== gs_* retirés (variance nulle / non dérivable) ==========")
    for k, v in DROPPED_GS_ZERO_VARIANCE.items():
        log(f"  {k:<25} : {v}")
    for k, v in NOT_DERIVABLE.items():
        log(f"  {k:<25} : {v}  [demandé mais IMPOSSIBLE A DERIVER]")

    target = df[TARGET].astype("int8")
    groups = df[GROUP_KEY]

    log("\n========== CONSTRUCTION DES FEATURES ==========")
    X, _ = build_features(df)

    feature_cols = list(X.columns)
    log(f"\n========== LISTE FINALE DES FEATURES ({len(feature_cols)}) ==========")
    for col in feature_cols:
        log(f"  {col:<35} {X[col].dtype}")

    log(f"\nX.shape = {X.shape}")
    n_nan = int(X.isna().sum().sum())
    log(f"NaN dans X : {n_nan} (attendu 0)")
    if n_nan:
        log(f"  colonnes concernées : {X.isna().sum()[lambda s: s > 0].to_dict()}")

    # --- Split groupé par partie ---
    log("\n========== SPLIT GROUPÉ PAR PARTIE (GroupShuffleSplit) ==========")
    log("Raison : les snapshots d'une même partie sont corrélés (même issue finale) ;")
    log("un split aléatoire ligne-à-ligne mettrait des snapshots de LA MÊME partie à la")
    log("fois en train et en test -> fuite d'information par corrélation intra-groupe.")

    splitter = GroupShuffleSplit(n_splits=1, test_size=TEST_SIZE, random_state=RANDOM_STATE)
    train_idx, test_idx = next(splitter.split(X, target, groups))

    X_train, X_test = X.iloc[train_idx], X.iloc[test_idx]
    y_train, y_test = target.iloc[train_idx], target.iloc[test_idx]
    groups_train, groups_test = groups.iloc[train_idx], groups.iloc[test_idx]

    train_games = set(groups_train.unique())
    test_games = set(groups_test.unique())
    overlap = train_games & test_games

    log(f"\nX_train.shape = {X_train.shape}   y_train.shape = {y_train.shape}")
    log(f"X_test.shape  = {X_test.shape}   y_test.shape  = {y_test.shape}")
    log(f"lignes : train={len(X_train)} ({len(X_train) / len(X):.1%}), "
        f"test={len(X_test)} ({len(X_test) / len(X):.1%})")
    log(f"parties distinctes : train={len(train_games)}, test={len(test_games)}, "
        f"total={len(train_games | test_games)}")
    log(f"parties en commun train/test : {len(overlap)}  "
        f"({'OK — split groupé propre' if not overlap else 'ANOMALIE CRITIQUE'})")
    assert not overlap, "fuite de split détectée : un gameId est à cheval train/test"

    log(f"\nwon rate train : {y_train.mean():.4f}")
    log(f"won rate test  : {y_test.mean():.4f}")

    # --- Sauvegarde (X + cible + clé de groupe, pour rechargement direct par le script 3) ---
    PROCESSED_DIR.mkdir(parents=True, exist_ok=True)
    train_out = X_train.copy()
    train_out[TARGET] = y_train.values
    train_out[GROUP_KEY] = groups_train.values
    test_out = X_test.copy()
    test_out[TARGET] = y_test.values
    test_out[GROUP_KEY] = groups_test.values

    train_out.to_parquet(OUT_TRAIN, engine="pyarrow", index=False)
    test_out.to_parquet(OUT_TEST, engine="pyarrow", index=False)
    log(f"\n[2_features] écrit : {OUT_TRAIN} ({OUT_TRAIN.stat().st_size / 1024:.0f} KB)")
    log(f"[2_features] écrit : {OUT_TEST} ({OUT_TEST.stat().st_size / 1024:.0f} KB)")
    log("(colonnes 'won' et 'rec_gameId' incluses pour traçabilité — à exclure de X par le "
        "script d'entraînement avant fit)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
