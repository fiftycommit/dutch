import { describe, it, before } from 'node:test';
import assert from 'node:assert';
import { LeaderboardService } from '../services/LeaderboardService';

describe('LeaderboardService', () => {
  let service: LeaderboardService;

  before(async () => {
    service = new LeaderboardService();
    await service.reset();
  });

  it('constructs without error', () => {
    assert.ok(service);
  });

  describe('getStats', () => {
    it('returns stats object with correct types', () => {
      const stats = service.getStats();
      assert.strictEqual(typeof stats.totalBots, 'number');
      assert.strictEqual(typeof stats.avgMMR, 'number');
      assert.strictEqual(typeof stats.lastUpdated, 'string');
    });

    it('returns zero stats when leaderboard is empty', () => {
      const stats = service.getStats();
      assert.strictEqual(stats.totalBots, 0);
      assert.strictEqual(stats.avgMMR, 0);
      assert.strictEqual(stats.highestMMR, 0);
      assert.strictEqual(stats.lowestMMR, 0);
      assert.strictEqual(stats.totalGames, 0);
    });
  });

  describe('getTopBots', () => {
    it('returns empty array when no bots', () => {
      const top = service.getTopBots();
      assert.ok(Array.isArray(top));
      assert.strictEqual(top.length, 0);
    });

    it('returns empty array with custom limit when no bots', () => {
      const top = service.getTopBots(5);
      assert.ok(Array.isArray(top));
      assert.strictEqual(top.length, 0);
    });
  });

  describe('getFullLeaderboard', () => {
    it('returns empty array when no bots', () => {
      const full = service.getFullLeaderboard();
      assert.ok(Array.isArray(full));
      assert.strictEqual(full.length, 0);
    });
  });

  describe('getBySkillLevel', () => {
    it('returns empty array for non-existent skill level', () => {
      const result = service.getBySkillLevel('nonexistent');
      assert.ok(Array.isArray(result));
      assert.strictEqual(result.length, 0);
    });
  });

  describe('getByPersonality', () => {
    it('returns empty array for non-existent personality', () => {
      const result = service.getByPersonality('nonexistent');
      assert.ok(Array.isArray(result));
      assert.strictEqual(result.length, 0);
    });
  });

  describe('findBot', () => {
    it('returns undefined for non-existent bot', () => {
      const result = service.findBot('nonexistent-bot');
      assert.strictEqual(result, undefined);
    });
  });

  describe('getBotRank', () => {
    it('returns null for non-existent bot', () => {
      const result = service.getBotRank('nonexistent-bot');
      assert.strictEqual(result, null);
    });
  });

  describe('getRisingStars', () => {
    it('returns empty array when no bots', () => {
      const result = service.getRisingStars();
      assert.ok(Array.isArray(result));
      assert.strictEqual(result.length, 0);
    });

    it('accepts custom limit', () => {
      const result = service.getRisingStars(3);
      assert.ok(Array.isArray(result));
    });
  });

  describe('getGenerationStats', () => {
    it('returns empty array when no bots', () => {
      const result = service.getGenerationStats();
      assert.ok(Array.isArray(result));
      assert.strictEqual(result.length, 0);
    });
  });

  describe('updateLeaderboard', () => {
    before(async () => {
      await service.reset();
    });

    it('adds a new bot to the leaderboard', async () => {
      await service.updateLeaderboard({
        botId: 'bot-1',
        botName: 'TestBot1',
        mmr: 800,
        wins: 5,
        losses: 3,
        totalGames: 8,
        avgScore: 42,
        skillLevel: 'gold',
        lastPlayed: new Date().toISOString(),
      });

      const full = service.getFullLeaderboard();
      assert.strictEqual(full.length, 1);
      assert.strictEqual(full[0].botId, 'bot-1');
      assert.strictEqual(full[0].rank, 1);
      assert.strictEqual(full[0].winRate, 5 / 8);
    });

    it('updates an existing bot', async () => {
      await service.updateLeaderboard({
        botId: 'bot-1',
        botName: 'TestBot1',
        mmr: 900,
        wins: 10,
        losses: 3,
        totalGames: 13,
        avgScore: 38,
        skillLevel: 'gold',
        lastPlayed: new Date().toISOString(),
      });

      const full = service.getFullLeaderboard();
      assert.strictEqual(full.length, 1);
      assert.strictEqual(full[0].mmr, 900);
      assert.strictEqual(full[0].wins, 10);
    });

    it('sorts bots by MMR descending and assigns correct ranks', async () => {
      await service.updateLeaderboard({
        botId: 'bot-2',
        botName: 'TestBot2',
        mmr: 1000,
        wins: 20,
        losses: 2,
        totalGames: 22,
        avgScore: 30,
        skillLevel: 'platinum',
        lastPlayed: new Date().toISOString(),
      });

      await service.updateLeaderboard({
        botId: 'bot-3',
        botName: 'TestBot3',
        mmr: 600,
        wins: 3,
        losses: 7,
        totalGames: 10,
        avgScore: 55,
        skillLevel: 'silver',
        lastPlayed: new Date().toISOString(),
      });

      const full = service.getFullLeaderboard();
      assert.strictEqual(full.length, 3);
      assert.strictEqual(full[0].botId, 'bot-2');
      assert.strictEqual(full[0].rank, 1);
      assert.strictEqual(full[1].botId, 'bot-1');
      assert.strictEqual(full[1].rank, 2);
      assert.strictEqual(full[2].botId, 'bot-3');
      assert.strictEqual(full[2].rank, 3);
    });

    it('calculates winRate correctly including zero totalGames', async () => {
      await service.updateLeaderboard({
        botId: 'bot-zero',
        botName: 'ZeroBot',
        mmr: 100,
        wins: 0,
        losses: 0,
        totalGames: 0,
        avgScore: 0,
        skillLevel: 'bronze',
        lastPlayed: new Date().toISOString(),
      });

      const bot = service.findBot('bot-zero');
      assert.ok(bot);
      assert.strictEqual(bot.winRate, 0);
    });
  });

  describe('after populating bots', () => {
    it('getStats returns correct aggregate stats', () => {
      const stats = service.getStats();
      assert.ok(stats.totalBots > 0);
      assert.ok(stats.avgMMR > 0);
      assert.ok(stats.highestMMR >= stats.lowestMMR);
      assert.ok(stats.totalGames > 0);
    });

    it('getTopBots respects the limit', () => {
      const top2 = service.getTopBots(2);
      assert.strictEqual(top2.length, 2);
      assert.ok(top2[0].mmr >= top2[1].mmr);
    });

    it('getBySkillLevel filters correctly', () => {
      const goldBots = service.getBySkillLevel('gold');
      for (const bot of goldBots) {
        assert.strictEqual(bot.skillLevel, 'gold');
      }
    });

    it('getBySkillLevel respects limit', () => {
      const result = service.getBySkillLevel('gold', 1);
      assert.ok(result.length <= 1);
    });

    it('getByPersonality filters correctly', async () => {
      await service.updateLeaderboard({
        botId: 'bot-personality',
        botName: 'PersonalityBot',
        mmr: 750,
        wins: 5,
        losses: 5,
        totalGames: 10,
        avgScore: 40,
        skillLevel: 'gold',
        personality: 'aggressive',
        lastPlayed: new Date().toISOString(),
      });

      const result = service.getByPersonality('aggressive');
      assert.ok(result.length >= 1);
      for (const bot of result) {
        assert.strictEqual(bot.personality, 'aggressive');
      }
    });

    it('getByPersonality respects limit', () => {
      const result = service.getByPersonality('aggressive', 1);
      assert.ok(result.length <= 1);
    });

    it('findBot returns the correct bot', () => {
      const bot = service.findBot('bot-2');
      assert.ok(bot);
      assert.strictEqual(bot.botId, 'bot-2');
      assert.strictEqual(bot.botName, 'TestBot2');
    });

    it('getBotRank returns correct rank', () => {
      const rank = service.getBotRank('bot-2');
      assert.strictEqual(rank, 1);
    });

    it('getRisingStars returns bots sorted by winRate', () => {
      const stars = service.getRisingStars(3);
      assert.ok(stars.length <= 3);
      for (let i = 1; i < stars.length; i++) {
        assert.ok(stars[i - 1].winRate >= stars[i].winRate);
      }
    });

    it('getGenerationStats groups by generation', async () => {
      await service.updateLeaderboard({
        botId: 'gen-bot-1',
        botName: 'GenBot1',
        mmr: 700,
        wins: 4,
        losses: 6,
        totalGames: 10,
        avgScore: 45,
        skillLevel: 'silver',
        generation: 1,
        lastPlayed: new Date().toISOString(),
      });

      await service.updateLeaderboard({
        botId: 'gen-bot-2',
        botName: 'GenBot2',
        mmr: 850,
        wins: 7,
        losses: 3,
        totalGames: 10,
        avgScore: 35,
        skillLevel: 'gold',
        generation: 1,
        lastPlayed: new Date().toISOString(),
      });

      await service.updateLeaderboard({
        botId: 'gen-bot-3',
        botName: 'GenBot3',
        mmr: 950,
        wins: 9,
        losses: 1,
        totalGames: 10,
        avgScore: 28,
        skillLevel: 'platinum',
        generation: 2,
        lastPlayed: new Date().toISOString(),
      });

      const genStats = service.getGenerationStats();
      assert.ok(genStats.length >= 2);

      // Sorted by generation descending
      for (let i = 1; i < genStats.length; i++) {
        assert.ok(genStats[i - 1].generation > genStats[i].generation);
      }

      const gen1 = genStats.find(g => g.generation === 1);
      assert.ok(gen1);
      assert.strictEqual(gen1.count, 2);
      assert.strictEqual(gen1.avgMMR, (700 + 850) / 2);

      const gen2 = genStats.find(g => g.generation === 2);
      assert.ok(gen2);
      assert.strictEqual(gen2.count, 1);
      assert.strictEqual(gen2.avgMMR, 950);
    });

    it('getFullLeaderboard returns a copy', () => {
      const full1 = service.getFullLeaderboard();
      const full2 = service.getFullLeaderboard();
      assert.notStrictEqual(full1, full2);
      assert.deepStrictEqual(full1, full2);
    });
  });

  describe('reset', () => {
    it('clears the leaderboard', async () => {
      await service.reset();
      const full = service.getFullLeaderboard();
      assert.strictEqual(full.length, 0);
      const stats = service.getStats();
      assert.strictEqual(stats.totalBots, 0);
    });
  });
});
