"""
Script 3 — Entraînement : baseline LogReg + RandomForest + XGBoost, CV groupée par partie.

Charge `data/processed/features_train.parquet` (sortie du script 2 — déjà splitté, déjà
anti-leakage). `features_test.parquet` N'EST PAS touché ici : réservé à l'évaluation finale
(script 4). Toute mesure de performance dans CE script vient uniquement de la validation
croisée groupée (GroupKFold) sur le train.

================================================================================
RÈGLE ANTI-FUITE EN CV : même logique que le split train/test du script 2 — les folds de CV
sont groupés par `rec_gameId` (GroupKFold), jamais un split aléatoire ligne-à-ligne. Sinon,
des snapshots de la même partie se retrouveraient à la fois dans le fold d'entraînement et le
fold de validation interne -> fuite par corrélation intra-partie, exactement le risque déjà
neutralisé au script 2 pour train/test.
================================================================================

Déséquilibre de classes (won ≈ 38% au niveau ligne sur le train, cf. script 2) :
  - LogisticRegression / RandomForest : class_weight='balanced' (réinjecte le déséquilibre
    dans la fonction de perte via des poids inversement proportionnels à la fréquence de
    classe — calculé en interne par sklearn).
  - XGBoost : pas de class_weight natif -> scale_pos_weight = n_négatifs / n_positifs, calculé
    une fois depuis le ratio RÉEL du train complet (pas recalculé par fold : pratique standard,
    la valeur ne bouge presque pas entre folds avec un GroupKFold à 5 plis sur 16 000 parties).

Seeds : random_state=42 partout où c'est applicable (LogisticRegression, RandomForestClassifier,
XGBClassifier) — même valeur que RANDOM_STATE du script 2, un seul seed nommé pour tout le
pipeline. GroupKFold n'a PAS de paramètre random_state : il ne mélange pas les groupes, le
découpage en plis est déterministe par construction (dépend seulement de l'ordre d'apparition
des groupes dans les données, lui-même fixé puisque le parquet est écrit une fois pour toutes).

Exécution :  uv run scripts/3_train.py
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import sklearn
import xgboost
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import GridSearchCV, GroupKFold, cross_validate
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from xgboost import XGBClassifier

ML_DIR = Path(__file__).resolve().parents[1]
PROCESSED_DIR = ML_DIR / "data" / "processed"
MODELS_DIR = ML_DIR / "models"
IN_TRAIN = PROCESSED_DIR / "features_train.parquet"

TARGET = "won"
GROUP_KEY = "rec_gameId"
RANDOM_STATE = 42
N_SPLITS = 5

# Colonnes one-hot produites par pd.get_dummies au script 2 (préfixes identifiables) -> le
# reste de X est numérique. Dérivé par préfixe plutôt que recopié en dur : reste correct si
# le script 2 rencontre de nouvelles valeurs catégorielles (ex. nouveau rang de carte).
DUMMY_PREFIXES = ("gs_topDiscardValue_", "gs_botBehavior_", "gs_botSkillLevel_")

# RandomForest : grille de recherche pour contraindre les arbres (CV initiale = arbres non
# bridés, AUC=0.8392 et fichier .joblib de 2.6 Go -> signe de surapprentissage/mémorisation).
# Bornes demandées explicitement : max_depth in [10,15], min_samples_leaf in [5,20].
RF_PARAM_GRID = {
    "clf__max_depth": [10, 15],
    "clf__min_samples_leaf": [5, 20],
}
RF_BASELINE_AUC = 0.8392  # CV précédente (arbres non bridés) — seuil de non-régression.


def log(msg: str = "") -> None:
    print(msg, flush=True)


def split_numeric_dummy_columns(columns: list[str]) -> tuple[list[str], list[str]]:
    dummy_cols = [c for c in columns if c.startswith(DUMMY_PREFIXES)]
    numeric_cols = [c for c in columns if c not in dummy_cols]
    return numeric_cols, dummy_cols


def build_models(
    numeric_cols: list[str], scale_pos_weight: float
) -> dict[str, Pipeline]:
    """Un pipeline complet par modèle (mêmes colonnes X en entrée pour les 3)."""
    # LogReg : sensible à l'échelle -> imputation + standardisation des numériques ; les
    # colonnes one-hot (déjà 0/1) passent inchangées (remainder='passthrough').
    logreg_preprocessor = ColumnTransformer(
        transformers=[
            (
                "num",
                Pipeline(
                    [
                        ("imputer", SimpleImputer(strategy="median")),
                        ("scaler", StandardScaler()),
                    ]
                ),
                numeric_cols,
            ),
        ],
        remainder="passthrough",
    )
    logreg = Pipeline(
        [
            ("preprocessor", logreg_preprocessor),
            (
                "clf",
                LogisticRegression(
                    class_weight="balanced", max_iter=1000, random_state=RANDOM_STATE
                ),
            ),
        ]
    )

    # RandomForest : invariant à l'échelle -> pas de scaler, juste une imputation défensive
    # (0 NaN connus dans X, cf. script 2, mais le pipeline reste robuste si ça change).
    rf = Pipeline(
        [
            ("imputer", SimpleImputer(strategy="median")),
            (
                "clf",
                RandomForestClassifier(
                    n_estimators=200,
                    class_weight="balanced",
                    random_state=RANDOM_STATE,
                    n_jobs=-1,
                ),
            ),
        ]
    )

    # XGBoost : gère nativement les NaN éventuels, pas d'imputation nécessaire.
    xgb = Pipeline(
        [
            (
                "clf",
                XGBClassifier(
                    n_estimators=200,
                    scale_pos_weight=scale_pos_weight,
                    random_state=RANDOM_STATE,
                    eval_metric="logloss",
                    n_jobs=-1,
                ),
            ),
        ]
    )

    return {"logreg": logreg, "random_forest": rf, "xgboost": xgb}


def main() -> int:
    if not IN_TRAIN.exists():
        log(f"[ERREUR] introuvable : {IN_TRAIN} (lancer 2_features.py d'abord)")
        return 1

    df = pd.read_parquet(IN_TRAIN)
    log(f"[3_train] features_train chargé : {df.shape}")

    y = df[TARGET].astype("int8")
    groups = df[GROUP_KEY]
    X = df.drop(columns=[TARGET, GROUP_KEY])

    numeric_cols, dummy_cols = split_numeric_dummy_columns(list(X.columns))
    log(f"colonnes numériques : {len(numeric_cols)}")
    log(f"colonnes one-hot    : {len(dummy_cols)}")
    assert len(numeric_cols) + len(dummy_cols) == X.shape[1]

    n_pos = int(y.sum())
    n_neg = int(len(y) - n_pos)
    scale_pos_weight = n_neg / n_pos
    log(f"\nclasses train : positifs={n_pos} ({n_pos / len(y):.4f}), négatifs={n_neg}")
    log(f"scale_pos_weight (XGBoost)      = {n_neg}/{n_pos} = {scale_pos_weight:.4f}")
    log(
        "class_weight='balanced' (LogReg, RandomForest) -> calculé en interne par sklearn "
        "depuis ces mêmes fréquences de classe."
    )

    models = build_models(numeric_cols, scale_pos_weight)

    log(f"\n========== SEEDS ==========")
    log(f"RANDOM_STATE = {RANDOM_STATE}  (LogisticRegression, RandomForestClassifier, XGBClassifier)")
    log("GroupKFold n'a pas de random_state : découpage déterministe par construction "
        "(pas de mélange des groupes), donc rien à fixer ici.")

    log(f"\n========== VALIDATION CROISÉE GROUPÉE (GroupKFold, n_splits={N_SPLITS}) ==========")
    log(f"groupes = {GROUP_KEY} ({groups.nunique()} parties distinctes dans le train)")
    cv = GroupKFold(n_splits=N_SPLITS)
    cv_results: dict[str, dict] = {}

    for name, pipeline in models.items():
        if name == "random_forest":
            continue  # traité séparément ci-dessous (grid search sur max_depth/min_samples_leaf)
        t0 = time.perf_counter()
        scores = cross_validate(
            pipeline,
            X,
            y,
            groups=groups,
            cv=cv,
            scoring=["roc_auc", "f1"],
            n_jobs=1,
            return_train_score=False,
        )
        elapsed = time.perf_counter() - t0
        auc_mean, auc_std = scores["test_roc_auc"].mean(), scores["test_roc_auc"].std()
        f1_mean, f1_std = scores["test_f1"].mean(), scores["test_f1"].std()
        cv_results[name] = {
            "roc_auc_mean": float(auc_mean),
            "roc_auc_std": float(auc_std),
            "f1_mean": float(f1_mean),
            "f1_std": float(f1_std),
            "roc_auc_folds": scores["test_roc_auc"].tolist(),
            "f1_folds": scores["test_f1"].tolist(),
        }
        log(f"\n{name} ({elapsed:.1f}s) :")
        log(
            f"  AUC : {auc_mean:.4f} ± {auc_std:.4f}  "
            f"(folds: {np.round(scores['test_roc_auc'], 4).tolist()})"
        )
        log(
            f"  F1  : {f1_mean:.4f} ± {f1_std:.4f}  "
            f"(folds: {np.round(scores['test_f1'], 4).tolist()})"
        )

    # --- RandomForest : grid search (même CV groupée) sur max_depth / min_samples_leaf ---
    # Motivation : CV précédente = arbres non bridés (max_depth=None) -> AUC le plus bas des
    # 3 modèles (0.8392) ET fichier .joblib de 2.6 Go -> signe de surapprentissage (arbres
    # profonds qui mémorisent du bruit plutôt que de généraliser). On cherche un AUC stable ou
    # meilleur avec des arbres bridés, nettement plus légers.
    log(f"\n========== GRID SEARCH RandomForest (GroupKFold, n_splits={N_SPLITS}) ==========")
    log(f"grille : {RF_PARAM_GRID}")
    t0 = time.perf_counter()
    rf_grid = GridSearchCV(
        models["random_forest"],
        param_grid=RF_PARAM_GRID,
        scoring={"roc_auc": "roc_auc", "f1": "f1"},
        refit="roc_auc",
        cv=cv,
        n_jobs=1,  # le RF interne parallélise déjà (n_jobs=-1) -> évite la sur-souscription CPU
        return_train_score=False,
    )
    rf_grid.fit(X, y, groups=groups)
    elapsed = time.perf_counter() - t0

    log(f"\ntoutes les combinaisons testées ({elapsed:.1f}s total) :")
    for params, auc_m, auc_s, f1_m, f1_s in zip(
        rf_grid.cv_results_["params"],
        rf_grid.cv_results_["mean_test_roc_auc"],
        rf_grid.cv_results_["std_test_roc_auc"],
        rf_grid.cv_results_["mean_test_f1"],
        rf_grid.cv_results_["std_test_f1"],
    ):
        log(f"  {params}  ->  AUC={auc_m:.4f}±{auc_s:.4f}  F1={f1_m:.4f}±{f1_s:.4f}")

    best_idx = rf_grid.best_index_
    rf_auc_mean = float(rf_grid.cv_results_["mean_test_roc_auc"][best_idx])
    rf_auc_std = float(rf_grid.cv_results_["std_test_roc_auc"][best_idx])
    rf_f1_mean = float(rf_grid.cv_results_["mean_test_f1"][best_idx])
    rf_f1_std = float(rf_grid.cv_results_["std_test_f1"][best_idx])
    log(f"\nmeilleure combinaison : {rf_grid.best_params_}")
    log(f"  AUC : {rf_auc_mean:.4f} ± {rf_auc_std:.4f}  "
        f"({'>=' if rf_auc_mean >= RF_BASELINE_AUC else '<'} baseline non bridée {RF_BASELINE_AUC})")
    log(f"  F1  : {rf_f1_mean:.4f} ± {rf_f1_std:.4f}")

    cv_results["random_forest"] = {
        "roc_auc_mean": rf_auc_mean,
        "roc_auc_std": rf_auc_std,
        "f1_mean": rf_f1_mean,
        "f1_std": rf_f1_std,
        "best_params": rf_grid.best_params_,
        "grid_search_all_combos": [
            {
                "params": p,
                "roc_auc_mean": float(a),
                "roc_auc_std": float(asd),
                "f1_mean": float(f),
                "f1_std": float(fsd),
            }
            for p, a, asd, f, fsd in zip(
                rf_grid.cv_results_["params"],
                rf_grid.cv_results_["mean_test_roc_auc"],
                rf_grid.cv_results_["std_test_roc_auc"],
                rf_grid.cv_results_["mean_test_f1"],
                rf_grid.cv_results_["std_test_f1"],
            )
        ],
    }
    # best_estimator_ est déjà ré-entraîné par GridSearchCV(refit="roc_auc") sur l'intégralité
    # de X/y avec les meilleurs hyperparamètres -> remplace l'entrée non bridée dans `models`.
    models["random_forest"] = rf_grid.best_estimator_

    log("\n========== RÉSUMÉ CV ==========")
    log(f"{'modèle':<15} {'AUC':>20} {'F1':>20}")
    for name, r in cv_results.items():
        log(
            f"{name:<15} {r['roc_auc_mean']:.4f} ± {r['roc_auc_std']:.4f}        "
            f"{r['f1_mean']:.4f} ± {r['f1_std']:.4f}"
        )

    # --- Entraînement final sur l'intégralité du train (les modèles sauvegardés ne voient
    # jamais le test, réservé au script 4) ---
    log("\n========== ENTRAÎNEMENT FINAL (train complet) ==========")
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    for name, pipeline in models.items():
        t0 = time.perf_counter()
        pipeline.fit(X, y)
        elapsed = time.perf_counter() - t0
        out_path = MODELS_DIR / f"{name}.joblib"
        joblib.dump(pipeline, out_path)
        log(
            f"{name:<15} entraîné en {elapsed:.1f}s -> {out_path} "
            f"({out_path.stat().st_size / 1024:.0f} KB)"
        )

    # --- Metadata ---
    metadata = {
        "random_state": RANDOM_STATE,
        "n_splits_cv": N_SPLITS,
        "target": TARGET,
        "group_key": GROUP_KEY,
        "features": list(X.columns),
        "n_features": X.shape[1],
        "numeric_features": numeric_cols,
        "dummy_features": dummy_cols,
        "train_shape": list(X.shape),
        "n_games_train": int(groups.nunique()),
        "class_balance_train": {
            "n_pos": n_pos,
            "n_neg": n_neg,
            "pos_rate": n_pos / len(y),
        },
        "scale_pos_weight_xgboost": scale_pos_weight,
        "cv_results": cv_results,
        "versions": {
            "python": sys.version,
            "pandas": pd.__version__,
            "numpy": np.__version__,
            "sklearn": sklearn.__version__,
            "xgboost": xgboost.__version__,
        },
        "models": {
            name: {
                "type": pipeline.named_steps["clf"].__class__.__name__,
                "params": {
                    k: v
                    for k, v in pipeline.named_steps["clf"].get_params().items()
                    if isinstance(v, (int, float, str, bool, type(None)))
                },
            }
            for name, pipeline in models.items()
        },
    }
    meta_path = MODELS_DIR / "metadata.json"
    meta_path.write_text(json.dumps(metadata, indent=2, ensure_ascii=False))
    log(f"\n[3_train] metadata écrite : {meta_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
