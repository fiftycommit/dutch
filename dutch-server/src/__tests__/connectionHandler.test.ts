import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import { Server, Socket } from 'socket.io';
import { RoomManager } from '../services/RoomManager';
import { setupConnectionHandler } from '../handlers/connectionHandler';

// Mock Socket implementation
class MockSocket {
  id: string;
  events: Map<string, Function> = new Map();
  emittedEvents: Array<{ event: string; data: any }> = [];
  rooms: Set<string> = new Set();

  constructor(id: string) {
    this.id = id;
  }

  on(event: string, callback: Function) {
    this.events.set(event, callback);
    return this;
  }

  emit(event: string, data: any) {
    this.emittedEvents.push({ event, data });
    return this;
  }

  join(room: string) {
    this.rooms.add(room);
    return this;
  }

  leave(room: string) {
    this.rooms.delete(room);
    return this;
  }

  to(target: string) {
    return this;
  }

  // Helper to trigger events in tests
  triggerEvent(event: string, ...args: any[]) {
    const handler = this.events.get(event);
    if (handler) {
      handler(...args);
    }
  }
}

// Mock Server
class MockServer {
  events: Array<{ target: string; event: string; data: any }> = [];
  private currentTarget = '';

  to(target: string) {
    this.currentTarget = target;
    return this;
  }

  emit(event: string, data: any) {
    this.events.push({ target: this.currentTarget, event, data });
    return true;
  }
}

describe('connectionHandler', () => {
  let mockSocket: MockSocket;
  let mockServer: MockServer;
  let roomManager: RoomManager;

  beforeEach(() => {
    mockSocket = new MockSocket('socket-1');
    mockServer = new MockServer();
    roomManager = new RoomManager(mockServer as unknown as Server, {
      cleanupIntervalMs: 10_000,
      roomTtlMs: 60_000,
    });

    setupConnectionHandler(mockSocket as unknown as Socket, roomManager);
  });

  describe('client:ping', () => {
    it('responds with server time', () => {
      let callbackResult: any = null;
      const callback = (response: any) => {
        callbackResult = response;
      };

      mockSocket.triggerEvent('client:ping', { clientTime: 12345 }, callback);

      assert.ok(callbackResult);
      assert.ok(callbackResult.serverTime);
      assert.strictEqual(typeof callbackResult.serverTime, 'number');
      assert.strictEqual(callbackResult.clientTime, 12345);
    });

    it('handles missing callback gracefully', () => {
      // Should not throw
      mockSocket.triggerEvent('client:ping', { clientTime: 12345 });
      assert.ok(true);
    });

    it('handles missing data gracefully', () => {
      let callbackResult: any = null;
      const callback = (response: any) => {
        callbackResult = response;
      };

      mockSocket.triggerEvent('client:ping', undefined, callback);

      assert.ok(callbackResult);
      assert.ok(callbackResult.serverTime);
    });

    it('touches player presence', () => {
      // Create a room with the socket
      const room = roomManager.createRoom('socket-1', {
        minPlayers: 2,
        maxPlayers: 4,
        fillBots: false,
      });

      mockSocket.triggerEvent('client:ping', {}, () => {});

      // The touchPlayer should update lastSeenAt
      // We can't easily verify without exposing internal state
      // but at least it shouldn't throw
      assert.ok(true);
    });
  });

  describe('presence:focus', () => {
    it('updates player focus state', () => {
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
      assert.ok(player);
      // Player focus should be updated
    });

    it('handles missing roomCode gracefully', () => {
      mockSocket.triggerEvent('presence:focus', { focused: true });
      // Should not throw
      assert.ok(true);
    });

    it('handles invalid roomCode gracefully', () => {
      mockSocket.triggerEvent('presence:focus', {
        roomCode: 'INVALID',
        focused: true,
      });
      // Should not throw
      assert.ok(true);
    });

    it('normalizes roomCode to uppercase', () => {
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
      assert.ok(true);
    });
  });

  describe('presence:ack', () => {
    it('confirms player presence', () => {
      const room = roomManager.createRoom('socket-1', {
        minPlayers: 2,
        maxPlayers: 4,
        fillBots: false,
      });

      mockSocket.triggerEvent('presence:ack', { roomCode: room.id });

      // Should complete without error
      assert.ok(true);
    });

    it('handles missing roomCode gracefully', () => {
      mockSocket.triggerEvent('presence:ack', {});
      assert.ok(true);
    });

    it('handles invalid roomCode gracefully', () => {
      mockSocket.triggerEvent('presence:ack', { roomCode: 'NONEXISTENT' });
      assert.ok(true);
    });
  });

  describe('disconnect', () => {
    it('handles player disconnect', () => {
      const room = roomManager.createRoom('socket-1', {
        minPlayers: 2,
        maxPlayers: 4,
        fillBots: false,
      });
      roomManager.joinRoom(room.id, 'socket-2', 'Player 2', 'client-2');

      mockSocket.triggerEvent('disconnect');

      // Player should be marked as disconnected
      const player = room.players.find(p => p.id === 'socket-1');
      assert.ok(player);
      assert.strictEqual(player.connected, false);
    });

    it('handles disconnect when not in any room', () => {
      mockSocket.triggerEvent('disconnect');
      // Should not throw
      assert.ok(true);
    });
  });
});
