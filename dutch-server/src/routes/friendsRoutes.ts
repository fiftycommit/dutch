import { Router } from 'express';
import { Server } from 'socket.io';
import { FriendsService } from '../services/FriendsService';
import { PushNotificationService } from '../services/PushNotificationService';
import { requireAuth, AuthenticatedRequest } from '../middleware/authMiddleware';
import { requireAppCheck } from '../middleware/appCheckMiddleware';
import { FIREBASE_UNAVAILABLE_ERROR_CODE, roomRegistryService } from '../services/RoomRegistryService';
import { firestoreService } from '../services/FirestoreService';
import { RoomManager } from '../services/RoomManager';
import { SecurityService } from '../services/SecurityService';

const router = Router();

let friendsIo: Server | null = null;
let friendsRoomManager: RoomManager | null = null;

export function setFriendsIo(io: Server, rm: RoomManager) {
  friendsIo = io;
  friendsRoomManager = rm;
}

function isFirestoreUnavailable(error: unknown): boolean {
  if (typeof error !== 'object' || error === null) return false;
  const code = (error as { code?: string | number }).code;
  const message = (error instanceof Error ? error.message : JSON.stringify(error)).toLowerCase();
  return (
    code === 'unavailable' ||
    code === 'failed-precondition' ||
    code === 14 ||
    code === 9 ||
    message.includes('firestore non initialisé')
  );
}

// Toutes les routes nécessitent l'authentification
router.use(requireAuth);
router.use(requireAppCheck);

// GET /api/friends
router.get('/', SecurityService.userDataLimiter, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const friends = await FriendsService.getFriends(authReq.user!.uid);
  res.json({ success: true, friends });
});

// GET /api/friends/summary — amis + demandes en un seul appel
router.get('/summary', SecurityService.userDataLimiter, async (req, res) => {
  try {
    const authReq = req as AuthenticatedRequest;
    const uid = authReq.user!.uid;
    const [friends, incoming, outgoing] = await Promise.all([
      FriendsService.getFriends(uid),
      FriendsService.getIncomingRequests(uid),
      FriendsService.getOutgoingRequests(uid),
    ]);
    res.json({ success: true, friends, incoming, outgoing });
  } catch (error) {
    console.error('friends summary error:', error);
    if (isFirestoreUnavailable(error)) {
      res.status(503).json({
        success: false,
        errorCode: FIREBASE_UNAVAILABLE_ERROR_CODE,
        error:
          'Service social temporairement indisponible (Firebase). Vérifie https://downdetector.com/status/firebase/',
      });
      return;
    }
    res.status(500).json({ success: false, error: 'Erreur serveur' });
  }
});

// GET /api/friends/requests
router.get('/requests', SecurityService.userDataLimiter, async (req, res) => {
  try {
    const authReq = req as AuthenticatedRequest;
    const [incoming, outgoing] = await Promise.all([
      FriendsService.getIncomingRequests(authReq.user!.uid),
      FriendsService.getOutgoingRequests(authReq.user!.uid),
    ]);
    res.json({ success: true, incoming, outgoing });
  } catch (error) {
    console.error('friends requests error:', error);
    if (isFirestoreUnavailable(error)) {
      res.status(503).json({
        success: false,
        errorCode: FIREBASE_UNAVAILABLE_ERROR_CODE,
        error:
          'Service social temporairement indisponible (Firebase). Vérifie https://downdetector.com/status/firebase/',
      });
      return;
    }
    res.status(500).json({ success: false, error: 'Erreur serveur' });
  }
});

// GET /api/friends/lookup?username=foo
router.get('/lookup', SecurityService.socialLookupLimiter, async (req, res) => {
  try {
    const username = typeof req.query.username === 'string'
      ? req.query.username.trim()
      : '';
    if (!username) {
      res.status(400).json({ success: false, error: 'Nom d\'utilisateur requis' });
      return;
    }
    const lookup = await FriendsService.lookupUserByUsername(username);
    if (!lookup.exists || !lookup.user) {
      res.status(404).json({ success: false, exists: false, error: 'Utilisateur introuvable' });
      return;
    }
    res.json({ success: true, exists: true, user: lookup.user });
  } catch (error) {
    if (isFirestoreUnavailable(error)) {
      res.status(503).json({
        success: false,
        errorCode: FIREBASE_UNAVAILABLE_ERROR_CODE,
        error:
          'Service social temporairement indisponible (Firebase). Vérifie https://downdetector.com/status/firebase/',
      });
      return;
    }
    res.status(500).json({ success: false, error: 'Erreur serveur' });
  }
});

// POST /api/friends/request
router.post('/request', SecurityService.socialActionLimiter, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const { username } = req.body;

  if (!username) {
    res.status(400).json({ success: false, error: 'Nom d\'utilisateur requis' });
    return;
  }

  const result = await FriendsService.sendRequest(authReq.user!.uid, username);

  if (!result.success) {
    res.status(400).json(result);
    return;
  }

  res.json(result);
});

// POST /api/friends/accept
router.post('/accept', SecurityService.socialActionLimiter, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const { requestId } = req.body;

  if (!requestId) {
    res.status(400).json({ success: false, error: 'requestId requis' });
    return;
  }

  const result = await FriendsService.acceptRequest(authReq.user!.uid, requestId);

  if (!result.success) {
    res.status(400).json(result);
    return;
  }

  res.json(result);
});

// POST /api/friends/reject
router.post('/reject', SecurityService.socialActionLimiter, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const { requestId } = req.body;

  if (!requestId) {
    res.status(400).json({ success: false, error: 'requestId requis' });
    return;
  }

  const result = await FriendsService.rejectRequest(authReq.user!.uid, requestId);

  if (!result.success) {
    res.status(400).json(result);
    return;
  }

  res.json(result);
});

// POST /api/friends/cancel
router.post('/cancel', SecurityService.socialActionLimiter, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const { requestId } = req.body;

  if (!requestId) {
    res.status(400).json({ success: false, error: 'requestId requis' });
    return;
  }

  const result = await FriendsService.cancelRequest(authReq.user!.uid, requestId);

  if (!result.success) {
    res.status(400).json(result);
    return;
  }

  res.json(result);
});

// POST /api/friends/invite
router.post('/invite', SecurityService.socialActionLimiter, async (req, res) => {
  try {
    const authReq = req as AuthenticatedRequest;
    const { roomCode, friendUserId } = req.body;

    const normalizedRoomCode = typeof roomCode === 'string'
      ? roomCode.trim().toUpperCase()
      : '';
    const normalizedFriendUserId = typeof friendUserId === 'string'
      ? friendUserId.trim()
      : '';

    if (!normalizedRoomCode || !normalizedFriendUserId) {
      res.status(400).json({ success: false, error: 'roomCode et friendUserId requis' });
      return;
    }

    const friends = await FriendsService.getFriends(authReq.user!.uid);
    const isFriend = friends.some((friend) => friend.userId === normalizedFriendUserId);
    if (!isFriend) {
      res.status(403).json({ success: false, error: 'Ce joueur n\'est pas ton ami' });
      return;
    }

    const sender = await firestoreService.getUser(authReq.user!.uid);
    const inviterName =
      sender?.displayName?.trim() ||
      sender?.username?.trim() ||
      authReq.user!.email ||
      'Un ami';

    // Récupérer les infos de l'ami pour l'ajouter au salon
    const friendUser = await firestoreService.getUser(normalizedFriendUserId);
    const friendDisplayName = friendUser?.displayName?.trim() || friendUser?.username?.trim() || 'Joueur';
    const friendUsername = friendUser?.username?.trim() || '';

    // Ajouter l'ami comme joueur déconnecté dans la room en mémoire
    let addedPlayer = false;
    if (friendsRoomManager) {
      const player = friendsRoomManager.addInvitedPlayer(
        normalizedRoomCode,
        normalizedFriendUserId,
        friendUsername,
        friendDisplayName
      );
      if (player) {
        addedPlayer = true;
        // Sync Firestore members
        const room = friendsRoomManager.getRoom(normalizedRoomCode);
        if (room) {
          roomRegistryService.upsertMember(room, player).catch(() => {});
        }
      }
    }

    await PushNotificationService.notifyRoomInvite(
      normalizedFriendUserId,
      inviterName,
      normalizedRoomCode
    );

    // Enregistrer le salon dans activeRooms de l'ami → apparaît dans "Mes salons"
    roomRegistryService.registerInvitedMember(normalizedRoomCode, normalizedFriendUserId).catch(() => {});

    // Notification temps réel si l'ami est en ligne
    if (friendsIo) {
      friendsIo.to(FriendsService.getUserRoom(normalizedFriendUserId)).emit('room:invite', {
        roomCode: normalizedRoomCode,
        fromUserId: authReq.user!.uid,
        fromUsername: sender?.username || '',
        fromDisplayName: inviterName,
      });
    }

    res.json({ success: true, addedPlayer });
  } catch (error) {
    if (isFirestoreUnavailable(error)) {
      res.status(503).json({
        success: false,
        errorCode: FIREBASE_UNAVAILABLE_ERROR_CODE,
        error:
          'Service social temporairement indisponible (Firebase). Vérifie https://downdetector.com/status/firebase/',
      });
      return;
    }
    res.status(500).json({ success: false, error: 'Erreur serveur' });
  }
});

// DELETE /api/friends/:userId
router.delete('/:userId', SecurityService.socialActionLimiter, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const friendId = Array.isArray(req.params.userId)
    ? req.params.userId[0]
    : req.params.userId;

  if (!friendId) {
    res.status(400).json({ success: false, error: 'userId invalide' });
    return;
  }

  const result = await FriendsService.removeFriend(authReq.user!.uid, friendId);
  res.json(result);
});

// POST /api/friends/block
router.post('/block', SecurityService.socialActionLimiter, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const { userId } = req.body;

  if (!userId) {
    res.status(400).json({ success: false, error: 'userId requis' });
    return;
  }

  const result = await FriendsService.blockUser(authReq.user!.uid, userId);

  if (!result.success) {
    res.status(400).json(result);
    return;
  }

  res.json(result);
});

// DELETE /api/friends/block/:userId
router.delete('/block/:userId', SecurityService.socialActionLimiter, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const targetId = Array.isArray(req.params.userId)
    ? req.params.userId[0]
    : req.params.userId;

  if (!targetId) {
    res.status(400).json({ success: false, error: 'userId invalide' });
    return;
  }

  const result = await FriendsService.unblockUser(authReq.user!.uid, targetId);
  res.json(result);
});

// GET /api/friends/blocked
router.get('/blocked', SecurityService.userDataLimiter, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const blocked = await FriendsService.getBlockedUsers(authReq.user!.uid);
  res.json({ success: true, blocked });
});

export default router;
