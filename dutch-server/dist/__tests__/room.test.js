"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const node_assert_1 = __importDefault(require("node:assert"));
const Room_1 = require("../models/Room");
const GameState_1 = require("../models/GameState");
(0, node_test_1.describe)('Room', () => {
    const defaultSettings = {
        gameMode: GameState_1.GameMode.quick,
        botDifficulty: 1,
        luckDifficulty: 1,
        reactionTimeMs: 3000,
        minPlayers: 2,
        maxPlayers: 4,
        fillBots: true,
    };
    (0, node_test_1.describe)('createRoom', () => {
        (0, node_test_1.it)('creates a room with correct initial values', () => {
            const expiresAt = Date.now() + 3600000; // 1 hour
            const room = (0, Room_1.createRoom)('ABC123', 'host-1', defaultSettings, expiresAt);
            node_assert_1.default.strictEqual(room.id, 'ABC123');
            node_assert_1.default.strictEqual(room.hostPlayerId, 'host-1');
            node_assert_1.default.strictEqual(room.status, Room_1.RoomStatus.waiting);
            node_assert_1.default.strictEqual(room.gameState, null);
            node_assert_1.default.deepStrictEqual(room.players, []);
            node_assert_1.default.strictEqual(room.expiresAt, expiresAt);
            node_assert_1.default.strictEqual(room.tournamentRound, 1);
            node_assert_1.default.strictEqual(room.isPaused, false);
        });
        (0, node_test_1.it)('copies game mode from settings', () => {
            const tournamentSettings = {
                ...defaultSettings,
                gameMode: GameState_1.GameMode.tournament,
            };
            const room = (0, Room_1.createRoom)('DEF456', 'host-2', tournamentSettings, Date.now() + 3600000);
            node_assert_1.default.strictEqual(room.gameMode, GameState_1.GameMode.tournament);
        });
        (0, node_test_1.it)('sets createdAt to current time', () => {
            const beforeCreate = new Date();
            const room = (0, Room_1.createRoom)('GHI789', 'host-3', defaultSettings, Date.now() + 3600000);
            const afterCreate = new Date();
            node_assert_1.default.ok(room.createdAt >= beforeCreate);
            node_assert_1.default.ok(room.createdAt <= afterCreate);
        });
        (0, node_test_1.it)('sets lastActivityAt to current timestamp', () => {
            const before = Date.now();
            const room = (0, Room_1.createRoom)('JKL012', 'host-4', defaultSettings, Date.now() + 3600000);
            const after = Date.now();
            node_assert_1.default.ok(room.lastActivityAt >= before);
            node_assert_1.default.ok(room.lastActivityAt <= after);
        });
        (0, node_test_1.it)('stores settings correctly', () => {
            const customSettings = {
                gameMode: GameState_1.GameMode.tournament,
                botDifficulty: 2,
                luckDifficulty: 0,
                reactionTimeMs: 5000,
                minPlayers: 3,
                maxPlayers: 4,
                fillBots: false,
            };
            const room = (0, Room_1.createRoom)('MNO345', 'host-5', customSettings, Date.now() + 3600000);
            node_assert_1.default.strictEqual(room.settings.reactionTimeMs, 5000);
            node_assert_1.default.strictEqual(room.settings.minPlayers, 3);
            node_assert_1.default.strictEqual(room.settings.fillBots, false);
        });
    });
    (0, node_test_1.describe)('RoomStatus', () => {
        (0, node_test_1.it)('has all expected status values', () => {
            node_assert_1.default.strictEqual(Room_1.RoomStatus.waiting, 'waiting');
            node_assert_1.default.strictEqual(Room_1.RoomStatus.playing, 'playing');
            node_assert_1.default.strictEqual(Room_1.RoomStatus.ended, 'ended');
            node_assert_1.default.strictEqual(Room_1.RoomStatus.closing, 'closing');
        });
    });
});
//# sourceMappingURL=room.test.js.map