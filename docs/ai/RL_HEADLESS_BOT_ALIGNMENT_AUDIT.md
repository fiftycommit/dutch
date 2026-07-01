# Audit : alignement du runner headless avec la logique bot actuelle

Date : 2026-07-01
Agent : Claude Code
Statut : **AUDIT lecture seule — aucun changement fonctionnel.**

Objectif : avant d'envisager `--policy existing_bot`, vérifier que
`tool/rl_env_runner.dart::_playBotTurn` joue avec la **logique bot actuelle** (mêmes
services de stratégie que le vrai jeu), et non une ancienne approximation forkée.

Réponse courte : **le headless appelle les services de stratégie ACTUELS
(aucun fork de logique).** Il ré-orchestre le squelette de tour en **miroir
byte-exact du générateur** (`playOneGame`), lui-même « miroir headless de
`BotAI.playBotTurn` ». La seule divergence de comportement vs le vrai jeu est la
**couche gossip/alliance, volontairement omise** (+ logging/délais/asserts sans
effet logique). → **Option A avec une réserve documentée (gossip/alliance).**

---

## 1. Chemin d'appel bot NORMAL (vrai jeu)

`bot_orchestrator.dart` / `game_provider.dart` → `IBotAIService` (`BotAIServiceImpl`)
→ **`BotAI.playBotTurn`** (`lib/services/game/bot_ai.dart`) :

1. `BotConfig.getDifficulty(bot, playerMMR, hardcoreLevel, playerSkillEstimate)`
2. `BotConfig.getBotPhase` ; `BotPersonality.fromBot`
3. `GameLoggerService.logTurnStart` *(log)*
4. **`BotGossipService.instance.onBotTurn(bot, gs)`** *(alliance + speeches)*
5. `BotMemoryManager.applyMemoryDecay`
6. `BotFairPlayAudit.auditKnowledgeState('turn_start')` *(assert)*
7. délai de réflexion *(UI)*
8. `BotDutchStrategy.shouldCallDutch(...)` + `auditDutchDecisionBlindness` *(assert)*
9. si Dutch : **`BotGossipService.onBotCallsDutch`** + `GameLogic.callDutch` ; return
10. `GameLogic.drawCard`
11. délai post-draw *(UI)*
12. `BotCardStrategy.decideCardAction(...)` + `auditKnowledgeState('after_card_action')`

Réaction : `BotAI.tryReactionMatch` → `BotCardStrategy.tryReactionMatch` (encadré
d'asserts fair-play). Pouvoir : `BotAI.useBotSpecialPower` → garde `phase==specialPower
&& specialCardToActivate!=null` → `BotPowerHandler.useBotSpecialPower(gs, diff, context, personality)`.

## 2. Chemin d'appel bot HEADLESS (runner)

`tool/rl_env_runner.dart::_advanceToRlOrTerminal` → **`_playBotTurn(bot)`** (mirroir
de `playOneGame` du générateur) :

1. `BotConfig.getDifficulty(bot, null)`  *(pas de MMR/hardcore/skillEstimate)*
2. `BotConfig.getBotPhase` ; `BotPersonality.fromBot`
3. `BotMemoryManager.applyMemoryDecay`
4. `BotDutchStrategy.shouldCallDutch(...)` → si Dutch : `GameLogic.callDutch` ; return
5. `GameLogic.drawCard`
6. `BotCardStrategy.decideCardAction(...)`
7. si `phase==specialPower` : `BotPowerHandler.useBotSpecialPower(gs, diff, null, skipDelay:true)`
   puis reset manuel `phase=playing / isWaitingForSpecialPower=false / specialCardToActivate=null`.

Réaction : `_runBotReactionTick` → `BotCardStrategy.tryReactionMatch(gs, p, diff, phaseBot,
personality, skipDelay:true)` par bot, dans une fenêtre bornée par un **timer global
simulé** (30 ticks ~3 s). Pouvoirs de match pending résolus (7/10 puis Valet/Joker FIFO)
via `BotPowerHandler` — même logique bot.

**Générateur (référence de parité #5)** : `playOneGame` (`tool/ml_dataset_generator.dart`,
« miroir headless de `BotAI.playBotTurn` ») fait la **même** séquence (getDifficulty(bot,null)
→ applyMemoryDecay → shouldCallDutch → drawCard → decideCardAction → useBotSpecialPower →
tryReactionMatch). Le runner le reproduit **byte-à-byte** (test #5, 100 seeds).

## 3. Comparaison action par action (headless vs normal)

| Élément | Même service ? | Mêmes règles/effets ? | Divergence headless |
|---|---|---|---|
| `draw` | oui (`GameLogic.drawCard`) | oui | — |
| `post_draw_discard` / `post_draw_replace` | oui (`BotCardStrategy.decideCardAction`) | oui | — |
| `call_dutch` | oui (`BotDutchStrategy.shouldCallDutch` + `GameLogic.callDutch`) | oui | pas de `onBotCallsDutch` (gossip) |
| reaction `match` / `pass_tick` | oui (`BotCardStrategy.tryReactionMatch`) | oui | fenêtre pilotée par timer simulé (fidèle) ; `skipDelay:true` |
| `power_7_look` | oui (`BotPowerHandler`) | oui | `context:null` (UI only), `skipDelay:true` |
| `power_10_spy` | oui | oui | idem |
| `jack_swap` (Valet) | oui | oui | idem + **ciblage alliance inactif** (§4) |
| `joker` | oui | oui | idem + **ciblage alliance inactif** (§4) |
| memory updates (`mentalMap`/`knownCards`) | oui (via `GameLogic`/`decideCardAction`) | oui | p0 RL : decay **volontairement** non appliqué (siège RL) ; bots & p0-frozen : decay appliqué |
| `spyMemory` updates | oui (`BotPowerHandler`/`rememberSpiedCard`) | oui | — |
| `discardTracker` | oui (`BotDutchStrategy.discardTracker`) | oui | — |
| threat / `humanThreatTracker` | oui (`BotCardStrategy._buildTableConclusions`) | oui | — (pas d'humain en collecte RL → menace humaine ~inactive de toute façon) |
| personality / aiParameters | oui (`BotPersonality.fromBot`, `BotConfig`) | oui | MMR/hardcore/skillEstimate = null en headless |
| RNG seedable | oui (`EngineRandom`) | oui | re-seed identique (parité #5) |

## 4. Différences trouvées

1. **Gossip / alliance (seule divergence comportementale)** : le headless
   n'appelle **jamais** `BotGossipService.onBotTurn`/`onBotCallsDutch`. Impact :
   - speeches bot = UI pure → **aucun effet décision** ;
   - **alliance** : `bot_power_handler.dart:1817` lit
     `BotGossipService.instance.allianceTargetFor(bot.id, gs.turnCount)` pour
     prioriser une cible commune de pouvoir. Sans `onBotTurn`, aucune alliance
     n'est proposée/acceptée → `allianceTargetFor` renvoie toujours `null` →
     **branche inerte**. Les alliances ne se forment que contre un **leader
     humain** dangereux ; en collecte RL (adversaires bots, pas d'humain), elles
     ne se formeraient pas non plus dans le vrai jeu. **Divergence réelle mais
     pratiquement nulle pour la collecte bot-vs-bot.**
2. **logging / délais / asserts fair-play** omis en headless → **aucun effet
   logique** (délais = UI ; logs = observabilité ; asserts = debug only).
3. **`applyMemoryDecay` sur p0** non appliqué **en mode RL** (siège RL garde une
   mémoire fidèle) — **intentionnel**. En `frozenBotMode` (et pour un futur
   `existing_bot` jouant p0 via `_playBotTurn`), le decay **est** appliqué → un
   bot-en-p0 resterait fidèle.
4. **Paramètres difficulty** : headless passe `getDifficulty(bot, null)` (pas de
   MMR/hardcore/skillEstimate). Pour la collecte RL, la difficulté vient du skill
   propre du bot → acceptable ; à garder en tête si on veut le mode hardcore.

**Aucune logique de stratégie dupliquée ou forkée** : le runner appelle les classes
de service actuelles (`BotCardStrategy`, `BotDutchStrategy`, `BotPowerHandler`,
`BotMemoryManager`). `bot_simulator.dart` reste du code mort non utilisé.

## 5. Risques `context:null`

**Aucun.** Vérifié : `bot_power_handler.dart` n'a **aucune** garde `if (context ...)`
sur la logique de pouvoir. `context` (typé `Object?`) n'est passé qu'aux
notifications (`showBotSpyNotification`/`showBotSwapNotification`/…), appelées
seulement `if (target.isHuman)` et no-op en headless via
`bot_power_notifications_stub.dart` (import conditionnel). La logique métier est
séparée de l'UI ; le bot joue **exactement pareil** sans `BuildContext`.

## 6. Risques `frozenBotMode`

`frozenBotMode` **ne change pas la stratégie** : il fait seulement jouer le siège p0
par la **même** policy bot que les adversaires (via `_playBotTurn` + participation à
`_runFullBotReactionPass`), pour reproduire `playOneGame` byte-à-byte (parité #5).
Il ne désactive aucune action, ne fige pas l'aléatoire autrement que par le re-seed
`EngineRandom` normal. `main()` le force à `false` sur le chemin Python/PPO. → p0 en
`frozenBotMode` joue comme un **vrai bot**, pas une version simplifiée.

## 7. Tests existants

- `test/rl/rl_env_runner_test.dart` : **parité #5 byte-à-byte** runner frozen vs
  `playOneGame` (100 seeds : rangs, scores, dutchCaller) ; groupe 6 pouvoirs
  (7/10/Valet/Joker effet moteur) ; masques, réaction bornée + timer global,
  slot_stability, legal_private_memory anti-leak, `legal_action_v2`, épisodes random
  terminants, absence de leakage.
- `test/services/bot/*` : unités par stratégie (`bot_card_strategy`, `bot_dutch_strategy`,
  `bot_power_handler`, `bot_memory_manager`, `bot_threat_analyzer`, `bot_fair_play_audit`),
  `test/services/bot_ai_test.dart`, `test/providers/managers/bot_orchestrator_test.dart`.

## 8. Tests manquants

- ~~Aucun test n'assert que l'orchestration headless == `BotAI.playBotTurn`~~ →
  **AJOUTÉ** : `test/rl/headless_bot_orchestration_alignment_test.dart` compare
  `playOneGame` (générateur, byte-parity runner via #5) vs une partie complète
  pilotée par `BotAI.playBotTurn` (chemin de jeu normal) sur **100 seeds** :
  rangs / scores / dutchCaller **identiques**. Ferme la boucle
  « runner == générateur == BotAI ». **Vert.** Délais neutralisés par `fakeAsync`
  (aucun RNG), logger désactivé, gossip reset.
- Pas de test « bot-en-p0 via existing_bot » (n'existe pas encore).

### Décision gossip/alliance (actée)

`BotGossipService` (speeches + alliances) est **ignoré volontairement** en collecte
RL : (1) les speeches sont de l'UI pure (aucun effet décision) ; (2) l'alliance ne
se forme que contre un **leader humain** dangereux, or la collecte RL est
bot-vs-bot (pas d'humain) → aucune alliance ne se formerait même dans le vrai jeu ;
(3) `bot_power_handler.dart:1817` (`allianceTargetFor`) reste donc inerte. Le test
d'alignement le confirme (100 seeds identiques sans humain). Dans le test, gossip
est de plus `reset()` et n'utilise qu'un `Random` privé (pas `EngineRandom`), donc
sans effet sur le déterminisme. Si un jour un siège **humain** est simulé en
collecte, réévaluer (activer gossip côté headless ou le neutraliser explicitement).

## 9. Recommandation

**Option A (avec réserve documentée B sur gossip/alliance).**

Le headless utilise bien la **logique bot actuelle** (services identiques,
byte-parity avec le générateur miroir de `BotAI`). On peut donc envisager
`existing_bot` par **capture/traduction en `action_v2`** (cf.
`RL_EXISTING_BOTS_POLICY_AUDIT.md`, Option C). Réserve unique à trancher
explicitement, **pas un blocage** :

- **gossip/alliance omis** → ciblage de pouvoir par alliance inactif. Impact nul en
  collecte bot-vs-bot sans humain. Décider : (a) l'accepter tel quel pour la
  collecte RL, ou (b) ajouter un test de non-régression `playOneGame` vs
  `BotAI.playBotTurn` pour verrouiller l'alignement d'orchestration.

Non retenu : Option C (aucun fork de vieille logique), Option D (le headless
correspond bien au vrai jeu au niveau stratégie).

## 10. Prochain chantier proposé

1. (Optionnel, recommandé) **Test de non-régression d'orchestration** :
   `playOneGame` vs `BotAI.playBotTurn` sur N seeds (rangs/scores/dutchCaller), pour
   verrouiller que le headless ne dérive pas du chemin normal (gossip mis à part,
   documenté). Micro-test, aucun changement fonctionnel.
2. Décider explicitement le sort de **gossip/alliance** en collecte RL (accepter /
   activer derrière un flag).
3. Puis chantier `existing_bot` (Option C de l'audit précédent) : couche d'action
   `action_v2` dans le runner, `--policy existing_bot`, parité #5 intacte, anti-leak,
   smoke 50 ép. sous /tmp.
