import * as fs from 'fs/promises';
import * as path from 'path';
import { BotGameRecord, BotAction } from '../models/BotLearning';

interface PlayerPattern {
  avgDecisionTime: number;
  dutchThresholdPattern: number;
  aggressivenessScore: number;
  riskTakingScore: number;
  powerUsageFrequency: number;
  cardReplacementPattern: number[];
  preferredActions: Map<string, number>;
  playStyle: 'aggressive' | 'defensive' | 'balanced' | 'opportunistic';
}

interface ClonedPlayer {
  playerId: string;
  playerName: string;
  createdAt: string;
  gamesAnalyzed: number;
  pattern: PlayerPattern;
  clonedBotId: string;
  accuracy: number;
}

export class PlayerCloningService {
  private dataDir: string;

  constructor() {
    this.dataDir = path.join(__dirname, '../../data/bot-learning/clones');
    this.ensureDataDirectory();
  }

  private async ensureDataDirectory() {
    try {
      await fs.mkdir(this.dataDir, { recursive: true });
    } catch (error) {
      console.error('❌ Erreur création répertoire clones:', error);
    }
  }

  /**
   * Analyse les parties d'un joueur humain pour créer un clone
   */
  async analyzePlayerGames(playerId: string, games: any[]): Promise<PlayerPattern> {
    if (games.length === 0) {
      throw new Error('Aucune partie à analyser');
    }

    let totalDecisionTime = 0;
    let totalDutchCalls = 0;
    let totalDutchScore = 0;
    let aggressiveActions = 0;
    let defensiveActions = 0;
    let powerUses = 0;
    let totalActions = 0;
    const actionCounts = new Map<string, number>();
    const cardReplacementCounts = new Array(4).fill(0);
    let riskActions = 0;

    for (const game of games) {
      for (const action of game.actions || []) {
        totalActions++;
        totalDecisionTime += action.decisionTime || 1000;

        const actionType = action.actionType;
        actionCounts.set(actionType, (actionCounts.get(actionType) || 0) + 1);

        if (actionType === 'draw_from_discard') {
          aggressiveActions++;
        } else if (actionType === 'draw_from_deck') {
          defensiveActions++;
        }

        if (actionType === 'use_power') {
          powerUses++;
        }

        if (actionType === 'replace_card' && action.actionDetails?.cardIndex !== undefined) {
          cardReplacementCounts[action.actionDetails.cardIndex]++;
        }

        if (action.gameState?.myScore > 15 && actionType === 'draw_from_discard') {
          riskActions++;
        }
      }

      if (game.calledDutch) {
        totalDutchCalls++;
        totalDutchScore += game.scoreAtDutch || 0;
      }
    }

    const avgDecisionTime = totalDecisionTime / totalActions;
    const dutchThresholdPattern = totalDutchCalls > 0 ? totalDutchScore / totalDutchCalls : 15;
    const aggressivenessScore = aggressiveActions / (aggressiveActions + defensiveActions);
    const riskTakingScore = riskActions / totalActions;
    const powerUsageFrequency = powerUses / totalActions;

    const preferredActions = new Map<string, number>();
    for (const [action, count] of actionCounts.entries()) {
      preferredActions.set(action, count / totalActions);
    }

    const totalReplacements = cardReplacementCounts.reduce((a, b) => a + b, 0);
    const cardReplacementPattern = cardReplacementCounts.map(c => 
      totalReplacements > 0 ? c / totalReplacements : 0.25
    );

    let playStyle: PlayerPattern['playStyle'] = 'balanced';
    if (aggressivenessScore > 0.7 && riskTakingScore > 0.3) {
      playStyle = 'aggressive';
    } else if (aggressivenessScore < 0.3 && riskTakingScore < 0.2) {
      playStyle = 'defensive';
    } else if (riskTakingScore > 0.4) {
      playStyle = 'opportunistic';
    }

    return {
      avgDecisionTime,
      dutchThresholdPattern,
      aggressivenessScore,
      riskTakingScore,
      powerUsageFrequency,
      cardReplacementPattern,
      preferredActions,
      playStyle,
    };
  }

  /**
   * Crée un bot cloné à partir d'un joueur
   */
  async createClone(
    playerId: string,
    playerName: string,
    games: any[]
  ): Promise<ClonedPlayer> {
    const pattern = await this.analyzePlayerGames(playerId, games);
    
    const clonedBotId = `clone_${playerId}_${Date.now()}`;
    
    const clone: ClonedPlayer = {
      playerId,
      playerName,
      createdAt: new Date().toISOString(),
      gamesAnalyzed: games.length,
      pattern,
      clonedBotId,
      accuracy: this.calculateAccuracy(games.length),
    };

    const filepath = path.join(this.dataDir, `${clonedBotId}.json`);
    await fs.writeFile(filepath, JSON.stringify(clone, null, 2));

    console.log(`✅ Clone créé pour ${playerName}: ${clonedBotId} (${games.length} parties analysées)`);
    
    return clone;
  }

  /**
   * Calcule la précision estimée du clone basée sur le nombre de parties
   */
  private calculateAccuracy(gamesCount: number): number {
    if (gamesCount < 5) return 0.5;
    if (gamesCount < 10) return 0.65;
    if (gamesCount < 20) return 0.75;
    if (gamesCount < 50) return 0.85;
    return 0.95;
  }

  /**
   * Récupère un clone par son ID
   */
  async getClone(clonedBotId: string): Promise<ClonedPlayer | null> {
    try {
      const filepath = path.join(this.dataDir, `${clonedBotId}.json`);
      const data = await fs.readFile(filepath, 'utf-8');
      return JSON.parse(data);
    } catch (error) {
      return null;
    }
  }

  /**
   * Liste tous les clones disponibles
   */
  async listClones(): Promise<ClonedPlayer[]> {
    try {
      const files = await fs.readdir(this.dataDir);
      const clones: ClonedPlayer[] = [];

      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        const data = await fs.readFile(path.join(this.dataDir, file), 'utf-8');
        clones.push(JSON.parse(data));
      }

      return clones.sort((a, b) => b.accuracy - a.accuracy);
    } catch (error) {
      return [];
    }
  }

  /**
   * Convertit un pattern de joueur en paramètres de bot
   */
  patternToBotParameters(pattern: PlayerPattern): Record<string, any> {
    return {
      aggressiveness: pattern.aggressivenessScore,
      caution: 1 - pattern.riskTakingScore,
      dutchThreshold: Math.round(pattern.dutchThresholdPattern),
      powerUsageRate: pattern.powerUsageFrequency,
      memoryAccuracy: 0.8,
      riskTolerance: pattern.riskTakingScore,
      decisionDelay: Math.round(pattern.avgDecisionTime),
      cardReplacementPreference: pattern.cardReplacementPattern,
      playStyle: pattern.playStyle,
    };
  }

  /**
   * Met à jour un clone avec de nouvelles parties
   */
  async updateClone(clonedBotId: string, newGames: any[]): Promise<ClonedPlayer | null> {
    const clone = await this.getClone(clonedBotId);
    if (!clone) return null;

    const allGamesCount = clone.gamesAnalyzed + newGames.length;
    const newPattern = await this.analyzePlayerGames(clone.playerId, newGames);

    const weight = clone.gamesAnalyzed / allGamesCount;
    const newWeight = newGames.length / allGamesCount;

    clone.pattern = {
      avgDecisionTime: clone.pattern.avgDecisionTime * weight + newPattern.avgDecisionTime * newWeight,
      dutchThresholdPattern: clone.pattern.dutchThresholdPattern * weight + newPattern.dutchThresholdPattern * newWeight,
      aggressivenessScore: clone.pattern.aggressivenessScore * weight + newPattern.aggressivenessScore * newWeight,
      riskTakingScore: clone.pattern.riskTakingScore * weight + newPattern.riskTakingScore * newWeight,
      powerUsageFrequency: clone.pattern.powerUsageFrequency * weight + newPattern.powerUsageFrequency * newWeight,
      cardReplacementPattern: clone.pattern.cardReplacementPattern.map((v, i) => 
        v * weight + newPattern.cardReplacementPattern[i] * newWeight
      ),
      preferredActions: clone.pattern.preferredActions,
      playStyle: newPattern.playStyle,
    };

    clone.gamesAnalyzed = allGamesCount;
    clone.accuracy = this.calculateAccuracy(allGamesCount);

    const filepath = path.join(this.dataDir, `${clonedBotId}.json`);
    await fs.writeFile(filepath, JSON.stringify(clone, null, 2));

    console.log(`✅ Clone mis à jour: ${clonedBotId} (${allGamesCount} parties)`);
    
    return clone;
  }
}
