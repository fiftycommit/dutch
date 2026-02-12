import { Router } from 'express';
import { FriendsService } from '../services/FriendsService';
import { PushNotificationService } from '../services/PushNotificationService';
import { requireAuth, AuthenticatedRequest } from '../middleware/authMiddleware';

const router = Router();

// Toutes les routes nécessitent l'authentification
router.use(requireAuth);

// GET /api/friends
router.get('/', async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const friends = await FriendsService.getFriends(authReq.user!.uid);
  res.json({ success: true, friends });
});

// GET /api/friends/requests
router.get('/requests', async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const incoming = await FriendsService.getIncomingRequests(authReq.user!.uid);
  const outgoing = await FriendsService.getOutgoingRequests(authReq.user!.uid);
  res.json({ success: true, incoming, outgoing });
});

// POST /api/friends/request
router.post('/request', async (req, res) => {
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
router.post('/accept', async (req, res) => {
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
router.post('/reject', async (req, res) => {
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
router.post('/cancel', async (req, res) => {
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

// DELETE /api/friends/:userId
router.delete('/:userId', async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const friendId = req.params.userId; // String directement, plus de parseInt

  if (!friendId) {
    res.status(400).json({ success: false, error: 'userId invalide' });
    return;
  }

  const result = await FriendsService.removeFriend(authReq.user!.uid, friendId);
  res.json(result);
});

// POST /api/friends/block
router.post('/block', async (req, res) => {
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
router.delete('/block/:userId', async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const targetId = req.params.userId; // String directement, plus de parseInt

  if (!targetId) {
    res.status(400).json({ success: false, error: 'userId invalide' });
    return;
  }

  const result = await FriendsService.unblockUser(authReq.user!.uid, targetId);
  res.json(result);
});

// GET /api/friends/blocked
router.get('/blocked', async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const blocked = await FriendsService.getBlockedUsers(authReq.user!.uid);
  res.json({ success: true, blocked });
});

export default router;
