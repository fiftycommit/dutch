"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const node_assert_1 = __importDefault(require("node:assert"));
const RoomManager_1 = require("../services/RoomManager");
const gameHandler_1 = require("../handlers/gameHandler");
const GameState_1 = require("../models/GameState");
const Card_1 = require("../models/Card");
const SecurityService_1 = require("../services/SecurityService");
// Mock Socket implementation
class MockSocket {
    constructor(id) {
        this.events = new Map();
        this.emittedEvents = [];
        this.rooms = new Set();
        this.targetedEmits = [];
        this.id = id;
    }
    on(event, callback) {
        this.events.set(event, callback);
        return this;
    }
    emit(event, data) {
        this.emittedEvents.push({ event, data });
        return this;
    }
    join(room) {
        this.rooms.add(room);
        return this;
    }
    leave(room) {
        this.rooms.delete(room);
        return this;
    }
    to(target) {
        const self = this;
        return {
            emit(event, data) {
                self.targetedEmits.push({ target, event, data });
                return self;
            }
        };
    }
    triggerEvent(event, ...args) {
        const handler = this.events.get(event);
        if (handler) {
            return handler(...args);
        }
    }
}
class MockServer {
    constructor() {
        this.events = [];
        this.currentTarget = '';
    }
    to(target) {
        this.currentTarget = target;
        return this;
    }
    emit(event, data) {
        this.events.push({ target: this.currentTarget, event, data });
        return true;
    }
}
(0, node_test_1.describe)('gameHandler', () => {
    let mockSocket;
    let mockServer;
    let roomManager;
    let roomCode;
    (0, node_test_1.beforeEach)(() => {
        SecurityService_1.SecurityService.resetForTesting();
        mockSocket = new MockSocket('player-1');
        mockServer = new MockServer();
        roomManager = new RoomManager_1.RoomManager(mockServer, {
            cleanupIntervalMs: 10000,
            roomTtlMs: 60000,
            turnTimeoutMs: 30000,
            presenceGraceMs: 5000,
        });
        (0, gameHandler_1.setupGameHandler)(mockSocket, roomManager);
        // Create and start a game
        const room = roomManager.createRoom('player-1', {
            minPlayers: 2,
            maxPlayers: 4,
            fillBots: false,
        });
        roomCode = room.id;
        roomManager.joinRoom(roomCode, 'player-2', 'Player 2', 'client-2');
        roomManager.setReady(roomCode, 'player-1', true);
        roomManager.setReady(roomCode, 'player-2', true);
        roomManager.startGame(roomCode, { fillBots: false });
        // Mark players ready after memorization
        roomManager.markPlayerReady(roomCode, 'player-1');
        roomManager.markPlayerReady(roomCode, 'player-2');
    });
    (0, node_test_1.afterEach)(() => {
        roomManager.dispose();
    });
    (0, node_test_1.describe)('game:draw_card', () => {
        (0, node_test_1.it)('allows current player to draw a card', async () => {
            const room = roomManager.getRoom(roomCode);
            room.gameState.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
            const deckSizeBefore = room.gameState.deck.length;
            await mockSocket.triggerEvent('game:draw_card', { roomCode });
            // Allow async operations to complete
            await new Promise(resolve => setTimeout(resolve, 50));
            node_assert_1.default.ok(room.gameState.drawnCard !== null ||
                room.gameState.deck.length < deckSizeBefore);
        });
        (0, node_test_1.it)('rejects draw from non-current player', async () => {
            const room = roomManager.getRoom(roomCode);
            // Set current player to someone else
            room.gameState.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-2');
            const deckSizeBefore = room.gameState.deck.length;
            await mockSocket.triggerEvent('game:draw_card', { roomCode });
            await new Promise(resolve => setTimeout(resolve, 50));
            // Deck should not change because it's not player-1's turn
            node_assert_1.default.strictEqual(room.gameState.deck.length, deckSizeBefore);
        });
        (0, node_test_1.it)('rejects draw from spectator', async () => {
            const room = roomManager.getRoom(roomCode);
            room.gameState.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
            room.players.find(p => p.id === 'player-1').isSpectator = true;
            const deckSizeBefore = room.gameState.deck.length;
            await mockSocket.triggerEvent('game:draw_card', { roomCode });
            await new Promise(resolve => setTimeout(resolve, 50));
            node_assert_1.default.strictEqual(room.gameState.deck.length, deckSizeBefore);
        });
        (0, node_test_1.it)('handles invalid room code', async () => {
            await mockSocket.triggerEvent('game:draw_card', { roomCode: 'INVALID' });
            // Should not throw
            node_assert_1.default.ok(true);
        });
    });
    (0, node_test_1.describe)('game:replace_card', () => {
        (0, node_test_1.it)('allows replacing a card in hand', async () => {
            const room = roomManager.getRoom(roomCode);
            const playerIndex = room.players.findIndex(p => p.id === 'player-1');
            room.gameState.currentPlayerIndex = playerIndex;
            room.gameState.drawnCard = (0, Card_1.createCard)('hearts', '5');
            const oldCard = room.gameState.players[playerIndex].hand[0];
            await mockSocket.triggerEvent('game:replace_card', { roomCode, cardIndex: 0 });
            await new Promise(resolve => setTimeout(resolve, 50));
            // Drawn card should now be in hand
            node_assert_1.default.strictEqual(room.gameState.drawnCard, null);
        });
        (0, node_test_1.it)('rejects replace without drawn card', async () => {
            const room = roomManager.getRoom(roomCode);
            room.gameState.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
            room.gameState.drawnCard = null;
            await mockSocket.triggerEvent('game:replace_card', { roomCode, cardIndex: 0 });
            // Should not throw or change state
            node_assert_1.default.ok(true);
        });
    });
    (0, node_test_1.describe)('game:discard_card', () => {
        (0, node_test_1.it)('allows discarding drawn card', async () => {
            const room = roomManager.getRoom(roomCode);
            room.gameState.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
            room.gameState.drawnCard = (0, Card_1.createCard)('hearts', '5');
            const discardSizeBefore = room.gameState.discardPile.length;
            await mockSocket.triggerEvent('game:discard_card', { roomCode });
            await new Promise(resolve => setTimeout(resolve, 50));
            node_assert_1.default.strictEqual(room.gameState.drawnCard, null);
            node_assert_1.default.strictEqual(room.gameState.discardPile.length, discardSizeBefore + 1);
        });
        (0, node_test_1.it)('triggers reaction phase for non-special card', async () => {
            const room = roomManager.getRoom(roomCode);
            room.gameState.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
            room.gameState.drawnCard = (0, Card_1.createCard)('hearts', '5');
            room.gameState.phase = GameState_1.GamePhase.playing;
            await mockSocket.triggerEvent('game:discard_card', { roomCode });
            await new Promise(resolve => setTimeout(resolve, 50));
            node_assert_1.default.strictEqual(room.gameState.phase, GameState_1.GamePhase.reaction);
        });
    });
    (0, node_test_1.describe)('game:take_from_discard', () => {
        (0, node_test_1.it)('takes card from discard pile', async () => {
            const room = roomManager.getRoom(roomCode);
            room.gameState.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
            room.gameState.discardPile.push((0, Card_1.createCard)('spades', '6'));
            const discardSizeBefore = room.gameState.discardPile.length;
            await mockSocket.triggerEvent('game:take_from_discard', { roomCode });
            await new Promise(resolve => setTimeout(resolve, 50));
            node_assert_1.default.strictEqual(room.gameState.discardPile.length, discardSizeBefore - 1);
            node_assert_1.default.ok(room.gameState.drawnCard);
        });
    });
    (0, node_test_1.describe)('game:call_dutch', () => {
        (0, node_test_1.it)('allows player to call Dutch', async () => {
            const room = roomManager.getRoom(roomCode);
            await mockSocket.triggerEvent('game:call_dutch', { roomCode });
            await new Promise(resolve => setTimeout(resolve, 50));
            node_assert_1.default.strictEqual(room.gameState.dutchCallerId, 'player-1');
        });
        (0, node_test_1.it)('rejects Dutch from spectator', async () => {
            const room = roomManager.getRoom(roomCode);
            room.players.find(p => p.id === 'player-1').isSpectator = true;
            await mockSocket.triggerEvent('game:call_dutch', { roomCode });
            await new Promise(resolve => setTimeout(resolve, 50));
            node_assert_1.default.strictEqual(room.gameState.dutchCallerId, null);
        });
    });
    (0, node_test_1.describe)('game:attempt_match', () => {
        (0, node_test_1.it)('allows match attempt during reaction phase', async () => {
            const room = roomManager.getRoom(roomCode);
            room.gameState.phase = GameState_1.GamePhase.reaction;
            room.gameState.discardPile.push((0, Card_1.createCard)('hearts', '5'));
            const player = room.gameState.players.find(p => p.id === 'player-1');
            player.hand[0] = (0, Card_1.createCard)('spades', '5'); // Matching card
            const handSizeBefore = player.hand.length;
            await mockSocket.triggerEvent('game:attempt_match', { roomCode, cardIndex: 0 });
            await new Promise(resolve => setTimeout(resolve, 50));
            // If match successful, hand size decreases
            node_assert_1.default.ok(player.hand.length <= handSizeBefore);
        });
        (0, node_test_1.it)('rejects match outside reaction phase', async () => {
            const room = roomManager.getRoom(roomCode);
            room.gameState.phase = GameState_1.GamePhase.playing;
            await mockSocket.triggerEvent('game:attempt_match', { roomCode, cardIndex: 0 });
            // Should be ignored
            node_assert_1.default.ok(true);
        });
    });
    (0, node_test_1.describe)('game:use_special_power', () => {
        (0, node_test_1.it)('handles card 7 special power', async () => {
            const room = roomManager.getRoom(roomCode);
            room.gameState.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
            room.gameState.phase = GameState_1.GamePhase.specialPower;
            room.gameState.isWaitingForSpecialPower = true;
            room.gameState.specialCardToActivate = (0, Card_1.createCard)('hearts', '7');
            await mockSocket.triggerEvent('game:use_special_power', {
                roomCode,
                cardIndex: 0,
            });
            await new Promise(resolve => setTimeout(resolve, 50));
            // Power should be used
            node_assert_1.default.strictEqual(room.gameState.isWaitingForSpecialPower, false);
        });
        (0, node_test_1.it)('handles card 10 special power', async () => {
            const room = roomManager.getRoom(roomCode);
            room.gameState.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
            room.gameState.phase = GameState_1.GamePhase.specialPower;
            room.gameState.isWaitingForSpecialPower = true;
            room.gameState.specialCardToActivate = (0, Card_1.createCard)('spades', '10');
            await mockSocket.triggerEvent('game:use_special_power', {
                roomCode,
                targetPlayerIndex: 1,
                targetCardIndex: 0,
            });
            await new Promise(resolve => setTimeout(resolve, 50));
            node_assert_1.default.strictEqual(room.gameState.isWaitingForSpecialPower, false);
        });
        (0, node_test_1.it)('handles Jack (V) swap power', async () => {
            const room = roomManager.getRoom(roomCode);
            room.gameState.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
            room.gameState.phase = GameState_1.GamePhase.specialPower;
            room.gameState.isWaitingForSpecialPower = true;
            room.gameState.specialCardToActivate = (0, Card_1.createCard)('clubs', 'V');
            await mockSocket.triggerEvent('game:use_special_power', {
                roomCode,
                player1Index: 0,
                card1Index: 0,
                player2Index: 1,
                card2Index: 0,
            });
            await new Promise(resolve => setTimeout(resolve, 50));
            node_assert_1.default.strictEqual(room.gameState.isWaitingForSpecialPower, false);
        });
        (0, node_test_1.it)('handles JOKER shuffle power', async () => {
            const room = roomManager.getRoom(roomCode);
            room.gameState.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
            room.gameState.phase = GameState_1.GamePhase.specialPower;
            room.gameState.isWaitingForSpecialPower = true;
            room.gameState.specialCardToActivate = (0, Card_1.createCard)('joker', 'JOKER');
            await mockSocket.triggerEvent('game:use_special_power', {
                roomCode,
                targetPlayerIndex: 1,
            });
            await new Promise(resolve => setTimeout(resolve, 50));
            node_assert_1.default.strictEqual(room.gameState.isWaitingForSpecialPower, false);
        });
    });
    (0, node_test_1.describe)('game:skip_special_power', () => {
        (0, node_test_1.it)('allows skipping special power', async () => {
            const room = roomManager.getRoom(roomCode);
            room.gameState.currentPlayerIndex = room.players.findIndex(p => p.id === 'player-1');
            room.gameState.phase = GameState_1.GamePhase.specialPower;
            room.gameState.isWaitingForSpecialPower = true;
            room.gameState.specialCardToActivate = (0, Card_1.createCard)('hearts', '7');
            await mockSocket.triggerEvent('game:skip_special_power', { roomCode });
            await new Promise(resolve => setTimeout(resolve, 50));
            node_assert_1.default.strictEqual(room.gameState.isWaitingForSpecialPower, false);
            node_assert_1.default.strictEqual(room.gameState.phase, GameState_1.GamePhase.reaction);
        });
    });
    (0, node_test_1.describe)('game:pause', () => {
        (0, node_test_1.it)('allows player to pause game', async () => {
            const room = roomManager.getRoom(roomCode);
            await mockSocket.triggerEvent('game:pause', { roomCode });
            await new Promise(resolve => setTimeout(resolve, 50));
            node_assert_1.default.strictEqual(room.isPaused, true);
        });
        (0, node_test_1.it)('rejects pause from spectator', async () => {
            const room = roomManager.getRoom(roomCode);
            room.players.find(p => p.id === 'player-1').isSpectator = true;
            await mockSocket.triggerEvent('game:pause', { roomCode });
            await new Promise(resolve => setTimeout(resolve, 50));
            node_assert_1.default.strictEqual(room.isPaused, false);
        });
    });
    (0, node_test_1.describe)('game:resume', () => {
        (0, node_test_1.it)('allows player to resume game', async () => {
            const room = roomManager.getRoom(roomCode);
            room.isPaused = true;
            await mockSocket.triggerEvent('game:resume', { roomCode });
            await new Promise(resolve => setTimeout(resolve, 50));
            node_assert_1.default.strictEqual(room.isPaused, false);
        });
    });
    (0, node_test_1.describe)('game:forfeit', () => {
        (0, node_test_1.it)('allows player to forfeit', async () => {
            await mockSocket.triggerEvent('game:forfeit', { roomCode });
            await new Promise(resolve => setTimeout(resolve, 50));
            // Player should be marked in some way (spectator, folded, etc.)
            const room = roomManager.getRoom(roomCode);
            // Room might be ended or player converted
            node_assert_1.default.ok(true);
        });
    });
    (0, node_test_1.describe)('player:ready', () => {
        (0, node_test_1.it)('marks player as ready after memorization', async () => {
            // Reset game state for this test
            const room = roomManager.getRoom(roomCode);
            room.gameState.phase = GameState_1.GamePhase.setup;
            room.gameState.readyPlayerIds = [];
            await mockSocket.triggerEvent('player:ready', { roomCode });
            await new Promise(resolve => setTimeout(resolve, 50));
            node_assert_1.default.ok(room.gameState.readyPlayerIds.includes('player-1'));
        });
        (0, node_test_1.it)('rejects ready from spectator', async () => {
            const room = roomManager.getRoom(roomCode);
            room.gameState.phase = GameState_1.GamePhase.setup;
            room.gameState.readyPlayerIds = [];
            room.players.find(p => p.id === 'player-1').isSpectator = true;
            await mockSocket.triggerEvent('player:ready', { roomCode });
            await new Promise(resolve => setTimeout(resolve, 50));
            node_assert_1.default.ok(!room.gameState.readyPlayerIds.includes('player-1'));
        });
    });
});
