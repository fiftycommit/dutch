import { describe, it } from 'node:test';
import assert from 'node:assert';
import { BotLearningService } from '../services/BotLearningService';

describe('BotLearningService', () => {
  it('constructs without error', () => {
    const service = new BotLearningService();
    assert.ok(service);
  });

  it('isPaused returns false by default', () => {
    const service = new BotLearningService();
    assert.strictEqual(service.isPaused(), false);
  });

  it('getPendingCount returns a number', async () => {
    const service = new BotLearningService();
    const count = await service.getPendingCount();
    assert.strictEqual(typeof count, 'number');
    assert.ok(count >= 0);
  });
});
