import { describe, it } from 'node:test';
import assert from 'node:assert';
import { TournamentService } from '../services/TournamentService';

describe('TournamentService', () => {
  it('constructs without error', () => {
    const service = new TournamentService();
    assert.ok(service);
  });

  it('getStats returns stats object', async () => {
    const service = new TournamentService();
    const stats = await service.getStats();
    assert.strictEqual(typeof stats.totalTournaments, 'number');
    assert.strictEqual(typeof stats.completedTournaments, 'number');
    assert.strictEqual(typeof stats.totalMatches, 'number');
  });
});
