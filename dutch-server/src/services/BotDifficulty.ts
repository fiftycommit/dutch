export interface BotDifficultyConfig {
  name: string;
  forgetChancePerTurn: number;
  confusionOnSwap: number;
  dutchThreshold: number;
  reactionSpeed: number;
  matchAccuracy: number;
  reactionMatchChance: number;
  keepCardThreshold: number;
}

export class BotDifficulty {
  static readonly bronze: BotDifficultyConfig = {
    name: 'Bronze',
    forgetChancePerTurn: 0.18,
    confusionOnSwap: 0.30,
    dutchThreshold: 10,
    reactionSpeed: 0.55,
    matchAccuracy: 0.75,
    reactionMatchChance: 0.35,
    keepCardThreshold: 7,
  };

  static readonly silver: BotDifficultyConfig = {
    name: 'Argent',
    forgetChancePerTurn: 0.08,
    confusionOnSwap: 0.12,
    dutchThreshold: 6,
    reactionSpeed: 0.75,
    matchAccuracy: 0.85,
    reactionMatchChance: 0.55,
    keepCardThreshold: 6,
  };

  static readonly gold: BotDifficultyConfig = {
    name: 'Or',
    forgetChancePerTurn: 0.01,
    confusionOnSwap: 0.01,
    dutchThreshold: 3,
    reactionSpeed: 0.96,
    matchAccuracy: 0.97,
    reactionMatchChance: 0.9,
    keepCardThreshold: 3,
  };

  static readonly platinum: BotDifficultyConfig = {
    name: 'Platine',
    forgetChancePerTurn: 0.0,
    confusionOnSwap: 0.0,
    dutchThreshold: 1,
    reactionSpeed: 1.0,
    matchAccuracy: 1.0,
    reactionMatchChance: 1.0,
    keepCardThreshold: 1,
  };

  static fromMMR(mmr: number): BotDifficultyConfig {
    if (mmr < 300) {
      return this.bronze;
    } else if (mmr < 600) {
      return this.silver;
    } else if (mmr < 900) {
      return this.gold;
    } else {
      return this.platinum;
    }
  }

  static fromRank(rank: string): BotDifficultyConfig {
    switch (rank) {
      case 'Bronze':
        return this.bronze;
      case 'Argent':
        return this.silver;
      case 'Or':
        return this.gold;
      case 'Platine':
        return this.platinum;
      default:
        return this.silver;
    }
  }
}
