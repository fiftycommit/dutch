import { Router, Request, Response } from 'express';
import { BotLearningService } from '../services/BotLearningService';
import { PlayerCloningService } from '../services/PlayerCloningService';
import { BotPersonalityService } from '../services/BotPersonalityService';
import { BotGameRecord } from '../models/BotLearning';

const router = Router();
const botLearningService = new BotLearningService();
const cloningService = new PlayerCloningService();
const personalityService = new BotPersonalityService();

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

/**
 * GET /api/bot-learning/ml-stats
 * Récupère les statistiques des modèles ML
 */
router.get('/ml-stats', async (req: Request, res: Response) => {
  try {
    const mlStats = botLearningService.getMLStats();
    res.json(mlStats);
  } catch (error) {
    console.error('Erreur récupération stats ML:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * POST /api/bot-learning/predict-action
 * Prédit la meilleure action avec le réseau de neurones
 */
router.post('/predict-action', async (req: Request, res: Response) => {
  try {
    const { gameState, action } = req.body;
    const prediction = botLearningService.predictAction(gameState, action);
    res.json({ predictedAction: prediction });
  } catch (error) {
    console.error('Erreur prédiction action:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * POST /api/bot-learning/clone-player
 * Crée un clone d'un joueur
 */
router.post('/clone-player', async (req: Request, res: Response) => {
  try {
    const { playerId, playerName, games } = req.body;
    
    if (!playerId || !playerName || !games || games.length === 0) {
      return res.status(400).json({ error: 'Données invalides' });
    }
    
    const clone = await cloningService.createClone(playerId, playerName, games);
    res.json(clone);
  } catch (error) {
    console.error('Erreur création clone:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * GET /api/bot-learning/clones
 * Liste tous les clones disponibles
 */
router.get('/clones', async (req: Request, res: Response) => {
  try {
    const clones = await cloningService.listClones();
    res.json(clones);
  } catch (error) {
    console.error('Erreur récupération clones:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * GET /api/bot-learning/clone/:clonedBotId
 * Récupère un clone spécifique
 */
router.get('/clone/:clonedBotId', async (req: Request, res: Response) => {
  try {
    const clonedBotId = Array.isArray(req.params.clonedBotId) ? req.params.clonedBotId[0] : req.params.clonedBotId;
    const clone = await cloningService.getClone(clonedBotId);
    
    if (!clone) {
      return res.status(404).json({ error: 'Clone non trouvé' });
    }
    
    res.json(clone);
  } catch (error) {
    console.error('Erreur récupération clone:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * PUT /api/bot-learning/clone/:clonedBotId
 * Met à jour un clone avec de nouvelles parties
 */
router.put('/clone/:clonedBotId', async (req: Request, res: Response) => {
  try {
    const { games } = req.body;
    
    if (!games || games.length === 0) {
      return res.status(400).json({ error: 'Aucune partie fournie' });
    }
    
    const clonedBotId = Array.isArray(req.params.clonedBotId) ? req.params.clonedBotId[0] : req.params.clonedBotId;
    const clone = await cloningService.updateClone(clonedBotId, games);
    
    if (!clone) {
      return res.status(404).json({ error: 'Clone non trouvé' });
    }
    
    res.json(clone);
  } catch (error) {
    console.error('Erreur mise à jour clone:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * GET /api/bot-learning/personalities
 * Liste toutes les personnalités disponibles
 */
router.get('/personalities', async (req: Request, res: Response) => {
  try {
    const personalities = personalityService.getAllPersonalities();
    res.json(personalities);
  } catch (error) {
    console.error('Erreur récupération personnalités:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * GET /api/bot-learning/personality/:id
 * Récupère une personnalité spécifique
 */
router.get('/personality/:id', async (req: Request, res: Response) => {
  try {
    const id = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const personality = personalityService.getPersonality(id);
    
    if (!personality) {
      return res.status(404).json({ error: 'Personnalité non trouvée' });
    }
    
    res.json(personality);
  } catch (error) {
    console.error('Erreur récupération personnalité:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * GET /api/bot-learning/personality/random
 * Récupère une personnalité aléatoire
 */
router.get('/personality-random', async (req: Request, res: Response) => {
  try {
    const personality = personalityService.getRandomPersonality();
    res.json(personality);
  } catch (error) {
    console.error('Erreur récupération personnalité aléatoire:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * GET /api/bot-learning/personality/difficulty/:level
 * Récupère une personnalité selon la difficulté
 */
router.get('/personality/difficulty/:level', async (req: Request, res: Response) => {
  try {
    const level = req.params.level as 'easy' | 'medium' | 'hard';
    
    if (!['easy', 'medium', 'hard'].includes(level)) {
      return res.status(400).json({ error: 'Niveau de difficulté invalide' });
    }
    
    const personality = personalityService.getPersonalityByDifficulty(level);
    res.json(personality);
  } catch (error) {
    console.error('Erreur récupération personnalité par difficulté:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * GET /api/bot-learning/team/:count
 * Crée une équipe équilibrée de personnalités
 */
router.get('/team/:count', async (req: Request, res: Response) => {
  try {
    const countParam = Array.isArray(req.params.count) ? req.params.count[0] : req.params.count;
    const count = parseInt(countParam);
    
    if (isNaN(count) || count < 1 || count > 10) {
      return res.status(400).json({ error: 'Nombre invalide (1-10)' });
    }
    
    const team = personalityService.createBalancedTeam(count);
    res.json(team);
  } catch (error) {
    console.error('Erreur création équipe:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * POST /api/bot-learning/personality
 * Crée une personnalité personnalisée
 */
router.post('/personality', async (req: Request, res: Response) => {
  try {
    const personality = req.body;
    
    if (!personality.id || !personality.name || !personality.traits || !personality.behaviors) {
      return res.status(400).json({ error: 'Données de personnalité invalides' });
    }
    
    await personalityService.createCustomPersonality(personality);
    res.json({ success: true, message: 'Personnalité créée' });
  } catch (error) {
    console.error('Erreur création personnalité:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

export default router;
