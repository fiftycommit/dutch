# Dutch RL — AI Handoff

Dernière mise à jour : 2026-06-26 01:20 (CEST, 23:20 UTC)
Agent ayant modifié ce fichier : Codex

> Ce fichier est la **source de vérité de continuité** entre Claude Code, Codex et tout autre agent IA travaillant sur la phase 2 RL de Dutch'78. Il doit rester exact et utilisable même si une session est interrompue brutalement.

---

## Résumé ultra-court

Le projet Dutch'78 entre en phase 2 RL. La phase 1 ML supervisée est terminée/frozen et ne doit pas être cassée. L'objectif actuel est de mettre en place une architecture PPO depuis zéro, avec intégration Dart ↔ Python, plusieurs agents différenciés par reward, et une VM Azure disponible pour les expérimentations.

**État au 2026-06-26 :** l'infrastructure RL est en place et validée. La VM Azure `rlDutch` est accessible en SSH, l'environnement (Flutter/Dart + Python/uv + deps RL) est installé dessus, le runner Dart est compilé avec le fix logger et la barrière de validation `rl/test_roundtrip.py` passe **6/6 sur la VM** après recompilation. `rl/train_parallel.py` est ajouté et validé en smoke (K=4, checkpoints, TensorBoard, sauvegarde finale). Le premier run réel 13 h est lancé dans tmux (`dutch_rl_train`) avec `--total-timesteps=57600000`, FPS observé ≈1230-1240 steps agent/s, logs dans `rl/runs/`.

---

## Objectif actuel

Mettre en place la phase 2 RL du projet Dutch'78.

Contraintes :
- RL depuis zéro (le siège RL n'hérite d'aucune heuristique de bot ; il ne connaît que les règles du jeu).
- PPO, pas Q-learning.
- Plusieurs agents avec rewards différenciées (objectif multi-objectif : gagner vite + déstabiliser l'humain).
- Architecture Dart ↔ Python décidée proprement (cf. section décisions).
- Préserver la phase 1 ML supervisée.
- Inspecter le vrai code avant toute modification.
- Ne pas inventer la structure du projet.
- Planifier avant de coder (mode plan + gates STOP explicites).

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

Module expérimental à NE PAS utiliser :
- `dutch-server/src/services/QLearningService.ts` (+ `NeuralNetworkService.ts`, `GeneticAlgorithmService.ts`) — module expérimental historique. Vérification prod du 2026-06-26 : ils ne sont **pas** exclus de compilation et ne sont **pas** dormants au sens strict ; ils sont compilés dans `dist/` et chargés au démarrage via `BotLearningService`. Les données runtime d'apprentissage restent en revanche purgées/vides et aucune trace récente d'entraînement effectif n'a été trouvée. Ne pas les réveiller ni s'en inspirer pour la phase 2 RL.

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
- **Observation** : `Box(148,)` taille fixe (agrégats adversaires, pas de slots bruts ; anti-fuite : n'expose que les croyances mentalMap/knownCards/spyMemory, jamais les vraies cartes non vues). MAX_HAND=13, MAX_OPP=5.
- **Action** : `Discrete(165)` masquée (MaskablePPO). Blocs contigus : call_dutch=0, continue_draw=1, discard_drawn=2, skip_power=3, replace 4-16, power7_look 17-29, power10_spy 30-94, powerV_swap 95-159, powerJoker 160-164. La réaction (D) est **exclue** en v1.
- **Reward multi-objectif (MORL)** : scalarisation préférence-conditionnée `w1·principal + w2·destab`, poids ~Dirichlet(1,1) par épisode, concaténés à l'observation. Objectif 1 = gagner vite (terminal, rang normalisé). Objectif 2 = déstabiliser un proxy-humain dynamique (signal dense ré-dérivé de `HumanThreatTracker`, règle de proxy stable : reward_destab=0 si le proxy change).
- **Algo** : `sb3-contrib` MaskablePPO (PPO masqué).
- **Nombre de joueurs** : 2 à 6 (aligné sur le vrai jeu / UI).
- **Déterminisme** : RNG seedable côté Dart (`engine_random.dart`), seeds incrémentaux par épisode côté Python.
- **Entraînement parallèle** : `SubprocVecEnv` **K=4** retenu pour le premier run sérieux après mesures empiriques sur la VM. Mesures longues 10k steps vectorisés sans updates PPO : K=3 ≈2222 FPS agent, RSS arbre ≈2074→2078 MB ; K=4 ≈2547 FPS agent, RSS arbre ≈2610→2615 MB. Nombre de descendants observé = `2*K + 2` (workers Python + runners Dart + processus support Python forkserver/resource_tracker), stable. Mesure de croisière avec entraînement PPO réel : **≈1230 FPS agent** ; utiliser ce chiffre, pas 2547, pour dimensionner `--total-timesteps`.
- **Hyperparamètres PPO v1** : `n_steps=512`, `batch_size=128`, `gamma=0.997`, `gae_lambda=0.95`, `learning_rate=3e-4`, `clip_range=0.2`, `ent_coef=0.01`, `vf_coef=0.5`, `max_grad_norm=0.5`, `n_epochs=10`, `target_kl=0.03`.

### Encore à décider / à faire
- Volume (`--total-timesteps`) du premier run sérieux multi-heures.
- Différenciation concrète des « agents » via le simplexe de poids (sélection, évaluation).
- Baselines d'évaluation (vs bots existants, vs aléatoire).
- Protocole de non-régression de la phase 1.

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
- `rl/runner_process.py` — pilote subprocess NDJSON.
- `rl/encoding.py` — tables action/observation/masque.
- `rl/dutch_env.py` — `gym.Env` mono-agent.
- `rl/train_ppo.py` — entraîneur smoke (plomberie).
- `rl/train_parallel.py` — entraîneur PPO parallèle (`SubprocVecEnv`, checkpoints, TensorBoard, sauvegarde `finally`, surveillance erreurs).
- `rl/test_roundtrip.py` — barrière de validation (6 checks).
- `rl/pyproject.toml`, `rl/uv.lock` — dépendances RL uv (inclut TensorBoard pour SB3).
- `test/rl/` — tests Dart de non-régression du runner (dont byte-parity avec le générateur).

À éviter :
- `dutch-server/src/services/QLearningService.ts` et apparentés : présents/chargés en prod mais sans données ni usage récent prouvé ; module expérimental à ne pas réutiliser pour la phase 2 RL.

> Ne pas supposer que cette liste est exhaustive. Inspecter le repo réel avant toute modification.

---

## Prochaine étape immédiate

L'accès SSH et le setup de l'environnement sont **faits et validés** (roundtrip 6/6 sur la VM). La suite (phase 3 — entraînement parallélisé) :

1. ✅ **Fait (VM, validé)** — fuite mémoire `_logBuffer` corrigée : `GameLoggerService.instance.setEnabled(false)` en tête du `main()` du runner, binaire recompilé sur la VM, `flutter test test/rl/` passé **15/15**, puis `rl/test_roundtrip.py` relancé après recompilation et passé **6/6**.
2. (Optionnel) Slim torch en CPU-only sur la VM (récupère ~3 Go).
3. ✅ **Fait (local/VM, validé)** — `DutchEnv.step()` gère désormais deux modes de défaillance sans casser `SubprocVecEnv` : process runner mort/timeout → épisode tronqué neutre ; erreur moteur `INTERNAL fatal:true` → log ERROR + épisode tronqué signalé.
4. ✅ **Fait (VM, validé)** — `rl/train_parallel.py` ajouté : `SubprocVecEnv` K=4 par défaut, `CheckpointCallback`, TensorBoard, callback de surveillance erreurs (`engine_internal_error` seuil 8), sauvegarde finale garantie en `finally`. Dépendance `tensorboard>=2.20.0` ajoutée via `uv add` + `rl/uv.lock`.
5. ✅ **Fait (VM, mesuré)** — FPS/mémoire parallèle mesurés pour K=3/K=4 ; K=4 retenu pour le premier run : ≈2547 FPS agent, RSS arbre ≈2.61 Go, stable sur 10k steps vectorisés.
6. ✅ **En cours (VM)** — run réel 13 h lancé dans tmux (`dutch_rl_train`) : `--total-timesteps=57600000`, K=4, checkpoints tous les 500k timesteps agent, logs/checkpoints sous `rl/runs/` et `rl/models/` (gitignorés).
7. **Prochaine action** — ne pas modifier le code pendant le run sauf incident. Attendre la fin du run (ou faire un check-in périodique), puis évaluer le modèle obtenu vs bots existants et vs aléatoire avant de concevoir les agents « moyen » et « facile ».

Ne pas modifier le code applicatif hors périmètre RL tant qu'un plan court n'est pas validé.

---

## Suivi sécurité (à traiter)

- Une inspection antérieure de la prod (`pm2 jlist`) a exposé `FIREBASE_SERVICE_ACCOUNT_JSON` (clé privée) et `FIREBASE_WEB_API_KEY` dans un transcript. **Rotation de la clé de service Firebase recommandée.**

---

## Journal des mises à jour

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
