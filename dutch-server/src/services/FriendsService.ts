import { firestoreService, FirestoreUser } from './FirestoreService';
import { PublicUser } from '../models/User';

export interface FriendInfo {
  userId: string;
  username: string;
  displayName: string;
  addedAt: string;
  isOnline: boolean;
}

export interface RequestInfo {
  requestId: string;
  userId: string;
  username: string;
  displayName: string;
  requestedAt: string;
}

export interface BlockedInfo {
  userId: string;
  username: string;
  displayName: string;
}

// Référence vers la map d'utilisateurs en ligne (injectée depuis socketAuthMiddleware)
let onlineUsersRef: Map<string, Set<string>> = new Map();

export class FriendsService {
  static setOnlineUsersRef(ref: Map<string, Set<string>>) {
    onlineUsersRef = ref;
  }

  static isUserOnline(userId: string): boolean {
    const sockets = onlineUsersRef.get(userId);
    return !!sockets && sockets.size > 0;
  }

  static async getFriends(userId: string): Promise<FriendInfo[]> {
    const friendUids = await firestoreService.getFriends(userId);
    if (friendUids.length === 0) return [];

    const users = await Promise.all(friendUids.map(uid => firestoreService.getUser(uid)));
    const friends: FriendInfo[] = [];

    for (let i = 0; i < friendUids.length; i++) {
      const user = users[i];
      if (user) {
        const uid = friendUids[i];
        friends.push({
          userId: uid,
          username: user.username,
          displayName: user.displayName,
          addedAt: user.createdAt?.toDate?.()?.toISOString() || '',
          isOnline: this.isUserOnline(uid),
        });
      }
    }

    return friends;
  }

  static async getIncomingRequests(userId: string): Promise<RequestInfo[]> {
    const requests = await firestoreService.getPendingRequestsTo(userId);
    if (requests.length === 0) return [];

    const users = await Promise.all(requests.map(req => firestoreService.getUser(req.fromUid)));
    const results: RequestInfo[] = [];

    for (let i = 0; i < requests.length; i++) {
      const user = users[i];
      if (user) {
        const req = requests[i];
        results.push({
          requestId: req.id,
          userId: req.fromUid,
          username: user.username,
          displayName: user.displayName,
          requestedAt: req.createdAt?.toDate?.()?.toISOString() || '',
        });
      }
    }

    return results;
  }

  static async getOutgoingRequests(userId: string): Promise<RequestInfo[]> {
    const requests = await firestoreService.getPendingRequestsFrom(userId);
    if (requests.length === 0) return [];

    const users = await Promise.all(requests.map(req => firestoreService.getUser(req.toUid)));
    const results: RequestInfo[] = [];

    for (let i = 0; i < requests.length; i++) {
      const user = users[i];
      if (user) {
        const req = requests[i];
        results.push({
          requestId: req.id,
          userId: req.toUid,
          username: user.username,
          displayName: user.displayName,
          requestedAt: req.createdAt?.toDate?.()?.toISOString() || '',
        });
      }
    }

    return results;
  }

  static async sendRequest(fromUserId: string, toUsername: string): Promise<{ success: boolean; error?: string; requestId?: string; toUserId?: string }> {
    const target = await firestoreService.getUserByUsername(toUsername);

    if (!target) {
      return { success: false, error: 'Utilisateur introuvable' };
    }

    if (target.uid === fromUserId) {
      return { success: false, error: 'Tu ne peux pas t\'ajouter toi-même' };
    }

    // Vérifier si déjà amis
    const friends = await firestoreService.getFriends(fromUserId);
    if (friends.includes(target.uid)) {
      return { success: false, error: 'Déjà amis' };
    }

    // Vérifier blocage
    const blocked = await firestoreService.isBlocked(fromUserId, target.uid);
    const blockedReverse = await firestoreService.isBlocked(target.uid, fromUserId);
    if (blocked || blockedReverse) {
      return { success: false, error: 'Action impossible' };
    }

    // Vérifier si demande inverse (auto-accept)
    const pendingToMe = await firestoreService.getPendingRequestsTo(fromUserId);
    const reverseRequest = pendingToMe.find(r => r.fromUid === target.uid);
    if (reverseRequest) {
      const result = await firestoreService.acceptFriendRequest(reverseRequest.id);
      if (result) {
        return { success: true, toUserId: target.uid };
      }
    }

    // Vérifier si demande déjà envoyée
    const pendingFromMe = await firestoreService.getPendingRequestsFrom(fromUserId);
    const existing = pendingFromMe.find(r => r.toUid === target.uid);
    if (existing) {
      return { success: false, error: 'Demande déjà envoyée' };
    }

    const requestId = await firestoreService.sendFriendRequest(fromUserId, target.uid);
    return { success: true, requestId, toUserId: target.uid };
  }

  static async lookupUserByUsername(username: string): Promise<{
    exists: boolean;
    user?: PublicUser;
  }> {
    const normalized = username.trim().toLowerCase();
    if (!normalized) {
      return { exists: false };
    }
    const target = await firestoreService.getUserByUsername(normalized);
    if (!target) {
      return { exists: false };
    }
    return {
      exists: true,
      user: {
        id: target.uid,
        username: target.data.username,
        displayName: target.data.displayName,
      },
    };
  }

  static async acceptRequest(userId: string, requestId: string): Promise<{ success: boolean; error?: string; toUserId?: string }> {
    const result = await firestoreService.acceptFriendRequest(requestId);
    if (!result) {
      return { success: false, error: 'Demande introuvable' };
    }
    return { success: true, toUserId: result.fromUid };
  }

  static async rejectRequest(userId: string, requestId: string): Promise<{ success: boolean; error?: string }> {
    const ok = await firestoreService.rejectFriendRequest(requestId);
    if (!ok) {
      return { success: false, error: 'Demande introuvable' };
    }
    return { success: true };
  }

  static async cancelRequest(userId: string, requestId: string): Promise<{ success: boolean; error?: string }> {
    const ok = await firestoreService.cancelFriendRequest(requestId, userId);
    if (!ok) {
      return { success: false, error: 'Demande introuvable' };
    }
    return { success: true };
  }

  static async removeFriend(userId: string, friendId: string): Promise<{ success: boolean; error?: string }> {
    await firestoreService.removeFriend(userId, friendId);
    return { success: true };
  }

  static async blockUser(userId: string, targetId: string): Promise<{ success: boolean; error?: string }> {
    if (userId === targetId) {
      return { success: false, error: 'Action impossible' };
    }
    await firestoreService.blockUser(userId, targetId);
    return { success: true };
  }

  static async unblockUser(userId: string, targetId: string): Promise<{ success: boolean; error?: string }> {
    await firestoreService.unblockUser(userId, targetId);
    return { success: true };
  }

  static async getBlockedUsers(userId: string): Promise<BlockedInfo[]> {
    const blockedUids = await firestoreService.getBlockedUsers(userId);
    if (blockedUids.length === 0) return [];

    const users = await Promise.all(blockedUids.map(uid => firestoreService.getUser(uid)));
    const results: BlockedInfo[] = [];

    for (let i = 0; i < blockedUids.length; i++) {
      const user = users[i];
      if (user) {
        results.push({
          userId: blockedUids[i],
          username: user.username,
          displayName: user.displayName,
        });
      }
    }

    return results;
  }

  static isBlocked(userId: string, targetId: string): Promise<boolean> {
    return firestoreService.isBlocked(userId, targetId);
  }

  // Obtenir les socket IDs d'un user pour les notifications temps réel
  static getUserSocketIds(userId: string): string[] {
    const sockets = onlineUsersRef.get(userId);
    return sockets ? Array.from(sockets) : [];
  }
}
