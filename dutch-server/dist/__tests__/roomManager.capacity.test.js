"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = __importDefault(require("node:test"));
const strict_1 = __importDefault(require("node:assert/strict"));
const RoomManager_1 = require("../services/RoomManager");
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
}
function createManager() {
    const io = new FakeServer();
    const manager = new RoomManager_1.RoomManager(io, {
        cleanupIntervalMs: 10000,
        roomTtlMs: 60000,
    });
    return { io, manager };
}
// ============ Tests de capacité des rooms ============
(0, node_test_1.default)('5th player cannot join a room with maxPlayers=4', (t) => {
    const { manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-1', {
        minPlayers: 2,
        maxPlayers: 4,
        fillBots: false,
    });
    // Rejoindre avec 3 autres joueurs (total 4 avec l'hôte)
    manager.joinRoom(room.id, 'p2', 'P2', 'c2');
    manager.joinRoom(room.id, 'p3', 'P3', 'c3');
    manager.joinRoom(room.id, 'p4', 'P4', 'c4');
    strict_1.default.equal(room.players.length, 4, 'Room should have 4 players');
    // Tenter de rejoindre avec un 5ème joueur
    const result = manager.joinRoom(room.id, 'p5', 'P5', 'c5');
    strict_1.default.equal(result.error, 'Room is full', 'Should return error message');
    strict_1.default.equal(result.room, undefined, 'Should not return room');
    strict_1.default.equal(room.players.length, 4, 'Room should still have 4 players');
    // Vérifier que le 5ème joueur n'est pas dans la room
    const p5InRoom = room.players.find((p) => p.id === 'p5');
    strict_1.default.equal(p5InRoom, undefined, 'P5 should not be in room');
});
(0, node_test_1.default)('player can join room with exactly maxPlayers slots', (t) => {
    const { manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-2', {
        minPlayers: 2,
        maxPlayers: 4,
        fillBots: false,
    });
    // Rejoindre avec 2 autres joueurs (total 3)
    manager.joinRoom(room.id, 'p2', 'P2', 'c2');
    manager.joinRoom(room.id, 'p3', 'P3', 'c3');
    strict_1.default.equal(room.players.length, 3);
    // Le 4ème joueur doit pouvoir rejoindre
    const result = manager.joinRoom(room.id, 'p4', 'P4', 'c4');
    strict_1.default.equal(result.error, undefined, 'Should not have error');
    strict_1.default.ok(result.room, 'Should return room');
    strict_1.default.equal(room.players.length, 4, 'Room should have 4 players');
});
(0, node_test_1.default)('room with maxPlayers=2 rejects 3rd player', (t) => {
    const { manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-3', {
        minPlayers: 2,
        maxPlayers: 2,
        fillBots: false,
    });
    // Rejoindre avec 1 autre joueur (total 2)
    const result1 = manager.joinRoom(room.id, 'p2', 'P2', 'c2');
    strict_1.default.ok(result1.room, 'P2 should join successfully');
    strict_1.default.equal(room.players.length, 2);
    // Tenter de rejoindre avec un 3ème joueur
    const result2 = manager.joinRoom(room.id, 'p3', 'P3', 'c3');
    strict_1.default.equal(result2.error, 'Room is full');
    strict_1.default.equal(room.players.length, 2, 'Room should still have 2 players');
});
(0, node_test_1.default)('disconnected player can rejoin without counting toward capacity', (t) => {
    const { manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-4', {
        minPlayers: 2,
        maxPlayers: 4,
        fillBots: false,
    });
    manager.joinRoom(room.id, 'p2', 'P2', 'c2');
    manager.joinRoom(room.id, 'p3', 'P3', 'c3');
    manager.joinRoom(room.id, 'p4', 'P4', 'c4');
    strict_1.default.equal(room.players.length, 4);
    // P2 se déconnecte
    manager.handleDisconnect('p2');
    const p2 = room.players.find((p) => p.id === 'p2');
    strict_1.default.equal(p2?.connected, false, 'P2 should be disconnected');
    // P2 peut se reconnecter (même socket ID ou nouveau)
    const reconnectResult = manager.joinRoom(room.id, 'p2-new', 'P2', 'c2');
    strict_1.default.ok(reconnectResult.room, 'P2 should be able to reconnect');
    strict_1.default.equal(room.players.length, 4, 'Room should still have 4 players');
});
(0, node_test_1.default)('room with maxPlayers=6 accepts 6 players', (t) => {
    const { manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-6', {
        minPlayers: 2,
        maxPlayers: 6,
        fillBots: false,
    });
    // Rejoindre avec 5 autres joueurs
    for (let i = 2; i <= 6; i++) {
        const result = manager.joinRoom(room.id, `p${i}`, `P${i}`, `c${i}`);
        strict_1.default.ok(result.room, `P${i} should join successfully`);
    }
    strict_1.default.equal(room.players.length, 6, 'Room should have 6 players');
    // Le 7ème joueur ne peut pas rejoindre
    const result = manager.joinRoom(room.id, 'p7', 'P7', 'c7');
    strict_1.default.equal(result.error, 'Room is full');
    strict_1.default.equal(room.players.length, 6);
});
(0, node_test_1.default)('public room becomes unavailable when full', (t) => {
    const { manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-public', {
        minPlayers: 2,
        maxPlayers: 3,
        fillBots: false,
        isPublic: true,
    });
    manager.joinRoom(room.id, 'p2', 'P2', 'c2');
    // Room pas encore pleine, devrait être visible
    strict_1.default.equal(room.players.length, 2);
    // Remplir la room
    manager.joinRoom(room.id, 'p3', 'P3', 'c3');
    strict_1.default.equal(room.players.length, 3);
    // Vérifier qu'un 4ème joueur ne peut pas rejoindre
    const result = manager.joinRoom(room.id, 'p4', 'P4', 'c4');
    strict_1.default.equal(result.error, 'Room is full');
});
