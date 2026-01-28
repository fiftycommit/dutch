import { Server } from 'socket.io';
import { GameLogic } from './GameLogic';
import { BotAI } from './BotAI';
import {
  createGameState,
  GameMode,
  GamePhase,
  Difficulty,
  getCurrentPlayer,
} from '../models/GameState';
import {
  createPlayer,
  Player,
  BotBehavior,
  BotSkillLevel,
  calculateScore,
} from '../models/Player';
import {
  Room,
  RoomStatus,
  GameSettings,
  createRoom as createRoomModel,
} from '../models/Room';
import { TimerManager } from './TimerManager';

export interface RoomManagerOptions {
  turnTimeoutMs: number;
  presenceGraceMs: number;
  roomTtlMs: number;
  cleanupIntervalMs: number;
  stalePlayerMs: number;
  now: () => number;
}

export class RoomManager {
  private rooms = new Map<string, Room>();
  private timerManager: TimerManager;
  private actionTimers = new Map<string, NodeJS.Timeout>();
  private presenceTimers = new Map<string, NodeJS.Timeout>();
  private presenceChecks = new Map<string, { playerId: string; deadlineAt: number }>();
  private cleanupTimer: NodeJS.Timeout | null = null;
  private turnTimeoutMs: number;
  private presenceGraceMs: number;
  private roomTtlMs: number;
  private cleanupIntervalMs: number;
  private stalePlayerMs: number;
  private now: () => number;

  constructor(private io: Server, options: Partial<RoomManagerOptions> = {}) {
    this.turnTimeoutMs = options.turnTimeoutMs ?? 20000;
    this.presenceGraceMs = options.presenceGraceMs ?? 3000;
    this.roomTtlMs = options.roomTtlMs ?? 2 * 60 * 60 * 1000;
    this.cleanupIntervalMs = options.cleanupIntervalMs ?? 10000;
    this.stalePlayerMs = options.stalePlayerMs ?? 15000;
    this.now = options.now ?? (() => Date.now());
    this.timerManager = new TimerManager({
      getRoom: (roomCode) => this.getRoom(roomCode),
      broadcastGameState: (roomCode, updateType, data) =>
        this.broadcastGameState(roomCode, updateType, data),
      endReactionPhase: (roomCode) => this.endReactionPhase(roomCode),
    });
    this.startCleanupLoop();
  }

  getRoom(roomCode: string): Room | undefined {
    return this.rooms.get(roomCode);
  }

  getRoomCount(): number {
    return this.rooms.size;
  }

  listRooms() {
    return Array.from(this.rooms.values()).map((room) => ({
      id: room.id,
      playerCount: this.activePlayerCount(room),
      status: room.status,
      gameMode: GameMode[room.gameMode],
    }));
  }

  listRoomsDebug() {
    const now = this.now();
    return Array.from(this.rooms.values()).map((room) => ({
      id: room.id,
      status: room.status,
      hostPlayerId: room.hostPlayerId,
      expiresAt: room.expiresAt,
      lastActivityAt: room.lastActivityAt,
      players: room.players.map((p) => ({
        id: p.id,
        clientId: p.clientId,
        name: p.name,
        isHuman: p.isHuman,
        connected: p.connected,
        focused: p.focused,
        lastSeenAt: p.lastSeenAt,
        stale: p.isHuman ? now - (p.lastSeenAt ?? 0) > this.stalePlayerMs : false,
        staleSince: p.lastSeenAt ? now - p.lastSeenAt : null,
        ready: p.ready,
        isSpectator: p.isSpectator,
      })),
    }));
  }

  dispose() {
    if (this.cleanupTimer) {
      clearInterval(this.cleanupTimer);
      this.cleanupTimer = null;
    }

    for (const roomCode of this.rooms.keys()) {
      this.clearTurnTimer(roomCode);
      this.clearReactionTimer(roomCode);
      const pending = this.presenceChecks.get(roomCode);
      if (pending) {
        this.clearPresenceCheck(roomCode, pending.playerId);
      }
    }

    for (const timer of this.presenceTimers.values()) {
      clearTimeout(timer);
    }
    this.presenceTimers.clear();
    this.presenceChecks.clear();
    this.actionTimers.clear();
    this.rooms.clear();
  }

  createRoom(
    hostSocketId: string,
    settings: any,
    playerName?: string,
    clientId?: string
  ): Room {
    const normalizedSettings = this.normalizeSettings(settings);
    const roomCode = this.generateRoomCode();
    const expiresAt = this.now() + this.roomTtlMs;
    const room = createRoomModel(
      roomCode,
      hostSocketId,
      normalizedSettings,
      expiresAt
    );

    const hostPlayer = createPlayer(
      hostSocketId,
      playerName || 'Hôte',
      true,
      0,
      undefined,
      undefined,
      clientId
    );
    hostPlayer.connected = true;
    hostPlayer.focused = true;
    hostPlayer.lastSeenAt = this.now();
    room.players.push(hostPlayer);

    this.touchRoom(room);
    this.rooms.set(roomCode, room);
    return room;
  }

  joinRoom(
    roomCode: string,
    socketId: string,
    playerName?: string,
    clientId?: string
  ): {
    room?: Room;
    player?: Player;
    error?: string;
  } {
    const room = this.rooms.get(roomCode);
    if (!room) {
      return { error: 'Room introuvable' };
    }

    this.pruneWaitingRoom(room);
    this.ensureHost(room);

    if (clientId) {
      const existing = room.players.find((p) => p.clientId === clientId);
      if (existing) {
        // Allow rejoining even if playing
        const previousId = existing.id;
        existing.id = socketId;
        if (playerName) {
          existing.name = playerName;
        }
        existing.isHuman = true;
        existing.connected = true;
        existing.focused = true;
        existing.lastSeenAt = this.now();

        // Clear any pending presence check for this player
        const pendingCheck = this.presenceChecks.get(roomCode);
        if (pendingCheck && pendingCheck.playerId === previousId) {
          this.clearPresenceCheck(roomCode, previousId);
        }

        if (room.hostPlayerId === previousId) {
          room.hostPlayerId = socketId;
        }
        this.touchRoom(room);
        return { room, player: existing };
      }
    }

    // Si la partie est en cours, on rejoint comme SPECTATEUR
    const isSpectator = (room.status !== RoomStatus.waiting && room.status !== RoomStatus.ended);

    const maxPlayers =
      typeof room.settings?.maxPlayers === 'number'
        ? room.settings.maxPlayers
        : 4;

    // Si on n'est pas spectateur et que c'est plein -> Erreur
    if (!isSpectator && this.activePlayerCount(room) >= maxPlayers) {
      return { error: 'Room pleine' };
    }

    const player = createPlayer(
      socketId,
      playerName || `Joueur ${room.players.length + 1}`,
      true,
      room.players.length,
      undefined,
      undefined,
      clientId
    );
    player.connected = true;
    player.focused = true;
    player.lastSeenAt = this.now();
    player.ready = false;
    player.isSpectator = isSpectator;

    room.players.push(player);
    this.reindexPlayers(room);
    this.touchRoom(room);

    // Si une partie est en cours, envoyer l'état complet au nouveau joueur
    if (room.gameState) {
      this.sendFullStateToPlayer(roomCode, socketId);
    }

    return { room, player };
  }

  notifyPlayerJoined(roomCode: string, player: Player) {
    const room = this.rooms.get(roomCode);
    if (!room) return;
    this.io.to(roomCode).emit('room:player_joined', {
      roomCode,
      player,
      playerCount: this.activePlayerCount(room),
    });
  }

  /**
   * Abandonner la partie en cours (sans quitter la room)
   */
  forfeitGame(roomCode: string, playerId: string): boolean {
    const room = this.rooms.get(roomCode);
    if (!room) return false;

    // Trouver le joueur
    const player = room.players.find(p => p.id === playerId);
    if (!player) return false;

    // Si partie en cours, on le marque comme "Folded"
    if (room.status === RoomStatus.playing && room.gameState) {
      const gamePlayer = room.gameState.players.find(p => p.id === playerId);
      if (gamePlayer) {
        // Logique de jeu: abandon
        // On pourrait appeler GameLogic.fold() mais fold() c'est pour le tour.
        // Ici c'est un abandon total.
        // On va simuler qu'il devient spectateur mais RESTE connecté
        player.isSpectator = true;
        player.ready = false;

        this.clearPresenceCheck(roomCode, playerId);
        this.clearTurnTimer(roomCode);

        // Check if only one active player remains ("Last Man Standing")
        const activeCount = this.activePlayerCount(room);
        if (activeCount <= 1) {
          this.handleGameEnd(roomCode); // Utiliser handleGameEnd directement
        } else if (getCurrentPlayer(room.gameState).id === playerId) {
          this.forceEndTurn(roomCode, `${player.name} a abandonné.`);
        }
      }

      // Notifier tout le monde que le joueur abandonne
      this.io.to(roomCode).emit('player:forfeit', {
        roomCode,
        playerId,
        playerName: player.name,
        message: `${player.name} a abandonné la partie et rejoint le lobby.`
      });
    }

    this.touchRoom(room);
    this.broadcastPresence(roomCode); // Mise à jour UI Lobby
    return true;
  }

  startGame(roomCode: string, options: { fillBots?: boolean } = {}): boolean {
    const room = this.rooms.get(roomCode);
    if (!room) return false;

    this.pruneWaitingRoom(room);
    room.players = room.players.filter((p) => !p.isHuman || p.connected !== false);
    this.reindexPlayers(room);
    this.ensureHost(room);

    const minPlayers =
      typeof room.settings?.minPlayers === 'number'
        ? room.settings.minPlayers
        : 2;
    const maxPlayers =
      typeof room.settings?.maxPlayers === 'number'
        ? room.settings.maxPlayers
        : 4;
    const fillBots = options.fillBots ?? (room.settings?.fillBots !== false);

    const host = room.players.find((p) => p.id === room.hostPlayerId);
    if (!host || host.connected === false) return false;
    if (!host.ready) return false;

    const readyHumans = room.players.filter(
      (p) => p.isHuman && p.connected !== false && p.ready
    ).length;
    if (readyHumans < minPlayers) return false;
    if (this.activePlayerCount(room) > maxPlayers) return false;

    const difficulty = this.getBotDifficulty(room.settings);
    if (fillBots) {
      while (room.players.length < maxPlayers) {
        room.players.push(this.createBot(room.players.length, difficulty));
      }
    }

    const gameState = createGameState(room.players, room.gameMode, difficulty);
    GameLogic.initializeGame(gameState);
    gameState.phase = GamePhase.playing;

    room.gameState = gameState;
    room.status = RoomStatus.playing;
    this.clearTurnTimer(roomCode);
    this.startTurnTimer(roomCode);
    this.touchRoom(room);
    return true;
  }

  broadcastGameState(
    roomCode: string,
    updateType: string,
    additionalData: any = {}
  ) {
    const room = this.rooms.get(roomCode);
    if (!room || !room.gameState) return;
    this.touchRoom(room);

    room.players.forEach((player) => {
      const personalizedState = this.getPersonalizedState(
        room.gameState,
        player.id
      );
      this.io.to(player.id).emit('game:state_update', {
        type: updateType,
        gameState: personalizedState,
        ...additionalData,
      });
    });
  }

  startReactionTimer(roomCode: string, durationMs: number) {
    this.clearTurnTimer(roomCode);
    this.timerManager.startReactionTimer(roomCode, durationMs);
  }



  clearReactionTimer(roomCode: string) {
    this.timerManager.clearTimer(roomCode);
  }

  pauseGame(roomCode: string, pausedByName: string) {
    const room = this.rooms.get(roomCode);
    if (!room || !room.gameState) return;
    if (room.isPaused) return;

    room.isPaused = true;

    // Arrêter les timers sans les effacer complètement (logic complexe)
    // Pour simplifier : on clear les timers, et on les relancera au resume.
    // Il faudrait stocker le temps restant pour être précis, mais pour l'instant on stop.
    this.clearTurnTimer(roomCode);
    this.timerManager.pauseTimer(roomCode); // Supposons que TimerManager gère ça, sinon on clear

    this.broadcastGameState(roomCode, 'GAME_PAUSED', { pausedBy: pausedByName });
  }

  resumeGame(roomCode: string, resumedByName: string) {
    const room = this.rooms.get(roomCode);
    if (!room || !room.gameState) return;
    if (!room.isPaused) return;

    room.isPaused = false;

    // Relancer les timers
    if (room.gameState.phase === GamePhase.playing) {
      this.startTurnTimer(roomCode);
    } else if (room.gameState.phase === GamePhase.reaction) {
      this.timerManager.resumeTimer(roomCode);
    }

    this.broadcastGameState(roomCode, 'GAME_RESUMED', { resumedBy: resumedByName });
  }

  async endReactionPhase(roomCode: string) {

    this.clearReactionTimer(roomCode);
    const room = this.rooms.get(roomCode);
    if (!room || !room.gameState) return;

    room.gameState.phase = GamePhase.playing;
    room.gameState.lastSpiedCard = null;
    room.gameState.reactionStartTime = null;

    GameLogic.nextPlayer(room.gameState);
    this.broadcastGameState(roomCode, 'PHASE_CHANGE');

    await this.checkAndPlayBotTurn(roomCode);
  }

  async checkAndPlayBotTurn(roomCode: string) {
    const room = this.rooms.get(roomCode);
    if (!room || !room.gameState) return;
    const gameState = room.gameState;

    while (true) {
      if (gameState.phase !== GamePhase.playing) break;
      if (getCurrentPlayer(gameState).isHuman) break;

      await this.delay(800);
      await BotAI.playBotTurn(gameState);

      this.broadcastGameState(roomCode, 'PARTIAL_UPDATE');

      const phase = this.currentPhase(gameState);
      if (phase === GamePhase.ended) {
        this.handleGameEnd(roomCode);
        return;
      }

      if (phase === GamePhase.reaction) {
        const reactionTime =
          typeof room.settings?.reactionTimeMs === 'number'
            ? room.settings.reactionTimeMs
            : 3000;
        this.startReactionTimer(roomCode, reactionTime);
        break;
      }
    }

    if (gameState.phase === GamePhase.playing) {
      this.startTurnTimer(roomCode);
    }
  }

  handleGameEnd(roomCode: string) {
    const room = this.rooms.get(roomCode);
    if (!room || !room.gameState) return;

    // Calculer les scores de cette manche pour chaque joueur
    const roundScores = room.gameState.players.map((player) => ({
      playerId: player.id,
      clientId: player.clientId,
      name: player.name,
      score: calculateScore(player),
      hand: player.hand, // Inclure les cartes pour affichage
    }));

    // Calculer et stocker les scores cumulés
    this.updateCumulativeScores(room);

    room.status = RoomStatus.ended;
    room.gameState.phase = GamePhase.ended;
    this.clearTurnTimer(roomCode);
    this.broadcastGameState(roomCode, 'GAME_ENDED', {
      message: 'Partie terminée !',
      roundScores, // Scores de cette manche
      cumulativeScores: this.getCumulativeScoresArray(room),
    });
    this.broadcastPresence(roomCode);
  }

  /**
   * Redémarre une partie (rematch) - garde les joueurs et scores cumulés
   */
  restartGame(roomCode: string, requesterId: string): boolean {
    const room = this.rooms.get(roomCode);
    if (!room) return false;

    // Seul l'hôte peut relancer
    if (room.hostPlayerId !== requesterId) return false;

    // La partie doit être terminée
    if (room.status !== RoomStatus.ended) return false;

    // Reset room state for new game

    // Remove bots so we can refill them or play just humans
    room.players = room.players.filter((p) => p.isHuman);

    room.status = RoomStatus.waiting;
    room.gameState = null;

    room.players.forEach(p => {
      p.ready = false;
      p.hand = [];
      p.hasFolded = false;
      p.knownCards = [];
      p.isSpectator = false;
    });

    this.reindexPlayers(room);

    // Incrémenter le round si mode tournoi
    if (room.gameMode === GameMode.tournament) {
      room.tournamentRound = (room.tournamentRound || 1) + 1;
    }

    this.touchRoom(room);
    this.broadcastPresence(roomCode);

    this.io.to(roomCode).emit('room:restarted', {
      roomCode,
      message: 'Nouvelle partie !',
      cumulativeScores: this.getCumulativeScoresArray(room),
    });

    return true;
  }

  /**
   * Kick un joueur (hôte uniquement)
   */
  kickPlayer(
    roomCode: string,
    hostId: string,
    targetClientId: string
  ): boolean {
    const room = this.rooms.get(roomCode);
    if (!room) return false;

    // Seul l'hôte peut kick
    if (room.hostPlayerId !== hostId) return false;

    // Trouver le joueur à kick par clientId
    const targetIndex = room.players.findIndex(
      (p) => p.clientId === targetClientId
    );
    if (targetIndex < 0) return false;

    const target = room.players[targetIndex];

    // On ne peut pas se kick soi-même
    if (target.id === hostId) return false;

    // Notifier le joueur qu'il est kicked
    this.io.to(target.id).emit('room:kicked', {
      roomCode,
      message: "Vous avez été exclu de la room par l'hôte",
    });

    // Retirer le joueur
    room.players.splice(targetIndex, 1);
    this.reindexPlayers(room);

    this.touchRoom(room);
    this.broadcastPresence(roomCode);

    return true;
  }

  /**
   * Met à jour les scores cumulés pour tous les joueurs de la room
   */
  private updateCumulativeScores(room: Room): void {
    if (!room.gameState) return;

    // Initialiser si nécessaire
    if (!room.cumulativeScores) {
      room.cumulativeScores = new Map<string, number>();
    }

    // Ajouter les scores de cette manche
    for (const player of room.gameState.players) {
      const scoreKey = player.clientId || player.id;
      const currentScore = room.cumulativeScores.get(scoreKey) || 0;
      const roundScore = calculateScore(player);
      room.cumulativeScores.set(scoreKey, currentScore + roundScore);
    }
  }

  /**
   * Retourne les scores cumulés sous forme de tableau
   */
  private getCumulativeScoresArray(
    room: Room
  ): Array<{ clientId: string; score: number; name: string }> {
    if (!room.cumulativeScores) return [];

    const result: Array<{ clientId: string; score: number; name: string }> = [];
    room.cumulativeScores.forEach((score, clientId) => {
      const player = room.players.find(
        (p) => p.clientId === clientId || p.id === clientId
      );
      result.push({
        clientId,
        score,
        name: player?.name || 'Joueur',
      });
    });

    // Trier par score croissant (le plus bas est le meilleur au Dutch)
    result.sort((a, b) => {
      const diff = a.score - b.score;
      if (diff !== 0) return diff;

      // En cas d'égalité, le joueur encore en ligne/actif gagne (est considéré meilleur = premier)
      const pA = room.players.find(p => p.clientId === a.clientId || p.id === a.clientId);
      const pB = room.players.find(p => p.clientId === b.clientId || p.id === b.clientId);

      const aActive = pA && pA.connected && !pA.isSpectator;
      const bActive = pB && pB.connected && !pB.isSpectator;

      if (aActive && !bActive) return -1; // a gagne
      if (!aActive && bActive) return 1;  // b gagne

      return 0;
    });
    return result;
  }

  setReady(roomCode: string, socketId: string, ready: boolean): boolean {
    const room = this.rooms.get(roomCode);
    if (!room || room.status !== RoomStatus.waiting) return false;
    const player = room.players.find((p) => p.id === socketId);
    if (!player || !player.isHuman) return false;

    player.ready = ready;
    player.connected = true;
    player.lastSeenAt = this.now();
    this.touchRoom(room);
    this.broadcastPresence(roomCode);
    return true;
  }

  sendChat(roomCode: string, socketId: string, rawMessage: string): boolean {
    const room = this.rooms.get(roomCode);
    if (!room) return false;
    const player = room.players.find((p) => p.id === socketId);
    if (!player || player.isSpectator) return false;

    const message = rawMessage?.toString().trim();
    if (!message) return false;

    const payload = {
      roomCode,
      playerId: player.id,
      clientId: player.clientId,
      name: player.name,
      message: message.slice(0, 240),
      timestamp: this.now(),
    };

    this.touchPlayer(socketId);
    this.io.to(roomCode).emit('chat:message', payload);
    return true;
  }

  touchPlayer(socketId: string) {
    const now = this.now();
    for (const room of this.rooms.values()) {
      const player = room.players.find((p) => p.id === socketId);
      if (!player) continue;
      player.lastSeenAt = now;
      player.connected = true;
      this.touchRoom(room);
    }
  }

  recordPlayerAction(roomCode: string, playerId: string) {
    const room = this.rooms.get(roomCode);
    if (!room) return;
    const player = room.players.find((p) => p.id === playerId);
    if (player) {
      player.lastSeenAt = this.now();
      player.connected = true;
    }
    this.touchRoom(room);

    const pending = this.presenceChecks.get(roomCode);
    if (pending && pending.playerId === playerId) {
      this.clearPresenceCheck(roomCode, playerId);
    }

    if (
      room.gameState &&
      room.gameState.phase === GamePhase.playing &&
      getCurrentPlayer(room.gameState).id === playerId
    ) {
      this.startTurnTimer(roomCode);
    }
  }

  updateFocus(roomCode: string, socketId: string, focused: boolean) {
    const room = this.rooms.get(roomCode);
    if (!room) return;
    const player = room.players.find((p) => p.id === socketId);
    if (!player) return;
    player.focused = focused;
    player.connected = true;
    player.lastSeenAt = this.now();
    this.touchRoom(room);
    this.broadcastPresence(roomCode);
  }

  confirmPresence(roomCode: string, socketId: string) {
    const room = this.rooms.get(roomCode);
    if (!room) return;
    const player = room.players.find((p) => p.id === socketId);
    if (!player) return;
    this.clearPresenceCheck(roomCode, player.id);
    player.connected = true;
    player.lastSeenAt = this.now();
    this.touchRoom(room);
    this.startTurnTimer(roomCode);
    this.broadcastPresence(roomCode);
  }

  handleLeave(roomCode: string, socketId: string) {
    const room = this.rooms.get(roomCode);
    if (!room) return;
    const index = room.players.findIndex((p) => p.id === socketId);
    if (index < 0) return;

    const leaving = room.players[index];
    this.clearPresenceCheck(roomCode, socketId);

    // Notifier les autres joueurs que ce joueur quitte
    this.io.to(roomCode).emit('player:left', {
      playerId: leaving.id,
      playerName: leaving.name,
      roomCode,
    });

    if (room.status === RoomStatus.waiting) {
      room.players.splice(index, 1);
      if (room.players.length === 0) {
        this.removeRoom(roomCode);
        return;
      }
      this.reindexPlayers(room);
      if (room.hostPlayerId === socketId && room.players.length > 0) {
        room.hostPlayerId = room.players[0].id;
      }
      this.ensureHost(room);
    } else {
      leaving.connected = false;
      leaving.focused = false;
      leaving.lastSeenAt = this.now();
      leaving.isSpectator = true;
      if (room.gameState && getCurrentPlayer(room.gameState).id === leaving.id) {
        this.forceEndTurn(roomCode, `${leaving.name} est passé spectateur.`);
      }
    }

    this.touchRoom(room);
    this.broadcastPresence(roomCode);
    this.broadcastGameState(roomCode, 'PLAYER_LEFT');

    // Check if game should end due to lack of players
    this.checkGameEndCondition(roomCode);
  }

  handleDisconnect(socketId: string) {
    for (const room of this.rooms.values()) {
      const player = room.players.find((p) => p.id === socketId);
      if (!player) continue;
      player.connected = false;
      player.focused = false;
      player.lastSeenAt = this.now();
      this.touchRoom(room);
      this.broadcastPresence(room.id);
      this.checkGameEndCondition(room.id);
    }
    this.cleanupRooms();
  }

  checkGameEndCondition(roomCode: string) {
    const room = this.rooms.get(roomCode);
    if (!room || !room.gameState) return;
    if (room.gameState.phase === GamePhase.ended) return;
    if (room.gameState.phase === GamePhase.setup) return; // Don't end during setup

    // Count active (connected and not spectator) human players
    const activeHumans = room.players.filter(
      (p) => p.isHuman && p.connected && !p.isSpectator
    );

    // If less than 2 active humans remain (and we are in a multiplayer game)
    // Note: If playing with bots, we might want to keep playing?
    // User requirement: "When opponent leaves, game ends".
    // Assuming 1v1 human or multi-human.

    // If only 1 or 0 active humans left, end the game.
    // (Should we allow playing against bots if humans leave? 
    // The user issue is specifically about "opponent leaves -> game stuck".
    // So enforcing "min 2 humans" or "min 1 human if bots present"?)

    // Let's stick to: if only 1 active player (human or bot) left ? 
    // No, bots don't disconnect.
    // If 2 humans playing, one leaves -> 1 active human. Game should end.

    // Let's count *active players* (including bots if they count as players)
    // But bots are always "connected".
    // If the game was initialized with bots, `room.players` has bots.

    // Valid termination condition:
    // If it's a multiplayer game (started with >1 human), and now <2 humans are connected.

    // Let's use a simpler heuristic:
    // If only 1 "alive" player remains.
    // "Alive" means connected and not spectator.

    const activePlayers = room.players.filter(
      p => (p.isHuman ? (p.connected && !p.isSpectator) : true)
    );

    if (activePlayers.length < 2) {
      this.handleGameEnd(roomCode);
    }
  }

  broadcastPresence(roomCode: string) {
    const room = this.rooms.get(roomCode);
    if (!room) return;
    const now = this.now();
    const players = room.players.map((player) => ({
      id: player.id,
      clientId: player.clientId,
      name: player.name,
      isHuman: player.isHuman,
      position: player.position,
      connected: player.isHuman
        ? (player.connected ?? false) && !this.isPlayerStale(player, now)
        : true,
      focused: player.focused ?? false,
      isSpectator: player.isSpectator ?? false,
      ready: player.ready ?? false,
    }));
    this.io.to(roomCode).emit('presence:update', {
      roomCode,
      hostPlayerId: room.hostPlayerId,
      players,
      gameMode: room.gameMode,
      status: room.status,
      cumulativeScores: this.getCumulativeScoresArray(room),
    });
  }

  startTurnTimer(roomCode: string) {
    const room = this.rooms.get(roomCode);
    if (!room || !room.gameState) return;
    if (room.gameState.phase !== GamePhase.playing) return;
    if (this.presenceChecks.has(roomCode)) return;

    const currentPlayer = getCurrentPlayer(room.gameState);
    if (!currentPlayer.isHuman || currentPlayer.isSpectator) return;

    this.clearTurnTimer(roomCode);

    // Si le jeu est en pause, on ne lance pas le timer maintenant
    if (room.isPaused) return;

    // Mettre à jour les infos de timer dans le gameState pour l'affichage client
    room.gameState.turnStartTime = this.now();
    room.gameState.turnTimeoutMs = this.turnTimeoutMs;

    const playerId = currentPlayer.id;

    const timer = setTimeout(() => {
      const currentRoom = this.rooms.get(roomCode);
      if (!currentRoom || !currentRoom.gameState) return;
      const stillCurrent = getCurrentPlayer(currentRoom.gameState).id === playerId;
      if (!stillCurrent) return;
      this.actionTimers.delete(roomCode);
      this.triggerPresenceCheck(roomCode, playerId, 'Temps de jeu écoulé');
    }, this.turnTimeoutMs);

    this.actionTimers.set(roomCode, timer);
  }

  clearTurnTimer(roomCode: string) {
    const timer = this.actionTimers.get(roomCode);
    if (timer) {
      clearTimeout(timer);
      this.actionTimers.delete(roomCode);
    }
    // Réinitialiser le timestamp de tour
    const room = this.rooms.get(roomCode);
    if (room?.gameState) {
      room.gameState.turnStartTime = null;
    }
  }

  triggerPresenceCheck(roomCode: string, playerId: string, reason: string) {
    const room = this.rooms.get(roomCode);
    if (!room) return;
    const player = room.players.find((p) => p.id === playerId);
    if (!player || player.isSpectator) return;
    if (this.presenceChecks.get(roomCode)?.playerId === playerId) return;

    const deadlineAt = this.now() + this.presenceGraceMs;
    this.presenceChecks.set(roomCode, { playerId, deadlineAt });

    this.io.to(player.id).emit('presence:check', {
      reason,
      deadlineMs: this.presenceGraceMs,
    });

    const key = `${roomCode}:${playerId}`;
    const existing = this.presenceTimers.get(key);
    if (existing) clearTimeout(existing);

    const timer = setTimeout(() => {
      const current = this.presenceChecks.get(roomCode);
      if (!current || current.playerId !== playerId) return;
      this.markSpectator(roomCode, playerId, 'Inactif');
    }, this.presenceGraceMs);

    this.presenceTimers.set(key, timer);
  }

  private clearPresenceCheck(roomCode: string, playerId: string) {
    const current = this.presenceChecks.get(roomCode);
    if (current && current.playerId === playerId) {
      this.presenceChecks.delete(roomCode);
    }

    const key = `${roomCode}:${playerId}`;
    const timer = this.presenceTimers.get(key);
    if (timer) {
      clearTimeout(timer);
      this.presenceTimers.delete(key);
    }
  }

  markSpectator(roomCode: string, playerId: string, reason: string) {
    const room = this.rooms.get(roomCode);
    if (!room) return;
    const player = room.players.find((p) => p.id === playerId);
    if (!player || player.isSpectator) return;
    player.isSpectator = true;
    player.connected = false; // Mark disconnected effectively
    player.focused = false;
    player.lastSeenAt = this.now();
    this.clearPresenceCheck(roomCode, playerId);
    this.clearTurnTimer(roomCode);

    // Check if only one active player remains ("Last Man Standing")
    const activeCount = this.activePlayerCount(room);
    if (activeCount <= 1) {
      this.touchRoom(room);
      this.broadcastPresence(roomCode);
      this.handleGameEnd(roomCode);
      return;
    }

    if (room.gameState && getCurrentPlayer(room.gameState).id === playerId) {
      this.forceEndTurn(roomCode, `${player.name} est passé spectateur.`);
    }

    this.touchRoom(room);
    this.broadcastPresence(roomCode);
  }

  private forceEndTurn(roomCode: string, reason: string) {
    const room = this.rooms.get(roomCode);
    if (!room || !room.gameState) return;
    const gameState = room.gameState;

    if (gameState.isWaitingForSpecialPower) {
      GameLogic.skipSpecialPower(gameState);
    } else if (gameState.drawnCard) {
      GameLogic.discardDrawnCard(gameState);
      if (gameState.isWaitingForSpecialPower) {
        GameLogic.skipSpecialPower(gameState);
      } else {
        GameLogic.nextPlayer(gameState);
      }
    } else {
      GameLogic.nextPlayer(gameState);
    }

    this.broadcastGameState(roomCode, 'ACTION_RESULT', { message: reason });

    if (gameState.phase === GamePhase.ended) {
      this.handleGameEnd(roomCode);
      return;
    }

    if (gameState.phase === GamePhase.reaction) {
      const reactionTime =
        typeof room.settings?.reactionTimeMs === 'number'
          ? room.settings.reactionTimeMs
          : 3000;
      this.startReactionTimer(roomCode, reactionTime);
      return;
    }

    void this.checkAndPlayBotTurn(roomCode);
  }

  private activePlayerCount(room: Room): number {
    const now = this.now();
    return room.players.filter((player) => {
      if (!player.isHuman) return true;
      if (!player.connected) return false;
      return !this.isPlayerStale(player, now);
    }).length;
  }

  private isPlayerStale(player: Player, now: number): boolean {
    if (!player.isHuman) return false;
    const lastSeen = player.lastSeenAt ?? 0;
    return now - lastSeen > this.stalePlayerMs;
  }

  private reindexPlayers(room: Room) {
    room.players.forEach((player, index) => {
      player.position = index;
    });
  }

  private ensureHost(room: Room) {
    const now = this.now();
    const host = room.players.find(
      (p) => p.id === room.hostPlayerId && p.isHuman && p.connected && !this.isPlayerStale(p, now)
    );
    if (host) return;
    const nextHost = room.players.find(
      (p) => p.isHuman && p.connected && !this.isPlayerStale(p, now)
    );
    if (nextHost) {
      room.hostPlayerId = nextHost.id;
    }
  }

  private pruneWaitingRoom(room: Room) {
    if (room.status !== RoomStatus.waiting) return;
    const now = this.now();
    const before = room.players.length;
    room.players = room.players.filter((player) => {
      if (!player.isHuman) return true;
      if (player.connected !== false) return true;
      const lastSeen = player.lastSeenAt ?? 0;
      return now - lastSeen <= this.stalePlayerMs * 2;
    });
    if (room.players.length !== before) {
      this.reindexPlayers(room);
    }
  }

  private touchRoom(room: Room) {
    room.lastActivityAt = this.now();
  }

  private startCleanupLoop() {
    if (this.cleanupTimer) return;
    this.cleanupTimer = setInterval(() => this.cleanupRooms(), this.cleanupIntervalMs);
  }

  private cleanupRooms() {
    const now = this.now();
    for (const room of this.rooms.values()) {
      // Supprimer les rooms en cours de fermeture expirées
      if (room.status === RoomStatus.closing) {
        if (room.closingAt && now >= room.closingAt) {
          this.removeRoom(room.id);
          continue;
        }
        // Room en fermeture mais pas encore expirée, on continue
        continue;
      }

      if (room.status === RoomStatus.waiting) {
        this.pruneWaitingRoom(room);
        this.ensureHost(room);
      }

      let staleChanged = false;
      for (const player of room.players) {
        if (!player.isHuman) continue;
        const lastSeen = player.lastSeenAt ?? 0;
        const isStale = now - lastSeen > this.stalePlayerMs;
        if ((player.connected ?? false) && isStale) {
          player.connected = false;
          player.focused = false;
          staleChanged = true;
        }
      }

      const anyConnected = room.players.some((player) => {
        if (!player.isHuman) return true;
        if (!player.connected) return false;
        const lastSeen = player.lastSeenAt ?? 0;
        return now - lastSeen <= this.stalePlayerMs;
      });

      if (!anyConnected || now >= room.expiresAt) {
        this.removeRoom(room.id);
        continue;
      }

      if (staleChanged) {
        this.broadcastPresence(room.id);
      }
    }
  }

  // ============ Gestion fermeture/transfert de room ============

  /**
   * Ferme une room (hôte uniquement)
   * La room reste disponible 5 minutes pour permettre le transfert d'hôte
   */
  closeRoom(
    roomCode: string,
    socketId: string
  ): { success: boolean; reason?: string } {
    const room = this.rooms.get(roomCode);
    if (!room) return { success: false, reason: 'Room not found' };
    if (room.hostPlayerId !== socketId)
      return { success: false, reason: 'Not host' };

    // Notifier tous les joueurs sauf l'hôte
    room.players.forEach((player) => {
      if (player.id !== socketId && player.isHuman && player.connected) {
        this.io.to(player.id).emit('room:closed', {
          roomCode,
          hostLeft: true,
          canBecomeHost: true,
        });
      }
    });

    // Marquer la room comme en cours de fermeture
    room.status = RoomStatus.closing;
    room.closingAt = this.now() + 5 * 60 * 1000; // 5 minutes

    // Retirer l'ancien hôte de la room
    const hostIndex = room.players.findIndex((p) => p.id === socketId);
    if (hostIndex !== -1) {
      room.players.splice(hostIndex, 1);
    }

    this.broadcastPresence(roomCode);
    return { success: true };
  }

  /**
   * Transfert d'hôte - un joueur demande à devenir hôte d'une room fermée
   */
  transferHost(roomCode: string, requesterId: string): boolean {
    const room = this.rooms.get(roomCode);
    if (!room) return false;

    // Vérifier que la room est en cours de fermeture ou que l'hôte actuel n'est plus connecté
    const currentHost = room.players.find((p) => p.id === room.hostPlayerId);
    const isClosing = room.status === RoomStatus.closing;
    const hostDisconnected = !currentHost || !currentHost.connected;

    if (!isClosing && !hostDisconnected) return false;

    const requester = room.players.find((p) => p.id === requesterId);
    if (!requester || !requester.isHuman || !requester.connected) return false;

    // Transférer l'hôte
    room.hostPlayerId = requesterId;
    room.status = RoomStatus.waiting;
    room.closingAt = undefined;

    this.broadcastPresence(roomCode);

    // Notifier le nouveau hôte
    this.io.to(requesterId).emit('room:host_transferred', {
      roomCode,
      message: 'Vous êtes maintenant l\'hôte',
    });

    return true;
  }

  /**
   * Vérifie quelles rooms sont encore actives
   */
  checkActiveRooms(
    roomCodes: string[]
  ): Array<{ roomCode: string; status: string; playerCount: number }> {
    const result: Array<{
      roomCode: string;
      status: string;
      playerCount: number;
    }> = [];

    for (const code of roomCodes) {
      const room = this.rooms.get(code.toUpperCase());
      if (room) {
        result.push({
          roomCode: room.id,
          status: room.status,
          playerCount: this.activePlayerCount(room),
        });
      }
    }

    return result;
  }

  /**
   * Change le mode de jeu (hôte uniquement, en lobby)
   */
  setGameMode(roomCode: string, socketId: string, mode: number): boolean {
    const room = this.rooms.get(roomCode);
    if (!room || room.status !== RoomStatus.waiting) return false;
    if (room.hostPlayerId !== socketId) return false;

    room.gameMode = mode as GameMode;
    this.broadcastPresence(roomCode);
    return true;
  }

  /**
   * Envoie l'état complet du jeu à un joueur spécifique
   */
  sendFullStateToPlayer(roomCode: string, playerId: string): void {
    const room = this.rooms.get(roomCode);
    if (!room || !room.gameState) return;

    const personalizedState = this.getPersonalizedState(
      room.gameState,
      playerId
    );
    this.io.to(playerId).emit('game:full_state', {
      type: 'FULL_STATE',
      gameState: personalizedState,
    });
  }

  private removeRoom(roomCode: string) {
    this.clearTurnTimer(roomCode);
    this.clearReactionTimer(roomCode);
    const pending = this.presenceChecks.get(roomCode);
    if (pending) {
      this.clearPresenceCheck(roomCode, pending.playerId);
    }

    for (const key of Array.from(this.presenceTimers.keys())) {
      if (key.startsWith(`${roomCode}:`)) {
        const timer = this.presenceTimers.get(key);
        if (timer) clearTimeout(timer);
        this.presenceTimers.delete(key);
      }
    }

    this.rooms.delete(roomCode);
  }

  private getPersonalizedState(gameState: any, playerId: string): any {
    const state = { ...gameState };
    const isGameEnded = gameState.phase === GamePhase.ended;

    state.players = state.players.map((player: Player) => {
      // Si la partie est terminée, révéler toutes les cartes à tous les joueurs
      if (isGameEnded) {
        return {
          ...player,
          // S'assurer que les cartes sont visibles
          hand: player.hand.map((card: any) => ({
            ...card,
            hidden: false,
          })),
        };
      }

      if (player.id === playerId) {
        return player;
      }
      return {
        ...player,
        hand: player.hand.map(() => ({ hidden: true })),
      };
    });

    state.deck = state.deck.map(() => ({ hidden: true }));

    return state;
  }

  private generateRoomCode(): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let code: string;
    do {
      code = Array.from({ length: 6 }, () =>
        chars.charAt(Math.floor(Math.random() * chars.length))
      ).join('');
    } while (this.rooms.has(code));
    return code;
  }

  private createBot(position: number, difficulty: Difficulty): Player {
    const botNames = ['Alice', 'Bob', 'Charlie', 'Diana'];
    const behaviors = [
      BotBehavior.balanced,
      BotBehavior.aggressive,
      BotBehavior.fast,
    ];
    const behavior = behaviors[position % behaviors.length];

    let skillLevel: BotSkillLevel;
    switch (difficulty) {
      case Difficulty.easy:
        skillLevel = BotSkillLevel.bronze;
        break;
      case Difficulty.hard:
        skillLevel = BotSkillLevel.platinum;
        break;
      default:
        skillLevel = BotSkillLevel.silver;
    }

    return {
      id: `bot_${position}`,
      name: botNames[position] || `Bot ${position}`,
      isHuman: false,
      connected: true,
      focused: true,
      isSpectator: false,
      botBehavior: behavior,
      botSkillLevel: skillLevel,
      position,
      hand: [],
      knownCards: [],
    };
  }

  private normalizeSettings(settings: any): GameSettings {
    const gameMode = this.parseGameMode(settings?.gameMode);
    const reactionTimeMs =
      typeof settings?.reactionTimeMs === 'number' ? settings.reactionTimeMs : 3000;
    const botDifficulty =
      typeof settings?.botDifficulty === 'number'
        ? settings.botDifficulty
        : Difficulty.medium;
    const luckDifficulty =
      typeof settings?.luckDifficulty === 'number'
        ? settings.luckDifficulty
        : Difficulty.medium;
    const minPlayersRaw =
      typeof settings?.minPlayers === 'number' ? settings.minPlayers : 2;
    const maxPlayersRaw =
      typeof settings?.maxPlayers === 'number' ? settings.maxPlayers : 4;
    let minPlayers = Math.max(2, Math.min(4, minPlayersRaw));
    let maxPlayers = Math.max(2, Math.min(4, maxPlayersRaw));
    if (maxPlayers < minPlayers) {
      maxPlayers = minPlayers;
    }
    const fillBots = settings?.fillBots !== false;

    return {
      gameMode,
      botDifficulty,
      luckDifficulty,
      reactionTimeMs,
      minPlayers,
      maxPlayers,
      fillBots,
    };
  }

  private parseGameMode(value: any): GameMode {
    if (value === GameMode.tournament || value === 1 || value === 'tournament') {
      return GameMode.tournament;
    }
    return GameMode.quick;
  }

  private getBotDifficulty(settings: GameSettings): Difficulty {
    if (typeof settings?.botDifficulty === 'number') {
      return settings.botDifficulty as Difficulty;
    }
    return Difficulty.medium;
  }

  private currentPhase(gameState: { phase: GamePhase }): GamePhase {
    return gameState.phase;
  }

  private delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
