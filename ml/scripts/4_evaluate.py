"""
Script 4 — Évaluation finale sur le test set (jamais vu : ni en train, ni en CV groupée).

Charge les 3 modèles entraînés (script 3) + `features_test.parquet` (script 2), et calcule :
  1. Métriques classiques (accuracy, precision, recall, F1, ROC-AUC, matrice de confusion)
     pour les 3 modèles, comparées à deux baselines triviales (DummyClassifier).
  2. Courbes ROC + matrices de confusion + importances de features -> PNG dans `ml/reports/`.
  3. Importance des features : natif (RF/XGB) ou coefficients (LogReg).
  4. Une métrique "accuracy-partie" : pour chaque partie du test, on prend le DERNIER snapshot
     de chaque bot (l'état le plus informé) et on regarde si argmax(proba) tombe sur le vrai
     gagnant — distinct de l'accuracy-ligne, qui traite chaque snapshot indépendamment.

================================================================================
ACCURACY-LIGNE vs ACCURACY-PARTIE (rappel du script 2) : le taux `won` au niveau ligne (~38%)
diffère du taux au niveau record (~33%) parce que les parties gagnantes ont en moyenne plus de
snapshots (parties plus longues côté gagnant). L'accuracy-ligne mesure donc une moyenne biaisée
par la longueur des parties ; l'accuracy-partie répond à la question métier réelle : "le modèle
aurait-il deviné le bon gagnant à la fin de la partie ?".
================================================================================

Pour l'accuracy-partie, on a besoin de l'identité du bot (`rec_botName`) et de l'ordre des
snapshots (`snapshot_index`) au sein de chaque partie — des colonnes volontairement absentes de
`features_test.parquet` (ce sont des identifiants, jamais des features, cf. BLOCKLIST script 2).
On les récupère en filtrant `snapshots_raw.parquet` sur les `rec_gameId` du test (le split est
groupé par partie : tous les snapshots d'une partie sont du même côté train/test, donc ce filtre
reconstruit exactement les lignes de test), puis en reconstruisant X via `build_features()` du
script 2 (importé par chemin de fichier — `2_features.py` n'est pas un nom de module Python
valide pour un `import` standard, le nom commence par un chiffre).

Exécution :  uv run scripts/4_evaluate.py
"""

from __future__ import annotations

import importlib.util
import json
import sys
import types
from pathlib import Path

import joblib
import matplotlib

matplotlib.use("Agg")  # génération de PNG seulement, pas d'affichage interactif
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.dummy import DummyClassifier
from sklearn.metrics import (
    ConfusionMatrixDisplay,
    accuracy_score,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
    roc_curve,
)

ML_DIR = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = ML_DIR / "scripts"
PROCESSED_DIR = ML_DIR / "data" / "processed"
MODELS_DIR = ML_DIR / "models"
REPORTS_DIR = ML_DIR / "reports"

IN_TRAIN = PROCESSED_DIR / "features_train.parquet"
IN_TEST = PROCESSED_DIR / "features_test.parquet"
IN_RAW = PROCESSED_DIR / "snapshots_raw.parquet"
META_PATH = MODELS_DIR / "metadata.json"

TARGET = "won"
GROUP_KEY = "rec_gameId"
RANDOM_STATE = 42
MODEL_NAMES = ["logreg", "random_forest", "xgboost"]


def log(msg: str = "") -> None:
    print(msg, flush=True)


def load_build_features() -> types.FunctionType:
    """Importe build_features() depuis 2_features.py par chemin de fichier (nom de module
    invalide pour un `import` standard, commence par un chiffre)."""
    spec = importlib.util.spec_from_file_location(
        "script2_features", SCRIPTS_DIR / "2_features.py"
    )
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.build_features


def compute_metrics(y_true, y_pred, y_proba) -> dict:
    return {
        "accuracy": float(accuracy_score(y_true, y_pred)),
        "precision": float(precision_score(y_true, y_pred, zero_division=0)),
        "recall": float(recall_score(y_true, y_pred, zero_division=0)),
        "f1": float(f1_score(y_true, y_pred, zero_division=0)),
        "roc_auc": float(roc_auc_score(y_true, y_proba)) if y_proba is not None else float("nan"),
    }


def main() -> int:
    for p in (IN_TRAIN, IN_TEST, IN_RAW, META_PATH):
        if not p.exists():
            log(f"[ERREUR] introuvable : {p}")
            return 1

    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    metadata = json.loads(META_PATH.read_text())
    feature_cols: list[str] = metadata["features"]
    numeric_cols: list[str] = metadata["numeric_features"]
    dummy_cols: list[str] = metadata["dummy_features"]
    logreg_feature_order = numeric_cols + dummy_cols

    df_train = pd.read_parquet(IN_TRAIN)
    df_test = pd.read_parquet(IN_TEST)
    y_train = df_train[TARGET].astype("int8")
    X_train = df_train[feature_cols]
    y_test = df_test[TARGET].astype("int8")
    X_test = df_test[feature_cols]
    log(f"[4_evaluate] train={X_train.shape}  test={X_test.shape}  won rate test={y_test.mean():.4f}")

    models = {name: joblib.load(MODELS_DIR / f"{name}.joblib") for name in MODEL_NAMES}

    # --- Baselines triviales (entraînées sur le train, comme les vrais modèles) ---
    baselines = {
        "dummy_most_frequent": DummyClassifier(strategy="most_frequent"),
        "dummy_stratified": DummyClassifier(strategy="stratified", random_state=RANDOM_STATE),
    }
    for clf in baselines.values():
        clf.fit(X_train, y_train)

    all_models = {**models, **baselines}
    all_metrics: dict[str, dict] = {}
    predictions: dict[str, tuple] = {}

    log("\n========== MÉTRIQUES TEST SET (accuracy-ligne) ==========")
    log(f"{'modèle':<22} {'acc':>7} {'prec':>7} {'rec':>7} {'f1':>7} {'auc':>7}")
    for name, clf in all_models.items():
        y_pred = clf.predict(X_test)
        y_proba = clf.predict_proba(X_test)[:, 1] if hasattr(clf, "predict_proba") else None
        m = compute_metrics(y_test, y_pred, y_proba)
        all_metrics[name] = m
        predictions[name] = (y_pred, y_proba)
        log(
            f"{name:<22} {m['accuracy']:.4f} {m['precision']:.4f} {m['recall']:.4f} "
            f"{m['f1']:.4f} {m['roc_auc']:.4f}"
        )

    # --- Matrices de confusion (3 vrais modèles) ---
    fig, axes = plt.subplots(1, 3, figsize=(15, 5))
    for ax, name in zip(axes, MODEL_NAMES):
        y_pred, _ = predictions[name]
        cm = confusion_matrix(y_test, y_pred)
        ConfusionMatrixDisplay(cm, display_labels=["perdant", "gagnant"]).plot(
            ax=ax, colorbar=False
        )
        ax.set_title(f"{name}\nacc={all_metrics[name]['accuracy']:.3f}")
    fig.suptitle("Matrices de confusion — test set (accuracy-ligne)")
    fig.tight_layout()
    cm_path = REPORTS_DIR / "confusion_matrices.png"
    fig.savefig(cm_path, dpi=150)
    plt.close(fig)
    log(f"\n[4_evaluate] sauvegardé : {cm_path}")

    # --- Courbes ROC ---
    fig, ax = plt.subplots(figsize=(7, 7))
    for name in MODEL_NAMES:
        _, y_proba = predictions[name]
        fpr, tpr, _ = roc_curve(y_test, y_proba)
        ax.plot(fpr, tpr, label=f"{name} (AUC={all_metrics[name]['roc_auc']:.3f})")
    ax.plot([0, 1], [0, 1], linestyle="--", color="gray", label="hasard (AUC=0.5)")
    ax.set_xlabel("Taux de faux positifs")
    ax.set_ylabel("Taux de vrais positifs")
    ax.set_title("Courbes ROC — test set")
    ax.legend()
    fig.tight_layout()
    roc_path = REPORTS_DIR / "roc_curves.png"
    fig.savefig(roc_path, dpi=150)
    plt.close(fig)
    log(f"[4_evaluate] sauvegardé : {roc_path}")

    # --- Importance des features ---
    log("\n========== IMPORTANCE DES FEATURES (top 15) ==========")
    importances: dict[str, pd.Series] = {}
    for name in ("random_forest", "xgboost"):
        clf = models[name].named_steps["clf"]
        importances[name] = pd.Series(
            clf.feature_importances_, index=feature_cols
        ).sort_values(ascending=False)

    logreg_clf = models["logreg"].named_steps["clf"]
    logreg_coefs = pd.Series(logreg_clf.coef_[0], index=logreg_feature_order)
    importances["logreg"] = logreg_coefs.abs().sort_values(ascending=False)

    for name in MODEL_NAMES:
        top = importances[name].head(15)
        log(f"\n{name} :")
        for feat, val in top.items():
            extra = f"  (coef={logreg_coefs[feat]:+.4f})" if name == "logreg" else ""
            log(f"  {feat:<35} {val:.4f}{extra}")

    fig, axes = plt.subplots(1, 3, figsize=(20, 6))
    for ax, name in zip(axes, MODEL_NAMES):
        top = importances[name].head(15).sort_values()
        ax.barh(top.index, top.values)
        ax.set_title(name)
        ax.tick_params(axis="y", labelsize=8)
    fig.suptitle("Top 15 features par modèle (|coef| pour logreg)")
    fig.tight_layout()
    fi_path = REPORTS_DIR / "feature_importances.png"
    fig.savefig(fi_path, dpi=150)
    plt.close(fig)
    log(f"\n[4_evaluate] sauvegardé : {fi_path}")

    # --- Accuracy-partie ---
    log("\n========== ACCURACY-LIGNE vs ACCURACY-PARTIE ==========")
    log(
        "accuracy-partie : pour chaque partie de test, on prend le DERNIER snapshot de "
        "chaque bot (état le plus informé), on prédit le gagnant par argmax(proba), et on "
        "compare au vrai gagnant. Répond à : le modèle aurait-il deviné le bon gagnant à la "
        "fin de la partie ?"
    )

    build_features = load_build_features()
    df_raw = pd.read_parquet(IN_RAW)
    test_game_ids = set(df_test[GROUP_KEY].unique())
    df_test_raw = df_raw[df_raw[GROUP_KEY].isin(test_game_ids)].copy()
    log(f"\nlignes test reconstruites depuis snapshots_raw : {len(df_test_raw)} (attendu {len(df_test)})")
    assert len(df_test_raw) == len(df_test), "désalignement test_features vs snapshots_raw"

    X_test_rebuilt, _ = build_features(df_test_raw)
    X_test_rebuilt = X_test_rebuilt[feature_cols].reset_index(drop=True)
    df_test_raw = df_test_raw.reset_index(drop=True)

    # Sanity : la reconstruction doit être numériquement identique à features_test.parquet
    # (même fonction déterministe, mêmes lignes filtrées) -> confirme l'alignement avant de
    # s'appuyer sur cette reconstruction pour le "dernier snapshot par bot".
    sanity_ok = np.allclose(
        X_test_rebuilt.values.astype("float64"),
        X_test.reset_index(drop=True)[feature_cols].values.astype("float64"),
    )
    log(f"sanity reconstruction features == features_test.parquet : {'OK' if sanity_ok else 'MISMATCH'}")
    if not sanity_ok:
        log("[ERREUR] désalignement détecté entre la reconstruction et le parquet sauvegardé.")
        return 1

    test_full = pd.concat(
        [X_test_rebuilt, df_test_raw[[GROUP_KEY, "rec_botName", "snapshot_index", TARGET]]],
        axis=1,
    )
    last_snapshots = (
        test_full.sort_values("snapshot_index")
        .groupby([GROUP_KEY, "rec_botName"], as_index=False)
        .tail(1)
        .reset_index(drop=True)
    )
    n_games_test = last_snapshots[GROUP_KEY].nunique()
    log(f"bots distincts (gameId+botName) dans le test : {len(last_snapshots)}  ({n_games_test} parties)")

    winners_per_game = last_snapshots.groupby(GROUP_KEY)[TARGET].sum()
    n_anomalies = int((winners_per_game != 1).sum())
    log(
        f"parties test avec un nombre de gagnants != 1 (dernier snapshot) : "
        f"{n_anomalies} / {len(winners_per_game)} "
        f"{'(exclues du calcul ci-dessous via la jointure)' if n_anomalies else ''}"
    )

    game_accuracies: dict[str, float] = {}
    for name in MODEL_NAMES:
        clf = models[name]
        proba = clf.predict_proba(last_snapshots[feature_cols])[:, 1]
        tmp = last_snapshots[[GROUP_KEY, "rec_botName", TARGET]].copy()
        tmp["pred_proba"] = proba
        pred_winner = tmp.loc[
            tmp.groupby(GROUP_KEY)["pred_proba"].idxmax(), [GROUP_KEY, "rec_botName"]
        ]
        true_winner = tmp.loc[tmp[TARGET] == 1, [GROUP_KEY, "rec_botName"]]
        merged = pred_winner.merge(true_winner, on=GROUP_KEY, suffixes=("_pred", "_true"))
        game_acc = float((merged["rec_botName_pred"] == merged["rec_botName_true"]).mean())
        game_accuracies[name] = game_acc
        log(
            f"{name:<15} accuracy-ligne={all_metrics[name]['accuracy']:.4f}   "
            f"accuracy-partie={game_acc:.4f}  (sur {len(merged)}/{len(winners_per_game)} parties)"
        )

    log(f"\n[4_evaluate] rapports PNG dans : {REPORTS_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
