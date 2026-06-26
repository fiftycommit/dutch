import { Router, Request, Response } from 'express';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { BotLearningService } from '../services/BotLearningService';
import { PlayerCloningService } from '../services/PlayerCloningService';
import { BotPersonalityService } from '../services/BotPersonalityService';
import { BotGameRecord } from '../models/BotLearning';
import { requireAuth, AuthenticatedRequest } from '../middleware/authMiddleware';
import { requireAdmin } from '../middleware/adminAuthMiddleware';
import { requireAppCheck } from '../middleware/appCheckMiddleware';
import { SecurityService } from '../services/SecurityService';

const router = Router();

// Toutes les routes nécessitent une authentification Firebase
router.use(requireAuth);
router.use(SecurityService.learningReadLimiter);
const botLearningService = new BotLearningService();
const cloningService = new PlayerCloningService();
const personalityService = new BotPersonalityService();
const trainingSeriesPath = path.join(__dirname, '../../data/bot-learning/training-series.jsonl');

function getAuthUid(req: Request): string {
  return (req as AuthenticatedRequest).user!.uid;
}

/**
 * POST /api/bot-learning/record
 * Enregistre une partie de bot
 */
router.post('/record', requireAdmin, async (req: Request, res: Response) => {
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
router.get('/top-bots', requireAdmin, async (req: Request, res: Response) => {
  try {
    const limit = Number.parseInt(req.query.limit as string) || 10;
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
router.get('/parameters/:behavior/:skillLevel', requireAdmin, async (req: Request, res: Response) => {
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
router.get('/stats', requireAdmin, async (req: Request, res: Response) => {
  try {
    const stats = await botLearningService.getStats();
    res.json(stats);
  } catch (error) {
    console.error('Erreur récupération stats:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

router.get('/ml-stats', requireAdmin, (_req: Request, res: Response) => {
  res.status(410).json({ error: 'Machine learning stats supprimés.' });
});

router.post('/predict-action', requireAdmin, (_req: Request, res: Response) => {
  res.status(410).json({ error: 'Prédiction d\'action supprimée.' });
});

/**
 * POST /api/bot-learning/clone-player
 * Crée un clone d'un joueur
 */
router.post('/clone-player', requireAppCheck, SecurityService.learningWriteLimiter, async (req: Request, res: Response) => {
  try {
    const { playerName, games } = req.body;
    const playerId = getAuthUid(req);
    
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
router.get('/clones', requireAppCheck, async (req: Request, res: Response) => {
  try {
    const clones = await cloningService.listClones();
    const authUid = getAuthUid(req);
    const ownClones = clones.filter(clone => clone.playerId === authUid);
    res.json(ownClones);
  } catch (error) {
    console.error('Erreur récupération clones:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * GET /api/bot-learning/clone/:clonedBotId
 * Récupère un clone spécifique
 */
router.get('/clone/:clonedBotId', requireAppCheck, async (req: Request, res: Response) => {
  try {
    const clonedBotId = Array.isArray(req.params.clonedBotId) ? req.params.clonedBotId[0] : req.params.clonedBotId;
    const clone = await cloningService.getClone(clonedBotId);
    
    if (!clone) {
      return res.status(404).json({ error: 'Clone non trouvé' });
    }

    if (clone.playerId !== getAuthUid(req)) {
      return res.status(403).json({ error: 'Accès refusé' });
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
router.put('/clone/:clonedBotId', requireAppCheck, SecurityService.learningWriteLimiter, async (req: Request, res: Response) => {
  try {
    const { games } = req.body;
    
    if (!games || games.length === 0) {
      return res.status(400).json({ error: 'Aucune partie fournie' });
    }
    
    const clonedBotId = Array.isArray(req.params.clonedBotId) ? req.params.clonedBotId[0] : req.params.clonedBotId;
    const existingClone = await cloningService.getClone(clonedBotId);
    if (!existingClone) {
      return res.status(404).json({ error: 'Clone non trouvé' });
    }
    if (existingClone.playerId !== getAuthUid(req)) {
      return res.status(403).json({ error: 'Accès refusé' });
    }

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
router.get('/personalities', requireAdmin, async (req: Request, res: Response) => {
  try {
    const personalities = personalityService.getAllPersonalities();
    res.json(personalities);
  } catch (error) {
    console.error('Erreur récupération personnalités:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * POST /api/bot-learning/training-series
 * Enregistre un point de suivi d'entraînement (bots vs fantômes)
 */
router.post('/training-series', requireAdmin, async (req: Request, res: Response) => {
  try {
    const { timestamp, totalMatches, botWinRate } = req.body || {};

    if (!timestamp || typeof totalMatches !== 'number' || typeof botWinRate !== 'number') {
      return res.status(400).json({ error: 'Données invalides' });
    }

    await fs.mkdir(path.dirname(trainingSeriesPath), { recursive: true });
    const entry = JSON.stringify({
      timestamp,
      totalMatches,
      botWinRate,
    });
    await fs.appendFile(trainingSeriesPath, `${entry}\n`);
    res.json({ success: true });
  } catch (error) {
    console.error('Erreur enregistrement training-series:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * GET /api/bot-learning/training-series
 * Retourne la série de suivi d'entraînement
 */
router.get('/training-series', requireAdmin, async (req: Request, res: Response) => {
  try {
    const limit = Math.min(Number.parseInt(req.query.limit as string) || 200, 1000);

    let content = '';
    try {
      content = await fs.readFile(trainingSeriesPath, 'utf-8');
    } catch {
      return res.json([]);
    }

    const lines = content
      .split('\n')
      .map(l => l.trim())
      .filter(Boolean)
      .map(line => {
        try {
          return JSON.parse(line);
        } catch {
          return null;
        }
      })
      .filter(Boolean) as Array<{ timestamp: string; totalMatches: number; botWinRate: number }>;

    const sliced = lines.slice(-limit);
    res.json(sliced);
  } catch (error) {
    console.error('Erreur récupération training-series:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * GET /api/bot-learning/personality/:id
 * Récupère une personnalité spécifique
 */
router.get('/personality/:id', requireAdmin, async (req: Request, res: Response) => {
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
router.get('/personality-random', requireAdmin, async (req: Request, res: Response) => {
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
router.get('/personality/difficulty/:level', requireAdmin, async (req: Request, res: Response) => {
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
router.get('/team/:count', requireAdmin, async (req: Request, res: Response) => {
  try {
    const countParam = Array.isArray(req.params.count) ? req.params.count[0] : req.params.count;
    const count = Number.parseInt(countParam);
    
    if (Number.isNaN(count) || count < 1 || count > 10) {
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
router.post('/personality', requireAdmin, async (req: Request, res: Response) => {
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

// ========== Phase 4: Routes de Compétition ==========

/**
 * GET /api/bot-learning/leaderboard
 * Récupère le classement mondial
 */
router.get('/leaderboard', requireAdmin, async (req: Request, res: Response) => {
  try {
    const limit = Number.parseInt(req.query.limit as string) || 100;
    const leaderboard = botLearningService.getLeaderboardService().getTopBots(limit);
    res.json(leaderboard);
  } catch (error) {
    console.error('Erreur récupération leaderboard:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * GET /api/bot-learning/leaderboard/stats
 * Récupère les stats du leaderboard
 */
router.get('/leaderboard/stats', requireAdmin, async (req: Request, res: Response) => {
  try {
    const stats = botLearningService.getLeaderboardService().getStats();
    res.json(stats);
  } catch (error) {
    console.error('Erreur récupération stats leaderboard:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * POST /api/bot-learning/tournament/create
 * Crée un nouveau tournoi
 */
router.post('/tournament/create', requireAdmin, async (req: Request, res: Response) => {
  try {
    const { name, type, participants } = req.body;
    
    if (!name || !type || !participants || !Array.isArray(participants)) {
      return res.status(400).json({ error: 'Données de tournoi invalides' });
    }
    
    const tournament = await botLearningService.getTournamentService().createTournament(name, type, participants);
    res.json(tournament);
  } catch (error: any) {
    console.error('Erreur création tournoi:', error);
    res.status(500).json({ error: error.message || 'Erreur serveur' });
  }
});

/**
 * POST /api/bot-learning/tournament/:id/run
 * Lance un tournoi
 */
router.post('/tournament/:id/run', requireAdmin, async (req: Request, res: Response) => {
  try {
    const tournamentId = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const tournament = await botLearningService.getTournamentService().runTournament(tournamentId);
    res.json(tournament);
  } catch (error: any) {
    console.error('Erreur lancement tournoi:', error);
    res.status(500).json({ error: error.message || 'Erreur serveur' });
  }
});

/**
 * GET /api/bot-learning/tournament/:id
 * Récupère un tournoi
 */
router.get('/tournament/:id', requireAdmin, async (req: Request, res: Response) => {
  try {
    const tournamentId = Array.isArray(req.params.id) ? req.params.id[0] : req.params.id;
    const tournament = botLearningService.getTournamentService().getTournament(tournamentId);
    
    if (!tournament) {
      return res.status(404).json({ error: 'Tournoi introuvable' });
    }
    
    res.json(tournament);
  } catch (error) {
    console.error('Erreur récupération tournoi:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * GET /api/bot-learning/tournaments
 * Liste tous les tournois
 */
router.get('/tournaments', requireAdmin, async (req: Request, res: Response) => {
  try {
    const status = req.query.status as 'pending' | 'in_progress' | 'completed' | undefined;
    const tournaments = await botLearningService.getTournamentService().listTournaments(status);
    res.json(tournaments);
  } catch (error) {
    console.error('Erreur liste tournois:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

router.post('/genetic/initialize', requireAdmin, (_req: Request, res: Response) => {
  res.status(410).json({ error: 'Algorithme génétique supprimé.' });
});

router.post('/genetic/evolve', requireAdmin, (_req: Request, res: Response) => {
  res.status(410).json({ error: 'Algorithme génétique supprimé.' });
});

router.get('/genetic/population', requireAdmin, (_req: Request, res: Response) => {
  res.status(410).json({ error: 'Algorithme génétique supprimé.' });
});

router.get('/genetic/best', requireAdmin, (_req: Request, res: Response) => {
  res.status(410).json({ error: 'Algorithme génétique supprimé.' });
});

/**
 * POST /api/bot-learning/adaptive/analyze
 * Analyse un joueur pour adapter la difficulté
 */
router.post('/adaptive/analyze', async (req: Request, res: Response) => {
  try {
    const { games } = req.body;
    const playerId = getAuthUid(req);
    
    if (!playerId || !games || !Array.isArray(games)) {
      return res.status(400).json({ error: 'Données invalides' });
    }
    
    const stats = await botLearningService.getAdaptiveService().analyzePlayer(playerId, games);
    res.json(stats);
  } catch (error: any) {
    console.error('Erreur analyse joueur:', error);
    res.status(500).json({ error: error.message || 'Erreur serveur' });
  }
});

/**
 * POST /api/bot-learning/adaptive/adjust
 * Ajuste la difficulté d'un bot pour un joueur
 */
router.post('/adaptive/adjust', async (req: Request, res: Response) => {
  try {
    const { botBaseMMR, targetSkillLevel } = req.body;
    const playerId = getAuthUid(req);
    
    if (!botBaseMMR || !playerId || !targetSkillLevel) {
      return res.status(400).json({ error: 'Données invalides' });
    }
    
    const adjustment = await botLearningService.getAdaptiveService().adjustBotDifficulty(
      botBaseMMR,
      playerId,
      targetSkillLevel
    );
    res.json(adjustment);
  } catch (error) {
    console.error('Erreur ajustement difficulté:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

/**
 * GET /api/bot-learning/adaptive/recommend/:playerId
 * Recommande un niveau de difficulté pour un joueur
 */
router.get('/adaptive/recommend/:playerId', async (req: Request, res: Response) => {
  try {
    const playerId = getAuthUid(req);
    const difficulty = botLearningService.getAdaptiveService().recommendDifficulty(playerId);
    res.json({ playerId, recommendedDifficulty: difficulty });
  } catch (error) {
    console.error('Erreur recommandation difficulté:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

// Route pour analyser les patterns de mélange
router.get('/shuffle-stats', requireAdmin, async (req, res) => {
  try {
    const stats = await botLearningService.getShuffleStats();
    res.json(stats);
  } catch (error) {
    console.error('❌ Erreur récupération stats mélange:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

// ========== Contrôles Dashboard ==========

/**
 * GET /api/bot-learning/learning-status
 * Retourne le statut de l'apprentissage (actif ou en pause)
 */
router.get('/learning-status', requireAdmin, async (req: Request, res: Response) => {
  const pendingCount = await botLearningService.getPendingCount();
  res.json({ paused: botLearningService.isPaused(), pendingCount });
});

/**
 * POST /api/bot-learning/pause
 * Met en pause ou reprend l'apprentissage
 */
router.post('/pause', requireAdmin, (req: Request, res: Response) => {
  const { paused } = req.body;
  botLearningService.setPaused(!!paused);
  res.json({ success: true, paused: botLearningService.isPaused() });
});

/**
 * POST /api/bot-learning/reset
 * Réinitialise toutes les données d'apprentissage
 */
router.post('/reset', requireAdmin, async (req: Request, res: Response) => {
  try {
    const result = await botLearningService.resetAll();
    res.json({ success: true, ...result });
  } catch (error) {
    console.error('Erreur reset learning:', error);
    res.status(500).json({ error: 'Erreur serveur' });
  }
});

export default router;
