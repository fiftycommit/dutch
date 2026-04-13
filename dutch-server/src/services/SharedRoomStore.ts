import { randomUUID } from 'node:crypto';
import { createClient } from 'redis';
import { Room } from '../models/Room';
import { RoomSnapshotCodec } from './RoomSnapshotCodec';

type RedisConnection = ReturnType<typeof createClient>;

const RELEASE_LOCK_SCRIPT = `
if redis.call("get", KEYS[1]) == ARGV[1] then
  return redis.call("del", KEYS[1])
end
return 0
`;

export interface SharedRoomStoreOptions {
  keyPrefix?: string;
  lockTtlMs?: number;
  lockRetryDelayMs?: number;
  lockAcquireTimeoutMs?: number;
  now?: () => number;
}

export class SharedRoomStore {
  private readonly keyPrefix: string;
  private readonly lockTtlMs: number;
  private readonly lockRetryDelayMs: number;
  private readonly lockAcquireTimeoutMs: number;
  private readonly now: () => number;

  constructor(
    private readonly redis: RedisConnection,
    options: SharedRoomStoreOptions = {}
  ) {
    this.keyPrefix = options.keyPrefix ?? 'multiplayer';
    this.lockTtlMs = options.lockTtlMs ?? 120_000;
    this.lockRetryDelayMs = options.lockRetryDelayMs ?? 100;
    this.lockAcquireTimeoutMs = options.lockAcquireTimeoutMs ?? 5_000;
    this.now = options.now ?? (() => Date.now());
  }

  async loadRoom(roomCode: string): Promise<Room | undefined> {
    const raw = await this.redis.get(this.roomKey(roomCode));
    if (!raw) {
      return undefined;
    }

    return RoomSnapshotCodec.deserialize(raw);
  }

  async saveRoom(room: Room): Promise<void> {
    const ttlMs = Math.max(1, room.expiresAt - this.now());
    const roomKey = this.roomKey(room.id);

    await this.redis.multi()
      .set(roomKey, RoomSnapshotCodec.serialize(room), { PX: ttlMs })
      .sAdd(this.roomIndexKey(), room.id)
      .exec();
  }

  async deleteRoom(roomCode: string): Promise<void> {
    await this.redis.multi()
      .del(this.roomKey(roomCode))
      .sRem(this.roomIndexKey(), roomCode)
      .exec();
  }

  async loadAllRooms(): Promise<Room[]> {
    const roomCodes = await this.redis.sMembers(this.roomIndexKey());
    if (roomCodes.length === 0) {
      return [];
    }

    const rooms = await Promise.all(roomCodes.map((roomCode) => this.loadRoom(roomCode)));
    const activeRooms: Room[] = [];
    const staleCodes: string[] = [];

    rooms.forEach((room, index) => {
      if (room) {
        activeRooms.push(room);
        return;
      }

      staleCodes.push(roomCodes[index]);
    });

    if (staleCodes.length > 0) {
      await this.redis.sRem(this.roomIndexKey(), staleCodes);
    }

    return activeRooms;
  }

  async withRoomLock<T>(roomCode: string, operation: () => Promise<T>): Promise<T> {
    const lockToken = await this.acquireRoomLock(roomCode);
    try {
      return await operation();
    } finally {
      await this.releaseRoomLock(roomCode, lockToken);
    }
  }

  private async acquireRoomLock(roomCode: string): Promise<string> {
    const token = randomUUID();
    const deadlineAt = this.now() + this.lockAcquireTimeoutMs;
    const lockKey = this.lockKey(roomCode);

    while (this.now() < deadlineAt) {
      const acquired = await this.redis.set(lockKey, token, {
        NX: true,
        PX: this.lockTtlMs,
      });

      if (acquired === 'OK') {
        return token;
      }

      await new Promise((resolve) => setTimeout(resolve, this.lockRetryDelayMs));
    }

    throw new Error(`Timeout d'acquisition du verrou Redis pour la room ${roomCode}`);
  }

  private async releaseRoomLock(roomCode: string, token: string): Promise<void> {
    await this.redis.eval(RELEASE_LOCK_SCRIPT, {
      keys: [this.lockKey(roomCode)],
      arguments: [token],
    });
  }

  private roomKey(roomCode: string): string {
    return `${this.keyPrefix}:room:${roomCode.toUpperCase()}`;
  }

  private roomIndexKey(): string {
    return `${this.keyPrefix}:rooms:index`;
  }

  private lockKey(roomCode: string): string {
    return `${this.keyPrefix}:lock:room:${roomCode.toUpperCase()}`;
  }
}
