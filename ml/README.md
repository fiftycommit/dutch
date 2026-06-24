# Pipeline ML — Dutch'78

## 1. Contexte

Dutch'78 est un jeu de cartes de mémoire et de stratégie : chaque joueur connaît seulement une
partie de ses propres cartes, doit deviner le reste au fil de la partie, et cherche à finir avec
le score le plus faible possible. Les bots du jeu sont des joueurs artificiels qui peuvent
remplacer un humain, avec un niveau de difficulté (facile à difficile) et un style de jeu
(agressif, rapide, équilibré…) qui influencent leurs décisions à chaque tour.

Ce pipeline est un projet personnel de portfolio en data science, pensé pour montrer une chaîne
complète : génération de données, feature engineering, modélisation, évaluation. Le jeu n'est
ici qu'un terrain d'application ; la même démarche s'appliquerait à n'importe quel système
produisant des séquences d'états avec une issue finale connue.

## 2. Le problème

Si on pouvait estimer, à tout moment d'une partie, la probabilité qu'un joueur la gagne,
plusieurs usages deviendraient possibles : calibrer la difficulté des bots en cours de partie
pour la garder serrée jusqu'au bout, par exemple, ou afficher un indicateur de tension en direct.
C'est ce signal que ce pipeline cherche à apprendre.

Concrètement : prédire, à partir d'un état de partie en cours (le `gameState` qu'un bot observe
au moment de décider d'une action), la probabilité que ce joueur gagne la partie (`finalRank ==
1`). C'est une classification binaire, mais séquentielle : un même bot génère plusieurs snapshots
au fil de la partie, tous rattachés à la même issue finale.

## 3. Démarche

Apprendre ce signal demande un grand nombre de parties dont l'issue est déjà connue : c'est la
matière première de tout apprentissage supervisé. Dutch'78 n'a pas, à ce stade, un volume de
parties humaines journalisées côté serveur suffisant : il faudrait des mois de collecte avant
d'avoir assez d'exemples pour entraîner quoi que ce soit de fiable.

La solution retenue : générer ce volume artificiellement, en faisant rejouer le vrai moteur de
jeu Dart (`lib/`) par des bots contre eux-mêmes (self-play), plutôt que d'écrire une simulation
simplifiée des règles. Cela garantit que les parties générées respectent exactement les règles
réelles du jeu (mêmes pouvoirs spéciaux, même calcul de score…), au prix d'un biais documenté
plus loin (§9 Limites & biais) : ce sont des bots qui jouent contre des bots, jamais de vraies
parties humaines.

En pratique, un générateur self-play headless (`tool/ml_dataset_generator.dart`) fait
s'affronter des bots entre eux et journalise leur état de croyance à chaque tour ; le RNG est
seedé, donc la génération est reproductible. C'est ce dataset que la section suivante détaille.

## 4. Données

Le générateur de la section précédente produit un parquet de snapshots bruts. Cette section en
détaille les volumes et les répartitions, avec deux pièges de lecture identifiés au passage :

- 20 000 parties, `--seed=42`, 2 à 4 bots par partie.
- 60 033 records (un par bot par partie), 563 632 snapshots (un par décision).
- Génération accélérée après correction d'un bug de délai d'animation (`skipDelay`) qui
  ralentissait inutilement le moteur en mode headless, mesuré empiriquement : 300 parties
  générées en 459,9 s avant le fix, 0,6 s après (~750×). Cohérent à l'échelle réelle : les
  20 000 parties du dataset se génèrent en 32,55 s avec le fix.
- Répartition des niveaux de bot, au niveau bot/partie (60 033 records dédupliqués par
  `rec_gameId`+`rec_botName`) : quasi uniforme, bronze 33.4 %, silver 33.6 %, difficile 33.0 %.
  Une agrégation au niveau ligne/snapshot donne un résultat trompeur (bronze 49.6 %, silver
  29.5 %, difficile 20.9 %), parce que les bots bronze génèrent en moyenne 2.4 fois plus de
  snapshots par partie que les bots difficile (13.9 contre 5.9, médiane 7 contre 6) : ce chiffre
  mesure un volume de décisions logguées, pas une répartition de bots. Le premier est la bonne
  lecture.
- Nombre de joueurs par partie réellement variable, pas fixé à 3 comme le laissait penser une
  version antérieure de ce document : 2 joueurs (217 414 lignes), 3 (175 596), 4 (170 622).
- Taux de victoire (`won`) : 38.4 % au niveau ligne (snapshot) contre 33.4 % au niveau record
  (bot/partie). L'écart vient de la longueur de partie, puisque les bots gagnants jouent en
  moyenne plus de tours et produisent donc plus de snapshots ; l'accuracy-ligne est de fait une
  moyenne pondérée par la longueur de partie, pas une moyenne par partie (cf. §7).
- Schéma complet du parquet brut (59 colonnes) en annexe, §Schéma.

## 5. Anti-leakage

Un risque classique quand on construit des features à partir d'un historique d'événements est la
fuite d'information : si une colonne encode, même indirectement, le résultat final ou un état que
le bot n'a pas encore au moment de décider, le modèle obtient une performance artificiellement
élevée à l'évaluation, sans avoir appris un signal réutilisable en situation réelle. Cette section
documente comment cette fuite est évitée à chaque étape du pipeline.

Règle d'or (`scripts/2_features.py:9-13`) : seuls les champs `gs_*`, l'état que le bot observe au
moment de décider (`actions[i].gameState`), sont des features candidates légitimes. Tout `rec_*`
est une métadonnée de partie ou un résultat connu seulement en fin de partie, donc exclu par
construction.

La liste bloquée explicitement (`scripts/2_features.py:92-104`) couvre plusieurs raisons
distinctes. Fuite directe pour `rec_finalScore`, `rec_finalRank`, `rec_calledDutch`,
`rec_wonDutch`, `rec_cardsAtDutch`, `rec_scoreAtDutch`, `rec_totalTurns`, `rec_avgDecisionTime`,
`rec_powerUsesCount`, `rec_goodDecisions` et `rec_badDecisions` : ce sont des résultats connus
seulement en fin de partie. `believedScoreAfter` fuite aussi, mais pour une autre raison : c'est
l'état *après* l'action du snapshot, pas avant. `timestamp`, `rec_startTime` et `rec_endTime`
viennent de l'horloge virtuelle du générateur et n'ont aucune valeur prédictive réelle.
`rec_gameId`, `rec_botId`, `rec_botName` et `snapshot_index` sont de simples identifiants ;
`rec_gameId` est gardé à part comme clé de groupe pour le split, jamais comme colonne de X.
Enfin, `rec_botBehavior`, `rec_botSkillLevel` et le reste des champs `rec_*` sont exclus par
choix de scope, puisque leurs équivalents `gs_botBehavior`/`gs_botSkillLevel` sont utilisés à la
place. Cas à part : `actionType` a été discuté puis exclu par défaut, parce qu'annoncer Dutch
encode déjà la croyance « je suis en tête », donc plutôt un proxy de décision qu'un état de
plateau brut, alors que les features de croyance (catégorie b) capturent cette même information
de façon plus granulaire.

Le split train/test (`scripts/2_features.py:239-258`) est groupé par partie : `GroupShuffleSplit`
sur `rec_gameId`, 80/20, `random_state=42`. Un split ligne-à-ligne aléatoire mettrait des
snapshots de la même partie en train et en test, ce qui créerait une fuite par corrélation
intra-groupe puisqu'ils partagent la même issue finale. Vérifié : 0 partie en commun entre train
et test, sur 16 000 parties d'entraînement et 4 000 de test (448 891 et 114 741 lignes
respectivement). La même logique de groupe est réutilisée en validation croisée (`GroupKFold`,
script 3) ; il n'y a jamais de validation croisée ligne-à-ligne sur ces données.

## 6. Modélisation

Une fois les features choisies et le split posé (§5), restait à choisir des modèles capables
d'apprendre le signal du §2, et à vérifier que la performance ne tient pas à un seul choix
d'algorithme. Trois familles sont comparées : un modèle linéaire (LogReg) et deux modèles à
arbres (RandomForest, XGBoost), tous avec `random_state=42` fixé (`scripts/3_train.py`).

Le taux de victoire n'est pas équilibré (38.4 % de lignes gagnantes au niveau snapshot, cf. §4),
donc chaque modèle reçoit une stratégie de rééquilibrage explicite plutôt que de laisser faire la
distribution des classes :

| Modèle | Pipeline | Gestion du déséquilibre |
|---|---|---|
| `LogisticRegression` | `SimpleImputer`+`StandardScaler` (numériques) + passthrough (one-hot) | `class_weight="balanced"` |
| `RandomForestClassifier` | `SimpleImputer` + arbres | `class_weight="balanced"` |
| `XGBClassifier` | direct (gère les NaN nativement) | `scale_pos_weight=1.6069` (= nég/pos du train réel) |

46 features au total : 25 numériques et 21 one-hot, pour les niveaux de `gs_topDiscardValue`,
`gs_botBehavior` et `gs_botSkillLevel`.

Le RandomForest a dû être recalibré. Le premier passage, avec des arbres non bridés
(`max_depth=None`), a produit le modèle le plus lourd des trois (2.6 Go) mais aussi le moins bon
(AUC en CV de 0.8392, pire que LogReg et XGBoost) : signal classique de sur-apprentissage, les
arbres profonds mémorisent le bruit des 448 891 lignes du train plutôt que d'apprendre un signal
généralisable. La correction est passée par un `GridSearchCV` (mêmes groupes, même `GroupKFold`)
sur `max_depth ∈ {10,15}` et `min_samples_leaf ∈ {5,20}`. La meilleure combinaison,
`max_depth=15, min_samples_leaf=20`, donne un modèle 20 fois plus léger (131 Mo) et un AUC
meilleur que les 3 modèles (0.8520). Les deux valeurs retenues sont au bord supérieur de la
grille testée, donc un optimum encore meilleur reste plausible avec une grille plus large ; non
explorée ici par discipline de scope (cf. §9).

## 7. Résultats chiffrés

Cette section répond directement à la question posée en §2 : le modèle devine-t-il vraiment qui
va gagner, et de combien dépasse-t-il un simple hasard pondéré par les classes ?

### Validation croisée groupée (`GroupKFold`, 5 folds, train uniquement, 16 000 parties)

Avant de toucher au test, un premier contrôle sur le train seul, pour repérer un éventuel
sur-apprentissage en amont :

| Modèle | AUC | F1 |
|---|---|---|
| LogReg | 0.8441 ± 0.0047 | 0.7087 ± 0.0059 |
| XGBoost | 0.8472 ± 0.0051 | 0.7124 ± 0.0057 |
| RandomForest (tuné) | **0.8520 ± 0.0046** | **0.7182 ± 0.0050** |

### Test set, jamais vu (114 741 lignes, 4 000 parties)

Accuracy-ligne, chaque snapshot évalué indépendamment :

| Modèle | Accuracy | Précision | Rappel | F1 | AUC |
|---|---|---|---|---|---|
| LogReg | 0.7503 | 0.6476 | 0.7709 | 0.7039 | 0.8373 |
| RandomForest | 0.7539 | 0.6466 | 0.7954 | 0.7133 | 0.8514 |
| XGBoost | 0.7554 | 0.6537 | 0.7752 | 0.7092 | 0.8458 |
| *baseline* `dummy_most_frequent` | 0.6151 | 0.0000 | 0.0000 | 0.0000 | 0.5000 |
| *baseline* `dummy_stratified` | 0.5275 | 0.3859 | 0.3845 | 0.3852 | 0.5008 |

Les 3 modèles battent largement les deux baselines triviales : 13 à 14 points d'accuracy de plus
que `dummy_most_frequent` et 22 à 23 points de plus que `dummy_stratified` (le hasard pondéré par
la fréquence des classes), pour un AUC qui passe de 0.50 à environ 0.84. La performance vient donc
bien du signal des features, pas seulement de l'exploitation du déséquilibre de classe.

L'accuracy-ligne sous-estime fortement l'utilité réelle du modèle, car elle moyenne des
décisions de début de partie (peu d'information) et de fin de partie (beaucoup d'information) à
poids égal. On calcule donc, pour chaque partie de test, le dernier snapshot connu de chaque bot
(l'état le plus informé), et on compare l'argmax des probabilités prédites au vrai gagnant : le
modèle aurait-il deviné le bon vainqueur à la fin de la partie ?

| Modèle | Accuracy-ligne | Accuracy-partie |
|---|---|---|
| LogReg | 0.7503 | 0.8877 |
| RandomForest | 0.7539 | 0.9229 |
| XGBoost | 0.7554 | 0.9276 |

L'accuracy-partie est calculée sur 4 006 observations : les 4 000 parties de test, dont six
comportent plusieurs gagnants ex-aequo de rang 1. Ces égalités sont légitimes (une propriété du
jeu, pas un bug du pipeline) et chaque gagnant est inclus dans le calcul : la métrique est donc
pondérée par le nombre de gagnants, pas une métrique par partie au sens strict.

C'est le chiffre à retenir de toute cette section : avec XGBoost et le dernier état connu de
chaque bot, le modèle identifie le bon vainqueur dans environ 93 % des parties de test.

Graphiques : `reports/confusion_matrices.png`, `reports/roc_curves.png`.

## 8. Importances de features

Le score seul ne dit pas sur quoi le modèle s'appuie pour décider ; regarder les features les
plus importantes permet de vérifier que le signal appris correspond à une intuition du jeu,
plutôt qu'à un artefact caché du dataset.

Les classements divergent entre modèles, ce qui est attendu : LogReg pondère un effet linéaire
global, alors que RandomForest et XGBoost capturent des interactions et des seuils non-linéaires
(détail complet dans `reports/feature_importances.png`, top 15 par modèle). LogReg privilégie
`gs_botSkillLevel_difficile` et `gs_botSkillLevel_bronze` (rang 1-2), puis `opp_hand_mean`.
RandomForest privilégie les tailles de main : `gs_minOpponentHandSize`, `opp_hand_mean` et
`gs_botHandSize` occupent les rangs 1 à 3. XGBoost, lui, privilégie largement
`gs_unknownCardCount`, en tête loin devant le reste.

Malgré cette divergence, le meilleur des trois indicateurs `gs_botSkillLevel_*` (toujours
`difficile`) reste dans le top 4 des trois modèles : rang 1 pour LogReg, rang 4 pour
RandomForest, rang 2 pour XGBoost. C'est le signal le plus constant du dataset, cohérent avec
l'intuition qu'un bot « difficile » gagne plus souvent qu'un bot « bronze », toutes choses égales
par ailleurs. `gs_botSkillLevel_bronze` suit d'assez près (rang 2, 6 et 5 respectivement), mais
`gs_botSkillLevel_silver` retombe loin derrière (rang 33, 14 et 18) : les modèles apprennent
surtout à distinguer les extrêmes, pas le niveau intermédiaire. `gs_believedTotalScoreEstimate`,
l'estimation de croyance la plus synthétique du bot sur son propre score, apparaît dans les trois
classements à des rangs inégaux : 9 pour RandomForest (0.0504) et pour XGBoost (0.0111), mais 19
pour LogReg (0.1074). Présente partout, jamais dominante.

## 9. Limites & biais

Les chiffres des sections précédentes valent dans un cadre précis ; voici ses limites connues,
pour ne pas les sur-interpréter.

Le dataset entier est du self-play, des bots contre des bots, jamais de vraies parties humaines.
Les modèles apprennent donc à prédire l'issue de parties entre IA, pas le comportement de
joueurs humains réels, et rien ne garantit que cette performance se transfère à de vraies
données humaines.

Les personnalités synthétiques prévues par `documentation/PROMPT_ML_DATASET.md` (Étape 3) n'ont
pas été activées pour ce dataset. La spécification prévoyait de diversifier les bots via des
`aiParameters` tirés aléatoirement (agressivité, prudence, tolérance au risque, seuil de
Dutch...), mais `gs_aiParams` est toujours null sur les 563 632 lignes, vérifié empiriquement. À
ne pas confondre avec le système des « 8 personnalités » de matchmaking déjà en production côté
serveur (`documentation/BOT_LEARNING.md`, `ML_GUIDE.md`) : un système distinct, qui n'est pas non
plus utilisé en self-play local. La diversité réellement présente dans ce dataset vient donc
uniquement du nombre de joueurs variable (2 à 4) et du niveau de compétence
(`bronze`/`silver`/`difficile`).

La grille testée pour le RandomForest reste limitée : l'optimum retrouvé (`max_depth=15,
min_samples_leaf=20`, §6) est au bord supérieur de cette grille, donc un résultat encore meilleur
reste possible avec une grille plus large, non explorée ici.

Les matrices de confusion montrent enfin un biais optimiste cohérent avec
`class_weight="balanced"` : pour les 3 modèles, il y a nettement plus de faux positifs (perdant
prédit gagnant) que de faux négatifs (gagnant prédit perdant), avec un ratio FP/FN d'environ 1.8
à 2.1 :

| Modèle | FP | FN | ratio |
|---|---|---|---|
| LogReg | 18 530 | 10 118 | 1.83 |
| RandomForest | 19 201 | 9 034 | 2.13 |
| XGBoost | 18 139 | 9 930 | 1.83 |

C'est l'effet attendu du rééquilibrage des classes (`class_weight`/`scale_pos_weight`) : le seuil
de décision se décale pour mieux rattraper la classe minoritaire « gagnant » (rappel de 0.77 à
0.80), au prix d'une précision plus faible (environ 0.65). Le modèle a donc tendance à
sur-prédire la victoire plutôt qu'à la sous-prédire.

## 10. Chantiers suivants

Pistes pour la suite, à peu près dans l'ordre où elles répondraient aux limites du §9.

Deux pistes amélioreraient surtout la diversité du dataset actuel : activer les personnalités
synthétiques de l'Étape 3 (`PROMPT_ML_DATASET.md`) pour varier les profils de bots, et, si une
collecte devient possible côté serveur, intégrer de vraies parties humaines pour mesurer l'écart
entre self-play et jeu réel et ré-entraîner sur un mélange des deux.

Ces données humaines ouvriraient aussi la voie à de l'imitation learning : entraîner des bots
« fantômes » qui reproduisent un style de jeu humain réel plutôt que des heuristiques codées à la
main.

Le chantier le plus large reste séparé de ce pipeline supervisé : `PROMPT_ML_DATASET.md` marque
explicitement le RL (phase 2) comme un chantier à part, hors scope de ce document (section « Hors-
scope de ce document »). L'idée serait d'obtenir des bots dont la force est ajustable nativement
plutôt qu'imitée, mais aucun détail d'implémentation (algorithme, fonction de récompense) n'est
encore fixé à ce stade.

---

## Environnement (uv)

Pour exécuter ou reproduire ce pipeline localement, voici l'environnement Python utilisé. Stack
gérée par [`uv`](https://docs.astral.sh/uv/), pas de `pip`/`python` nu.

Choix : **`pyproject.toml`** (projet uv propre, non-packagé : `tool.uv.package = false`) +
**`uv.lock`** (versions épinglées, reproductible). Le venv vit dans `ml/.venv` (gitignoré).

```bash
cd ml
uv sync                       # crée .venv + installe depuis le lock
uv run scripts/1_load_data.py # lance un script dans l'env
```

Dépendances : `pandas`, `scikit-learn`, `matplotlib`, `xgboost`, `joblib`, `pyarrow`.

**macOS uniquement** : `xgboost` a besoin du runtime OpenMP, absent par défaut sur macOS
(erreur `libomp.dylib not loaded` sinon) :
```bash
brew install libomp
```

## Arborescence

Pour se repérer dans le dépôt, voici l'arborescence du dossier `ml/` et ce que produit chaque
étape :

```
ml/
├── pyproject.toml / uv.lock     # projet + lock uv
├── data/
│   ├── raw/games/               # 60 033 JSON bruts (gitignorés, régénérables via Dart)
│   │   └── game_42_<g>_p<seat>.json
│   └── processed/               # parquets intermédiaires (gitignorés)
│       ├── snapshots_raw.parquet      # sortie script 1 (563 632, 59)
│       ├── features_train.parquet     # sortie script 2 (448 891, 46+won+rec_gameId)
│       └── features_test.parquet      # sortie script 2 (114 741, 46+won+rec_gameId)
├── models/                      # sorties script 3 (gitignorées sauf metadata.json)
│   ├── logreg.joblib            # 7 KB
│   ├── random_forest.joblib     # 131 MB (post-tuning, cf. §6)
│   ├── xgboost.joblib           # 802 KB
│   └── metadata.json            # features, seeds, versions, résultats CV
├── reports/                     # sorties script 4 (PNG)
│   ├── confusion_matrices.png
│   ├── roc_curves.png
│   └── feature_importances.png
└── scripts/
    ├── 1_load_data.py           # ingestion brute → parquet
    ├── 2_features.py            # feature engineering anti-leakage + split groupé
    ├── 3_train.py               # entraînement (CV groupée + grid search RF)
    ├── 4_evaluate.py            # évaluation test set + accuracy-partie + graphiques
    └── 5_predict.py             # inférence (predict_win_proba / predict_all_players)
```

Régénérer les données brutes :
```bash
cd ..   # racine du repo Flutter
~/fvm/default/bin/dart run tool/ml_dataset_generator.dart --games=20000 --seed=42 --out=ml/data/raw/games
```

## Scripts

Les 5 scripts s'enchaînent dans cet ordre, chacun consommant la sortie du précédent :

```bash
cd ml
uv run scripts/1_load_data.py   # JSON bruts -> snapshots_raw.parquet
uv run scripts/2_features.py    # -> features_train.parquet / features_test.parquet
uv run scripts/3_train.py       # -> models/*.joblib + models/metadata.json
uv run scripts/4_evaluate.py    # -> reports/*.png + métriques console
uv run scripts/5_predict.py     # exemple d'inférence sur un snapshot réel du dataset
```

### `5_predict.py` (inférence)

Seul script qui ne sert pas à entraîner mais à utiliser un modèle déjà entraîné, pour scorer un
état de jeu donné. Il expose `predict_win_proba(snapshot: dict) -> float` et
`predict_all_players(game_state: dict[str, dict]) -> dict[str, float]`. Le nom de fichier
commence par un chiffre (pas un nom de module Python valide) : pour les réutiliser ailleurs,
les importer par chemin comme le fait le script lui-même avec `2_features.py` (cf.
`_load_build_features()` en tête de fichier), ou copier les deux fonctions dans un module
classique.

```python
proba = predict_win_proba(snapshot)          # snapshot = un dict gameState brut (POV d'un bot)
probas = predict_all_players({"alice": snap_alice, "bob": snap_bob})  # un snapshot par joueur
```

Utilise XGBoost (`models/xgboost.joblib`), qui a la meilleure accuracy-partie (0.9276) et le
fichier le plus léger (802 KB, contre 131 Mo pour le RandomForest pourtant proche en score).
Applique le même
`build_features()` que les scripts 2/4 puis un `reindex` sur la liste de features de
`metadata.json` pour garantir le bon jeu de colonnes one-hot et le bon ordre, même sur un
snapshot unique (cf. commentaire en tête du script pour le piège évité).

## Schéma réel observé du DataFrame aplati (59 colonnes, sortie script 1)

Référence complète des colonnes du parquet brut, utile pour vérifier d'où vient une feature
donnée ou pour réutiliser ces données dans un autre script. Conventions de préfixe :
- `rec_*` — champ du **record parent** (métadonnée / cible / stat de fin de partie).
- `gs_*` — champ de **`gameState`** (état observable par le bot à ce tour = futures features brutes).
- sans préfixe — identifiant du snapshot + cible dérivée.

| Colonne | Type | Source / sens |
|---|---|---|
| `rec_gameId` | str | id partie (`game_42_<g>`) |
| `rec_botId` | str | archétype (`<behavior>_<skill>`), non unique dans une partie |
| `rec_botName` | str | nom + siège (`<archétype>_<seat>`), clé unique d'un record avec `gameId` |
| `rec_botBehavior` | str | `balanced` / `aggressive` / `fast` / … |
| `rec_botSkillLevel` | str | `bronze` / `silver` / `difficile` |
| `rec_numberOfPlayers` | int | nb joueurs, varie réellement : 2/3/4 selon la partie |
| `rec_gameMode` | str | `quick` |
| `rec_usedSBMM` | bool | matchmaking SBMM (False en self-play) |
| `rec_startTime`, `rec_endTime` | str | timestamps ISO (horloge virtuelle déterministe) |
| `rec_initialHandSize` | int | taille main initiale (4) |
| `rec_finalScore` | int | score final du bot |
| `rec_finalRank` | int | **rang final 1..N** (base de la cible) |
| `rec_calledDutch` | bool | a appelé Dutch |
| `rec_wonDutch` | bool | a gagné son Dutch |
| `rec_cardsAtDutch`, `rec_scoreAtDutch` | int | état au moment du Dutch |
| `rec_totalTurns` | int | nb de tours de la partie |
| `rec_avgDecisionTime` | float | temps de décision moyen (artefact horloge virtuelle) |
| `rec_powerUsesCount` | int | nb pouvoirs utilisés |
| `rec_goodDecisions`, `rec_badDecisions` | int | comptes qualitatifs (annotés par le générateur) |
| `rec_opponents_json` | str (JSON) | liste adversaires `[{id,name,isHuman,behavior,skillLevel}]` |
| `won` | int | **cible dérivée** : `1` si `rec_finalRank == 1` sinon `0` |
| `snapshot_index` | int | index du snapshot dans le record |
| `actionType` | str | `play_turn` (543 661) / `call_dutch` (19 971) |
| `turnNumber` | int | numéro de tour |
| `timestamp` | str | ISO (horloge virtuelle) |
| `believedScoreAfter` | float | estimation post-action ; **null pour `call_dutch`** (19 971 nulls, normal) |
| `gs_turnCount`, `gs_actionCount` | int | compteurs partie |
| `gs_phase` | str | toujours `playing` (snapshots pris en phase de jeu) |
| `gs_numberOfPlayers`, `gs_botSeatIndex` | int | contexte siège |
| `gs_deckSize`, `gs_discardPileSize` | int | tailles pioche / défausse |
| `gs_topDiscardValue` | str | rang carte sommet défausse (`R`,`D`,`V`,`10`,`2`…) |
| `gs_topDiscardPoints` | int | points de cette carte |
| `gs_botHandSize`, `gs_minOpponentHandSize` | int | tailles de mains |
| `gs_expectedDeckCardValue` | float | valeur attendue d'une carte piochée |
| `gs_dutchCalledAlready` | bool | Dutch déjà appelé |
| `gs_knownCardCount`, `gs_unknownCardCount` | int | cartes connues/inconnues du bot |
| `gs_memoryConfidence` | float | confiance mémoire [0,1] |
| `gs_believedKnownScore`, `gs_maxKnownCardValue` | int | score connu estimé / max connu (-1 = aucun) |
| `gs_hasDoublon`, `gs_doublonCount` | bool/int | doublons en main |
| `gs_expectedUnknownValueSum` | float | somme attendue des inconnues |
| `gs_believedTotalScoreEstimate` | float | score total estimé |
| `gs_spiedOpponentCardsCount` | int | cartes adverses espionnées |
| `gs_bestMatchProbability` | float | proba du meilleur match |
| `gs_botBehavior`, `gs_botSkillLevel` | str | redondants avec `rec_*` (cohérence vérifiable) |
| `gs_usedSBMM` | bool | redondant avec `rec_usedSBMM` |
| `gs_aiParams` | object | **toujours null** (cf. §9, personnalités synthétiques non activées) |
| `gs_opponentsHandSizes` | list[int] | tailles mains adverses (colonne liste, parquet natif) |
| `gs_discardedRanks_json` | str (JSON) | histogramme rangs défaussés `{rang: count}` |

### Champs record **toujours null** en self-play (droppés à l'ingestion)

Le générateur est all-bots → tout ce qui concerne un humain est null. Documentés pour mémoire,
absents du parquet :
`humanFinalScore`, `humanFinalHandSize`, `botFinalHandSize`, `pBeatHuman`, `initialDeck`,
`turnsBeforeDutch`, `discardsPerRound`, `triageDecisions`, `initialHandScore`, `initialHandRank`,
`initialHandRankFromWorst`. Le champ `actionDetails` (niveau action) est toujours `{}` → droppé.

## Notes déterminisme

Récapitulatif, dispersé autrement dans les sections précédentes, des garanties et limites de
reproductibilité de ce pipeline :

- Génération reproductible via `--seed` (RNG `EngineRandom` central). Les délais d'animation
  sont **skippés** en génération (`skipDelay`) sans impact sur le contenu (temps d'horloge, pas RNG).
- Les champs temporels (`startTime`, `timestamp`, `avgDecisionTime`…) viennent d'une horloge
  virtuelle déterministe, blocklistés côté features (pas d'info prédictive réelle, cf. §5).
- Reproductibilité de `Random(seed)` liée à la version du SDK Dart (Flutter 3.41.9 / Dart 3.11.5).
- Seeds ML : `random_state=42` partout (split, CV, LogReg, RandomForest, XGBoost,
  `DummyClassifier(strategy="stratified")`). `GroupKFold`/`GroupShuffleSplit` n'ont besoin
  d'aucun aléa supplémentaire au-delà de `random_state` pour `GroupShuffleSplit` (découpage des
  groupes déterministe une fois la graine fixée).
