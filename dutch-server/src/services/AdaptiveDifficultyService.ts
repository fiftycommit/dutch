import { promises as fs } from 'node:fs';
import path from 'node:path';

interface PlayerStats {
  playerId: string;
  playerName: string;
  totalGames: number;
  wins: number;
  losses: number;
  avgScore: number;
  avgDecisionTime: number;
  skillLevel: 'beginner' | 'intermediate' | 'advanced' | 'expert';
  estimatedMMR: number;
  lastUpdated: string;
}

interface BotDifficultyAdjustment {
  botId: string;
  targetPlayerId: string;
  baseMMR: number;
  adjustedMMR: number;
  adjustmentFactor: number;
  reason: string;
  timestamp: string;
}

/**
 * Service pour ajuster automatiquement la difficulté des bots
 * selon le niveau du joueur humain
 */
export class AdaptiveDifficultyService {
  private dataDir: string;
  private playerStats: Map<string, PlayerStats>;

  constructor() {
    this.dataDir = path.join(__dirname, '../../data/bot-learning/adaptive');
    this.playerStats = new Map();
    this.ensureDataDirectory();
    this.loadPlayerStatsSync();
  }

  private ensureDataDirectory() {
    try {
      const fsSync = require('node:fs');
      if (!fsSync.existsSync(this.dataDir)) {
        fsSync.mkdirSync(this.dataDir, { recursive: true });
      }
    } catch (error) {
      console.error('❌ Erreur création répertoire adaptive:', error instanceof Error ? error.message : String(error));
    }
  }

  /**
   * Analyse les performances d'un joueur pour déterminer son niveau
   */
  async analyzePlayer(playerId: string, games: any[]): Promise<PlayerStats> {
    if (games.length === 0) {
      throw new Error('Aucune partie à analyser');
    }

    const wins = games.filter(g => g.finalRank === 1).length;
    const losses = games.length - wins;
    const avgScore = games.reduce((sum, g) => sum + g.finalScore, 0) / games.length;
    const avgDecisionTime = games.reduce((sum, g) => sum + (g.avgDecisionTime || 1500), 0) / games.length;

    // Calculer le niveau de compétence
    const winRate = wins / games.length;
    const skillLevel = this.determineSkillLevel(winRate, avgScore, avgDecisionTime);
    const estimatedMMR = this.estimatePlayerMMR(winRate, avgScore, games.length);

    const stats: PlayerStats = {
      playerId,
      playerName: games[0]?.playerName || 'Joueur',
      totalGames: games.length,
      wins,
      losses,
      avgScore,
      avgDecisionTime,
      skillLevel,
      estimatedMMR,
      lastUpdated: new Date().toISOString(),
    };

    this.playerStats.set(playerId, stats);
    await this.savePlayerStats(stats);

    console.log(`📊 Joueur analysé: ${stats.playerName} - Niveau: ${skillLevel} - MMR estimé: ${estimatedMMR}`);
    return stats;
  }

  /**
   * Détermine le niveau de compétence du joueur
   */
  private determineSkillLevel(
    winRate: number,
    avgScore: number,
    avgDecisionTime: number
  ): 'beginner' | 'intermediate' | 'advanced' | 'expert' {
    // Débutant : faible taux de victoire, score élevé, décisions lentes
    if (winRate < 0.2 && avgScore > 15 && avgDecisionTime > 3000) {
      return 'beginner';
    }

    // Intermédiaire : taux de victoire moyen, score moyen
    if (winRate < 0.4 && avgScore > 12) {
      return 'intermediate';
    }

    // Avancé : bon taux de victoire, bon score
    if (winRate < 0.6 && avgScore < 12) {
      return 'advanced';
    }

    // Expert : très bon taux de victoire, excellent score
    return 'expert';
  }

  /**
   * Estime le MMR du joueur basé sur ses performances
   */
  private estimatePlayerMMR(winRate: number, avgScore: number, gamesPlayed: number): number {
    const baseMMR = 1500;
    
    // Ajustement basé sur le taux de victoire
    const winRateBonus = (winRate - 0.25) * 1000; // -250 à +750
    
    // Ajustement basé sur le score moyen (meilleur score = plus de MMR)
    const scoreBonus = (15 - avgScore) * 50; // -250 à +500
    
    // Bonus pour l'expérience (plafonné à +200)
    const experienceBonus = Math.min(gamesPlayed * 5, 200);
    
    return Math.max(800, Math.min(2500, baseMMR + winRateBonus + scoreBonus + experienceBonus));
  }

  /**
   * Ajuste la difficulté d'un bot pour un joueur spécifique
   * 
   * Règles :
   * - Bronze/Silver : Bots légèrement plus faibles (-100 à -200 MMR)
   * - Gold/Platinum : Bots plus forts (+100 à +300 MMR) pour challenge
   * - Adaptation progressive pour garder le jeu intéressant
   */
  async adjustBotDifficulty(
    botBaseMMR: number,
    playerId: string,
    targetSkillLevel: 'bronze' | 'silver' | 'gold' | 'platinum'
  ): Promise<BotDifficultyAdjustment> {
    const playerStats = this.playerStats.get(playerId);
    
    if (!playerStats) {
      // Pas de stats, utiliser le MMR de base
      return {
        botId: 'unknown',
        targetPlayerId: playerId,
        baseMMR: botBaseMMR,
        adjustedMMR: botBaseMMR,
        adjustmentFactor: 1,
        reason: 'Aucune statistique disponible',
        timestamp: new Date().toISOString(),
      };
    }

    let adjustmentFactor = 1;
    let reason = '';

    // Ajustement selon le niveau cible
    switch (targetSkillLevel) {
      case 'bronze':
        // Bots plus faciles pour débutants
        if (playerStats.skillLevel === 'beginner') {
          adjustmentFactor = 0.7; // -30% MMR
          reason = 'Débutant : bots plus faciles';
        } else if (playerStats.skillLevel === 'intermediate') {
          adjustmentFactor = 0.85; // -15% MMR
          reason = 'Intermédiaire : bots légèrement plus faciles';
        } else {
          adjustmentFactor = 0.95; // -5% MMR
          reason = 'Avancé : bots compétitifs';
        }
        break;

      case 'silver':
        // Bots équilibrés
        if (playerStats.skillLevel === 'beginner') {
          adjustmentFactor = 0.8; // -20% MMR
          reason = 'Débutant : bots modérés';
        } else if (playerStats.skillLevel === 'intermediate') {
          adjustmentFactor = 0.95; // -5% MMR
          reason = 'Intermédiaire : bots équilibrés';
        } else {
          adjustmentFactor = 1; // MMR normal
          reason = 'Avancé : bots au niveau';
        }
        break;

      case 'gold':
        // Bots plus difficiles
        if (playerStats.skillLevel === 'beginner' || playerStats.skillLevel === 'intermediate') {
          adjustmentFactor = 1.1; // +10% MMR
          reason = 'Challenge modéré';
        } else if (playerStats.skillLevel === 'advanced') {
          adjustmentFactor = 1.2; // +20% MMR
          reason = 'Challenge élevé';
        } else {
          adjustmentFactor = 1.3; // +30% MMR
          reason = 'Expert : challenge maximum';
        }
        break;

      case 'platinum':
        // Bots très difficiles - doivent battre le joueur systématiquement
        if (playerStats.skillLevel === 'beginner' || playerStats.skillLevel === 'intermediate') {
          adjustmentFactor = 1.4; // +40% MMR
          reason = 'Platine : très difficile';
        } else if (playerStats.skillLevel === 'advanced') {
          adjustmentFactor = 1.5; // +50% MMR
          reason = 'Platine : extrêmement difficile';
        } else {
          adjustmentFactor = 1.6; // +60% MMR
          reason = 'Platine : quasi-imbattable';
        }
        break;
    }

    const adjustedMMR = Math.round(botBaseMMR * adjustmentFactor);

    const adjustment: BotDifficultyAdjustment = {
      botId: 'bot_adjusted',
      targetPlayerId: playerId,
      baseMMR: botBaseMMR,
      adjustedMMR,
      adjustmentFactor,
      reason,
      timestamp: new Date().toISOString(),
    };

    console.log(`🎯 Ajustement difficulté: ${botBaseMMR} → ${adjustedMMR} (${reason})`);
    return adjustment;
  }

  /**
   * Recommande un niveau de difficulté pour un joueur
   */
  recommendDifficulty(playerId: string): 'bronze' | 'silver' | 'gold' | 'platinum' {
    const stats = this.playerStats.get(playerId);
    
    if (!stats) {
      return 'bronze'; // Par défaut pour nouveaux joueurs
    }

    const winRate = stats.wins / stats.totalGames;

    // Si le joueur gagne trop (>60%), augmenter la difficulté
    if (winRate > 0.6) {
      if (stats.skillLevel === 'expert') {
        return 'platinum';
      }
      return 'gold';
    }

    // Si le joueur perd trop (<30%), réduire la difficulté
    if (winRate < 0.3) {
      return 'bronze';
    }

    // Sinon, difficulté équilibrée
    return 'silver';
  }

  /**
   * Récupère les stats d'un joueur
   */
  getPlayerStats(playerId: string): PlayerStats | undefined {
    return this.playerStats.get(playerId);
  }

  /**
   * Liste tous les joueurs analysés
   */
  getAllPlayers(): PlayerStats[] {
    return Array.from(this.playerStats.values());
  }

  /**
   * Sauvegarde les stats d'un joueur
   */
  private async savePlayerStats(stats: PlayerStats) {
    try {
      const filePath = path.join(this.dataDir, `${stats.playerId}.json`);
      await fs.writeFile(filePath, JSON.stringify(stats, null, 2));
    } catch (error) {
      console.error(`❌ Erreur sauvegarde stats joueur ${stats.playerId}:`, error instanceof Error ? error.message : String(error));
    }
  }

  /**
   * Charge tous les stats des joueurs
   */
  private loadPlayerStatsSync() {
    try {
      const fsSync = require('node:fs');
      const files: string[] = fsSync.readdirSync(this.dataDir);
      const statFiles = files.filter((f: string) => f.endsWith('.json'));

      for (const file of statFiles) {
        const filePath = path.join(this.dataDir, file);
        const data = fsSync.readFileSync(filePath, 'utf-8');
        const stats: PlayerStats = JSON.parse(data);
        this.playerStats.set(stats.playerId, stats);
      }

      console.log(`✅ ${this.playerStats.size} joueurs chargés pour adaptation`);
    } catch {
      console.log('ℹ️ Aucune statistique de joueur existante');
    }
  }
}
