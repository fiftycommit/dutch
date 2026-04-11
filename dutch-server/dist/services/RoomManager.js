"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.RoomManager = void 0;
const fs = __importStar(require("node:fs"));
const path = __importStar(require("node:path"));
const GameLogic_1 = require("./GameLogic");
const BotAI_1 = require("./BotAI");
const GameState_1 = require("../models/GameState");
const Player_1 = require("../models/Player");
const Room_1 = require("../models/Room");
const TimerManager_1 = require("./TimerManager");
const PushNotificationService_1 = require("./PushNotificationService");
class RoomManager {
    getIO() {
        return this.io;
    }
    constructor(io, options = {}) {
        this.io = io;
        this.rooms = new Map();
        this.actionTimers = new Map();
        this.presenceTimers = new Map();
        this.presenceChecks = new Map();
        this.cleanupTimer = null;
        this.botCastingCache = null;
        this.botCastingCacheLoadedAtMs = 0;
        this.turnTimeoutMs = options.turnTimeoutMs ?? 90000;
        this.specialPowerTimeoutMs = options.specialPowerTimeoutMs ?? 60000;
        this.presenceGraceMs = options.presenceGraceMs ?? 15000;
        this.roomTtlMs = options.roomTtlMs ?? 2 * 60 * 60 * 1000;
        this.cleanupIntervalMs = options.cleanupIntervalMs ?? 10000;
        this.stalePlayerMs = options.stalePlayerMs ?? 15000;
        this.now = options.now ?? (() => Date.now());
        this.timerManager = new TimerManager_1.TimerManager({
            getRoom: (roomCode) => this.getRoom(roomCode),
            broadcastGameState: (roomCode, updateType, data) => this.broadcastGameState(roomCode, updateType, data),
            endReactionPhase: (roomCode) => this.endReactionPhase(roomCode),
        });
        this.startCleanupLoop();
    }
    getRoom(roomCode) {
        return this.rooms.get(roomCode);
    }
    findConnectedPlayerByUserId(roomCode, userId) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return undefined;
        const normalizedUserId = userId.trim();
        const now = this.now();
        return room.players.find((p) => p.isHuman &&
            p.userId?.trim() === normalizedUserId &&
            (p.connected ?? false) &&
            !this.isPlayerStale(p, now));
    }
    getRoomCount() {
        return this.rooms.size;
    }
    listRooms() {
        return Array.from(this.rooms.values()).map((room) => ({
            id: room.id,
            playerCount: this.activePlayerCount(room),
            status: room.status,
            gameMode: GameState_1.GameMode[room.gameMode],
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
    createRoom(hostSocketId, settings, playerName, clientId, userId, username) {
        const normalizedSettings = this.normalizeSettings(settings);
        const roomCode = this.generateRoomCode();
        const expiresAt = this.now() + this.roomTtlMs;
        const room = (0, Room_1.createRoom)(roomCode, hostSocketId, normalizedSettings, expiresAt, userId?.trim());
        const hostPlayer = (0, Player_1.createPlayer)(hostSocketId, playerName || 'Hôte', true, 0, undefined, undefined, clientId, userId, username);
        hostPlayer.connected = true;
        hostPlayer.focused = true;
        hostPlayer.lastSeenAt = this.now();
        room.players.push(hostPlayer);
        this.touchRoom(room);
        this.rooms.set(roomCode, room);
        return room;
    }
    joinRoom(roomCode, socketId, playerName, clientId, userId, username) {
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
        const matchesIdentity = (player) => {
            if (!player.isHuman)
                return false;
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
            if (pendingCheck?.playerId === previousId) {
                this.clearPresenceCheck(roomCode, previousId);
            }
            // Restore host status using persistent identity.
            // Priority: room creator always gets host back, then old socket match,
            // then fallback if current host is stale/disconnected.
            const isCreator = normalizedUserId && room.creatorUserId === normalizedUserId;
            const wasHost = room.hostPlayerId === previousId;
            const hostPlayerStale = !room.players.some((p) => p.id === room.hostPlayerId && p.connected);
            if (isCreator || wasHost || hostPlayerStale) {
                room.hostPlayerId = socketId;
            }
            this.ensureHost(room);
            this.touchRoom(room);
            return { room, player: existing, previousSocketId: previousId === socketId ? undefined : previousId };
        }
        // For new players, ensure host is valid before adding them
        this.ensureHost(room);
        // Si la partie est en cours, on rejoint comme SPECTATEUR
        const isSpectator = (room.status !== Room_1.RoomStatus.waiting && room.status !== Room_1.RoomStatus.ended);
        const maxPlayers = typeof room.settings?.maxPlayers === 'number'
            ? room.settings.maxPlayers
            : 6;
        // Si on n'est pas spectateur et que c'est plein -> Erreur
        if (!isSpectator && this.activePlayerCount(room) >= maxPlayers) {
            return { error: 'Room pleine' };
        }
        const player = (0, Player_1.createPlayer)(socketId, playerName || `Joueur ${room.players.length + 1}`, true, room.players.length, undefined, undefined, normalizedClientId, normalizedUserId, normalizedUsername);
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
    notifyPlayerJoined(roomCode, player) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return;
        this.io.to(roomCode).emit('room:player_joined', {
            roomCode,
            player,
            playerCount: this.activePlayerCount(room),
        });
    }
    /**
     * Abandonner la partie en cours (sans quitter la room)
     */
    forfeitGame(roomCode, playerId) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return false;
        // Trouver le joueur
        const player = room.players.find(p => p.id === playerId);
        if (!player)
            return false;
        // Si partie en cours, on le marque comme "Folded"
        if (room.status === Room_1.RoomStatus.playing && room.gameState) {
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
                }
                else if ((0, GameState_1.getCurrentPlayer)(room.gameState).id === playerId) {
                    this.forceEndTurn(roomCode, `${player.name} a abandonné.`);
                }
            }
        }
        this.touchRoom(room);
        this.broadcastGameState(roomCode, 'PLAYER_FORFEIT', { playerId });
        this.broadcastPresence(roomCode);
        return true;
    }
    startGame(roomCode, options = {}) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return false;
        this.pruneWaitingRoom(room);
        const preservedTournamentSpectators = room.gameMode === GameState_1.GameMode.tournament
            ? room.players.filter((p) => p.isHuman && p.isSpectator)
            : [];
        const readyHumans = room.players.filter((p) => p.isHuman && !p.isSpectator && p.connected !== false && p.ready);
        room.players = [...readyHumans, ...preservedTournamentSpectators];
        this.reindexPlayers(room);
        this.ensureHost(room);
        const minPlayers = typeof room.settings?.minPlayers === 'number'
            ? room.settings.minPlayers
            : 2;
        const maxPlayers = typeof room.settings?.maxPlayers === 'number'
            ? room.settings.maxPlayers
            : 6;
        const fillBots = options.fillBots ?? (room.settings?.fillBots !== false);
        const host = room.players.find((p) => p.id === room.hostPlayerId);
        if (!host || host.connected === false)
            return false;
        if (!host.ready)
            return false;
        if (readyHumans.length < minPlayers)
            return false;
        if (this.activePlayerCount(room) > maxPlayers)
            return false;
        const difficulty = this.getBotDifficulty(room.settings);
        // Déterminer le nombre de bots à ajouter
        let targetPlayerCount = maxPlayers;
        if (room.settings.numberOfBots !== undefined) {
            // Nombre de bots spécifié explicitement
            targetPlayerCount = Math.min(readyHumans.length + room.settings.numberOfBots, maxPlayers);
        }
        else if (!fillBots) {
            // Ne pas ajouter de bots
            targetPlayerCount = readyHumans.length;
        }
        const activePlayers = [...readyHumans];
        // Ajouter les bots jusqu'au nombre cible
        const sbmmLevels = room.settings.sbmmBotLevels;
        let botIndex = 0;
        while (activePlayers.length < targetPlayerCount) {
            let bot;
            if (sbmmLevels && botIndex < sbmmLevels.length) {
                // SBMM : chaque bot a son propre skill level
                bot = this.createBotWithSkill(room.players.length, sbmmLevels[botIndex]);
            }
            else {
                bot = this.createBot(room.players.length, difficulty);
            }
            room.players.push(bot);
            activePlayers.push(bot);
            botIndex++;
        }
        const gameState = (0, GameState_1.createGameState)(activePlayers, room.gameMode, difficulty);
        GameLogic_1.GameLogic.initializeGame(gameState);
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
        gameState.phase = GameState_1.GamePhase.setup;
        gameState.readyPlayerIds = [];
        room.gameState = gameState;
        room.status = Room_1.RoomStatus.playing;
        // Don't start turn timer yet - wait for all players to be ready
        this.touchRoom(room);
        return true;
    }
    /**
     * Mark a player as ready after memorization.
     * When all human players are ready, transition to playing phase.
     */
    markPlayerReady(roomCode, playerId) {
        const room = this.rooms.get(roomCode);
        if (!room?.gameState)
            return false;
        const gameState = room.gameState;
        // Only works during setup phase
        if (gameState.phase !== GameState_1.GamePhase.setup)
            return false;
        // Don't add duplicates
        if (gameState.readyPlayerIds.includes(playerId))
            return true;
        gameState.readyPlayerIds.push(playerId);
        // Check if all human players are ready
        const humanPlayers = gameState.players.filter(p => p.isHuman && !p.isSpectator);
        const allReady = humanPlayers.every(p => gameState.readyPlayerIds.includes(p.id));
        if (allReady) {
            // Transition to playing phase
            gameState.phase = GameState_1.GamePhase.playing;
            this.clearTurnTimer(roomCode);
            // Notify all players that game is starting
            this.io.to(roomCode).emit('game:all_ready', {
                message: 'Tous les joueurs sont prêts !',
            });
            // Si c'est le tour d'un bot, lancer son tour
            // Sinon, démarrer le timer pour le joueur humain
            const currentPlayer = (0, GameState_1.getCurrentPlayer)(gameState);
            if (currentPlayer.isHuman) {
                this.startTurnTimer(roomCode);
            }
            else {
                // Lancer le tour du bot après un court délai
                setTimeout(() => this.checkAndPlayBotTurn(roomCode), 500);
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
    broadcastGameState(roomCode, updateType, additionalData = {}) {
        const room = this.rooms.get(roomCode);
        if (!room?.gameState)
            return;
        this.touchRoom(room);
        room.players.forEach((player) => {
            const personalizedState = this.getPersonalizedState(room.gameState, player.id);
            this.io.to(player.id).emit('game:state_update', {
                type: updateType,
                gameState: personalizedState,
                ...additionalData,
            });
        });
    }
    startReactionTimer(roomCode, durationMs) {
        // Arrêter le timer de tour quand la phase de réaction commence
        this.clearTurnTimer(roomCode);
        this.timerManager.startReactionTimer(roomCode, durationMs);
    }
    clearReactionTimer(roomCode) {
        this.timerManager.clearTimer(roomCode);
    }
    pauseGame(roomCode, pausedByPlayerId, pausedByName) {
        const room = this.rooms.get(roomCode);
        if (!room?.gameState)
            return;
        if (room.isPaused)
            return;
        room.isPaused = true;
        room.pausedByPlayerId = pausedByPlayerId;
        room.pausedByName = pausedByName;
        room.pauseStartTime = Date.now();
        this.clearTurnTimer(roomCode);
        this.timerManager.pauseTimer(roomCode);
        // Warning à 60s : "sera expulsé dans 30 secondes"
        const warn1 = setTimeout(() => {
            const r = this.rooms.get(roomCode);
            if (!r || !r.isPaused || r.pausedByPlayerId !== pausedByPlayerId)
                return;
            this.io.to(roomCode).emit('game:pause_warning', {
                roomCode,
                pausedBy: pausedByName,
                secondsRemaining: 30,
                message: `${pausedByName} sera expulsé dans 30 secondes s'il ne lève pas la pause.`,
            });
        }, 60000);
        // Warning à 75s : "sera expulsé dans 15 secondes"
        const warn2 = setTimeout(() => {
            const r = this.rooms.get(roomCode);
            if (!r || !r.isPaused || r.pausedByPlayerId !== pausedByPlayerId)
                return;
            this.io.to(roomCode).emit('game:pause_warning', {
                roomCode,
                pausedBy: pausedByName,
                secondsRemaining: 15,
                message: `${pausedByName} sera expulsé dans 15 secondes s'il ne lève pas la pause.`,
            });
        }, 75000);
        // Kick + auto-resume à 90s
        const kick = setTimeout(() => {
            const r = this.rooms.get(roomCode);
            if (!r || !r.isPaused || r.pausedByPlayerId !== pausedByPlayerId)
                return;
            console.log(`⏱️ Pause timeout: kick de ${pausedByName} (${pausedByPlayerId})`);
            // Lever la pause d'abord (sans broadcast séparé, resumeGame va broadcaster)
            r.pauseTimeoutHandle = undefined;
            this.markSpectator(roomCode, pausedByPlayerId, 'pause trop longue');
            // Si le joueur n'était plus dans la room après kick, la pause est déjà levée
            // Sinon on force la reprise
            if (r.isPaused) {
                this.resumeGame(roomCode, pausedByPlayerId, 'Système', true);
            }
        }, 90000);
        // On stocke les 3 handles dans un seul pour nettoyer facilement
        // On les encapsule dans un handle composite via clearTimeout multiple
        room.pauseTimeoutHandle = kick;
        // Store warn handles on the kick handle object (hack simple)
        kick._warn1 = warn1;
        kick._warn2 = warn2;
        this.broadcastGameState(roomCode, 'GAME_PAUSED', {
            pausedBy: pausedByName,
            pausedByPlayerId,
            pauseDeadline: room.pauseStartTime + 90000,
        });
    }
    resumeGame(roomCode, resumedByPlayerId, resumedByName, forced = false) {
        const room = this.rooms.get(roomCode);
        if (!room?.gameState)
            return;
        if (!room.isPaused)
            return;
        // Seul le joueur qui a mis pause peut lever la pause (sauf si forced par le système)
        if (!forced && room.pausedByPlayerId && room.pausedByPlayerId !== resumedByPlayerId) {
            console.log(`🚫 ${resumedByName} tente de lever la pause mais ce n'est pas lui qui l'a mise`);
            return;
        }
        // Annuler les timers de warning + kick
        const handle = room.pauseTimeoutHandle;
        if (handle !== undefined) {
            clearTimeout(handle);
            if (handle._warn1)
                clearTimeout(handle._warn1);
            if (handle._warn2)
                clearTimeout(handle._warn2);
        }
        room.isPaused = false;
        room.pausedByPlayerId = undefined;
        room.pausedByName = undefined;
        room.pauseStartTime = undefined;
        room.pauseTimeoutHandle = undefined;
        if (room.gameState.phase === GameState_1.GamePhase.playing || room.gameState.phase === GameState_1.GamePhase.specialPower) {
            this.startTurnTimer(roomCode);
        }
        else if (room.gameState.phase === GameState_1.GamePhase.reaction) {
            this.timerManager.resumeTimer(roomCode);
        }
        this.broadcastGameState(roomCode, 'GAME_RESUMED', { resumedBy: resumedByName });
    }
    async endReactionPhase(roomCode) {
        this.clearReactionTimer(roomCode);
        const room = this.rooms.get(roomCode);
        if (!room?.gameState)
            return;
        room.gameState.lastSpiedCard = null;
        room.gameState.reactionStartTime = null;
        // S'il y a des pouvoirs en attente (matchs pendant la réaction), les résoudre
        if (room.gameState.pendingMatchPowers.length > 0) {
            await this.processPendingMatchPowers(roomCode);
            return;
        }
        room.gameState.phase = GameState_1.GamePhase.playing;
        GameLogic_1.GameLogic.nextPlayer(room.gameState);
        this.broadcastGameState(roomCode, 'PHASE_CHANGE');
        await this.checkAndPlayBotTurn(roomCode);
    }
    /**
     * Résout les pouvoirs en attente suite à des matchs pendant la réaction.
     * Attribution aléatoire d'un numéro d'ordre, puis résolution séquentielle.
     */
    async processPendingMatchPowers(roomCode) {
        const room = this.rooms.get(roomCode);
        if (!room?.gameState)
            return;
        const pending = room.gameState.pendingMatchPowers;
        if (pending.length === 0) {
            // Plus de pouvoirs → avancer au tour suivant
            room.gameState.phase = GameState_1.GamePhase.playing;
            GameLogic_1.GameLogic.nextPlayer(room.gameState);
            this.broadcastGameState(roomCode, 'PHASE_CHANGE');
            await this.checkAndPlayBotTurn(roomCode);
            return;
        }
        // Séparer les pouvoirs passifs (7, 10) des pouvoirs actifs (Valet, Joker).
        // Les passifs ne modifient pas l'état du jeu → pas besoin de tirage d'ordre.
        const passivePowers = pending.filter(p => p.card.value === '7' || p.card.value === '10');
        const activePowers = pending.filter(p => p.card.value !== '7' && p.card.value !== '10');
        // Réorganiser : passifs d'abord (numéro auto), puis actifs
        pending.length = 0;
        let order = 1;
        for (const p of passivePowers) {
            p.drawNumber = order++;
        }
        pending.push(...passivePowers);
        if (activePowers.length === 0) {
            // Que des pouvoirs passifs → résoudre directement, pas de loterie
            this.activateNextPendingPower(roomCode);
            return;
        }
        if (activePowers.length === 1) {
            // Un seul pouvoir actif → pas besoin de loterie
            activePowers[0].drawNumber = order;
            pending.push(...activePowers);
            this.activateNextPendingPower(roomCode);
            return;
        }
        // Plusieurs pouvoirs actifs → loterie pour l'ordre entre eux uniquement
        const numbers = Array.from({ length: activePowers.length }, (_, i) => i + 1);
        for (let i = numbers.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [numbers[i], numbers[j]] = [numbers[j], numbers[i]];
        }
        for (let i = 0; i < activePowers.length; i++) {
            activePowers[i].drawNumber = order + numbers[i] - 1;
        }
        pending.push(...activePowers);
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
    activateNextPendingPower(roomCode) {
        const room = this.rooms.get(roomCode);
        if (!room?.gameState)
            return;
        const pending = room.gameState.pendingMatchPowers;
        if (pending.length === 0) {
            // Plus de pouvoirs → avancer au tour suivant
            room.gameState.specialPowerPlayerId = null;
            room.gameState.phase = GameState_1.GamePhase.playing;
            GameLogic_1.GameLogic.nextPlayer(room.gameState);
            this.broadcastGameState(roomCode, 'PHASE_CHANGE');
            void this.checkAndPlayBotTurn(roomCode);
            return;
        }
        // Prendre le premier pouvoir
        const power = pending.shift();
        const now = Date.now();
        room.gameState.phase = GameState_1.GamePhase.specialPower;
        room.gameState.isWaitingForSpecialPower = true;
        room.gameState.specialCardToActivate = power.card;
        room.gameState.specialPowerPlayerId = power.playerId;
        room.gameState.specialPowerStartTime = now;
        room.gameState.turnStartTime = now;
        room.gameState.turnTimeoutMs = 60000;
        this.broadcastGameState(roomCode, 'ACTION_RESULT');
        // Si c'est un bot, utiliser le pouvoir via BotAI
        const player = room.gameState.players.find(p => p.id === power.playerId);
        if (player && !player.isHuman) {
            setTimeout(async () => {
                const currentRoom = this.rooms.get(roomCode);
                if (!currentRoom?.gameState)
                    return;
                if (currentRoom.gameState.phase !== GameState_1.GamePhase.specialPower)
                    return;
                if (currentRoom.gameState.specialPowerPlayerId !== power.playerId)
                    return;
                // Utiliser le pouvoir via BotAI (au lieu de skip systématique)
                await BotAI_1.BotAI.useBotSpecialPower(currentRoom.gameState);
                this.broadcastGameState(roomCode, 'ACTION_RESULT');
                this.activateNextPendingPower(roomCode);
            }, 800);
        }
        else {
            // Joueur humain : démarrer le timer de pouvoir
            this.startMatchPowerTimer(roomCode, power.playerId);
        }
    }
    /**
     * Timer pour un pouvoir de match (similaire à startTurnTimer mais pour specialPowerPlayerId)
     */
    startMatchPowerTimer(roomCode, playerId) {
        this.clearTurnTimer(roomCode);
        const timer = setTimeout(() => {
            const room = this.rooms.get(roomCode);
            if (!room?.gameState)
                return;
            if (room.gameState.phase !== GameState_1.GamePhase.specialPower)
                return;
            if (room.gameState.specialPowerPlayerId !== playerId)
                return;
            this.actionTimers.delete(roomCode);
            GameLogic_1.GameLogic.skipSpecialPower(room.gameState);
            this.broadcastGameState(roomCode, 'ACTION_RESULT', {
                message: '⏱️ Pouvoir spécial expiré (60s) : pouvoir ignoré.',
            });
            this.activateNextPendingPower(roomCode);
        }, this.specialPowerTimeoutMs);
        this.actionTimers.set(roomCode, timer);
    }
    async checkAndPlayBotTurn(roomCode) {
        const room = this.rooms.get(roomCode);
        if (!room?.gameState)
            return;
        const gameState = room.gameState;
        while (true) {
            if (gameState.phase !== GameState_1.GamePhase.playing)
                break;
            if ((0, GameState_1.getCurrentPlayer)(gameState).isHuman)
                break;
            await this.delay(800);
            await BotAI_1.BotAI.playBotTurn(gameState);
            // Si le bot a déclenché un pouvoir spécial, l'utiliser automatiquement
            if (this.currentPhase(gameState) === GameState_1.GamePhase.specialPower) {
                this.broadcastGameState(roomCode, 'PARTIAL_UPDATE');
                await this.delay(800);
                await BotAI_1.BotAI.useBotSpecialPower(gameState);
                // Le bot a utilisé son pouvoir mais n'a pas transitionné la phase.
                // Appliquer la même logique que skipSpecialPower/useSpecialPower :
                GameLogic_1.GameLogic.startReactionPhase(gameState);
            }
            this.broadcastGameState(roomCode, 'PARTIAL_UPDATE');
            const phase = this.currentPhase(gameState);
            if (phase === GameState_1.GamePhase.ended) {
                this.handleGameEnd(roomCode);
                return;
            }
            if (phase === GameState_1.GamePhase.reaction) {
                const reactionTime = typeof room.settings?.reactionTimeMs === 'number'
                    ? room.settings.reactionTimeMs
                    : 3000;
                this.startReactionTimer(roomCode, reactionTime);
                break;
            }
        }
        if (gameState.phase === GameState_1.GamePhase.playing) {
            this.startTurnTimer(roomCode);
        }
    }
    handleGameEnd(roomCode) {
        const room = this.rooms.get(roomCode);
        if (!room?.gameState)
            return;
        // Calculer les scores de carte de cette manche pour chaque joueur
        const playersWithScores = room.gameState.players.map((player) => ({
            player,
            cardScore: (0, Player_1.calculateScore)(player),
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
            if (diff !== 0)
                return diff;
            // En cas d'égalité de score de cartes
            if (a.player.id === dutchCallerId)
                return -1; // Le caller gagne l'égalité
            if (b.player.id === dutchCallerId)
                return 1; // Le caller gagne l'égalité
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
        const ranks = new Map();
        let currentRank = 1;
        for (let i = 0; i < sortedPlayers.length; i++) {
            const pId = sortedPlayers[i].player.id;
            if (eliminatedIds.includes(pId)) {
                currentRank = i + 1; // Les éliminés prennent la place exacte restante
            }
            else if (i > 0 &&
                !eliminatedIds.includes(sortedPlayers[i - 1].player.id) &&
                sortedPlayers[i].cardScore > sortedPlayers[i - 1].cardScore) {
                currentRank = i + 1;
            }
            ranks.set(pId, currentRank);
        }
        // Calculer les points RP de BASE selon la position (en se calquant sur le rang Bronze du client par défaut).
        // Sur le client, des bonus supplémentaires (série de victoires, rang exact du joueur) seront appliqués
        // mais pour le classement du salon (points bruts gagnés pendant la session), on utilise la base.
        const getRPForRank = (rank, totalPlayers) => {
            const points = {
                win: 30,
                second: 15,
                third: -25,
                last: -50,
            };
            let baseRP = 0;
            const playerMultiplier = 1 + (totalPlayers - 2) * 0.2;
            if (rank === 1) {
                baseRP = points.win;
            }
            else if (rank === totalPlayers) {
                baseRP = points.last;
            }
            else if (totalPlayers === 4) {
                if (rank === 2)
                    baseRP = points.second;
                else
                    baseRP = points.third;
            }
            else if (totalPlayers === 3) {
                baseRP = Math.round((points.second + points.third) / 2);
            }
            else if (totalPlayers === 5) {
                if (rank === 2)
                    baseRP = points.second;
                else if (rank === 3)
                    baseRP = points.third;
                else
                    baseRP = Math.floor((points.third + points.last) / 2);
            }
            else if (totalPlayers === 6) {
                if (rank === 2)
                    baseRP = points.second;
                else if (rank === 3)
                    baseRP = points.third;
                else if (rank === 4)
                    baseRP = Math.floor((points.third + points.last) / 2);
                else
                    baseRP = Math.floor((points.third + points.last * 2) / 3);
            }
            else {
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
                }
                else {
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
        room.status = Room_1.RoomStatus.ended;
        room.gameState.phase = GameState_1.GamePhase.ended;
        // Tous les humains connectés sont sur l'écran de résultats
        room.playersInResults = new Set(room.players.filter((p) => p.isHuman && p.connected).map((p) => p.id));
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
    backToLobby(roomCode, playerId) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return false;
        if (room.status !== Room_1.RoomStatus.ended)
            return false;
        room.playersInResults?.delete(playerId);
        this.tryResetEndedRoom(room, roomCode);
        return true;
    }
    /**
     * Si plus personne n'est sur les résultats, remet la room en waiting.
     */
    tryResetEndedRoom(room, roomCode) {
        if (room.status !== Room_1.RoomStatus.ended)
            return;
        if (room.playersInResults && room.playersInResults.size > 0)
            return;
        // En mode tournoi, déléguer à restartGame pour appliquer la logique
        // d'élimination et d'incrémentation du round
        if (room.gameMode === GameState_1.GameMode.tournament) {
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
        room.status = Room_1.RoomStatus.waiting;
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
    restartGame(roomCode, requesterId) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return false;
        // La partie doit être terminée
        if (room.status !== Room_1.RoomStatus.ended)
            return false;
        const requester = room.players.find((p) => p.id === requesterId);
        const tournamentRequesterAllowed = room.gameMode === GameState_1.GameMode.tournament &&
            requester?.isHuman == true &&
            requester.isSpectator != true;
        // En partie rapide, seul l'hôte peut relancer.
        // En tournoi, n'importe quel survivant peut lancer la manche suivante.
        if (room.hostPlayerId !== requesterId && !tournamentRequesterAllowed) {
            return false;
        }
        // En mode tournoi, gérer l'élimination
        let eliminatedPlayerId = null;
        if (room.gameMode === GameState_1.GameMode.tournament && room.gameState) {
            // Calculer le classement final (score le plus bas = meilleur)
            const ranking = [...room.gameState.players]
                .filter(p => !room.gameState.eliminatedPlayerIds.includes(p.id))
                .sort((a, b) => (0, Player_1.calculateScore)(a) - (0, Player_1.calculateScore)(b));
            if (ranking.length >= 2) {
                const eliminated = ranking[ranking.length - 1];
                eliminatedPlayerId = eliminated.id;
                console.log(`🏆 Tournoi ${roomCode}: ${eliminated.name} éliminé (score: ${(0, Player_1.calculateScore)(eliminated)})`);
                if (ranking.length === 2) {
                    // C'était la finale, le tournoi est terminé après cette élimination
                    console.log(`🏆 Tournoi ${roomCode} terminé! Gagnant: ${ranking[0]?.name}`);
                }
            }
            else if (ranking.length === 1) {
                console.log(`🏆 Tournoi ${roomCode} terminé! Gagnant: ${ranking[0]?.name}`);
            }
        }
        // Toujours retirer les bots entre deux manches.
        room.players = room.players.filter((p) => p.isHuman);
        // En mode tournoi, le joueur éliminé reste dans le salon
        // mais devient spectateur pour les manches suivantes.
        for (const player of room.players) {
            if (room.gameMode === GameState_1.GameMode.tournament && player.id === eliminatedPlayerId) {
                player.isSpectator = true;
                player.ready = false;
                player.hand = [];
                player.hasFolded = false;
                player.knownCards = [];
                this.io.to(player.id).emit('tournament:eliminated', {
                    roomCode,
                    message: 'Vous avez été éliminé du tournoi !',
                    finalRank: room.players.filter((p) => p.isHuman && !p.isSpectator).length + 1,
                });
                continue;
            }
            player.ready = room.gameMode === GameState_1.GameMode.tournament;
            player.hand = [];
            player.hasFolded = false;
            player.knownCards = [];
            player.isSpectator = false;
        }
        // Vérifier qu'il reste assez de joueurs pour continuer
        const remainingActiveHumans = room.players.filter((p) => p.isHuman && !p.isSpectator);
        if (room.gameMode === GameState_1.GameMode.tournament && remainingActiveHumans.length < 2) {
            // Pas assez de joueurs, le tournoi est terminé
            room.playersInResults = undefined;
            this.io.to(roomCode).emit('tournament:ended', {
                roomCode,
                message: 'Tournoi terminé !',
                winner: remainingActiveHumans[0]?.name || 'Inconnu',
            });
            // Ne pas relancer, garder le status 'ended'
            return false;
        }
        room.status = Room_1.RoomStatus.waiting;
        room.gameState = null;
        room.playersInResults = undefined;
        this.reindexPlayers(room);
        this.ensureHost(room);
        // Incrémenter le round si mode tournoi
        if (room.gameMode === GameState_1.GameMode.tournament) {
            room.tournamentRound = (room.tournamentRound || 1) + 1;
        }
        this.touchRoom(room);
        this.broadcastPresence(roomCode);
        this.io.to(roomCode).emit('room:restarted', {
            roomCode,
            message: room.gameMode === GameState_1.GameMode.tournament
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
    kickPlayer(roomCode, hostId, targetClientId) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return false;
        // Seul l'hôte peut kick
        if (room.hostPlayerId !== hostId)
            return false;
        // Trouver le joueur à kick par clientId
        const targetIndex = room.players.findIndex((p) => p.clientId === targetClientId);
        if (targetIndex < 0)
            return false;
        const target = room.players[targetIndex];
        // On ne peut pas se kick soi-même
        if (target.id === hostId)
            return false;
        // Notifier le joueur qu'il est kické (peut revenir)
        this.io.to(target.id).emit('room:kicked', {
            roomCode,
            message: "Vous avez été exclu de la room par l'hôte",
            canRejoin: true, // Le joueur PEUT revenir
        });
        // Si la partie est en cours, gérer proprement le retrait du gameState
        if (room.status === Room_1.RoomStatus.playing && room.gameState) {
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
    banPlayer(roomCode, hostId, targetClientId) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return false;
        // Seul l'hôte peut bannir
        if (room.hostPlayerId !== hostId)
            return false;
        // Trouver le joueur à bannir par clientId
        const targetIndex = room.players.findIndex((p) => p.clientId === targetClientId);
        if (targetIndex < 0)
            return false;
        const target = room.players[targetIndex];
        // On ne peut pas se bannir soi-même
        if (target.id === hostId)
            return false;
        // Notifier le joueur qu'il est banni (ne peut PAS revenir)
        this.io.to(target.id).emit('room:banned', {
            roomCode,
            message: "Vous avez été banni de cette room par l'hôte",
            canRejoin: false,
        });
        // Ajouter le clientId à la liste des bannis
        if (target.clientId) {
            room.bannedClientIds ?? (room.bannedClientIds = new Set());
            room.bannedClientIds.add(target.clientId);
        }
        // Si la partie est en cours, gérer proprement le retrait du gameState
        if (room.status === Room_1.RoomStatus.playing && room.gameState) {
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
    updateCumulativeScores(room) {
        if (!room.gameState)
            return;
        // Initialiser si nécessaire
        room.cumulativeScores ?? (room.cumulativeScores = new Map());
        // Ajouter les scores de cette manche
        for (const player of room.gameState.players) {
            const scoreKey = player.clientId || player.id;
            const currentScore = room.cumulativeScores.get(scoreKey) || 0;
            const roundScore = (0, Player_1.calculateScore)(player);
            room.cumulativeScores.set(scoreKey, Math.max(0, currentScore + roundScore));
        }
    }
    /**
     * Met à jour les scores cumulés avec le système RP (points de classement)
     */
    updateCumulativeScoresWithRP(room, roundScores) {
        room.cumulativeScores ?? (room.cumulativeScores = new Map());
        for (const score of roundScores) {
            const scoreKey = score.clientId || score.playerId;
            const currentScore = room.cumulativeScores.get(scoreKey) || 0;
            room.cumulativeScores.set(scoreKey, Math.max(0, currentScore + score.rpChange));
        }
    }
    /**
     * Retourne les scores cumulés sous forme de tableau
     */
    getCumulativeScoresArray(room) {
        if (!room.cumulativeScores)
            return [];
        const result = [];
        room.cumulativeScores.forEach((score, clientId) => {
            const player = room.players.find((p) => p.clientId === clientId || p.id === clientId);
            result.push({
                clientId,
                score,
                name: player?.name || 'Joueur',
            });
        });
        // Trier par score décroissant (le PLUS HAUT score (RP) est le meilleur)
        result.sort((a, b) => {
            const diff = b.score - a.score;
            if (diff !== 0)
                return diff;
            // En cas d'égalité, le joueur encore en ligne/actif gagne (est considéré meilleur = premier)
            const pA = room.players.find(p => p.clientId === a.clientId || p.id === a.clientId);
            const pB = room.players.find(p => p.clientId === b.clientId || p.id === b.clientId);
            const aActive = pA && pA.connected && !pA.isSpectator;
            const bActive = pB && pB.connected && !pB.isSpectator;
            if (aActive && !bActive)
                return -1; // a gagne
            if (!aActive && bActive)
                return 1; // b gagne
            return 0;
        });
        return result;
    }
    setReady(roomCode, socketId, ready) {
        const room = this.rooms.get(roomCode);
        if (room?.status !== Room_1.RoomStatus.waiting)
            return false;
        const player = room.players.find((p) => p.id === socketId);
        if (!player || !player.isHuman || player.isSpectator)
            return false;
        player.ready = ready;
        player.connected = true;
        player.lastSeenAt = this.now();
        this.touchRoom(room);
        this.broadcastPresence(roomCode);
        return true;
    }
    sendChat(roomCode, socketId, rawMessage) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return false;
        const player = room.players.find((p) => p.id === socketId);
        if (!player || player.isSpectator)
            return false;
        const message = rawMessage?.toString().trim();
        if (!message)
            return false;
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
    touchPlayer(socketId) {
        const now = this.now();
        for (const room of this.rooms.values()) {
            const player = room.players.find((p) => p.id === socketId);
            if (!player)
                continue;
            player.lastSeenAt = now;
            player.connected = true;
            this.touchRoom(room);
        }
    }
    recordPlayerAction(roomCode, playerId) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return;
        const player = room.players.find((p) => p.id === playerId);
        if (player) {
            player.lastSeenAt = this.now();
            player.connected = true;
        }
        this.touchRoom(room);
        const pending = this.presenceChecks.get(roomCode);
        if (pending?.playerId === playerId) {
            this.clearPresenceCheck(roomCode, playerId);
        }
        // Note: Le timer n'est plus réinitialisé après chaque action.
        // Il démarre au début du tour et se termine à la phase de réaction.
    }
    updateFocus(roomCode, socketId, focused) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return;
        const player = room.players.find((p) => p.id === socketId);
        if (!player)
            return;
        player.focused = focused;
        player.connected = true;
        player.lastSeenAt = this.now();
        this.touchRoom(room);
        this.broadcastPresence(roomCode);
    }
    confirmPresence(roomCode, socketId) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return;
        const player = room.players.find((p) => p.id === socketId);
        if (!player)
            return;
        this.clearPresenceCheck(roomCode, player.id);
        player.connected = true;
        player.lastSeenAt = this.now();
        this.touchRoom(room);
        // Après confirmation de présence : seulement 15s pour jouer (pas le timer complet)
        const extensionMs = 15000;
        this.clearTurnTimer(roomCode);
        if (room.gameState && (room.gameState.phase === GameState_1.GamePhase.playing || room.gameState.phase === GameState_1.GamePhase.specialPower)) {
            room.gameState.turnStartTime = this.now();
            room.gameState.turnTimeoutMs = extensionMs;
            const currentPlayer = room.gameState.players[room.gameState.currentPlayerIndex];
            if (currentPlayer?.id === socketId) {
                const timer = setTimeout(() => {
                    const currentRoom = this.rooms.get(roomCode);
                    if (!currentRoom?.gameState)
                        return;
                    const stillCurrent = currentRoom.gameState.players[currentRoom.gameState.currentPlayerIndex]?.id === socketId;
                    if (!stillCurrent)
                        return;
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
    handleLeave(roomCode, socketId) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return;
        const index = room.players.findIndex((p) => p.id === socketId);
        if (index < 0)
            return;
        const leaving = room.players[index];
        this.clearPresenceCheck(roomCode, socketId);
        // Notifier les autres joueurs que ce joueur quitte
        this.io.to(roomCode).emit('player:left', {
            playerId: leaving.id,
            playerName: leaving.name,
            roomCode,
        });
        if (room.status === Room_1.RoomStatus.waiting || room.status === Room_1.RoomStatus.ended) {
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
        }
        else {
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
    handleDisconnect(socketId) {
        for (const room of this.rooms.values()) {
            const player = room.players.find((p) => p.id === socketId);
            if (!player)
                continue;
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
    detachIdentityFromOtherRooms(targetRoomCode, params) {
        const normalizedTarget = targetRoomCode.toUpperCase();
        const userId = params.userId?.trim();
        const username = params.username?.trim().toLowerCase();
        const clientId = params.clientId?.trim();
        const matchesIdentity = (player) => {
            if (!player.isHuman)
                return false;
            if (player.id === params.socketId)
                return true;
            if (userId && player.userId?.trim() === userId)
                return true;
            if (!userId && username && player.username?.trim().toLowerCase() === username) {
                return true;
            }
            if (!userId && !username && clientId && player.clientId?.trim() === clientId) {
                return true;
            }
            return false;
        };
        const leaves = [];
        for (const room of this.rooms.values()) {
            if (room.id.toUpperCase() === normalizedTarget)
                continue;
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
    checkGameEndCondition(roomCode) {
        const room = this.rooms.get(roomCode);
        if (!room?.gameState)
            return;
        if (room.gameState.phase === GameState_1.GamePhase.ended)
            return;
        if (room.gameState.phase === GameState_1.GamePhase.setup)
            return; // Don't end during setup
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
        const activePlayers = room.players.filter(p => (p.isHuman ? (p.connected && !p.isSpectator) : true));
        if (activePlayers.length < 2) {
            this.handleGameEnd(roomCode);
        }
    }
    broadcastPresence(roomCode) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return;
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
    startTurnTimer(roomCode) {
        const room = this.rooms.get(roomCode);
        if (!room?.gameState)
            return;
        if (room.gameState.phase !== GameState_1.GamePhase.playing && room.gameState.phase !== GameState_1.GamePhase.specialPower)
            return;
        if (this.presenceChecks.has(roomCode))
            return;
        const currentPlayer = (0, GameState_1.getCurrentPlayer)(room.gameState);
        if (!currentPlayer.isHuman || currentPlayer.isSpectator)
            return;
        this.clearTurnTimer(roomCode);
        // Si le jeu est en pause, on ne lance pas le timer maintenant
        if (room.isPaused)
            return;
        const waitingSpecialPower = room.gameState.phase === GameState_1.GamePhase.specialPower;
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
            if (!currentRoom?.gameState)
                return;
            const currentGameState = currentRoom.gameState;
            const stillCurrent = (0, GameState_1.getCurrentPlayer)(currentGameState).id === playerId;
            if (!stillCurrent)
                return;
            this.actionTimers.delete(roomCode);
            if (currentGameState.phase === GameState_1.GamePhase.specialPower) {
                GameLogic_1.GameLogic.skipSpecialPower(currentGameState);
                const timeoutSeconds = Math.round(this.specialPowerTimeoutMs / 1000);
                this.broadcastGameState(roomCode, 'ACTION_RESULT', {
                    message: `⏱️ Pouvoir spécial expiré (${timeoutSeconds}s) : pouvoir ignoré.`,
                });
                const phaseAfterSkip = currentGameState.phase;
                if (phaseAfterSkip === GameState_1.GamePhase.ended) {
                    this.handleGameEnd(roomCode);
                    return;
                }
                if (phaseAfterSkip === GameState_1.GamePhase.reaction) {
                    const reactionTime = typeof currentRoom.settings?.reactionTimeMs === 'number'
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
    clearTurnTimer(roomCode) {
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
    triggerPresenceCheck(roomCode, playerId, reason, options) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return;
        const player = room.players.find((p) => p.id === playerId);
        if (!player || player.isSpectator)
            return;
        if (this.presenceChecks.get(roomCode)?.playerId === playerId)
            return;
        const deadlineMs = options?.deadlineMs ?? this.presenceGraceMs;
        const deadlineAt = this.now() + deadlineMs;
        this.presenceChecks.set(roomCode, { playerId, deadlineAt });
        this.io.to(player.id).emit('presence:check', {
            reason,
            deadlineMs,
        });
        if (options?.sendPush && player.userId) {
            PushNotificationService_1.PushNotificationService.sendToUser(player.userId, {
                title: 'Tu es toujours là ?',
                body: 'La partie t\'attend ! Reviens vite ou tu seras expulsé(e).',
                data: { type: 'presence_check', roomCode }
            }).catch(console.error);
        }
        const key = `${roomCode}:${playerId}`;
        const existing = this.presenceTimers.get(key);
        if (existing)
            clearTimeout(existing);
        const timer = setTimeout(() => {
            const current = this.presenceChecks.get(roomCode);
            if (current?.playerId !== playerId)
                return;
            this.markSpectator(roomCode, playerId, 'Inactif');
        }, deadlineMs);
        this.presenceTimers.set(key, timer);
    }
    clearPresenceCheck(roomCode, playerId) {
        const current = this.presenceChecks.get(roomCode);
        if (current?.playerId === playerId) {
            this.presenceChecks.delete(roomCode);
        }
        const key = `${roomCode}:${playerId}`;
        const timer = this.presenceTimers.get(key);
        if (timer) {
            clearTimeout(timer);
            this.presenceTimers.delete(key);
        }
    }
    removePlayerFromGameState(roomCode, playerId, removeReason) {
        const room = this.rooms.get(roomCode);
        if (!room?.gameState)
            return;
        const gameState = room.gameState;
        const playerIndex = gameState.players.findIndex((p) => p.id === playerId);
        if (playerIndex < 0)
            return;
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
        if ((phaseBeforeRemoval === GameState_1.GamePhase.playing || phaseBeforeRemoval === GameState_1.GamePhase.specialPower) && wasCurrentPlayer) {
            this.clearTurnTimer(roomCode);
            this.forceEndTurn(roomCode, removeReason);
        }
    }
    removePlayerFromActiveRoom(roomCode, playerId, options) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return;
        const player = room.players.find((p) => p.id === playerId);
        if (!player)
            return;
        this.clearPresenceCheck(roomCode, playerId);
        this.removePlayerFromGameState(roomCode, playerId, options.removeReason);
        const roomIndex = room.players.findIndex((p) => p.id === playerId);
        if (roomIndex >= 0) {
            if (room.status === Room_1.RoomStatus.waiting || room.status === Room_1.RoomStatus.ended) {
                // En attente ou partie terminée : retirer complètement le joueur
                room.players.splice(roomIndex, 1);
            }
            else {
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
        if (room.status !== Room_1.RoomStatus.playing && !room.isPaused) {
            this.reindexPlayers(room);
        }
        this.ensureHost(room);
        this.touchRoom(room);
        this.broadcastPresence(roomCode);
        this.broadcastGameState(roomCode, 'PLAYER_LEFT', { playerId });
        this.checkGameEndCondition(roomCode);
    }
    markSpectator(roomCode, playerId, reason) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return;
        const player = room.players.find((p) => p.id === playerId);
        if (!player || player.isSpectator)
            return;
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
    forceEndTurn(roomCode, reason) {
        const room = this.rooms.get(roomCode);
        if (!room?.gameState)
            return;
        const gameState = room.gameState;
        if (gameState.phase === GameState_1.GamePhase.specialPower) {
            GameLogic_1.GameLogic.skipSpecialPower(gameState);
        }
        else if (gameState.drawnCard) {
            GameLogic_1.GameLogic.discardDrawnCard(gameState);
            if (gameState.phase === GameState_1.GamePhase.specialPower) {
                GameLogic_1.GameLogic.skipSpecialPower(gameState);
            }
            else {
                GameLogic_1.GameLogic.nextPlayer(gameState);
            }
        }
        else {
            GameLogic_1.GameLogic.nextPlayer(gameState);
        }
        this.broadcastGameState(roomCode, 'ACTION_RESULT', { message: reason });
        if (gameState.phase === GameState_1.GamePhase.ended) {
            this.handleGameEnd(roomCode);
            return;
        }
        if (gameState.phase === GameState_1.GamePhase.reaction) {
            const reactionTime = typeof room.settings?.reactionTimeMs === 'number'
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
    addInvitedPlayer(roomCode, userId, username, displayName) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return null;
        if (room.status !== Room_1.RoomStatus.waiting)
            return null;
        // Déjà dedans ?
        if (room.players.some((p) => p.isHuman && p.userId?.trim() === userId.trim())) {
            return null;
        }
        const maxPlayers = typeof room.settings?.maxPlayers === 'number'
            ? room.settings.maxPlayers
            : 6;
        if (this.activePlayerCount(room) >= maxPlayers)
            return null;
        const position = room.players.length;
        const player = (0, Player_1.createPlayer)(`invited-${userId}`, displayName, true, position, undefined, undefined, undefined, userId.trim(), username.trim().toLowerCase());
        player.connected = false;
        player.focused = false;
        player.ready = false;
        room.players.push(player);
        this.reindexPlayers(room);
        this.touchRoom(room);
        this.broadcastPresence(roomCode);
        return player;
    }
    activePlayerCount(room) {
        const now = this.now();
        return room.players.filter((player) => {
            if (player.isSpectator)
                return false;
            if (!player.isHuman)
                return true;
            if (!player.connected)
                return false;
            return !this.isPlayerStale(player, now);
        }).length;
    }
    isPlayerStale(player, now) {
        if (!player.isHuman)
            return false;
        const lastSeen = player.lastSeenAt ?? 0;
        return now - lastSeen > this.stalePlayerMs;
    }
    reindexPlayers(room) {
        room.players.forEach((player, index) => {
            player.position = index;
        });
    }
    ensureHost(room) {
        const now = this.now();
        const host = room.players.find((p) => p.id === room.hostPlayerId &&
            p.isHuman &&
            p.connected &&
            !p.isSpectator &&
            !this.isPlayerStale(p, now));
        if (host)
            return;
        const nextHost = room.players.find((p) => p.isHuman && p.connected && !p.isSpectator && !this.isPlayerStale(p, now));
        if (nextHost) {
            room.hostPlayerId = nextHost.id;
            return;
        }
        const fallbackHost = room.players.find((p) => p.isHuman && p.connected && !this.isPlayerStale(p, now));
        if (fallbackHost) {
            room.hostPlayerId = fallbackHost.id;
        }
    }
    pruneWaitingRoom(room) {
        if (room.status !== Room_1.RoomStatus.waiting)
            return;
        const now = this.now();
        const before = room.players.length;
        room.players = room.players.filter((player) => {
            if (!player.isHuman)
                return true;
            if (player.connected !== false)
                return true;
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
    touchRoom(room) {
        room.lastActivityAt = this.now();
    }
    startCleanupLoop() {
        if (this.cleanupTimer)
            return;
        this.cleanupTimer = setInterval(() => this.cleanupRooms(), this.cleanupIntervalMs);
    }
    cleanupRooms() {
        const now = this.now();
        for (const room of this.rooms.values()) {
            // Supprimer les rooms en cours de fermeture expirées
            if (room.status === Room_1.RoomStatus.closing) {
                if (room.closingAt && now >= room.closingAt) {
                    this.removeRoom(room.id);
                    continue;
                }
                // Room en fermeture mais pas encore expirée, on continue
                continue;
            }
            if (room.status === Room_1.RoomStatus.waiting) {
                this.pruneWaitingRoom(room);
                this.ensureHost(room);
            }
            let staleChanged = false;
            for (const player of room.players) {
                if (!player.isHuman)
                    continue;
                const lastSeen = player.lastSeenAt ?? 0;
                const isStale = now - lastSeen > this.stalePlayerMs;
                if ((player.connected ?? false) && isStale) {
                    player.connected = false;
                    player.focused = false;
                    staleChanged = true;
                }
            }
            const anyConnected = room.players.some((player) => {
                if (!player.isHuman)
                    return true;
                if (!player.connected)
                    return false;
                const lastSeen = player.lastSeenAt ?? 0;
                return now - lastSeen <= this.stalePlayerMs;
            });
            if (anyConnected) {
                // Activity detected, clear grace period
                room.emptyAt = undefined;
                if (now >= room.expiresAt) {
                    this.removeRoom(room.id);
                    continue;
                }
            }
            else {
                // No short inactivity auto-delete: keep room available until TTL/admin action.
                if (!room.emptyAt) {
                    room.emptyAt = now;
                }
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
    closeRoom(roomCode, socketId) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return { success: false, reason: 'Room not found' };
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
        room.status = Room_1.RoomStatus.closing;
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
    transferHost(roomCode, requesterId) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return false;
        // Vérifier que la room est en cours de fermeture ou que l'hôte actuel n'est plus connecté
        const currentHost = room.players.find((p) => p.id === room.hostPlayerId);
        const isClosing = room.status === Room_1.RoomStatus.closing;
        const hostDisconnected = !currentHost?.connected;
        if (!isClosing && !hostDisconnected)
            return false;
        const requester = room.players.find((p) => p.id === requesterId);
        if (!requester || !requester.isHuman || !requester.connected)
            return false;
        // Transférer l'hôte
        room.hostPlayerId = requesterId;
        room.status = Room_1.RoomStatus.waiting;
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
    checkActiveRooms(roomCodes) {
        const result = [];
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
    getActiveRoomsForMember(params) {
        const userId = params.userId?.trim();
        const username = params.username?.trim().toLowerCase();
        const clientId = params.clientId?.trim();
        if (!userId && !username && !clientId) {
            return [];
        }
        const matchesMember = (player) => {
            if (!player.isHuman)
                return false;
            if (userId && player.userId === userId)
                return true;
            if (!userId && username && player.username?.trim().toLowerCase() === username) {
                return true;
            }
            if (!userId && !username && clientId && player.clientId === clientId)
                return true;
            return false;
        };
        const result = [];
        for (const room of this.rooms.values()) {
            if (room.status === Room_1.RoomStatus.closing) {
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
    setGameMode(roomCode, socketId, mode) {
        const room = this.rooms.get(roomCode);
        if (room?.status !== Room_1.RoomStatus.waiting)
            return false;
        if (room.hostPlayerId !== socketId)
            return false;
        room.gameMode = mode;
        this.broadcastPresence(roomCode);
        return true;
    }
    /**
     * Met à jour les paramètres de la room (hôte uniquement, en lobby)
     */
    updateRoomSettings(roomCode, socketId, settings) {
        const room = this.rooms.get(roomCode);
        if (room?.status !== Room_1.RoomStatus.waiting)
            return false;
        if (room.hostPlayerId !== socketId)
            return false;
        // Mettre à jour les paramètres
        if (settings.botDifficulty !== undefined) {
            room.settings.botDifficulty = settings.botDifficulty;
        }
        if (settings.luckDifficulty !== undefined) {
            room.settings.luckDifficulty = settings.luckDifficulty;
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
    sendFullStateToPlayer(roomCode, playerId) {
        const room = this.rooms.get(roomCode);
        if (!room?.gameState)
            return;
        const personalizedState = this.getPersonalizedState(room.gameState, playerId);
        this.io.to(playerId).emit('game:full_state', {
            type: 'FULL_STATE',
            gameState: personalizedState,
        });
    }
    removeRoom(roomCode) {
        this.clearTurnTimer(roomCode);
        this.clearReactionTimer(roomCode);
        const pending = this.presenceChecks.get(roomCode);
        if (pending) {
            this.clearPresenceCheck(roomCode, pending.playerId);
        }
        for (const key of Array.from(this.presenceTimers.keys())) {
            if (key.startsWith(`${roomCode}:`)) {
                const timer = this.presenceTimers.get(key);
                if (timer)
                    clearTimeout(timer);
                this.presenceTimers.delete(key);
            }
        }
        this.rooms.delete(roomCode);
    }
    getPersonalizedState(gameState, playerId) {
        const state = { ...gameState };
        const isGameEnded = gameState.phase === GameState_1.GamePhase.ended;
        state.players = state.players.map((player) => {
            // Si la partie est terminée, révéler toutes les cartes à tous les joueurs
            if (isGameEnded) {
                return {
                    ...player,
                    // S'assurer que les cartes sont visibles
                    hand: player.hand.map((card) => ({
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
            gameState.phase === GameState_1.GamePhase.playing &&
            !gameState.drawnCard) {
            // Envoyer la carte du dessus du deck (celle qui sera piochée)
            state.preloadedDeckCard = gameState.deck[gameState.deck.length - 1];
        }
        else {
            state.preloadedDeckCard = null;
        }
        return state;
    }
    generateRoomCode() {
        const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
        let code;
        do {
            code = Array.from({ length: 6 }, () => chars.charAt(Math.floor(Math.random() * chars.length))).join('');
        } while (this.rooms.has(code));
        return code;
    }
    createBot(position, difficulty) {
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
            Player_1.BotBehavior.balanced,
            Player_1.BotBehavior.aggressive,
            Player_1.BotBehavior.fast,
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
    getDesiredSkillLevel(difficulty) {
        switch (difficulty) {
            case GameState_1.Difficulty.easy:
                return Player_1.BotSkillLevel.bronze;
            case GameState_1.Difficulty.hard:
                return Player_1.BotSkillLevel.platinum;
            default:
                return Player_1.BotSkillLevel.silver;
        }
    }
    // Crée un bot avec un BotSkillLevel spécifique (utilisé par le SBMM)
    createBotWithSkill(position, skillLevel) {
        const botNames = ['Alice', 'Bob', 'Charlie', 'Diana', 'Eve'];
        const behaviors = [
            Player_1.BotBehavior.balanced,
            Player_1.BotBehavior.aggressive,
            Player_1.BotBehavior.fast,
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
    loadBotCastingCacheIfNeeded() {
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
            const profiles = [];
            for (const file of files) {
                try {
                    const raw = fs.readFileSync(path.join(profilesDir, file), 'utf-8');
                    const parsed = JSON.parse(raw);
                    if (!parsed || typeof parsed.botId !== 'string')
                        continue;
                    profiles.push({
                        botId: parsed.botId,
                        botName: parsed.botName,
                        behavior: parsed.behavior,
                        skillLevel: parsed.skillLevel,
                        mmr: typeof parsed.mmr === 'number' ? parsed.mmr : undefined,
                    });
                }
                catch {
                    // Ignorer un fichier corrompu
                }
            }
            // Trier par MMR décroissant (bots forts en premier)
            profiles.sort((a, b) => (b.mmr ?? 0) - (a.mmr ?? 0));
            this.botCastingCache = profiles;
            this.botCastingCacheLoadedAtMs = now;
        }
        catch {
            this.botCastingCache = [];
            this.botCastingCacheLoadedAtMs = now;
        }
    }
    selectCastingBot(position, desiredSkill) {
        this.loadBotCastingCacheIfNeeded();
        if (!this.botCastingCache || this.botCastingCache.length === 0)
            return null;
        // Casting persistant: on privilégie les bots déjà forts (MMR élevé),
        // indépendamment du skillLevel "déclaratif".
        // Ainsi, si Oscar/Jack deviennent forts, ils reviennent naturellement.
        const pool = this.botCastingCache;
        const picked = pool[position % pool.length];
        if (!picked)
            return null;
        // Convert behavior/skillLevel strings en enums serveur
        let behavior = Player_1.BotBehavior.balanced;
        if (picked.behavior === 'fast')
            behavior = Player_1.BotBehavior.fast;
        else if (picked.behavior === 'aggressive')
            behavior = Player_1.BotBehavior.aggressive;
        let skillLevel = Player_1.BotSkillLevel.bronze;
        if (picked.skillLevel === 'platinum')
            skillLevel = Player_1.BotSkillLevel.platinum;
        else if (picked.skillLevel === 'gold')
            skillLevel = Player_1.BotSkillLevel.gold;
        else if (picked.skillLevel === 'silver')
            skillLevel = Player_1.BotSkillLevel.silver;
        // Si le profil n'a pas de skillLevel, on retombe sur celui attendu par la difficulté
        const resolvedSkillLevel = picked.skillLevel ? skillLevel : desiredSkill;
        return {
            botId: picked.botId,
            botName: picked.botName,
            botBehavior: behavior,
            botSkillLevel: resolvedSkillLevel,
        };
    }
    normalizeSettings(settings) {
        const gameMode = this.parseGameMode(settings?.gameMode);
        const reactionTimeMs = typeof settings?.reactionTimeMs === 'number' ? settings.reactionTimeMs : 3000;
        const botDifficulty = typeof settings?.botDifficulty === 'number'
            ? settings.botDifficulty
            : GameState_1.Difficulty.medium;
        const luckDifficulty = typeof settings?.luckDifficulty === 'number'
            ? settings.luckDifficulty
            : GameState_1.Difficulty.medium;
        const minPlayersRaw = typeof settings?.minPlayers === 'number' ? settings.minPlayers : 2;
        const maxPlayersRaw = typeof settings?.maxPlayers === 'number' ? settings.maxPlayers : 6;
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
    parseGameMode(value) {
        if (value === GameState_1.GameMode.tournament || value === 1 || value === 'tournament') {
            return GameState_1.GameMode.tournament;
        }
        return GameState_1.GameMode.quick;
    }
    getBotDifficulty(settings) {
        // Le client Flutter calculera la difficulté SBMM et l'enverra dans botDifficulty
        // Si useSBMM est true, le client aura déjà calculé la difficulté recommandée
        if (typeof settings?.botDifficulty === 'number') {
            return settings.botDifficulty;
        }
        return GameState_1.Difficulty.medium;
    }
    currentPhase(gameState) {
        return gameState.phase;
    }
    delay(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
    }
}
exports.RoomManager = RoomManager;
//# sourceMappingURL=RoomManager.js.map