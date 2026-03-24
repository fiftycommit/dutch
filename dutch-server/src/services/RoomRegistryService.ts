import { admin, firestore } from './FirebaseAdmin';
import { Room, RoomStatus } from '../models/Room';
import { Player } from '../models/Player';
import { RoomManager } from './RoomManager';

const ACTIVE_ROOM_SYNC_INTERVAL_MS = 30_000;
const DEFAULT_ROOM_TTL_MS = 2 * 60 * 60 * 1000;

export const FIREBASE_UNAVAILABLE_ERROR_CODE = 'BACKEND_UNAVAILABLE_FIREBASE';

export class RoomRegistryUnavailableError extends Error {
  readonly code = FIREBASE_UNAVAILABLE_ERROR_CODE;

  constructor(message = 'Service Firebase indisponible') {
    super(message);
    this.name = 'RoomRegistryUnavailableError';
  }
}

export interface ActiveRoomEntry {
  roomCode: string;
  isHost: boolean;
  status: string;
  playerCount: number;
  updatedAt?: admin.firestore.Timestamp | null;
  expiresAt?: admin.firestore.Timestamp | null;
}

class RoomRegistryService {
  private syncTimer: NodeJS.Timeout | null = null;
  private syncInProgress = false;
  private socketMembership = new Map<string, { roomCode: string; uid: string }>();

  private get db(): FirebaseFirestore.Firestore {
    if (!firestore) {
      throw new RoomRegistryUnavailableError();
    }
    return firestore;
  }

  isAvailable(): boolean {
    return !!firestore;
  }

  ensureAvailable(): void {
    if (!firestore) {
      throw new RoomRegistryUnavailableError();
    }
  }

  bindSocketMembership(socketId: string, roomCode: string, uid: string): void {
    this.socketMembership.set(socketId, {
      roomCode: roomCode.toUpperCase(),
      uid: uid.trim(),
    });
  }

  unbindSocketMembership(socketId: string): void {
    this.socketMembership.delete(socketId);
  }

  async handleSocketDisconnected(socketId: string): Promise<void> {
    const binding = this.socketMembership.get(socketId);
    if (!binding) return;
    this.socketMembership.delete(socketId);
    await this.markMemberDisconnected(binding.roomCode, binding.uid);
  }

  async markMemberDisconnected(roomCode: string, uid: string): Promise<void> {
    this.ensureAvailable();
    const normalizedRoomCode = roomCode.toUpperCase();
    const normalizedUid = uid.trim();
    const now = admin.firestore.FieldValue.serverTimestamp();

    await this.db
      .collection('multiplayer_rooms')
      .doc(normalizedRoomCode)
      .collection('members')
      .doc(normalizedUid)
      .set(
        {
          connected: false,
          disconnectedAt: now,
          updatedAt: now,
        },
        { merge: true }
      );

    await this.db
      .collection('users')
      .doc(normalizedUid)
      .collection('activeRooms')
      .doc(normalizedRoomCode)
      .set(
        {
          updatedAt: now,
        },
        { merge: true }
      );
  }

  async removeMember(roomCode: string, uid: string): Promise<void> {
    this.ensureAvailable();
    const normalizedRoomCode = roomCode.toUpperCase();
    const normalizedUid = uid.trim();
    await Promise.all([
      this.db
        .collection('multiplayer_rooms')
        .doc(normalizedRoomCode)
        .collection('members')
        .doc(normalizedUid)
        .delete(),
      this.db
        .collection('users')
        .doc(normalizedUid)
        .collection('activeRooms')
        .doc(normalizedRoomCode)
        .delete(),
      this.db.collection('multiplayer_rooms').doc(normalizedRoomCode).set(
        {
          memberUids: admin.firestore.FieldValue.arrayRemove(normalizedUid),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      ),
    ]);
  }

  async removeActiveRoomForUser(uid: string, roomCode: string): Promise<void> {
    this.ensureAvailable();
    await this.db
      .collection('users')
      .doc(uid.trim())
      .collection('activeRooms')
      .doc(roomCode.toUpperCase())
      .delete();
  }

  async upsertRoom(room: Room): Promise<void> {
    this.ensureAvailable();

    const memberUids = this.extractMemberUids(room.players);
    const activeCount = this.computeActivePlayerCount(room);
    const connectedCount = room.players.filter(
      (p) => p.isHuman && p.userId && p.connected && !p.isSpectator
    ).length;
    const host = room.players.find((p) => p.id === room.hostPlayerId);
    const expiresAtMs = room.expiresAt || Date.now() + DEFAULT_ROOM_TTL_MS;

    await this.db
      .collection('multiplayer_rooms')
      .doc(room.id)
      .set(
        {
          roomCode: room.id,
          status: room.status,
          settings: room.settings ?? {},
          isPublic: room.settings?.isPublic === true,
          gameMode: room.gameMode,
          hostUid: host?.userId ?? null,
          memberUids,
          membersCount: memberUids.length,
          connectedCount,
          playerCount: activeCount,
          createdAt: admin.firestore.Timestamp.fromDate(room.createdAt ?? new Date()),
          lastActivityAt: admin.firestore.Timestamp.fromMillis(
            room.lastActivityAt || Date.now()
          ),
          expiresAt: admin.firestore.Timestamp.fromMillis(expiresAtMs),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
  }

  async upsertMember(room: Room, player: Player): Promise<void> {
    const uid = player.userId?.trim();
    if (!uid) return;
    this.ensureAvailable();

    const normalizedRoomCode = room.id.toUpperCase();
    const now = admin.firestore.FieldValue.serverTimestamp();
    const isHost = room.hostPlayerId === player.id;
    const activeCount = this.computeActivePlayerCount(room);
    const expiresAtMs = room.expiresAt || Date.now() + DEFAULT_ROOM_TTL_MS;

    await Promise.all([
      this.db
        .collection('multiplayer_rooms')
        .doc(normalizedRoomCode)
        .collection('members')
        .doc(uid)
        .set(
          {
            uid,
            username: player.username ?? null,
            displayName: player.name,
            clientId: player.clientId ?? null,
            socketId: player.id,
            connected: player.connected !== false,
            ready: player.ready === true,
            isHost,
            isSpectator: player.isSpectator === true,
            lastSeenAt:
              player.lastSeenAt == null
                ? null
                : admin.firestore.Timestamp.fromMillis(player.lastSeenAt),
            disconnectedAt:
              player.connected === false
                ? admin.firestore.FieldValue.serverTimestamp()
                : admin.firestore.FieldValue.delete(),
            joinedAt: now,
            updatedAt: now,
          },
          { merge: true }
        ),
      this.db
        .collection('users')
        .doc(uid)
        .collection('activeRooms')
        .doc(normalizedRoomCode)
        .set(
          {
            roomCode: normalizedRoomCode,
            isHost,
            status: room.status,
            playerCount: activeCount,
            updatedAt: now,
            expiresAt: admin.firestore.Timestamp.fromMillis(expiresAtMs),
          },
          { merge: true }
        ),
      this.db.collection('multiplayer_rooms').doc(normalizedRoomCode).set(
        {
          memberUids: admin.firestore.FieldValue.arrayUnion(uid),
          updatedAt: now,
        },
        { merge: true }
      ),
    ]);
  }

  async archiveRoom(roomCode: string, memberUids?: string[]): Promise<void> {
    this.ensureAvailable();
    const normalizedRoomCode = roomCode.toUpperCase();
    const now = admin.firestore.FieldValue.serverTimestamp();
    const roomRef = this.db.collection('multiplayer_rooms').doc(normalizedRoomCode);

    let uids = (memberUids ?? []).map((uid) => uid.trim()).filter((uid) => uid.length > 0);
    if (uids.length === 0) {
      const membersSnap = await roomRef.collection('members').get();
      uids = membersSnap.docs.map((doc) => doc.id);
    }

    const batch = this.db.batch();
    batch.set(
      roomRef,
      {
        status: 'offline',
        connectedCount: 0,
        playerCount: 0,
        updatedAt: now,
      },
      { merge: true }
    );

    for (const uid of uids) {
      batch.delete(this.db.collection('users').doc(uid).collection('activeRooms').doc(normalizedRoomCode));
      batch.delete(roomRef.collection('members').doc(uid));
    }

    await batch.commit();
  }

  async getUserActiveRooms(uid: string): Promise<ActiveRoomEntry[]> {
    this.ensureAvailable();
    const normalizedUid = uid.trim();
    const nowMs = Date.now();
    const activeRoomsRef = this.db.collection('users').doc(normalizedUid).collection('activeRooms');
    const snap = await activeRoomsRef.orderBy('updatedAt', 'desc').limit(20).get();
    const expiredRefs: FirebaseFirestore.DocumentReference[] = [];
    const result: ActiveRoomEntry[] = [];

    for (const doc of snap.docs) {
      const data = doc.data();
      const status = typeof data.status === 'string' ? data.status : 'waiting';
      const expiresAt = data.expiresAt as admin.firestore.Timestamp | undefined;
      if (expiresAt && expiresAt.toMillis() <= nowMs) {
        expiredRefs.push(doc.ref);
        continue;
      }
      if (status === RoomStatus.closing || status === 'offline') {
        continue;
      }
      result.push({
        roomCode: (data.roomCode as string | undefined)?.toUpperCase() ?? doc.id.toUpperCase(),
        isHost: data.isHost === true,
        status,
        playerCount:
          typeof data.playerCount === 'number'
            ? data.playerCount
            : Number(data.playerCount) || 0,
        updatedAt: (data.updatedAt as admin.firestore.Timestamp | undefined) ?? null,
        expiresAt: expiresAt ?? null,
      });
    }

    if (expiredRefs.length > 0) {
      const batch = this.db.batch();
      for (const ref of expiredRefs) {
        batch.delete(ref);
      }
      await batch.commit();
    }

    return result;
  }

  startPeriodicSync(roomManager: RoomManager, intervalMs = ACTIVE_ROOM_SYNC_INTERVAL_MS): void {
    if (this.syncTimer) return;
    this.syncTimer = setInterval(() => {
      void this.syncFromRoomManager(roomManager);
    }, intervalMs);
  }

  stopPeriodicSync(): void {
    if (!this.syncTimer) return;
    clearInterval(this.syncTimer);
    this.syncTimer = null;
  }

  async syncFromRoomManager(roomManager: RoomManager): Promise<void> {
    if (!this.isAvailable() || this.syncInProgress) return;
    this.syncInProgress = true;
    try {
      const roomSummaries = roomManager.listRooms();
      for (const summary of roomSummaries) {
        const room = roomManager.getRoom(summary.id);
        if (!room) continue;
        await this.upsertRoom(room);
        for (const player of room.players) {
          if (!player.isHuman || !player.userId) continue;
          await this.upsertMember(room, player);
        }
      }
      await this.purgeExpiredRooms();
    } catch (error) {
      console.error('RoomRegistryService sync error:', error);
    } finally {
      this.syncInProgress = false;
    }
  }

  private async purgeExpiredRooms(): Promise<void> {
    this.ensureAvailable();
    const now = admin.firestore.Timestamp.now();
    const expiredSnap = await this.db
      .collection('multiplayer_rooms')
      .where('expiresAt', '<=', now)
      .limit(20)
      .get();

    for (const doc of expiredSnap.docs) {
      await this.archiveRoom(doc.id);
    }
  }

  private extractMemberUids(players: Player[]): string[] {
    const set = new Set<string>();
    for (const player of players) {
      const uid = player.userId?.trim();
      if (!uid || !player.isHuman) continue;
      set.add(uid);
    }
    return Array.from(set.values());
  }

  private computeActivePlayerCount(room: Room): number {
    return room.players.filter((player) => {
      if (player.isSpectator) return false;
      if (!player.isHuman) return true;
      return player.connected !== false;
    }).length;
  }

  /**
   * Enregistre l'ami invité dans son sous-collection activeRooms, sans qu'il
   * ait besoin d'être connecté via socket. Le salon apparaît ainsi dans "Mes salons".
   */
  async registerInvitedMember(roomCode: string, friendUid: string): Promise<void> {
    if (!firestore) return;
    const now = admin.firestore.FieldValue.serverTimestamp();
    const expiresAtMs = Date.now() + DEFAULT_ROOM_TTL_MS;

    // Récupère le statut actuel de la room depuis Firestore (best-effort)
    let status = 'waiting';
    try {
      const roomDoc = await firestore.collection('multiplayer_rooms').doc(roomCode).get();
      if (roomDoc.exists) status = (roomDoc.data()?.status as string) || 'waiting';
    } catch {}

    await firestore
      .collection('users')
      .doc(friendUid)
      .collection('activeRooms')
      .doc(roomCode)
      .set(
        {
          roomCode,
          isHost: false,
          status,
          updatedAt: now,
          expiresAt: admin.firestore.Timestamp.fromMillis(expiresAtMs),
        },
        { merge: true }
      );
  }
}

export const roomRegistryService = new RoomRegistryService();

export function isRoomRegistryUnavailableError(
  error: unknown
): error is RoomRegistryUnavailableError {
  if (error instanceof RoomRegistryUnavailableError) {
    return true;
  }
  if (typeof error !== 'object' || error === null) {
    return false;
  }
  const code = (error as { code?: string }).code;
  if (code === FIREBASE_UNAVAILABLE_ERROR_CODE) {
    return true;
  }
  // Firestore transient operational errors
  return (
    code === 'unavailable' ||
    code === 'deadline-exceeded' ||
    code === 'resource-exhausted' ||
    code === 'failed-precondition'
  );
}
