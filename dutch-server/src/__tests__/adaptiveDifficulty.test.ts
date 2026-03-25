import { describe, it } from 'node:test';
import assert from 'node:assert';
import { AdaptiveDifficultyService } from '../services/AdaptiveDifficultyService';

describe('AdaptiveDifficultyService', () => {
  it('constructs without error', () => {
    const service = new AdaptiveDifficultyService();
    assert.ok(service);
  });

  it('adjustBotDifficulty returns base MMR when no player stats', async () => {
    const service = new AdaptiveDifficultyService();
    const result = await service.adjustBotDifficulty(1000, 'unknown-player', 'bronze');
    assert.strictEqual(result.baseMMR, 1000);
    assert.strictEqual(result.adjustedMMR, 1000);
    assert.strictEqual(result.adjustmentFactor, 1);
    assert.ok(result.reason.includes('Aucune statistique'));
  });

  it('adjustBotDifficulty works for all skill levels', async () => {
    const service = new AdaptiveDifficultyService();
    for (const level of ['bronze', 'silver', 'gold', 'platinum'] as const) {
      const result = await service.adjustBotDifficulty(800, 'no-stats-player', level);
      assert.strictEqual(result.baseMMR, 800);
      assert.strictEqual(typeof result.adjustedMMR, 'number');
    }
  });
});
