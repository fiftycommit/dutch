import fs from 'node:fs';
import path from 'node:path';
import { sanitizeId } from '../utils/sanitize';

// ============================================================
// INTERFACES
// ============================================================

interface GameResult {
  gameId: string;
  rank: number;
  score: number;
  botLevels: string[];
  totalPlayers: number;
  dutchCalled: boolean;
  dutchWon: boolean;
  timestamp: string;
}

interface PlayerSBMMProfile {
  playerId: string;
  mmr: number;
  cursor: number;
  gamesPlayed: number;
  wins: number;
  winRate: number;
  recentResults: GameResult[];
  lastUpdated: string;
}

interface BotResult {
  level: string;
  rank: number;
  score: number;
  dutchCalled: boolean;
  dutchWon: boolean;
}

interface BotLevelStats {
  level: string;
  gamesPlayed: number;
  winsVsHumans: number;
  winRateVsHumans: number;
  totalScore: number;
  avgScore: number;
  totalRank: number;
  avgRank: number;
  dutchCallCount: number;
  dutchSuccessCount: number;
  dutchSuccessRate: number;
}

interface AllBotStats {
  bronze: BotLevelStats;
  silver: BotLevelStats;
  gold: BotLevelStats;
  platinum: BotLevelStats;
}

// ============================================================
// SERVICE
// ============================================================

export class SBMMService {
  private readonly dataDir: string;
  private readonly profilesDir: string;
  private readonly botStatsPath: string;

  constructor() {
    this.dataDir = path.join(__dirname, '../../data/sbmm');
    this.profilesDir = path.join(this.dataDir, 'profiles');
    this.botStatsPath = path.join(this.dataDir, 'bot-stats.json');
    this.ensureDirectories();
  }

  private ensureDirectories(): void {
    if (!fs.existsSync(this.dataDir)) {
      fs.mkdirSync(this.dataDir, { recursive: true });
    }
    if (!fs.existsSync(this.profilesDir)) {
      fs.mkdirSync(this.profilesDir, { recursive: true });
    }
  }

  // ============================================================
  // PROFIL JOUEUR
  // ============================================================

  getProfile(playerId: string): PlayerSBMMProfile {
    const filePath = path.join(this.profilesDir, `${sanitizeId(playerId)}.json`);
    if (fs.existsSync(filePath)) {
      try {
        return JSON.parse(fs.readFileSync(filePath, 'utf-8'));
      } catch {
        // Fichier corrompu, recréer
      }
    }
    return this.createDefaultProfile(playerId);
  }

  private saveProfile(profile: PlayerSBMMProfile): void {
    const filePath = path.join(this.profilesDir, `${sanitizeId(profile.playerId)}.json`);
    fs.writeFileSync(filePath, JSON.stringify(profile, null, 2));
  }

  private createDefaultProfile(playerId: string): PlayerSBMMProfile {
    return {
      playerId,
      mmr: 500,
      cursor: this.mmrToCursor(500),
      gamesPlayed: 0,
      wins: 0,
      winRate: 0,
      recentResults: [],
      lastUpdated: new Date().toISOString(),
    };
  }

  // ============================================================
  // ALGO SBMM — MMR ↔ CURSOR
  // ============================================================

  // Sigmoïde centrée à 600 MMR
  // MMR 0→0.05, 300→0.18, 500→0.38, 600→0.50, 800→0.73, 1000→0.88, 1200→0.95
  mmrToCursor(mmr: number): number {
    return 1 / (1 + Math.exp(-(mmr - 600) / 200));
  }

  // ============================================================
  // ALGO SBMM — CURSOR → BOT MIX
  // ============================================================

  // Convertit un cursor (0-1) en niveau de bot
  // Zones de transition probabilistes pour éviter les sauts brusques
  private cursorToSkillLevel(cursor: number): string {
    if (cursor < 0.25) return 'bronze';
    if (cursor < 0.35) {
      // Transition Bronze → Argent
      return Math.random() < (cursor - 0.25) / 0.1 ? 'silver' : 'bronze';
    }
    if (cursor < 0.55) return 'silver';
    if (cursor < 0.65) {
      // Transition Argent → Or
      return Math.random() < (cursor - 0.55) / 0.1 ? 'gold' : 'silver';
    }
    if (cursor < 0.8) return 'gold';
    if (cursor < 0.88) {
      // Transition Or → Platine
      return Math.random() < (cursor - 0.8) / 0.08 ? 'platinum' : 'gold';
    }
    return 'platinum';
  }

  // Génère le mix de bots pour un joueur
  // Étale les bots autour du cursor avec un spread pour créer de la variété
  getBotMix(playerId: string, botCount: number): { botLevels: string[]; cursor: number; mmr: number } {
    const profile = this.getProfile(playerId);
    const cursor = profile.cursor;
    const levels: string[] = [];

    const spread = botCount > 1 ? 0.15 : 0;

    for (let i = 0; i < botCount; i++) {
      const offset = botCount > 1
        ? -spread + (2 * spread * i) / (botCount - 1)
        : 0;
      const effectiveCursor = Math.max(0, Math.min(1, cursor + offset));
      levels.push(this.cursorToSkillLevel(effectiveCursor));
    }

    // Trier du plus faible au plus fort
    const order: Record<string, number> = { bronze: 0, silver: 1, gold: 2, platinum: 3 };
    levels.sort((a, b) => (order[a] ?? 0) - (order[b] ?? 0));

    return { botLevels: levels, cursor, mmr: profile.mmr };
  }

  // ============================================================
  // ALGO — AJUSTEMENT POST-PARTIE
  // ============================================================

  // MMR implicite par niveau de bot
  private static readonly LEVEL_MMR: Record<string, number> = {
    bronze: 300,
    silver: 500,
    gold: 750,
    platinum: 1000,
  };

  recordGame(
    playerId: string,
    gameId: string,
    rank: number,
    score: number,
    botResults: BotResult[],
    totalPlayers: number,
    dutchCalled: boolean,
    dutchWon: boolean
  ): { newMMR: number; newCursor: number } {
    const profile = this.getProfile(playerId);

    // Calculer le nouveau MMR (Elo adapté multi-joueurs)
    const botLevels = botResults.map((b) => b.level);
    const newMMR = this.adjustMMR(profile, rank, totalPlayers, botLevels, dutchCalled, dutchWon);

    // Enregistrer le résultat
    const result: GameResult = {
      gameId,
      rank,
      score,
      botLevels,
      totalPlayers,
      dutchCalled,
      dutchWon,
      timestamp: new Date().toISOString(),
    };

    profile.recentResults.push(result);
    if (profile.recentResults.length > 20) {
      profile.recentResults = profile.recentResults.slice(-20);
    }

    // Mettre à jour le profil
    profile.mmr = newMMR;
    profile.gamesPlayed++;
    if (rank === 1) profile.wins++;
    profile.winRate = profile.gamesPlayed > 0 ? profile.wins / profile.gamesPlayed : 0;
    profile.cursor = this.adjustCursor(profile);
    profile.lastUpdated = new Date().toISOString();

    this.saveProfile(profile);

    // Mettre à jour les stats agrégées par niveau de bot
    this.updateBotStats(rank, totalPlayers, botResults);

    return { newMMR: profile.mmr, newCursor: profile.cursor };
  }

  // Ajustement MMR Elo adapté multi-joueurs
  private adjustMMR(
    profile: PlayerSBMMProfile,
    rank: number,
    totalPlayers: number,
    botLevels: string[],
    dutchCalled: boolean,
    dutchWon: boolean
  ): number {
    const K = 32;

    // MMR moyen des bots affrontés
    const botMMRAvg = botLevels.reduce(
      (sum, level) => sum + (SBMMService.LEVEL_MMR[level] ?? 500), 0
    ) / botLevels.length;

    // Score attendu (Elo)
    const expectedScore = 1 / (1 + Math.pow(10, (botMMRAvg - profile.mmr) / 400));

    // Score réel basé sur le placement (1er = 1.0, dernier = 0.0)
    const actualScore = totalPlayers > 1
      ? (totalPlayers - rank) / (totalPlayers - 1)
      : 0.5;

    // Bonus/malus Dutch
    let dutchModifier = 0;
    if (dutchCalled) {
      dutchModifier = dutchWon ? 5 : -8;
    }

    const change = Math.round(K * (actualScore - expectedScore)) + dutchModifier;
    return Math.max(0, Math.min(1500, profile.mmr + change));
  }

  // Ajustement Cursor (confort) — lissage adaptatif
  private adjustCursor(profile: PlayerSBMMProfile): number {
    const baseCursor = this.mmrToCursor(profile.mmr);
    const recent = profile.recentResults.slice(-10);

    if (recent.length < 3) {
      return baseCursor; // Pas assez de données, utiliser le MMR brut
    }

    // Win rate récent
    const recentWins = recent.filter((r) => r.rank === 1).length;
    const recentWinRate = recentWins / recent.length;

    if (recentWinRate > 0.55) {
      // Trop facile → monter
      return Math.min(1, baseCursor + 0.05);
    }
    if (recentWinRate < 0.15) {
      // Trop dur → descendre
      return Math.max(0, baseCursor - 0.08);
    }

    // Rang moyen : si presque toujours dernier, descendre
    const avgRank = recent.reduce((s, r) => s + r.rank, 0) / recent.length;
    const avgTotal = recent.reduce((s, r) => s + r.totalPlayers, 0) / recent.length;
    if (avgTotal > 0 && avgRank > avgTotal * 0.8) {
      return Math.max(0, baseCursor - 0.05);
    }

    return baseCursor;
  }

  // ============================================================
  // STATS AGRÉGÉES PAR NIVEAU DE BOT
  // ============================================================

  private getDefaultBotStats(): AllBotStats {
    const defaultLevel = (level: string): BotLevelStats => ({
      level,
      gamesPlayed: 0,
      winsVsHumans: 0,
      winRateVsHumans: 0,
      totalScore: 0,
      avgScore: 0,
      totalRank: 0,
      avgRank: 0,
      dutchCallCount: 0,
      dutchSuccessCount: 0,
      dutchSuccessRate: 0,
    });

    return {
      bronze: defaultLevel('bronze'),
      silver: defaultLevel('silver'),
      gold: defaultLevel('gold'),
      platinum: defaultLevel('platinum'),
    };
  }

  getBotStats(): AllBotStats {
    if (fs.existsSync(this.botStatsPath)) {
      try {
        return JSON.parse(fs.readFileSync(this.botStatsPath, 'utf-8'));
      } catch {
        // Fichier corrompu
      }
    }
    return this.getDefaultBotStats();
  }

  private saveBotStats(stats: AllBotStats): void {
    fs.writeFileSync(this.botStatsPath, JSON.stringify(stats, null, 2));
  }

  // Met à jour les stats de chaque bot après une partie
  private updateBotStats(humanRank: number, totalPlayers: number, botResults: BotResult[]): void {
    const stats = this.getBotStats();

    for (const bot of botResults) {
      const level = bot.level as keyof AllBotStats;
      const levelStats = stats[level];
      if (!levelStats) continue;

      levelStats.gamesPlayed++;
      levelStats.totalScore += bot.score;
      levelStats.totalRank += bot.rank;
      levelStats.avgScore = levelStats.totalScore / levelStats.gamesPlayed;
      levelStats.avgRank = levelStats.totalRank / levelStats.gamesPlayed;

      // Win vs humain = bot est arrivé avant l'humain
      if (bot.rank < humanRank) {
        levelStats.winsVsHumans++;
      }
      levelStats.winRateVsHumans = levelStats.gamesPlayed > 0
        ? levelStats.winsVsHumans / levelStats.gamesPlayed
        : 0;

      // Dutch
      if (bot.dutchCalled) {
        levelStats.dutchCallCount++;
        if (bot.dutchWon) {
          levelStats.dutchSuccessCount++;
        }
      }
      levelStats.dutchSuccessRate = levelStats.dutchCallCount > 0
        ? levelStats.dutchSuccessCount / levelStats.dutchCallCount
        : 0;
    }

    this.saveBotStats(stats);
  }

  // ============================================================
  // RESET
  // ============================================================

  resetAll(): { deletedProfiles: number } {
    let deletedProfiles = 0;

    // Supprimer les profils
    if (fs.existsSync(this.profilesDir)) {
      const files = fs.readdirSync(this.profilesDir).filter((f) => f.endsWith('.json'));
      for (const file of files) {
        fs.unlinkSync(path.join(this.profilesDir, file));
        deletedProfiles++;
      }
    }

    // Réinitialiser les stats des bots
    this.saveBotStats(this.getDefaultBotStats());

    return { deletedProfiles };
  }
}
