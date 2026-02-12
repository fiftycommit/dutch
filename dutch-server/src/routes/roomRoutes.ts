import { Router } from 'express';
import { requireAuth, AuthenticatedRequest } from '../middleware/authMiddleware';
import { firestoreService } from '../services/FirestoreService';

const router = Router();

// GET /api/rooms/mine — Récupérer les rooms de l'utilisateur
router.get('/mine', requireAuth, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const uid = authReq.user!.uid;

  try {
    const rooms = await firestoreService.getUserRooms(uid);

    res.json({
      success: true,
      rooms: rooms.map(r => ({
        roomCode: r.roomCode,
        isHost: r.isHost,
        joinedAt: r.joinedAt?.toDate?.()?.toISOString() || '',
      })),
    });
  } catch (e) {
    res.status(500).json({ success: false, error: 'Erreur serveur' });
  }
});

// POST /api/rooms/save — Sauvegarder une room
router.post('/save', requireAuth, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const uid = authReq.user!.uid;
  const { roomCode, isHost } = req.body;

  if (!roomCode || typeof roomCode !== 'string') {
    res.status(400).json({ success: false, error: 'roomCode requis' });
    return;
  }

  try {
    await firestoreService.saveRoomToUser(uid, roomCode.toUpperCase(), !!isHost);
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ success: false, error: 'Erreur serveur' });
  }
});

// DELETE /api/rooms/:roomCode — Supprimer une room sauvegardée
router.delete('/:roomCode', requireAuth, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const uid = authReq.user!.uid;
  const roomCode = (req.params.roomCode as string).toUpperCase();

  try {
    await firestoreService.removeUserRoom(uid, roomCode);
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ success: false, error: 'Erreur serveur' });
  }
});

export default router;
