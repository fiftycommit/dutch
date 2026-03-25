import { describe, it } from 'node:test';
import assert from 'node:assert';
import { SBMMService } from '../services/SBMMService';

describe('SBMMService', () => {
  it('constructs without error', () => {
    const service = new SBMMService();
    assert.ok(service);
  });

  it('mmrToCursor returns values between 0 and 1', () => {
    const service = new SBMMService();
    assert.ok(service.mmrToCursor(0) > 0);
    assert.ok(service.mmrToCursor(0) < 0.5);
    assert.ok(Math.abs(service.mmrToCursor(600) - 0.5) < 0.01);
    assert.ok(service.mmrToCursor(1200) > 0.9);
    assert.ok(service.mmrToCursor(1200) < 1);
  });

  it('getProfile returns default profile for new player', () => {
    const service = new SBMMService();
    const profile = service.getProfile('test-new-player-' + Date.now());
    assert.strictEqual(profile.mmr, 500);
    assert.strictEqual(profile.gamesPlayed, 0);
    assert.strictEqual(profile.wins, 0);
    assert.strictEqual(profile.winRate, 0);
  });

  it('getBotMix returns correct number of levels', () => {
    const service = new SBMMService();
    const mix = service.getBotMix('test-player-' + Date.now(), 3);
    assert.strictEqual(mix.botLevels.length, 3);
    for (const level of mix.botLevels) {
      assert.ok(['bronze', 'silver', 'gold', 'platinum'].includes(level));
    }
  });

  it('getBotStats returns stats object', () => {
    const service = new SBMMService();
    const stats = service.getBotStats();
    assert.ok(stats);
    assert.ok('bronze' in stats);
    assert.ok('silver' in stats);
    assert.ok('gold' in stats);
    assert.ok('platinum' in stats);
  });
});
