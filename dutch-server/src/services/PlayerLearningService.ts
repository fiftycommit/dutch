import * as fs from 'fs/promises';
import * as path from 'path';
import {
  PlayerLearningUploadPayload,
  PlayerProfileSnapshot,
  PlayerGameRecordSnapshot,
} from '../models/PlayerLearning';

export class PlayerLearningService {
  private dataDir: string;

  constructor() {
    this.dataDir = path.join(__dirname, '../../data/player-learning');
    this.ensureDataDirectory();
  }

  private async ensureDataDirectory() {
    try {
      await fs.mkdir(this.dataDir, { recursive: true });
      await fs.mkdir(path.join(this.dataDir, 'profiles'), { recursive: true });
      await fs.mkdir(path.join(this.dataDir, 'history'), { recursive: true });
    } catch (error) {
      console.error('❌ Erreur création répertoire player-learning:', error);
    }
  }

  private profilePath(clientId: string, slotId: number) {
    return path.join(this.dataDir, 'profiles', `${clientId}_slot_${slotId}.json`);
  }

  private historyPath(clientId: string, slotId: number) {
    return path.join(this.dataDir, 'history', `${clientId}_slot_${slotId}.json`);
  }

  async upload(payload: PlayerLearningUploadPayload): Promise<void> {
    const { clientId, slotId } = payload;

    const snapshot: PlayerProfileSnapshot = {
      clientId,
      slotId,
      profileId: payload.profile.profileId,
      createdAt: payload.profile.createdAt,
      lastUpdatedAt: payload.profile.lastUpdatedAt,
      gamesAnalyzed: payload.profile.gamesAnalyzed,
      learnedParameters: payload.profile.learnedParameters,
      updatedAt: new Date().toISOString(),
    };

    await fs.writeFile(this.profilePath(clientId, slotId), JSON.stringify(snapshot, null, 2));

    if (payload.history && Array.isArray(payload.history)) {
      const trimmed = payload.history.slice(0, 25);
      await fs.writeFile(
        this.historyPath(clientId, slotId),
        JSON.stringify(trimmed, null, 2)
      );
    }
  }

  async getProfile(clientId: string, slotId: number): Promise<PlayerProfileSnapshot | null> {
    try {
      const raw = await fs.readFile(this.profilePath(clientId, slotId), 'utf-8');
      return JSON.parse(raw);
    } catch {
      return null;
    }
  }

  async getHistory(clientId: string, slotId: number): Promise<PlayerGameRecordSnapshot[]> {
    try {
      const raw = await fs.readFile(this.historyPath(clientId, slotId), 'utf-8');
      const arr = JSON.parse(raw);
      if (!Array.isArray(arr)) return [];
      return arr;
    } catch {
      return [];
    }
  }
}
