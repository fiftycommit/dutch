import test from 'node:test';
import assert from 'node:assert/strict';
import { Server } from 'socket.io';
import { RoomManager } from '../services/RoomManager';
import { getCurrentPlayer } from '../models/GameState';

type EmittedEvent = {
  target: string;
  event: string;
  data: any;
};

class FakeServer {
  events: EmittedEvent[] = [];
  private currentTarget = '';

  to(target: string) {
    this.currentTarget = target;
    return this;
  }

  emit(event: string, data: any) {
    this.events.push({ target: this.currentTarget, event, data });
    return true;
  }

  findEventsFor(target: string, event: string) {
    return this.events.filter((e) => e.target === target && e.event === event);
  }
}

function createManager(
  options: Partial<ConstructorParameters<typeof RoomManager>[1]> = {}
) {
  const io = new FakeServer();
  const manager = new RoomManager(io as unknown as Server, {
    cleanupIntervalMs: 10_000,
    roomTtlMs: 60_000,
    ...options,
  });
  return { io, manager };
}

test('startGame enforces minPlayers and respects fillBots=false', (t) => {
  const { manager } = createManager();
  t.after(() => manager.dispose());

  const room = manager.createRoom('host-1', {
    minPlayers: 3,
    maxPlayers: 4,
    fillBots: false,
  });

  manager.joinRoom(room.id, 'p2', 'P2', 'c2');

  const startedTooEarly = manager.startGame(room.id);
  assert.equal(startedTooEarly, false);
  assert.equal(room.status, 'waiting');
  assert.equal(room.gameState, null);

  manager.joinRoom(room.id, 'p3', 'P3', 'c3');
  const started = manager.startGame(room.id);
  assert.equal(started, true);
  assert.ok(room.gameState);

  const humanCount = room.players.filter((p) => p.isHuman).length;
  assert.equal(humanCount, 3);
  assert.equal(room.players.length, 3);
});

test('startGame fills bots up to maxPlayers when fillBots=true', (t) => {
  const { manager } = createManager();
  t.after(() => manager.dispose());

  const room = manager.createRoom('host-2', {
    minPlayers: 2,
    maxPlayers: 4,
    fillBots: true,
  });

  manager.joinRoom(room.id, 'p2', 'P2', 'c2');

  const started = manager.startGame(room.id);
  assert.equal(started, true);
  assert.ok(room.gameState);

  const humanCount = room.players.filter((p) => p.isHuman).length;
  assert.equal(humanCount, 2);
  assert.equal(room.players.length, 4);
});

test('turn timeout triggers presence check then spectator', async (t) => {
  const { io, manager } = createManager({
    turnTimeoutMs: 40,
    presenceGraceMs: 40,
    cleanupIntervalMs: 10_000,
    roomTtlMs: 60_000,
  });
  t.after(() => manager.dispose());

  const room = manager.createRoom('host-3', {
    minPlayers: 2,
    maxPlayers: 2,
    fillBots: false,
  });
  manager.joinRoom(room.id, 'p2', 'P2', 'c2');

  const started = manager.startGame(room.id);
  assert.equal(started, true);
  assert.ok(room.gameState);

  const currentPlayerId = getCurrentPlayer(room.gameState!).id;
  const otherPlayerId = room.players.find((p) => p.id !== currentPlayerId)!.id;

  await new Promise((resolve) => setTimeout(resolve, 70));

  const checkEvents = io.findEventsFor(currentPlayerId, 'presence:check');
  assert.ok(checkEvents.length >= 1);

  await new Promise((resolve) => setTimeout(resolve, 80));

  const timedOutPlayer = room.players.find((p) => p.id === currentPlayerId)!;
  assert.equal(timedOutPlayer.isSpectator, true);
  assert.notEqual(getCurrentPlayer(room.gameState!).id, currentPlayerId);
  assert.equal(getCurrentPlayer(room.gameState!).id, otherPlayerId);
});

test('cleanup removes room on TTL expiration', async (t) => {
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

  assert.equal(manager.getRoom(room.id), undefined);
});

test('cleanup removes room when all humans disconnect', async (t) => {
  const { manager } = createManager({
    roomTtlMs: 60_000,
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

  assert.equal(manager.getRoom(room.id), undefined);
});
