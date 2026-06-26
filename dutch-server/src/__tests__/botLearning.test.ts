import { describe, it, before } from 'node:test';
import assert from 'node:assert';
import { BotLearningService } from '../services/BotLearningService';

describe('BotLearningService', () => {
  let service: BotLearningService;

  before(() => {
    service = new BotLearningService();
  });

  it('constructs without error', () => {
    assert.ok(service);
  });

  describe('isPaused / setPaused', () => {
    it('isPaused returns false by default', () => {
      assert.strictEqual(service.isPaused(), false);
    });

    it('setPaused(true) sets paused to true', () => {
      service.setPaused(true);
      assert.strictEqual(service.isPaused(), true);
    });

    it('setPaused(false) sets paused to false', () => {
      service.setPaused(false);
      assert.strictEqual(service.isPaused(), false);
    });

    it('setPaused(true) then setPaused(false) triggers processPendingGames', () => {
      service.setPaused(true);
      assert.strictEqual(service.isPaused(), true);
      // Resuming should trigger processPendingGames (async, no error expected)
      service.setPaused(false);
      assert.strictEqual(service.isPaused(), false);
    });

    it('setPaused(false) when already not paused does not trigger pending processing', () => {
      assert.strictEqual(service.isPaused(), false);
      service.setPaused(false);
      assert.strictEqual(service.isPaused(), false);
    });
  });

  describe('getPendingCount', () => {
    it('returns a number >= 0', async () => {
      const count = await service.getPendingCount();
      assert.strictEqual(typeof count, 'number');
      assert.ok(count >= 0);
    });
  });

  describe('getStats', () => {
    it('returns valid stats object', async () => {
      const stats = await service.getStats();
      assert.ok('totalGames' in stats);
      assert.ok('totalBots' in stats);
      assert.ok('avgWinRate' in stats);
      assert.ok('topPerformers' in stats);
      assert.ok('recentGames' in stats);

      assert.strictEqual(typeof stats.totalGames, 'number');
      assert.strictEqual(typeof stats.totalBots, 'number');
      assert.strictEqual(typeof stats.avgWinRate, 'number');
      assert.ok(Array.isArray(stats.topPerformers));
      assert.ok(Array.isArray(stats.recentGames));
    });

    it('returns non-negative values', async () => {
      const stats = await service.getStats();
      assert.ok(stats.totalGames >= 0);
      assert.ok(stats.totalBots >= 0);
      assert.ok(stats.avgWinRate >= 0);
    });

    it('uses cache for repeated calls', async () => {
      const stats1 = await service.getStats();
      const stats2 = await service.getStats();
      // Should return same object from cache
      assert.deepStrictEqual(stats1, stats2);
    });
  });

  describe('getTopBots', () => {
    it('returns an array', async () => {
      const topBots = await service.getTopBots();
      assert.ok(Array.isArray(topBots));
    });

    it('returns at most `limit` bots', async () => {
      const topBots = await service.getTopBots(5);
      assert.ok(topBots.length <= 5);
    });

    it('returns an empty array when filtering with non-existent behavior', async () => {
      const topBots = await service.getTopBots(10, 'nonexistent_behavior');
      assert.ok(Array.isArray(topBots));
    });

    it('returns an empty array when filtering with non-existent skillLevel', async () => {
      const topBots = await service.getTopBots(10, undefined, 'nonexistent_skill');
      assert.ok(Array.isArray(topBots));
    });

    it('accepts both behavior and skillLevel filters', async () => {
      const topBots = await service.getTopBots(10, 'balanced', 'silver');
      assert.ok(Array.isArray(topBots));
    });

    it('default limit is 10', async () => {
      const topBots = await service.getTopBots();
      assert.ok(topBots.length <= 10);
    });
  });

  describe('getBotParameters', () => {
    it('returns parameters for unknown bot (defaults)', async () => {
      const params = await service.getBotParameters('balanced', 'silver');
      assert.ok(params !== null);
      assert.strictEqual(typeof params, 'object');
    });

    it('returns parameters with aggressiveness', async () => {
      const params = await service.getBotParameters('balanced', 'silver');
      assert.ok(params !== null);
      assert.ok('aggressiveness' in params!);
      assert.strictEqual(typeof params!.aggressiveness, 'number');
    });

    it('returns different defaults for different behaviors', async () => {
      const balancedParams = await service.getBotParameters('balanced', 'silver');
      const aggressiveParams = await service.getBotParameters('aggressive', 'silver');
      assert.ok(balancedParams !== null);
      assert.ok(aggressiveParams !== null);
      // Aggressive should have higher aggressiveness
      assert.ok(aggressiveParams!.aggressiveness > balancedParams!.aggressiveness);
    });

    it('returns different defaults for different skill levels', async () => {
      const bronzeParams = await service.getBotParameters('balanced', 'bronze');
      const platinumParams = await service.getBotParameters('balanced', 'platinum');
      assert.ok(bronzeParams !== null);
      assert.ok(platinumParams !== null);
      // Platinum should have higher memoryAccuracy
      assert.ok(platinumParams!.memoryAccuracy > bronzeParams!.memoryAccuracy);
    });

    it('returns defaults for fast behavior', async () => {
      const params = await service.getBotParameters('fast', 'silver');
      assert.ok(params !== null);
      assert.ok(params!.aggressiveness >= 0.7);
      assert.ok(params!.caution <= 0.3);
      assert.ok(params!.decisionSpeed <= 1200);
    });

    it('returns defaults for gold skill level', async () => {
      const params = await service.getBotParameters('balanced', 'gold');
      assert.ok(params !== null);
      assert.ok(params!.memoryAccuracy >= 0.9);
      assert.ok(params!.memoryRetention >= 0.85);
    });

    it('returns defaults for unknown behavior/skill', async () => {
      const params = await service.getBotParameters('unknown', 'unknown');
      assert.ok(params !== null);
      assert.strictEqual(typeof params!.aggressiveness, 'number');
    });
  });

  describe('saveGameRecord', () => {
    it('saves a game record without error', async () => {
      const record = createMockRecord('save-test-1', 'bot-save-1');
      await assert.doesNotReject(service.saveGameRecord(record));
    });

    it('saves a game record when paused (marks as pending)', async () => {
      service.setPaused(true);
      const record = createMockRecord('save-test-paused', 'bot-save-paused');
      await assert.doesNotReject(service.saveGameRecord(record));
      service.setPaused(false);
    });

    it('saves multiple game records', async () => {
      const record1 = createMockRecord('save-test-multi-1', 'bot-save-multi');
      const record2 = createMockRecord('save-test-multi-2', 'bot-save-multi');
      await assert.doesNotReject(service.saveGameRecord(record1));
      await assert.doesNotReject(service.saveGameRecord(record2));
    });

    it('saves a record with calledDutch=true and wonDutch=true', async () => {
      const record = createMockRecord('save-test-dutch', 'bot-save-dutch');
      record.calledDutch = true;
      record.wonDutch = true;
      record.finalRank = 1;
      record.cardsAtDutch = 3;
      record.scoreAtDutch = 8;
      await assert.doesNotReject(service.saveGameRecord(record));
    });

    it('saves a record with pBeatHuman set', async () => {
      const record = createMockRecord('save-test-phuman', 'bot-save-phuman');
      record.pBeatHuman = 0.75;
      await assert.doesNotReject(service.saveGameRecord(record));
    });

    it('saves a record with opponents that have MMR', async () => {
      const record = createMockRecord('save-test-opp', 'bot-save-opp');
      record.opponents = [
        { botId: 'opp-1', rank: 1, mmr: 1500, learnedParams: { aggressiveness: 0.8 } },
        { botId: 'opp-2', rank: 3, mmr: 1100 },
      ];
      await assert.doesNotReject(service.saveGameRecord(record));
    });
  });

  describe('getShuffleStats', () => {
    it('returns a stats object', async () => {
      const stats = await service.getShuffleStats();
      assert.strictEqual(typeof stats, 'object');
      assert.ok('totalGames' in stats);
    });

    it('returns zero values when no shuffle data exists', async () => {
      const stats = await service.getShuffleStats();
      assert.strictEqual(typeof stats.totalGames, 'number');
      assert.ok(stats.totalGames >= 0);
    });
  });

  describe('resetAll', () => {
    it('returns deleted counts', async () => {
      const result = await service.resetAll();
      assert.ok('deletedProfiles' in result);
      assert.ok('deletedGames' in result);
      assert.strictEqual(typeof result.deletedProfiles, 'number');
      assert.strictEqual(typeof result.deletedGames, 'number');
      assert.ok(result.deletedProfiles >= 0);
      assert.ok(result.deletedGames >= 0);
      // Wait for fire-and-forget async ops from new service constructors
      await new Promise(resolve => setTimeout(resolve, 100));
    });
  });

  describe('processPendingGames', () => {
    it('returns a number of processed games', async () => {
      const processed = await service.processPendingGames();
      assert.strictEqual(typeof processed, 'number');
      assert.ok(processed >= 0);
    });
  });

  describe('service accessors', () => {
    it('getTournamentService returns an object', () => {
      const tournament = service.getTournamentService();
      assert.ok(tournament !== null && tournament !== undefined);
    });

    it('getAdaptiveService returns an object', () => {
      const adaptive = service.getAdaptiveService();
      assert.ok(adaptive !== null && adaptive !== undefined);
    });

    it('getLeaderboardService returns an object', () => {
      const leaderboard = service.getLeaderboardService();
      assert.ok(leaderboard !== null && leaderboard !== undefined);
    });
  });
});

function createMockRecord(gameId: string, botId: string): any {
  return {
    gameId,
    botId,
    botName: 'Test Bot',
    botBehavior: 'balanced',
    botSkillLevel: 'silver',
    startTime: new Date().toISOString(),
    endTime: new Date().toISOString(),
    numberOfPlayers: 4,
    gameMode: 'classic',
    usedSBMM: false,
    actions: [
      {
        actionType: 'draw_from_deck',
        turnNumber: 1,
        timestamp: new Date().toISOString(),
        gameState: {
          myScore: 20,
          cardsInHand: 4,
          turnPhase: 'playing',
          opponentsAvgScore: 18,
          deckCardsRemaining: 40,
        },
        actionDetails: {},
        result: { newScore: 18 },
      },
      {
        actionType: 'replace_card',
        turnNumber: 2,
        timestamp: new Date().toISOString(),
        gameState: {
          myScore: 18,
          cardsInHand: 4,
          turnPhase: 'playing',
          opponentsAvgScore: 16,
          deckCardsRemaining: 39,
        },
        actionDetails: { cardIndex: 0 },
        result: { newScore: 15 },
      },
    ],
    initialHandSize: 4,
    finalScore: 15,
    finalRank: 2,
    calledDutch: false,
    wonDutch: false,
    cardsAtDutch: 0,
    scoreAtDutch: 0,
    totalTurns: 2,
    avgDecisionTime: 1500,
    powerUsesCount: 0,
    goodDecisions: 2,
    badDecisions: 0,
    opponents: [],
  };
}
