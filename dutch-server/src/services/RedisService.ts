import { createClient } from 'redis';
import { createAdapter } from '@socket.io/redis-adapter';
import { SharedRoomStore } from './SharedRoomStore';

type RedisConnection = ReturnType<typeof createClient>;

export interface RedisRuntime {
  enabled: boolean;
  roomStore?: SharedRoomStore;
  keyValueClient?: RedisConnection;
  pubClient?: RedisConnection;
  subClient?: RedisConnection;
}

function isRedisEnabled(): boolean {
  const enabled = process.env.REDIS_ENABLED?.trim().toLowerCase();
  if (enabled === 'true') {
    return true;
  }
  if (enabled === 'false') {
    return false;
  }
  return Boolean(process.env.REDIS_URL?.trim());
}

function getRedisUrl(): string {
  return process.env.REDIS_URL?.trim() || 'redis://127.0.0.1:6379';
}

export class RedisService {
  private static runtime: RedisRuntime | null = null;

  static async initialize(): Promise<RedisRuntime> {
    if (this.runtime) {
      return this.runtime;
    }

    if (!isRedisEnabled()) {
      this.runtime = { enabled: false };
      return this.runtime;
    }

    const redisUrl = getRedisUrl();
    const keyValueClient = createClient({ url: redisUrl });
    const pubClient = keyValueClient.duplicate();
    const subClient = keyValueClient.duplicate();

    keyValueClient.on('error', (error) => {
      console.error('[REDIS] client error:', error);
    });
    pubClient.on('error', (error) => {
      console.error('[REDIS] pub client error:', error);
    });
    subClient.on('error', (error) => {
      console.error('[REDIS] sub client error:', error);
    });

    await Promise.all([
      keyValueClient.connect(),
      pubClient.connect(),
      subClient.connect(),
    ]);

    const runtime: RedisRuntime = {
      enabled: true,
      roomStore: new SharedRoomStore(keyValueClient),
      keyValueClient,
      pubClient,
      subClient,
    };
    this.runtime = runtime;

    console.log(`[REDIS] Connected to ${redisUrl}`);
    return runtime;
  }

  static getAdapterFactory() {
    const runtime = this.runtime;
    if (!runtime?.enabled || !runtime.pubClient || !runtime.subClient) {
      return undefined;
    }

    return createAdapter(runtime.pubClient, runtime.subClient);
  }

  static async shutdown(): Promise<void> {
    if (!this.runtime?.enabled) {
      this.runtime = null;
      return;
    }

    const clients = [
      this.runtime.subClient,
      this.runtime.pubClient,
      this.runtime.keyValueClient,
    ].filter((client): client is RedisConnection => Boolean(client));

    await Promise.all(clients.map(async (client) => {
      if (client.isOpen) {
        await client.quit();
      }
    }));

    this.runtime = null;
  }
}
