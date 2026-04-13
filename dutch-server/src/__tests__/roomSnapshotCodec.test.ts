import test from 'node:test';
import assert from 'node:assert/strict';
import { createCard } from '../models/Card';
import { createGameState, GameMode, Difficulty } from '../models/GameState';
import { createPlayer } from '../models/Player';
import { createRoom } from '../models/Room';
import { RoomSnapshotCodec } from '../services/RoomSnapshotCodec';

test('RoomSnapshotCodec préserve les structures nécessaires à la reprise Redis', () => {
  const host = createPlayer(
    'socket-host',
    'Hôte',
    true,
    0,
    undefined,
    undefined,
    'client-host',
    'uid-host',
    'host'
  );
  const guest = createPlayer(
    'socket-guest',
    'Invité',
    true,
    1,
    undefined,
    undefined,
    'client-guest',
    'uid-guest',
    'guest'
  );

  const room = createRoom(
    'ABC123',
    host.id,
    {
      gameMode: GameMode.quick,
      botDifficulty: Difficulty.medium,
      luckDifficulty: Difficulty.easy,
      reactionTimeMs: 3500,
      minPlayers: 2,
      maxPlayers: 4,
      fillBots: false,
    },
    Date.now() + 60_000,
    host.userId
  );

  room.players.push(host, guest);
  room.createdAt = new Date('2026-04-13T10:15:30.000Z');
  room.bannedClientIds = new Set(['banned-a', 'banned-b']);
  room.playersInResults = new Set([guest.id]);
  room.cumulativeScores = new Map([
    [host.id, 42],
    [guest.id, 17],
  ]);
  room.isPaused = true;
  room.pausedByPlayerId = host.id;
  room.pausedByName = host.name;
  room.pauseStartTime = Date.parse('2026-04-13T10:16:30.000Z');

  room.gameState = createGameState(room.players, GameMode.quick, Difficulty.medium);
  room.gameState.deck = [createCard('hearts', '7')];
  room.gameState.discardPile = [createCard('spades', 'R')];
  room.gameState.reactionStartTime = new Date('2026-04-13T10:16:00.000Z');
  room.gameState.reactionTimeRemaining = 2800;
  room.gameState.reactionDeadlineAt = Date.parse('2026-04-13T10:16:03.500Z');
  room.gameState.readyPlayerIds = [host.id];
  room.gameState.turnStartTime = Date.parse('2026-04-13T10:16:40.000Z');
  room.gameState.turnTimeoutMs = 90_000;

  const restored = RoomSnapshotCodec.deserialize(
    RoomSnapshotCodec.serialize(room)
  );

  assert.equal(restored.id, room.id);
  assert.equal(restored.createdAt.toISOString(), room.createdAt.toISOString());
  assert.deepEqual(
    Array.from(restored.bannedClientIds ?? []),
    ['banned-a', 'banned-b']
  );
  assert.deepEqual(
    Array.from(restored.playersInResults ?? []),
    [guest.id]
  );
  assert.deepEqual(
    Array.from(restored.cumulativeScores?.entries() ?? []),
    Array.from(room.cumulativeScores?.entries() ?? [])
  );
  assert.ok(restored.gameState);
  assert.equal(
    restored.gameState?.reactionStartTime?.toISOString(),
    '2026-04-13T10:16:00.000Z'
  );
  assert.equal(restored.gameState?.reactionTimeRemaining, 2800);
  assert.equal(
    restored.gameState?.reactionDeadlineAt,
    Date.parse('2026-04-13T10:16:03.500Z')
  );
  assert.equal(
    restored.gameState?.turnStartTime,
    Date.parse('2026-04-13T10:16:40.000Z')
  );
  assert.equal(restored.gameState?.turnTimeoutMs, 90_000);
  assert.equal(restored.isPaused, true);
  assert.equal(restored.pausedByPlayerId, host.id);
  assert.equal(restored.pausedByName, host.name);
  assert.equal(
    restored.pauseStartTime,
    Date.parse('2026-04-13T10:16:30.000Z')
  );
  assert.equal(restored.gameState?.discardPile[0].id, 'R_spades');
});
