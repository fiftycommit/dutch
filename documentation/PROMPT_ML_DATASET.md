# Mission — Générateur de dataset ML self-play pour Dutch'78

## Comment tu travailles (À LIRE EN PREMIER)

Tu travailles en **mode plan + validation par étapes**. Règles non négociables :

1. **Tu ne codes rien tant qu'une étape n'est pas explicitement validée par moi.**
2. À la fin de **chaque étape**, tu t'arrêtes, tu **expliques ce que tu as fait ou ce que tu comptes faire**, et tu attends mon **GO** avant de continuer.
3. Si tu hésites entre deux interprétations, tu **ne devines pas** : tu poses la question et tu attends.
4. Si tu découvres que le code réel contredit une instruction de ce document, tu **t'arrêtes et tu me le signales** — le code fait foi, pas mes suppositions.
5. Tu **cites toujours** le fichier et la ligne quand tu affirmes quelque chose sur le code (`fichier.dart:123`). Pas d'affirmation non sourcée.
6. Si une fonction que tu crois utiliser n'existe pas exactement comme tu l'imagines, tu **ne l'inventes pas** : tu la cherches, et si elle n'existe pas, tu me le dis.

Le but de ce mode : zéro hallucination, zéro dérive. On avance lentement et sûrement.

---

## Contexte du projet

Projet **Dutch'78** : jeu de cartes (variante Cabo) full-stack.
- App : **Flutter / Dart** (`lib/`) — c'est le moteur qui fait foi.
- Serveur : Node.js/TypeScript (`dutch-server/`) — reçoit/persiste seulement, ne génère pas de records.

On construit un **dataset de machine learning supervisé** : prédire, depuis un état de partie en cours, si un joueur va **gagner** (finir rang 1).

Ce document concerne **uniquement la phase 1 : la génération du dataset** (le pipeline Python viendra après, séparément). On génère via **self-play headless** en réutilisant le vrai moteur Dart.

Un plan d'implémentation a déjà été validé entre nous. Ce document le formalise pour que tu ne perdes pas le fil.

---

## ÉTAPE 0 — Inspection préalable (AUCUN code)

**Objectif : tout vérifier dans le code réel avant d'écrire quoi que ce soit. Tu lis, tu rapportes, tu attends mon GO.**

### 0.1 — Analyse exhaustive de `lib/models/player.dart`

Lis le fichier en entier et produis un **inventaire complet** :
- Tous les champs (nom, type, ligne) — en distinguant clairement ce qui est **vrai état** (`hand`) de ce qui est **croyance du bot** (`mentalMap`, `knownCards`, `spyMemory`).
- Toutes les méthodes publiques utiles au snapshot ML, avec signature + ligne + ce qu'elles retournent : au minimum `calculateScore`, `getKnownScore`, `knownCardCount`, `unknownCardCount`, `getMemoryConfidence`, `forgetCard`, `resetMentalMap`, `initializeBotMemory`, et toute méthode liée à la mémoire/croyance.
- Les champs `botBehavior`, `botSkillLevel`, `aiParameters` : type exact, valeurs possibles, d'où ils viennent.
- **Signale tout écart** entre ce que tu trouves et ce que ce document suppose.

### 0.2 — Analyse exhaustive de `lib/services/game/bot_ai.dart`

Lis le fichier en entier et produis :
- La séquence exacte d'un tour de bot dans `playBotTurn` (chaque appel, dans l'ordre, avec lignes).
- Tous les imports, en **identifiant lesquels tirent `dart:ui` / Flutter** (ex. `package:flutter/material.dart`) — c'est critique pour le headless.
- Pour chaque sous-appel (`BotConfig`, `BotDutchStrategy`, `BotCardStrategy`, `BotMemoryManager`, `BotPowerHandler`, `BotPersonality`, `BotFairPlayAudit`, `BotGossipService`), dis s'il est **headless-safe** (Dart pur) ou s'il a une dépendance UI, sourcé.
- Comment les **pouvoirs spéciaux** sont déclenchés et exécutés (le chemin `decideCardAction` → `_checkSpecialPower` → `useBotSpecialPower`), avec lignes.

### 0.3 — Synthèse

Après 0.1 et 0.2, donne-moi :
- Un tableau "ce que je vais lire pour chaque feature du snapshot" (feature → fonction source → fichier:ligne).
- La liste de **tout ce qui pourrait poser problème en headless** (imports UI, RNG non seedables, effets de bord).

**⛔ STOP. Tu présentes 0.1 + 0.2 + 0.3 et tu attends mon GO. Tu ne passes pas à l'étape 1 sans validation.**

---

## ÉTAPE 1 — Seeding déterministe (`EngineRandom`)

**Objectif : un `--seed` global qui rend toute la génération reproductible.**

### 1.1 — Plan d'abord
Avant de coder, liste **tous les `Random()` et `.shuffle()` du moteur** que la génération va toucher (fichier:ligne), et montre-moi la conversion prévue pour chacun. Tu as déjà identifié ~14 RNG indépendants + des shuffle inline — confirme la liste à jour depuis le code réel.

### 1.2 — Implémentation
- Crée `lib/services/game/engine_random.dart` :
  - `static Random _rng = Random();`
  - `static void seed(int s) { _rng = Random(s); }`
  - `static Random get instance => _rng;`
  - **Non seedé, le comportement doit être identique à aujourd'hui** (`Random()` normal) → zéro régression en prod.
- Convertis chaque RNG listé pour tirer de `EngineRandom.instance`. Édits mécaniques, 1 ligne chacun.
- Gère les `.shuffle()` en leur passant `EngineRandom.instance`.

### 1.3 — Caveats déterminisme
- `DateTime.now()` (timestamps, startTime/endTime) casse le déterminisme → prévois une **horloge virtuelle** (compteur monotone basé sur `actionCount`) pour le générateur. Les champs horaires bruts sont blocklistés côté features de toute façon.
- Note la **version du SDK Dart** dans le futur README (le déterminisme de `Random(seed)` en dépend).

### 1.4 — Non-régression
Lance `flutter analyze` puis `flutter test`. **Tout doit passer.** Montre-moi la sortie.

**⛔ STOP. Tu montres : la liste des RNG convertis, le code d'`EngineRandom`, et le résultat de `flutter analyze` + `flutter test`. Tu attends mon GO.**

---

## ÉTAPE 2 — Le générateur (`tool/ml_dataset_generator.dart`)

**Objectif : un générateur self-play headless FIDÈLE, isolé, qui écrit des `BotGameRecord` en JSON local.**

### Règles de fidélité (CRITIQUES)

1. **PAS de "final lap".** Dans Dutch'78, annoncer Dutch **termine la manche immédiatement** : tous révèlent, fin. Le `break` sur `dutchCalled` est **correct et fidèle**. ⚠️ **N'ajoute SURTOUT PAS de tour après l'annonce Dutch.** Ce serait une infidélité au jeu.

2. **Pouvoirs spéciaux : exécutés fidèlement.** Les 4 pouvoirs (7, 10, Valet, Joker) doivent produire leur **effet logique complet sur l'état** :
   - **7** : le bot regarde une de ses cartes → met à jour sa `mentalMap`.
   - **10** : le bot espionne une carte adverse → met à jour `spyMemory`.
   - **Valet** : échange une carte (bot↔adversaire ou adversaire↔adversaire) → mutation réelle des mains + mentalMap.
   - **Joker** : mélange la main d'un joueur ciblé → ce joueur oublie ses cartes (`mentalMap` → null).
   - Tu réutilises `BotPowerHandler.useBotSpecialPower(gs, difficulty, null, ...)` avec `context = null` et `skipDelay: true`. Tu as confirmé en étape 0 que c'est headless-safe (stub no-op + garde `if (target.isHuman)`).
   - **Si un pouvoir a une dépendance UI que tu ne peux pas contourner, tu t'ARRÊTES et tu me le dis. Tu ne sautes AUCUN pouvoir en silence.**

3. **Pas d'import qui tire `dart:ui`.** Tu n'importes **pas** `BotAI` (il importe `package:flutter/material.dart`). Tu reconstruis sa logique avec les modules purs (`BotConfig`, `BotDutchStrategy`, `BotCardStrategy`, `BotMemoryManager`) + `BotPowerHandler` (headless-safe). C'est ce que fait déjà le runner existant, plus les pouvoirs.

4. **Délais supprimés** : pas de `Future.delayed` de réflexion (inutile en génération, sans effet sur l'état).

### Boucle de partie (référence — à confirmer contre le code réel)

```
Par partie :
  - construire 2 à 4 Player bots (niveaux + personnalités variés, voir Étape 3)
  - GameLogic.initializeGame → phase = playing
  - startRecording par bot
  tant que phase ∉ {ended, dutchCalled} et guard < max :
      bot = currentPlayer
      difficulty = BotConfig.getDifficulty(bot, null)
      phase_bot = BotConfig.getBotPhase(bot, gs)
      perso = BotPersonality.fromBot(bot)
      ── SNAPSHOT ICI (AVANT toute action) : recordAction(bot, snapshot a/b/c)
      BotMemoryManager.applyMemoryDecay(bot, difficulty, personality: perso)
      si BotDutchStrategy.shouldCallDutch(...) :
          GameLogic.callDutch(gs) ; break          # ← PAS de final lap
      GameLogic.drawCard(gs)
      await BotCardStrategy.decideCardAction(gs, bot, difficulty, phase_bot, personality: perso)
      si gs.phase == specialPower :                 # ← pouvoirs fidèles
          await BotPowerHandler.useBotSpecialPower(gs, difficulty, null, personality: perso, skipDelay: true)
          gs.phase = playing ; gs.isWaitingForSpecialPower = false ; gs.specialCardToActivate = null
      updateLastActionResult(bot, {...})            # post-action, blocklisté côté ML
      ── phase de réaction : gs.phase = reaction ; pour chaque bot : BotCardStrategy.tryReactionMatch(...) ; gs.phase = playing
      si deck vide & discard ≤ 1 : break
      GameLogic.nextPlayer(gs)
  GameLogic.endGame(gs)
  ranks = gs.getFinalRanksWithTies()               # ← cible, fait foi
  pour chaque bot : endRecording(finalScore, finalRank = ranks[bot.id], won = ranks[bot.id]==1) → écrit JSON
```

⚠️ **Avant de coder cette boucle, vérifie chaque appel contre le code réel** (noms de méthodes, signatures, champs `GameState`). Si quelque chose diffère, signale-le.

### Recording : local, pas `BotLearningService`

- **N'utilise PAS** `BotLearningService.recordAction/endGameRecording` : son `endGameRecording` POST au serveur (interdit) et son `_captureGameState` est pauvre (9 champs).
- Le générateur embarque **son propre** `recordAction` / `updateLastActionResult` / `endRecording`, mais **réutilise les modèles** `BotAction` / `BotGameRecord` (`lib/models/bot_learning_data.dart`) pour la sérialisation (format compatible serveur plus tard).
- Sortie : `ml/data/raw/games/{gameId}_{botId}.json`.

### Schéma du snapshot (capturé AU DÉBUT du tour, avant action)

**(a) Public** : `turnCount`, `actionCount`, `phase`, `numberOfPlayers`, `relativePosition`, `deckSize`, `discardPileSize`, `topDiscardValue`, `topDiscardPoints`, `botHandSize`, `opponentsHandSizes`, `minOpponentHandSize`, `expectedDeckCardValue` (`getExpectedDeckCardValue`), résumé `discardedRanks` (`countDiscardedRanks`), `dutchCalledAlready`, `turnsSinceDutch`.

**(b) Croyance du bot — JAMAIS depuis `hand`** : `knownCardCount`, `unknownCardCount`, `memoryConfidence`, `believedKnownScore` (`getKnownScore`), `maxKnownCardValue`, `hasDoublon`/`doublonCount` (`findDoublons`), `expectedUnknownValueSum` (Σ `getUnknownBeliefExpectedValue`), `believedTotalScoreEstimate`, `spiedOpponentCardsCount` (`spyMemory`), `bestMatchProbability` (max `getMatchProbability`).

**(c) Perso/params** : `botBehavior`, `botSkillLevel`, `usedSBMM`, et `aiParams_*` (aggressiveness, caution, riskTolerance, dutchThreshold, memoryAccuracy, powerUsageRate, powerDefensiveRate, powerOffensiveRate, targetingStrategy).

**(d) Cible — fin de partie uniquement, JAMAIS dans un snapshot de feature** : `finalScore`, `finalRank` (`getFinalRanksWithTies`), `won` (= rank 1).

### 2.1 — Tu me présentes d'abord le plan détaillé du fichier (structure, fonctions, ordre), SANS coder. GO. Puis tu codes.

**⛔ STOP après le plan du fichier. Puis ⛔ STOP après le code, avant tout run.**

---

## ÉTAPE 3 — Diversité (sans réseau)

- **Personnalités synthétiques** : tire les `aiParameters` via `EngineRandom` dans des plages réalistes (documentées) :
  - aggressiveness, caution, riskTolerance ∈ [0.1, 0.9]
  - **dutchThreshold ∈ [4, 22]** ⚠️ `BotPersonality.fromBot` clampe à [5, 30] : **confirme-moi si [4,22] est respecté ou re-clampé à 5 en plancher**. Si écrasé, dis-le et propose (ajuster le clamp, ou vivre avec 5).
  - memoryAccuracy ∈ [0.4, 0.95], powerUsageRate ∈ [0.2, 0.9]
  - targetingStrategy ∈ {leader, weak, random}
- **Niveaux** : mix réparti ≈ uniforme de `BotSkillLevel` (bronze/silver/gold/platinum) sur les parties.
- **Nb joueurs** : tiré dans {2, 3, 4} par partie (seedé).

**⛔ STOP. Montre les plages implémentées + la réponse sur le clamp dutchThreshold. GO.**

---

## ÉTAPE 4 — Run de fumée (LE point de contrôle critique)

Lance **deux fois** : `dart run tool/ml_dataset_generator.dart --games=5 --seed=1`

Vérifie et montre-moi **les trois** :
1. **Déterminisme** : les deux runs produisent des JSON **byte-identiques** (features + cible). Si non → le seeding fuit, on corrige avant tout.
2. **`actions[]` non vides** : chaque record contient des snapshots (le bug historique du runner était `actions: []`).
3. **Traces de pouvoirs visibles** : sur certaines lignes, `spiedOpponentCardsCount > 0` (pouvoir 10), des `mentalMap` remises à zéro (Joker), des échanges (Valet). Preuve que les pouvoirs s'exécutent vraiment.

Montre-moi 1 ou 2 JSON d'exemple + la confirmation des 3 points.

**⛔ STOP. Si le run de fumée n'est pas propre sur les 3 points, on NE génère PAS. On débugge. GO seulement si tout est vert.**

---

## ÉTAPE 5 — Génération réelle

Seulement après un run de fumée validé :
`dart run tool/ml_dataset_generator.dart --games=3000 --seed=42 --out=ml/data/raw/games`

Montre-moi : nb de parties, nb de records, nb de lignes (snapshots) total, distribution de la cible `won` (équilibre des classes), distribution des niveaux. On vérifie ensemble que le dataset est sain avant le pipeline Python.

**⛔ STOP. On regarde les stats ensemble.**

---

## Anti-leakage (rappel permanent)

Une feature n'est valide **que si elle est calculable au moment de prédire pendant une vraie partie**, avec la seule info dont dispose le joueur.
- ❌ Jamais : `hand` (vraies cartes), résultat final, tours futurs.
- ✅ Toujours : `mentalMap`, `knownCards`, `spyMemory` au tour t ; infos publiques (défausse, deck size).
- **Blocklist** (jamais en feature) : finalScore, finalRank, won, wonDutch, cardsAtDutch, scoreAtDutch, goodDecisions, badDecisions, pBeatHuman, humanFinal*, endTime, totalTurns, avgDecisionTime, tout champ `result.*` des snapshots, toute clé dérivée de `hand`.

---

## Ce qui sera documenté plus tard dans `ml/README.md` (biais assumés)
- Données **bots-vs-bots** (le modèle apprend la dynamique des bots, pas des humains).
- Personnalités **synthétiques** locales (pas les profils serveur réels).
- Toute infidélité résiduelle au jeu réel.

---

## Hors-scope de ce document
Le pipeline Python (`1_load_data.py` → `5_predict.py`) et le RL (phase 2) sont des chantiers séparés. **Ne les commence pas ici.** Ce document s'arrête à un dataset généré et vérifié.
