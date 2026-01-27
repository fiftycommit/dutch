# Plan d'implémentation : Mode Multijoueur en ligne (Node.js + Socket.IO)

## Vue d'ensemble

Implémentation d'un système multijoueur en ligne robuste pour le jeu Dutch avec :
- Backend Node.js + Socket.IO (autorité serveur complète)
- Bots gérés côté serveur
- Système de rooms privées avec codes
- Support des modes Quick Game et Tournament
- Timer de réaction synchronisé par le serveur

## Architecture technique

### Stack technologique

**Backend**
- Node.js 18+ avec TypeScript
- Socket.IO 4.x pour communication temps réel
- Express.js pour API REST (matchmaking, stats)
- MongoDB ou PostgreSQL pour persistance (rooms actives, historique)
- Redis (optionnel) pour gestion des sessions

**Client Flutter**
- Package `socket_io_client` ^2.0.0
- Refactoring de GameProvider pour gérer état réseau
- Nouveau service `MultiplayerService` pour communication serveur

### Modèle de données réseau

**Room**
```typescript
interface Room {
  id: string;              // Code room (ex: "ABC123")
  hostPlayerId: string;
  settings: GameSettings;
  gameMode: 'quick' | 'tournament';
  players: Player[];       // Max 4 joueurs
  gameState: GameState | null;
  status: 'waiting' | 'playing' | 'ended';
  createdAt: Date;
  tournamentRound?: number;
}
```

**NetworkAction** (événements client → serveur)
```typescript
interface NetworkAction {
  type: 'DRAW_CARD' | 'REPLACE_CARD' | 'DISCARD_CARD' |
        'TAKE_FROM_DISCARD' | 'CALL_DUTCH' | 'ATTEMPT_MATCH' |
        'USE_SPECIAL_POWER' | 'COMPLETE_SWAP' | 'SKIP_SPECIAL_POWER';
  playerId: string;
  data?: any;              // Paramètres spécifiques (cardIndex, targetPlayerIndex, etc.)
  timestamp: number;
}
```

**GameStateUpdate** (événements serveur → clients)
```typescript
interface GameStateUpdate {
  type: 'FULL_STATE' | 'PARTIAL_UPDATE' | 'ACTION_RESULT' |
        'TIMER_UPDATE' | 'PHASE_CHANGE' | 'GAME_ENDED';
  gameState?: GameState;   // État complet ou partiel
  patch?: GameStatePatch;  // Changements incrémentiels
  reactionTimeRemaining?: number;
  error?: string;
}
```

## Phases d'implémentation

---

## Phase 1 : Sérialisation des modèles Flutter (Fondation)

### Fichiers à modifier

#### 1.1 `lib/models/card.dart`

Ajouter sérialisation JSON pour PlayingCard :

```dart
factory PlayingCard.fromJson(Map<String, dynamic> json) {
  return PlayingCard(
    suit: json['suit'] as String,
    value: json['value'] as String,
    points: json['points'] as int,
    isSpecial: json['isSpecial'] as bool,
    id: json['id'] as String,
  );
}

Map<String, dynamic> toJson() {
  return {
    'suit': suit,
    'value': value,
    'points': points,
    'isSpecial': isSpecial,
    'id': id,
  };
}
```

#### 1.2 `lib/models/player.dart`

Ajouter sérialisation JSON pour Player :

```dart
factory Player.fromJson(Map<String, dynamic> json) {
  return Player(
    id: json['id'] as String,
    name: json['name'] as String,
    isHuman: json['isHuman'] as bool,
    botBehavior: json['botBehavior'] != null
        ? BotBehavior.values[json['botBehavior'] as int]
        : null,
    botSkillLevel: json['botSkillLevel'] != null
        ? BotSkillLevel.values[json['botSkillLevel'] as int]
        : null,
    position: json['position'] as int? ?? 0,
  )
    ..hand = (json['hand'] as List?)
            ?.map((e) => PlayingCard.fromJson(e as Map<String, dynamic>))
            .toList() ??
        []
    ..knownCards = (json['knownCards'] as List?)?.cast<bool>() ?? [];
}

Map<String, dynamic> toJson() {
  return {
    'id': id,
    'name': name,
    'isHuman': isHuman,
    'botBehavior': botBehavior?.index,
    'botSkillLevel': botSkillLevel?.index,
    'position': position,
    'hand': hand.map((c) => c.toJson()).toList(),
    'knownCards': knownCards,
  };
}
```

**Note** : Ne pas sérialiser `mentalMap`, `dutchHistory`, `consecutiveBadDraws` (état local des bots géré serveur)

#### 1.3 `lib/models/game_state.dart`

Ajouter sérialisation complète de GameState :

```dart
factory GameState.fromJson(Map<String, dynamic> json) {
  return GameState(
    players: (json['players'] as List)
        .map((e) => Player.fromJson(e as Map<String, dynamic>))
        .toList(),
    deck: (json['deck'] as List)
        .map((e) => PlayingCard.fromJson(e as Map<String, dynamic>))
        .toList(),
    discardPile: (json['discardPile'] as List)
        .map((e) => PlayingCard.fromJson(e as Map<String, dynamic>))
        .toList(),
    currentPlayerIndex: json['currentPlayerIndex'] as int,
    gameMode: GameMode.values[json['gameMode'] as int],
    phase: GamePhase.values[json['phase'] as int],
    difficulty: Difficulty.values[json['difficulty'] as int],
  )
    ..drawnCard = json['drawnCard'] != null
        ? PlayingCard.fromJson(json['drawnCard'] as Map<String, dynamic>)
        : null
    ..dutchCallerId = json['dutchCallerId'] as String?
    ..isWaitingForSpecialPower = json['isWaitingForSpecialPower'] as bool? ?? false
    ..specialCardToActivate = json['specialCardToActivate'] != null
        ? PlayingCard.fromJson(json['specialCardToActivate'] as Map<String, dynamic>)
        : null
    ..reactionTimeRemaining = json['reactionTimeRemaining'] as int? ?? 0
    ..actionHistory = (json['actionHistory'] as List?)?.cast<String>() ?? []
    ..tournamentCumulativeScores =
        (json['tournamentCumulativeScores'] as Map?)?.cast<String, int>() ?? {}
    ..tournamentRound = json['tournamentRound'] as int? ?? 1
    ..lastSpiedCard = json['lastSpiedCard'] != null
        ? PlayingCard.fromJson(json['lastSpiedCard'] as Map<String, dynamic>)
        : null
    ..pendingSwap = json['pendingSwap'] != null
        ? Map<String, dynamic>.from(json['pendingSwap'] as Map)
        : null;
}

Map<String, dynamic> toJson() {
  return {
    'players': players.map((p) => p.toJson()).toList(),
    'deck': deck.map((c) => c.toJson()).toList(),
    'discardPile': discardPile.map((c) => c.toJson()).toList(),
    'currentPlayerIndex': currentPlayerIndex,
    'gameMode': gameMode.index,
    'phase': phase.index,
    'difficulty': difficulty.index,
    'drawnCard': drawnCard?.toJson(),
    'dutchCallerId': dutchCallerId,
    'isWaitingForSpecialPower': isWaitingForSpecialPower,
    'specialCardToActivate': specialCardToActivate?.toJson(),
    'reactionTimeRemaining': reactionTimeRemaining,
    'actionHistory': actionHistory,
    'tournamentCumulativeScores': tournamentCumulativeScores,
    'tournamentRound': tournamentRound,
    'lastSpiedCard': lastSpiedCard?.toJson(),
    'pendingSwap': pendingSwap,
  };
}
```

---

## Phase 2 : Backend Node.js + Socket.IO

### Structure du projet serveur

```
dutch-server/
├── src/
│   ├── index.ts                    # Point d'entrée
│   ├── server.ts                   # Configuration Express + Socket.IO
│   ├── models/
│   │   ├── Room.ts                 # Modèle Room
│   │   ├── GameState.ts            # GameState (port depuis Dart)
│   │   ├── Player.ts               # Player (port depuis Dart)
│   │   └── Card.ts                 # PlayingCard (port depuis Dart)
│   ├── services/
│   │   ├── RoomManager.ts          # Gestion des rooms
│   │   ├── GameLogic.ts            # Port de lib/services/game_logic.dart
│   │   ├── BotAI.ts                # Port de lib/services/bot_ai.dart
│   │   └── TimerManager.ts         # Gestion des timers de réaction
│   ├── handlers/
│   │   ├── connectionHandler.ts    # Connexion/déconnexion
│   │   ├── roomHandler.ts          # Création/join room
│   │   └── gameHandler.ts          # Actions de jeu
│   └── utils/
│       ├── logger.ts
│       └── validators.ts
├── package.json
├── tsconfig.json
└── .env
```

### Fichiers critiques du serveur

#### 2.1 `src/server.ts`

```typescript
import express from 'express';
import { createServer } from 'http';
import { Server } from 'socket.io';
import { RoomManager } from './services/RoomManager';
import { setupConnectionHandler } from './handlers/connectionHandler';
import { setupRoomHandler } from './handlers/roomHandler';
import { setupGameHandler } from './handlers/gameHandler';

const app = express();
const httpServer = createServer(app);
const io = new Server(httpServer, {
  cors: {
    origin: '*', // À restreindre en production
    methods: ['GET', 'POST'],
  },
  pingTimeout: 60000,
  pingInterval: 25000,
});

const roomManager = new RoomManager(io);

io.on('connection', (socket) => {
  console.log(`Client connected: ${socket.id}`);

  setupConnectionHandler(socket, roomManager);
  setupRoomHandler(socket, roomManager);
  setupGameHandler(socket, roomManager);
});

const PORT = process.env.PORT || 3000;
httpServer.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
```

#### 2.2 `src/services/RoomManager.ts`

```typescript
import { Server, Socket } from 'socket.io';
import { Room } from '../models/Room';
import { GameState } from '../models/GameState';
import { TimerManager } from './TimerManager';

export class RoomManager {
  private rooms: Map<string, Room> = new Map();
  private timerManager: TimerManager;

  constructor(private io: Server) {
    this.timerManager = new TimerManager(this);
  }

  // Générer code room unique (6 caractères)
  generateRoomCode(): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let code: string;
    do {
      code = Array.from({ length: 6 }, () =>
        chars.charAt(Math.floor(Math.random() * chars.length))
      ).join('');
    } while (this.rooms.has(code));
    return code;
  }

  // Créer room
  createRoom(hostSocketId: string, settings: any): Room {
    const code = this.generateRoomCode();
    const room: Room = {
      id: code,
      hostPlayerId: hostSocketId,
      settings,
      gameMode: settings.gameMode || 'quick',
      players: [],
      gameState: null,
      status: 'waiting',
      createdAt: new Date(),
    };
    this.rooms.set(code, room);
    return room;
  }

  // Joindre room
  joinRoom(roomCode: string, socket: Socket, playerName: string): Room | null {
    const room = this.rooms.get(roomCode);
    if (!room || room.status !== 'waiting' || room.players.length >= 4) {
      return null;
    }

    // Ajouter joueur
    const player = {
      id: socket.id,
      name: playerName,
      isHuman: true,
      hand: [],
      knownCards: [],
      position: room.players.length,
    };

    room.players.push(player);
    socket.join(roomCode);

    // Notifier tous les joueurs dans la room
    this.io.to(roomCode).emit('room:player_joined', {
      roomCode,
      player,
      playerCount: room.players.length,
    });

    return room;
  }

  // Démarrer partie
  startGame(roomCode: string): boolean {
    const room = this.rooms.get(roomCode);
    if (!room || room.players.length < 2) return false;

    // Ajouter bots si nécessaire (total 4 joueurs)
    while (room.players.length < 4) {
      room.players.push(this.createBot(room.players.length, room.settings));
    }

    // Initialiser GameState
    room.gameState = this.initializeGameState(room);
    room.status = 'playing';

    // Envoyer état initial à tous les joueurs
    this.broadcastGameState(roomCode, 'FULL_STATE');

    // Démarrer phase de réaction si nécessaire
    if (room.gameState.phase === 'reaction') {
      this.timerManager.startReactionTimer(roomCode, room.settings.reactionTimeMs);
    }

    return true;
  }

  // Créer bot
  private createBot(position: number, settings: any): any {
    const botNames = ['Alice', 'Bob', 'Charlie', 'Diana'];
    return {
      id: `bot_${position}`,
      name: botNames[position] || `Bot ${position}`,
      isHuman: false,
      botBehavior: 'balanced',
      botSkillLevel: settings.botDifficulty || 'silver',
      hand: [],
      knownCards: [],
      position,
    };
  }

  // Initialiser GameState (port de GameLogic.initializeGame)
  private initializeGameState(room: Room): GameState {
    // TODO: Porter la logique de lib/services/game_logic.dart
    // Créer deck, mélanger, distribuer cartes, etc.
    return {
      players: room.players,
      deck: [],
      discardPile: [],
      currentPlayerIndex: 0,
      gameMode: room.gameMode,
      phase: 'playing',
      difficulty: room.settings.botDifficulty,
      // ... autres champs
    };
  }

  // Broadcast état du jeu
  broadcastGameState(roomCode: string, updateType: string, data?: any) {
    const room = this.rooms.get(roomCode);
    if (!room || !room.gameState) return;

    // Pour chaque joueur, envoyer sa vue personnalisée
    room.players.forEach((player) => {
      const personalizedState = this.getPersonalizedState(room.gameState!, player.id);
      this.io.to(player.id).emit('game:state_update', {
        type: updateType,
        gameState: personalizedState,
        ...data,
      });
    });
  }

  // État personnalisé (masquer cartes adversaires)
  private getPersonalizedState(gameState: GameState, playerId: string): GameState {
    const state = { ...gameState };

    state.players = state.players.map((player) => {
      if (player.id === playerId) {
        return player; // Cartes visibles
      } else {
        // Masquer les cartes des adversaires
        return {
          ...player,
          hand: player.hand.map(() => ({ hidden: true })),
        };
      }
    });

    // Masquer le deck
    state.deck = state.deck.map(() => ({ hidden: true }));

    return state;
  }

  // Traiter action joueur
  async handlePlayerAction(roomCode: string, action: any): Promise<boolean> {
    const room = this.rooms.get(roomCode);
    if (!room || !room.gameState) return false;

    // Valider que c'est le tour du joueur
    const currentPlayer = room.gameState.players[room.gameState.currentPlayerIndex];
    if (currentPlayer.id !== action.playerId && room.gameState.phase !== 'reaction') {
      return false;
    }

    // Appliquer l'action via GameLogic (porté)
    // TODO: Porter toutes les actions de lib/services/game_logic.dart

    // Si c'est un bot qui doit jouer ensuite, le faire jouer
    await this.checkAndPlayBotTurn(roomCode);

    // Broadcast nouvel état
    this.broadcastGameState(roomCode, 'ACTION_RESULT', { action });

    return true;
  }

  // Boucle de jeu des bots
  private async checkAndPlayBotTurn(roomCode: string) {
    const room = this.rooms.get(roomCode);
    if (!room || !room.gameState) return;

    while (
      room.gameState.phase === 'playing' &&
      !room.gameState.players[room.gameState.currentPlayerIndex].isHuman
    ) {
      // Délai pour simuler réflexion
      await this.delay(800);

      // TODO: Porter BotAI.playBotTurn()
      // await BotAI.playBotTurn(room.gameState);

      // Broadcast changement
      this.broadcastGameState(roomCode, 'PARTIAL_UPDATE');

      // Démarrer phase réaction
      if (room.gameState.phase === 'playing') {
        room.gameState.phase = 'reaction';
        this.timerManager.startReactionTimer(roomCode, room.settings.reactionTimeMs);
        break;
      }
    }
  }

  private delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  getRoom(roomCode: string): Room | undefined {
    return this.rooms.get(roomCode);
  }

  deleteRoom(roomCode: string) {
    this.timerManager.clearTimer(roomCode);
    this.rooms.delete(roomCode);
  }
}
```

#### 2.3 `src/services/TimerManager.ts`

```typescript
import { RoomManager } from './RoomManager';

export class TimerManager {
  private timers: Map<string, NodeJS.Timer> = new Map();

  constructor(private roomManager: RoomManager) {}

  startReactionTimer(roomCode: string, durationMs: number) {
    this.clearTimer(roomCode);

    const room = this.roomManager.getRoom(roomCode);
    if (!room || !room.gameState) return;

    room.gameState.reactionTimeRemaining = durationMs;

    const timer = setInterval(() => {
      if (!room || !room.gameState) {
        this.clearTimer(roomCode);
        return;
      }

      room.gameState.reactionTimeRemaining -= 50;

      // Broadcast temps restant (toutes les 200ms pour économiser bande passante)
      if (room.gameState.reactionTimeRemaining % 200 === 0) {
        this.roomManager.broadcastGameState(roomCode, 'TIMER_UPDATE', {
          reactionTimeRemaining: room.gameState.reactionTimeRemaining,
        });
      }

      if (room.gameState.reactionTimeRemaining <= 0) {
        this.endReactionPhase(roomCode);
      }
    }, 50);

    this.timers.set(roomCode, timer);
  }

  private async endReactionPhase(roomCode: string) {
    this.clearTimer(roomCode);

    const room = this.roomManager.getRoom(roomCode);
    if (!room || !room.gameState) return;

    // Passer au joueur suivant
    room.gameState.phase = 'playing';
    room.gameState.lastSpiedCard = null;

    // TODO: Porter GameLogic.nextPlayer()
    room.gameState.currentPlayerIndex =
      (room.gameState.currentPlayerIndex + 1) % room.gameState.players.length;

    this.roomManager.broadcastGameState(roomCode, 'PHASE_CHANGE');

    // Si bot, le faire jouer
    // await this.roomManager.checkAndPlayBotTurn(roomCode);
  }

  clearTimer(roomCode: string) {
    const timer = this.timers.get(roomCode);
    if (timer) {
      clearInterval(timer);
      this.timers.delete(roomCode);
    }
  }
}
```

#### 2.4 `src/handlers/gameHandler.ts`

```typescript
import { Socket } from 'socket.io';
import { RoomManager } from '../services/RoomManager';

export function setupGameHandler(socket: Socket, roomManager: RoomManager) {
  // Pioche
  socket.on('game:draw_card', async (data) => {
    const { roomCode } = data;
    await roomManager.handlePlayerAction(roomCode, {
      type: 'DRAW_CARD',
      playerId: socket.id,
    });
  });

  // Remplacer carte
  socket.on('game:replace_card', async (data) => {
    const { roomCode, cardIndex } = data;
    await roomManager.handlePlayerAction(roomCode, {
      type: 'REPLACE_CARD',
      playerId: socket.id,
      data: { cardIndex },
    });
  });

  // Rejeter carte piochée
  socket.on('game:discard_card', async (data) => {
    const { roomCode } = data;
    await roomManager.handlePlayerAction(roomCode, {
      type: 'DISCARD_CARD',
      playerId: socket.id,
    });
  });

  // Prendre de la défausse
  socket.on('game:take_from_discard', async (data) => {
    const { roomCode } = data;
    await roomManager.handlePlayerAction(roomCode, {
      type: 'TAKE_FROM_DISCARD',
      playerId: socket.id,
    });
  });

  // Appeler Dutch
  socket.on('game:call_dutch', async (data) => {
    const { roomCode } = data;
    await roomManager.handlePlayerAction(roomCode, {
      type: 'CALL_DUTCH',
      playerId: socket.id,
    });
  });

  // Tenter match (phase réaction)
  socket.on('game:attempt_match', async (data) => {
    const { roomCode, cardIndex } = data;
    await roomManager.handlePlayerAction(roomCode, {
      type: 'ATTEMPT_MATCH',
      playerId: socket.id,
      data: { cardIndex },
    });
  });

  // Utiliser pouvoir spécial
  socket.on('game:use_special_power', async (data) => {
    const { roomCode, targetPlayerIndex, targetCardIndex } = data;
    await roomManager.handlePlayerAction(roomCode, {
      type: 'USE_SPECIAL_POWER',
      playerId: socket.id,
      data: { targetPlayerIndex, targetCardIndex },
    });
  });

  // Compléter échange (Valet)
  socket.on('game:complete_swap', async (data) => {
    const { roomCode, ownCardIndex } = data;
    await roomManager.handlePlayerAction(roomCode, {
      type: 'COMPLETE_SWAP',
      playerId: socket.id,
      data: { ownCardIndex },
    });
  });

  // Ignorer pouvoir spécial
  socket.on('game:skip_special_power', async (data) => {
    const { roomCode } = data;
    await roomManager.handlePlayerAction(roomCode, {
      type: 'SKIP_SPECIAL_POWER',
      playerId: socket.id,
    });
  });
}
```

#### 2.5 `src/handlers/roomHandler.ts`

```typescript
import { Socket } from 'socket.io';
import { RoomManager } from '../services/RoomManager';

export function setupRoomHandler(socket: Socket, roomManager: RoomManager) {
  // Créer room
  socket.on('room:create', (data, callback) => {
    try {
      const room = roomManager.createRoom(socket.id, data.settings);

      // Ajouter l'hôte comme premier joueur
      const hostPlayer = {
        id: socket.id,
        name: data.playerName || 'Hôte',
        isHuman: true,
        hand: [],
        knownCards: [],
        position: 0,
      };
      room.players.push(hostPlayer);
      socket.join(room.id);

      callback({ success: true, roomCode: room.id, room });
    } catch (error) {
      callback({ success: false, error: error.message });
    }
  });

  // Rejoindre room
  socket.on('room:join', (data, callback) => {
    try {
      const room = roomManager.joinRoom(data.roomCode, socket, data.playerName);

      if (!room) {
        callback({ success: false, error: 'Room introuvable ou pleine' });
        return;
      }

      callback({ success: true, room });
    } catch (error) {
      callback({ success: false, error: error.message });
    }
  });

  // Démarrer partie
  socket.on('room:start_game', (data, callback) => {
    try {
      const room = roomManager.getRoom(data.roomCode);

      if (!room) {
        callback({ success: false, error: 'Room introuvable' });
        return;
      }

      if (room.hostPlayerId !== socket.id) {
        callback({ success: false, error: 'Seul l\'hôte peut démarrer' });
        return;
      }

      const started = roomManager.startGame(data.roomCode);
      callback({ success: started });
    } catch (error) {
      callback({ success: false, error: error.message });
    }
  });

  // Quitter room
  socket.on('room:leave', (data) => {
    const { roomCode } = data;
    socket.leave(roomCode);

    // TODO: Gérer déconnexion mid-game
  });
}
```

---

## Phase 3 : Client Flutter - MultiplayerService

### Fichiers à créer/modifier

#### 3.1 `lib/services/multiplayer_service.dart` (NOUVEAU)

```dart
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/game_state.dart';
import '../models/game_settings.dart';

class MultiplayerService {
  static const String _serverUrl = 'http://localhost:3000'; // À configurer

  IO.Socket? _socket;
  String? _currentRoomCode;
  String? _playerId;

  bool get isConnected => _socket?.connected ?? false;
  String? get currentRoomCode => _currentRoomCode;

  // Callbacks
  Function(GameState)? onGameStateUpdate;
  Function(String)? onError;
  Function(Map<String, dynamic>)? onPlayerJoined;
  Function(int)? onTimerUpdate;

  // Connexion au serveur
  Future<void> connect() async {
    _socket = IO.io(_serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    _setupEventListeners();
    _socket!.connect();

    await Future.delayed(const Duration(seconds: 1));

    if (!isConnected) {
      throw Exception('Impossible de se connecter au serveur');
    }

    _playerId = _socket!.id;
  }

  // Écoute des événements
  void _setupEventListeners() {
    _socket!.on('connect', (_) {
      print('Connecté au serveur');
      _playerId = _socket!.id;
    });

    _socket!.on('disconnect', (_) {
      print('Déconnecté du serveur');
    });

    _socket!.on('game:state_update', (data) {
      final updateType = data['type'] as String;
      final gameStateJson = data['gameState'] as Map<String, dynamic>?;

      if (gameStateJson != null) {
        final gameState = GameState.fromJson(gameStateJson);
        onGameStateUpdate?.call(gameState);
      }

      if (updateType == 'TIMER_UPDATE') {
        final remaining = data['reactionTimeRemaining'] as int?;
        if (remaining != null) {
          onTimerUpdate?.call(remaining);
        }
      }
    });

    _socket!.on('room:player_joined', (data) {
      onPlayerJoined?.call(data);
    });

    _socket!.on('error', (error) {
      onError?.call(error.toString());
    });
  }

  // Créer room
  Future<String?> createRoom({
    required GameSettings settings,
    required String playerName,
  }) async {
    if (!isConnected) await connect();

    final completer = Completer<String?>();

    _socket!.emitWithAck('room:create', {
      'settings': settings.toJson(),
      'playerName': playerName,
    }, ack: (response) {
      if (response['success'] == true) {
        _currentRoomCode = response['roomCode'];
        completer.complete(response['roomCode']);
      } else {
        completer.completeError(response['error'] ?? 'Erreur inconnue');
      }
    });

    return completer.future;
  }

  // Rejoindre room
  Future<bool> joinRoom({
    required String roomCode,
    required String playerName,
  }) async {
    if (!isConnected) await connect();

    final completer = Completer<bool>();

    _socket!.emitWithAck('room:join', {
      'roomCode': roomCode,
      'playerName': playerName,
    }, ack: (response) {
      if (response['success'] == true) {
        _currentRoomCode = roomCode;
        completer.complete(true);
      } else {
        completer.completeError(response['error'] ?? 'Erreur inconnue');
      }
    });

    return completer.future;
  }

  // Démarrer partie
  Future<bool> startGame() async {
    if (_currentRoomCode == null) return false;

    final completer = Completer<bool>();

    _socket!.emitWithAck('room:start_game', {
      'roomCode': _currentRoomCode,
    }, ack: (response) {
      completer.complete(response['success'] == true);
    });

    return completer.future;
  }

  // Actions de jeu
  void drawCard() {
    _socket!.emit('game:draw_card', {'roomCode': _currentRoomCode});
  }

  void replaceCard(int cardIndex) {
    _socket!.emit('game:replace_card', {
      'roomCode': _currentRoomCode,
      'cardIndex': cardIndex,
    });
  }

  void discardDrawnCard() {
    _socket!.emit('game:discard_card', {'roomCode': _currentRoomCode});
  }

  void takeFromDiscard() {
    _socket!.emit('game:take_from_discard', {'roomCode': _currentRoomCode});
  }

  void callDutch() {
    _socket!.emit('game:call_dutch', {'roomCode': _currentRoomCode});
  }

  void attemptMatch(int cardIndex) {
    _socket!.emit('game:attempt_match', {
      'roomCode': _currentRoomCode,
      'cardIndex': cardIndex,
    });
  }

  void useSpecialPower(int targetPlayerIndex, int targetCardIndex) {
    _socket!.emit('game:use_special_power', {
      'roomCode': _currentRoomCode,
      'targetPlayerIndex': targetPlayerIndex,
      'targetCardIndex': targetCardIndex,
    });
  }

  void completeSwap(int ownCardIndex) {
    _socket!.emit('game:complete_swap', {
      'roomCode': _currentRoomCode,
      'ownCardIndex': ownCardIndex,
    });
  }

  void skipSpecialPower() {
    _socket!.emit('game:skip_special_power', {'roomCode': _currentRoomCode});
  }

  // Quitter room
  void leaveRoom() {
    if (_currentRoomCode != null) {
      _socket!.emit('room:leave', {'roomCode': _currentRoomCode});
      _currentRoomCode = null;
    }
  }

  // Déconnexion
  void disconnect() {
    leaveRoom();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _playerId = null;
  }
}
```

#### 3.2 `lib/providers/multiplayer_game_provider.dart` (NOUVEAU)

Nouveau provider qui étend GameProvider mais utilise MultiplayerService :

```dart
import 'package:flutter/foundation.dart';
import '../models/game_state.dart';
import '../services/multiplayer_service.dart';

class MultiplayerGameProvider with ChangeNotifier {
  final MultiplayerService _multiplayerService = MultiplayerService();

  GameState? _gameState;
  GameState? get gameState => _gameState;

  String? _roomCode;
  String? get roomCode => _roomCode;

  bool _isHost = false;
  bool get isHost => _isHost;

  List<String> _playersInLobby = [];
  List<String> get playersInLobby => _playersInLobby;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  MultiplayerGameProvider() {
    _multiplayerService.onGameStateUpdate = (gameState) {
      _gameState = gameState;
      notifyListeners();
    };

    _multiplayerService.onTimerUpdate = (remaining) {
      if (_gameState != null) {
        _gameState!.reactionTimeRemaining = remaining;
        notifyListeners();
      }
    };

    _multiplayerService.onPlayerJoined = (data) {
      // Mettre à jour la liste des joueurs dans le lobby
      notifyListeners();
    };

    _multiplayerService.onError = (error) {
      _errorMessage = error;
      notifyListeners();
    };
  }

  Future<void> createRoom({
    required GameSettings settings,
    required String playerName,
  }) async {
    try {
      _roomCode = await _multiplayerService.createRoom(
        settings: settings,
        playerName: playerName,
      );
      _isHost = true;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> joinRoom({
    required String roomCode,
    required String playerName,
  }) async {
    try {
      await _multiplayerService.joinRoom(
        roomCode: roomCode,
        playerName: playerName,
      );
      _roomCode = roomCode;
      _isHost = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> startGame() async {
    if (!_isHost) return;

    try {
      await _multiplayerService.startGame();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  // Déléguer toutes les actions au service
  void drawCard() => _multiplayerService.drawCard();
  void replaceCard(int cardIndex) => _multiplayerService.replaceCard(cardIndex);
  void discardDrawnCard() => _multiplayerService.discardDrawnCard();
  void takeFromDiscard() => _multiplayerService.takeFromDiscard();
  void callDutch() => _multiplayerService.callDutch();
  void attemptMatch(int cardIndex) => _multiplayerService.attemptMatch(cardIndex);

  void useSpecialPower(int targetPlayerIndex, int targetCardIndex) {
    _multiplayerService.useSpecialPower(targetPlayerIndex, targetCardIndex);
  }

  void completeSwap(int ownCardIndex) {
    _multiplayerService.completeSwap(ownCardIndex);
  }

  void skipSpecialPower() => _multiplayerService.skipSpecialPower();

  void leaveRoom() {
    _multiplayerService.leaveRoom();
    _roomCode = null;
    _gameState = null;
    _isHost = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _multiplayerService.disconnect();
    super.dispose();
  }
}
```

---

## Phase 4 : UI Multijoueur (Flutter)

### Fichiers à créer

#### 4.1 `lib/screens/multiplayer_menu_screen.dart` (NOUVEAU)

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/multiplayer_game_provider.dart';
import 'multiplayer_lobby_screen.dart';

class MultiplayerMenuScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Multijoueur en ligne')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => _createRoom(context),
              child: Text('Créer une partie'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _joinRoom(context),
              child: Text('Rejoindre une partie'),
            ),
          ],
        ),
      ),
    );
  }

  void _createRoom(BuildContext context) async {
    final provider = context.read<MultiplayerGameProvider>();

    // TODO: Demander settings + nom joueur
    await provider.createRoom(
      settings: GameSettings(), // À personnaliser
      playerName: 'Joueur 1',
    );

    if (provider.roomCode != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MultiplayerLobbyScreen(),
        ),
      );
    }
  }

  void _joinRoom(BuildContext context) async {
    // Afficher dialog pour entrer le code
    final code = await _showRoomCodeDialog(context);
    if (code == null) return;

    final provider = context.read<MultiplayerGameProvider>();
    await provider.joinRoom(
      roomCode: code,
      playerName: 'Joueur',
    );

    if (provider.roomCode != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MultiplayerLobbyScreen(),
        ),
      );
    }
  }

  Future<String?> _showRoomCodeDialog(BuildContext context) async {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Entrer le code de la partie'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: 'Ex: ABC123'),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.toUpperCase()),
            child: Text('Rejoindre'),
          ),
        ],
      ),
    );
  }
}
```

#### 4.2 `lib/screens/multiplayer_lobby_screen.dart` (NOUVEAU)

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/multiplayer_game_provider.dart';
import 'multiplayer_game_screen.dart';

class MultiplayerLobbyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Salle d\'attente')),
      body: Consumer<MultiplayerGameProvider>(
        builder: (context, provider, _) {
          if (provider.gameState != null) {
            // Partie démarrée, naviguer vers l'écran de jeu
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => MultiplayerGameScreen(),
                ),
              );
            });
          }

          return Column(
            children: [
              // Afficher code room
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Code de la partie: ${provider.roomCode}',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),

              // Liste des joueurs
              Expanded(
                child: ListView.builder(
                  itemCount: provider.playersInLobby.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      leading: Icon(Icons.person),
                      title: Text(provider.playersInLobby[index]),
                    );
                  },
                ),
              ),

              // Bouton démarrer (seulement pour l'hôte)
              if (provider.isHost)
                Padding(
                  padding: EdgeInsets.all(16),
                  child: ElevatedButton(
                    onPressed: () => provider.startGame(),
                    child: Text('Démarrer la partie'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
```

#### 4.3 `lib/screens/multiplayer_game_screen.dart` (NOUVEAU)

Réutilise la logique de `game_screen.dart` mais avec `MultiplayerGameProvider` :

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/multiplayer_game_provider.dart';
// Réutiliser les widgets existants (CenterTable, PlayerHand, etc.)

class MultiplayerGameScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<MultiplayerGameProvider>(
        builder: (context, provider, _) {
          if (provider.gameState == null) {
            return Center(child: CircularProgressIndicator());
          }

          // TODO: Réutiliser la mise en page de game_screen.dart
          // Mais appeler les méthodes de MultiplayerGameProvider

          return Stack(
            children: [
              // Table de jeu
              // Mains des joueurs
              // Contrôles
            ],
          );
        },
      ),
    );
  }
}
```

---

## Phase 5 : Support Tournament multijoueur

### Extensions nécessaires

#### 5.1 Backend - Gestion des manches

Dans `RoomManager.ts`, ajouter :

```typescript
// Terminer manche et démarrer la suivante
async endTournamentRound(roomCode: string) {
  const room = this.rooms.get(roomCode);
  if (!room || room.gameMode !== 'tournament') return;

  // Calculer classement
  const ranking = this.getFinalRanking(room.gameState!);

  // Mettre à jour scores cumulés
  ranking.forEach((player, index) => {
    const score = this.getFinalScore(room.gameState!, player);
    room.gameState!.tournamentCumulativeScores[player.id] =
      (room.gameState!.tournamentCumulativeScores[player.id] || 0) + score;
  });

  // Éliminer dernier joueur
  const eliminatedPlayer = ranking[ranking.length - 1];
  room.players = room.players.filter((p) => p.id !== eliminatedPlayer.id);

  // Si 1 seul joueur restant = victoire
  if (room.players.length === 1) {
    room.status = 'ended';
    this.broadcastGameState(roomCode, 'GAME_ENDED', {
      winner: room.players[0],
    });
    return;
  }

  // Démarrer manche suivante
  room.gameState!.tournamentRound++;
  room.gameState = this.initializeGameState(room);

  this.broadcastGameState(roomCode, 'FULL_STATE', {
    message: `Manche ${room.gameState!.tournamentRound} - ${room.players.length} joueurs restants`,
  });
}
```

#### 5.2 Client - UI Tournament

Afficher le classement entre les manches, scores cumulés, etc.

---

## Fichiers critiques à modifier/créer

### Backend (Node.js)
- `src/server.ts` (création)
- `src/services/RoomManager.ts` (création)
- `src/services/TimerManager.ts` (création)
- `src/services/GameLogic.ts` (port de Dart → TypeScript)
- `src/services/BotAI.ts` (port de Dart → TypeScript)
- `src/handlers/connectionHandler.ts` (création)
- `src/handlers/roomHandler.ts` (création)
- `src/handlers/gameHandler.ts` (création)
- `src/models/Room.ts` (création)
- `src/models/GameState.ts` (port)
- `src/models/Player.ts` (port)
- `src/models/Card.ts` (port)

### Client (Flutter)
- `lib/models/card.dart` (ajout toJson/fromJson)
- `lib/models/player.dart` (ajout toJson/fromJson)
- `lib/models/game_state.dart` (ajout toJson/fromJson)
- `lib/services/multiplayer_service.dart` (création)
- `lib/providers/multiplayer_game_provider.dart` (création)
- `lib/screens/multiplayer_menu_screen.dart` (création)
- `lib/screens/multiplayer_lobby_screen.dart` (création)
- `lib/screens/multiplayer_game_screen.dart` (création)
- `pubspec.yaml` (ajout socket_io_client: ^2.0.0)

---

## Vérification et tests

### Tests backend

1. **Test de connexion Socket.IO**
   ```bash
   # Dans dutch-server/
   npm test -- connection.test.ts
   ```

2. **Test création/join room**
   ```bash
   npm test -- room.test.ts
   ```

3. **Test synchronisation GameState**
   ```bash
   npm test -- gamestate.test.ts
   ```

4. **Test actions joueurs**
   ```bash
   npm test -- actions.test.ts
   ```

### Tests client

1. **Test connexion au serveur**
   - Lancer le serveur : `npm start`
   - Lancer l'app Flutter
   - Vérifier connexion dans les logs

2. **Test création room**
   - Créer une partie
   - Vérifier réception du code room
   - Vérifier que l'hôte est bien dans la lobby

3. **Test join room**
   - Créer une partie sur un appareil
   - Rejoindre avec le code sur un autre appareil
   - Vérifier synchronisation de la liste des joueurs

4. **Test partie complète**
   - Démarrer une partie 2 joueurs + 2 bots
   - Jouer plusieurs tours
   - Vérifier synchronisation du timer
   - Vérifier synchronisation des actions
   - Terminer la partie

5. **Test Tournament**
   - Lancer un tournoi à 4 joueurs
   - Finir manche 1
   - Vérifier élimination + scores cumulés
   - Jouer manche 2
   - Vérifier fin du tournoi

### Tests de robustesse

1. **Test déconnexion**
   - Couper réseau d'un joueur mid-game
   - Vérifier gestion de la déconnexion
   - Reconnecter et vérifier re-synchronisation

2. **Test latence**
   - Simuler latence réseau (Network Link Conditioner sur iOS)
   - Vérifier que le timer reste synchronisé
   - Vérifier que les actions sont bien validées

3. **Test race conditions**
   - 2 joueurs tentent de matcher en même temps
   - Vérifier que le serveur n'accepte qu'une action
   - Vérifier cohérence de l'état final

---

## Points d'attention

### Sécurité
- Valider TOUTES les actions côté serveur
- Ne jamais faire confiance aux données client
- Vérifier que c'est bien le tour du joueur
- Limiter le taux d'actions (rate limiting)
- Protéger contre les room codes devinables (codes longs + expiration)

### Performance
- Utiliser des updates partiels au lieu de FULL_STATE à chaque action
- Broadcast timer seulement toutes les 200ms
- Nettoyer les rooms inactives (expiration après 30min)
- Limiter la taille de l'historique des actions (50 dernières)

### UX
- Afficher indicateur de latence
- Feedback visuel immédiat (optimistic updates)
- Messages d'erreur clairs
- Gestion gracieuse des déconnexions
- Possibilité de quitter proprement

---

## Extensions futures

1. **Chat in-game**
   - Événements `chat:message`
   - Filtrage de langage offensant

2. **Rejeu automatique**
   - Sauvegarder l'historique complet
   - Rejouer les actions pour debug

3. **Spectateurs**
   - Permettre de regarder une partie sans jouer
   - Room.spectators[]

4. **Matchmaking automatique**
   - File d'attente par niveau MMR
   - Système de rangs persisté en DB

5. **Statistiques en ligne**
   - API REST pour stats globales
   - Leaderboards
   - Historique des parties

6. **Mobile + Web**
   - Version web du jeu (Flutter Web)
   - Cross-platform rooms

---

## Estimation de l'effort

- **Phase 1** (Sérialisation) : 1-2 jours
- **Phase 2** (Backend) : 5-7 jours
- **Phase 3** (Client service) : 2-3 jours
- **Phase 4** (UI multijoueur) : 3-4 jours
- **Phase 5** (Tournament) : 2-3 jours
- **Tests & Debug** : 3-5 jours

**Total estimé : 3-4 semaines de développement**
