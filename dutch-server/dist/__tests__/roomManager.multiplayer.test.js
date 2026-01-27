"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = __importDefault(require("node:test"));
const strict_1 = __importDefault(require("node:assert/strict"));
const RoomManager_1 = require("../services/RoomManager");
const GameState_1 = require("../models/GameState");
class FakeServer {
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
    findEventsFor(target, event) {
        return this.events.filter((e) => e.target === target && e.event === event);
    }
}
function createManager(options = {}) {
    const io = new FakeServer();
    const manager = new RoomManager_1.RoomManager(io, {
        cleanupIntervalMs: 10000,
        roomTtlMs: 60000,
        ...options,
    });
    return { io, manager };
}
(0, node_test_1.default)('startGame enforces minPlayers and respects fillBots=false', (t) => {
    const { manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-1', {
        minPlayers: 3,
        maxPlayers: 4,
        fillBots: false,
    });
    manager.joinRoom(room.id, 'p2', 'P2', 'c2');
    const startedTooEarly = manager.startGame(room.id);
    strict_1.default.equal(startedTooEarly, false);
    strict_1.default.equal(room.status, 'waiting');
    strict_1.default.equal(room.gameState, null);
    manager.joinRoom(room.id, 'p3', 'P3', 'c3');
    const started = manager.startGame(room.id);
    strict_1.default.equal(started, true);
    strict_1.default.ok(room.gameState);
    const humanCount = room.players.filter((p) => p.isHuman).length;
    strict_1.default.equal(humanCount, 3);
    strict_1.default.equal(room.players.length, 3);
});
(0, node_test_1.default)('startGame fills bots up to maxPlayers when fillBots=true', (t) => {
    const { manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-2', {
        minPlayers: 2,
        maxPlayers: 4,
        fillBots: true,
    });
    manager.joinRoom(room.id, 'p2', 'P2', 'c2');
    const started = manager.startGame(room.id);
    strict_1.default.equal(started, true);
    strict_1.default.ok(room.gameState);
    const humanCount = room.players.filter((p) => p.isHuman).length;
    strict_1.default.equal(humanCount, 2);
    strict_1.default.equal(room.players.length, 4);
});
(0, node_test_1.default)('turn timeout triggers presence check then spectator', async (t) => {
    const { io, manager } = createManager({
        turnTimeoutMs: 40,
        presenceGraceMs: 40,
        cleanupIntervalMs: 10000,
        roomTtlMs: 60000,
    });
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-3', {
        minPlayers: 2,
        maxPlayers: 2,
        fillBots: false,
    });
    manager.joinRoom(room.id, 'p2', 'P2', 'c2');
    const started = manager.startGame(room.id);
    strict_1.default.equal(started, true);
    strict_1.default.ok(room.gameState);
    const currentPlayerId = (0, GameState_1.getCurrentPlayer)(room.gameState).id;
    const otherPlayerId = room.players.find((p) => p.id !== currentPlayerId).id;
    await new Promise((resolve) => setTimeout(resolve, 70));
    const checkEvents = io.findEventsFor(currentPlayerId, 'presence:check');
    strict_1.default.ok(checkEvents.length >= 1);
    await new Promise((resolve) => setTimeout(resolve, 80));
    const timedOutPlayer = room.players.find((p) => p.id === currentPlayerId);
    strict_1.default.equal(timedOutPlayer.isSpectator, true);
    strict_1.default.notEqual((0, GameState_1.getCurrentPlayer)(room.gameState).id, currentPlayerId);
    strict_1.default.equal((0, GameState_1.getCurrentPlayer)(room.gameState).id, otherPlayerId);
});
(0, node_test_1.default)('cleanup removes room on TTL expiration', async (t) => {
    const { manager } = createManager({
        roomTtlMs: 50,
        cleanupIntervalMs: 20,
    });
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-4', {
        minPlayers: 2,
        maxPlayers: 4,
        fillBots: true,
    });
    await new Promise((resolve) => setTimeout(resolve, 120));
    strict_1.default.equal(manager.getRoom(room.id), undefined);
});
(0, node_test_1.default)('cleanup removes room when all humans disconnect', async (t) => {
    const { manager } = createManager({
        roomTtlMs: 60000,
        cleanupIntervalMs: 20,
    });
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-5', {
        minPlayers: 2,
        maxPlayers: 4,
        fillBots: false,
    });
    manager.joinRoom(room.id, 'p2', 'P2', 'c2');
    manager.handleDisconnect('host-5');
    manager.handleDisconnect('p2');
    await new Promise((resolve) => setTimeout(resolve, 80));
    strict_1.default.equal(manager.getRoom(room.id), undefined);
});
