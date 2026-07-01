# Audit : bots existants comme behavior policy RL v2

Date : 2026-07-01
Agent : Claude Code
Statut : **AUDIT lecture seule — aucun code d'intégration, aucun changement fonctionnel.**

Objectif : déterminer si les bots existants peuvent servir de behavior policy plus
forte que `safe_heuristic` pour collecter des trajectoires R2D2 v2, **sans hidden
leak**. Ne pas accuser les bots : documenter techniquement.

---

## 1. Fichiers bots trouvés (rôles)

Cœur décision (`lib/services/game/bot/`) :
- `bot_ai_service_impl.dart` — implémente `IBotAIService` (orchestration d'un tour bot).
- `bot_card_strategy.dart` — **décision draw/replace/discard** + `tryReactionMatch` (match réaction).
- `bot_dutch_strategy.dart` — **décision `shouldCallDutch`** + estimation adverse.
- `bot_power_handler.dart` — **usage des pouvoirs** 7/10/Valet/Joker (`useBotSpecialPower`).
- `bot_memory_manager.dart` — mémoire propre (mentalMap, doublons, inconnues, decay).
- `bot_threat_analyzer.dart`, `human_threat_tracker.dart`, `discard_tracker.dart` — analyse **publique** (menace, défausses observées, styles adverses).
- `bot_personality.dart`, `bot_config.dart`, `bot_difficulty.dart`, `hardcore_*.dart`, `dutch_strategy_config.dart`, `duel_tuning.dart`, `moi_ml_profile.dart` — paramètres de comportement (skill/personality), pas d'état de jeu caché.
- `bot_fair_play_audit.dart` — **audit anti-triche runtime (`assert`)** déjà présent.
- `bot_power_notifications_stub.dart` / `_flutter.dart` — notifications pouvoir : **chemin headless (stub)** vs UI.
- `bot_simulator.dart` — simulateur Monte-Carlo. **Importé par personne** (`grep` repo-wide : self-only) → **code mort côté décision**, non utilisé en jeu.

Interface : `lib/core/interfaces/i_bot_ai_service.dart`.
Entrée dans le runner RL : `tool/rl_env_runner.dart::_playBotTurn` (voir §6).

## 2. Résumé de leur logique

Un tour bot (`_playBotTurn` / `bot_ai_service_impl`) enchaîne :
1. `BotDutchStrategy.shouldCallDutch(gs, bot, diff, phase)` → appeler Dutch ou non.
2. sinon `draw`, puis `BotCardStrategy.decideCardAction` → replace(idx) ou discard,
   avec règles par tier (bronze/silver/difficult/platine), doublons, tempo self-match,
   règle du 7/Valet, anti-humain, pression deck.
3. `BotPowerHandler.useBotSpecialPower` → 7 (look), 10 (spy), Valet (swap), Joker.
4. `BotCardStrategy.tryReactionMatch` → match pendant la fenêtre de réaction.

Toutes ces décisions s'appuient sur : **croyance de sa propre main** (`bot.mentalMap`,
`bot.knownCards`, `bot.getKnownScore()`, `getUnknownCardHintConfidence`), **mémoire
d'espionnage légale** (`bot.spyMemory` / `getSpiedCards`), **compteurs publics**
(`hand.length`, `gs.deck.length`, `discardPile`, top discard), **observations
publiques** (discardTracker : défausses observées, `memorizedCardIndices`, usages de
pouvoir, ciblages), **paramètres bot** et **RNG seedable** (`EngineRandom`).

## 3. Actions supportées

| action_v2 | supportée par le bot ? | source |
|---|---|---|
| `draw` | oui | `_playBotTurn` (draw implicite avant decideCardAction) |
| `call_dutch` | oui | `BotDutchStrategy.shouldCallDutch` |
| `post_draw_replace` / `post_draw_discard` | oui | `BotCardStrategy.decideCardAction` (`GameLogic.replaceCard`/`discardDrawnCard`) |
| `match` / `pass_tick` (réaction) | oui | `BotCardStrategy.tryReactionMatch` (`GameLogic.matchCard`) |
| `power_7_look` | oui | `BotPowerHandler` |
| `power_10_spy` | oui | `BotPowerHandler` |
| `jack_swap` (Valet) | oui | `BotPowerHandler` |
| `joker` | oui | `BotPowerHandler` |

→ Les bots couvrent **toutes** les `action_v2`, y compris Valet/Joker complets
(que `safe_heuristic` skippe). C'est le gain potentiel principal.

## 4. Champs lus par les bots

- Propres : `bot.hand.length`, `bot.mentalMap[i]` (croyance), `bot.knownCards[i]`,
  `bot.getKnownScore()`, `getUnknownCardHintConfidence(i)`, `bot.spyMemory` /
  `getSpiedCards(oppId)`, `consecutiveBadDraws`, `bronzeBlackout*`, `lastTargetedByPowerTurn`.
- Publics de table : `gs.drawnCard` (sa propre pioche), `gs.deck.length`,
  `gs.discardPile` (+ top), `gs.turnCount`, `gs.actionCount`, `gs.dutchCallerId`,
  `opponent.hand.length`, `opponent.memorizedCardIndices` (marqueurs publics),
  `opponent.lastTargetedByPowerTurn`, `opponent.isHuman`, `opponent.botBehavior`.
- Dérivés observés : `discardTracker` (moyennes/ratios de défausses, styles,
  estimations de main/score adverse **à partir d'observations publiques + spied**).
- Config : `BotDifficulty`, `BotPersonality`, tuning — non liés à l'état caché.
- **Un seul accès à une carte adverse réelle** : `bot_power_handler.dart:529`
  `final spiedCard = target.hand[idx];` — lu **après** `GameLogic.lookAtCard`, càd
  après avoir décidé et **exécuté** le spy (mécanique légale) ; le résultat va dans
  `spyMemory`. Le **choix** de l'index à espionner se fait via discardTracker /
  spyMemory / RNG, **avant** toute lecture de la carte.

## 5. Tableau OK / suspect / interdit

| Champ / accès | Classe | Justification |
|---|---|---|
| `mentalMap`, `knownCards`, `getKnownScore`, `getUnknownCardHintConfidence` | **A — OK** | croyance sur sa **propre** main (= `legal_private_memory.own_hand`) |
| `spyMemory` / `getSpiedCards` | **A — OK** | cartes adverses **légalement espionnées** (= `opponents.spied_slots`) |
| `top discard`, `deck.length`, `hand.length` adverse, `discardPile` | **A — OK** | faits publics (obs v2) |
| `discardTracker`, `memorizedCardIndices`, styles/estimations adverses | **A — OK** | dérivés d'**observations publiques**, pas de carte cachée |
| `gs.drawnCard` (propre) | **A — OK** | sa propre pioche (= `drawn_value/points`) |
| lecture d'une carte spied `target.hand[idx]` **après** `lookAtCard` | **A — OK** | exécution d'un pouvoir légal → `spyMemory` |
| réception de `GameState gs` complet (contient `players[*].hand` réelles, `deck`) | **B — suspect/acceptable** | l'objet complet est passé, mais **aucun champ caché n'est lu en décision** (vérifié §4 + audit §6) |
| `BotSimulator` (lit `deck.removeLast()`, hands réelles) | **B — acceptable** | **non utilisé** en décision (import self-only) ; à ne pas réveiller |
| `opponent.hand[i]` réel en décision | **C — interdit** | **aucune occurrence** hors spy-exécution et audit-masking |
| `deck_order`, `true_score`, `debug_eval_labels`, cartes inconnues | **C — interdit** | **aucune lecture** trouvée dans les décisions bot |

## 6. Compatibilité avec obs/action_v2

- **Headless confirmé** : `tool/rl_env_runner.dart::_playBotTurn` appelle déjà
  `shouldCallDutch` / `decideCardAction` / `useBotSpecialPower(_gs, diff, null, …)`
  / `tryReactionMatch` **avec `BuildContext = null`**. Le `BuildContext?` de
  l'interface est optionnel ; le chemin headless existe (`bot_power_notifications_stub`).
- **Le runner peut déjà faire jouer p0 par le bot** : `frozenBotMode` (drapeau
  **réservé aux tests de parité #5**) : `if (isRl && !frozenBotMode)` sinon
  `_playBotTurn(cur)`. Donc l'exécution bot-en-p0 headless **existe déjà**.
- **MAIS incompatibilité de sortie** : le bot **mute directement le GameState**
  (`GameLogic.replaceCard/discardDrawnCard/matchCard/lookAtCard`). Il **ne retourne
  pas** d'`action_v2`. La collecte R2D2 v2 est pilotée côté Python : Python choisit
  une entrée de `legal_action_v2.actions` et le runner l'applique. Pour utiliser le
  bot comme behavior policy, il faut **capturer** le coup exécuté par le bot et le
  **traduire** en `action_v2` correspondant à une entrée légale, puis le renvoyer à
  Python. C'est le vrai chantier (couche d'action, côté Dart runner).

## 7. Risques de hidden leak

- **Décisions : aucun leak réel trouvé.** Draw/replace/discard, match réaction,
  Dutch et sélection de cible des pouvoirs n'utilisent que croyance propre +
  spyMemory + publics + RNG.
- **Garde-fou déjà présent** : `BotFairPlayAudit.auditDutchDecisionBlindness`
  clone l'état, **masque les cartes adverses non-spied** et vérifie que la décision
  Dutch est **invariante** (assert debug). `auditKnowledgeState` vérifie la
  cohérence mentalMap/knownCards/spyMemory. Couvre Dutch (pas encore card/power/match).
- **Surface résiduelle** : les fonctions **reçoivent** le `GameState` complet
  (hands réelles + deck). Pas exploité aujourd'hui, mais une future modif pourrait
  introduire un leak silencieux → argument pour une **vue masquée** (défense en
  profondeur) si on branche les bots en collecte RL.

## 8. Difficulté d'intégration

- **Faible** côté « faire tourner le bot » : déjà headless dans le runner.
- **Moyenne** côté « couche d'action » : capturer le coup exécuté et le sérialiser
  en `action_v2` légal (draw/replace/discard/match/pass_tick/powers), y compris
  Valet/Joker complets. Nécessite du travail **Dart dans `tool/rl_env_runner.dart`**
  (nouveau mode « policy=bot » qui décide p0 via le bot et **retourne** l'action_v2
  jouée), + un flag Python `--policy existing_bot` côté `collect_rollouts_v2`.
- **Optionnelle** : vue GameState masquée pour p0 (défense en profondeur), et
  extension de `BotFairPlayAudit` aux décisions card/power/match.
- Contrainte dure : **ne pas casser la parité #5** (`frozenBotMode`) ni le chemin
  défaut du runner.

## 9. Comparaison avec safe_heuristic

| | safe_heuristic (baseline actuelle) | bots existants |
|---|---|---|
| Entrée | `obs_raw` légal uniquement | `GameState` complet (mais lit seulement le légal) |
| Sortie | **retourne** une `action_v2` légale | **mute** GameState, pas d'`action_v2` |
| Leak | **impossible par construction** | **aucun en pratique**, mais objet complet reçu |
| Valet/Joker | skip | **joués complètement** |
| Pouvoirs 7/10 | info basique | ciblage informé (discardTracker) |
| Dutch | prudent (main connue + score ≤ 8) | timing riche, estimation adverse |
| Diversité stratégique | faible (baseline) | **forte** (tiers, personnalités, anti-humain) |
| Intégration RL v2 | **déjà branché** (`--policy safe_heuristic`) | **à adapter** (couche d'action Dart) |

## 10. Recommandation finale

**Option C — les bots sont propres et headless, mais leur sortie n'est pas
`action_v2` : adapter uniquement la couche d'action, sans changer leur stratégie.**

Justification : aucun hidden leak réel en décision (§7), exécution headless déjà
en place (§6), audit fair-play existant. Le seul blocage est la traduction du coup
bot en `action_v2` légal dans le runner. Retenir aussi une **touche d'Option B** en
défense en profondeur : exposer au bot p0 une **vue masquée** du GameState et
étendre `BotFairPlayAudit` aux décisions card/power/match. **Pas** Option A (le
simple `--policy existing_bot` ne suffit pas, la sortie diffère). **Pas** Option D
(aucun leak avéré ; ne pas jeter les bots).

Ne pas intégrer maintenant : chantier séparé, avec plan court validé, tests de
parité intacts, et garde-fous anti-leak.

## 11. Prochain prompt proposé

> Chantier : brancher les bots existants comme behavior policy R2D2 v2 (Option C).
> 1. Dans `tool/rl_env_runner.dart`, ajouter un mode « policy=bot » pour le siège
>    p0 : faire décider le bot (réutiliser `_playBotTurn`/`tryReactionMatch` sans
>    changer la stratégie), **capturer** le coup exécuté et le **sérialiser en
>    `action_v2`** présent dans `legal_action_v2.actions` (draw/replace/discard/
>    match/pass_tick/power_7/power_10/jack_swap/joker). Renvoyer cette action_v2 au
>    protocole NDJSON pour que Python la journalise comme transition.
> 2. Défense en profondeur : exposer une **vue masquée** du GameState à p0 et
>    étendre `BotFairPlayAudit` aux décisions card/power/match.
> 3. Côté Python : `collect_rollouts_v2.py --policy existing_bot`, `random` et
>    `safe_heuristic` **strictement inchangés**.
> 4. Tests : parité #5 (`frozenBotMode`) intacte, `flutter test test/rl/`,
>    anti-leak (aucune clé cachée dans obs_raw), `test_roundtrip` 6/6.
> 5. Smoke 50 épisodes sous `/tmp`, comparer faux matchs / Dutch / wins / rang vs
>    `safe_heuristic` et random. Aucun training, aucun artefact committé.
