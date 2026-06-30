# Dutch RL — AI Handoff

Dernière mise à jour : 2026-06-30 (Claude Code)
Agent ayant modifié ce fichier : Claude Code

> Ce fichier est la **source de vérité de continuité** entre Claude Code, Codex et tout autre agent IA travaillant sur la phase 2 RL de Dutch'78. Il doit rester exact et utilisable même si une session est interrompue brutalement.

---

## Résumé ultra-court

Le projet Dutch'78 reste en phase 2 RL. L'AgentInterface v2 (faits publics, mémoire privée légale, stabilité de slots, actions structurées `action_v2`) est en place, et **un cœur R2D2 v2 complet a maintenant été construit dessus**, en pile de fichiers `*_v2.py` isolés qui ne touchent ni PPO legacy ni le gameplay. La phase 1 ML supervisée est terminée/frozen et ne doit pas être cassée.

Le cœur R2D2 v2 (PER, IS weights, update priorities, Double Q factorisé, n-step, burn-in complet), les schedules beta/epsilon, l'export de métriques d'entraînement, et un logger + analyseur de traces action-level sont en place et testés (commits `010751e`, `8d42d87`, `de7d21f`, `786a791`, `738b153`).

> ⚠️ **NE PAS RELANCER D'ENTRAÎNEMENT POUR L'INSTANT.** Deux raisons : (1) le runner avait des BLOCKERs de fidélité (corrigés, cf. ci-dessous) ; (2) le reward v2 ne pénalise pas assez les faux matchs (**H2** de l'audit), ce qui pousse l'agent au match-spam — à revoir AVANT tout retrain. Audit reward actuel : `docs/ai/RL_REWARD_V2_AUDIT.md` (`2026-06-30`, Codex). Constat important : Dart émet `principal` + `destab` + `win_bonus`, mais la pile R2D2 v2 Python stocke/optimise actuellement seulement `principal`.

> ⚠️ **L'ancien checkpoint `/tmp/dutch_r2d2_v2_first_run_20260630_192728/checkpoint.pt` a été entraîné sur le runner pré-fix et NE DOIT PAS servir de point de départ sérieux** (ni base de fine-tune). Il a appris une policy dégénérée match-heavy et finit même PIRE que random au score final post-fix. Retrain depuis zéro recommandé.

> ⚠️ **La fidélité du runner passe avant le scaling RL.** Toute divergence de gameplay doit être auditée et corrigée avant d'entraîner.

**Chronologie récente (audit + fix runner)** :
- `c9f9ad8 docs(rl): audit v2 runner fidelity` : audit complet (`docs/ai/RL_RUNNER_FIDELITY_AUDIT.md`). 3 BLOCKERs trouvés : réaction pilotée par `pass_tick` au lieu du timer réel → boucles `match` ; `phase=ended` continuait avec `done=false` ; faux match `deck=0` devenait un no-op ; `legal_action_v2` proposait `match` en `ended`/no-op.
- `9682d7b fix(rl): simulate reaction timer and recycle discard` : runner corrigé (cf. section « Fidélité du runner »). Évaluation contrôlée post-fix faite (sans training) : épisodes terminants, `reached_max_steps` 27/30 → **0/30**, plus de boucle (`match_chain_max` 100 → **30** = timer 3s simulé), 0 action illégale, 0 crash. **Le runner est maintenant stable pour un retrain ; le reward H2 reste à traiter d'abord.**

Avant tout cela, deux commits avaient stabilisé l'interface : `8fa49fa` (reaction window exposée à p0) et `1c2c4fa` (pendingMatchPowers résolus, Valet/Joker FIFO).

---

## Objectif actuel

Le cœur R2D2 v2 et le runner corrigé sont en place. **Avant tout nouveau training**, la prochaine étape est de **patcher le reward shaping v2 après audit H2** : faux match, match réussi, Dutch, score final/rang — l'agent fait du match-spam faute de signal pénalisant les faux matchs coûteux. L'audit `docs/ai/RL_REWARD_V2_AUDIT.md` confirme aussi que `win_bonus` et `destab` sont émis par Dart mais ignorés par les extracteurs R2D2 v2 (`rollout_v2`, `collect_rollouts_v2`, `infer_r2d2_v2`), qui ne gardent que `rewards.principal`. Séquence recommandée :
1. Patch reward v2 conservateur + tests (faux match pénalisé, `win_bonus` consommé ou explicitement désactivé, scalarisation unique côté Python).
2. Collecte neuve sur le runner corrigé (idéalement epsilon-greedy, pas pure random).
3. **Retrain depuis zéro** (ne pas fine-tune l'ancien checkpoint, biaisé par le runner pré-fix).
4. Évaluation + traces post-train.

Ne pas relancer de training tant que le reward H2 n'a pas été revu.

Contraintes :
- RL depuis zéro : le siège RL n'hérite d'aucune heuristique de bot.
- MaskablePPO feed-forward reste une baseline historique, pas une hypothèse à valider automatiquement.
- Ne pas lancer de nouvel entraînement tant que l'interface agent n'est pas fidèle.
- Préserver la phase 1 ML supervisée.
- Inspecter le vrai code avant toute modification.
- Ne pas inventer de classes, méthodes, chemins ou signatures.
- Ne pas mélanger les changements RL avec les fichiers hors scope déjà présents dans le worktree.

---

## Fidélité du runner RL v2 (audit + fix)

> **Principe : la fidélité du runner passe avant le scaling RL.** Toute divergence entre le vrai Dutch'78 et le runner headless doit être auditée et corrigée avant d'entraîner. Audit complet : `docs/ai/RL_RUNNER_FIDELITY_AUDIT.md`.

### BLOCKERs trouvés (audit `c9f9ad8`) — désormais corrigés
- Réaction pilotée par `pass_tick` au lieu du timer réel → un agent greedy qui matche toujours bouclait à l'infini.
- `phase=ended` pouvait continuer avec `done=false` (épisode jamais terminé).
- Faux match avec `deck=0` devenait un no-op répétable.
- `legal_action_v2` proposait encore `match` en `ended`/no-op.

### Fix appliqué (`9682d7b`, fichiers `tool/rl_env_runner.dart` + `test/rl/rl_env_runner_test.dart`)
- **Timer GLOBAL de réaction simulé** (équivalent headless du timer mural ~3s) : `_kReactionTimerMs = 3000`, `_kHeadlessReactionTickMs = 100`, `_kMaxHeadlessReactionTicks = 30`.
- **Aucune action ne réinitialise le timer** : ni un match réussi, ni un faux match, ni un `pass_tick`, ni un changement de top discard. Chaque décision de réaction consomme **un tick** ; l'expiration du budget ferme la fenêtre (même si p0 ne joue jamais `pass_tick`). Budget réamorcé uniquement à l'ouverture d'une nouvelle fenêtre.
- **Deck vide → recyclage** (réutilise `GameLogic._refillDeck`) : remélange toute la défausse **sauf la top discard** quand une pioche est nécessaire ; la top reste matchable ; le deck vide seul ne termine pas la manche.
- **Faux match → pénalité réelle** (via refill si besoin), top inchangée, carte reste en main, timer continue ; jamais de no-op.
- `phase=ended` ⇒ `done=true` côté RL ; `legal_action_v2` ne propose plus `match` en `ended`/terminal.
- Tests : `flutter test test/rl/rl_env_runner_test.dart` **67/67** (dont parité byte-à-byte #5 intacte) ; `dart analyze` runner OK ; Python v2 (`test_action_trace_v2`, `test_analyze_action_trace_v2`, `test_infer_r2d2_v2`, `test_evaluate_r2d2_v2`) verts ; `test_roundtrip` **6/6** ; `git diff --check` OK. Binaire `tool/rl_env_runner` recompilé (gitignored, non committé).

### Évaluation contrôlée post-fix (sans training, ancien checkpoint)
Checkpoint évalué : `/tmp/dutch_r2d2_v2_first_run_20260630_192728/checkpoint.pt` (entraîné AVANT le fix). 30 épisodes, 6 joueurs, greedy ε=0, `compare-random`.

| métrique | modèle (greedy) | random |
|---|---|---|
| completed | 30/30 | 30/30 |
| average_steps | 38.9 | 31.4 |
| reached_max_steps | **0** | 0 |
| average_reward | −0.987 | −1.0 |
| dutch_calls | 0 | 5 (0 réussis) |
| wins / win_rate | 0 / 0.0 | 0 / 0.0 |
| average_final_rank | 5.97 | 6.0 |
| average_final_score_p0 | 208.6 | 187.0 |
| illegal_action_errors | 0 | 0 |

Trace (5 ép., 238 décisions) : selected `match 143, pass_tick 72, draw 9, post_draw_replace 9, jack_swap 2, joker 1, power_7 1, power_10 1` ; phase `reaction 215, playing 18, specialPower 5, ended 0` ; `done_true 5/5` ; `match_chain_max 30` (= timer simulé) ; `call_dutch` légal 9× / choisi 0× ; **0 clé interdite**, **0 `phase=ended` `done=false`**, **0 `match` offert en `ended`**.

**Comparaison avant/après fix (modèle greedy)** : `average_steps` 457.8 → **38.9** ; `reached_max_steps` 27/30 → **0/30** ; `phase=ended done=false` nombreux → **0** ; `match_chain_max` ~100/∞ → **30**. Épisodes désormais terminants, aucune boucle.

### Conclusions
- Le runner est **stable pour un retrain**.
- L'ancien checkpoint est **trop biaisé** (policy match-spam apprise sur le runner bogué ; pire que random au score final). **Ne pas le fine-tune comme base sérieuse.**
- Avant retrain : traiter **H2** (reward v2 ne pénalise pas assez les faux matchs → match-spam).

---

## Contexte projet

Dutch'78 est un jeu de cartes multijoueur Flutter/Dart (racine) + Node/TypeScript (`dutch-server/`).

Repo :
- `https://github.com/fiftycommit/dutch` (privé — pas de clone HTTPS anonyme possible).

Déploiement :
- `dutch-game.me` (prod sur DigitalOcean, droplet 2 vCPU / 2 Go — trop petit pour l'entraînement RL, **ne pas y entraîner**).

Phase 1 ML supervisée existante (à préserver) :
- Générateur self-play Dart headless : `tool/ml_dataset_generator.dart`
- RNG seedable : `lib/services/game/engine_random.dart`
- Dossier ML Python : `ml/` (venv uv, `pyproject.toml`, `scripts/`, `data/`, `models/`, `reports/`, `README.md`)
- Modèles entraînés : `ml/models/xgboost.joblib`, `ml/models/logreg.joblib`, `ml/models/random_forest.joblib`
- Objectif phase 1 : prédiction du vainqueur.

À préserver :
- Ne pas casser le générateur existant (`tool/ml_dataset_generator.dart`).
- Ne pas écraser les modèles de `ml/models/`.
- Ne pas réutiliser l'ancien module expérimental `qlearning` (cf. ci-dessous).

Module expérimental supprimé (2026-06-26) :
- `dutch-server/src/services/QLearningService.ts`, `NeuralNetworkService.ts`, `GeneticAlgorithmService.ts` — **supprimés du repo** (commit faisant suite à vérification prod : 0 hit sur 2,5 mois de logs PM2 blue+green). Les 6 routes `/api/bot-learning/(ml-stats|predict-action|genetic/*)` renvoient désormais `410 Gone`. Les fichiers source ne sont plus présents ; ne pas les recréer ni s'en inspirer pour la phase 2 RL.

---

## Instructions obligatoires pour tout agent IA

Tout agent qui reprend ce projet doit :

1. Lire ce fichier (`docs/ai/HANDOFF.md`) avant de faire quoi que ce soit.
2. Lire `AGENTS.md` s'il existe (il existe, à la racine du repo).
3. Inspecter les fichiers réels avant de proposer ou modifier du code.
4. Ne jamais inventer de noms de classes, méthodes, chemins ou signatures.
5. Ne jamais modifier le code sans plan court validé ou nécessité clairement expliquée.
6. Préserver la phase 1 ML supervisée.
7. Ne pas utiliser l'ancien module expérimental `qlearning`.
8. Ne pas faire de supposition silencieuse sur l'architecture.
9. Mettre à jour ce fichier après chaque étape significative.
10. En fin de réponse, dire explicitement si ce handoff a été mis à jour ou non.

---

## Règle obligatoire de mise à jour du handoff

À chaque changement concret, ce fichier doit être mis à jour.

Un changement concret inclut :
- création, modification ou suppression d'un fichier ;
- installation d'un outil ou d'une dépendance ;
- commande Azure qui modifie l'infrastructure ;
- changement d'état de la VM ;
- nouvelle erreur bloquante ;
- correction d'un bug ;
- décision d'architecture validée ;
- commande importante exécutée avec résultat significatif ;
- modification d'un plan ;
- découverte importante dans le code ;
- changement de stratégie technique.

Après chaque changement concret :
1. Mettre à jour la section concernée.
2. Ajouter une entrée datée dans `## Journal des mises à jour`.
3. Mentionner :
   - ce qui a changé ;
   - pourquoi ;
   - fichiers/commandes concernés ;
   - résultat obtenu ;
   - état actuel ;
   - prochaine action recommandée.

Ne pas attendre la fin d'une longue série d'actions. Le fichier doit rester utilisable même si la session s'interrompt brutalement.

---

## État infrastructure Azure

Abonnement :
- Azure for Students (ID `28f47268-4579-4782-aebb-acce0b99e0ab`).

Régions / tailles testées (historique) :
- `westeurope` : interdite — `RequestDisallowedByAzure` (n'accepte plus de nouveaux clients).
- `northeurope` : interdite — `RequestDisallowedByAzure`.
- `francecentral` : RG possible, mais `Standard_F4s_v2` (4 vCPU) → `SkuNotAvailable`.
- `swedencentral` : `Standard_F4s_v2` → `SkuNotAvailable`, mais **`Standard_B4as_v2` → succès**.

VM créée et opérationnelle :
- Resource group : `rg-dutch-rl`
- Nom VM : `rlDutch`
- Région : `swedencentral`
- Taille : `Standard_B4as_v2`
- CPU/RAM observés : **4 vCPU AMD EPYC 7763 / 15 Gio RAM** (≈16 Go)
- Disque : 29 Go (≈21 Go libres après setup)
- OS : Ubuntu 22.04.5 LTS x86_64
- IP publique : `20.91.236.73`

État SSH : ✅ **RÉSOLU**
- Accès fonctionnel via l'alias `dutch-rl-vm` (configuré dans `~/.ssh/config` en local).
- Utilisateur : `max` (créé via le portail web Azure, **pas** `azureuser`).
- Clé retenue : `~/.ssh/dutch-rl-azure` (dédiée). Trois clés locales sont en fait autorisées (`id_rsa`, `id_ed25519`, `dutch-rl-azure`).
- Historique : la toute première tentative `ssh max@20.91.236.73` avait échoué (`Permission denied (publickey)`) car la clé par défaut ne correspondait pas ; résolu en pointant la bonne clé via l'alias.

Commandes Azure utiles :

```bash
# Stopper la VM sans payer le compute
az vm deallocate --resource-group rg-dutch-rl --name rlDutch

# Redémarrer la VM
az vm start --resource-group rg-dutch-rl --name rlDutch

# Récupérer l'IP publique
az vm show --resource-group rg-dutch-rl --name rlDutch -d --query publicIps -o tsv

# Vérifier les quotas
az vm list-usage --location swedencentral -o table
```

> ⚠️ Pense à `az vm deallocate` quand la VM n'entraîne pas, pour ne pas payer le compute inutilement.

---

## État de l'environnement sur la VM

Installé et vérifié sur `rlDutch` (au 2026-06-25) :
- **Flutter 3.44.4 / Dart 3.12.2** (`~/flutter`, ajouté au PATH via `~/.bashrc`). Flutter est requis — et pas seulement Dart — car `pubspec.yaml` déclare des dépendances `sdk: flutter`, donc `dart pub get` seul échoue.
- `unzip`, `build-essential` (linker nécessaire à `dart compile exe`), `uv 0.11.24`.
- Code projet transféré par **rsync** depuis le local (repo privé) sous `~/dutch/` : `lib/`, `tool/`, `rl/`, `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`.
- Runner Dart compilé : `~/dutch/tool/rl_env_runner` (répond au protocole NDJSON).
- Environnement Python : venv `uv` **Python 3.12.13** dans `~/dutch/rl/.venv` (Ubuntu 22.04 n'a que Python 3.10, insuffisant) + `gymnasium`, `numpy`, `stable-baselines3 2.9.0`, `sb3-contrib 2.9.0`, `torch 2.12.1`, `tensorboard 2.20.0`.

Point d'optimisation connu (non bloquant) :
- `uv` a installé les wheels CUDA (`nvidia-*`) alors que la VM est CPU-only → venv à 4,6 Go. Réinstaller torch CPU-only récupérerait ~3 Go (21 Go encore libres, donc pas urgent).

Validation passée sur la VM (`rl/test_roundtrip.py`) : **6/6 vert** (relancé après recompilation du runner avec fix logger le 2026-06-25 22:49 CEST / 20:49 UTC)
1. aller-retour scripté ; 2. reward terminale Python↔Dart ; 3. déterminisme ; 4. honnêteté du masque ; 5. formes fixes 2-6 joueurs ; 6. robustesse process (kill + timeout).

> ✅ **VM validée après fix logger.** Le binaire `tool/rl_env_runner` est plus récent que `tool/rl_env_runner.dart` (`20:33` vs `20:32` UTC sur `ls -la`) et `rl/test_roundtrip.py` passe 6/6 depuis cette recompilation. Avant tout long run : conserver cette barrière 6/6 comme prérequis.

---

## Décisions d'architecture (phase 2 RL)

### Décidées et implémentées
- **Intégration Dart ↔ Python : subprocess + NDJSON sur stdin/stdout.** Le runner Dart headless (`tool/rl_env_runner.dart`) est la source de vérité des règles ; Python pilote via messages JSON ligne par ligne (`reset` / `observation` / `action` / `error` / `close`).
- **Le Dart est l'autorité du moteur** : aucune règle de jeu réimplémentée en Python.
- **Observation actuelle RL** : `OBS_DIM=147`. Elle reste une observation de baseline PPO, pas encore un event stream pur AgentInterface v2.
- **Action actuelle RL** : `N_ACTIONS=179` masqué. La micro-phase `reaction` existe maintenant : `pass_tick`, alias compatibilité `no_match`, et `match(slot)`. Tous les slots présents sont tentables, y compris pour faux match, sans filtrage expert.
- **Reaction window RL** (`8fa49fa`) : p0 peut matcher pendant la défausse collective, subir la pénalité de faux match, matcher après son propre `replace`, réaliser un doublon naturellement, matcher plusieurs fois, et faire `pass_tick` puis être réinvité si un bot matche dans la même fenêtre.
- **Pending match powers** (`1c2c4fa`) : après la reaction window, le runner headless résout `pendingMatchPowers`. Les `7/10` restent traités avant les pouvoirs actifs dans la queue pending actuelle. Les `Valet/Joker` actifs sont résolus en FIFO (plus de shuffle/loterie). Si le pouvoir appartient à p0, le runner expose la micro-phase `power` existante. Si le pouvoir appartient à un bot, le runner appelle `BotPowerHandler.useBotSpecialPower(..., skipDelay: true)` en mettant temporairement `currentPlayerIndex` sur le bot propriétaire puis en le restaurant. Côté UI, suppression du délai artificiel 800 ms et plus d'auto-skip des pending powers bot.
- **Reward hiérarchique** (depuis 2026-06-27, remplace l'ancienne MORL — cf. journal) : `principal(rang normalisé) + win_bonus + DESTAB_SCALE·clip(destab, ±CAP_DESTAB)`. Terme dominant = victoire/rang ; `win_bonus = kBonusMax·min(1, gap/kGapSat)` si rang==1 (`kBonusMax=0.30`, `kGapSat=20.0`, Dart) récompense les victoires nettes ; le destab dense est un **signal d'appoint borné** (`DESTAB_SCALE=1/256≈0.0039`, `CAP_DESTAB=2.0`, Python), plus jamais le terme dominant. Le proxy de déstabilisation reste celui d'avant (leader courant via `BotThreatAnalyzer`, reward_destab=0 si le proxy change). **Ancienne MORL retirée** : scalarisation `w1·principal + w2·destab` à poids Dirichlet concaténés à l'obs — abandonnée car le destab non borné dominait la reward (~105% du retour) et l'agent ne gagnait/n'appelait jamais Dutch (reward hacking).
- **Algo historique** : `sb3-contrib` MaskablePPO (PPO masqué) reste la baseline existante, isolée du chantier R2D2 v2. La pile R2D2 v2 ne dépend pas de SB3 et ne modifie aucun fichier PPO.
- **R2D2 v2 (cœur complet, pile `*_v2.py` isolée)** : recurrent Q-network GRU (`R2D2AgentV2`) à têtes Q factorisées + masquage par tête ; replay séquentiel episode-aware ; **burn-in complet** (état caché initial zéro par séquence, forward sur `burn_in + train`, loss sur `train_mask` seul, padding exclu, **pas de stored recurrent state** dans ce patch) ; n-step TD avec **source de vérité unique côté loss** (`dataset_v2.compute_n_step_returns` = helper offline) ; target network (hard sync + soft update dispo) ; **Double Q factorisé** sur les actions légales suivantes (online sélectionne, target évalue ; fallback action-type-head documenté et testé si actions légales next absentes) ; **prioritized sequence replay** (PER proportionnel par séquence, clé stable `(episode_id, start_step_index)`) ; **importance sampling weights** (`(N·P)^(-beta)`, normalisés max=1, jamais zéro) ; **update priorities depuis TD-error** (`eta·max|δ| + (1-eta)·mean|δ|` sur positions valides) ; learner câblé ; train CLI avec flags R2D2 ; checkpoint / infer / evaluate compatibles (format checkpoint inchangé, anciens checkpoints chargeables).
- **Schedules d'annealing R2D2 v2** (`rl/schedules_v2.py`, `LinearScheduleV2`) : annealing `priority_beta` côté training (appliqué au `sample_sequences(beta=...)`, donc influe réellement sur les IS weights ; **exige `--prioritized-replay`**) et annealing `epsilon` côté policy d'inférence/évaluation (step global qui décale entre épisodes). Choix : l'epsilon schedule est branché **uniquement là où une policy choisit vraiment des actions** (`infer_r2d2_v2`, exposé via `evaluate`/`smoke`) ; **pas d'epsilon schedule dans `train_r2d2_v2`** dont le smoke rejoue un dataset statique sans sélection d'action (aurait été décoratif). Le builder refuse un triplet `start/end/steps` partiel (erreur claire, jamais de schedule à moitié câblé).
- **Nombre de joueurs** : 2 à 6 (aligné sur le vrai jeu / UI).
- **Déterminisme** : RNG seedable côté Dart (`engine_random.dart`), seeds incrémentaux par épisode côté Python.
- **Entraînement parallèle** : `SubprocVecEnv` **K=4** retenu pour le premier run sérieux après mesures empiriques sur la VM. Mesures longues 10k steps vectorisés sans updates PPO : K=3 ≈2222 FPS agent, RSS arbre ≈2074→2078 MB ; K=4 ≈2547 FPS agent, RSS arbre ≈2610→2615 MB. Nombre de descendants observé = `2*K + 2` (workers Python + runners Dart + processus support Python forkserver/resource_tracker), stable. Mesure de croisière avec entraînement PPO réel : **≈1230 FPS agent** ; utiliser ce chiffre, pas 2547, pour dimensionner `--total-timesteps`.
- **Hyperparamètres PPO v1** : `n_steps=512`, `batch_size=128`, `gamma=0.997`, `gae_lambda=0.95`, `learning_rate=3e-4`, `clip_range=0.2`, `ent_coef=0.01`, `vf_coef=0.5`, `max_grad_norm=0.5`, `n_epochs=10`, `target_kl=0.03`.

### Encore à décider / à faire
- Valet complet côté RL : vrai choix `player_a/slot_a/player_b/slot_b`, joueur courant inclus si légal, adversaire ↔ adversaire si règle officielle.
- Joker complet côté RL : vérifier les cibles autorisées et la cohérence avec le vrai jeu.
- Event stream brut : `discard_reason`, `replaced_slot`, `match_discard`, événements publics ordonnés.
- Mémoire adverse légale structurée : cartes vues avec 10, âge de l'information, invalidations, stabilité temporelle des slots.
- ~~Dataset séquentiel puis R2D2/DRQN seulement après interface fidèle.~~ **Fait** : la pile R2D2 v2 (dataset séquentiel + cœur R2D2 + schedules) est implémentée et testée (cf. « R2D2 v2 » ci-dessus et journal 2026-06-30). Reste : premier vrai run plus long, puis évaluation et éventuel reward shaping.
- Stored recurrent state : non implémenté volontairement (burn-in complet retenu). Optimisation future possible si le burn-in devient coûteux.
- Acteurs distribués : plus tard, après validation mono-process.

---

## Fichiers importants (vérifiés dans le repo réel)

Phase 1 ML (à préserver, ne pas modifier) :
- `tool/ml_dataset_generator.dart` — générateur self-play headless.
- `lib/services/game/engine_random.dart` — RNG seedable.
- `ml/models/xgboost.joblib`, `ml/models/logreg.joblib`, `ml/models/random_forest.joblib`.
- `ml/` (pipeline Python : `scripts/`, `data/`, `reports/`, `README.md`).

Phase 2 RL (en cours) :
- `tool/rl_env_runner.dart` — env RL headless (source de vérité des règles côté Dart).
- `lib/services/game/bot/headless_threat_signal.dart` — ré-dérivation headless du signal de menace.
- `rl/runner_process.py` — pilote subprocess NDJSON ; `_recv()` lit le fd en **binaire** (`os.read` + découpage manuel des lignes, buffer résiduel `self._buf`, `bufsize=0`) — plus de mélange `select`/`readline` texte (cause racine du désync `BAD_PHASE` éliminée).
- `rl/encoding.py` — tables action/observation/masque.
- `rl/dutch_env.py` — `gym.Env` mono-agent ; `step()` traite toute erreur runner `fatal:false` comme récupérable (épisode tronqué, compteur `engine_recoverable_error_count`, log WARNING) et **lève** sur `fatal:true`.
- `rl/train_ppo.py` — entraîneur smoke (plomberie).
- `rl/train_parallel.py` — entraîneur PPO parallèle (`SubprocVecEnv`, checkpoints, TensorBoard, sauvegarde `finally`). Option `--resume-from` (`MaskablePPO.load` + `reset_num_timesteps=False` ; `--total-timesteps` = cible cumulée, additionnel calculé en interne). `FailureCountersCallback` : `--internal-error-threshold` + garde-fou de fréquence sur erreurs récupérables (`--recoverable-error-window` déf. 200000, `--recoverable-error-threshold` déf. 50, ≤0 pour désactiver).
- `rl/self_imitation_buffer.py` — buffer SIL isolé d'épisodes gagnants, capacité en transitions, contexte v1 `{"hard": bool}`, sampling équilibré par contexte éligible.
- `rl/self_imitation_callback.py` — callback SB3 isolé, reconstruit les épisodes par worker et stocke uniquement les épisodes terminaux avec `info["won"] is True`.
- `rl/self_imitation_ppo.py` — sous-classe isolée de `MaskablePPO`, ajoute une behavior cloning loss légère et capée (`bc_coef` défaut 0.001, cap défaut 0.005).
- `rl/train_self_imitation.py` — script séparé pour futurs runs SIL ; ne remplace pas `train_parallel.py`.
- `rl/test_self_imitation.py` — tests Python courts SIL.
- `rl/evaluate_behavior.py` — évaluation comportementale V1 offline, isolée du training : lit uniquement observation/masques/infos terminales déjà disponibles côté Python, produit un CSV séparé et un résumé par `skill × num_players`, sans changer observation/reward/runner.
- `rl/test_roundtrip.py` — barrière de validation (6 checks).
- `rl/pyproject.toml`, `rl/uv.lock` — dépendances RL uv (inclut TensorBoard pour SB3).
- `test/rl/` — tests Dart de non-régression du runner (dont byte-parity avec le générateur).

Pile R2D2 v2 (cœur RL v2, fichiers `*_v2.py` isolés — chacun a son `test_*_v2.py` vert) :
- `rl/encoding_v2.py` — encodeur AgentInterface v2 (faits publics, mémoire privée légale, event stream, stabilité slots, masques d'action factorisés). Séparé de `rl/encoding.py` (PPO legacy).
- `rl/rollout_v2.py` — recorder de transitions `TransitionV2` + (de)sérialisation JSONL.
- `rl/collect_rollouts_v2.py` — collecteur de rollouts réels via `RunnerProcess` (policy aléatoire légale).
- `rl/replay_buffer_v2.py` — replay séquentiel episode-aware ; `SequenceBatchV2` ; **prioritized replay** (alpha/beta/epsilon), IS weights, `update_priorities`, mode uniforme inchangé.
- `rl/dataset_v2.py` — loader JSONL → `ReplayBufferV2` ; `compute_n_step_returns` = helper offline d'analyse (pas la source de vérité d'entraînement).
- `rl/model_r2d2_v2.py` — `R2D2AgentV2` (GRU + têtes Q factorisées + masquage) ; stratégie burn-in complet documentée.
- `rl/loss_r2d2_v2.py` — TD loss n-step factorisée, Double Q, bootstrap sur actions légales next, IS weighting ; **source de vérité n-step**.
- `rl/policy_r2d2_v2.py` — sélection d'action `action_v2` (greedy / epsilon-greedy) à partir des sorties factorisées.
- `rl/infer_r2d2_v2.py` — boucle d'inférence step-par-step (état caché porté dans l'épisode) ; **epsilon schedule** branché ici.
- `rl/learner_r2d2_v2.py` — learner (loss → backward → clip → optimizer), Double Q, IS weighting, calcul + écriture des priorités, hard/soft target sync.
- `rl/train_r2d2_v2.py` — CLI d'entraînement borné depuis JSONL ; flags R2D2 (`--prioritized-replay`, `--double-q`, `--priority-alpha/beta/epsilon/eta`) et **schedule beta** (`--priority-beta-start/end/steps`) ; garde-fous (pas de long run sans `--allow-long-run`, pas de save sans `--allow-save`).
- `rl/smoke_r2d2_v2.py` — smoke end-to-end (collect → train → checkpoint → infer), artefacts temporaires auto-supprimés ; flags epsilon schedule.
- `rl/evaluate_r2d2_v2.py` — évaluation bornée random vs checkpoint, métriques enrichies (win-rate, rangs, scores p0, dutch calls, done reasons) ; flags epsilon schedule.
- `rl/schedules_v2.py` — `LinearScheduleV2` (warmup, clamp, `value_at`) + `build_optional_schedule` (refuse les triplets partiels). Partagé par beta (train) et epsilon (infer/evaluate/smoke).

État worktree local à ne pas mélanger avec les commits AgentInterface :
- Hors cette mise à jour handoff, changements hors scope encore présents : `rl/dutch_env.py`, `rl/train_parallel.py`, scripts auxiliary et nombreux CSV/reports non suivis.
- Ne pas inclure ces fichiers dans un commit lié à l'AgentInterface sauf demande explicite.

Supprimés (ne plus référencer) :
- `dutch-server/src/services/QLearningService.ts`, `NeuralNetworkService.ts`, `GeneticAlgorithmService.ts` — supprimés du repo le 2026-06-26 après confirmation 0 usage prod sur 2,5 mois. Les routes correspondantes répondent 410. Déploiement blue/green à faire séparément.

> Ne pas supposer que cette liste est exhaustive. Inspecter le repo réel avant toute modification.

---

## Prochaine étape immédiate

Le cœur R2D2 v2 et ses schedules sont en place, et le runner est stable après le
fix de fidélité. Le prochain pas logique n'est plus un run : c'est un **patch
reward v2 testé** à partir de `docs/ai/RL_REWARD_V2_AUDIT.md`.

Plan recommandé :
1. Ajouter une scalarisation reward unique côté Python v2, partagée par
   `rollout_v2`, `collect_rollouts_v2`, `infer_r2d2_v2` et les traces.
2. Ajouter/émettre une pénalité immédiate de faux match, assez visible pour
   éviter match-spam mais inférieure au signal terminal victoire/défaite.
3. Décider explicitement si `win_bonus` est consommé (recommandé) ou retiré de la
   documentation, puis tester ce choix.
4. Garder le bon match à `0` ou à un bonus minuscule : c'est un moyen, pas le but.
5. Ajouter les tests Dart/Python listés dans `docs/ai/RL_REWARD_V2_AUDIT.md`.
6. Ensuite seulement : collecte neuve, retrain from scratch, évaluation + traces.

Ne jamais committer dataset/checkpoint/report dans le repo. Ne pas lancer de run long sans validation explicite.

En parallèle (fidélité d'interface, indépendant du run R2D2), divergences restantes à documenter avant un entraînement « définitif » :
1. **Valet RL encore simplifié** : le runner RL ne permet pas encore le vrai choix complet `player_a/slot_a/player_b/slot_b`. Le Valet complet est le prochain chantier recommandé.
2. **Joker RL encore simplifié** : vérifier plus tard les cibles autorisées et la cohérence avec le vrai jeu. Ne pas corriger en même temps que Valet.
3. **Pas encore d'event stream brut** : `discard_reason` existe côté moteur/tracker mais n'est pas exposé au RL (`drawn_discard`, `exchange_discard`, `match_discard`). `replaced_slot` existe pour `exchange_discard` mais n'est pas exposé comme fait public au RL. Pas encore de mémoire adverse légale structurée.
4. **Observation encore imparfaite pour AgentInterface v2 pure** : l'observation PPO contient encore des signaux dérivés/interprétatifs existants. À garder pour baseline, mais un futur belief-state/R2D2 devra utiliser des faits publics/event stream.
5. **Gossip/alliance** : `BotGossipService` / alliance n'est pas actif dans le runner RL actuel. Ne pas l'ajouter maintenant.

Roadmap courte (fidélité d'interface, en parallèle du run R2D2) :
1. Valet complet (le runner RL expose déjà `player_a/slot_a/player_b/slot_b` côté AgentInterface v2 ; finaliser/valider la cohérence).
2. Joker complet / cohérence cibles.
3. Event stream brut : `discard_reason`, `replaced_slot`, `match_discard`, événements publics.
4. Mémoire adverse légale : cartes vues avec 10, âge de l'info, slots changés, stabilité des slots.
5. ~~Dataset séquentiel.~~ **Fait** (pile R2D2 v2).
6. ~~R2D2/DRQN seulement après interface fidèle.~~ **Fait** : cœur R2D2 v2 + schedules construits et testés ; le premier vrai run plus long est la prochaine action (cf. ci-dessus).

Ne pas modifier le code applicatif hors périmètre AgentInterface tant qu'un plan court n'est pas validé.

---

## Suivi sécurité (à traiter)

- Une inspection antérieure de la prod (`pm2 jlist`) a exposé `FIREBASE_SERVICE_ACCOUNT_JSON` (clé privée) et `FIREBASE_WEB_API_KEY` dans un transcript. **Rotation de la clé de service Firebase recommandée.**

---

## Journal des mises à jour

### 2026-06-30 — Audit reward v2 H2 (Codex)

Contexte :
- Le runner v2 est stable après le fix timer réaction/recyclage, mais aucun
  retrain ne doit être lancé tant que le reward H2 n'est pas revu.
- Objectif de cette passe : audit documentaire seulement, sans modifier le code
  reward ni lancer collecte/training.

Changement :
- Ajout de `docs/ai/RL_REWARD_V2_AUDIT.md`.
- Mise à jour du présent handoff : la prochaine étape immédiate devient un patch
  reward v2 testé, pas un run R2D2.

Constats principaux :
- La reward Dart terminale `principal` est rank-normalized et utilise
  `GameState.getFinalRanksWithTies()`, donc le Dutch raté est bien dernier actif
  côté moteur.
- Dart émet aussi `win_bonus` et `destab`, mais les extracteurs R2D2 v2 Python
  (`rl/rollout_v2.py`, `rl/collect_rollouts_v2.py`, `rl/infer_r2d2_v2.py`) ne
  stockent que `rewards.principal` dans `TransitionV2.reward`.
- Faux match, bon match, draw/replace/discard/powers/pass_tick ont actuellement
  `0.0` de reward immédiate optimisée. H2 est confirmé : faux match n'a pas de
  malus RL immédiat visible, seulement un coût futur sparse via le score/rang.

Résultat :
- **Ne pas entraîner maintenant.**
- Prochaine action recommandée : patch reward v2 conservateur + tests
  Dart/Python, puis collecte neuve et retrain from scratch.

### 2026-06-30 — Audit fidélité runner + fix timer réaction/recyclage + éval post-fix (Claude Code)

Contexte : le premier run contrôlé (collecte 9370 transitions, train 3000 steps) et son éval ont révélé que le modèle greedy ne terminait presque jamais les parties (`average_steps≈457.8`, `reached_max_steps=27/30`, `dutch_calls=0`). Le logger + analyseur de traces action-level (`786a791`, `738b153`) ont localisé la cause : boucle `match` en `reaction`/`ended`.

Étapes :
- **Logger/analyseur de traces** (`786a791 feat(rl): add v2 action trace logging`, `738b153 feat(rl): add v2 action trace analysis`) : `rl/action_trace_v2.py` (+test), `rl/analyze_action_trace_v2.py` (+test) ; niveaux `none/selected/legal_scores/full`, gzip, scan anti-fuite, scores identiques à la policy.
- **Audit fidélité** (`c9f9ad8 docs(rl): audit v2 runner fidelity`) : `docs/ai/RL_RUNNER_FIDELITY_AUDIT.md`. 3 BLOCKERs (réaction `pass_tick` au lieu du timer ; `phase=ended` `done=false` ; faux match `deck=0` no-op ; `legal_action_v2` proposant `match` en `ended`).
- **Fix runner** (`72a442b` puis `9682d7b fix(rl): simulate reaction timer and recycle discard`) : timer global 3s simulé (3000/100 = 30 ticks), aucune action ne reset le timer, chaque décision consomme un tick, recyclage défausse (sauf top) à la pioche, faux match toujours pénalisé, `phase=ended ⇒ done=true`, plus de `match` en terminal. `tool/rl_env_runner.dart` + `test/rl/rl_env_runner_test.dart` (groupes 2c + 2d). 67/67 Dart (parité #5 OK), Python v2 + `test_roundtrip` 6/6, binaire recompilé (gitignored).
- **Éval contrôlée post-fix** (sans training) : épisodes terminants (30/30), `reached_max_steps` 27/30 → **0/30**, `match_chain_max` ~100 → **30**, `phase=ended done=false` → **0**, 0 illégal, 0 crash. Détails et tableaux dans la section « Fidélité du runner RL v2 » ci-dessus.

Décisions :
- Runner **stable pour retrain**.
- **Ancien checkpoint à jeter comme base** (biaisé par le runner pré-fix ; policy match-spam ; pire que random au score final).
- **Ne pas relancer de training** tant que le reward **H2** (faux matchs sous-pénalisés) n'a pas été revu.

Prochaine action recommandée : audit/rework reward v2 → collecte neuve (epsilon-greedy) sur runner corrigé → retrain from scratch → éval + traces.

### 2026-06-30 — Cœur R2D2 v2 complété + schedules beta/epsilon (Claude Code)

Contexte :
- L'AgentInterface v2 et sa pile d'amorçage (`encoding_v2`, rollout recorder/collector, replay buffer séquentiel, dataset loader JSONL, `R2D2AgentV2`, TD loss factorisée, policy `action_v2`, smokes inference/learner/training/e2e/evaluation, métriques d'évaluation enrichies) étaient déjà committées (`b8d88df` → `990dd9a`).
- Deux jalons ont ensuite complété et durci le cœur R2D2 v2, sans toucher PPO legacy, le gameplay, `GameLogic`, le runner Dart, `rl/encoding.py`, `rl/dutch_env.py`, `rl/train_parallel.py`, ni les CSV/scripts auxiliaires.

Commit `010751e feat(rl): complete v2 r2d2 core` :
- **Prioritized sequence replay** : PER proportionnel par séquence dans `ReplayBufferV2`, clé stable `(episode_id, start_step_index)` (survit à l'éviction front), `prioritized/priority_alpha/beta/epsilon`, mode uniforme strictement inchangé (déterminisme préservé).
- **Importance sampling weights** : `(N·P(i))^(-beta)`, normalisés pour `max==1`, jamais nuls ; `None` en mode uniforme (loss non pondérée).
- **Update priorities depuis TD-error** : `update_priorities(sample_indices, priorities)`, priorité R2D2 `eta·max|δ| + (1-eta)·mean|δ|` sur positions valides (ni burn-in ni padding), réécrite dans le buffer.
- **Double Q factorisé** : bootstrap sur les actions légales suivantes (`legal_actions_v2` propagé dans le batch) — online sélectionne l'action gloutonne, target l'évalue ; fallback action-type-head **explicite et testé** quand les actions légales next sont absentes (jamais d'action illégale fabriquée).
- **n-step TD propre** : construit dans la loss à partir de la séquence (source de vérité unique) ; `dataset_v2.compute_n_step_returns` redocumenté comme helper offline et **plus appelé-puis-jeté** dans le loader (code mort retiré) ; test de cohérence croisée loss↔dataset.
- **Burn-in complet documenté et verrouillé** : état caché initial zéro par séquence, forward sur `burn_in + train`, loss sur `train_mask` seul, padding exclu, **pas de stored recurrent state** ; test de continuité d'état caché (full pass == burn-in puis train avec état porté).
- **Learner** : `double_q` + `priority_eta` en config ; IS weighting, écriture des priorités, métriques complètes (`weighted_loss`, `mean/max_td_error`, `mean_priority`, `mean_is_weight`, `double_q`, `prioritized`, `priority_eta`, …).
- **Train CLI** : `--prioritized-replay`, `--double-q`, `--priority-alpha/beta/epsilon/eta` ; garde-fous long-run/no-save/no-runner/no-import-side-effect intacts ; checkpoint inchangé (vérifié chargeable). Compatibilité infer/evaluate/smoke/policy/model préservée (champs batch optionnels).
- 11 fichiers (6 source + 5 tests) ; smoke court e2e : `collected=51 train_steps=5 infer_steps=20 loss=0.001110 artifacts=removed`.

Commit `8d42d87 feat(rl): add v2 r2d2 schedules` :
- **`rl/schedules_v2.py`** : `LinearScheduleV2` (`start_value`, `end_value`, `duration_steps`, `warmup_steps`, `clamp`, `value_at(step)`) + fonction pure + `build_optional_schedule` qui **refuse un triplet partiel** (erreur claire).
- **Beta schedule (PER)** dans `train_r2d2_v2` : `--priority-beta-start/end/steps` ; beta annealé appliqué à `sample_sequences(beta=...)` → **influe réellement sur les IS weights** ; métriques `priority_beta_current` + `schedule_step` ; **exige `--prioritized-replay`** (sinon erreur, jamais décoratif).
- **Epsilon schedule (policy)** dans `infer_r2d2_v2` : `--epsilon-start/end/steps` ; epsilon annealé sur un **step global** qui décale entre épisodes ; valeur enregistrée dans `info["inference_epsilon"]` ; exposé via `evaluate_r2d2_v2` et `smoke_r2d2_v2`. **Pas** ajouté à `train_r2d2_v2` (smoke = dataset statique sans sélection d'action → aurait été décoratif).
- 11 fichiers (2 nouveaux : `schedules_v2.py`, `test_schedules_v2.py` ; 9 modifiés).

Validation (les deux jalons) :
- `py_compile` de toute la pile v2 OK ; `git diff --check` OK.
- Tests unitaires v2 tous verts : `schedules`, `replay_buffer`, `dataset`, `model`, `loss`, `policy`, `infer`, `learner`, `train`, `evaluate`, `smoke`, `encoding`.
- Barrière `rl/test_roundtrip.py` : **6/6**.
- Smokes : e2e baseline OK (`artifacts=removed`) ; schedule epsilon (`--epsilon-start 1.0 --epsilon-end 0.1 --epsilon-steps 5`) OK ; schedule beta via train CLI (dataset en scratchpad hors repo) → beta annealé `0.2000 → 0.4667 → 0.7333 → 1.0000`, `checkpoint=None`.

Garde-fous respectés :
- Aucun entraînement long ; aucun dataset/checkpoint/report versionné committé (le dataset de test était dans le scratchpad hors repo) ; aucun fichier hors scope stagé/committé ; pas de version cheap / fallback dangereux / schedule décoratif.

État / prochaine action recommandée :
- Cœur R2D2 v2 prêt pour un **premier vrai run contrôlé plus long** (collecte ~10k transitions → quelques milliers de steps → evaluate vs random/bots → métriques hors repo → reward shaping si besoin). Stored recurrent state et acteurs distribués = plus tard.

### 2026-06-30 — AgentInterface v2 : reaction window RL + pendingMatchPowers

Contexte :
- PPO/reward shaping/auxiliary heads sont en pause.
- L'objectif immédiat est de rendre l'interface RL fidèle au vrai Dutch'78 avant de discuter R2D2/DRQN ou nouvel entraînement.

Commits validés :
- `8fa49fa feat(rl): expose reaction window to RL agent`
- `1c2c4fa feat(game): resolve pending match powers for bots`

Changement commit `8fa49fa` :
- Ajout de la micro-phase `reaction` au siège RL p0.
- Ajout de `pass_tick`; `no_match` reste accepté comme alias de compatibilité.
- Ajout de `match(slot)`.
- Faux match possible et pénalisé.
- Tous les slots présents sont tentables, sans filtrage expert.
- p0 peut matcher après son propre `replace`, ce qui rend la technique du doublon possible naturellement.
- p0 peut matcher plusieurs fois dans une même fenêtre.
- p0 peut `pass_tick` puis être réinvité si un bot match pendant la même fenêtre.
- Dimensions actuelles : `OBS_DIM=147`, `N_ACTIONS=179`.

Changement commit `1c2c4fa` :
- Les `pendingMatchPowers` sont résolus côté runner headless après la reaction window.
- Les `7/10` restent traités avant `Valet/Joker` dans la queue pending actuelle.
- Les `Valet/Joker` actifs sont résolus en FIFO : plus de shuffle/loterie, premier posé = premier résolu.
- Si le pouvoir pending appartient à p0, le runner expose la micro-phase `power` existante.
- Si le pouvoir pending appartient à un bot, le bot utilise `BotPowerHandler.useBotSpecialPower(..., skipDelay: true)`.
- Les bots ne skip plus automatiquement leurs pending powers.
- Le délai artificiel 800 ms côté UI a été supprimé.
- `currentPlayerIndex` est temporairement mis sur le bot propriétaire du pouvoir, puis restauré.
- `GameLogic` n'a pas été modifié.

Validation :
- `dart analyze lib/providers/game_provider.dart tool/rl_env_runner.dart test/rl/rl_env_runner_test.dart` : OK.
- `flutter test test/rl/rl_env_runner_test.dart` : OK.
- `python3 -m py_compile rl/encoding.py rl/evaluate_behavior_v3.py rl/test_roundtrip.py` : OK.
- `dart compile exe tool/rl_env_runner.dart -o tool/rl_env_runner` : OK.
- `cd rl && uv run python test_roundtrip.py` : OK.
- Aucun entraînement lancé.
- Aucun push effectué.

État / divergences restantes :
- Valet RL encore simplifié : pas encore de vrai choix complet `player_a/slot_a/player_b/slot_b`.
- Joker RL encore simplifié : cibles et cohérence avec le vrai jeu à vérifier plus tard.
- Pas encore d'event stream brut : `discard_reason`, `replaced_slot`, `match_discard` et événements publics ne sont pas exposés proprement au RL.
- Pas encore de mémoire adverse légale structurée : cartes vues avec 10, âge de l'info, invalidations et stabilité des slots restent à concevoir.
- L'observation PPO contient encore des signaux dérivés/interprétatifs ; à garder pour baseline, mais pas comme interface finale belief-state/R2D2.
- `BotGossipService` / alliance n'est pas actif dans le runner RL actuel.
- Hors cette mise à jour handoff, worktree hors scope encore présent : `rl/dutch_env.py`, `rl/train_parallel.py`, scripts auxiliary, CSV/reports et autres modifications non liées à ces deux commits. Ne pas les mélanger avec le chantier AgentInterface.

Prochaine action recommandée :
- Implémenter le Valet complet côté RL, avec tests contrôlés, avant Joker complet, event stream, mémoire adverse légale, dataset séquentiel et R2D2/DRQN.

### 2026-06-29 — Étape B auxiliary heads : PPO isolé + smoke

Contexte :
- Étape A validée : les labels auxiliaires sont disponibles et suffisamment fréquents pour tester une première loss faible (`dutch_label_coverage≈0.61`, `dutch_would_win_pos_rate≈0.21` sur mini-run).
- Objectif : créer une piste isolée, sans changer l'observation ni le training principal, pour tester deux têtes auxiliaires BCE.

Changement :
- Ajout de `rl/auxiliary_ppo.py` :
  - `AuxiliaryRolloutBuffer` sous-classe `MaskableRolloutBuffer` et stocke les labels auxiliaires synchronisés transition par transition.
  - `AuxiliaryMaskableActorCriticPolicy` ajoute deux têtes : `aux_full_hand_known` et `aux_dutch_would_win_now_when_legal`.
  - `AuxiliaryMaskablePPO` ajoute une loss auxiliaire BCE faible, masquée par `aux_dutch_label_valid` pour le label Dutch.
- Ajout de `rl/train_auxiliary.py`, script de smoke/training court séparé de `train_parallel.py`.

Garanties :
- Pas de modification d'observation (`OBS_DIM=146`), aucun label dans `obs`.
- Pas de modification d'action mask.
- Pas de modification de `tool/rl_env_runner` binaire ni de `tool/rl_env_runner_behavior.dart`.
- Expériences auxiliary à lancer avec `--anti-missed-dutch-coef 0.0` pour ne pas mélanger avec la pénalité reward-only.

Validation :
- `python3 -m py_compile rl/auxiliary_ppo.py rl/train_auxiliary.py rl/dutch_env.py rl/train_parallel.py` : OK.
- `OBS_DIM=146` confirmé.
- Test import/shape : `AuxiliaryMaskablePPO` créé, logits auxiliaires shapes `(1,)`, observation `(146,)`.
- Mini-run 1024 steps avec `--anti-missed-dutch-coef 0.0 --aux-coef 0.001` : OK, losses auxiliaires loggées, pas de NaN visible, erreurs runner `0`, pénalité count/total `0`.
- Sauvegarde/chargement du modèle `/tmp/dutch_auxiliary_heads_smoke_models/auxiliary_maskable_ppo_final.zip` : OK ; prédiction masquée légale.
- Smoke `evaluate_behavior_v3.py` sur le checkpoint auxiliaire et `/tmp/rl_env_runner_behavior` : OK.

Prochaine action recommandée :
- Après validation explicite seulement : run court 5M ou 10M avec `rl/train_auxiliary.py`, sorties séparées, `--anti-missed-dutch-coef 0.0`, puis comparaison V3+ contre le checkpoint 90M et le 100M.

### 2026-06-29 — Étape A auxiliary heads : collecte/logging sans loss

Contexte :
- Le run court 10M avec pénalité reward-only anti-missed-Dutch n'a pas corrigé le Dutch timing : sous-appel Dutch persistant, missed real wins toujours très élevés.
- Décision : ne pas continuer à tuner les pénalités au hasard ; préparer une piste auxiliary heads, mais commencer par vérifier les labels sans modifier PPO.

Changement :
- `rl/dutch_env.py` ajoute `info["aux_labels"]` sur chaque step, calculé depuis les `training_signals` pré-action : `aux_full_hand_known`, `aux_dutch_label_valid`, `aux_dutch_would_win_now_when_legal`, `aux_full_table_rounds_completed`, `aux_late_game_bucket`.
- `rl/train_parallel.py` loggue ces labels via le callback existant : `aux/full_hand_known_rate`, `aux/dutch_label_coverage`, `aux/dutch_would_win_pos_rate`, `aux/late_game_rate`.
- Ajout de `--log-every-steps` pour rendre les métriques visibles dans les mini-runs.

Garanties :
- Pas de policy custom, pas de `AuxiliaryMaskablePPO`, pas d'auxiliary loss.
- Pas de changement d'observation (`OBS_DIM=146`), pas de changement d'action mask, pas de changement de reward hors pénalité existante déjà désactivable.
- `tool/rl_env_runner.dart` et `tool/rl_env_runner_behavior.dart` restent compatibles ; le binaire principal `tool/rl_env_runner` n'a pas été remplacé.

Validation :
- `python3 -m py_compile rl/dutch_env.py rl/train_parallel.py` : OK.
- `dart analyze tool/rl_env_runner.dart` : OK.
- `OBS_DIM=146` confirmé.
- Mini-run PPO 1024 steps avec `--anti-missed-dutch-coef 0.0` : OK, logs `aux/*` présents, pénalité count/total à 0.
- Smoke `evaluate_behavior_v3.py` sur `/tmp/rl_env_runner_behavior` : OK.

Prochaine action recommandée :
- Si les distributions de labels sont jugées suffisantes, implémenter ensuite une classe isolée `AuxiliaryMaskablePPO` minimale avec une seule tête binaire faible (`dutch_would_win_now_when_legal`) et garder `--anti-missed-dutch-coef 0.0` pendant l'expérience.

### 2026-06-29 — Pénalité reward-only anti-missed-Dutch

Contexte :
- Run 100M terminé proprement, puis sweep V3+ des checkpoints 37M/37.5M/50M/60M/70M/80M/90M/100M.
- Conclusion expérimentale : meilleures décisions locales possibles sur swap/draw, mais Dutch timing toujours mauvais (`missed real wins` très élevé, missed late persistants, known-full late encore ratés).

Changement :
- `tool/rl_env_runner.dart` émet un champ top-level `training_signals` sur les observations non terminales : `dutch_would_win_now`, `dutch_margin_now`, `full_table_rounds_completed`, `p0_full_hand_known`, `dutch_legal_now`.
- `rl/dutch_env.py` consomme le signal pré-action pour appliquer une petite pénalité si l'agent n'appelle pas Dutch alors que la situation est tardive, gagnante, connue et avec marge positive.
- `rl/train_parallel.py` expose `--anti-missed-dutch-coef` (défaut `0.08`, `0.0` désactive), `--anti-missed-dutch-min-rounds` (défaut `2`) et `--anti-missed-dutch-require-full-known/--no-...` (défaut full-known requis), plus logs TensorBoard `reward/anti_missed_dutch_penalty_{count,total,mean}`.
- L'observation reste inchangée (`OBS_DIM=146`) ; les diagnostics V3+ restent eval-only dans `tool/rl_env_runner_behavior.dart`.

Validation :
- `python3 -m py_compile rl/dutch_env.py rl/train_parallel.py` : OK.
- `dart analyze tool/rl_env_runner.dart` : OK.
- Compilation test uniquement vers `/tmp/rl_env_runner_anti_missed_dutch` : OK.
- Smoke direct runner : `training_signals` présent hors `obs`.
- Test unitaire manuel de pénalité : marge 10, coef 0.08 => pénalité 0.04.
- Mini-run PPO 2048 steps sur `/tmp/rl_env_runner_anti_missed_dutch` : OK, `illegal_count=0`, erreurs runner `0`, pénalité déclenchée 1 fois (`0.036`).
- Smoke `evaluate_behavior_v3.py` sur `/tmp/rl_env_runner_behavior` : OK.
- `uv run python test_roundtrip.py` sur le binaire principal existant : 6/6 OK.

État actuel :
- Source modifiée, mais `tool/rl_env_runner` n'a pas été remplacé.
- Aucun checkpoint existant modifié, aucun CSV supprimé, aucun push effectué.

Prochaine action recommandée :
- Compiler explicitement `tool/rl_env_runner` seulement au moment de lancer un run court anti-missed-Dutch, puis entraîner 10M/20M et comparer V3+ contre 37.5M/90M/100M.

### 2026-06-28 — Évaluation comportementale RL V1 offline

Changement :
- Ajout de `rl/evaluate_behavior.py`, script isolé d'évaluation comportementale offline pour diagnostiquer le comportement d'un checkpoint RL sans modifier le training.
- Aucun changement observation/reward/runner.
- Aucun fichier protégé modifié : `rl/train_parallel.py`, `rl/dutch_env.py`, `tool/rl_env_runner.dart`, `tool/rl_env_runner`.
- Aucun push effectué.

Métriques V1 disponibles :
- Dutch legal decisions, appels Dutch de l'agent, Dutch call rate when legal.
- Dutch success/bad call, marge Dutch au moment où l'agent appelle, score agent et meilleur score adverse au call.
- Usage des pouvoirs (`7`, `10`, `V`, `JOKER`) et taux d'usage quand disponible.
- Proxies explicites pour discard/replace (`*_proxy`), basés sur les informations connues/croyances de l'observation.
- Trajectoire du score connu/estimé (`known_score_*`, `estimated_score_*`).

Limites V1 :
- Pas de vraies missed Dutch opportunities.
- Pas de vraie marge Dutch à chaque décision.
- Pas de vrai `swap_delta_real_score`.
- Pas de vraie discard quality si la carte remplacée est inconnue.
- Ces métriques nécessitent une future V2 avec diagnostics exposés par le runner Dart.

Validation :
- `cd rl && uv run python -m py_compile evaluate_behavior.py` : OK.
- Smoke court OK sur checkpoint compatible `models/maskable_ppo_parallel_checkpoint_10000000_steps.zip` (`--games 1 --skills bronze --num-players 2`).
- Le script détecte proprement les checkpoints incompatibles `obs_dim=148` et abort avec message explicite.

État actuel :
- `dutch_rl_train4` reste actif et intact.
- `rl/evaluate_behavior.py` est prêt pour commit local après validation ; aucun CSV de smoke n'est conservé.
- Aucun push effectué.

### 2026-06-27 — Self-Imitation Learning isolé + check-in `dutch_rl_train4`

Changement :
- Ajout d'une première piste Self-Imitation Learning (SIL) pour MaskablePPO en fichiers isolés uniquement.
- Aucun fichier utilisé par le run actif n'a été modifié : `rl/train_parallel.py`, `rl/dutch_env.py`, `tool/rl_env_runner.dart`, `tool/rl_env_runner` sont restés intacts.
- Aucun runner Dart recompilé, aucun tmux stoppé, aucun long training lancé, aucun commit/push effectué.

Fichiers créés :
- `rl/self_imitation_buffer.py` : buffer d'épisodes gagnants, capacité en transitions, purge FIFO par épisode, contexte v1 `{"hard": bool}`, sampling équilibré entre contextes éligibles, structure extensible pour futur `skill`/`num_players`.
- `rl/self_imitation_callback.py` : callback SB3 qui reconstruit les épisodes par worker via les locals de `collect_rollouts`, stocke uniquement les terminaux avec `info["won"] is True`, ignore pertes/troncatures/crash/timeout/recoverable errors, loggue `sil/*`.
- `rl/self_imitation_ppo.py` : sous-classe isolée de `MaskablePPO`, recopie locale de `train()` depuis sb3-contrib installé et ajout d'une BC loss légère `-log_prob(actions gagnantes).mean()`, `bc_coef=0.001`, contribution effective capée par défaut à `0.005`, buffer exclu des sauvegardes modèle.
- `rl/train_self_imitation.py` : script séparé de futur run SIL (`SubprocVecEnv`, `ActionMasker`, `Monitor`, checkpoints, sauvegarde finale, flags SIL), sans remplacer `train_parallel.py`.
- `rl/test_self_imitation.py` : tests Python courts.

Commandes exécutées :
- `tmux ls`, `tmux list-panes`, `tmux capture-pane -t dutch_rl_train4:0.0 -p -S -80` en lecture seule.
- `cd rl && uv run python test_self_imitation.py`
- `cd rl && uv run python -m py_compile self_imitation_buffer.py self_imitation_callback.py self_imitation_ppo.py train_self_imitation.py test_self_imitation.py`

Résultat obtenu :
- `test_self_imitation.py` : **6/6 vert**.
- `py_compile` : OK.
- Check-in run actif : `dutch_rl_train4` actif (`cmd=uv`), ~32,1M timesteps, ≈1009 fps, `eval/win_rate_hard=0.121`, `engine_internal_errors=0`, `engine_recoverable_errors=7`, `runner_crashes=0`, `runner_timeouts=0`.

État actuel :
- `dutch_rl_train4` continue de tourner.
- SIL est implémenté mais non entraîné en long run.
- Changements locaux non committés/non pushés.

Prochaine action recommandée :
- Laisser finir `dutch_rl_train4`.
- Après validation explicite, lancer éventuellement un run séparé avec `rl/train_self_imitation.py` ; commencer par un smoke très court avant tout run long.

### 2026-06-27 — Smoke runtime SIL 1024 steps

Changement :
- Validation runtime très courte de l'intégration `SelfImitationPPO + SelfImitationCallback + DutchEnv` via `rl/train_self_imitation.py`.
- Aucun fichier protégé modifié/recompilé : `rl/train_parallel.py`, `rl/dutch_env.py`, `tool/rl_env_runner.dart`, `tool/rl_env_runner`.
- `dutch_rl_train4` laissé actif, aucun commit/push.

Commande exécutée :
```bash
cd rl && uv run python train_self_imitation.py \
  --num-workers 1 \
  --total-timesteps 1024 \
  --checkpoint-freq 1000000 \
  --tensorboard-log-dir tmp_sil_smoke_runs \
  --model-out tmp_sil_smoke_models \
  --curriculum-hard-ratio 0.0 \
  --sil-buffer-size 1000 \
  --sil-min-episodes-per-context 1 \
  --sil-batch-size 16 \
  --bc-coef 0.001 \
  --bc-effective-loss-cap 0.005
```

Résultat :
- Exit code 0.
- Modèle final temporaire créé : `tmp_sil_smoke_models/maskable_ppo_sil_final.zip`.
- TensorBoard temporaire créé : `tmp_sil_smoke_runs/MaskablePPO_1/events.out.tfevents...`.
- Logs `train/bc_loss`, `train/bc_effective_loss` et `train/bc_ratio_to_policy_loss` produits pendant le smoke.
- Correction monitoring validée après relance smoke : `train/bc_ratio_to_policy_loss=0.0687`, cohérent avec `bc_effective_loss=0.000944` et `policy_gradient_loss=-0.0137` (ratio des moyennes agrégées, plus de dénominateur mini-batch quasi nul).
- Dossiers temporaires supprimés après vérification : `rl/tmp_sil_smoke_models`, `rl/tmp_sil_smoke_runs`.
- Tests courts relancés ensuite : `uv run python test_self_imitation.py` **6/6 vert** ; `py_compile` ciblé OK.

État actuel :
- SIL validé en smoke runtime court seulement.
- Aucun long training SIL lancé.
- Changements locaux non committés/non pushés.

### 2026-06-27 — Restructure reward + run 30M + diagnostic éval v2 + plan PISTE 1

**Contexte (chantier reward, fait avant ce diagnostic) :**
- Reward MORL **retirée**, remplacée par une reward **hiérarchique** (cf. section décisions). Constantes : `kBonusMax=0.30`, `kGapSat=20.0` (Dart) ; `DESTAB_SCALE=1/256≈0.0039`, `CAP_DESTAB=2.0` (Python). Motif : le destab non borné dominait le retour (~105%), l'agent ne gagnait/n'appelait jamais Dutch (reward hacking).
- **OBS_DIM 148 → 146** (suppression des 2 poids MORL concaténés à l'obs). Casse la compat avec l'ancien checkpoint : garde-fou explicite dans `evaluate_rl.py` (abort si `obs_dim` du modèle ≠ `encoding.OBS_DIM`) + `check_for_correct_spaces` SB3 au resume → échec **franc**, pas silencieux.
- **Monitoring direct (PART B)** : `FailureCountersCallback` logge `eval/{rank_mean,win_rate,dutch_call_rate,dutch_success_rate,collapse_warn}` (fenêtres glissantes, par épisode/step) + garde-fou collapse en **WARNING seul** (jamais d'arrêt auto, décision validée : pas de référence fiable du comportement normal à 3M sous la nouvelle reward).
- Validé avant run : `flutter analyze` propre, `test_roundtrip.py` 6/6 (obs=(146,)), parité #5 verte.

**Run 30M (`dutch_rl_train3`) :**
- Run à neuf (obligatoire vu OBS 148→146), 30M steps, ~1150 fps, ~7h. Terminé **sain** : 0 collapse, métriques en progression continue jusqu'au bout (win_rate ~0.256, dutch_success ~0.634, rank_mean ~2.72). Modèle final : `rl/models/maskable_ppo_parallel_final.zip` (écrasé proprement en fin de run réussi, pas pendant un crash).

**Diagnostic éval v2 (`rl/report_v2.csv`, 15 000 parties = 15 conditions × 1000, 0 abandon, 2m43s) :**
- **Bug « n'appelle jamais Dutch » RÉSOLU** : p0 appelle Dutch dans **50.9%** des parties, succès **65.5%** (≈ dutch_success d'entraînement 63.4% → éval cohérente avec l'entraînement, pas d'écart train/éval suspect).
- **MAIS effondrement en conditions dures** : contre bots `difficile` en multijoueur, win% **sous le hasard** — difficile×3j **20.9%** (hasard 33%), ×4j **9.0%** (25%), ×5j **4.2%** (20%), ×6j **2.2%** (16.7%). Seul le heads-up difficile (2j, 53.7%) tient.
- Par skill adverse : bronze **58.8%**, silver **26.0%**, difficile **18.0%**. Niveau global ≈ **« silver »**.
- **Verdict : PAS prêt à remplacer le bot « difficile ».** Le remplacer l'affaiblirait en multijoueur (3+).
- Cause suspectée : le mix d'entraînement (chemin défaut `_buildPlayers`, tirage **uniforme** skill×behavior×num_players) sous-expose l'agent aux conditions dures (difficile + 4-6 joueurs), justement là où il échoue. Indice corroborant : contre difficile les parties sont courtes (les bots ferment vite via Dutch avant que p0 ait le temps de jouer).

**Plan retenu (PISTE 1, isolée — ne touche NI observation NI reward, toutes deux validées) :**
- Quota strict : **70% des épisodes d'entraînement en `difficile × num_players∈{4,5,6}`**, 30% tirage uniforme classique. Implémentation **côté Python uniquement** (`DutchEnv.reset`, réutilise le levier `extra_options` déjà existant et testé → **zéro changement Dart**, chemin défaut/parité #5 intact). Ajout métrique séparée **`eval/win_rate_hard`** (rang==1 sur les seuls épisodes en condition dure) pour juger l'effet réel — le `win_rate` global baissera mécaniquement avec un mix plus dur. **Plan détaillé présenté, en attente de validation avant tout code.**

Fichiers concernés (chantier reward, déjà sur disque, **non committés**) : `tool/rl_env_runner.dart`, `rl/dutch_env.py`, `rl/encoding.py`, `rl/train_parallel.py`, `rl/evaluate_rl.py`, `rl/test_roundtrip.py`, `rl/train_ppo.py`. Artefacts éval : `rl/report_v2.csv`, `rl/eval_run_v2.log`.

État historique à ce moment-là : aucun entraînement en cours. Cette ligne est dépassée par l'entrée du 2026-06-27 ci-dessus : `dutch_rl_train4` est désormais actif.

Prochaine action recommandée : valider le plan PISTE 1, l'implémenter (Python only), relancer un run avec le quota et surveiller `eval/win_rate_hard` vs `eval/win_rate`.

### 2026-06-26 09:18 UTC — Évaluation rapide checkpoint 19M

Changement :
- Évaluation indicative du checkpoint `rl/models/maskable_ppo_parallel_checkpoint_19000000_steps.zip` pendant que le run principal continue.
- Aucun fichier source modifié.
- Compilation d'un binaire d'éval séparé `/tmp/rl_env_runner_eval` pour ne pas écraser `tool/rl_env_runner` pendant l'entraînement.

Pourquoi :
- Les logs `train_parallel.py` ne journalisent pas directement `won` / `rank`; ils exposent surtout reward, longueur, KL et compteurs de défaillances. Il fallait donc utiliser `rl/evaluate_rl.py` pour savoir si le modèle gagne.

Fichiers / commandes concernés :
- Première tentative : `uv run python evaluate_rl.py models/maskable_ppo_parallel_checkpoint_19000000_steps.zip --games 5 ...` a abort car le binaire `tool/rl_env_runner` est trop ancien pour l'extension d'éval (`num_players=99` non rejeté).
- Compilation sans toucher au binaire de training : `dart compile exe tool/rl_env_runner.dart -o /tmp/rl_env_runner_eval`.
- Éval : `cd rl && uv run python evaluate_rl.py models/maskable_ppo_parallel_checkpoint_19000000_steps.zip --games 5 --exe /tmp/rl_env_runner_eval --out /tmp/dutch_eval_19m_g5.csv`.

Résultat obtenu :
- 225 parties évaluées (45 conditions × 5 parties), aucune partie abandonnée.
- Résultat très bruité (5 parties/condition), mais mauvais à ce stade :
  - macro win-rate `(1,0)` : **2,7 %** ;
  - macro win-rate `(0.5,0.5)` : **2,7 %** ;
  - macro win-rate `(0,1)` : **1,3 %**.
- Les seules victoires observées sont contre `bronze`, surtout en 2 joueurs, plus une condition bronze 5 joueurs `(0,1)`.
- L'agent n'appelle jamais Dutch dans cet échantillon (`dutch%=0.0%` partout), signe qu'il n'a pas encore appris la stratégie de fin de manche.

État actuel :
- L'entraînement principal `dutch_rl_train2` continue après l'éval : vérifié à `total_timesteps=19 223 616`, ≈1246 fps, `engine_recoverable_errors=1`, `runner_crashes=0`, `runner_timeouts=0`.

Prochaine action recommandée :
- Ne pas conclure définitivement sur le niveau final avant la fin du run. Refaire une évaluation plus robuste (au moins 100 parties/condition, idéalement 1000) sur le modèle final, puis comparer vs bots existants / aléatoire.

### 2026-06-26 09:12 UTC — Check-in run RL repris

Changement :
- Vérification demandée de l'état du run RL repris.
- Correction de contexte : l'agent est déjà exécuté sur la VM `rlDutch`; la tentative SSH précédente était inutile.
- Aucun code modifié ; ce handoff est mis à jour avec l'état observé.

Commandes / observations :
- `hostname` renvoie `rlDutch`.
- `tmux ls` montre `dutch_rl_train2` actif, et `tmux list-panes` indique `cmd=uv` pour `dutch_rl_train2:0.0`.
- Lecture directe du pane `tmux capture-pane -t dutch_rl_train2:0.0`.
- Dernier bloc observé : `total_timesteps=18 781 248`, `fps=1246`, `iterations=4776`.
- Compteurs observés : `engine_internal_errors=0`, `engine_recoverable_errors=1`, `runner_crashes=0`, `runner_timeouts=0`.
- Dernier checkpoint local observé : `rl/models/maskable_ppo_parallel_checkpoint_18500000_steps.zip` à `09:08:49` UTC.

État actuel :
- Le run RL est **toujours actif** au check-in 09:12 UTC.
- Progression : ~18,8M / 57,6M steps cumulés.

Prochaine action recommandée :
- Continuer à laisser tourner sans modifier le code. Refaire un check périodique via `tmux capture-pane -t dutch_rl_train2:0.0 -p -S -80`, le log ou les checkpoints.

### 2026-06-26 ~07:01 UTC — Crash BAD_PHASE résolu (3 correctifs) + reprise du run

**Symptôme :** pendant le run `dutch_rl_train` (~9M steps), un worker `SubprocVecEnv` a été tué par une `RuntimeError` non gérée (« BAD_PHASE épisode déjà terminé »). Le process principal est resté bloqué à ~103% CPU sans avancer, avec 3/4 runners Dart orphelins.

**Cause racine :** désync rare d'un message dans `_recv()` (`runner_process.py`) — mélange de `select()` sur le fd brut et de `readline()` sur un flux texte bufferisé avec read-ahead : sous charge, une rafale de plusieurs lignes désynchronisait le flux. Côté Python, `dutch_env.py::step()` ne traitait comme récupérable que `code=="INTERNAL" && fatal:true` ; toute autre erreur (dont `BAD_PHASE`) tombait sur un `raise` générique qui tuait le worker.

**Trois correctifs appliqués (validés par 21 tests verts : 15 Dart + 6 Python) :**
1. `rl/dutch_env.py::step()` — toute erreur runner `fatal:false` est désormais récupérable (`terminated=False`, `truncated=True`, compteur `engine_recoverable_error_count` distinct, log WARNING). `fatal:true` **LÈVE** désormais, y compris `INTERNAL+fatal:true` — **changement** vs le comportement précédent qui tronquait : on ne masque plus un état moteur corrompu.
2. `rl/runner_process.py::_recv()` — réécrit en lecture **binaire** (`os.read` + découpage manuel des lignes, buffer résiduel `self._buf`, `bufsize=0`). Plus de mélange `select`/`readline` texte ; une rafale multi-lignes est mise en buffer et rendue une ligne par appel. Cause racine du désync éliminée.
3. `rl/train_parallel.py` — option `--resume-from` (`MaskablePPO.load(path, env=env)` + `model.learn(..., reset_num_timesteps=False)`). `--total-timesteps` reste la **cible cumulée** ; l'additionnel est calculé en interne. Vérifié dans le source SB3 installé : `stable_baselines3/common/base_class.py:416` fait `total_timesteps += self.num_timesteps` quand `reset_num_timesteps=False`, et `num_timesteps` n'est pas dans `_excluded_save_params` (donc restauré par `load`). Garde-fou de fréquence sur erreurs récupérables ajouté dans `FailureCountersCallback` (fenêtre glissante `deque`) : `--recoverable-error-window` (déf. 200000) et `--recoverable-error-threshold` (déf. 50, ≤0 pour désactiver).

**Reprise du run :**
- Nouvelle session tmux `dutch_rl_train2` (l'ancienne `dutch_rl_train` est morte avec le crash).
- Reprise depuis `models/maskable_ppo_parallel_checkpoint_9000000_steps.zip` (PAS `maskable_ppo_parallel_final.zip`, écrit pendant l'agonie du crash → état non fiable).
- `num_timesteps` restauré = 9 000 000 ; additionnel calculé = 48 600 000 ; cible cumulée 57 600 000.
- Confirmation : `total_timesteps` démarre à ~9 018 432 (pas 0) → `reset_num_timesteps=False` OK. Les nouveaux checkpoints continuent la numérotation depuis ~9M (pas d'écrasement des `*_steps.zip` existants).
- ≈1221 fps, log `rl/runs/train_parallel_resume_20260626_070144.log`.

**Fichiers modifiés :** `rl/dutch_env.py`, `rl/runner_process.py`, `rl/train_parallel.py`, `docs/ai/HANDOFF.md`.

**État actuel :** run en cours dans `dutch_rl_train2`. `pubspec.lock` reste modifié localement hors périmètre.

**Prochaine action recommandée :** laisser tourner jusqu'à 57,6M (ou check-in périodique) ; ne reprendre, si besoin, que depuis le dernier `*_steps.zip` valide via la commande de reprise (section « Prochaine étape immédiate »). Puis évaluer le modèle vs bots existants / aléatoire.

### 2026-06-26 — Validation prod complète de la suppression ML legacy + découverte CI/CD

#### Point 1 — Confirmation finale du déploiement de suppression ML legacy

Le déploiement (commit `ec360e0`, puis `699006f` après amend du message) a été vérifié de bout en bout :

Build & tests :
- Build TypeScript : 0 erreur (Node 24.14.0).
- Tests : 419/420. Le seul échec (`adaptiveDifficulty.test.js`) confirmé pré-existant et indépendant de nos changements, via double vérification : test croisé sur Node 24.18.0 et git stash sur l'ancien commit.

Déploiement prod :
- CI `deploy-server.yml` déclenché automatiquement au push sur `main`, complété en ~2m33s.
- `GIT_SHA` en prod : `ec360e01`, instance `dutch-server-green` (port 3001), symlink `current` → `releases/ec360e0...`.
- Ancienne instance `dutch-server-blue` proprement supprimée par le CI.
- Logs de démarrage : **zéro trace ML** — `ℹ️ Nouveau réseau de neurones créé` et `ℹ️ Nouvelle Q-Table créée` ont disparu.

Vérification visuelle par Max (dashboards admin) :
- `bot-dashboard.html` : section "🧠 Statistiques Machine Learning" disparue, reste du dashboard intact.
- `bot-stats.html` ("🤖 Bot Learning Dashboard") : aucune dépendance aux routes supprimées. Ce fichier appelle uniquement `/stats`, `/top-bots`, `/training-series` — toutes intactes.

Routes legacy :
- `/ml-stats`, `/predict-action`, `/genetic/*` répondent 410 Gone (confirmé indirectement : 401 sans secret admin valide prouve que le serveur répond et que le middleware d'auth s'exécute avant le stub 410).

**Conclusion : suppression complètement validée en prod. Aucune régression détectée.**

---

#### Point 2 — Découverte structurelle : push sur main = déploiement automatique immédiat

Le workflow `.github/workflows/deploy-server.yml` se déclenche sur **tout** push vers `main`, sans filtre `paths:`. Il n'existe pas de filtre limité à `dutch-server/` — **même un commit touchant uniquement `docs/` déclenche un cycle blue/green complet** (build Flutter web + build serveur + déploiement). Vérifié sur le trigger :

```yaml
on:
  push:
    branches: ["main"]
  workflow_dispatch:
# (pas de paths: filter)
```

Implication pour tout futur agent ou session :
- Il n'existe **pas** de fenêtre entre "push sur main" et "déploiement en prod réelle". Le cycle blue/green complet (build, healthcheck, bascule nginx, suppression ancienne instance) s'exécute en ~2-3 minutes, **sans étape de validation manuelle intermédiaire**.
- La validation du commit/diff **est** en réalité la validation du déploiement — il n'y a pas de second gate.
- Cela s'applique à **tout** push sur main, y compris des changements purement documentaires comme cette entrée de handoff.
- La VM Azure RL (`rlDutch`) **n'est pas concernée** : elle ne dispose pas de déploiement continu et nécessite un `git pull` + recompilation manuels.

**Règle à respecter impérativement pour toute future modification de `dutch-server/` :**
Présenter le plan **et** le diff complet AVANT le push — pas seulement avant un hypothétique "déploiement" séparé qui n'existe pas comme étape distincte. Mentionner explicitement à l'utilisateur que `git push origin main` = mise en prod immédiate avant de pousser quoi que ce soit touchant `dutch-server/src/` ou `dutch-server/public/`.

### 2026-06-26 — Suppression des services ML legacy (QLearning / NeuralNetwork / GeneticAlgorithm)

Changement :
Suppression complète de trois services ML expérimentaux qui étaient instanciés au démarrage du serveur (consommant de la mémoire, loggant `ℹ️ Nouveau réseau de neurones créé`) mais n'avaient aucun usage actif en prod — confirmé par 2,5 mois de logs PM2 (blue + green, 14 avril → 25 juin 2026, 0 hit sur les routes concernées).

Étapes exécutées :
1. **`BotLearningService.ts`** — suppression des 3 imports, 3 champs privés, 3 instanciations constructeur, appels `trainFromGame`/`decayEpsilon` dans `processPendingGames()`, `saveGameRecord()` et `resetAll()`. Suppression de 4 méthodes publiques devenues sans objet : `getMLStats()`, `predictAction()`, `getGeneticService()`, `selectQLearningAction()`.
2. **`botLearningRoutes.ts`** — remplacement de 6 routes (`GET /ml-stats`, `POST /predict-action`, `POST /genetic/initialize`, `POST /genetic/evolve`, `GET /genetic/population`, `GET /genetic/best`) par des stubs `410 Gone`. Les 26+ autres routes restent intactes.
3. **`bot-dashboard.html`** — suppression des CSS `.ml-stats`/`.ml-card`/`.ml-title`/`.ml-stat`, de la section HTML `🧠 Statistiques Machine Learning`, de la fonction JS `loadMLStats()` (50 lignes), et de son appel dans `Promise.all([...])`.
4. **Tests** — suppression de 3 fichiers de test entiers (`qlearning.test.ts`, `neuralNetwork.test.ts`, `geneticAlgorithm.test.ts`) + retrait de 3 blocs `describe`/`it` dans `botLearning.test.ts` (`getMLStats`, `predictAction`, `getGeneticService`).
5. **Suppression des sources** — `QLearningService.ts`, `NeuralNetworkService.ts`, `GeneticAlgorithmService.ts` supprimés de `dutch-server/src/services/`.

Fichiers modifiés / supprimés :
- Modifiés : `dutch-server/src/services/BotLearningService.ts`, `dutch-server/src/routes/botLearningRoutes.ts`, `dutch-server/public/bot-dashboard.html`, `dutch-server/src/__tests__/botLearning.test.ts`.
- Supprimés : `dutch-server/src/services/QLearningService.ts`, `NeuralNetworkService.ts`, `GeneticAlgorithmService.ts`, `dutch-server/src/__tests__/qlearning.test.ts`, `neuralNetwork.test.ts`, `geneticAlgorithm.test.ts`.

Résultats build & tests :
- **Build TypeScript** : 0 erreur (`npm run build`, Node 24.14.0).
- **Tests** : 419/420 pass. Le seul échec (`dist/__tests__/adaptiveDifficulty.test.js`) est pré-existant : confirmé indépendant de ces changements par double vérification — (a) même échec reproductible sur le code d'avant via `git stash` + test, (b) même erreur V8 deserialization sur Node 24.18.0 sur l'ancien code. Aucun test de la suite actuelle n'est cassé par nos changements.
- **Grep de vérification** : 0 référence résiduelle à `QLearning`, `NeuralNetwork` ou `GeneticAlgorithm` dans `dutch-server/src/`.

État actuel :
- Committé et pushé sur `origin/main`.
- **Déploiement blue/green : EN ATTENTE** — décision séparée, à faire explicitement. Séquence prévue : déployer sur `dutch-server-blue` (instance inactive), valider le démarrage (absence de logs ML), vérifier les 410 sur les routes legacy, basculer le trafic de green vers blue.
- `pubspec.lock` reste une modification locale non committée, hors périmètre.

Prochaine action recommandée :
- Valider le déploiement blue/green de manière explicite et séparée.

### 2026-06-26 00:05 UTC — Correction du statut prod Q-learning / NeuralNetwork

Changement :
- Correction d'une affirmation inexacte du handoff : `dutch-server/src/services/QLearningService.ts`, `NeuralNetworkService.ts` et `GeneticAlgorithmService.ts` étaient décrits comme « exclus de la compilation TS » et « confirmés inutilisés en prod ». Ces deux points précis sont faux pour le déploiement actuel.
- La recommandation reste inchangée : ne pas réveiller ces modules et ne pas s'en inspirer pour la phase 2 RL.

Vérification prod lecture seule :
- Serveur inspecté : `root@164.92.234.245`.
- Process actif : PM2 `dutch-server-green`.
- Release actif : `/root/apps/dutch-server/releases/36dcb9a23d99b4e42ee9d6fd9c13f276ff7dd704`.
- Commit/build déclarés par PM2 : `36dcb9a23d99b4e42ee9d6fd9c13f276ff7dd704`, build `2026-06-25T23:23:02Z`.
- Fichiers compilés présents dans le `dist/` réellement déployé :
  - `dist/services/QLearningService.js`
  - `dist/services/NeuralNetworkService.js`
  - `dist/services/GeneticAlgorithmService.js`
  - `dist/services/BotLearningService.js`
  - `dist/routes/botLearningRoutes.js`
- Les logs PM2 récents du process actif contiennent `ℹ️ Nouveau réseau de neurones créé`, ce qui confirme que `NeuralNetworkService` est instancié au démarrage du serveur.

État des données :
- Le point « données purgées » reste exact pour les données d'apprentissage runtime : `qlearning/`, `neural/`, `genetic/`, `games/`, `profiles/`, `adaptive/`, `leaderboard/`, `clones/` et `tournaments/` sont vides hors `.gitkeep`.
- Seul `personalities/` contient 8 fichiers JSON statiques (`the_*`), qui sont des profils de personnalité, pas des données d'apprentissage.
- Aucune trace dans les 100 dernières lignes des logs PM2 du process actif d'un appel récent à `/api/bot-learning/record`, d'un `Q-Learning entraîné`, d'un `Réseau de neurones entraîné`, de `predict-action`, de `ml-stats` ou de `training-series`.

Conclusion correcte :
- Ces services sont chargés et vivants en mémoire au démarrage du serveur ; ce n'est donc pas du code mort exclu de compilation.
- Ils n'ont pas de données d'entraînement actuelles ni de preuve d'usage récent, donc ils n'ont pas d'influence réelle observée sur le comportement des bots en production aujourd'hui.
- Si les routes `/api/bot-learning/*` recevaient de nouvelles données valides, ce code pourrait recommencer à apprendre.

État actuel :
- Handoff corrigé sur ce point.
- Aucun fichier applicatif modifié.
- `pubspec.lock` reste une modification locale hors périmètre.

Prochaine action recommandée :
- Si une suppression est envisagée, analyser d'abord les imports, routes `/api/bot-learning/*`, clients Flutter/admin et logs PM2 sur une fenêtre plus large, puis retirer proprement les routes/instanciations avant de supprimer les services.

### 2026-06-26 01:20 — Lancement du run réel 13 h PPO parallèle

Changement :
- Lancement du premier run réel PPO parallèle dans une session tmux persistante nommée `dutch_rl_train`.
- Chemins persistants choisis :
  - TensorBoard : `/home/max/dutch/rl/runs`
  - Modèles/checkpoints : `/home/max/dutch/rl/models`
  - Log stdout complet : `/home/max/dutch/rl/runs/train_parallel_20260625_231422.log`
- `rl/runs/` et `rl/models/` sont bien gitignorés par `rl/.gitignore` ; ces artefacts ne doivent pas être committés.

Commande exacte lancée depuis `/home/max/dutch/rl` :

```bash
uv run python train_parallel.py --num-workers=4 --total-timesteps=57600000 \
  --checkpoint-freq=500000 --internal-error-threshold=8 \
  --tensorboard-log-dir=/home/max/dutch/rl/runs \
  --model-out=/home/max/dutch/rl/models \
  2>&1 | tee -a /home/max/dutch/rl/runs/train_parallel_20260625_231422.log
```

Paramètres :
- `num_workers=4`
- `total_timesteps=57600000` (≈13 h visées avec le repère de croisière ≈1230 steps agent/s)
- `checkpoint_freq=500000` (≈115 checkpoints attendus)
- `internal_error_threshold=8`

Horaires :
- Démarrage tmux : 2026-06-25 23:14:54 UTC (2026-06-26 01:14:54 CEST).
- Fin estimée à ≈1230 steps agent/s : 2026-06-26 vers 12:15 UTC (14:15 CEST).

Processus principaux confirmés :
- `uv run` : PID `18490`
- Python venv : PID `18494`

Suivi / rattachement :
- Rattacher tmux : `tmux attach -t dutch_rl_train`
- Détacher sans tuer : `Ctrl-B`, puis `D`
- Suivre le log : `tail -f /home/max/dutch/rl/runs/train_parallel_20260625_231422.log`
- TensorBoard : `cd /home/max/dutch/rl && uv run tensorboard --logdir runs`

Résultat initial observé :
- Run confirmé actif après 1-2 minutes, puis re-vérifié à environ 5 min.
- Exemple observé : `iterations=200`, `total_timesteps=409600`, `fps=1241`, `ep_len_mean=49.6`, `ep_rew_mean=6.4`.
- Compteurs défaillance observés dans le log : `engine_internal_errors=0`, `runner_crashes=0`, `runner_timeouts=0`.
- TensorBoard écrit : `/home/max/dutch/rl/runs/MaskablePPO_1/events.out.tfevents...`.

État actuel :
- Aucune action de code attendue jusqu'à la fin du run ou un point de contrôle volontaire.
- Le run lui-même ne doit générer que des artefacts gitignorés (`rl/runs/`, `rl/models/`).
- `pubspec.lock` reste une modification locale hors périmètre.

Prochaine action recommandée :
- Attendre la fin du run (ou faire un check-in périodique de santé).
- Après fin : évaluer le modèle obtenu contre les bots existants et contre un agent aléatoire (protocole à définir), avant de passer à la conception des agents « moyen » et « facile ».

### 2026-06-26 01:06 — Fermeture robuste après Ctrl-C dans `train_parallel.py`

Changement :
- Patch de `rl/train_parallel.py` dans le bloc `finally` de `main()` : `model.save(...)` reste inchangé et obligatoire, puis `env.close()` est maintenant entouré d'un `try/except` qui ignore uniquement les erreurs de fermeture déjà cassée : `BrokenPipeError`, `ConnectionResetError`, `EOFError`, `OSError`.
- Message explicite en cas d'exception ignorée : fermeture de l'environnement déjà interrompue (pipe cassé ou fermé), avec le type et le message de l'exception.

Pourquoi :
- Pendant un run de croisière interrompu par `Ctrl-C`, le modèle final se sauvegardait correctement, mais `SubprocVecEnv.close()` pouvait ensuite lever `BrokenPipeError` ou `EOFError` si un pipe worker était déjà fermé/cassé. Résultat : traceback et code de sortie `1`, trompeur puisque la sauvegarde avait réussi.
- Le patch ne masque pas une erreur de `model.save()` : seule la fermeture `env.close()` est tolérante.

Fichiers / commandes concernés :
- Modifié : `rl/train_parallel.py`.
- Inspection SB3 : `stable_baselines3/common/vec_env/subproc_vec_env.py`, `close()` lit `remote.recv()` puis envoie `remote.send(("close", None))`, ce qui explique `EOFError` ou erreur de pipe selon l'état exact du worker.
- Reproduction :
  `uv run python train_parallel.py --num-workers=4 --total-timesteps=900000 --checkpoint-freq=200000 --tensorboard-log-dir=/tmp/dutch_rl_fps_check_runs --model-out=/tmp/dutch_rl_fps_check_models --internal-error-threshold=8`

Résultat obtenu :
- Reproduction après patch : interruption `Ctrl-C` après environ 80-90 s, pas de traceback, `EXIT_CODE=130` propre.
- Modèle final confirmé présent avant nettoyage : `/tmp/dutch_rl_fps_check_models/maskable_ppo_parallel_final.zip`.
- TensorBoard confirmé présent et non vide : `/tmp/dutch_rl_fps_check_runs/MaskablePPO_1/events.out.tfevents...`.
- Compteurs erreurs à zéro : `engine_internal_errors=0`, `runner_crashes=0`, `runner_timeouts=0`.
- Artefacts temporaires `/tmp/dutch_rl_fps_check_runs` et `/tmp/dutch_rl_fps_check_models` supprimés après vérification.

FPS de croisière :
- Le test long réel avec updates PPO a stabilisé autour de **1230 steps agent/s** sur K=4 (run précédent monté à environ 190 itérations / 389 120 timesteps avant interruption).
- Ce chiffre est nettement inférieur à la sonde sans entraînement PPO (K=4 ≈2547 FPS agent). Pour calculer le `--total-timesteps` d'un run multi-heures, utiliser **≈1230 steps agent/s**, pas ≈2550.

État actuel :
- `train_parallel.py` gère correctement l'interruption volontaire : sauvegarde finale, fermeture tolérante si pipe déjà cassé, code retour `130`.
- `pubspec.lock` reste modifié localement mais hors périmètre.

Prochaine action recommandée :
- Commit/push de `rl/train_parallel.py` + ce handoff, puis fixer le volume du run 13 h avec le repère ≈1230 FPS : ordre de grandeur **13 h ≈ 57,6 M timesteps agent**.
- Vérifier la disponibilité de `nohup`, `screen` ou `tmux` sur la VM, lancer le run en arrière-plan et suivre via TensorBoard.

### 2026-06-26 00:24 — Ajout entraînement PPO parallèle + TensorBoard

Changement :
- Ajout de `rl/train_parallel.py`, script d'entraînement PPO masqué parallèle :
  - CLI : `--num-workers` défaut 4, `--total-timesteps` défaut 5 000 000 (point à confirmer avant run multi-heures), `--checkpoint-freq`, `--tensorboard-log-dir`, `--model-out`, `--internal-error-threshold` défaut 8.
  - Environnement : `SubprocVecEnv` avec `DutchEnv(seed_start=worker_idx * 100_000)`, `ActionMasker`, `Monitor`.
  - Modèle : `MaskablePPO("MlpPolicy", ...)` avec `n_steps=512`, `batch_size=128`, `gamma=0.997`, `gae_lambda=0.95`, `learning_rate=3e-4`, `clip_range=0.2`, `ent_coef=0.01`, `vf_coef=0.5`, `max_grad_norm=0.5`, `n_epochs=10`, `target_kl=0.03`.
  - Callbacks : `CheckpointCallback` avec correction `save_freq = checkpoint_freq // num_workers`, et callback custom cumulant `engine_internal_error`, `runner_crashed`, `runner_timeout`; arrêt propre si `engine_internal_error > threshold`.
  - Sauvegarde finale garantie dans `finally` vers `maskable_ppo_parallel_final.zip`.
- Ajout de `tensorboard>=2.20.0` via `uv add tensorboard` dans `rl/pyproject.toml`.
- Création de `rl/uv.lock` : lock volontaire à suivre pour reproductibilité des dépendances RL.

Pourquoi :
- Passer de la plomberie smoke mono-env (`rl/train_ppo.py`) à un script de run parallèle multi-heures robuste, avec checkpoints, TensorBoard, sauvegarde finale, et surveillance des erreurs avant de lancer un entraînement sérieux.

Décision K=4 :
- Sondes FPS/mémoire longues sur VM, 10 000 steps vectorisés, warmup 100, actions légales masquées :
  - K=3 : `fps_avg=2222.52`, premier dixième `2224.10`, dernier dixième `2249.49`, RSS arbre `2074.1 -> 2077.5 MB`, descendants `8 = dart:3 + python:5`.
  - K=4 : `fps_avg=2546.65`, premier dixième `2517.25`, dernier dixième `2573.20`, RSS arbre `2610.4 -> 2614.5 MB`, descendants `10 = dart:4 + python:6`.
- Écart descendants vs `2*K` expliqué par les processus support Python (`forkserver`/`resource_tracker`) de `SubprocVecEnv`. Pas de crash, pas de dérive mémoire inquiétante.
- Conclusion : K=4 retenu par défaut pour le premier run sérieux.

Fichiers / commandes concernés :
- Créé : `rl/train_parallel.py`.
- Modifié : `rl/pyproject.toml`.
- Créé : `rl/uv.lock`.
- Commande dépendance : `cd rl && uv add tensorboard`.
- Commande vérif version : `uv run python -c "import tensorboard; print(tensorboard.__version__)"` → `2.20.0`.
- Smoke test :
  `uv run python train_parallel.py --num-workers=4 --total-timesteps=2000 --checkpoint-freq=500 --tensorboard-log-dir=/tmp/dutch_rl_smoke_runs --model-out=/tmp/dutch_rl_smoke_models --internal-error-threshold=8`

Résultat obtenu :
- Smoke test **OK, exit code 0**.
- TensorBoard fonctionnel : event file écrit dans `/tmp/dutch_rl_smoke_runs/MaskablePPO_1/`.
- Checkpoints écrits dans `/tmp/dutch_rl_smoke_models/` :
  - `maskable_ppo_parallel_checkpoint_500_steps.zip`
  - `maskable_ppo_parallel_checkpoint_1000_steps.zip`
  - `maskable_ppo_parallel_checkpoint_1500_steps.zip`
  - `maskable_ppo_parallel_checkpoint_2000_steps.zip`
- Modèle final écrit : `maskable_ppo_parallel_final.zip`.
- Compteurs erreurs : `engine_internal_errors=0`, `runner_crashes=0`, `runner_timeouts=0`.
- Artefacts `/tmp/dutch_rl_smoke_runs` et `/tmp/dutch_rl_smoke_models` supprimés après vérification.

État actuel :
- `train_parallel.py`, `pyproject.toml`, `uv.lock` et ce handoff prêts à être commit/push.
- `pubspec.lock` reste modifié localement mais hors périmètre.

Prochaine action recommandée :
- Fixer une durée cible du premier run multi-heures et convertir en `--total-timesteps` avec le FPS K=4 réel avec updates PPO (~1230 steps agent/s) : 1 h ≈ 4,4 M, 4 h ≈ 17,7 M, 13 h ≈ 57,6 M.
- Vérifier sur la VM la disponibilité de `nohup`, `screen` ou `tmux`, lancer `train_parallel.py` en arrière-plan, puis suivre via TensorBoard.

### 2026-06-25 23:12 — Robustesse `DutchEnv.step()` avant entraînement parallèle

Changement :
- Patch de `rl/dutch_env.py` dans `DutchEnv.step()` pour distinguer deux modes de défaillance :
  - Mode 1 infra : `RunnerCrashed` ou `RunnerTimeout` levés par `self._runner.step(...)` → fermeture du runner via `self._runner.close(quiet=True)`, transition Gymnasium valide avec `reward=0.0`, `terminated=False`, `truncated=True`, `obs=self._last_obs.copy()`, et `info["runner_crashed"]=True` ou `info["runner_timeout"]=True`.
  - Mode 2 moteur vivant mais erreur applicative : message NDJSON `{"type":"error","code":"INTERNAL","fatal":true}` → log Python `ERROR`, compteur `self.engine_internal_error_count`, transition tronquée valide avec `info["engine_internal_error"]=True`, `engine_error_code`, `engine_error_message`, `engine_error_fatal`.
- Les autres erreurs runner (`code != INTERNAL` ou `fatal` falsy) conservent le comportement existant : `RuntimeError`.

Pourquoi :
- Préparer `train_parallel.py` / `SubprocVecEnv` pour un run multi-heures : éviter qu'un accident infra rare tue un worker, tout en gardant les erreurs moteur `INTERNAL` visibles et comptabilisables comme signaux de bug.

Fichiers / commandes concernés :
- Modifié : `rl/dutch_env.py`.
- Vérification préalable de cohérence : `RunnerProcess.close()` met bien `self.proc = None`, et `RunnerProcess.reset()` appelle `_ensure_alive()`, qui relance quand `_alive()` est faux (`self.proc is None` ou `poll() != None`).
- Tests lancés :
  - `flutter test test/rl/`
  - `cd rl && uv run python test_roundtrip.py`

Résultat obtenu :
- **15/15 tests Dart RL verts**.
- **Roundtrip Python 6/6 vert** :
  1. aller-retour scripté ;
  2. reward terminale Python↔Dart ;
  3. déterminisme ;
  4. honnêteté du masque ;
  5. formes fixes 2-6 joueurs ;
  6. robustesse process kill + timeout.

État actuel :
- Patch prêt à être committé avec ce handoff.
- `pubspec.lock` reste modifié localement mais hors périmètre de ce patch.
- Le binaire runner Dart n'a pas été modifié/recompilé par ce patch Python.

Prochaine action recommandée :
- Écrire `rl/train_parallel.py`, mesurer le FPS réel sur la VM avant de fixer `K`, puis choisir le volume `total_timesteps` du premier long run.

### 2026-06-25 22:49 — Validation roundtrip VM après recompilation du runner

Changement :
- Vérification post-recompilation du binaire `tool/rl_env_runner` avec le fix logger (`GameLoggerService.instance.setEnabled(false)` en tête de `main()`).
- Mise à jour de l'état VM dans ce handoff : la VM n'est plus considérée en retard pour ce point, le runner recompilé a été validé par la barrière Python.

Pourquoi :
- Confirmer que `rl/test_roundtrip.py` teste bien le binaire recompilé, et pas un ancien artefact antérieur au fix `_logBuffer`.

Fichiers / commandes concernés :
- Lecture timestamps : `ls -la tool/rl_env_runner tool/rl_env_runner.dart`.
- Résultat timestamps : `tool/rl_env_runner` = `Jun 25 20:33`, `tool/rl_env_runner.dart` = `Jun 25 20:32` → le binaire est plus récent que la source.
- Commande demandée via uv : `cd /home/max/dutch/rl && uv run python test_roundtrip.py`.
- Note d'exécution : premier lancement sandboxé bloqué par le cache uv (`Could not create temporary file ... /home/max/.cache/uv/... Read-only file system`), puis relance autorisée de la même commande. `uv` a utilisé CPython 3.12.13, créé `rl/.venv` et installé 35 packages.

Résultat obtenu :
- `rl/test_roundtrip.py` passe **6/6**.
- Sortie complète :

```text
Using CPython 3.12.13
Creating virtual environment at: .venv
Installed 35 packages in 754ms
=== test_roundtrip : 6 vérifications ===
  [OK ] 1. aller-retour scripté — épisode terminé en 15 steps, transitions cohérentes
  [OK ] 2. reward terminale Python<->Dart — 8 fins de partie cohérentes (principal == rang normalisé)
  [OK ] 3. déterminisme — 2 runs seed=7 identiques (349 observations)
  [OK ] 4. honnêteté du masque — wrapper jamais hors masque ; action forcée => ILLEGAL_ACTION
  [OK ] 5. formes fixes 2-6 joueurs — obs=(148,) mask=(165,) sur tables [2, 3, 4, 5, 6]
  [OK ] 6. robustesse process (kill + timeout) — kill => reset relance ; binaire muet => RunnerTimeout
=== TOUT VERT ===
```

État actuel :
- Runner VM recompilé et validé.
- Barrière Dart `flutter test test/rl/` : 15/15 vert (fait avant cette reprise).
- Barrière Python `rl/test_roundtrip.py` : 6/6 vert après recompilation.
- Aucun fichier source modifié pendant cette vérification ; seul `docs/ai/HANDOFF.md` a été mis à jour comme demandé.

Prochaine action recommandée :
- Passer à la phase 3 : écrire `rl/train_parallel.py` (`SubprocVecEnv` K=3, checkpoints, TensorBoard, stop-file/time-limit, sauvegarde `try/finally`) puis mesurer le FPS avant le long run.

### 2026-06-25 22:22 — Fix fuite mémoire GameLoggerService (headless)

Changement :
- Dans `tool/rl_env_runner.dart` : ajout de `GameLoggerService.instance.setEnabled(false)` en toute première ligne de `main()` + import du service.

Pourquoi :
- En mode headless RL, `startNewGame()`/`reset()` du logger ne sont jamais appelés, donc `_logBuffer` (StringBuffer) n'est jamais vidé et grossit indéfiniment au fil des tours → fuite mémoire sur les longs runs. Couper le logging à l'entrée neutralise toutes les écritures.

Vérification de l'API (sans rien inventer) :
- `GameLoggerService.instance` (singleton) et `setEnabled(bool)` existent (`lib/services/logging/game_logger_service.dart`). `_isEnabled` défaut `true`. Les 15 méthodes `logXxx` (dont `logTurnStart`, `logDraw`, `logDiscard`, `logMatch`, `logPowerUse`, `logDutch`, `logRoundEnd`, `logGameEnd`…) court-circuitent toutes sur `if (!_isEnabled) return;` avant tout `_logBuffer.write` → aucune accumulation une fois désactivé.

Fichiers / commandes concernés :
- Modifié : `tool/rl_env_runner.dart`.
- `dart compile exe tool/rl_env_runner.dart -o tool/rl_env_runner` (binaire gitignoré, recompilé localement).
- `flutter test test/rl/...` ; `rl/.venv/bin/python rl/test_roundtrip.py`.

Résultat obtenu :
- Recompilation OK, runner répond toujours au protocole NDJSON (reset).
- **15/15 tests Dart verts** (déterminisme, masque, anti-fuite, byte-parity 100 seeds, pouvoirs 7/10/V/Joker).
- **Roundtrip Python 6/6 vert** en local.

État actuel :
- Fix appliqué et validé en local. Commit/push **en attente de validation** (gate STOP).
- Règle confirmée : la VM ne fait qu'exécuter, jamais éditer le code source — tout fix se fait en local puis se propage par git.

Prochaine action recommandée :
- Après GO : commit + push sur `main` (seul le `.dart` source part ; binaire reste gitignoré). Puis resync VM via git + recompile.

### 2026-06-25 21:53 — Push du code RL sur GitHub (commit `ae0a120`)

Changement :
- Commit + push sur `origin/main` de tout le code RL phase 2 (16 fichiers, 2757 insertions).
- Le code RL est désormais sur le repo → la VM doit **cloner/`git pull`** au lieu de recevoir des fichiers par rsync.

Pourquoi :
- Centraliser la source de vérité sur GitHub pour Claude Code, Codex et la VM.

Fichiers / commandes concernés :
- `git add -A && git commit -F- && git push origin main`.
- Inclus : `tool/rl_env_runner.dart`, `lib/services/game/bot/headless_threat_signal.dart`, `rl/*.py` + `pyproject.toml`/`requirements.txt`/`.gitignore`, `test/rl/*`, `documentation/RL_RUNNER.md`, `docs/ai/HANDOFF.md`, `.gitignore`, `tool/ml_dataset_generator.dart` (2-6 joueurs).
- Exclus (artefacts) : `rl/.venv`, `rl/models`, `rl/runs`, `rl/__pycache__`, binaire `tool/rl_env_runner`.

Résultat obtenu :
- Push OK : `4458a90..ae0a120  main -> main`. Branche locale synchro avec `origin/main`.

État actuel :
- Code RL sur `https://github.com/fiftycommit/dutch` (commit `ae0a120`).
- La VM `rlDutch` a encore la version rsync ; à resynchroniser via git (cloner le repo ou pointer `~/dutch` sur le remote, puis recompiler le runner).
- Note : ce handoff a été ré-édité après le push (entrée ci-dessus) → la version sur le repo est celle d'`ae0a120` (état 21:18) ; la version disque locale est en avance jusqu'au prochain commit.

Prochaine action recommandée :
- Sur la VM : remplacer le `~/dutch` rsync par un clone git (ou ajouter le remote + reset), `flutter pub get`, recompiler `tool/rl_env_runner`, revérifier `rl/test_roundtrip.py`. Puis démarrer la phase 3 (entraînement parallélisé).

### 2026-06-25 21:18 — Préparation du push GitHub du code RL (gitignore)

Changement :
- Bascule du workflow VM : on passe du transfert manuel (rsync) au **clonage GitHub**. Le code RL va être poussé sur `fiftycommit/dutch`.
- Complété `rl/.gitignore` : ajout de `!requirements.txt` (négation) car `rl/requirements.txt` était avalé par la règle globale `*.txt` de la racine, alors qu'il doit être suivi.

Pourquoi :
- Centraliser le code sur le repo pour que la VM (et tout agent) clone au lieu de recevoir des fichiers à la main.

Fichiers / commandes concernés :
- Modifié : `rl/.gitignore`.
- Vérifs : `git ls-files --others --exclude-standard`, `git check-ignore`.

Résultat obtenu :
- Liste d'ajout propre (13 fichiers untracked + 2 modifiés), tous < 30 Ko. Artefacts lourds bien exclus : `rl/.venv` (505 Mo), `rl/models` (524 Ko), `rl/__pycache__`, binaire `tool/rl_env_runner`. `rl/requirements.txt` désormais inclus.

État actuel :
- Étape 1 (gitignore) terminée. Commit/push **en attente de validation** du `git status` par l'utilisateur (gate STOP).
- À flaguer : `tool/ml_dataset_generator.dart` est modifié (2-4 → 2-6 joueurs, indissociable du runner pour la byte-parity).

Prochaine action recommandée :
- Après GO : `git add` du périmètre validé, commit (message décrivant runner Dart + signal MORL + wrapper Python + tests), `git push`. Puis cloner le repo sur la VM.

### 2026-06-25 21:10 — Initialisation du handoff

Changement :
- Création de `docs/ai/HANDOFF.md` (+ dossier `docs/ai/`).
- Réconciliation du template initial avec l'état réel vérifié du repo et de l'infra (le template décrivait un état antérieur « SSH bloqué / env non installé »).

Pourquoi :
- Permettre à Claude Code et Codex de reprendre le contexte sans session partagée, avec des faits exacts.

Fichiers / commandes concernés :
- Créé : `docs/ai/HANDOFF.md`. Aucun fichier fonctionnel touché.
- Inspections lecture seule : `docs/`, `AGENTS.md`, `ml/models/`, `tool/ml_dataset_generator.dart`, `lib/services/game/engine_random.dart`, `dutch-server/src/services/QLearningService.ts`, `rl/`.

Résultat obtenu :
- Handoff créé, vérifié contre le repo réel (chemins confirmés, pas d'invention).

État actuel :
- VM Azure `rlDutch` (`20.91.236.73`, swedencentral, B4as_v2, 4 vCPU/15 Gio) créée et **accessible en SSH** via l'alias `dutch-rl-vm`.
- Environnement RL installé sur la VM (Flutter 3.44.4/Dart 3.12.2, uv/Python 3.12, deps RL), runner compilé, `rl/test_roundtrip.py` **6/6 vert**.
- Aucun code applicatif modifié.

Prochaine action recommandée :
- Démarrer la phase 3 (entraînement parallélisé) en suivant la section « Prochaine étape immédiate ».
