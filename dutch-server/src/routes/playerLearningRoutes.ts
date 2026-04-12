import { Router, Request, Response } from 'express';
import { requireAppCheck } from '../middleware/appCheckMiddleware';
import { PlayerLearningService } from '../services/PlayerLearningService';
import { SecurityService } from '../services/SecurityService';
import { PlayerLearningUploadPayload } from '../models/PlayerLearning';
import { requireAuth, AuthenticatedRequest } from '../middleware/authMiddleware';

const router = Router();

// Toutes les routes nécessitent une authentification Firebase
router.use(requireAuth);
router.use(requireAppCheck);
const playerLearningService = new PlayerLearningService();

router.post('/upload', SecurityService.learningWriteLimiter, async (req: Request, res: Response) => {
  try {
    const payload: PlayerLearningUploadPayload = req.body;
    // Force clientId to authenticated user's UID (prevents IDOR)
    payload.clientId = (req as AuthenticatedRequest).user!.uid;

    if (!payload.clientId || !payload.slotId || !payload.profile) {
      return res.status(400).json({ error: 'Données invalides' });
    }

    await playerLearningService.upload(payload);

    res.json({ success: true });
  } catch (error) {
    console.error('Erreur upload player profile:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

router.get('/profile', SecurityService.learningReadLimiter, async (req: Request, res: Response) => {
  try {
    // Force clientId to authenticated user's UID (prevents IDOR)
    const clientId = (req as AuthenticatedRequest).user!.uid;
    const slotId = Number.parseInt(req.query.slotId as string);

    if (!clientId || Number.isNaN(slotId)) {
      return res.status(400).json({ error: 'slotId requis' });
    }

    const profile = await playerLearningService.getProfile(clientId, slotId);
    if (!profile) {
      return res.status(404).json({ error: 'Profil introuvable' });
    }

    const history = await playerLearningService.getHistory(clientId, slotId);

    res.json({ profile, history });
  } catch (error) {
    console.error('Erreur get player profile:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

export default router;
