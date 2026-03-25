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

  it('isPaused returns false by default', () => {
    assert.strictEqual(service.isPaused(), false);
  });

  it('getPendingCount returns a number', async () => {
    const count = await service.getPendingCount();
    assert.strictEqual(typeof count, 'number');
    assert.ok(count >= 0);
  });
});
