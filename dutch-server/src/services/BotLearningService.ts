import * as fs from 'fs/promises';
import * as path from 'path';
import { BotGameRecord, BotProfile, BotStats } from '../models/BotLearning';
import { QLearningService } from './QLearningService';
import { NeuralNetworkService } from './NeuralNetworkService';
import { TournamentService } from './TournamentService';
import { GeneticAlgorithmService } from './GeneticAlgorithmService';
import { AdaptiveDifficultyService } from './AdaptiveDifficultyService';
import { LeaderboardService } from './LeaderboardService';

export class BotLearningService {
  private dataDir: string;
  private qLearning: QLearningService;
  private neuralNet: NeuralNetworkService;
  private tournament: TournamentService;
  private genetic: GeneticAlgorithmService;
  private adaptive: AdaptiveDifficultyService;
  private leaderboard: LeaderboardService;

  constructor() {
    this.dataDir = path.join(__dirname, '../../data/bot-learning');
    this.ensureDataDirectory();
    this.qLearning = new QLearningService();
    this.neuralNet = new NeuralNetworkService();
    this.tournament = new TournamentService();
    this.genetic = new GeneticAlgorithmService();
    this.adaptive = new AdaptiveDifficultyService();
    this.leaderboard = new LeaderboardService();
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
      
      // Entraîner les modèles ML
      await this.qLearning.trainFromGame(record);
      await this.neuralNet.trainFromGame(record);
      this.qLearning.decayEpsilon();
      
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
          botName: record.botName,
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
          avgPBeatHuman: 0.5,
          totalDutchCalls: 0,
          successfulDutchCalls: 0,
          mmr: this.getInitialMMR(record.botSkillLevel),
          mmrHistory: [],
          learnedParameters: this.getDefaultParameters(record.botBehavior, record.botSkillLevel),
        };
      }

      // Backfill botName si absent (anciennes données)
      if (!profile.botName) {
        profile.botName = record.botName;
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

      if (typeof record.pBeatHuman === 'number') {
        const prev = typeof profile.avgPBeatHuman === 'number' ? profile.avgPBeatHuman : 0.5;
        profile.avgPBeatHuman = (prev * (profile.totalGames - 1) + record.pBeatHuman) / profile.totalGames;
      }
      
      if (record.calledDutch) {
        profile.totalDutchCalls++;
        if (record.wonDutch) {
          profile.successfulDutchCalls++;
        }
      }

      // Mettre à jour le MMR
      const oldMMR = profile.mmr;
      const opponentMMRs = record.opponents.map(opp => opp.mmr).filter(mmr => mmr !== undefined);
      profile.mmr = this.calculateNewMMR(profile.mmr, record.finalRank, record.numberOfPlayers, opponentMMRs);
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
   * Calcule le nouveau MMR après une partie (Elo avancé)
   */
  private calculateNewMMR(currentMMR: number, rank: number, totalPlayers: number, opponentMMRs: number[] = []): number {
    const K = 32; // Facteur K d'Elo
    
    // Si on a les MMR des adversaires, utiliser le calcul Elo avancé
    if (opponentMMRs.length > 0) {
      const avgOpponentMMR = opponentMMRs.reduce((sum, mmr) => sum + mmr, 0) / opponentMMRs.length;
      const expectedScore = 1 / (1 + Math.pow(10, (avgOpponentMMR - currentMMR) / 400));
      const actualScore = (totalPlayers - rank) / (totalPlayers - 1); // 1.0 = 1er, 0.0 = dernier
      const change = K * (actualScore - expectedScore);
      return Math.round(currentMMR + change);
    }
    
    // Sinon, utiliser le calcul simple
    const performance = (totalPlayers - rank + 1) / totalPlayers;
    const expected = 0.5;
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
      dutchQuality: 0.5,
      powerDefensiveRate: 0.5,
      powerOffensiveRate: 0.5,
      memoryAccuracy: 0.7,
      memoryRetention: 0.7,
      targetingStrategy: 'balanced',
      adaptability: 0.5,
      decisionSpeed: 2000,
      aggressiveness_winning: 0.5,
      aggressiveness_losing: 0.5,
      caution_winning: 0.5,
      caution_losing: 0.5,
    };

    // Ajuster selon le comportement
    switch (behavior) {
      case 'fast':
        baseParams.aggressiveness = 0.7;
        baseParams.caution = 0.3;
        baseParams.decisionSpeed = 1200;
        break;
      case 'aggressive':
        baseParams.aggressiveness = 0.8;
        baseParams.caution = 0.2;
        baseParams.dutchThreshold = 18;
        baseParams.powerOffensiveRate = 0.7;
        baseParams.targetingStrategy = 'leader';
        break;
      case 'balanced':
        // Garder les valeurs par défaut
        break;
    }

    // Ajuster selon le niveau
    switch (skillLevel) {
      case 'bronze':
        baseParams.memoryAccuracy = 0.5;
        baseParams.memoryRetention = 0.4;
        baseParams.powerDefensiveRate = 0.3;
        baseParams.powerOffensiveRate = 0.2;
        baseParams.adaptability = 0.3;
        break;
      case 'silver':
        baseParams.memoryAccuracy = 0.7;
        baseParams.memoryRetention = 0.7;
        baseParams.powerDefensiveRate = 0.5;
        baseParams.powerOffensiveRate = 0.4;
        baseParams.adaptability = 0.5;
        break;
      case 'gold':
        baseParams.memoryAccuracy = 0.9;
        baseParams.memoryRetention = 0.85;
        baseParams.powerDefensiveRate = 0.7;
        baseParams.powerOffensiveRate = 0.6;
        baseParams.adaptability = 0.7;
        break;
    }

    return baseParams;
  }

  /**
   * Ajuste les paramètres appris en fonction des performances (Gradient Descent + Imitation)
   */
  private adjustParameters(profile: BotProfile, record: BotGameRecord): Record<string, any> {
    const params = { ...profile.learnedParameters };
    // Learning rate plus agressif pour adaptation rapide (toutes les 1-2 parties)
    const baseLearningRate = 0.15;
    
    // Taux d'apprentissage adaptatif - reste élevé plus longtemps
    // Après 10 parties: 0.15 / sqrt(1.5) = 0.12
    // Après 50 parties: 0.15 / sqrt(2) = 0.10
    const adaptiveLR = baseLearningRate / Math.sqrt(1 + profile.totalGames / 20);
    
    // Calculer le gradient pour chaque paramètre
    const gradients = this.calculateParameterGradients(profile, record);
    
    // APPRENTISSAGE PAR IMITATION : Si le bot a mal performé, imiter les meilleurs
    if (record.finalRank >= 3 && record.opponents.length > 0) {
      const bestOpponent = record.opponents
        .filter(opp => opp.rank === 1) // Le gagnant
        .find(opp => opp.mmr && opp.mmr > profile.mmr + 100); // Significativement meilleur
      
      if (bestOpponent && bestOpponent.learnedParams) {
        // Imiter partiellement les paramètres du meilleur bot
        const imitationRate = 0.15; // 15% d'imitation
        for (const [param, value] of Object.entries(bestOpponent.learnedParams)) {
          if (typeof params[param] === 'number' && typeof value === 'number') {
            // Interpoler vers les paramètres du meilleur
            params[param] = params[param] * (1 - imitationRate) + value * imitationRate;
          }
        }
        console.log(`🎓 ${profile.botId} apprend de ${bestOpponent.botId} (MMR: ${bestOpponent.mmr})`);
      }
    }
    
    // Appliquer le gradient descent avec momentum
    for (const [param, gradient] of Object.entries(gradients)) {
      if (typeof params[param] === 'number') {
        const momentum = 0.9;
        const previousValue = params[param];
        
        // Mise à jour avec gradient descent
        params[param] = params[param] - adaptiveLR * gradient;
        
        // Appliquer les contraintes (0-1 pour la plupart des paramètres)
        if (param !== 'dutchThreshold') {
          params[param] = Math.max(0, Math.min(1, params[param]));
        } else {
          params[param] = Math.max(5, Math.min(30, params[param]));
        }
      }
    }
    
    // Ajustements spécifiques basés sur les résultats - plus agressifs
    if (record.calledDutch && record.wonDutch) {
      params.dutchThreshold = Math.max(5, params.dutchThreshold - 1.5); // Plus rapide
    } else if (record.calledDutch && !record.wonDutch) {
      params.dutchThreshold = Math.min(30, params.dutchThreshold + 2.5); // Plus rapide
    }
    
    return params;
  }
  
  /**
   * Calcule les gradients pour chaque paramètre
   */
  private calculateParameterGradients(profile: BotProfile, record: BotGameRecord): Record<string, number> {
    const gradients: Record<string, number> = {
      aggressiveness: 0,
      caution: 0,
      dutchThreshold: 0,
      dutchQuality: 0,
      powerDefensiveRate: 0,
      powerOffensiveRate: 0,
      memoryAccuracy: 0,
      memoryRetention: 0,
      adaptability: 0,
      decisionSpeed: 0,
      aggressiveness_winning: 0,
      aggressiveness_losing: 0,
      caution_winning: 0,
      caution_losing: 0,
    };
    
    // Performance score: 1.0 = victoire, 0.0 = dernier
    const performanceScore = (record.numberOfPlayers - record.finalRank) / (record.numberOfPlayers - 1);
    const targetScore = 0.7; // Objectif de performance
    const error = performanceScore - targetScore;
    
    // Gradient pour l'agressivité - PLUS AGRESSIF (x2)
    if (record.finalScore > 20) {
      gradients.aggressiveness = error * 1.0; // Trop agressif si score élevé
    } else {
      gradients.aggressiveness = -error * 1.0; // Pas assez agressif si bon score
    }
    
    // Gradient pour la prudence (inverse de l'agressivité)
    gradients.caution = -gradients.aggressiveness;
    
    // Gradient pour le seuil Dutch - PLUS RAPIDE (x2)
    if (record.calledDutch) {
      if (record.wonDutch) {
        gradients.dutchThreshold = -2; // Réduire le seuil si Dutch réussi
      } else {
        gradients.dutchThreshold = 4; // Augmenter si Dutch raté
      }
    } else if (record.finalRank > 2) {
      gradients.dutchThreshold = -1; // Aurait dû appeler Dutch plus tôt
    }
    
    // Gradient pour l'utilisation des pouvoirs - PLUS AGRESSIF
    const powerEfficiency = record.powerUsesCount > 0 ? 
      (record.goodDecisions / Math.max(1, record.powerUsesCount)) : 0.5;
    gradients.powerUsageRate = (powerEfficiency - 0.5) * error * 2;
    
    // Pénalité supplémentaire pour mauvaises décisions (ex: Joker sur 1 carte)
    if (record.badDecisions > 0) {
      gradients.powerUsageRate += 0.3 * record.badDecisions; // Réduire l'utilisation des pouvoirs
    }
    
    // Gradient pour la tolérance au risque - PLUS RAPIDE
    if (record.badDecisions > record.goodDecisions) {
      gradients.riskTolerance = 0.6; // Réduire la prise de risque
    } else {
      gradients.riskTolerance = -0.4; // Augmenter
    }
    
    // Gradient pour la précision de mémorisation (toujours améliorer)
    gradients.memoryAccuracy = -0.2 * error;
    
    return gradients;
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

  /**
   * Obtient les statistiques des modèles ML
   */
  getMLStats() {
    return {
      qLearning: this.qLearning.getStats(),
      neuralNetwork: this.neuralNet.getStats(),
      genetic: this.genetic.getStats(),
      leaderboard: this.leaderboard.getStats(),
    };
  }

  /**
   * Prédit la meilleure action avec le réseau de neurones
   */
  predictAction(gameState: any, action: any): string {
    return this.neuralNet.predictBestAction(gameState, action);
  }

  // ========== Phase 4: Services de Compétition ==========

  /**
   * Accès au service de tournois
   */
  getTournamentService() {
    return this.tournament;
  }

  /**
   * Accès au service génétique
   */
  getGeneticService() {
    return this.genetic;
  }

  /**
   * Accès au service d'adaptation de difficulté
   */
  getAdaptiveService() {
    return this.adaptive;
  }

  /**
   * Accès au service de leaderboard
   */
  getLeaderboardService() {
    return this.leaderboard;
  }

  /**
   * Met à jour le leaderboard après une partie
   */
  async updateLeaderboardAfterGame(record: BotGameRecord, profile: BotProfile) {
    await this.leaderboard.updateLeaderboard({
      botId: record.botId,
      botName: record.botName,
      mmr: profile.mmr,
      wins: profile.wins,
      losses: profile.losses,
      totalGames: profile.totalGames,
      avgScore: profile.avgScore,
      skillLevel: record.botSkillLevel,
      personality: profile.behavior || 'balanced',
      lastPlayed: record.endTime || new Date().toISOString(),
    });
  }

  /**
   * Sélectionne une action avec Q-Learning
   */
  selectQLearningAction(state: any, availableActions: any[]): any {
    return this.qLearning.selectAction(state, availableActions);
  }
}
