import { Router, Request, Response } from 'express';
import { BotLearningService } from '../services/BotLearningService';
import { BotGameRecord } from '../models/BotLearning';

const router = Router();
const botLearningService = new BotLearningService();

/**
 * POST /api/bot-learning/record
 * Enregistre une partie de bot
 */
router.post('/record', async (req: Request, res: Response) => {
  try {
    const record: BotGameRecord = req.body;
    
    // Validation basique
    if (!record.gameId || !record.botId || !record.botName) {
      return res.status(400).json({ error: 'Données invalides' });
    }
    
    await botLearningService.saveGameRecord(record);
    
    res.json({ success: true, message: 'Partie enregistrée' });
  } catch (error) {
    console.error('Erreur enregistrement partie bot:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * GET /api/bot-learning/top-bots
 * Récupère les meilleurs bots
 */
router.get('/top-bots', async (req: Request, res: Response) => {
  try {
    const limit = parseInt(req.query.limit as string) || 10;
    const behavior = req.query.behavior as string | undefined;
    const skillLevel = req.query.skillLevel as string | undefined;
    
    const topBots = await botLearningService.getTopBots(limit, behavior, skillLevel);
    
    res.json(topBots);
  } catch (error) {
    console.error('Erreur récupération top bots:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * GET /api/bot-learning/parameters/:behavior/:skillLevel
 * Récupère les paramètres appris d'un bot
 */
router.get('/parameters/:behavior/:skillLevel', async (req: Request, res: Response) => {
  try {
    const behavior = req.params.behavior as string;
    const skillLevel = req.params.skillLevel as string;
    
    const parameters = await botLearningService.getBotParameters(behavior, skillLevel);
    
    if (!parameters) {
      return res.status(404).json({ error: 'Bot non trouvé' });
    }
    
    res.json(parameters);
  } catch (error) {
    console.error('Erreur récupération paramètres bot:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * GET /api/bot-learning/stats
 * Récupère les statistiques globales
 */
router.get('/stats', async (req: Request, res: Response) => {
  try {
    const stats = await botLearningService.getStats();
    res.json(stats);
  } catch (error) {
    console.error('Erreur récupération stats:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

export default router;
