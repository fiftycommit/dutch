# Quick Start - Dutch Server

## Installation

```bash
cd /Users/maxmbey/projets/dutch/dutch-server
npm install
```

## Commandes Disponibles

### Compilation
```bash
npm run build
```
Compile TypeScript → JavaScript dans le dossier `dist/`

### Développement
```bash
npm run dev
```
Lance le serveur en mode développement avec rechargement automatique

### Production
```bash
npm start
```
Lance le serveur en mode production (nécessite un build préalable)

## Tests des Services de Jeu

### Test de Simulation
```bash
npm run build && node dist/services/example.js
```
Lance une simulation complète d'une partie avec 3 joueurs (1 humain, 2 bots)

### Test des Imports
```bash
npm run build && node dist/services/test-imports.js
```
Vérifie que tous les modules sont correctement importables

## Structure du Projet

```
dutch-server/
├── src/
│   ├── models/           # Modèles de données partagés
│   │   ├── Card.ts
│   │   ├── GameState.ts
│   │   ├── Player.ts
│   │   └── Room.ts
│   │
│   ├── services/         # Logique de jeu (NOUVEAU)
│   │   ├── GameLogic.ts      # Logique principale du jeu
│   │   ├── BotDifficulty.ts  # Configuration des bots
│   │   ├── BotAI.ts          # Intelligence artificielle
│   │   ├── example.ts        # Exemple d'utilisation
│   │   ├── test-imports.ts   # Tests de validation
│   │   ├── index.ts          # Exports centralisés
│   │   └── README.md         # Documentation détaillée
│   │
│   ├── handlers/         # Handlers Socket.IO
│   ├── utils/            # Utilitaires
│   └── index.ts          # Point d'entrée du serveur
│
├── dist/                 # Code compilé (généré)
├── node_modules/         # Dépendances (généré)
├── package.json
├── tsconfig.json
├── CHANGELOG.md          # Historique des changements
├── PORTING_SUMMARY.md    # Résumé du port Flutter → Node.js
└── QUICK_START.md        # Ce fichier
```

## Utilisation des Services dans votre Code

### Import Simple
```typescript
import { GameLogic, BotAI, BotDifficulty } from './services';
```

### Créer une Partie
```typescript
import { GameLogic } from './services';
import { createGameState, GameMode, Difficulty } from './models/GameState';
import { createPlayer, BotBehavior, BotSkillLevel } from './models/Player';

// Créer les joueurs
const players = [
  createPlayer('1', 'Alice', true, 0),
  createPlayer('2', 'Bot', false, 1, BotBehavior.balanced, BotSkillLevel.gold),
];

// Créer et initialiser le jeu
const gameState = createGameState(players, GameMode.quick, Difficulty.medium);
GameLogic.initializeGame(gameState);
```

### Jouer un Tour de Bot
```typescript
import { BotAI } from './services';

if (!gameState.currentPlayer.isHuman) {
  await BotAI.playBotTurn(gameState);
}
```

### Gérer les Réactions
```typescript
import { BotAI } from './services';
import { GamePhase } from './models/GameState';

if (gameState.phase === GamePhase.reaction) {
  for (const bot of gameState.players) {
    if (!bot.isHuman) {
      const matched = await BotAI.tryReactionMatch(gameState, bot);
      if (matched) break;
    }
  }
}
```

### Utiliser un Pouvoir Spécial
```typescript
import { BotAI } from './services';

if (gameState.isWaitingForSpecialPower && !gameState.currentPlayer.isHuman) {
  await BotAI.useBotSpecialPower(gameState);
}
```

## Intégration avec Socket.IO

### Exemple de Handler
```typescript
import { Server, Socket } from 'socket.io';
import { GameLogic, BotAI } from './services';

export function setupGameHandlers(io: Server, socket: Socket) {
  socket.on('game:draw', async (roomId: string) => {
    const room = rooms.get(roomId);
    if (!room) return;

    // Action du joueur
    GameLogic.drawCard(room.gameState);

    // Émettre l'update
    io.to(roomId).emit('game:update', room.gameState);

    // Si le joueur suivant est un bot
    GameLogic.nextPlayer(room.gameState);
    if (!room.gameState.currentPlayer.isHuman) {
      await BotAI.playBotTurn(room.gameState);
      io.to(roomId).emit('game:update', room.gameState);
    }
  });
}
```

## Gestion de la Mémoire

### Nettoyer la Mémoire d'un Bot
```typescript
import { BotAI } from './services';

// Quand un joueur quitte ou la partie se termine
BotAI.clearBotMemory(playerId);
```

### Nettoyer Toutes les Mémoires
```typescript
import { BotAI } from './services';

// Lors d'un reset complet du serveur
BotAI.clearAllBotMemories();
```

## Dépannage

### Erreur de Compilation
```bash
# Nettoyer et recompiler
rm -rf dist/
npm run build
```

### Erreur d'Import
Vérifiez que vous importez depuis le bon chemin :
```typescript
// ✓ Correct
import { GameLogic } from './services';

// ✗ Incorrect
import { GameLogic } from './services/GameLogic';
```

### Mémoire des Bots non Réinitialisée
```typescript
// Toujours nettoyer après une partie
BotAI.clearAllBotMemories();
```

## Documentation Complète

- **README des Services** : `src/services/README.md`
- **Résumé du Port** : `PORTING_SUMMARY.md`
- **Changelog** : `CHANGELOG.md`

## Support

Pour toute question ou problème, consultez d'abord la documentation dans :
1. `src/services/README.md` - Documentation détaillée des services
2. `PORTING_SUMMARY.md` - Détails techniques du port
3. `src/services/example.ts` - Exemple fonctionnel complet
