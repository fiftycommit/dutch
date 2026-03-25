import { describe, it } from 'node:test';
import assert from 'node:assert';
import { LeaderboardService } from '../services/LeaderboardService';

describe('LeaderboardService', () => {
  it('constructs without error', () => {
    const service = new LeaderboardService();
    assert.ok(service);
  });

  it('getStats returns stats object', () => {
    const service = new LeaderboardService();
    const stats = service.getStats();
    assert.strictEqual(typeof stats.totalBots, 'number');
    assert.strictEqual(typeof stats.avgMMR, 'number');
    assert.strictEqual(typeof stats.lastUpdated, 'string');
  });
});
