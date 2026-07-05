import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createClient } from 'redis';
import { Server } from 'socket.io';
import { RoomManager } from '../services/RoomManager';
import { SharedRoomStore } from '../services/SharedRoomStore';

type RedisConnection = ReturnType<typeof createClient>;

class FakeServer {
  to() {
    return this;
  }

  emit() {
    return true;
  }
}

function createManager(store: SharedRoomStore) {
  const io = new FakeServer();
  return new RoomManager(io as unknown as Server, {
    cleanupIntervalMs: 60_000,
    roomTtlMs: 120_000,
    sharedRoomStore: store,
  });
}

async function createRedisClient(url: string): Promise<RedisConnection> {
  const client = createClient({ url });
  client.on('error', (error) => {
    console.error('[redis-test] client error:', error);
  });
  await client.connect();
  return client;
}

async function deleteKeysByPrefix(client: RedisConnection, prefix: string): Promise<void> {
  for await (const key of client.scanIterator({ MATCH: `${prefix}:*`, COUNT: 100 })) {
    await client.del(key);
  }
}

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

test('Redis-backed SharedRoomStore serializes concurrent room mutations across managers', async (t) => {
  const redisUrl = process.env.REDIS_URL;
  assert.ok(redisUrl, 'REDIS_URL est requis pour ce test Redis réel');

  const keyPrefix = `ci:${randomUUID()}`;
  const clientA = await createRedisClient(redisUrl);
  const clientB = await createRedisClient(redisUrl);
  const cleanupClient = await createRedisClient(redisUrl);

  const storeA = new SharedRoomStore(clientA, {
    keyPrefix,
    lockRetryDelayMs: 5,
    lockAcquireTimeoutMs: 1_000,
  });
  const storeB = new SharedRoomStore(clientB, {
    keyPrefix,
    lockRetryDelayMs: 5,
    lockAcquireTimeoutMs: 1_000,
  });
  const managerA = createManager(storeA);
  const managerB = createManager(storeB);

  t.after(async () => {
    managerA.dispose();
    managerB.dispose();
    await deleteKeysByPrefix(cleanupClient, keyPrefix);
    await Promise.all([clientA.quit(), clientB.quit(), cleanupClient.quit()]);
  });

  const room = managerA.createRoom('host-1', { minPlayers: 2, maxPlayers: 4 }, 'Host', 'c1', 'u1');
  await Promise.resolve();

  let releaseFirstMutation!: () => void;
  let first!: Promise<void>;
  const firstMutationEntered = new Promise<void>((resolve) => {
    first = managerA.withRoomMutation(room.id, async () => {
      resolve();
      await new Promise<void>((release) => {
        releaseFirstMutation = release;
      });
      const joined = managerA.joinRoom(room.id, 'p2', 'P2', 'c2', 'u2');
      assert.ok(joined.player);
    });
  });
  await firstMutationEntered;

  let secondMutationCompleted = false;
  const second = managerB.withRoomMutation(room.id, async () => {
    const joined = managerB.joinRoom(room.id, 'p3', 'P3', 'c3', 'u3');
    assert.ok(joined.player);
    secondMutationCompleted = true;
  });

  await wait(25);
  assert.equal(
    secondMutationCompleted,
    false,
    'Redis doit bloquer la seconde instance tant que le verrou de room est tenu'
  );

  releaseFirstMutation();
  await Promise.all([first, second]);

  const finalRoom = await storeA.loadRoom(room.id);
  assert.ok(finalRoom);
  assert.deepEqual(
    finalRoom.players.filter((player) => player.isHuman).map((player) => player.clientId).sort(),
    ['c1', 'c2', 'c3']
  );
  assert.equal(finalRoom.players.filter((player) => player.id === finalRoom.hostPlayerId).length, 1);
});

test('Redis-backed SharedRoomStore keeps transferred host and deduplicates racing reconnects', async (t) => {
  const redisUrl = process.env.REDIS_URL;
  assert.ok(redisUrl, 'REDIS_URL est requis pour ce test Redis réel');

  const keyPrefix = `ci:${randomUUID()}`;
  const clientA = await createRedisClient(redisUrl);
  const clientB = await createRedisClient(redisUrl);
  const cleanupClient = await createRedisClient(redisUrl);

  const storeA = new SharedRoomStore(clientA, {
    keyPrefix,
    lockRetryDelayMs: 5,
    lockAcquireTimeoutMs: 1_000,
  });
  const storeB = new SharedRoomStore(clientB, {
    keyPrefix,
    lockRetryDelayMs: 5,
    lockAcquireTimeoutMs: 1_000,
  });
  const managerA = createManager(storeA);
  const managerB = createManager(storeB);

  t.after(async () => {
    managerA.dispose();
    managerB.dispose();
    await deleteKeysByPrefix(cleanupClient, keyPrefix);
    await Promise.all([clientA.quit(), clientB.quit(), cleanupClient.quit()]);
  });

  const room = managerA.createRoom('host-1', { minPlayers: 2, maxPlayers: 4 }, 'P1', 'c1', 'u1');
  await Promise.resolve();

  await managerA.withRoomMutation(room.id, async () => {
    const joined = managerA.joinRoom(room.id, 'p2', 'P2', 'c2', 'u2');
    assert.ok(joined.player);
  });

  await managerA.withRoomMutation(room.id, async () => {
    managerA.handleDisconnect('host-1');
  });

  const afterDisconnect = await storeA.loadRoom(room.id);
  assert.ok(afterDisconnect);
  assert.equal(afterDisconnect.hostPlayerId, 'p2');

  await Promise.all([
    managerA.withRoomMutation(room.id, async () => {
      const rejoined = managerA.joinRoom(room.id, 'host-2a', 'P1', 'c1', 'u1');
      assert.ok(rejoined.player);
    }),
    managerB.withRoomMutation(room.id, async () => {
      const rejoined = managerB.joinRoom(room.id, 'host-2b', 'P1', 'c1', 'u1');
      assert.ok(rejoined.player);
    }),
  ]);

  const afterReconnect = await storeA.loadRoom(room.id);
  assert.ok(afterReconnect);
  assert.equal(afterReconnect.hostPlayerId, 'p2');
  assert.equal(afterReconnect.players.filter((player) => player.userId === 'u1').length, 1);
  assert.equal(afterReconnect.players.filter((player) => player.userId === 'u2').length, 1);
  assert.equal(afterReconnect.players.filter((player) => player.id === afterReconnect.hostPlayerId).length, 1);
});
