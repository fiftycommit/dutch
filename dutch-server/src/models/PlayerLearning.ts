export interface PlayerProfileSnapshot {
  clientId: string;
  slotId: number;
  profileId: string;
  createdAt: string;
  lastUpdatedAt: string;
  gamesAnalyzed: number;
  learnedParameters: Record<string, any>;
  updatedAt: string;
}

export interface PlayerGameRecordSnapshot {
  gameId: string;
  startTime: string;
  endTime: string;
  usedSBMM: boolean;
  numberOfPlayers: number;
  finalRank: number;
  finalScore: number;
  calledDutch: boolean;
  wonDutch: boolean;
  profileBefore?: Record<string, any>;
  profileAfter?: Record<string, any>;
}

export interface PlayerLearningUploadPayload {
  clientId: string;
  slotId: number;
  profile: {
    profileId: string;
    createdAt: string;
    lastUpdatedAt: string;
    gamesAnalyzed: number;
    learnedParameters: Record<string, any>;
  };
  history?: PlayerGameRecordSnapshot[];
}
