import { database } from './Database';
import { User } from '../models/User';

export interface FriendInfo {
  userId: number;
  username: string;
  displayName: string;
  addedAt: string;
  isOnline: boolean;
}

export interface RequestInfo {
  requestId: number;
  userId: number;
  username: string;
  displayName: string;
  requestedAt: string;
}

export interface BlockedInfo {
  userId: number;
  username: string;
  displayName: string;
}

// Référence vers la map d'utilisateurs en ligne (injectée depuis socketAuthMiddleware)
let onlineUsersRef: Map<number, Set<string>> = new Map();

export class FriendsService {
  static setOnlineUsersRef(ref: Map<number, Set<string>>) {
    onlineUsersRef = ref;
  }

  static isUserOnline(userId: number): boolean {
    const sockets = onlineUsersRef.get(userId);
    return !!sockets && sockets.size > 0;
  }

  static getFriends(userId: number): FriendInfo[] {
    const rows = database.instance.prepare(`
      SELECT u.id, u.username, u.display_name, f.created_at
      FROM friends f
      JOIN users u ON u.id = f.friend_id
      WHERE f.user_id = ?
      ORDER BY u.display_name COLLATE NOCASE
    `).all(userId) as { id: number; username: string; display_name: string; created_at: string }[];

    return rows.map(r => ({
      userId: r.id,
      username: r.username,
      displayName: r.display_name,
      addedAt: r.created_at,
      isOnline: this.isUserOnline(r.id),
    }));
  }

  static getIncomingRequests(userId: number): RequestInfo[] {
    const rows = database.instance.prepare(`
      SELECT fr.id, u.id as user_id, u.username, u.display_name, fr.created_at
      FROM friend_requests fr
      JOIN users u ON u.id = fr.from_user_id
      WHERE fr.to_user_id = ? AND fr.status = 'pending'
      ORDER BY fr.created_at DESC
    `).all(userId) as { id: number; user_id: number; username: string; display_name: string; created_at: string }[];

    return rows.map(r => ({
      requestId: r.id,
      userId: r.user_id,
      username: r.username,
      displayName: r.display_name,
      requestedAt: r.created_at,
    }));
  }

  static getOutgoingRequests(userId: number): RequestInfo[] {
    const rows = database.instance.prepare(`
      SELECT fr.id, u.id as user_id, u.username, u.display_name, fr.created_at
      FROM friend_requests fr
      JOIN users u ON u.id = fr.to_user_id
      WHERE fr.from_user_id = ? AND fr.status = 'pending'
      ORDER BY fr.created_at DESC
    `).all(userId) as { id: number; user_id: number; username: string; display_name: string; created_at: string }[];

    return rows.map(r => ({
      requestId: r.id,
      userId: r.user_id,
      username: r.username,
      displayName: r.display_name,
      requestedAt: r.created_at,
    }));
  }

  static sendRequest(fromUserId: number, toUsername: string): { success: boolean; error?: string; requestId?: number; toUserId?: number } {
    const target = database.instance.prepare(
      'SELECT id FROM users WHERE username = ?'
    ).get(toUsername.toLowerCase()) as { id: number } | undefined;

    if (!target) {
      return { success: false, error: 'Utilisateur introuvable' };
    }

    if (target.id === fromUserId) {
      return { success: false, error: 'Tu ne peux pas t\'ajouter toi-même' };
    }

    // Vérifier si déjà amis
    const alreadyFriends = database.instance.prepare(
      'SELECT 1 FROM friends WHERE user_id = ? AND friend_id = ?'
    ).get(fromUserId, target.id);

    if (alreadyFriends) {
      return { success: false, error: 'Déjà amis' };
    }

    // Vérifier si bloqué
    const isBlocked = database.instance.prepare(
      'SELECT 1 FROM blocked_users WHERE (user_id = ? AND blocked_id = ?) OR (user_id = ? AND blocked_id = ?)'
    ).get(fromUserId, target.id, target.id, fromUserId);

    if (isBlocked) {
      return { success: false, error: 'Action impossible' };
    }

    // Vérifier si une demande inverse existe (auto-accept)
    const reverseRequest = database.instance.prepare(
      'SELECT id FROM friend_requests WHERE from_user_id = ? AND to_user_id = ? AND status = \'pending\''
    ).get(target.id, fromUserId) as { id: number } | undefined;

    if (reverseRequest) {
      // Auto-accept : la personne nous a déjà envoyé une demande
      return this.acceptRequest(fromUserId, reverseRequest.id);
    }

    // Vérifier si demande déjà envoyée
    const existing = database.instance.prepare(
      'SELECT id FROM friend_requests WHERE from_user_id = ? AND to_user_id = ? AND status = \'pending\''
    ).get(fromUserId, target.id);

    if (existing) {
      return { success: false, error: 'Demande déjà envoyée' };
    }

    const result = database.instance.prepare(
      'INSERT INTO friend_requests (from_user_id, to_user_id) VALUES (?, ?)'
    ).run(fromUserId, target.id);

    return { success: true, requestId: result.lastInsertRowid as number, toUserId: target.id };
  }

  static acceptRequest(userId: number, requestId: number): { success: boolean; error?: string; toUserId?: number } {
    const request = database.instance.prepare(
      'SELECT * FROM friend_requests WHERE id = ? AND to_user_id = ? AND status = \'pending\''
    ).get(requestId, userId) as { id: number; from_user_id: number; to_user_id: number } | undefined;

    if (!request) {
      return { success: false, error: 'Demande introuvable' };
    }

    const addFriends = database.instance.transaction(() => {
      // Ajouter la relation bidirectionnelle
      database.instance.prepare(
        'INSERT OR IGNORE INTO friends (user_id, friend_id) VALUES (?, ?)'
      ).run(userId, request.from_user_id);
      database.instance.prepare(
        'INSERT OR IGNORE INTO friends (user_id, friend_id) VALUES (?, ?)'
      ).run(request.from_user_id, userId);

      // Marquer la demande comme acceptée
      database.instance.prepare(
        'UPDATE friend_requests SET status = \'accepted\' WHERE id = ?'
      ).run(requestId);
    });

    addFriends();
    return { success: true, toUserId: request.from_user_id };
  }

  static rejectRequest(userId: number, requestId: number): { success: boolean; error?: string } {
    const result = database.instance.prepare(
      'UPDATE friend_requests SET status = \'rejected\' WHERE id = ? AND to_user_id = ? AND status = \'pending\''
    ).run(requestId, userId);

    if (result.changes === 0) {
      return { success: false, error: 'Demande introuvable' };
    }
    return { success: true };
  }

  static cancelRequest(userId: number, requestId: number): { success: boolean; error?: string } {
    const result = database.instance.prepare(
      'DELETE FROM friend_requests WHERE id = ? AND from_user_id = ? AND status = \'pending\''
    ).run(requestId, userId);

    if (result.changes === 0) {
      return { success: false, error: 'Demande introuvable' };
    }
    return { success: true };
  }

  static removeFriend(userId: number, friendId: number): { success: boolean; error?: string } {
    const removeBoth = database.instance.transaction(() => {
      database.instance.prepare(
        'DELETE FROM friends WHERE (user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)'
      ).run(userId, friendId, friendId, userId);
    });

    removeBoth();
    return { success: true };
  }

  static blockUser(userId: number, targetId: number): { success: boolean; error?: string } {
    if (userId === targetId) {
      return { success: false, error: 'Action impossible' };
    }

    const blockAndCleanup = database.instance.transaction(() => {
      // Ajouter au blocage
      database.instance.prepare(
        'INSERT OR IGNORE INTO blocked_users (user_id, blocked_id) VALUES (?, ?)'
      ).run(userId, targetId);

      // Supprimer l'amitié
      database.instance.prepare(
        'DELETE FROM friends WHERE (user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?)'
      ).run(userId, targetId, targetId, userId);

      // Supprimer les demandes en attente
      database.instance.prepare(
        'DELETE FROM friend_requests WHERE ((from_user_id = ? AND to_user_id = ?) OR (from_user_id = ? AND to_user_id = ?)) AND status = \'pending\''
      ).run(userId, targetId, targetId, userId);
    });

    blockAndCleanup();
    return { success: true };
  }

  static unblockUser(userId: number, targetId: number): { success: boolean; error?: string } {
    database.instance.prepare(
      'DELETE FROM blocked_users WHERE user_id = ? AND blocked_id = ?'
    ).run(userId, targetId);
    return { success: true };
  }

  static getBlockedUsers(userId: number): BlockedInfo[] {
    const rows = database.instance.prepare(`
      SELECT u.id, u.username, u.display_name
      FROM blocked_users b
      JOIN users u ON u.id = b.blocked_id
      WHERE b.user_id = ?
      ORDER BY u.username
    `).all(userId) as { id: number; username: string; display_name: string }[];

    return rows.map(r => ({
      userId: r.id,
      username: r.username,
      displayName: r.display_name,
    }));
  }

  // Vérifier si un user est bloqué par un autre
  static isBlocked(userId: number, targetId: number): boolean {
    const row = database.instance.prepare(
      'SELECT 1 FROM blocked_users WHERE user_id = ? AND blocked_id = ?'
    ).get(userId, targetId);
    return !!row;
  }

  // Obtenir les socket IDs d'un user pour les notifications temps réel
  static getUserSocketIds(userId: number): string[] {
    const sockets = onlineUsersRef.get(userId);
    return sockets ? Array.from(sockets) : [];
  }
}
