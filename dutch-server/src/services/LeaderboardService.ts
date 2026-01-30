import { promises as fs } from 'fs';
import path from 'path';

interface LeaderboardEntry {
  rank: number;
  botId: string;
  botName: string;
  mmr: number;
  wins: number;
  losses: number;
  totalGames: number;
  winRate: number;
  avgScore: number;
  skillLevel: string;
  personality?: string;
  generation?: number;
  lastPlayed: string;
}

interface LeaderboardStats {
  totalBots: number;
  avgMMR: number;
  highestMMR: number;
  lowestMMR: number;
  totalGames: number;
  lastUpdated: string;
}

/**
 * Service de classement mondial des bots
 */
export class LeaderboardService {
  private dataDir: string;
  private leaderboard: LeaderboardEntry[];
  private maxEntries: number;

  constructor() {
    this.dataDir = path.join(__dirname, '../../data/bot-learning/leaderboard');
    this.leaderboard = [];
    this.maxEntries = 100; // Top 100
    this.ensureDataDirectory();
    this.loadLeaderboard();
  }

  private async ensureDataDirectory() {
    try {
      const fsSync = require('fs');
      if (!fsSync.existsSync(this.dataDir)) {
        fsSync.mkdirSync(this.dataDir, { recursive: true });
      }
    } catch (error) {
      console.error('❌ Erreur création répertoire leaderboard:', error);
    }
  }

  /**
   * Met à jour le classement avec un bot
   */
  async updateLeaderboard(entry: Omit<LeaderboardEntry, 'rank' | 'winRate'>): Promise<void> {
    // Calculer le taux de victoire
    const winRate = entry.totalGames > 0 ? entry.wins / entry.totalGames : 0;

    // Chercher si le bot existe déjà
    const existingIndex = this.leaderboard.findIndex(e => e.botId === entry.botId);

    const fullEntry: LeaderboardEntry = {
      ...entry,
      rank: 0, // Sera calculé après le tri
      winRate,
    };

    if (existingIndex >= 0) {
      // Mettre à jour l'entrée existante
      this.leaderboard[existingIndex] = fullEntry;
    } else {
      // Ajouter nouvelle entrée
      this.leaderboard.push(fullEntry);
    }

    // Trier par MMR décroissant
    this.leaderboard.sort((a, b) => b.mmr - a.mmr);

    // Limiter au top N
    if (this.leaderboard.length > this.maxEntries) {
      this.leaderboard = this.leaderboard.slice(0, this.maxEntries);
    }

    // Mettre à jour les rangs
    this.leaderboard.forEach((entry, index) => {
      entry.rank = index + 1;
    });

    await this.saveLeaderboard();
  }

  /**
   * Récupère le top N du classement
   */
  getTopBots(limit: number = 10): LeaderboardEntry[] {
    return this.leaderboard.slice(0, limit);
  }

  /**
   * Récupère le classement complet
   */
  getFullLeaderboard(): LeaderboardEntry[] {
    return [...this.leaderboard];
  }

  /**
   * Récupère le classement par niveau de compétence
   */
  getBySkillLevel(skillLevel: string, limit: number = 10): LeaderboardEntry[] {
    return this.leaderboard
      .filter(e => e.skillLevel === skillLevel)
      .slice(0, limit);
  }

  /**
   * Récupère le classement par personnalité
   */
  getByPersonality(personality: string, limit: number = 10): LeaderboardEntry[] {
    return this.leaderboard
      .filter(e => e.personality === personality)
      .slice(0, limit);
  }

  /**
   * Recherche un bot spécifique
   */
  findBot(botId: string): LeaderboardEntry | undefined {
    return this.leaderboard.find(e => e.botId === botId);
  }

  /**
   * Récupère le rang d'un bot
   */
  getBotRank(botId: string): number | null {
    const entry = this.findBot(botId);
    return entry ? entry.rank : null;
  }

  /**
   * Récupère les statistiques du classement
   */
  getStats(): LeaderboardStats {
    if (this.leaderboard.length === 0) {
      return {
        totalBots: 0,
        avgMMR: 0,
        highestMMR: 0,
        lowestMMR: 0,
        totalGames: 0,
        lastUpdated: new Date().toISOString(),
      };
    }

    const totalMMR = this.leaderboard.reduce((sum, e) => sum + e.mmr, 0);
    const totalGames = this.leaderboard.reduce((sum, e) => sum + e.totalGames, 0);

    return {
      totalBots: this.leaderboard.length,
      avgMMR: totalMMR / this.leaderboard.length,
      highestMMR: this.leaderboard[0].mmr,
      lowestMMR: this.leaderboard[this.leaderboard.length - 1].mmr,
      totalGames,
      lastUpdated: new Date().toISOString(),
    };
  }

  /**
   * Récupère les bots qui ont progressé récemment
   */
  getRisingStars(limit: number = 5): LeaderboardEntry[] {
    // Pour l'instant, on retourne les bots avec le meilleur taux de victoire
    // Dans une version future, on pourrait tracker la progression MMR
    return [...this.leaderboard]
      .sort((a, b) => b.winRate - a.winRate)
      .slice(0, limit);
  }

  /**
   * Récupère les statistiques par génération (pour les bots génétiques)
   */
  getGenerationStats(): { generation: number; count: number; avgMMR: number }[] {
    const genMap = new Map<number, { count: number; totalMMR: number }>();

    this.leaderboard.forEach(entry => {
      if (entry.generation !== undefined) {
        const existing = genMap.get(entry.generation) || { count: 0, totalMMR: 0 };
        existing.count++;
        existing.totalMMR += entry.mmr;
        genMap.set(entry.generation, existing);
      }
    });

    return Array.from(genMap.entries())
      .map(([generation, data]) => ({
        generation,
        count: data.count,
        avgMMR: data.totalMMR / data.count,
      }))
      .sort((a, b) => b.generation - a.generation);
  }

  /**
   * Sauvegarde le classement
   */
  private async saveLeaderboard() {
    try {
      const filePath = path.join(this.dataDir, 'leaderboard.json');
      await fs.writeFile(filePath, JSON.stringify(this.leaderboard, null, 2));
    } catch (error) {
      console.error('❌ Erreur sauvegarde leaderboard:', error);
    }
  }

  /**
   * Charge le classement
   */
  private async loadLeaderboard() {
    try {
      const filePath = path.join(this.dataDir, 'leaderboard.json');
      const data = await fs.readFile(filePath, 'utf-8');
      this.leaderboard = JSON.parse(data);
      console.log(`✅ Leaderboard chargé: ${this.leaderboard.length} bots`);
    } catch (error) {
      console.log('ℹ️ Aucun leaderboard existant');
      this.leaderboard = [];
    }
  }

  /**
   * Réinitialise le classement (pour les tests)
   */
  async reset() {
    this.leaderboard = [];
    await this.saveLeaderboard();
    console.log('🔄 Leaderboard réinitialisé');
  }
}
