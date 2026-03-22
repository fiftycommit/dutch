import { Server } from 'socket.io';
import * as fs from 'fs';
import * as path from 'path';
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
import { PushNotificationService } from './PushNotificationService';

export interface RoomManagerOptions {
  turnTimeoutMs: number;
  specialPowerTimeoutMs: number;
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
  private specialPowerTimeoutMs: number;
  private presenceGraceMs: number;
  private roomTtlMs: number;
  private cleanupIntervalMs: number;
  private stalePlayerMs: number;
  private now: () => number;

  private botCastingCache:
    | Array<{
      botId: string;
      botName?: string;
      behavior?: string;
      skillLevel?: string;
      mmr?: number;
    }>
    | null = null;
  private botCastingCacheLoadedAtMs = 0;

  public getIO(): Server {
    return this.io;
  }

  constructor(private io: Server, options: Partial<RoomManagerOptions> = {}) {
    this.turnTimeoutMs = options.turnTimeoutMs ?? 90000;
    this.specialPowerTimeoutMs = options.specialPowerTimeoutMs ?? 60000;
    this.presenceGraceMs = options.presenceGraceMs ?? 15000;
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

  findConnectedPlayerByUserId(roomCode: string, userId: string): Player | undefined {
    const room = this.rooms.get(roomCode);
    if (!room) return undefined;
    const normalizedUserId = userId.trim();
    const now = this.now();
    return room.players.find(
      (p) =>
        p.isHuman &&
        p.userId?.trim() === normalizedUserId &&
        (p.connected ?? false) &&
        !this.isPlayerStale(p, now)
    );
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
    clientId?: string,
    userId?: string,
    username?: string
  ): Room {
    const normalizedSettings = this.normalizeSettings(settings);
    const roomCode = this.generateRoomCode();
    const expiresAt = this.now() + this.roomTtlMs;
    const room = createRoomModel(
      roomCode,
      hostSocketId,
      normalizedSettings,
      expiresAt,
      userId?.trim()
    );

    const hostPlayer = createPlayer(
      hostSocketId,
      playerName || 'Hôte',
      true,
      0,
      undefined,
      undefined,
      clientId,
      userId,
      username
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
    clientId?: string,
    userId?: string,
    username?: string
  ): {
    room?: Room;
    player?: Player;
    error?: string;
    previousSocketId?: string;
  } {
    const room = this.rooms.get(roomCode);
    if (!room) {
      return { error: 'Room introuvable' };
    }

    this.pruneWaitingRoom(room);
    // NOTE: ensureHost is called AFTER identity matching below,
    // so a reconnecting host is restored before any host transfer.

    const normalizedUserId = userId?.trim();
    const normalizedUsername = username?.trim().toLowerCase();
    const normalizedClientId = clientId?.trim();

    // Vérifier si le joueur a été BANNI (pas juste kické)
    if (normalizedClientId && room.bannedClientIds?.has(normalizedClientId)) {
      return { error: 'Vous avez été banni de cette room' };
    }

    const matchesIdentity = (player: Player): boolean => {
      if (!player.isHuman) return false;
      if (normalizedUserId) {
        return player.userId?.trim() == normalizedUserId;
      }
      if (normalizedUsername) {
        return player.username?.trim().toLowerCase() == normalizedUsername;
      }
      if (normalizedClientId) {
        return player.clientId?.trim() == normalizedClientId;
      }
      return false;
    };

    const existing = room.players.find(matchesIdentity);
    if (existing) {
      // Allow rejoining even if playing
      const previousId = existing.id;
      existing.id = socketId;
      if (playerName) {
        existing.name = playerName;
      }
      if (normalizedUsername) {
        existing.username = normalizedUsername;
      }
      if (normalizedUserId) {
        existing.userId = normalizedUserId;
      }
      if (normalizedClientId) {
        existing.clientId = normalizedClientId;
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

      // Restore host status using persistent identity.
      // Priority: room creator always gets host back, then old socket match,
      // then fallback if current host is stale/disconnected.
      const isCreator = normalizedUserId && room.creatorUserId === normalizedUserId;
      const wasHost = room.hostPlayerId === previousId;
      const hostPlayerStale = !room.players.some(
        (p) => p.id === room.hostPlayerId && p.connected
      );
      if (isCreator || wasHost || hostPlayerStale) {
        room.hostPlayerId = socketId;
      }

      this.ensureHost(room);
      this.touchRoom(room);
      return { room, player: existing, previousSocketId: previousId !== socketId ? previousId : undefined };
    }

    // For new players, ensure host is valid before adding them
    this.ensureHost(room);

    // Si la partie est en cours, on rejoint comme SPECTATEUR
    const isSpectator = (room.status !== RoomStatus.waiting && room.status !== RoomStatus.ended);

    const maxPlayers =
      typeof room.settings?.maxPlayers === 'number'
        ? room.settings.maxPlayers
        : 6;

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
      normalizedClientId,
      normalizedUserId,
      normalizedUsername
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
        gamePlayer.isSpectator = true; // Sync with GameState
        gamePlayer.hasFolded = true; // Also mark as folded for round logic

        // Traquer l'ordre d'élimination pour le classement de fin de partie
        if (!room.gameState.eliminatedPlayerIds) {
          room.gameState.eliminatedPlayerIds = [];
        }
        if (!room.gameState.eliminatedPlayerIds.includes(playerId)) {
          room.gameState.eliminatedPlayerIds.push(playerId);
        }

        this.clearPresenceCheck(roomCode, playerId);
        this.clearTurnTimer(roomCode);

        // Notifier tout le monde que le joueur abandonne
        this.io.to(roomCode).emit('player:forfeit', {
          roomCode,
          playerId,
          playerName: player.name,
          message: `${player.name} a abandonné la partie.`
        });

        // Check if only one active player remains ("Last Man Standing")
        const activeCount = this.activePlayerCount(room);
        if (activeCount <= 1) {
          // Game ends — handleGameEnd broadcasts GAME_ENDED + presence
          this.touchRoom(room);
          this.broadcastGameState(roomCode, 'PLAYER_FORFEIT', { playerId });
          this.broadcastPresence(roomCode);
          this.handleGameEnd(roomCode);
          return true;
        } else if (getCurrentPlayer(room.gameState).id === playerId) {
          this.forceEndTurn(roomCode, `${player.name} a abandonné.`);
        }
      }
    }

    this.touchRoom(room);
    this.broadcastGameState(roomCode, 'PLAYER_FORFEIT', { playerId });
    this.broadcastPresence(roomCode);
    return true;
  }

  startGame(roomCode: string, options: { fillBots?: boolean } = {}): boolean {
    const room = this.rooms.get(roomCode);
    if (!room) return false;

    this.pruneWaitingRoom(room);
    // Ne garder que les joueurs PRÊTS (humains connectés et prêts, ou bots)
    room.players = room.players.filter((p) => {
      if (!p.isHuman) return true; // Garder les bots
      return p.connected !== false && p.ready; // Humains: connectés ET prêts
    });
    this.reindexPlayers(room);
    this.ensureHost(room);

    const minPlayers =
      typeof room.settings?.minPlayers === 'number'
        ? room.settings.minPlayers
        : 2;
    const maxPlayers =
      typeof room.settings?.maxPlayers === 'number'
        ? room.settings.maxPlayers
        : 6;
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

    // Déterminer le nombre de bots à ajouter
    let targetPlayerCount = maxPlayers;
    if (room.settings.numberOfBots !== undefined) {
      // Nombre de bots spécifié explicitement
      targetPlayerCount = Math.min(
        room.players.length + room.settings.numberOfBots,
        maxPlayers
      );
    } else if (!fillBots) {
      // Ne pas ajouter de bots
      targetPlayerCount = room.players.length;
    }

    // Ajouter les bots jusqu'au nombre cible
    const sbmmLevels = room.settings.sbmmBotLevels;
    let botIndex = 0;
    while (room.players.length < targetPlayerCount) {
      if (sbmmLevels && botIndex < sbmmLevels.length) {
        // SBMM : chaque bot a son propre skill level
        room.players.push(this.createBotWithSkill(room.players.length, sbmmLevels[botIndex] as BotSkillLevel));
      } else {
        room.players.push(this.createBot(room.players.length, difficulty));
      }
      botIndex++;
    }

    const gameState = createGameState(room.players, room.gameMode, difficulty);
    GameLogic.initializeGame(gameState);

    // Si le joueur tiré au sort est le même qu'à la partie précédente, on re-tire parmi les autres
    if (room.lastStartingPlayerId && gameState.players.length > 1) {
      const currentStarter = gameState.players[gameState.currentPlayerIndex];
      if (currentStarter.id === room.lastStartingPlayerId) {
        const otherIndexes = gameState.players
          .map((_, i) => i)
          .filter(i => gameState.players[i].id !== room.lastStartingPlayerId);
        if (otherIndexes.length > 0) {
          gameState.currentPlayerIndex = otherIndexes[Math.floor(Math.random() * otherIndexes.length)];
          const newStarter = gameState.players[gameState.currentPlayerIndex];
          console.log(`🎲 Re-tirage (${currentStarter.name} déjà commencé) → ${newStarter.name}`);
        }
      }
    }
    room.lastStartingPlayerId = gameState.players[gameState.currentPlayerIndex].id;

    // Stay in setup phase until all humans complete memorization
    gameState.phase = GamePhase.setup;
    gameState.readyPlayerIds = [];

    room.gameState = gameState;
    room.status = RoomStatus.playing;
    // Don't start turn timer yet - wait for all players to be ready
    this.touchRoom(room);
    return true;
  }

  /**
   * Mark a player as ready after memorization.
   * When all human players are ready, transition to playing phase.
   */
  markPlayerReady(roomCode: string, playerId: string): boolean {
    const room = this.rooms.get(roomCode);
    if (!room || !room.gameState) return false;

    const gameState = room.gameState;

    // Only works during setup phase
    if (gameState.phase !== GamePhase.setup) return false;

    // Don't add duplicates
    if (gameState.readyPlayerIds.includes(playerId)) return true;

    gameState.readyPlayerIds.push(playerId);

    // Check if all human players are ready
    const humanPlayers = gameState.players.filter(p => p.isHuman && !p.isSpectator);
    const allReady = humanPlayers.every(p => gameState.readyPlayerIds.includes(p.id));

    if (allReady) {
      // Transition to playing phase
      gameState.phase = GamePhase.playing;
      this.clearTurnTimer(roomCode);

      // Notify all players that game is starting
      this.io.to(roomCode).emit('game:all_ready', {
        message: 'Tous les joueurs sont prêts !',
      });

      // Si c'est le tour d'un bot, lancer son tour
      // Sinon, démarrer le timer pour le joueur humain
      const currentPlayer = getCurrentPlayer(gameState);
      if (!currentPlayer.isHuman) {
        // Lancer le tour du bot après un court délai
        setTimeout(() => this.checkAndPlayBotTurn(roomCode), 500);
      } else {
        this.startTurnTimer(roomCode);
      }
    }

    this.touchRoom(room);
    this.broadcastGameState(roomCode, 'PLAYER_READY', {
      readyPlayerId: playerId,
      readyCount: gameState.readyPlayerIds.length,
      totalHumans: humanPlayers.length,
      allReady,
    });

    // Éviter que le joueur ne soit marqué comme inactif juste après avoir envoyé "Prêt"
    this.touchPlayer(playerId);

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
    // Arrêter le timer de tour quand la phase de réaction commence
    this.clearTurnTimer(roomCode);
    this.timerManager.startReactionTimer(roomCode, durationMs);
  }



  clearReactionTimer(roomCode: string) {
    this.timerManager.clearTimer(roomCode);
  }

  pauseGame(roomCode: string, pausedByPlayerId: string, pausedByName: string) {
    const room = this.rooms.get(roomCode);
    if (!room || !room.gameState) return;
    if (room.isPaused) return;

    room.isPaused = true;
    room.pausedByPlayerId = pausedByPlayerId;
    room.pausedByName = pausedByName;
    room.pauseStartTime = Date.now();

    this.clearTurnTimer(roomCode);
    this.timerManager.pauseTimer(roomCode);

    // Warning à 60s : "sera expulsé dans 30 secondes"
    const warn1 = setTimeout(() => {
      const r = this.rooms.get(roomCode);
      if (!r || !r.isPaused || r.pausedByPlayerId !== pausedByPlayerId) return;
      this.io.to(roomCode).emit('game:pause_warning', {
        roomCode,
        pausedBy: pausedByName,
        secondsRemaining: 30,
        message: `${pausedByName} sera expulsé dans 30 secondes s'il ne lève pas la pause.`,
      });
    }, 60_000);

    // Warning à 75s : "sera expulsé dans 15 secondes"
    const warn2 = setTimeout(() => {
      const r = this.rooms.get(roomCode);
      if (!r || !r.isPaused || r.pausedByPlayerId !== pausedByPlayerId) return;
      this.io.to(roomCode).emit('game:pause_warning', {
        roomCode,
        pausedBy: pausedByName,
        secondsRemaining: 15,
        message: `${pausedByName} sera expulsé dans 15 secondes s'il ne lève pas la pause.`,
      });
    }, 75_000);

    // Kick + auto-resume à 90s
    const kick = setTimeout(() => {
      const r = this.rooms.get(roomCode);
      if (!r || !r.isPaused || r.pausedByPlayerId !== pausedByPlayerId) return;
      console.log(`⏱️ Pause timeout: kick de ${pausedByName} (${pausedByPlayerId})`);
      // Lever la pause d'abord (sans broadcast séparé, resumeGame va broadcaster)
      r.pauseTimeoutHandle = undefined;
      this.markSpectator(roomCode, pausedByPlayerId, 'pause trop longue');
      // Si le joueur n'était plus dans la room après kick, la pause est déjà levée
      // Sinon on force la reprise
      if (r.isPaused) {
        this.resumeGame(roomCode, pausedByPlayerId, 'Système', true);
      }
    }, 90_000);

    // On stocke les 3 handles dans un seul pour nettoyer facilement
    // On les encapsule dans un handle composite via clearTimeout multiple
    room.pauseTimeoutHandle = kick as ReturnType<typeof setTimeout>;
    // Store warn handles on the kick handle object (hack simple)
    (kick as any)._warn1 = warn1;
    (kick as any)._warn2 = warn2;

    this.broadcastGameState(roomCode, 'GAME_PAUSED', {
      pausedBy: pausedByName,
      pausedByPlayerId,
      pauseDeadline: room.pauseStartTime + 90_000,
    });
  }

  resumeGame(roomCode: string, resumedByPlayerId: string, resumedByName: string, forced = false) {
    const room = this.rooms.get(roomCode);
    if (!room || !room.gameState) return;
    if (!room.isPaused) return;

    // Seul le joueur qui a mis pause peut lever la pause (sauf si forced par le système)
    if (!forced && room.pausedByPlayerId && room.pausedByPlayerId !== resumedByPlayerId) {
      console.log(`🚫 ${resumedByName} tente de lever la pause mais ce n'est pas lui qui l'a mise`);
      return;
    }

    // Annuler les timers de warning + kick
    const handle = room.pauseTimeoutHandle;
    if (handle !== undefined) {
      clearTimeout(handle);
      if ((handle as any)._warn1) clearTimeout((handle as any)._warn1);
      if ((handle as any)._warn2) clearTimeout((handle as any)._warn2);
    }

    room.isPaused = false;
    room.pausedByPlayerId = undefined;
    room.pausedByName = undefined;
    room.pauseStartTime = undefined;
    room.pauseTimeoutHandle = undefined;

    if (room.gameState.phase === GamePhase.playing || room.gameState.phase === GamePhase.specialPower) {
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

    room.gameState.lastSpiedCard = null;
    room.gameState.reactionStartTime = null;

    // S'il y a des pouvoirs en attente (matchs pendant la réaction), les résoudre
    if (room.gameState.pendingMatchPowers.length > 0) {
      await this.processPendingMatchPowers(roomCode);
      return;
    }

    room.gameState.phase = GamePhase.playing;
    GameLogic.nextPlayer(room.gameState);
    this.broadcastGameState(roomCode, 'PHASE_CHANGE');

    await this.checkAndPlayBotTurn(roomCode);
  }

  /**
   * Résout les pouvoirs en attente suite à des matchs pendant la réaction.
   * Attribution aléatoire d'un numéro d'ordre, puis résolution séquentielle.
   */
  async processPendingMatchPowers(roomCode: string) {
    const room = this.rooms.get(roomCode);
    if (!room || !room.gameState) return;

    const pending = room.gameState.pendingMatchPowers;
    if (pending.length === 0) {
      // Plus de pouvoirs → avancer au tour suivant
      room.gameState.phase = GamePhase.playing;
      GameLogic.nextPlayer(room.gameState);
      this.broadcastGameState(roomCode, 'PHASE_CHANGE');
      await this.checkAndPlayBotTurn(roomCode);
      return;
    }

    // Un seul pouvoir en attente → pas besoin de loterie, activer directement
    if (pending.length === 1) {
      pending[0].drawNumber = 1;
      this.activateNextPendingPower(roomCode);
      return;
    }

    // Attribuer des numéros aléatoires pour l'ordre
    const numbers = Array.from({ length: pending.length }, (_, i) => i + 1);
    for (let i = numbers.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [numbers[i], numbers[j]] = [numbers[j], numbers[i]];
    }
    for (let i = 0; i < pending.length; i++) {
      pending[i].drawNumber = numbers[i];
    }
    // Trier par numéro (plus petit en premier)
    pending.sort((a, b) => (a.drawNumber ?? 0) - (b.drawNumber ?? 0));

    // Broadcast les numéros pour affichage de la loterie
    this.broadcastGameState(roomCode, 'MATCH_POWER_LOTTERY');

    // Petit délai pour que les joueurs voient les numéros
    await this.delay(2000);

    // Activer le premier pouvoir
    this.activateNextPendingPower(roomCode);
  }

  /**
   * Active le prochain pouvoir en attente dans la queue
   */
  activateNextPendingPower(roomCode: string) {
    const room = this.rooms.get(roomCode);
    if (!room || !room.gameState) return;

    const pending = room.gameState.pendingMatchPowers;
    if (pending.length === 0) {
      // Plus de pouvoirs → avancer au tour suivant
      room.gameState.specialPowerPlayerId = null;
      room.gameState.phase = GamePhase.playing;
      GameLogic.nextPlayer(room.gameState);
      this.broadcastGameState(roomCode, 'PHASE_CHANGE');
      void this.checkAndPlayBotTurn(roomCode);
      return;
    }

    // Prendre le premier pouvoir
    const power = pending.shift()!;
    const now = Date.now();
    room.gameState.phase = GamePhase.specialPower;
    room.gameState.isWaitingForSpecialPower = true;
    room.gameState.specialCardToActivate = power.card;
    room.gameState.specialPowerPlayerId = power.playerId;
    room.gameState.specialPowerStartTime = now;
    room.gameState.turnStartTime = now;
    room.gameState.turnTimeoutMs = 60000;

    this.broadcastGameState(roomCode, 'ACTION_RESULT');

    // Si c'est un bot, auto-résoudre
    const player = room.gameState.players.find(p => p.id === power.playerId);
    if (player && !player.isHuman) {
      setTimeout(() => {
        const currentRoom = this.rooms.get(roomCode);
        if (!currentRoom?.gameState) return;
        if (currentRoom.gameState.phase !== GamePhase.specialPower) return;
        if (currentRoom.gameState.specialPowerPlayerId !== power.playerId) return;
        GameLogic.skipSpecialPower(currentRoom.gameState);
        this.broadcastGameState(roomCode, 'ACTION_RESULT');
        this.activateNextPendingPower(roomCode);
      }, 800);
    } else {
      // Joueur humain : démarrer le timer de pouvoir
      this.startMatchPowerTimer(roomCode, power.playerId);
    }
  }

  /**
   * Timer pour un pouvoir de match (similaire à startTurnTimer mais pour specialPowerPlayerId)
   */
  startMatchPowerTimer(roomCode: string, playerId: string) {
    this.clearTurnTimer(roomCode);

    const timer = setTimeout(() => {
      const room = this.rooms.get(roomCode);
      if (!room?.gameState) return;
      if (room.gameState.phase !== GamePhase.specialPower) return;
      if (room.gameState.specialPowerPlayerId !== playerId) return;
      this.actionTimers.delete(roomCode);

      GameLogic.skipSpecialPower(room.gameState);
      this.broadcastGameState(roomCode, 'ACTION_RESULT', {
        message: '⏱️ Pouvoir spécial expiré (60s) : pouvoir ignoré.',
      });
      this.activateNextPendingPower(roomCode);
    }, this.specialPowerTimeoutMs);

    this.actionTimers.set(roomCode, timer);
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

      // Si le bot a déclenché un pouvoir spécial, l'utiliser automatiquement
      if (this.currentPhase(gameState) === GamePhase.specialPower) {
        this.broadcastGameState(roomCode, 'PARTIAL_UPDATE');
        await this.delay(800);
        await BotAI.useBotSpecialPower(gameState);
        // Le bot a utilisé son pouvoir mais n'a pas transitionné la phase.
        // Appliquer la même logique que skipSpecialPower/useSpecialPower :
        GameLogic.startReactionPhase(gameState);
      }

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

    // Calculer les scores de carte de cette manche pour chaque joueur
    const playersWithScores = room.gameState.players.map((player) => ({
      player,
      cardScore: calculateScore(player),
    }));

    // Séparer les joueurs éliminés et non-éliminés
    const eliminatedIds = room.gameState.eliminatedPlayerIds || [];
    const activePlayers = playersWithScores.filter(p => !eliminatedIds.includes(p.player.id));
    const eliminatedPlayers = playersWithScores.filter(p => eliminatedIds.includes(p.player.id));

    // Trier les actifs par score de cartes (le plus bas est le meilleur)
    // En cas d'égalité, si l'un d'eux a appelé le Dutch, il gagne l'égalité (il passe devant, donc score considéré plus petit temporairement dans le tri)
    const dutchCallerId = room.gameState.dutchCallerId;

    activePlayers.sort((a, b) => {
      const diff = a.cardScore - b.cardScore;
      if (diff !== 0) return diff;

      // En cas d'égalité de score de cartes
      if (a.player.id === dutchCallerId) return -1; // Le caller gagne l'égalité
      if (b.player.id === dutchCallerId) return 1;  // Le caller gagne l'égalité
      return 0; // Vraie égalité
    });

    // Trier les éliminés par ordre inverse d'élimination (le premier éliminé est le pire)
    eliminatedPlayers.sort((a, b) => {
      const indexA = eliminatedIds.indexOf(a.player.id);
      const indexB = eliminatedIds.indexOf(b.player.id);
      return indexB - indexA; // Le dernier éliminé (index max) est "meilleur" que le premier éliminé
    });

    const sortedPlayers = [...activePlayers, ...eliminatedPlayers];
    const totalPlayers = playersWithScores.length;

    // Déterminer qui a le meilleur score (pour vérifier si le Dutch a réussi)
    // Le gagnant de la manche est la première personne du tableau `sortedPlayers`
    const roundWinner = sortedPlayers.length > 0 ? sortedPlayers[0].player.id : null;
    const isDutchSuccessful = dutchCallerId ? roundWinner === dutchCallerId : false;

    // Calculer les rangs et appliquer pénalités Dutch
    // Calculer les rangs avec égalités
    const ranks: Map<string, number> = new Map();
    let currentRank = 1;

    for (let i = 0; i < sortedPlayers.length; i++) {
      const pId = sortedPlayers[i].player.id;

      if (eliminatedIds.includes(pId)) {
        currentRank = i + 1; // Les éliminés prennent la place exacte restante
      } else if (i > 0 &&
        !eliminatedIds.includes(sortedPlayers[i - 1].player.id) &&
        sortedPlayers[i].cardScore > sortedPlayers[i - 1].cardScore) {
        currentRank = i + 1;
      }
      ranks.set(pId, currentRank);
    }

    // Calculer les points RP de BASE selon la position (en se calquant sur le rang Bronze du client par défaut).
    // Sur le client, des bonus supplémentaires (série de victoires, rang exact du joueur) seront appliqués
    // mais pour le classement du salon (points bruts gagnés pendant la session), on utilise la base.
    const getRPForRank = (rank: number, totalPlayers: number): number => {
      const points = {
        win: 30,
        second: 15,
        third: -25,
        last: -50,
      };

      let baseRP = 0;
      const playerMultiplier = 1.0 + (totalPlayers - 2) * 0.2;

      if (rank === 1) {
        baseRP = points.win;
      } else if (rank === totalPlayers) {
        baseRP = points.last;
      } else if (totalPlayers === 4) {
        if (rank === 2) baseRP = points.second;
        else baseRP = points.third;
      } else if (totalPlayers === 3) {
        baseRP = Math.round((points.second + points.third) / 2);
      } else if (totalPlayers === 5) {
        if (rank === 2) baseRP = points.second;
        else if (rank === 3) baseRP = points.third;
        else baseRP = Math.floor((points.third + points.last) / 2);
      } else if (totalPlayers === 6) {
        if (rank === 2) baseRP = points.second;
        else if (rank === 3) baseRP = points.third;
        else if (rank === 4) baseRP = Math.floor((points.third + points.last) / 2);
        else baseRP = Math.floor((points.third + points.last * 2) / 3);
      } else {
        baseRP = points.last;
      }

      baseRP = Math.round(baseRP * playerMultiplier);

      // Bonus/Malus tournoi omis ici car géré globalement ou par manche sur le client
      return baseRP;
    };

    // Générer les scores finaux avec RP
    const roundScores = playersWithScores.map(({ player, cardScore }) => {
      const rank = ranks.get(player.id) || totalPlayers;
      let rpChange = getRPForRank(rank, totalPlayers);

      // Bonus/Malus Dutch
      if (player.id === dutchCallerId) {
        if (isDutchSuccessful) {
          rpChange += 20; // Bonus Dutch gagné (+20 RP)
          // Bonus main vide (perfect Dutch)
          if (player.hand.length === 0) {
            rpChange += 30; // Bonus supplémentaire (+30 RP) = +50 RP au total
          }
        } else {
          rpChange -= 30; // Malus Dutch raté (-30 RP)
        }
      }

      return {
        playerId: player.id,
        clientId: player.clientId,
        name: player.name,
        cardScore, // Score de cartes (somme) (Affiché coté client)
        rank,
        rpChange, // Points gagnés/perdus cette manche pour le classement global
        hand: player.hand,
        calledDutch: player.id === dutchCallerId,
      };
    });

    // Calculer et stocker les scores cumulés via RP (plus haut gagne)
    this.updateCumulativeScoresWithRP(room, roundScores);

    room.status = RoomStatus.ended;
    room.gameState.phase = GamePhase.ended;

    // Tous les humains connectés sont sur l'écran de résultats
    room.playersInResults = new Set(
      room.players.filter((p) => p.isHuman && p.connected).map((p) => p.id)
    );

    this.clearTurnTimer(roomCode);
    this.broadcastGameState(roomCode, 'GAME_ENDED', {
      message: 'Partie terminée !',
      roundScores, // Scores de cette manche (points bruts + rpChange)
      cumulativeScores: this.getCumulativeScoresArray(room),
    });
    this.broadcastPresence(roomCode);
  }

  /**
   * Retour au salon : n'importe quel joueur peut appeler.
   * Retire le joueur de playersInResults.
   * Quand plus personne n'est sur les résultats → reset la room.
   */
  backToLobby(roomCode: string, playerId: string): boolean {
    const room = this.rooms.get(roomCode);
    if (!room) return false;
    if (room.status !== RoomStatus.ended) return false;

    room.playersInResults?.delete(playerId);
    this.tryResetEndedRoom(room, roomCode);

    return true;
  }

  /**
   * Si plus personne n'est sur les résultats, remet la room en waiting.
   */
  private tryResetEndedRoom(room: Room, roomCode: string) {
    if (room.status !== RoomStatus.ended) return;
    if (room.playersInResults && room.playersInResults.size > 0) return;

    // En mode tournoi, déléguer à restartGame pour appliquer la logique
    // d'élimination et d'incrémentation du round
    if (room.gameMode === GameMode.tournament) {
      this.ensureHost(room);
      if (room.hostPlayerId) {
        this.restartGame(roomCode, room.hostPlayerId);
      }
      return;
    }

    // Plus personne sur les résultats → reset complet (mode rapide)
    room.players = room.players.filter((p) => p.isHuman);
    room.players.forEach((p) => {
      p.ready = false;
      p.hand = [];
      p.hasFolded = false;
      p.knownCards = [];
      p.isSpectator = false;
    });

    room.status = RoomStatus.waiting;
    room.gameState = null;
    room.playersInResults = undefined;

    this.reindexPlayers(room);
    this.ensureHost(room);
    this.touchRoom(room);
    this.broadcastPresence(roomCode);
  }

  /**
   * Redémarre une partie (rematch) - garde les joueurs et scores cumulés
   * En mode tournoi: élimine le dernier du classement
   */
  restartGame(roomCode: string, requesterId: string): boolean {
    const room = this.rooms.get(roomCode);
    if (!room) return false;

    // Seul l'hôte peut relancer
    if (room.hostPlayerId !== requesterId) return false;

    // La partie doit être terminée
    if (room.status !== RoomStatus.ended) return false;

    // En mode tournoi, gérer l'élimination
    let eliminatedPlayerId: string | null = null;
    if (room.gameMode === GameMode.tournament && room.gameState) {
      // Calculer le classement final (score le plus bas = meilleur)
      const ranking = [...room.gameState.players]
        .filter(p => !room.gameState!.eliminatedPlayerIds.includes(p.id))
        .sort((a, b) => calculateScore(a) - calculateScore(b));

      // S'il reste plus de 2 joueurs, éliminer le dernier
      if (ranking.length > 2) {
        const eliminated = ranking[ranking.length - 1];
        eliminatedPlayerId = eliminated.id;
        console.log(`🏆 Tournoi ${roomCode}: ${eliminated.name} éliminé (score: ${calculateScore(eliminated)})`);
      } else if (ranking.length <= 2) {
        // C'était la finale, le tournoi est terminé
        console.log(`🏆 Tournoi ${roomCode} terminé! Gagnant: ${ranking[0]?.name}`);
      }
    }

    // Remove bots so we can refill them or play just humans
    // En mode tournoi, aussi retirer le joueur éliminé
    room.players = room.players.filter((p) => {
      if (!p.isHuman) return false; // Toujours retirer les bots
      if (room.gameMode === GameMode.tournament && p.id === eliminatedPlayerId) {
        // Notifier le joueur éliminé
        this.io.to(p.id).emit('tournament:eliminated', {
          roomCode,
          message: 'Vous avez été éliminé du tournoi !',
          finalRank: room.players.filter(pl => pl.isHuman).length,
        });
        return false; // Retirer le joueur éliminé
      }
      return true;
    });

    // Vérifier qu'il reste assez de joueurs pour continuer
    const humanCount = room.players.filter(p => p.isHuman).length;
    if (room.gameMode === GameMode.tournament && humanCount < 2) {
      // Pas assez de joueurs, le tournoi est terminé
      this.io.to(roomCode).emit('tournament:ended', {
        roomCode,
        message: 'Tournoi terminé !',
        winner: room.players[0]?.name || 'Inconnu',
      });
      // Ne pas relancer, garder le status 'ended'
      return false;
    }

    room.status = RoomStatus.waiting;
    room.gameState = null;

    room.players.forEach(p => {
      p.ready = false;
      p.hand = [];
      p.hasFolded = false;
      p.knownCards = [];
      p.isSpectator = false;
      // Re-mark connected players as non-spectator (forfeited players rejoin lobby)
    });

    this.reindexPlayers(room);
    this.ensureHost(room);

    // Incrémenter le round si mode tournoi
    if (room.gameMode === GameMode.tournament) {
      room.tournamentRound = (room.tournamentRound || 1) + 1;
    }

    this.touchRoom(room);
    this.broadcastPresence(roomCode);

    this.io.to(roomCode).emit('room:restarted', {
      roomCode,
      message: room.gameMode === GameMode.tournament
        ? `Manche ${room.tournamentRound} !`
        : 'Nouvelle partie !',
      cumulativeScores: this.getCumulativeScoresArray(room),
      tournamentRound: room.tournamentRound,
      eliminatedPlayerId,
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

    // Notifier le joueur qu'il est kické (peut revenir)
    this.io.to(target.id).emit('room:kicked', {
      roomCode,
      message: "Vous avez été exclu de la room par l'hôte",
      canRejoin: true, // Le joueur PEUT revenir
    });

    // Si la partie est en cours, gérer proprement le retrait du gameState
    if (room.status === RoomStatus.playing && room.gameState) {
      this.removePlayerFromActiveRoom(roomCode, target.id, {
        removeReason: `${target.name} a été exclu par l'hôte.`,
      });
      return true;
    }

    // Retirer le joueur (mais ne pas le bannir - il peut revenir)
    room.playersInResults?.delete(target.id);
    room.players.splice(targetIndex, 1);
    this.reindexPlayers(room);

    this.touchRoom(room);
    this.broadcastPresence(roomCode);

    // Si plus personne sur les résultats → reset la room
    this.tryResetEndedRoom(room, roomCode);

    return true;
  }

  /**
   * Bannir un joueur définitivement (hôte uniquement)
   */
  banPlayer(
    roomCode: string,
    hostId: string,
    targetClientId: string
  ): boolean {
    const room = this.rooms.get(roomCode);
    if (!room) return false;

    // Seul l'hôte peut bannir
    if (room.hostPlayerId !== hostId) return false;

    // Trouver le joueur à bannir par clientId
    const targetIndex = room.players.findIndex(
      (p) => p.clientId === targetClientId
    );
    if (targetIndex < 0) return false;

    const target = room.players[targetIndex];

    // On ne peut pas se bannir soi-même
    if (target.id === hostId) return false;

    // Notifier le joueur qu'il est banni (ne peut PAS revenir)
    this.io.to(target.id).emit('room:banned', {
      roomCode,
      message: "Vous avez été banni de cette room par l'hôte",
      canRejoin: false,
    });

    // Ajouter le clientId à la liste des bannis
    if (target.clientId) {
      if (!room.bannedClientIds) {
        room.bannedClientIds = new Set();
      }
      room.bannedClientIds.add(target.clientId);
    }

    // Si la partie est en cours, gérer proprement le retrait du gameState
    if (room.status === RoomStatus.playing && room.gameState) {
      this.removePlayerFromActiveRoom(roomCode, target.id, {
        removeReason: `${target.name} a été banni par l'hôte.`,
      });
      return true;
    }

    // Retirer le joueur
    room.playersInResults?.delete(target.id);
    room.players.splice(targetIndex, 1);
    this.reindexPlayers(room);

    this.touchRoom(room);
    this.broadcastPresence(roomCode);

    // Si plus personne sur les résultats → reset la room
    this.tryResetEndedRoom(room, roomCode);

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
      room.cumulativeScores.set(scoreKey, Math.max(0, currentScore + roundScore));
    }
  }

  /**
   * Met à jour les scores cumulés avec le système RP (points de classement)
   */
  private updateCumulativeScoresWithRP(
    room: Room,
    roundScores: Array<{
      playerId: string;
      clientId?: string;
      rpChange: number;
    }>
  ): void {
    if (!room.cumulativeScores) {
      room.cumulativeScores = new Map<string, number>();
    }

    for (const score of roundScores) {
      const scoreKey = score.clientId || score.playerId;
      const currentScore = room.cumulativeScores.get(scoreKey) || 0;
      room.cumulativeScores.set(scoreKey, Math.max(0, currentScore + score.rpChange));
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

    // Trier par score décroissant (le PLUS HAUT score (RP) est le meilleur)
    result.sort((a, b) => {
      const diff = b.score - a.score;
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
    // Note: Le timer n'est plus réinitialisé après chaque action.
    // Il démarre au début du tour et se termine à la phase de réaction.
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

    // Après confirmation de présence : seulement 15s pour jouer (pas le timer complet)
    const extensionMs = 15000;
    this.clearTurnTimer(roomCode);

    if (room.gameState && (room.gameState.phase === GamePhase.playing || room.gameState.phase === GamePhase.specialPower)) {
      room.gameState.turnStartTime = this.now();
      room.gameState.turnTimeoutMs = extensionMs;

      const currentPlayer = room.gameState.players[room.gameState.currentPlayerIndex];
      if (currentPlayer && currentPlayer.id === socketId) {
        const timer = setTimeout(() => {
          const currentRoom = this.rooms.get(roomCode);
          if (!currentRoom || !currentRoom.gameState) return;
          const stillCurrent = currentRoom.gameState.players[currentRoom.gameState.currentPlayerIndex]?.id === socketId;
          if (!stillCurrent) return;
          this.actionTimers.delete(roomCode);
          // Éjection directe après l'extension
          this.markSpectator(roomCode, socketId, 'Temps écoulé après avertissement');
        }, extensionMs);
        this.actionTimers.set(roomCode, timer);
      }

      this.broadcastGameState(roomCode, 'PRESENCE_CONFIRMED', {
        message: '⏱️ 15 secondes pour jouer !',
      });
    }

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

    if (room.status === RoomStatus.waiting || room.status === RoomStatus.ended) {
      // In waiting or ended state: clean removal (player leaves for real)
      room.playersInResults?.delete(socketId);
      room.players.splice(index, 1);
      if (room.players.length === 0 ||
          room.players.filter(p => p.isHuman).length === 0) {
        this.removeRoom(roomCode);
        return;
      }
      this.reindexPlayers(room);
      if (room.hostPlayerId === socketId) {
        this.ensureHost(room);
      }
      // Si plus personne sur les résultats → reset la room
      this.tryResetEndedRoom(room, roomCode);
    } else {
      // In playing state: mark as spectator (game still running)
      this.removePlayerFromActiveRoom(roomCode, leaving.id, {
        removeReason: `${leaving.name} a quitté la partie.`,
      });
      return;
    }

    this.touchRoom(room);
    this.broadcastPresence(roomCode);
    if (room.gameState) {
      this.broadcastGameState(roomCode, 'PLAYER_LEFT');
    }

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

  /**
   * Retire un joueur des autres rooms avant un nouveau join.
   * Empêche les doublons cross-room quand le socket/client réutilise une session.
   */
  detachIdentityFromOtherRooms(
    targetRoomCode: string,
    params: { socketId: string; userId?: string; username?: string; clientId?: string }
  ) {
    const normalizedTarget = targetRoomCode.toUpperCase();
    const userId = params.userId?.trim();
    const username = params.username?.trim().toLowerCase();
    const clientId = params.clientId?.trim();

    const matchesIdentity = (player: Player): boolean => {
      if (!player.isHuman) return false;
      if (player.id === params.socketId) return true;
      if (userId && player.userId?.trim() === userId) return true;
      if (!userId && username && player.username?.trim().toLowerCase() === username) {
        return true;
      }
      if (!userId && !username && clientId && player.clientId?.trim() === clientId) {
        return true;
      }
      return false;
    };

    const leaves: Array<{ roomCode: string; playerId: string }> = [];
    for (const room of this.rooms.values()) {
      if (room.id.toUpperCase() === normalizedTarget) continue;
      for (const player of room.players) {
        if (matchesIdentity(player)) {
          leaves.push({ roomCode: room.id, playerId: player.id });
        }
      }
    }

    for (const leave of leaves) {
      this.handleLeave(leave.roomCode, leave.playerId);
    }
  }

  checkGameEndCondition(roomCode: string) {
    const room = this.rooms.get(roomCode);
    if (!room || !room.gameState) return;
    if (room.gameState.phase === GamePhase.ended) return;
    if (room.gameState.phase === GamePhase.setup) return; // Don't end during setup

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
    if (room.gameState.phase !== GamePhase.playing && room.gameState.phase !== GamePhase.specialPower) return;
    if (this.presenceChecks.has(roomCode)) return;

    const currentPlayer = getCurrentPlayer(room.gameState);
    if (!currentPlayer.isHuman || currentPlayer.isSpectator) return;

    this.clearTurnTimer(roomCode);

    // Si le jeu est en pause, on ne lance pas le timer maintenant
    if (room.isPaused) return;

    const waitingSpecialPower = room.gameState.phase === GamePhase.specialPower;
    const timeoutMs = waitingSpecialPower
      ? this.specialPowerTimeoutMs
      : this.turnTimeoutMs;

    // Mettre à jour les infos de timer dans le gameState pour l'affichage client
    room.gameState.turnStartTime = this.now();
    room.gameState.turnTimeoutMs = timeoutMs;

    this.broadcastGameState(roomCode, 'TIMER_UPDATE');

    const playerId = currentPlayer.id;

    const timer = setTimeout(() => {
      const currentRoom = this.rooms.get(roomCode);
      if (!currentRoom || !currentRoom.gameState) return;
      const currentGameState = currentRoom.gameState;
      const stillCurrent = getCurrentPlayer(currentGameState).id === playerId;
      if (!stillCurrent) return;
      this.actionTimers.delete(roomCode);
      if (currentGameState.phase === GamePhase.specialPower) {
        GameLogic.skipSpecialPower(currentGameState);
        const timeoutSeconds = Math.round(this.specialPowerTimeoutMs / 1000);
        this.broadcastGameState(roomCode, 'ACTION_RESULT', {
          message: `⏱️ Pouvoir spécial expiré (${timeoutSeconds}s) : pouvoir ignoré.`,
        });

        const phaseAfterSkip = currentGameState.phase as GamePhase;
        if (phaseAfterSkip === GamePhase.ended) {
          this.handleGameEnd(roomCode);
          return;
        }

        if (phaseAfterSkip === GamePhase.reaction) {
          const reactionTime =
            typeof currentRoom.settings?.reactionTimeMs === 'number'
              ? currentRoom.settings.reactionTimeMs
              : 3000;
          this.startReactionTimer(roomCode, reactionTime);
          return;
        }

        void this.checkAndPlayBotTurn(roomCode);
        return;
      }

      this.triggerPresenceCheck(roomCode, playerId, 'Temps de jeu écoulé');
    }, timeoutMs);

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

  triggerPresenceCheck(
    roomCode: string,
    playerId: string,
    reason: string,
    options?: { deadlineMs?: number; sendPush?: boolean }
  ) {
    const room = this.rooms.get(roomCode);
    if (!room) return;
    const player = room.players.find((p) => p.id === playerId);
    if (!player || player.isSpectator) return;
    if (this.presenceChecks.get(roomCode)?.playerId === playerId) return;

    const deadlineMs = options?.deadlineMs ?? this.presenceGraceMs;
    const deadlineAt = this.now() + deadlineMs;
    this.presenceChecks.set(roomCode, { playerId, deadlineAt });

    this.io.to(player.id).emit('presence:check', {
      reason,
      deadlineMs,
    });

    if (options?.sendPush && player.userId) {
      PushNotificationService.sendToUser(player.userId, {
        title: 'Tu es toujours là ?',
        body: 'La partie t\'attend ! Reviens vite ou tu seras expulsé(e).',
        data: { type: 'presence_check', roomCode }
      }).catch(console.error);
    }

    const key = `${roomCode}:${playerId}`;
    const existing = this.presenceTimers.get(key);
    if (existing) clearTimeout(existing);

    const timer = setTimeout(() => {
      const current = this.presenceChecks.get(roomCode);
      if (!current || current.playerId !== playerId) return;
      this.markSpectator(roomCode, playerId, 'Inactif');
    }, deadlineMs);

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

  private removePlayerFromGameState(roomCode: string, playerId: string, removeReason: string) {
    const room = this.rooms.get(roomCode);
    if (!room?.gameState) return;
    const gameState = room.gameState;

    const playerIndex = gameState.players.findIndex((p) => p.id === playerId);
    if (playerIndex < 0) return;

    const wasCurrentPlayer = playerIndex === gameState.currentPlayerIndex;
    const phaseBeforeRemoval = gameState.phase;

    const gamePlayer = gameState.players[playerIndex];
    gamePlayer.hasFolded = true;
    gamePlayer.isSpectator = true;
    if (!gameState.eliminatedPlayerIds.includes(playerId)) {
      gameState.eliminatedPlayerIds.push(playerId);
    }

    // On ne retire surtout pas le joueur du tableau gameState.players
    // car cela fausserait l'indexation pour les tours suivants 
    // et empêcherait de le classer à la fin.
    gameState.readyPlayerIds = gameState.readyPlayerIds.filter((id) => id !== playerId);

    if ((phaseBeforeRemoval === GamePhase.playing || phaseBeforeRemoval === GamePhase.specialPower) && wasCurrentPlayer) {
      this.clearTurnTimer(roomCode);
      this.forceEndTurn(roomCode, removeReason);
    }
  }

  private removePlayerFromActiveRoom(
    roomCode: string,
    playerId: string,
    options: { removeReason: string }
  ) {
    const room = this.rooms.get(roomCode);
    if (!room) return;

    const player = room.players.find((p) => p.id === playerId);
    if (!player) return;

    this.clearPresenceCheck(roomCode, playerId);

    this.removePlayerFromGameState(roomCode, playerId, options.removeReason);

    const roomIndex = room.players.findIndex((p) => p.id === playerId);
    if (roomIndex >= 0) {
      if (room.status === RoomStatus.waiting || room.status === RoomStatus.ended) {
        // En attente ou partie terminée : retirer complètement le joueur
        room.players.splice(roomIndex, 1);
      } else {
        room.players[roomIndex].isSpectator = true;
        room.players[roomIndex].ready = false;
        room.players[roomIndex].connected = false;
      }
    }

    // Retirer des résultats si présent
    room.playersInResults?.delete(playerId);

    // On compte seulement les joueurs non-spectateurs (s'il y en a) pour détruire la room
    const activeHumanPlayers = room.players.filter(p => p.isHuman && !p.isSpectator);
    if (room.players.length === 0 || activeHumanPlayers.length === 0) {
      this.removeRoom(roomCode);
      return;
    }

    // Si plus personne sur les résultats → reset la room
    this.tryResetEndedRoom(room, roomCode);

    if (room.status !== RoomStatus.playing && !room.isPaused) {
      this.reindexPlayers(room);
    }

    this.ensureHost(room);
    this.touchRoom(room);

    this.broadcastPresence(roomCode);
    this.broadcastGameState(roomCode, 'PLAYER_LEFT', { playerId });
    this.checkGameEndCondition(roomCode);
  }

  markSpectator(roomCode: string, playerId: string, reason: string) {
    const room = this.rooms.get(roomCode);
    if (!room) return;
    const player = room.players.find((p) => p.id === playerId);
    if (!player || player.isSpectator) return;

    const removeReason = `${player.name} a été retiré de la partie (${reason}).`;

    this.io.to(player.id).emit('room:kicked', {
      roomCode,
      message: `Retiré pour inactivité: ${reason}. Vous pouvez rejoindre une nouvelle partie.`,
      canRejoin: true,
    });

    // Notifier tous les joueurs qu'un joueur est devenu AFK/spectateur
    this.io.to(roomCode).emit('player:afk', {
      playerId: player.id,
      playerName: player.name,
      reason,
      roomCode,
    });

    this.removePlayerFromActiveRoom(roomCode, playerId, {
      removeReason,
    });
  }

  private forceEndTurn(roomCode: string, reason: string) {
    const room = this.rooms.get(roomCode);
    if (!room || !room.gameState) return;
    const gameState = room.gameState;

    if (gameState.phase === GamePhase.specialPower) {
      GameLogic.skipSpecialPower(gameState);
    } else if (gameState.drawnCard) {
      GameLogic.discardDrawnCard(gameState);
      if ((gameState.phase as GamePhase) === GamePhase.specialPower) {
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

  /**
   * Ajoute un joueur invité (déconnecté) dans une room en attente.
   * Retourne le Player créé, ou null si impossible.
   */
  addInvitedPlayer(
    roomCode: string,
    userId: string,
    username: string,
    displayName: string
  ): Player | null {
    const room = this.rooms.get(roomCode);
    if (!room) return null;
    if (room.status !== RoomStatus.waiting) return null;

    // Déjà dedans ?
    if (room.players.some((p) => p.isHuman && p.userId?.trim() === userId.trim())) {
      return null;
    }

    const maxPlayers =
      typeof room.settings?.maxPlayers === 'number'
        ? room.settings.maxPlayers
        : 6;
    if (this.activePlayerCount(room) >= maxPlayers) return null;

    const position = room.players.length;
    const player = createPlayer(
      `invited-${userId}`,
      displayName,
      true,
      position,
      undefined,
      undefined,
      undefined,
      userId.trim(),
      username.trim().toLowerCase()
    );
    player.connected = false;
    player.focused = false;
    player.ready = false;

    room.players.push(player);
    this.reindexPlayers(room);
    this.touchRoom(room);
    this.broadcastPresence(roomCode);

    return player;
  }

  private activePlayerCount(room: Room): number {
    const now = this.now();
    return room.players.filter((player) => {
      if (player.isSpectator) return false;
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

      // Keep registered players (with clientId) much longer (5 minutes)
      // to allow app restart/rejoin
      const timeout = player.clientId ? 300000 : this.stalePlayerMs * 2;
      return now - lastSeen <= timeout;
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

      if (!anyConnected) {
        // No short inactivity auto-delete: keep room available until TTL/admin action.
        if (!room.emptyAt) {
          room.emptyAt = now;
        }

        if (now >= room.expiresAt) {
          this.removeRoom(room.id);
          continue;
        }
      } else {
        // Activity detected, clear grace period
        room.emptyAt = undefined;

        if (now >= room.expiresAt) {
          this.removeRoom(room.id);
          continue;
        }
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
   * Récupère les rooms actives où le joueur est présent (par userId ou clientId)
   */
  getActiveRoomsForMember(
    params: { userId?: string; username?: string; clientId?: string }
  ): Array<{ roomCode: string; status: string; playerCount: number; isHost: boolean }> {
    const userId = params.userId?.trim();
    const username = params.username?.trim().toLowerCase();
    const clientId = params.clientId?.trim();
    if (!userId && !username && !clientId) {
      return [];
    }

    const matchesMember = (player: Player): boolean => {
      if (!player.isHuman) return false;
      if (userId && player.userId === userId) return true;
      if (!userId && username && player.username?.trim().toLowerCase() === username) {
        return true;
      }
      if (!userId && !username && clientId && player.clientId === clientId) return true;
      return false;
    };

    const result: Array<{
      roomCode: string;
      status: string;
      playerCount: number;
      isHost: boolean;
    }> = [];

    for (const room of this.rooms.values()) {
      if (room.status === RoomStatus.closing) {
        continue;
      }

      const isMember = room.players.some(matchesMember);
      if (!isMember) {
        continue;
      }

      const host = room.players.find((p) => p.id === room.hostPlayerId);
      const isHost = host ? matchesMember(host) : false;

      result.push({
        roomCode: room.id,
        status: room.status,
        playerCount: this.activePlayerCount(room),
        isHost,
      });
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
   * Met à jour les paramètres de la room (hôte uniquement, en lobby)
   */
  updateRoomSettings(
    roomCode: string,
    socketId: string,
    settings: { botDifficulty?: number; luckDifficulty?: number }
  ): boolean {
    const room = this.rooms.get(roomCode);
    if (!room || room.status !== RoomStatus.waiting) return false;
    if (room.hostPlayerId !== socketId) return false;

    // Mettre à jour les paramètres
    if (settings.botDifficulty !== undefined) {
      room.settings.botDifficulty = settings.botDifficulty as Difficulty;
    }
    if (settings.luckDifficulty !== undefined) {
      room.settings.luckDifficulty = settings.luckDifficulty as Difficulty;
    }

    // Notifier tous les joueurs du changement
    this.io.to(roomCode).emit('room:settings_updated', {
      roomCode,
      settings: room.settings,
    });

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

    // Précharger la prochaine carte du deck pour le joueur actuel
    // Cela permet d'éliminer la latence perçue lors de la pioche
    const currentPlayer = gameState.players[gameState.currentPlayerIndex];
    if (currentPlayer?.id === playerId &&
      gameState.deck.length > 0 &&
      gameState.phase === GamePhase.playing &&
      !gameState.drawnCard) {
      // Envoyer la carte du dessus du deck (celle qui sera piochée)
      state.preloadedDeckCard = gameState.deck[gameState.deck.length - 1];
    } else {
      state.preloadedDeckCard = null;
    }

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
    const desiredSkill = this.getDesiredSkillLevel(difficulty);
    const selected = this.selectCastingBot(position, desiredSkill);

    if (selected) {
      return {
        id: selected.botId,
        name: selected.botName || selected.botId,
        isHuman: false,
        connected: true,
        focused: true,
        isSpectator: false,
        botBehavior: selected.botBehavior,
        botSkillLevel: selected.botSkillLevel,
        position,
        hand: [],
        knownCards: [],
      };
    }

    // Fallback : ancien comportement
    const botNames = ['Alice', 'Bob', 'Charlie', 'Diana'];
    const behaviors = [
      BotBehavior.balanced,
      BotBehavior.aggressive,
      BotBehavior.fast,
    ];
    const behavior = behaviors[position % behaviors.length];

    return {
      id: `bot_${position}`,
      name: botNames[position] || `Bot ${position}`,
      isHuman: false,
      connected: true,
      focused: true,
      isSpectator: false,
      botBehavior: behavior,
      botSkillLevel: desiredSkill,
      position,
      hand: [],
      knownCards: [],
    };
  }

  private getDesiredSkillLevel(difficulty: Difficulty): BotSkillLevel {
    switch (difficulty) {
      case Difficulty.easy:
        return BotSkillLevel.bronze;
      case Difficulty.hard:
        return BotSkillLevel.platinum;
      default:
        return BotSkillLevel.silver;
    }
  }

  // Crée un bot avec un BotSkillLevel spécifique (utilisé par le SBMM)
  private createBotWithSkill(position: number, skillLevel: BotSkillLevel): Player {
    const botNames = ['Alice', 'Bob', 'Charlie', 'Diana', 'Eve'];
    const behaviors = [
      BotBehavior.balanced,
      BotBehavior.aggressive,
      BotBehavior.fast,
    ];
    const behavior = behaviors[position % behaviors.length];

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

  private loadBotCastingCacheIfNeeded(): void {
    const now = this.now();
    if (this.botCastingCache && now - this.botCastingCacheLoadedAtMs < 15000) {
      return;
    }

    try {
      // Même convention de chemin que BotLearningService (services -> ../../data/bot-learning)
      const profilesDir = path.join(__dirname, '../../data/bot-learning/profiles');
      if (!fs.existsSync(profilesDir)) {
        this.botCastingCache = [];
        this.botCastingCacheLoadedAtMs = now;
        return;
      }

      const files = fs
        .readdirSync(profilesDir)
        .filter((f) => f.endsWith('.json'));

      const profiles: Array<{
        botId: string;
        botName?: string;
        behavior?: string;
        skillLevel?: string;
        mmr?: number;
      }> = [];

      for (const file of files) {
        try {
          const raw = fs.readFileSync(path.join(profilesDir, file), 'utf-8');
          const parsed = JSON.parse(raw);
          if (!parsed || typeof parsed.botId !== 'string') continue;
          profiles.push({
            botId: parsed.botId,
            botName: parsed.botName,
            behavior: parsed.behavior,
            skillLevel: parsed.skillLevel,
            mmr: typeof parsed.mmr === 'number' ? parsed.mmr : undefined,
          });
        } catch {
          // Ignorer un fichier corrompu
        }
      }

      // Trier par MMR décroissant (bots forts en premier)
      profiles.sort((a, b) => (b.mmr ?? 0) - (a.mmr ?? 0));

      this.botCastingCache = profiles;
      this.botCastingCacheLoadedAtMs = now;
    } catch {
      this.botCastingCache = [];
      this.botCastingCacheLoadedAtMs = now;
    }
  }

  private selectCastingBot(
    position: number,
    desiredSkill: BotSkillLevel
  ): { botId: string; botName?: string; botBehavior: BotBehavior; botSkillLevel: BotSkillLevel } | null {
    this.loadBotCastingCacheIfNeeded();
    if (!this.botCastingCache || this.botCastingCache.length === 0) return null;

    // Casting persistant: on privilégie les bots déjà forts (MMR élevé),
    // indépendamment du skillLevel "déclaratif".
    // Ainsi, si Oscar/Jack deviennent forts, ils reviennent naturellement.
    const pool = this.botCastingCache;
    const picked = pool[position % pool.length];
    if (!picked) return null;

    // Convert behavior/skillLevel strings en enums serveur
    const behavior =
      picked.behavior === 'fast'
        ? BotBehavior.fast
        : picked.behavior === 'aggressive'
          ? BotBehavior.aggressive
          : BotBehavior.balanced;

    const skillLevel =
      picked.skillLevel === 'platinum'
        ? BotSkillLevel.platinum
        : picked.skillLevel === 'gold'
          ? BotSkillLevel.gold
          : picked.skillLevel === 'silver'
            ? BotSkillLevel.silver
            : BotSkillLevel.bronze;

    // Si le profil n'a pas de skillLevel, on retombe sur celui attendu par la difficulté
    const resolvedSkillLevel = picked.skillLevel ? skillLevel : desiredSkill;

    return {
      botId: picked.botId,
      botName: picked.botName,
      botBehavior: behavior,
      botSkillLevel: resolvedSkillLevel,
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
      typeof settings?.maxPlayers === 'number' ? settings.maxPlayers : 6;
    let minPlayers = Math.max(2, Math.min(6, minPlayersRaw));
    let maxPlayers = Math.max(2, Math.min(6, maxPlayersRaw));
    if (maxPlayers < minPlayers) {
      maxPlayers = minPlayers;
    }
    const fillBots = settings?.fillBots !== false;
    const isPublic = settings?.isPublic === true;

    return {
      gameMode,
      botDifficulty,
      luckDifficulty,
      reactionTimeMs,
      minPlayers,
      maxPlayers,
      fillBots,
      isPublic,
    };
  }

  private parseGameMode(value: any): GameMode {
    if (value === GameMode.tournament || value === 1 || value === 'tournament') {
      return GameMode.tournament;
    }
    return GameMode.quick;
  }

  private getBotDifficulty(settings: GameSettings): Difficulty {
    // Le client Flutter calculera la difficulté SBMM et l'enverra dans botDifficulty
    // Si useSBMM est true, le client aura déjà calculé la difficulté recommandée
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
