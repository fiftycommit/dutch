import { describe, it, before } from 'node:test';
import assert from 'node:assert';
import { SBMMService } from '../services/SBMMService';

describe('SBMMService', () => {
  let service: SBMMService;
  const testPlayerId = 'test-sbmm-' + Date.now();

  before(() => {
    service = new SBMMService();
  });

  it('constructs without error', () => {
    assert.ok(service);
  });

  describe('mmrToCursor', () => {
    it('returns values between 0 and 1', () => {
      assert.ok(service.mmrToCursor(0) > 0);
      assert.ok(service.mmrToCursor(0) < 0.5);
      assert.ok(service.mmrToCursor(1200) > 0.9);
      assert.ok(service.mmrToCursor(1200) < 1);
    });

    it('returns ~0.5 for MMR 600 (sigmoid center)', () => {
      assert.ok(Math.abs(service.mmrToCursor(600) - 0.5) < 0.01);
    });

    it('is monotonically increasing', () => {
      const values = [0, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 1200, 1500];
      for (let i = 1; i < values.length; i++) {
        assert.ok(
          service.mmrToCursor(values[i]) > service.mmrToCursor(values[i - 1]),
          `mmrToCursor(${values[i]}) should be > mmrToCursor(${values[i - 1]})`
        );
      }
    });

    it('handles extreme MMR values', () => {
      const veryLow = service.mmrToCursor(-1000);
      assert.ok(veryLow > 0);
      assert.ok(veryLow < 0.1);

      const veryHigh = service.mmrToCursor(5000);
      assert.ok(veryHigh > 0.99);
      assert.ok(veryHigh <= 1);
    });
  });

  describe('getProfile', () => {
    it('returns default profile for new player', () => {
      const profile = service.getProfile(testPlayerId);
      assert.strictEqual(profile.mmr, 500);
      assert.strictEqual(profile.gamesPlayed, 0);
      assert.strictEqual(profile.wins, 0);
      assert.strictEqual(profile.winRate, 0);
      assert.strictEqual(profile.playerId, testPlayerId);
      assert.ok(Array.isArray(profile.recentResults));
      assert.strictEqual(profile.recentResults.length, 0);
      assert.strictEqual(profile.cursor, service.mmrToCursor(500));
    });

    it('returns the same default values for different new players', () => {
      const p1 = service.getProfile('new-player-a-' + Date.now());
      const p2 = service.getProfile('new-player-b-' + Date.now());
      assert.strictEqual(p1.mmr, p2.mmr);
      assert.strictEqual(p1.gamesPlayed, p2.gamesPlayed);
      assert.strictEqual(p1.cursor, p2.cursor);
    });
  });

  describe('getBotMix', () => {
    it('returns correct number of bot levels', () => {
      const mix = service.getBotMix(testPlayerId, 3);
      assert.strictEqual(mix.botLevels.length, 3);
    });

    it('returns valid bot levels', () => {
      const validLevels = ['bronze', 'silver', 'gold', 'platinum'];
      const mix = service.getBotMix(testPlayerId, 4);
      for (const level of mix.botLevels) {
        assert.ok(validLevels.includes(level), `Level ${level} should be valid`);
      }
    });

    it('returns levels sorted from weakest to strongest', () => {
      const order: Record<string, number> = { bronze: 0, silver: 1, gold: 2, platinum: 3 };
      const mix = service.getBotMix(testPlayerId, 4);
      for (let i = 1; i < mix.botLevels.length; i++) {
        assert.ok(
          (order[mix.botLevels[i]] ?? 0) >= (order[mix.botLevels[i - 1]] ?? 0),
          `Levels should be sorted: ${mix.botLevels.join(', ')}`
        );
      }
    });

    it('returns cursor and mmr in the result', () => {
      const mix = service.getBotMix(testPlayerId, 2);
      assert.strictEqual(typeof mix.cursor, 'number');
      assert.strictEqual(typeof mix.mmr, 'number');
    });

    it('handles single bot request (no spread)', () => {
      const mix = service.getBotMix(testPlayerId, 1);
      assert.strictEqual(mix.botLevels.length, 1);
      const validLevels = ['bronze', 'silver', 'gold', 'platinum'];
      assert.ok(validLevels.includes(mix.botLevels[0]));
    });

    it('handles zero bots', () => {
      const mix = service.getBotMix(testPlayerId, 0);
      assert.strictEqual(mix.botLevels.length, 0);
    });
  });

  describe('getBotStats', () => {
    it('returns stats object with all levels', () => {
      const stats = service.getBotStats();
      assert.ok(stats);
      assert.ok('bronze' in stats);
      assert.ok('silver' in stats);
      assert.ok('gold' in stats);
      assert.ok('platinum' in stats);
    });

    it('each level has correct default structure', () => {
      const stats = service.getBotStats();
      for (const level of ['bronze', 'silver', 'gold', 'platinum'] as const) {
        const s = stats[level];
        assert.strictEqual(typeof s.gamesPlayed, 'number');
        assert.strictEqual(typeof s.winsVsHumans, 'number');
        assert.strictEqual(typeof s.winRateVsHumans, 'number');
        assert.strictEqual(typeof s.totalScore, 'number');
        assert.strictEqual(typeof s.avgScore, 'number');
        assert.strictEqual(typeof s.totalRank, 'number');
        assert.strictEqual(typeof s.avgRank, 'number');
        assert.strictEqual(typeof s.dutchCallCount, 'number');
        assert.strictEqual(typeof s.dutchSuccessCount, 'number');
        assert.strictEqual(typeof s.dutchSuccessRate, 'number');
      }
    });
  });

  describe('recordGame', () => {
    const recordPlayerId = 'test-record-' + Date.now();

    it('records a game and updates MMR', () => {
      const result = service.recordGame(
        recordPlayerId,
        'game-1',
        1,    // rank (winner)
        15,   // score
        [
          { level: 'bronze', rank: 2, score: 30, dutchCalled: false, dutchWon: false },
          { level: 'silver', rank: 3, score: 45, dutchCalled: false, dutchWon: false },
        ],
        3,     // totalPlayers
        false, // dutchCalled
        false  // dutchWon
      );

      assert.strictEqual(typeof result.newMMR, 'number');
      assert.strictEqual(typeof result.newCursor, 'number');
      assert.ok(result.newMMR > 0);
    });

    it('winning increases MMR from default', () => {
      const playerId = 'test-winner-' + Date.now();
      const result = service.recordGame(
        playerId,
        'game-win',
        1,
        10,
        [
          { level: 'bronze', rank: 2, score: 30, dutchCalled: false, dutchWon: false },
          { level: 'bronze', rank: 3, score: 50, dutchCalled: false, dutchWon: false },
        ],
        3,
        false,
        false
      );
      assert.ok(result.newMMR > 500, `Expected MMR > 500, got ${result.newMMR}`);
    });

    it('losing decreases MMR from default', () => {
      const playerId = 'test-loser-' + Date.now();
      const result = service.recordGame(
        playerId,
        'game-lose',
        3,  // last place
        80,
        [
          { level: 'bronze', rank: 1, score: 10, dutchCalled: false, dutchWon: false },
          { level: 'bronze', rank: 2, score: 20, dutchCalled: false, dutchWon: false },
        ],
        3,
        false,
        false
      );
      assert.ok(result.newMMR < 500, `Expected MMR < 500, got ${result.newMMR}`);
    });

    it('dutch won gives MMR bonus', () => {
      const playerNoDutch = 'test-no-dutch-' + Date.now();
      const playerDutch = 'test-dutch-' + Date.now();
      const bots = [
        { level: 'silver', rank: 2, score: 30, dutchCalled: false, dutchWon: false },
      ];

      const resultNoDutch = service.recordGame(playerNoDutch, 'g1', 1, 10, bots, 2, false, false);
      const resultDutch = service.recordGame(playerDutch, 'g2', 1, 10, bots, 2, true, true);

      assert.ok(
        resultDutch.newMMR > resultNoDutch.newMMR,
        `Dutch bonus: ${resultDutch.newMMR} should be > ${resultNoDutch.newMMR}`
      );
    });

    it('dutch called but lost gives MMR penalty', () => {
      const playerNoDutch = 'test-nodutch2-' + Date.now();
      const playerDutchFail = 'test-dutchfail-' + Date.now();
      const bots = [
        { level: 'silver', rank: 1, score: 10, dutchCalled: false, dutchWon: false },
      ];

      const resultNoDutch = service.recordGame(playerNoDutch, 'g3', 2, 50, bots, 2, false, false);
      const resultDutchFail = service.recordGame(playerDutchFail, 'g4', 2, 50, bots, 2, true, false);

      assert.ok(
        resultDutchFail.newMMR < resultNoDutch.newMMR,
        `Dutch penalty: ${resultDutchFail.newMMR} should be < ${resultNoDutch.newMMR}`
      );
    });

    it('updates profile gamesPlayed and wins after recording', () => {
      const playerId = 'test-profile-update-' + Date.now();
      service.recordGame(playerId, 'g-a', 1, 10, [
        { level: 'bronze', rank: 2, score: 30, dutchCalled: false, dutchWon: false },
      ], 2, false, false);

      const profile = service.getProfile(playerId);
      assert.strictEqual(profile.gamesPlayed, 1);
      assert.strictEqual(profile.wins, 1);
      assert.strictEqual(profile.winRate, 1);
    });

    it('non-win does not increment wins', () => {
      const playerId = 'test-no-win-' + Date.now();
      service.recordGame(playerId, 'g-b', 2, 40, [
        { level: 'bronze', rank: 1, score: 10, dutchCalled: false, dutchWon: false },
      ], 2, false, false);

      const profile = service.getProfile(playerId);
      assert.strictEqual(profile.gamesPlayed, 1);
      assert.strictEqual(profile.wins, 0);
      assert.strictEqual(profile.winRate, 0);
    });

    it('keeps only last 20 recent results', () => {
      const playerId = 'test-history-limit-' + Date.now();
      for (let i = 0; i < 25; i++) {
        service.recordGame(playerId, `g-${i}`, 1, 10, [
          { level: 'bronze', rank: 2, score: 30, dutchCalled: false, dutchWon: false },
        ], 2, false, false);
      }

      const profile = service.getProfile(playerId);
      assert.ok(profile.recentResults.length <= 20, `Expected <= 20 results, got ${profile.recentResults.length}`);
    });

    it('MMR is clamped to 0-1500 range', () => {
      // Test lower bound
      const lowPlayer = 'test-low-mmr-' + Date.now();
      for (let i = 0; i < 50; i++) {
        service.recordGame(lowPlayer, `gl-${i}`, 4, 100, [
          { level: 'platinum', rank: 1, score: 5, dutchCalled: false, dutchWon: false },
          { level: 'platinum', rank: 2, score: 10, dutchCalled: false, dutchWon: false },
          { level: 'platinum', rank: 3, score: 15, dutchCalled: false, dutchWon: false },
        ], 4, false, false);
      }
      const lowProfile = service.getProfile(lowPlayer);
      assert.ok(lowProfile.mmr >= 0, `MMR should be >= 0, got ${lowProfile.mmr}`);
    });

    it('updates bot stats after recording a game', () => {
      const playerId = 'test-botstats-' + Date.now();
      service.recordGame(playerId, 'g-bs', 2, 40, [
        { level: 'gold', rank: 1, score: 15, dutchCalled: true, dutchWon: true },
      ], 2, false, false);

      const botStats = service.getBotStats();
      assert.ok(botStats.gold.gamesPlayed > 0);
    });

    it('bot stats track dutch calls and successes', () => {
      const playerId = 'test-botstats-dutch-' + Date.now();

      // Reset to get clean stats
      service.resetAll();

      service.recordGame(playerId, 'g-bd1', 2, 40, [
        { level: 'silver', rank: 1, score: 15, dutchCalled: true, dutchWon: true },
      ], 2, false, false);

      const stats = service.getBotStats();
      assert.strictEqual(stats.silver.dutchCallCount, 1);
      assert.strictEqual(stats.silver.dutchSuccessCount, 1);
      assert.strictEqual(stats.silver.dutchSuccessRate, 1);
    });

    it('bot stats track wins vs humans correctly', () => {
      service.resetAll();
      const playerId = 'test-botstats-wins-' + Date.now();

      service.recordGame(playerId, 'g-bw1', 2, 40, [
        { level: 'bronze', rank: 1, score: 15, dutchCalled: false, dutchWon: false },
      ], 2, false, false);

      const stats = service.getBotStats();
      assert.strictEqual(stats.bronze.winsVsHumans, 1);
      assert.ok(stats.bronze.winRateVsHumans > 0);
    });
  });

  describe('adjustCursor edge cases via recordGame', () => {
    it('cursor adjusts down when player consistently loses', () => {
      const playerId = 'test-cursor-down-' + Date.now();
      // Play enough games to trigger cursor adjustment (need >= 3 recent)
      for (let i = 0; i < 10; i++) {
        service.recordGame(playerId, `gc-${i}`, 4, 100, [
          { level: 'gold', rank: 1, score: 10, dutchCalled: false, dutchWon: false },
          { level: 'gold', rank: 2, score: 20, dutchCalled: false, dutchWon: false },
          { level: 'gold', rank: 3, score: 30, dutchCalled: false, dutchWon: false },
        ], 4, false, false);
      }

      const profile = service.getProfile(playerId);
      // With all losses, cursor should be adjusted down from base
      const baseCursor = service.mmrToCursor(profile.mmr);
      // The cursor should be <= baseCursor (either equal or reduced)
      assert.ok(profile.cursor <= baseCursor + 0.01, 'Cursor should not be above base for losing player');
    });

    it('cursor adjusts up when player consistently wins', () => {
      const playerId = 'test-cursor-up-' + Date.now();
      for (let i = 0; i < 10; i++) {
        service.recordGame(playerId, `gw-${i}`, 1, 10, [
          { level: 'bronze', rank: 2, score: 30, dutchCalled: false, dutchWon: false },
          { level: 'bronze', rank: 3, score: 50, dutchCalled: false, dutchWon: false },
        ], 3, false, false);
      }

      const profile = service.getProfile(playerId);
      const baseCursor = service.mmrToCursor(profile.mmr);
      // Winning a lot should push cursor up
      assert.ok(profile.cursor >= baseCursor - 0.01, 'Cursor should be at or above base for winning player');
    });
  });

  describe('recordGame with single player', () => {
    it('handles totalPlayers = 1 (actualScore = 0.5)', () => {
      const playerId = 'test-single-' + Date.now();
      const result = service.recordGame(playerId, 'g-solo', 1, 10, [], 1, false, false);
      assert.strictEqual(typeof result.newMMR, 'number');
    });
  });

  describe('resetAll', () => {
    it('returns deletedProfiles count', () => {
      const result = service.resetAll();
      assert.strictEqual(typeof result.deletedProfiles, 'number');
      assert.ok(result.deletedProfiles >= 0);
    });

    it('resets bot stats to defaults', () => {
      service.resetAll();
      const stats = service.getBotStats();
      for (const level of ['bronze', 'silver', 'gold', 'platinum'] as const) {
        assert.strictEqual(stats[level].gamesPlayed, 0);
        assert.strictEqual(stats[level].winsVsHumans, 0);
      }
    });
  });
});
