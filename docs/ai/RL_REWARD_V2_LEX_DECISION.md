# Décision : reward lexicographique / contrainte v2 (étude, pas de code)

Date : 2026-07-01
Agent : Claude Code
Statut : **ÉTUDE — aucun changement de code, aucune reward modifiée.**

Ce document tranche l'idée « reward à objectif principal dominant + missions
secondaires subordonnées » pour R2D2 v2. Il fait suite à
`docs/ai/RL_REWARD_V2_AUDIT.md` et au run contrôlé du 2026-07-01
(`/tmp/dutch_r2d2_v2_direct_reward_run_20260701_003748/`).

---

## 1. Ce que « reward lexicographique / contrainte » veut dire ici

- **Lexicographique stricte** : optimiser d'abord O₁ (gagner la manche), puis O₂
  (missions secondaires) *seulement à O₁ égal*. Un **scalaire unique ne peut pas
  encoder une vraie priorité stricte** : il ne peut que l'**approximer** en
  garantissant que la contribution cumulée des secondaires reste **bornée
  strictement sous l'écart du primaire**. La lexicographie stricte réelle exige
  des méthodes dédiées (thresholded lexicographic Q-learning) → surdimensionné.
- **Constrained RL (CMDP / Lagrangien)** : maximiser O₁ *sous contrainte* de coût
  secondaire ≤ seuil. Propre pour « ne jamais faux-matcher » mais ajoute un
  multiplicateur à tuner et de l'instabilité → surdimensionné ici.
- **Potential-based shaping** (Ng–Harada–Russell 1999) : `F = γΦ(s') − Φ(s)`.
  Théorème : **ne change pas la politique optimale**, somme télescopique bornée
  (`γᵀΦ(s_T) − Φ(s_0)`) → dense ET incapable d'inverser le primaire. Seule forme
  de shaping dense *prouvée* subordonnée. Coût : concevoir Φ (biais expert).
- **Reward hacking / inversion de dominance** : dès que Σ secondaires peut
  dépasser l'écart primaire, une politique qui sacrifie la victoire devient
  optimale (piège du `destab` non borné d'origine, ~105 % du retour).

Objectif projet : primaire = gagner la manche ; secondaires = bon match, éviter
faux match, ne pas Dutch trop tôt, améliorer sa main, utiliser la
mémoire/certitude — **jamais** au-dessus du primaire.

## 2. Réserves

- **La dégénérescence actuelle (Dutch suicide précoce) est un artefact de dataset
  off-policy, pas de forme de reward.** Le training rejoue un dataset **random
  légal** : toute continuation est polluée par des faux matchs aléatoires (6094
  faux / 200 bons sur 250 ép.). Donc Q(continuer) est bootstrappé sur des
  continuations catastrophiques → call_dutch (−1) devient le moindre mal.
  **Rescaler la reward (±100) ne corrige rien** ; le classement persiste,
  multiplié.
- **±100/−100 déstabilise TD** : cibles ∝ reward, |TD-error| énormes, PER
  échantillonne par |TD| → terminaux dominent tout le sampling. À proscrire.
- **Changer la reward sur un dataset empoisonné = déboguer à l'aveugle.** Toute
  conclusion serait non fiable.

## 3. Défaut réel *dans* la reward actuelle (petit, borné)

Les secondaires immédiats sont **additifs et non bornés en nombre**. Arithmétique
(retour non actualisé) :

- Victoire + 3 faux matchs : `3×(−0.7) + 1.0 = −1.1`.
- Défaite normale propre : `0.0`.
- → **la défaite (0.0) bat la victoire (−1.1)**.

Cela **viole la garantie « aucune défaite ne peut être meilleure qu'une
victoire »**. C'est le seul point de la reward qui mérite un patch, et il est
petit et localisé.

## 4. Options comparées

| Option | Idée | Garantit primaire dominant | Stabilité TD | Densité (crédit) | Coût / risque |
|---|---|---|---|---|---|
| **A. Ne pas toucher la reward, safe_heuristic d'abord** | Corriger le dataset (behavior policy), reward inchangée | Oui (défaite 0 > Dutch raté −1 une fois continuations non-random) | inchangée | inchangée | **Faible.** Corrige la cause réelle |
| **B. Reward inchangée + cap borné des secondaires** | Capper `Σ_episode` secondaires dans (−0.49, +0.49) à la finalisation | **Oui, prouvé** (win ≥ +0.51 > +0.49 ≥ loss) | O(1), inchangée | inchangée | Faible-moyen. Ajuste tests |
| **C. Potential-based shaping** | `γΦ(s')−Φ(s)`, `Φ=−believed_total_score_estimate` normalisé | **Oui, théorème** | O(1) | **dense** | Moyen. Design Φ + biais expert + tests |
| **D. Secondaires en auxiliary heads** | Reward = pur primaire ; missions = labels/têtes | Oui (secondaires hors retour) | O(1) | primaire sparse | Moyen. Nouvelles têtes R2D2 |
| **E. Lexicographique ±100/−100 naïf** | Gros écart d'échelle | Approx. seulement | **Mauvaise** | sparse | **Élevé. Rejeté.** |

## 5. Option recommandée

**A puis (conditionnellement) B.**

1. **safe_heuristic collection d'abord** → meilleures trajectoires. La
   dégénérescence Dutch-précoce devrait disparaître sans toucher la reward.
2. **Retrain + éval** (faux matchs, call_dutch timing, rang/score p0).
3. **Seulement s'il reste une inversion de dominance** (victoire-avec-faux-matchs
   classée sous défaite-propre), appliquer **B** : cap dur des secondaires.

Rejeté : E (±100). Reporté : C et D (utiles pour densifier proprement plus tard,
pas prioritaires).

## 6. Formule prête (à coder UNIQUEMENT à l'étape 3, si le besoin est confirmé)

Aucune constante primaire changée :

- `WIN_REWARD = +1.0`, défaite normale `0.0`, `FAILED_DUTCH = −1.0`.
- Secondaires immédiats inchangés en signe (bon match +0.5, faux match −0.7)
  **mais** cap dur à la finalisation d'épisode :
  `Σ_episode(secondaires immédiats) ∈ (−0.49, +0.49)`.
- Invariant garanti : tout retour gagnant ≥ `1.0 − 0.49 = +0.51` >
  `0.0 + 0.49 = +0.49` ≥ tout retour perdant → **aucune défaite ne bat une
  victoire**, et les secondaires ne remplacent jamais la victoire.

Tests à ajouter avant tout code : (a) invariant win>loss sous cap ; (b) cap
symétrique atteint ; (c) non-régression `test_reward_v2.py` mis à jour aux
nouvelles valeurs cappées ; (d) `test_roundtrip.py` 6/6.

## 7. Prochaine étape proposée

Revenir au chantier **safe_heuristic collection** (politique de collecte légale
prudente), smoke 50 épisodes sous `/tmp`, puis retrain/éval. Ne rouvrir la reward
qu'après avoir vu le comportement sur un dataset propre.
