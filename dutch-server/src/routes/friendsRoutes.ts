import { Router } from 'express';
import { FriendsService } from '../services/FriendsService';
import { requireAuth, AuthenticatedRequest } from '../middleware/authMiddleware';

const router = Router();

// Toutes les routes nécessitent l'authentification
router.use(requireAuth);

// GET /api/friends
router.get('/', (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const friends = FriendsService.getFriends(authReq.user!.userId);
  res.json({ success: true, friends });
});

// GET /api/friends/requests
router.get('/requests', (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const incoming = FriendsService.getIncomingRequests(authReq.user!.userId);
  const outgoing = FriendsService.getOutgoingRequests(authReq.user!.userId);
  res.json({ success: true, incoming, outgoing });
});

// POST /api/friends/request
router.post('/request', (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const { username } = req.body;

  if (!username) {
    res.status(400).json({ success: false, error: 'Nom d\'utilisateur requis' });
    return;
  }

  const result = FriendsService.sendRequest(authReq.user!.userId, username);

  if (!result.success) {
    res.status(400).json(result);
    return;
  }

  res.json(result);
});

// POST /api/friends/accept
router.post('/accept', (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const { requestId } = req.body;

  if (!requestId) {
    res.status(400).json({ success: false, error: 'requestId requis' });
    return;
  }

  const result = FriendsService.acceptRequest(authReq.user!.userId, requestId);

  if (!result.success) {
    res.status(400).json(result);
    return;
  }

  res.json(result);
});

// POST /api/friends/reject
router.post('/reject', (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const { requestId } = req.body;

  if (!requestId) {
    res.status(400).json({ success: false, error: 'requestId requis' });
    return;
  }

  const result = FriendsService.rejectRequest(authReq.user!.userId, requestId);

  if (!result.success) {
    res.status(400).json(result);
    return;
  }

  res.json(result);
});

// POST /api/friends/cancel
router.post('/cancel', (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const { requestId } = req.body;

  if (!requestId) {
    res.status(400).json({ success: false, error: 'requestId requis' });
    return;
  }

  const result = FriendsService.cancelRequest(authReq.user!.userId, requestId);

  if (!result.success) {
    res.status(400).json(result);
    return;
  }

  res.json(result);
});

// DELETE /api/friends/:userId
router.delete('/:userId', (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const friendId = parseInt(req.params.userId, 10);

  if (isNaN(friendId)) {
    res.status(400).json({ success: false, error: 'userId invalide' });
    return;
  }

  const result = FriendsService.removeFriend(authReq.user!.userId, friendId);
  res.json(result);
});

// POST /api/friends/block
router.post('/block', (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const { userId } = req.body;

  if (!userId) {
    res.status(400).json({ success: false, error: 'userId requis' });
    return;
  }

  const result = FriendsService.blockUser(authReq.user!.userId, userId);

  if (!result.success) {
    res.status(400).json(result);
    return;
  }

  res.json(result);
});

// DELETE /api/friends/block/:userId
router.delete('/block/:userId', (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const targetId = parseInt(req.params.userId, 10);

  if (isNaN(targetId)) {
    res.status(400).json({ success: false, error: 'userId invalide' });
    return;
  }

  const result = FriendsService.unblockUser(authReq.user!.userId, targetId);
  res.json(result);
});

// GET /api/friends/blocked
router.get('/blocked', (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const blocked = FriendsService.getBlockedUsers(authReq.user!.userId);
  res.json({ success: true, blocked });
});

export default router;
