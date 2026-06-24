"""
Script 5 — Inférence : prédire P(victoire) à partir d'un état de partie en cours.

Expose deux fonctions :
  - predict_win_proba(snapshot: dict) -> float
  - predict_all_players(game_state: dict) -> dict[str, float]

================================================================================
CHOIX DU MODÈLE : XGBoost (`models/xgboost.joblib`).
Justification (cf. script 4) : c'est le modèle avec la meilleure accuracy-partie
(0.9276, la métrique retenue comme résultat clé) ET le fichier le plus léger (802 KB,
contre 131 Mo pour le RandomForest pourtant très proche en score) — déterminant pour de
l'inférence répétée. RandomForest reste disponible (`models/random_forest.joblib`) si
besoin de comparer.
================================================================================

FORME ATTENDUE DE `snapshot` : un dict `gameState` brut, **du point de vue d'UN bot**, avec
exactement les champs documentés au script 1 (turnCount, actionCount, numberOfPlayers,
botSeatIndex, deckSize, discardPileSize, topDiscardValue, topDiscardPoints, botHandSize,
opponentsHandSizes, minOpponentHandSize, expectedDeckCardValue, discardedRanks,
knownCardCount, unknownCardCount, memoryConfidence, believedKnownScore, maxKnownCardValue,
hasDoublon, doublonCount, expectedUnknownValueSum, believedTotalScoreEstimate,
spiedOpponentCardsCount, bestMatchProbability, botBehavior, botSkillLevel...). C'est
littéralement `record["actions"][i]["gameState"]` dans le JSON brut du générateur.

FORME ATTENDUE DE `game_state` (predict_all_players) : un dict {nom_du_joueur: snapshot},
PAS un état de jeu global unique. Raison : `knownCardCount`, `memoryConfidence`,
`believedTotalScoreEstimate`... sont des croyances SUBJECTIVES propres à chaque bot (sa
propre mémoire, ses propres espions) — il n'existe pas d'état "objectif" unique qui les
contienne toutes pour tous les joueurs en même temps (ni dans les données, ni dans une vraie
partie à information cachée). Donc predict_all_players attend un snapshot par joueur.

PIÈGE ÉVITÉ (one-hot à l'inférence) : pd.get_dummies sur UNE seule ligne ne produit qu'UNE
colonne (celle de la catégorie présente) au lieu des 21 colonnes vues à l'entraînement. Le
`.reindex(columns=FEATURE_COLS, fill_value=0)` après build_features() corrige ça : une
colonne one-hot absente signifie "pas cette catégorie" -> 0 est la valeur sémantiquement
correcte, pas un défaut arbitraire.

Exécution (lance l'exemple en bas de fichier) :  uv run scripts/5_predict.py
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import joblib
import pandas as pd

ML_DIR = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = ML_DIR / "scripts"
MODELS_DIR = ML_DIR / "models"
PROCESSED_DIR = ML_DIR / "data" / "processed"

MODEL_NAME = "xgboost"


def log(msg: str = "") -> None:
    print(msg, flush=True)


def _load_build_features():
    """Importe build_features() depuis 2_features.py par chemin de fichier (nom de module
    invalide pour un `import` standard, commence par un chiffre) — même fonction que les
    scripts 2 et 4, donc même preprocessing garanti par construction (pas de réécriture)."""
    spec = importlib.util.spec_from_file_location(
        "script2_features", SCRIPTS_DIR / "2_features.py"
    )
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.build_features


_METADATA = json.loads((MODELS_DIR / "metadata.json").read_text())
_FEATURE_COLS: list[str] = _METADATA["features"]
_build_features = _load_build_features()
_model = joblib.load(MODELS_DIR / f"{MODEL_NAME}.joblib")


def _snapshot_to_dataframe(snapshot: dict) -> pd.DataFrame:
    """Convertit un dict `gameState` brut en DataFrame 1 ligne au format attendu par
    build_features() (colonnes gs_*, discardedRanks sérialisé en JSON comme à l'ingestion)."""
    row: dict = {}
    for k, v in snapshot.items():
        if k == "discardedRanks":
            row["gs_discardedRanks_json"] = json.dumps(v or {})
        else:
            row[f"gs_{k}"] = v
    return pd.DataFrame([row])


def predict_win_proba(snapshot: dict) -> float:
    """P(victoire) pour UN bot, à partir de son `gameState` brut au moment de décider."""
    df_row = _snapshot_to_dataframe(snapshot)
    feats, _ = _build_features(df_row)
    x_row = feats.reindex(columns=_FEATURE_COLS, fill_value=0)
    return float(_model.predict_proba(x_row)[0, 1])


def predict_all_players(game_state: dict) -> dict[str, float]:
    """P(victoire) pour chaque joueur de `game_state` ({nom: snapshot}, cf. docstring)."""
    return {player: predict_win_proba(snapshot) for player, snapshot in game_state.items()}


def _row_to_snapshot(row: pd.Series, gs_keys: list[str]) -> dict:
    """Inverse de _snapshot_to_dataframe, à partir d'une ligne de snapshots_raw.parquet —
    utilisé uniquement par l'exemple ci-dessous pour rejouer un snapshot réel du dataset."""
    snap = {k: row[f"gs_{k}"] for k in gs_keys}
    snap["opponentsHandSizes"] = list(row["gs_opponentsHandSizes"])
    snap["discardedRanks"] = json.loads(row["gs_discardedRanks_json"])
    return snap


def main() -> int:
    raw_path = PROCESSED_DIR / "snapshots_raw.parquet"
    if not raw_path.exists():
        log(f"[ERREUR] introuvable : {raw_path} (lancer 1_load_data.py d'abord)")
        return 1

    df_raw = pd.read_parquet(raw_path)
    gs_keys = [c[3:] for c in df_raw.columns if c.startswith("gs_") and not c.endswith("_json")]

    log("========== Exemple 1 : predict_win_proba sur un snapshot réel du dataset ==========")
    example = df_raw.iloc[len(df_raw) // 2]
    proba = predict_win_proba(_row_to_snapshot(example, gs_keys))
    log(
        f"bot      : {example['rec_botName']}  (partie {example['rec_gameId']}, "
        f"tour {example['gs_turnCount']}, niveau {example['gs_botSkillLevel']})"
    )
    log(f"P(victoire) prédite : {proba:.4f}")
    log(
        f"résultat réel       : {'GAGNANT' if example['won'] == 1 else 'perdant'} "
        f"(rang final {example['rec_finalRank']})"
    )

    log("\n========== Exemple 2 : predict_all_players sur les derniers snapshots d'une partie ==========")
    log("(\"dernier snapshot connu de chaque bot\" = la même approximation que l'accuracy-partie du script 4)")
    game_id = example["rec_gameId"]
    same_game = df_raw[df_raw["rec_gameId"] == game_id]
    last_per_bot = same_game.sort_values("snapshot_index").groupby("rec_botName").tail(1)

    game_state = {
        row["rec_botName"]: _row_to_snapshot(row, gs_keys) for _, row in last_per_bot.iterrows()
    }
    probs = predict_all_players(game_state)
    true_winners = last_per_bot.loc[last_per_bot["won"] == 1, "rec_botName"].tolist()
    predicted_winner = max(probs, key=lambda name: probs[name])

    log(f"partie : {game_id}  (vrai gagnant : {true_winners})")
    for name, p in sorted(probs.items(), key=lambda kv: -kv[1]):
        marker = "  <-- prédit gagnant" if name == predicted_winner else ""
        log(f"  {name:<25} P(victoire)={p:.4f}{marker}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
