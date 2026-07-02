import { describe, it, before, after } from 'node:test';
import assert from 'node:assert';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { AdaptiveDifficultyService } from '../services/AdaptiveDifficultyService';

describe('AdaptiveDifficultyService', () => {
  let service: AdaptiveDifficultyService;
  let dataDir: string;

  before(() => {
    dataDir = mkdtempSync(path.join(tmpdir(), 'dutch-adaptive-test-'));
    service = new AdaptiveDifficultyService(dataDir);
  });

  after(() => {
    rmSync(dataDir, { recursive: true, force: true });
  });

  describe('constructor and basic getters', () => {
    it('constructs without error', () => {
      assert.ok(service);
    });

    it('getPlayerStats returns undefined for unknown player', () => {
      const stats = service.getPlayerStats('nonexistent-player');
      assert.strictEqual(stats, undefined);
    });

    it('getAllPlayers returns an array', () => {
      const players = service.getAllPlayers();
      assert.ok(Array.isArray(players));
    });
  });

  describe('analyzePlayer', () => {
    it('throws when games array is empty', async () => {
      await assert.rejects(
        () => service.analyzePlayer('player1', []),
        { message: 'Aucune partie à analyser' }
      );
    });

    it('analyzes a beginner player (low win rate, high score, slow decisions)', async () => {
      const games = [
        { finalRank: 3, finalScore: 25, avgDecisionTime: 4000, playerName: 'Beginner' },
        { finalRank: 4, finalScore: 20, avgDecisionTime: 3500, playerName: 'Beginner' },
        { finalRank: 2, finalScore: 18, avgDecisionTime: 3200, playerName: 'Beginner' },
        { finalRank: 3, finalScore: 22, avgDecisionTime: 4500, playerName: 'Beginner' },
        { finalRank: 4, finalScore: 19, avgDecisionTime: 3800, playerName: 'Beginner' },
      ];
      const stats = await service.analyzePlayer('beginner-player', games);
      assert.strictEqual(stats.playerId, 'beginner-player');
      assert.strictEqual(stats.playerName, 'Beginner');
      assert.strictEqual(stats.totalGames, 5);
      assert.strictEqual(stats.wins, 0);
      assert.strictEqual(stats.losses, 5);
      assert.strictEqual(stats.skillLevel, 'beginner');
      assert.strictEqual(typeof stats.estimatedMMR, 'number');
      assert.ok(stats.lastUpdated);
    });

    it('analyzes an intermediate player', async () => {
      const games = [
        { finalRank: 1, finalScore: 14, avgDecisionTime: 2000, playerName: 'Inter' },
        { finalRank: 2, finalScore: 13, avgDecisionTime: 1800, playerName: 'Inter' },
        { finalRank: 3, finalScore: 15, avgDecisionTime: 2200, playerName: 'Inter' },
        { finalRank: 3, finalScore: 16, avgDecisionTime: 2100, playerName: 'Inter' },
        { finalRank: 4, finalScore: 14, avgDecisionTime: 1900, playerName: 'Inter' },
      ];
      const stats = await service.analyzePlayer('inter-player', games);
      assert.strictEqual(stats.skillLevel, 'intermediate');
    });

    it('analyzes an advanced player', async () => {
      const games = [
        { finalRank: 1, finalScore: 8, avgDecisionTime: 1200, playerName: 'Advanced' },
        { finalRank: 1, finalScore: 6, avgDecisionTime: 1100, playerName: 'Advanced' },
        { finalRank: 2, finalScore: 10, avgDecisionTime: 1300, playerName: 'Advanced' },
        { finalRank: 1, finalScore: 7, avgDecisionTime: 1000, playerName: 'Advanced' },
        { finalRank: 3, finalScore: 11, avgDecisionTime: 1500, playerName: 'Advanced' },
        { finalRank: 2, finalScore: 9, avgDecisionTime: 1100, playerName: 'Advanced' },
        { finalRank: 3, finalScore: 10, avgDecisionTime: 1200, playerName: 'Advanced' },
        { finalRank: 2, finalScore: 11, avgDecisionTime: 1300, playerName: 'Advanced' },
        { finalRank: 1, finalScore: 5, avgDecisionTime: 900, playerName: 'Advanced' },
        { finalRank: 2, finalScore: 9, avgDecisionTime: 1100, playerName: 'Advanced' },
      ];
      const stats = await service.analyzePlayer('advanced-player', games);
      assert.strictEqual(stats.skillLevel, 'advanced');
    });

    it('analyzes an expert player', async () => {
      const games = [
        { finalRank: 1, finalScore: 3, avgDecisionTime: 800, playerName: 'Expert' },
        { finalRank: 1, finalScore: 5, avgDecisionTime: 700, playerName: 'Expert' },
        { finalRank: 1, finalScore: 4, avgDecisionTime: 900, playerName: 'Expert' },
        { finalRank: 1, finalScore: 6, avgDecisionTime: 750, playerName: 'Expert' },
        { finalRank: 2, finalScore: 8, avgDecisionTime: 1000, playerName: 'Expert' },
      ];
      const stats = await service.analyzePlayer('expert-player', games);
      assert.strictEqual(stats.skillLevel, 'expert');
    });

    it('stores player stats after analysis', async () => {
      const games = [
        { finalRank: 1, finalScore: 10, avgDecisionTime: 1500, playerName: 'Stored' },
      ];
      await service.analyzePlayer('stored-player', games);
      const stats = service.getPlayerStats('stored-player');
      assert.ok(stats);
      assert.strictEqual(stats.playerId, 'stored-player');
    });

    it('uses default avgDecisionTime when not provided', async () => {
      const games = [
        { finalRank: 1, finalScore: 10, playerName: 'NoTime' },
        { finalRank: 2, finalScore: 12, playerName: 'NoTime' },
      ];
      const stats = await service.analyzePlayer('notime-player', games);
      assert.strictEqual(typeof stats.avgDecisionTime, 'number');
      assert.strictEqual(stats.avgDecisionTime, 1500); // default
    });

    it('uses default playerName when not provided', async () => {
      const games = [
        { finalRank: 1, finalScore: 10, avgDecisionTime: 1000 },
      ];
      const stats = await service.analyzePlayer('noname-player', games);
      assert.strictEqual(stats.playerName, 'Joueur');
    });

    it('getAllPlayers returns analyzed players', async () => {
      const games = [{ finalRank: 1, finalScore: 10, avgDecisionTime: 1000, playerName: 'Test' }];
      await service.analyzePlayer('list-test-player', games);
      const players = service.getAllPlayers();
      assert.ok(players.length > 0);
      const found = players.find(p => p.playerId === 'list-test-player');
      assert.ok(found);
    });
  });

  describe('adjustBotDifficulty', () => {
    it('returns base MMR when no player stats', async () => {
      const result = await service.adjustBotDifficulty(1000, 'unknown-player', 'bronze');
      assert.strictEqual(result.baseMMR, 1000);
      assert.strictEqual(result.adjustedMMR, 1000);
      assert.strictEqual(result.adjustmentFactor, 1);
      assert.ok(result.reason.includes('Aucune statistique'));
      assert.strictEqual(result.botId, 'unknown');
      assert.strictEqual(result.targetPlayerId, 'unknown-player');
      assert.ok(result.timestamp);
    });

    it('adjusts bronze for beginner', async () => {
      // Ensure beginner player exists
      const games = Array.from({ length: 10 }, () => ({
        finalRank: 4, finalScore: 25, avgDecisionTime: 4000, playerName: 'B',
      }));
      await service.analyzePlayer('bronze-beginner', games);
      const result = await service.adjustBotDifficulty(1000, 'bronze-beginner', 'bronze');
      assert.strictEqual(result.adjustmentFactor, 0.7);
      assert.strictEqual(result.adjustedMMR, 700);
      assert.ok(result.reason.includes('Débutant'));
    });

    it('adjusts bronze for intermediate', async () => {
      const games = [
        { finalRank: 1, finalScore: 14, avgDecisionTime: 2000, playerName: 'I' },
        { finalRank: 2, finalScore: 13, avgDecisionTime: 1800, playerName: 'I' },
        { finalRank: 3, finalScore: 15, avgDecisionTime: 2200, playerName: 'I' },
        { finalRank: 3, finalScore: 16, avgDecisionTime: 2100, playerName: 'I' },
        { finalRank: 4, finalScore: 14, avgDecisionTime: 1900, playerName: 'I' },
      ];
      await service.analyzePlayer('bronze-inter', games);
      const result = await service.adjustBotDifficulty(1000, 'bronze-inter', 'bronze');
      assert.strictEqual(result.adjustmentFactor, 0.85);
    });

    it('adjusts bronze for advanced/expert player', async () => {
      const games = Array.from({ length: 10 }, (_, i) => ({
        finalRank: i < 7 ? 1 : 2, finalScore: 5, avgDecisionTime: 800, playerName: 'A',
      }));
      await service.analyzePlayer('bronze-adv', games);
      const result = await service.adjustBotDifficulty(1000, 'bronze-adv', 'bronze');
      assert.strictEqual(result.adjustmentFactor, 0.95);
    });

    it('adjusts silver for beginner', async () => {
      const games = Array.from({ length: 10 }, () => ({
        finalRank: 4, finalScore: 25, avgDecisionTime: 4000, playerName: 'B',
      }));
      await service.analyzePlayer('silver-beginner', games);
      const result = await service.adjustBotDifficulty(1000, 'silver-beginner', 'silver');
      assert.strictEqual(result.adjustmentFactor, 0.8);
    });

    it('adjusts silver for intermediate', async () => {
      const games = [
        { finalRank: 1, finalScore: 14, avgDecisionTime: 2000, playerName: 'I' },
        { finalRank: 2, finalScore: 13, avgDecisionTime: 1800, playerName: 'I' },
        { finalRank: 3, finalScore: 15, avgDecisionTime: 2200, playerName: 'I' },
        { finalRank: 3, finalScore: 16, avgDecisionTime: 2100, playerName: 'I' },
        { finalRank: 4, finalScore: 14, avgDecisionTime: 1900, playerName: 'I' },
      ];
      await service.analyzePlayer('silver-inter', games);
      const result = await service.adjustBotDifficulty(1000, 'silver-inter', 'silver');
      assert.strictEqual(result.adjustmentFactor, 0.95);
    });

    it('adjusts silver for advanced/expert', async () => {
      const games = Array.from({ length: 10 }, (_, i) => ({
        finalRank: i < 7 ? 1 : 2, finalScore: 5, avgDecisionTime: 800, playerName: 'A',
      }));
      await service.analyzePlayer('silver-adv', games);
      const result = await service.adjustBotDifficulty(1000, 'silver-adv', 'silver');
      assert.strictEqual(result.adjustmentFactor, 1);
    });

    // Fusion gold+platinum → difficile : un seul palier fort (valeurs platinum).
    it('adjusts difficile for beginner/intermediate', async () => {
      const games = Array.from({ length: 10 }, () => ({
        finalRank: 4, finalScore: 25, avgDecisionTime: 4000, playerName: 'B',
      }));
      await service.analyzePlayer('diff-beginner', games);
      const result = await service.adjustBotDifficulty(1000, 'diff-beginner', 'difficile');
      assert.strictEqual(result.adjustmentFactor, 1.4);
    });

    it('adjusts difficile for advanced', async () => {
      const games = Array.from({ length: 10 }, (_, i) => ({
        finalRank: i < 5 ? 1 : 2, finalScore: 8, avgDecisionTime: 1200, playerName: 'A',
      }));
      await service.analyzePlayer('diff-adv', games);
      const result = await service.adjustBotDifficulty(1000, 'diff-adv', 'difficile');
      assert.strictEqual(result.adjustmentFactor, 1.5);
    });

    it('adjusts difficile for expert', async () => {
      const games = Array.from({ length: 5 }, () => ({
        finalRank: 1, finalScore: 3, avgDecisionTime: 800, playerName: 'E',
      }));
      await service.analyzePlayer('diff-expert', games);
      const result = await service.adjustBotDifficulty(1000, 'diff-expert', 'difficile');
      assert.strictEqual(result.adjustmentFactor, 1.6);
    });

    it('works for all skill levels with each target', async () => {
      for (const level of ['bronze', 'silver', 'difficile'] as const) {
        const result = await service.adjustBotDifficulty(800, 'no-stats-player', level);
        assert.strictEqual(result.baseMMR, 800);
        assert.strictEqual(typeof result.adjustedMMR, 'number');
      }
    });
  });

  describe('recommendDifficulty', () => {
    it('returns bronze for unknown player', () => {
      const diff = service.recommendDifficulty('totally-unknown');
      assert.strictEqual(diff, 'bronze');
    });

    it('returns bronze for player with low win rate (<30%)', async () => {
      const games = Array.from({ length: 10 }, (_, i) => ({
        finalRank: i < 2 ? 1 : 3, finalScore: 20, avgDecisionTime: 3500, playerName: 'Low',
      }));
      await service.analyzePlayer('low-wr-player', games);
      const diff = service.recommendDifficulty('low-wr-player');
      assert.strictEqual(diff, 'bronze');
    });

    it('returns silver for player with balanced win rate (30-60%)', async () => {
      const games = Array.from({ length: 10 }, (_, i) => ({
        finalRank: i < 4 ? 1 : 2, finalScore: 12, avgDecisionTime: 1500, playerName: 'Mid',
      }));
      await service.analyzePlayer('mid-wr-player', games);
      const diff = service.recommendDifficulty('mid-wr-player');
      assert.strictEqual(diff, 'silver');
    });

    it('returns silver for advanced player with 50% win rate', async () => {
      const games = Array.from({ length: 10 }, (_, i) => ({
        finalRank: i < 5 ? 1 : 2, finalScore: 8, avgDecisionTime: 1200, playerName: 'HighWR',
      }));
      await service.analyzePlayer('high-wr-adv', games);
      const diff = service.recommendDifficulty('high-wr-adv');
      assert.strictEqual(diff, 'silver');
    });

    it('returns silver for expert with exactly 60% win rate (boundary)', async () => {
      // winRate = 0.6 is NOT > 0.6, so it falls through to the silver branch
      const games = Array.from({ length: 10 }, (_, i) => ({
        finalRank: i < 6 ? 1 : 2, finalScore: 3, avgDecisionTime: 800, playerName: 'Boundary',
      }));
      await service.analyzePlayer('boundary-expert', games);
      const diff = service.recommendDifficulty('boundary-expert');
      assert.strictEqual(diff, 'silver');
    });

    it('returns platinum for expert player with high win rate (>60%)', async () => {
      const games = Array.from({ length: 5 }, () => ({
        finalRank: 1, finalScore: 3, avgDecisionTime: 800, playerName: 'TopExpert',
      }));
      await service.analyzePlayer('top-expert', games);
      const diff = service.recommendDifficulty('top-expert');
      assert.strictEqual(diff, 'platinum');
    });
  });
});
