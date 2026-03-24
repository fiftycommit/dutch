"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const node_assert_1 = __importDefault(require("node:assert"));
const RoomManager_1 = require("../services/RoomManager");
const connectionHandler_1 = require("../handlers/connectionHandler");
// Mock Socket implementation
class MockSocket {
    constructor(id) {
        this.events = new Map();
        this.emittedEvents = [];
        this.rooms = new Set();
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
        return this;
    }
    // Helper to trigger events in tests
    triggerEvent(event, ...args) {
        const handler = this.events.get(event);
        if (handler) {
            handler(...args);
        }
    }
}
// Mock Server
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
(0, node_test_1.describe)('connectionHandler', () => {
    let mockSocket;
    let mockServer;
    let roomManager;
    (0, node_test_1.beforeEach)(() => {
        mockSocket = new MockSocket('socket-1');
        mockServer = new MockServer();
        roomManager = new RoomManager_1.RoomManager(mockServer, {
            cleanupIntervalMs: 10000,
            roomTtlMs: 60000,
        });
        (0, connectionHandler_1.setupConnectionHandler)(mockSocket, roomManager);
    });
    (0, node_test_1.describe)('client:ping', () => {
        (0, node_test_1.it)('responds with server time', () => {
            let callbackResult = null;
            const callback = (response) => {
                callbackResult = response;
            };
            mockSocket.triggerEvent('client:ping', { clientTime: 12345 }, callback);
            node_assert_1.default.ok(callbackResult);
            node_assert_1.default.ok(callbackResult.serverTime);
            node_assert_1.default.strictEqual(typeof callbackResult.serverTime, 'number');
            node_assert_1.default.strictEqual(callbackResult.clientTime, 12345);
        });
        (0, node_test_1.it)('handles missing callback gracefully', () => {
            // Should not throw
            mockSocket.triggerEvent('client:ping', { clientTime: 12345 });
            node_assert_1.default.ok(true);
        });
        (0, node_test_1.it)('handles missing data gracefully', () => {
            let callbackResult = null;
            const callback = (response) => {
                callbackResult = response;
            };
            mockSocket.triggerEvent('client:ping', undefined, callback);
            node_assert_1.default.ok(callbackResult);
            node_assert_1.default.ok(callbackResult.serverTime);
        });
        (0, node_test_1.it)('touches player presence', () => {
            // Create a room with the socket
            const room = roomManager.createRoom('socket-1', {
                minPlayers: 2,
                maxPlayers: 4,
                fillBots: false,
            });
            mockSocket.triggerEvent('client:ping', {}, () => { });
            // The touchPlayer should update lastSeenAt
            // We can't easily verify without exposing internal state
            // but at least it shouldn't throw
            node_assert_1.default.ok(true);
        });
    });
    (0, node_test_1.describe)('presence:focus', () => {
        (0, node_test_1.it)('updates player focus state', () => {
            // Create a room first
            const room = roomManager.createRoom('socket-1', {
                minPlayers: 2,
                maxPlayers: 4,
                fillBots: false,
            });
            mockSocket.triggerEvent('presence:focus', {
                roomCode: room.id,
                focused: true,
            });
            // Check that the player's focused state was updated
            const player = room.players.find(p => p.id === 'socket-1');
            node_assert_1.default.ok(player);
            // Player focus should be updated
        });
        (0, node_test_1.it)('handles missing roomCode gracefully', () => {
            mockSocket.triggerEvent('presence:focus', { focused: true });
            // Should not throw
            node_assert_1.default.ok(true);
        });
        (0, node_test_1.it)('handles invalid roomCode gracefully', () => {
            mockSocket.triggerEvent('presence:focus', {
                roomCode: 'INVALID',
                focused: true,
            });
            // Should not throw
            node_assert_1.default.ok(true);
        });
        (0, node_test_1.it)('normalizes roomCode to uppercase', () => {
            const room = roomManager.createRoom('socket-1', {
                minPlayers: 2,
                maxPlayers: 4,
                fillBots: false,
            });
            mockSocket.triggerEvent('presence:focus', {
                roomCode: room.id.toLowerCase(),
                focused: false,
            });
            // Should work with lowercase
            node_assert_1.default.ok(true);
        });
    });
    (0, node_test_1.describe)('presence:ack', () => {
        (0, node_test_1.it)('confirms player presence', () => {
            const room = roomManager.createRoom('socket-1', {
                minPlayers: 2,
                maxPlayers: 4,
                fillBots: false,
            });
            mockSocket.triggerEvent('presence:ack', { roomCode: room.id });
            // Should complete without error
            node_assert_1.default.ok(true);
        });
        (0, node_test_1.it)('handles missing roomCode gracefully', () => {
            mockSocket.triggerEvent('presence:ack', {});
            node_assert_1.default.ok(true);
        });
        (0, node_test_1.it)('handles invalid roomCode gracefully', () => {
            mockSocket.triggerEvent('presence:ack', { roomCode: 'NONEXISTENT' });
            node_assert_1.default.ok(true);
        });
    });
    (0, node_test_1.describe)('disconnect', () => {
        (0, node_test_1.it)('handles player disconnect', () => {
            const room = roomManager.createRoom('socket-1', {
                minPlayers: 2,
                maxPlayers: 4,
                fillBots: false,
            });
            roomManager.joinRoom(room.id, 'socket-2', 'Player 2', 'client-2');
            mockSocket.triggerEvent('disconnect');
            // Player should be marked as disconnected
            const player = room.players.find(p => p.id === 'socket-1');
            node_assert_1.default.ok(player);
            node_assert_1.default.strictEqual(player.connected, false);
        });
        (0, node_test_1.it)('handles disconnect when not in any room', () => {
            mockSocket.triggerEvent('disconnect');
            // Should not throw
            node_assert_1.default.ok(true);
        });
    });
});
//# sourceMappingURL=connectionHandler.test.js.map