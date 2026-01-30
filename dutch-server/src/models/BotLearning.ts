export interface BotAction {
  actionType: string;
  turnNumber: number;
  timestamp: string;
  gameState: Record<string, any>;
  actionDetails: Record<string, any>;
  result: Record<string, any>;
}

export interface BotGameRecord {
  gameId: string;
  botId: string;
  botName: string;
  botBehavior: string;
  botSkillLevel: string;
  startTime: string;
  endTime?: string;
  numberOfPlayers: number;
  gameMode: string;
  usedSBMM: boolean;
  actions: BotAction[];
  initialHandSize: number;
  finalScore: number;
  finalRank: number;
  calledDutch: boolean;
  wonDutch: boolean;
  cardsAtDutch: number;
  scoreAtDutch: number;
  totalTurns: number;
  avgDecisionTime: number;
  powerUsesCount: number;
  goodDecisions: number;
  badDecisions: number;
  opponents: Array<Record<string, any>>;
}

export interface BotProfile {
  botId: string;
  botName?: string;
  behavior: string;
  skillLevel: string;
  createdAt: string;
  lastPlayedAt: string;
  totalGames: number;
  wins: number;
  losses: number;
  winRate: number;
  avgScore: number;
  avgRank: number;
  totalDutchCalls: number;
  successfulDutchCalls: number;
  mmr: number;
  mmrHistory: number[];
  learnedParameters: Record<string, any>;
}

export interface BotStats {
  totalGames: number;
  totalBots: number;
  avgWinRate: number;
  topPerformers: BotProfile[];
  recentGames: BotGameRecord[];
}
