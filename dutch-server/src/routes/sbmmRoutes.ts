import { Router, Request, Response } from 'express';
import { SBMMService } from '../services/SBMMService';
import { requireAuth, AuthenticatedRequest } from '../middleware/authMiddleware';
import { requireAdmin } from '../middleware/adminAuthMiddleware';

const router = Router();

// Toutes les routes nécessitent une authentification Firebase
router.use(requireAuth);
const sbmmService = new SBMMService();

// GET /api/sbmm/bot-mix?playerId=X&botCount=3
// Retourne le mix de BotSkillLevel recommandé pour un joueur
router.get('/bot-mix', (req: Request, res: Response) => {
  try {
    // Force playerId to authenticated user's UID (prevents IDOR)
    const playerId = (req as AuthenticatedRequest).user!.uid;
    const botCount = Number.parseInt(req.query.botCount as string, 10);

    if (!playerId) {
      return res.status(400).json({ error: 'playerId requis' });
    }
    if (Number.isNaN(botCount) || botCount < 1 || botCount > 5) {
      return res.status(400).json({ error: 'botCount doit être entre 1 et 5' });
    }

    const result = sbmmService.getBotMix(playerId, botCount);
    res.json(result);
  } catch (error) {
    console.error('Erreur bot-mix:', error);
    res.status(500).json({ error: 'Erreur interne' });
  }
});

// POST /api/sbmm/record-game
// Enregistre le résultat d'une partie et ajuste MMR/cursor
router.post('/record-game', (req: Request, res: Response) => {
  try {
    const { gameId, rank, score, botResults, totalPlayers, dutchCalled, dutchWon } = req.body;
    // Force playerId to authenticated user's UID (prevents IDOR)
    const playerId = (req as AuthenticatedRequest).user!.uid;

    if (!playerId || !gameId || rank === undefined || score === undefined) {
      return res.status(400).json({ error: 'Champs requis: playerId, gameId, rank, score' });
    }
    if (!Array.isArray(botResults) || botResults.length === 0) {
      return res.status(400).json({ error: 'botResults doit être un tableau non vide' });
    }
    if (!totalPlayers || totalPlayers < 2) {
      return res.status(400).json({ error: 'totalPlayers doit être >= 2' });
    }

    const result = sbmmService.recordGame(
      playerId,
      gameId,
      rank,
      score,
      botResults,
      totalPlayers,
      dutchCalled ?? false,
      dutchWon ?? false
    );

    res.json({ success: true, ...result });
  } catch (error) {
    console.error('Erreur record-game:', error);
    res.status(500).json({ error: 'Erreur interne' });
  }
});

// GET /api/sbmm/player-profile/:playerId
// Retourne le profil SBMM complet d'un joueur
router.get('/player-profile/:playerId', (req: Request, res: Response) => {
  try {
    // Force playerId to authenticated user's UID (prevents IDOR)
    const playerId = (req as AuthenticatedRequest).user!.uid;

    const profile = sbmmService.getProfile(playerId);
    res.json(profile);
  } catch (error) {
    console.error('Erreur player-profile:', error);
    res.status(500).json({ error: 'Erreur interne' });
  }
});

// GET /api/sbmm/bot-stats
// Retourne les stats agrégées par niveau de bot (pour le centre d'entraînement)
router.get('/bot-stats', (req: Request, res: Response) => {
  try {
    const stats = sbmmService.getBotStats();
    res.json(stats);
  } catch (error) {
    console.error('Erreur bot-stats:', error);
    res.status(500).json({ error: 'Erreur interne' });
  }
});

// POST /api/sbmm/reset
// Reset toutes les données SBMM
router.post('/reset', requireAdmin, (req: Request, res: Response) => {
  try {
    const result = sbmmService.resetAll();
    res.json({ success: true, ...result });
  } catch (error) {
    console.error('Erreur reset:', error);
    res.status(500).json({ error: 'Erreur interne' });
  }
});

export default router;
