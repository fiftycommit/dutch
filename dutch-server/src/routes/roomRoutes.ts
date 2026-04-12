import { Router } from 'express';
import { requireAuth, AuthenticatedRequest } from '../middleware/authMiddleware';
import { requireAppCheck } from '../middleware/appCheckMiddleware';
import {
  FIREBASE_UNAVAILABLE_ERROR_CODE,
  isRoomRegistryUnavailableError,
  roomRegistryService,
} from '../services/RoomRegistryService';
import { SecurityService } from '../services/SecurityService';

const router = Router();
const firebaseDownError =
  'Service multijoueur temporairement indisponible (Firebase). Vérifie https://downdetector.com/status/firebase/';

// GET /api/rooms/mine — Récupérer les rooms de l'utilisateur
router.get('/mine', requireAuth, requireAppCheck, SecurityService.userDataLimiter, async (req, res) => {
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
        error: firebaseDownError,
      });
      return;
    }
    res.status(500).json({ success: false, error: 'Erreur serveur' });
  }
});

// DELETE /api/rooms/:roomCode — Retirer une room active de "Mes salons"
router.delete('/:roomCode', requireAuth, requireAppCheck, SecurityService.userDataLimiter, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const uid = authReq.user!.uid;
  const roomCode = (req.params.roomCode as string).toUpperCase();

  try {
    await roomRegistryService.removeActiveRoomForUser(uid, roomCode);
    res.json({ success: true });
  } catch (e) {
    if (isRoomRegistryUnavailableError(e)) {
      res.status(503).json({
        success: false,
        errorCode: FIREBASE_UNAVAILABLE_ERROR_CODE,
        error: firebaseDownError,
      });
      return;
    }
    res.status(500).json({ success: false, error: 'Erreur serveur' });
  }
});

export default router;
