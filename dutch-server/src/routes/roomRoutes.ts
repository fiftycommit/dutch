import { Router } from 'express';
import { requireAuth, AuthenticatedRequest } from '../middleware/authMiddleware';
import { firestoreService } from '../services/FirestoreService';
import {
  FIREBASE_UNAVAILABLE_ERROR_CODE,
  isRoomRegistryUnavailableError,
  roomRegistryService,
} from '../services/RoomRegistryService';

const router = Router();

// GET /api/rooms/mine — Récupérer les rooms de l'utilisateur
router.get('/mine', requireAuth, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const uid = authReq.user!.uid;

  try {
    const rooms = await roomRegistryService.getUserActiveRooms(uid);

    res.json({
      success: true,
      rooms: rooms.map(r => ({
        roomCode: r.roomCode,
        isHost: r.isHost,
        status: r.status,
        playerCount: r.playerCount,
        joinedAt: r.updatedAt?.toDate?.()?.toISOString() || '',
      })),
    });
  } catch (e) {
    if (isRoomRegistryUnavailableError(e)) {
      res.status(503).json({
        success: false,
        errorCode: FIREBASE_UNAVAILABLE_ERROR_CODE,
        error: 'Service multiplayer indisponible. Vérifie Firebase.',
      });
      return;
    }
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
