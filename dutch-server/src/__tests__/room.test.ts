import { describe, it } from 'node:test';
import assert from 'node:assert';
import { createRoom, Room, RoomStatus, GameSettings } from '../models/Room';
import { GameMode } from '../models/GameState';

describe('Room', () => {
  const defaultSettings: GameSettings = {
    gameMode: GameMode.quick,
    botDifficulty: 1,
    luckDifficulty: 1,
    reactionTimeMs: 3000,
    minPlayers: 2,
    maxPlayers: 4,
    fillBots: true,
  };

  describe('createRoom', () => {
    it('creates a room with correct initial values', () => {
      const expiresAt = Date.now() + 3600000; // 1 hour
      const room = createRoom('ABC123', 'host-1', defaultSettings, expiresAt);

      assert.strictEqual(room.id, 'ABC123');
      assert.strictEqual(room.hostPlayerId, 'host-1');
      assert.strictEqual(room.status, RoomStatus.waiting);
      assert.strictEqual(room.gameState, null);
      assert.deepStrictEqual(room.players, []);
      assert.strictEqual(room.expiresAt, expiresAt);
      assert.strictEqual(room.tournamentRound, 1);
      assert.strictEqual(room.isPaused, false);
    });

    it('copies game mode from settings', () => {
      const tournamentSettings: GameSettings = {
        ...defaultSettings,
        gameMode: GameMode.tournament,
      };
      const room = createRoom('DEF456', 'host-2', tournamentSettings, Date.now() + 3600000);

      assert.strictEqual(room.gameMode, GameMode.tournament);
    });

    it('sets createdAt to current time', () => {
      const beforeCreate = new Date();
      const room = createRoom('GHI789', 'host-3', defaultSettings, Date.now() + 3600000);
      const afterCreate = new Date();

      assert.ok(room.createdAt >= beforeCreate);
      assert.ok(room.createdAt <= afterCreate);
    });

    it('sets lastActivityAt to current timestamp', () => {
      const before = Date.now();
      const room = createRoom('JKL012', 'host-4', defaultSettings, Date.now() + 3600000);
      const after = Date.now();

      assert.ok(room.lastActivityAt >= before);
      assert.ok(room.lastActivityAt <= after);
    });

    it('stores settings correctly', () => {
      const customSettings: GameSettings = {
        gameMode: GameMode.tournament,
        botDifficulty: 2,
        luckDifficulty: 0,
        reactionTimeMs: 5000,
        minPlayers: 3,
        maxPlayers: 4,
        fillBots: false,
      };
      const room = createRoom('MNO345', 'host-5', customSettings, Date.now() + 3600000);

      assert.strictEqual(room.settings.reactionTimeMs, 5000);
      assert.strictEqual(room.settings.minPlayers, 3);
      assert.strictEqual(room.settings.fillBots, false);
    });
  });

  describe('RoomStatus', () => {
    it('has all expected status values', () => {
      assert.strictEqual(RoomStatus.waiting, 'waiting');
      assert.strictEqual(RoomStatus.playing, 'playing');
      assert.strictEqual(RoomStatus.ended, 'ended');
      assert.strictEqual(RoomStatus.closing, 'closing');
    });
  });
});
