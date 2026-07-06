import test from 'node:test';
import assert from 'node:assert/strict';
import { Server } from 'socket.io';
import { RoomManager } from '../services/RoomManager';
import { SharedRoomStore } from '../services/SharedRoomStore';

type StoredValue = {
  value: string;
  expiresAt?: number;
};

class FakeRedis {
  private readonly values = new Map<string, StoredValue>();
  private readonly sets = new Map<string, Set<string>>();

  async get(key: string): Promise<string | null> {
    const entry = this.values.get(key);
    if (!entry) return null;
    if (entry.expiresAt != null && entry.expiresAt <= Date.now()) {
      this.values.delete(key);
      return null;
    }
    return entry.value;
  }

  async set(
    key: string,
    value: string,
    options: { NX?: boolean; PX?: number } = {}
  ): Promise<'OK' | null> {
    if (options.NX && (await this.get(key)) !== null) {
      return null;
    }
    const expiresAt = options.PX == null ? undefined : Date.now() + options.PX;
    this.values.set(key, { value, expiresAt });
    return 'OK';
  }

  async del(key: string): Promise<number> {
    const deleted = this.values.delete(key);
    this.sets.delete(key);
    return deleted ? 1 : 0;
  }

  async sAdd(key: string, value: string): Promise<number> {
    const set = this.sets.get(key) ?? new Set<string>();
    const before = set.size;
    set.add(value);
    this.sets.set(key, set);
    return set.size - before;
  }

  async sMembers(key: string): Promise<string[]> {
    return Array.from(this.sets.get(key) ?? []);
  }

  async sRem(key: string, value: string | string[]): Promise<number> {
    const set = this.sets.get(key);
    if (!set) return 0;
    const values = Array.isArray(value) ? value : [value];
    let removed = 0;
    for (const item of values) {
      if (set.delete(item)) removed++;
    }
    return removed;
  }

  async eval(
    _script: string,
    options: { keys: string[]; arguments: string[] }
  ): Promise<number> {
    const [key] = options.keys;
    const [token] = options.arguments;
    if ((await this.get(key)) === token) {
      return this.del(key);
    }
    return 0;
  }

  multi() {
    const commands: Array<() => Promise<unknown>> = [];
    const tx = {
      set: (key: string, value: string, options?: { PX?: number }) => {
        commands.push(() => this.set(key, value, options));
        return tx;
      },
      sAdd: (key: string, value: string) => {
        commands.push(() => this.sAdd(key, value));
        return tx;
      },
      del: (key: string) => {
        commands.push(() => this.del(key));
        return tx;
      },
      sRem: (key: string, value: string | string[]) => {
        commands.push(() => this.sRem(key, value));
        return tx;
      },
      exec: async () => Promise.all(commands.map((command) => command())),
    };
    return tx;
  }
}

class FakeServer {
  to() {
    return this;
  }

  emit() {
    return true;
  }
}

function createStore(redis: FakeRedis, keyPrefix = `test:${Date.now()}:${Math.random()}`) {
  return new SharedRoomStore(redis as never, {
    keyPrefix,
    lockRetryDelayMs: 5,
    lockAcquireTimeoutMs: 1_000,
  });
}

function createManager(store: SharedRoomStore) {
  const io = new FakeServer();
  return new RoomManager(io as unknown as Server, {
    cleanupIntervalMs: 60_000,
    roomTtlMs: 120_000,
    sharedRoomStore: store,
  });
}

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

test('SharedRoomStore serializes concurrent room joins across managers', async (t) => {
  const redis = new FakeRedis();
  const keyPrefix = `test:${Date.now()}:${Math.random()}`;
  const storeA = createStore(redis, keyPrefix);
  const storeB = createStore(redis, keyPrefix);
  const managerA = createManager(storeA);
  const managerB = createManager(storeB);
  t.after(() => {
    managerA.dispose();
    managerB.dispose();
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
    'la seconde instance ne doit pas muter la room tant que le verrou est tenu'
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

test('SharedRoomStore keeps one player identity and transferred host across managers', async (t) => {
  const redis = new FakeRedis();
  const store = createStore(redis);
  const managerA = createManager(store);
  const managerB = createManager(store);
  t.after(() => {
    managerA.dispose();
    managerB.dispose();
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

  let afterDisconnect = await store.loadRoom(room.id);
  assert.ok(afterDisconnect);
  assert.equal(afterDisconnect.hostPlayerId, 'p2');

  await managerB.withRoomMutation(room.id, async () => {
    const rejoined = managerB.joinRoom(room.id, 'host-2', 'P1', 'c1', 'u1');
    assert.ok(rejoined.player);
  });

  const afterReconnect = await store.loadRoom(room.id);
  assert.ok(afterReconnect);
  assert.equal(afterReconnect.hostPlayerId, 'p2');
  assert.equal(afterReconnect.players.filter((player) => player.userId === 'u1').length, 1);
  assert.equal(afterReconnect.players.filter((player) => player.userId === 'u2').length, 1);
  assert.equal(afterReconnect.players.filter((player) => player.id === afterReconnect.hostPlayerId).length, 1);
});

test('SharedRoomStore deduplicates the same reconnecting identity racing on two managers', async (t) => {
  const redis = new FakeRedis();
  const store = createStore(redis);
  const managerA = createManager(store);
  const managerB = createManager(store);
  t.after(() => {
    managerA.dispose();
    managerB.dispose();
  });

  const room = managerA.createRoom('host-1', { minPlayers: 2, maxPlayers: 4 }, 'Host', 'c1', 'u1');
  await Promise.resolve();

  await Promise.all([
    managerA.withRoomMutation(room.id, async () => {
      const joined = managerA.joinRoom(room.id, 'p2-a', 'P2', 'c2', 'u2');
      assert.ok(joined.player);
    }),
    managerB.withRoomMutation(room.id, async () => {
      const joined = managerB.joinRoom(room.id, 'p2-b', 'P2', 'c2', 'u2');
      assert.ok(joined.player);
    }),
  ]);

  const finalRoom = await store.loadRoom(room.id);
  assert.ok(finalRoom);
  const matchingPlayers = finalRoom.players.filter((player) => player.userId === 'u2');
  assert.equal(matchingPlayers.length, 1);
  assert.equal(matchingPlayers[0].connected, true);
  assert.equal(finalRoom.players.filter((player) => player.id === finalRoom.hostPlayerId).length, 1);
});
