import * as fs from 'fs/promises';
import * as path from 'path';
import { BotGameRecord, BotProfile, BotStats } from '../models/BotLearning';

export class BotLearningService {
  private dataDir: string;

  constructor() {
    this.dataDir = path.join(__dirname, '../../data/bot-learning');
    this.ensureDataDirectory();
  }

  private async ensureDataDirectory() {
    try {
      await fs.mkdir(this.dataDir, { recursive: true });
      await fs.mkdir(path.join(this.dataDir, 'games'), { recursive: true });
      await fs.mkdir(path.join(this.dataDir, 'profiles'), { recursive: true });
    } catch (error) {
      console.error('❌ Erreur création répertoire bot-learning:', error);
    }
  }

  /**
   * Enregistre une partie de bot
   */
  async saveGameRecord(record: BotGameRecord): Promise<void> {
    try {
      const filename = `${record.gameId}_${record.botId}_${Date.now()}.json`;
      const filepath = path.join(this.dataDir, 'games', filename);
      
      await fs.writeFile(filepath, JSON.stringify(record, null, 2));
      
      // Mettre à jour le profil du bot
      await this.updateBotProfile(record);
      
      console.log(`✅ Partie bot enregistrée: ${filename}`);
    } catch (error) {
      console.error('❌ Erreur sauvegarde partie bot:', error);
    }
  }

  /**
   * Met à jour le profil d'un bot avec les résultats d'une partie
   */
  private async updateBotProfile(record: BotGameRecord): Promise<void> {
    try {
      const profilePath = path.join(this.dataDir, 'profiles', `${record.botId}.json`);
      
      let profile: BotProfile;
      
      // Charger le profil existant ou en créer un nouveau
      try {
        const data = await fs.readFile(profilePath, 'utf-8');
        profile = JSON.parse(data);
      } catch {
        // Nouveau bot
        profile = {
          botId: record.botId,
          behavior: record.botBehavior,
          skillLevel: record.botSkillLevel,
          createdAt: new Date().toISOString(),
          lastPlayedAt: new Date().toISOString(),
          totalGames: 0,
          wins: 0,
          losses: 0,
          winRate: 0,
          avgScore: 0,
          avgRank: 0,
          totalDutchCalls: 0,
          successfulDutchCalls: 0,
          mmr: this.getInitialMMR(record.botSkillLevel),
          mmrHistory: [],
          learnedParameters: this.getDefaultParameters(record.botBehavior, record.botSkillLevel),
        };
      }

      // Mettre à jour les statistiques
      profile.totalGames++;
      profile.lastPlayedAt = new Date().toISOString();
      
      if (record.finalRank === 1) {
        profile.wins++;
      } else {
        profile.losses++;
      }
      
      profile.winRate = profile.wins / profile.totalGames;
      profile.avgScore = (profile.avgScore * (profile.totalGames - 1) + record.finalScore) / profile.totalGames;
      profile.avgRank = (profile.avgRank * (profile.totalGames - 1) + record.finalRank) / profile.totalGames;
      
      if (record.calledDutch) {
        profile.totalDutchCalls++;
        if (record.wonDutch) {
          profile.successfulDutchCalls++;
        }
      }

      // Mettre à jour le MMR
      const oldMMR = profile.mmr;
      profile.mmr = this.calculateNewMMR(profile.mmr, record.finalRank, record.numberOfPlayers);
      profile.mmrHistory.push(profile.mmr);
      
      // Limiter l'historique MMR à 100 parties
      if (profile.mmrHistory.length > 100) {
        profile.mmrHistory = profile.mmrHistory.slice(-100);
      }

      // Ajuster les paramètres appris
      profile.learnedParameters = this.adjustParameters(profile, record);

      await fs.writeFile(profilePath, JSON.stringify(profile, null, 2));
      
      console.log(`✅ Profil bot mis à jour: ${record.botId} (MMR: ${oldMMR} → ${profile.mmr})`);
    } catch (error) {
      console.error('❌ Erreur mise à jour profil bot:', error);
    }
  }

  /**
   * Récupère le MMR initial selon le niveau
   */
  private getInitialMMR(skillLevel: string): number {
    switch (skillLevel) {
      case 'bronze': return 800;
      case 'silver': return 1200;
      case 'gold': return 1600;
      default: return 1000;
    }
  }

  /**
   * Calcule le nouveau MMR après une partie
   */
  private calculateNewMMR(currentMMR: number, rank: number, totalPlayers: number): number {
    const K = 32; // Facteur K d'Elo
    const expectedRank = (totalPlayers + 1) / 2; // Rang attendu (milieu)
    const performance = (totalPlayers - rank + 1) / totalPlayers; // 1.0 = victoire, 0.0 = dernier
    const expected = 0.5; // Attendu = 50%
    
    const change = K * (performance - expected);
    return Math.round(currentMMR + change);
  }

  /**
   * Paramètres par défaut selon le comportement et niveau
   */
  private getDefaultParameters(behavior: string, skillLevel: string): Record<string, any> {
    const baseParams = {
      aggressiveness: 0.5,
      caution: 0.5,
      dutchThreshold: 15,
      powerUsageRate: 0.5,
      memoryAccuracy: 0.7,
      riskTolerance: 0.5,
    };

    // Ajuster selon le comportement
    switch (behavior) {
      case 'fast':
        baseParams.aggressiveness = 0.7;
        baseParams.caution = 0.3;
        break;
      case 'aggressive':
        baseParams.aggressiveness = 0.8;
        baseParams.riskTolerance = 0.7;
        baseParams.dutchThreshold = 18;
        break;
      case 'balanced':
        // Garder les valeurs par défaut
        break;
    }

    // Ajuster selon le niveau
    switch (skillLevel) {
      case 'bronze':
        baseParams.memoryAccuracy = 0.5;
        baseParams.powerUsageRate = 0.3;
        break;
      case 'silver':
        baseParams.memoryAccuracy = 0.7;
        baseParams.powerUsageRate = 0.5;
        break;
      case 'gold':
        baseParams.memoryAccuracy = 0.9;
        baseParams.powerUsageRate = 0.7;
        break;
    }

    return baseParams;
  }

  /**
   * Ajuste les paramètres appris en fonction des performances
   */
  private adjustParameters(profile: BotProfile, record: BotGameRecord): Record<string, any> {
    const params = { ...profile.learnedParameters };
    const learningRate = 0.05; // Taux d'apprentissage

    // Si victoire, renforcer les paramètres actuels
    if (record.finalRank === 1) {
      // Légère augmentation de tous les paramètres qui ont bien fonctionné
      if (record.calledDutch && record.wonDutch) {
        // Dutch réussi = bon timing
        params.dutchThreshold = Math.max(10, params.dutchThreshold - 1);
      }
      
      if (record.powerUsesCount > 0) {
        // Bonne utilisation des pouvoirs
        params.powerUsageRate = Math.min(1.0, params.powerUsageRate + learningRate);
      }
    } else {
      // Défaite = ajuster
      if (record.calledDutch && !record.wonDutch) {
        // Dutch raté = trop tôt ou trop tard
        if (record.scoreAtDutch > 20) {
          params.dutchThreshold = Math.min(25, params.dutchThreshold + 2);
        }
      }
      
      if (record.badDecisions > record.goodDecisions) {
        // Trop de mauvaises décisions = être plus prudent
        params.caution = Math.min(1.0, params.caution + learningRate);
        params.aggressiveness = Math.max(0.0, params.aggressiveness - learningRate);
      }
    }

    return params;
  }

  /**
   * Récupère les meilleurs bots
   */
  async getTopBots(limit: number = 10, behavior?: string, skillLevel?: string): Promise<BotProfile[]> {
    try {
      const profilesDir = path.join(this.dataDir, 'profiles');
      const files = await fs.readdir(profilesDir);
      
      const profiles: BotProfile[] = [];
      
      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        
        const data = await fs.readFile(path.join(profilesDir, file), 'utf-8');
        const profile: BotProfile = JSON.parse(data);
        
        // Filtrer par comportement et niveau si spécifié
        if (behavior && profile.behavior !== behavior) continue;
        if (skillLevel && profile.skillLevel !== skillLevel) continue;
        
        profiles.push(profile);
      }
      
      // Trier par MMR décroissant
      profiles.sort((a, b) => b.mmr - a.mmr);
      
      return profiles.slice(0, limit);
    } catch (error) {
      console.error('❌ Erreur récupération top bots:', error);
      return [];
    }
  }

  /**
   * Récupère les paramètres d'un bot spécifique
   */
  async getBotParameters(behavior: string, skillLevel: string): Promise<Record<string, any> | null> {
    try {
      const botId = `${behavior}_${skillLevel}`;
      const profilePath = path.join(this.dataDir, 'profiles', `${botId}.json`);
      
      const data = await fs.readFile(profilePath, 'utf-8');
      const profile: BotProfile = JSON.parse(data);
      
      return profile.learnedParameters;
    } catch (error) {
      // Si le bot n'existe pas, retourner les paramètres par défaut
      return this.getDefaultParameters(behavior, skillLevel);
    }
  }

  /**
   * Récupère les statistiques globales
   */
  async getStats(): Promise<BotStats> {
    try {
      const profilesDir = path.join(this.dataDir, 'profiles');
      const gamesDir = path.join(this.dataDir, 'games');
      
      const profileFiles = await fs.readdir(profilesDir);
      const gameFiles = await fs.readdir(gamesDir);
      
      const profiles: BotProfile[] = [];
      for (const file of profileFiles) {
        if (!file.endsWith('.json')) continue;
        const data = await fs.readFile(path.join(profilesDir, file), 'utf-8');
        profiles.push(JSON.parse(data));
      }
      
      const totalGames = profiles.reduce((sum, p) => sum + p.totalGames, 0);
      const avgWinRate = profiles.length > 0
        ? profiles.reduce((sum, p) => sum + p.winRate, 0) / profiles.length
        : 0;
      
      const topPerformers = profiles
        .sort((a, b) => b.mmr - a.mmr)
        .slice(0, 10);
      
      // Récupérer les 10 dernières parties
      const recentGameFiles = gameFiles
        .filter(f => f.endsWith('.json'))
        .sort()
        .reverse()
        .slice(0, 10);
      
      const recentGames: BotGameRecord[] = [];
      for (const file of recentGameFiles) {
        const data = await fs.readFile(path.join(gamesDir, file), 'utf-8');
        recentGames.push(JSON.parse(data));
      }
      
      return {
        totalGames,
        totalBots: profiles.length,
        avgWinRate,
        topPerformers,
        recentGames,
      };
    } catch (error) {
      console.error('❌ Erreur récupération stats:', error);
      return {
        totalGames: 0,
        totalBots: 0,
        avgWinRate: 0,
        topPerformers: [],
        recentGames: [],
      };
    }
  }
}
