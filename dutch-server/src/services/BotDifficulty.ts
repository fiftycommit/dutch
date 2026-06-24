export interface BotDifficultyConfig {
  name: string;
  forgetChancePerTurn: number;
  confusionOnSwap: number;
  dutchThreshold: number;
  reactionSpeed: number;
  matchAccuracy: number;
  reactionMatchChance: number;
}

export class BotDifficulty {
  static readonly bronze: BotDifficultyConfig = {
    name: 'Bronze',
    forgetChancePerTurn: 0.18,
    confusionOnSwap: 0.3,
    dutchThreshold: 10,
    reactionSpeed: 0.55,
    matchAccuracy: 0.75,
    reactionMatchChance: 0.35,
  };

  static readonly silver: BotDifficultyConfig = {
    name: 'Argent',
    forgetChancePerTurn: 0.08,
    confusionOnSwap: 0.12,
    dutchThreshold: 6,
    reactionSpeed: 0.75,
    matchAccuracy: 0.85,
    reactionMatchChance: 0.55,
  };

  // Palier fort unique : fusion des anciens Or+Platine (= valeurs Platine, les
  // plus fortes), alignée sur le client (BotDifficulty.difficult, 'Difficile').
  static readonly difficult: BotDifficultyConfig = {
    name: 'Difficile',
    forgetChancePerTurn: 0,
    confusionOnSwap: 0,
    dutchThreshold: 1,
    reactionSpeed: 1,
    matchAccuracy: 1,
    reactionMatchChance: 1,
  };

  static fromMMR(mmr: number): BotDifficultyConfig {
    if (mmr < 300) {
      return this.bronze;
    } else if (mmr < 600) {
      return this.silver;
    } else {
      // Anciennes plages Or (600-899) + Platine (>=900) fusionnées.
      return this.difficult;
    }
  }

  static fromRank(rank: string): BotDifficultyConfig {
    switch (rank) {
      case 'Bronze':
        return this.bronze;
      case 'Argent':
        return this.silver;
      // Legacy 'Or'/'Platine' fusionnés en 'Difficile'.
      case 'Or':
      case 'Platine':
      case 'Difficile':
        return this.difficult;
      default:
        return this.silver;
    }
  }
}
