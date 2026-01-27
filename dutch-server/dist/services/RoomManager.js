"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.RoomManager = void 0;
const GameLogic_1 = require("./GameLogic");
const BotAI_1 = require("./BotAI");
const GameState_1 = require("../models/GameState");
const Player_1 = require("../models/Player");
const Room_1 = require("../models/Room");
const TimerManager_1 = require("./TimerManager");
class RoomManager {
    constructor(io, options = {}) {
        this.io = io;
        this.rooms = new Map();
        this.actionTimers = new Map();
        this.presenceTimers = new Map();
        this.presenceChecks = new Map();
        this.cleanupTimer = null;
        this.turnTimeoutMs = options.turnTimeoutMs ?? 25000;
        this.presenceGraceMs = options.presenceGraceMs ?? 5000;
        this.roomTtlMs = options.roomTtlMs ?? 2 * 60 * 60 * 1000;
        this.cleanupIntervalMs = options.cleanupIntervalMs ?? 60000;
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
    getRoomCount() {
        return this.rooms.size;
    }
    listRooms() {
        return Array.from(this.rooms.values()).map((room) => ({
            id: room.id,
            playerCount: room.players.length,
            status: room.status,
            gameMode: GameState_1.GameMode[room.gameMode],
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
    createRoom(hostSocketId, settings, playerName, clientId) {
        const normalizedSettings = this.normalizeSettings(settings);
        const roomCode = this.generateRoomCode();
        const expiresAt = this.now() + this.roomTtlMs;
        const room = (0, Room_1.createRoom)(roomCode, hostSocketId, normalizedSettings, expiresAt);
        const hostPlayer = (0, Player_1.createPlayer)(hostSocketId, playerName || 'Hôte', true, 0, undefined, undefined, clientId);
        hostPlayer.connected = true;
        hostPlayer.focused = true;
        hostPlayer.lastSeenAt = this.now();
        room.players.push(hostPlayer);
        this.touchRoom(room);
        this.rooms.set(roomCode, room);
        return room;
    }
    joinRoom(roomCode, socketId, playerName, clientId) {
        const room = this.rooms.get(roomCode);
        if (!room) {
            return { error: 'Room introuvable' };
        }
        if (room.status !== Room_1.RoomStatus.waiting) {
            return { error: 'La partie a déjà commencé' };
        }
        if (clientId) {
            const existing = room.players.find((p) => p.clientId === clientId);
            if (existing) {
                const previousId = existing.id;
                existing.id = socketId;
                if (playerName) {
                    existing.name = playerName;
                }
                existing.isHuman = true;
                existing.connected = true;
                existing.focused = true;
                existing.lastSeenAt = this.now();
                if (room.hostPlayerId === previousId) {
                    room.hostPlayerId = socketId;
                }
                this.touchRoom(room);
                return { room, player: existing };
            }
        }
        const maxPlayers = typeof room.settings?.maxPlayers === 'number'
            ? room.settings.maxPlayers
            : 4;
        if (room.players.length >= maxPlayers) {
            return { error: 'Room pleine' };
        }
        const player = (0, Player_1.createPlayer)(socketId, playerName || `Joueur ${room.players.length + 1}`, true, room.players.length, undefined, undefined, clientId);
        player.connected = true;
        player.focused = true;
        player.lastSeenAt = this.now();
        room.players.push(player);
        this.touchRoom(room);
        return { room, player };
    }
    notifyPlayerJoined(roomCode, player) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return;
        this.io.to(roomCode).emit('room:player_joined', {
            roomCode,
            player,
            playerCount: room.players.length,
        });
    }
    startGame(roomCode) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return false;
        const minPlayers = typeof room.settings?.minPlayers === 'number'
            ? room.settings.minPlayers
            : 2;
        const maxPlayers = typeof room.settings?.maxPlayers === 'number'
            ? room.settings.maxPlayers
            : 4;
        const fillBots = room.settings?.fillBots !== false;
        const humanCount = room.players.filter((p) => p.isHuman).length;
        if (humanCount < minPlayers)
            return false;
        if (room.players.length > maxPlayers)
            return false;
        const difficulty = this.getBotDifficulty(room.settings);
        if (fillBots) {
            while (room.players.length < maxPlayers) {
                room.players.push(this.createBot(room.players.length, difficulty));
            }
        }
        const gameState = (0, GameState_1.createGameState)(room.players, room.gameMode, difficulty);
        GameLogic_1.GameLogic.initializeGame(gameState);
        gameState.phase = GameState_1.GamePhase.playing;
        room.gameState = gameState;
        room.status = Room_1.RoomStatus.playing;
        this.clearTurnTimer(roomCode);
        this.startTurnTimer(roomCode);
        this.touchRoom(room);
        return true;
    }
    broadcastGameState(roomCode, updateType, additionalData = {}) {
        const room = this.rooms.get(roomCode);
        if (!room || !room.gameState)
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
        this.clearTurnTimer(roomCode);
        this.timerManager.startReactionTimer(roomCode, durationMs);
    }
    clearReactionTimer(roomCode) {
        this.timerManager.clearTimer(roomCode);
    }
    async endReactionPhase(roomCode) {
        this.clearReactionTimer(roomCode);
        const room = this.rooms.get(roomCode);
        if (!room || !room.gameState)
            return;
        room.gameState.phase = GameState_1.GamePhase.playing;
        room.gameState.lastSpiedCard = null;
        room.gameState.reactionStartTime = null;
        GameLogic_1.GameLogic.nextPlayer(room.gameState);
        this.broadcastGameState(roomCode, 'PHASE_CHANGE');
        await this.checkAndPlayBotTurn(roomCode);
    }
    async checkAndPlayBotTurn(roomCode) {
        const room = this.rooms.get(roomCode);
        if (!room || !room.gameState)
            return;
        const gameState = room.gameState;
        while (true) {
            if (gameState.phase !== GameState_1.GamePhase.playing)
                break;
            if ((0, GameState_1.getCurrentPlayer)(gameState).isHuman)
                break;
            await this.delay(800);
            await BotAI_1.BotAI.playBotTurn(gameState);
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
        if (!room || !room.gameState)
            return;
        room.status = Room_1.RoomStatus.ended;
        this.clearTurnTimer(roomCode);
        this.broadcastGameState(roomCode, 'GAME_ENDED', {
            message: 'Partie terminée !',
        });
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
        if (pending && pending.playerId === playerId) {
            this.clearPresenceCheck(roomCode, playerId);
        }
        if (room.gameState &&
            room.gameState.phase === GameState_1.GamePhase.playing &&
            (0, GameState_1.getCurrentPlayer)(room.gameState).id === playerId) {
            this.startTurnTimer(roomCode);
        }
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
        this.startTurnTimer(roomCode);
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
        if (room.status === Room_1.RoomStatus.waiting) {
            room.players.splice(index, 1);
            if (room.players.length === 0) {
                this.removeRoom(roomCode);
                return;
            }
            if (room.hostPlayerId === socketId && room.players.length > 0) {
                room.hostPlayerId = room.players[0].id;
            }
        }
        else {
            leaving.connected = false;
            leaving.focused = false;
            leaving.lastSeenAt = this.now();
            leaving.isSpectator = true;
            if (room.gameState && (0, GameState_1.getCurrentPlayer)(room.gameState).id === leaving.id) {
                this.forceEndTurn(roomCode, `${leaving.name} est passé spectateur.`);
            }
        }
        this.touchRoom(room);
        this.broadcastPresence(roomCode);
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
        }
        this.cleanupRooms();
    }
    broadcastPresence(roomCode) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return;
        const players = room.players.map((player) => ({
            id: player.id,
            clientId: player.clientId,
            name: player.name,
            isHuman: player.isHuman,
            position: player.position,
            connected: player.connected ?? false,
            focused: player.focused ?? false,
            isSpectator: player.isSpectator ?? false,
        }));
        this.io.to(roomCode).emit('presence:update', { roomCode, players });
    }
    startTurnTimer(roomCode) {
        const room = this.rooms.get(roomCode);
        if (!room || !room.gameState)
            return;
        if (room.gameState.phase !== GameState_1.GamePhase.playing)
            return;
        if (this.presenceChecks.has(roomCode))
            return;
        const currentPlayer = (0, GameState_1.getCurrentPlayer)(room.gameState);
        if (!currentPlayer.isHuman || currentPlayer.isSpectator)
            return;
        this.clearTurnTimer(roomCode);
        const playerId = currentPlayer.id;
        const timer = setTimeout(() => {
            const currentRoom = this.rooms.get(roomCode);
            if (!currentRoom || !currentRoom.gameState)
                return;
            const stillCurrent = (0, GameState_1.getCurrentPlayer)(currentRoom.gameState).id === playerId;
            if (!stillCurrent)
                return;
            this.actionTimers.delete(roomCode);
            this.triggerPresenceCheck(roomCode, playerId, 'Temps de jeu écoulé');
        }, this.turnTimeoutMs);
        this.actionTimers.set(roomCode, timer);
    }
    clearTurnTimer(roomCode) {
        const timer = this.actionTimers.get(roomCode);
        if (timer) {
            clearTimeout(timer);
            this.actionTimers.delete(roomCode);
        }
    }
    triggerPresenceCheck(roomCode, playerId, reason) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return;
        const player = room.players.find((p) => p.id === playerId);
        if (!player || player.isSpectator)
            return;
        if (this.presenceChecks.get(roomCode)?.playerId === playerId)
            return;
        const deadlineAt = this.now() + this.presenceGraceMs;
        this.presenceChecks.set(roomCode, { playerId, deadlineAt });
        this.io.to(player.id).emit('presence:check', {
            reason,
            deadlineMs: this.presenceGraceMs,
        });
        const key = `${roomCode}:${playerId}`;
        const existing = this.presenceTimers.get(key);
        if (existing)
            clearTimeout(existing);
        const timer = setTimeout(() => {
            const current = this.presenceChecks.get(roomCode);
            if (!current || current.playerId !== playerId)
                return;
            this.markSpectator(roomCode, playerId, 'Inactif');
        }, this.presenceGraceMs);
        this.presenceTimers.set(key, timer);
    }
    clearPresenceCheck(roomCode, playerId) {
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
    markSpectator(roomCode, playerId, reason) {
        const room = this.rooms.get(roomCode);
        if (!room)
            return;
        const player = room.players.find((p) => p.id === playerId);
        if (!player || player.isSpectator)
            return;
        player.isSpectator = true;
        player.connected = player.connected ?? false;
        player.focused = false;
        player.lastSeenAt = this.now();
        this.clearPresenceCheck(roomCode, playerId);
        this.clearTurnTimer(roomCode);
        if (room.gameState && (0, GameState_1.getCurrentPlayer)(room.gameState).id === playerId) {
            this.forceEndTurn(roomCode, `${player.name} est passé spectateur.`);
        }
        this.touchRoom(room);
        this.broadcastPresence(roomCode);
    }
    forceEndTurn(roomCode, reason) {
        const room = this.rooms.get(roomCode);
        if (!room || !room.gameState)
            return;
        const gameState = room.gameState;
        if (gameState.isWaitingForSpecialPower) {
            GameLogic_1.GameLogic.skipSpecialPower(gameState);
        }
        else if (gameState.drawnCard) {
            GameLogic_1.GameLogic.discardDrawnCard(gameState);
            if (gameState.isWaitingForSpecialPower) {
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
            const humans = room.players.filter((p) => p.isHuman);
            const anyConnected = humans.some((p) => p.connected);
            if (!anyConnected || now >= room.expiresAt) {
                this.removeRoom(room.id);
            }
        }
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
        state.players = state.players.map((player) => {
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
    generateRoomCode() {
        const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
        let code;
        do {
            code = Array.from({ length: 6 }, () => chars.charAt(Math.floor(Math.random() * chars.length))).join('');
        } while (this.rooms.has(code));
        return code;
    }
    createBot(position, difficulty) {
        const botNames = ['Alice', 'Bob', 'Charlie', 'Diana'];
        const behaviors = [
            Player_1.BotBehavior.balanced,
            Player_1.BotBehavior.aggressive,
            Player_1.BotBehavior.fast,
        ];
        const behavior = behaviors[position % behaviors.length];
        let skillLevel;
        switch (difficulty) {
            case GameState_1.Difficulty.easy:
                skillLevel = Player_1.BotSkillLevel.bronze;
                break;
            case GameState_1.Difficulty.hard:
                skillLevel = Player_1.BotSkillLevel.platinum;
                break;
            default:
                skillLevel = Player_1.BotSkillLevel.silver;
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
        const maxPlayersRaw = typeof settings?.maxPlayers === 'number' ? settings.maxPlayers : 4;
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
    parseGameMode(value) {
        if (value === GameState_1.GameMode.tournament || value === 1 || value === 'tournament') {
            return GameState_1.GameMode.tournament;
        }
        return GameState_1.GameMode.quick;
    }
    getBotDifficulty(settings) {
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
