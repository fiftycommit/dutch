import { Router, Request, Response } from 'express';
import { PlayerLearningService } from '../services/PlayerLearningService';
import { PlayerLearningUploadPayload } from '../models/PlayerLearning';

const router = Router();
const playerLearningService = new PlayerLearningService();

router.post('/upload', async (req: Request, res: Response) => {
  try {
    const payload: PlayerLearningUploadPayload = req.body;

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

router.get('/profile', async (req: Request, res: Response) => {
  try {
    const clientId = req.query.clientId as string;
    const slotId = Number.parseInt(req.query.slotId as string);

    if (!clientId || Number.isNaN(slotId)) {
      return res.status(400).json({ error: 'clientId et slotId requis' });
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
