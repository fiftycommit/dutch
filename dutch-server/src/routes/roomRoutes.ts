import { Router } from 'express';
import { requireAuth, AuthenticatedRequest } from '../middleware/authMiddleware';
import { database } from '../services/Database';

const router = Router();

// GET /api/rooms/mine — Récupérer les rooms de l'utilisateur
router.get('/mine', requireAuth, (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const userId = authReq.user!.userId;

  try {
    const rooms = database.instance.prepare(`
      SELECT room_code, is_host, joined_at FROM user_rooms
      WHERE user_id = ?
      ORDER BY joined_at DESC
      LIMIT 10
    `).all(userId) as { room_code: string; is_host: number; joined_at: string }[];

    res.json({
      success: true,
      rooms: rooms.map(r => ({
        roomCode: r.room_code,
        isHost: r.is_host === 1,
        joinedAt: r.joined_at,
      })),
    });
  } catch (e) {
    res.status(500).json({ success: false, error: 'Erreur serveur' });
  }
});

// POST /api/rooms/save — Sauvegarder une room
router.post('/save', requireAuth, (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const userId = authReq.user!.userId;
  const { roomCode, isHost } = req.body;

  if (!roomCode || typeof roomCode !== 'string') {
    return res.status(400).json({ success: false, error: 'roomCode requis' });
  }

  try {
    database.instance.prepare(`
      INSERT INTO user_rooms (user_id, room_code, is_host)
      VALUES (?, ?, ?)
      ON CONFLICT(user_id, room_code) DO UPDATE SET
        is_host = excluded.is_host,
        joined_at = datetime('now')
    `).run(userId, roomCode.toUpperCase(), isHost ? 1 : 0);

    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ success: false, error: 'Erreur serveur' });
  }
});

// DELETE /api/rooms/:roomCode — Supprimer une room sauvegardée
router.delete('/:roomCode', requireAuth, (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const userId = authReq.user!.userId;
  const roomCode = (req.params.roomCode as string).toUpperCase();

  try {
    database.instance.prepare(`
      DELETE FROM user_rooms WHERE user_id = ? AND room_code = ?
    `).run(userId, roomCode);

    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ success: false, error: 'Erreur serveur' });
  }
});

export default router;
