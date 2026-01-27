# Services de Jeu Dutch - Documentation

Ce dossier contient la logique de jeu complète portée depuis le client Flutter vers le serveur Node.js.

## Fichiers

### GameLogic.ts
Contient toute la logique principale du jeu :
- Initialisation d'une partie
- Pioche et défausse de cartes
- Remplacement de cartes
- Match de cartes (réaction)
- Pouvoirs spéciaux (7, 10, Valet, Joker)
- Appel Dutch
- Gestion de la fin de partie

**Méthodes principales :**
- `initializeGame(gameState)` - Initialise une nouvelle partie
- `drawCard(gameState)` - Le joueur actuel pioche une carte
- `replaceCard(gameState, cardIndex)` - Remplace une carte de la main par la carte piochée
- `discardDrawnCard(gameState)` - Défausse la carte piochée
- `matchCard(gameState, player, cardIndex)` - Tente de matcher une carte pendant la phase de réaction
- `callDutch(gameState)` - Le joueur actuel appelle Dutch
- `lookAtCard(gameState, target, cardIndex)` - Regarde une carte (pouvoir 7 ou 10)
- `swapCards(gameState, p1, idx1, p2, idx2)` - Échange deux cartes (pouvoir Valet)
- `jokerEffect(gameState, targetPlayer)` - Mélange la main d'un joueur (pouvoir Joker)

### BotDifficulty.ts
Définit les niveaux de difficulté des bots avec leurs paramètres :
- **Bronze** : Niveau facile (oubli fréquent, faible précision)
- **Argent** : Niveau moyen
- **Or** : Niveau difficile (mémoire excellente, bonne stratégie)
- **Platine** : Niveau expert (mémoire parfaite, stratégie optimale)

**Paramètres :**
- `forgetChancePerTurn` : Probabilité d'oublier une carte connue par tour
- `confusionOnSwap` : Probabilité de confusion lors d'un échange
- `dutchThreshold` : Seuil de score pour appeler Dutch
- `reactionSpeed` : Vitesse de réaction (0-1)
- `matchAccuracy` : Précision pour matcher (0-1)
- `reactionMatchChance` : Probabilité de tenter un match en réaction
- `keepCardThreshold` : Seuil de points pour garder une carte piochée

**Méthodes :**
- `fromMMR(mmr)` - Obtient la difficulté selon le MMR du joueur
- `fromRank(rank)` - Obtient la difficulté selon le rang (string)

### BotAI.ts
Intelligence artificielle complète des bots avec 3 comportements différents :

**Comportements :**
- **Fast** : Joue rapidement, privilégie la vitesse sur la stratégie
- **Aggressive** : Cible le joueur humain, joue agressivement
- **Balanced** : Équilibré, stratégie adaptative selon la situation

**Phases de jeu du bot :**
- **Exploration** : Découvre ses cartes inconnues
- **Optimization** : Optimise son score en remplaçant les mauvaises cartes
- **Endgame** : Rush vers Dutch quand le score est bas

**Méthodes principales :**
- `playBotTurn(gameState, playerMMR?)` - Joue un tour complet pour un bot
- `tryReactionMatch(gameState, bot, playerMMR?)` - Tente de matcher pendant la phase de réaction
- `useBotSpecialPower(gameState, playerMMR?)` - Utilise un pouvoir spécial

**Gestion de la mémoire :**
La mémoire des bots (mentalMap, dutchHistory, consecutiveBadDraws) est stockée côté serveur dans une Map interne à BotAI. Les méthodes suivantes permettent de gérer cette mémoire :
- `clearBotMemory(playerId)` - Efface la mémoire d'un bot spécifique
- `clearAllBotMemories()` - Efface toutes les mémoires (utile lors d'un reset complet)

## Différences avec le client Flutter

### Adaptations TypeScript
1. **Random** : `Random()` de Dart → `Math.random()` de JavaScript
2. **Types** : Utilisation de TypeScript pour le typage fort
3. **Async/Await** : Les délais utilisent `Promise` au lieu de `Future`
4. **Enums** : Compatibles entre Dart et TypeScript

### Éléments non portés (spécifiques au client)
- Sons et vibrations (UI)
- Dialogs et notifications visuelles (UI)
- Provider/State management (remplacé par Socket.IO côté serveur)

### Mémoire des bots
Côté client Flutter, la mémoire des bots (mentalMap, dutchHistory, etc.) est stockée directement dans l'objet Player.

Côté serveur, pour des raisons de sérialisation et de séparation des responsabilités :
- Les interfaces `Player` et `GameState` ne contiennent que les données synchronisées
- La mémoire des bots est gérée dans une Map interne à `BotAI.ts`
- Cette approche permet de ne pas transmettre la mémoire secrète des bots aux clients

## Utilisation

```typescript
import { GameLogic, BotAI, BotDifficulty } from './services';
import { GameState, createGameState, GameMode } from './models/GameState';
import { Player, createPlayer, BotBehavior, BotSkillLevel } from './models/Player';
import { Difficulty } from './models/GameState';

// Créer des joueurs
const players = [
  createPlayer('1', 'Humain', true, 0),
  createPlayer('2', 'Bot 1', false, 1, BotBehavior.balanced, BotSkillLevel.gold),
  createPlayer('3', 'Bot 2', false, 2, BotBehavior.aggressive, BotSkillLevel.silver),
];

// Initialiser l'état du jeu
const gameState = createGameState(players, GameMode.quick, Difficulty.medium);

// Initialiser la partie
GameLogic.initializeGame(gameState);

// Tour d'un bot
if (!gameState.currentPlayer.isHuman) {
  await BotAI.playBotTurn(gameState);
}

// Gérer les réactions des bots
for (const bot of gameState.players) {
  if (!bot.isHuman) {
    const matched = await BotAI.tryReactionMatch(gameState, bot);
    if (matched) break;
  }
}

// Utiliser un pouvoir spécial
if (gameState.isWaitingForSpecialPower && !gameState.currentPlayer.isHuman) {
  await BotAI.useBotSpecialPower(gameState);
}
```

## Logique de jeu identique

La logique de jeu est **strictement identique** au client Flutter. Les algorithmes, seuils, probabilités et comportements des bots sont exactement les mêmes. Seule la syntaxe a été adaptée de Dart vers TypeScript.

Cela garantit que :
- Les parties multijoueur sont cohérentes entre clients et serveur
- Le comportement des bots est prévisible et testé
- Les règles du jeu sont appliquées de manière uniforme
