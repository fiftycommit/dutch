import { describe, it } from 'node:test';
import assert from 'node:assert';
import { PlayerLearningService } from '../services/PlayerLearningService';

describe('PlayerLearningService', () => {
  it('constructs without error', () => {
    const service = new PlayerLearningService();
    assert.ok(service);
  });

  it('getProfile returns null for non-existent player', async () => {
    const service = new PlayerLearningService();
    const profile = await service.getProfile('nonexistent-client', 0);
    assert.strictEqual(profile, null);
  });

  it('getHistory returns empty array for non-existent player', async () => {
    const service = new PlayerLearningService();
    const history = await service.getHistory('nonexistent-client', 0);
    assert.ok(Array.isArray(history));
    assert.strictEqual(history.length, 0);
  });
});
