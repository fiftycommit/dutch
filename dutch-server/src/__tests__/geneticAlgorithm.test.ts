import { describe, it } from 'node:test';
import assert from 'node:assert';
import { GeneticAlgorithmService } from '../services/GeneticAlgorithmService';

describe('GeneticAlgorithmService', () => {
  it('constructs without error', () => {
    const service = new GeneticAlgorithmService();
    assert.ok(service);
  });

  it('getStats returns valid stats', () => {
    const service = new GeneticAlgorithmService();
    const stats = service.getStats();
    assert.strictEqual(typeof stats.currentGeneration, 'number');
    assert.strictEqual(typeof stats.populationSize, 'number');
    assert.strictEqual(typeof stats.avgFitness, 'number');
  });

  it('getBestBot returns undefined or a genome', () => {
    const service = new GeneticAlgorithmService();
    const best = service.getBestBot();
    // Population may be empty on fresh init
    if (best !== undefined) {
      assert.strictEqual(typeof best.genes.aggressiveness, 'number');
      assert.strictEqual(typeof best.genes.dutchThreshold, 'number');
    } else {
      assert.strictEqual(best, undefined);
    }
  });

  it('getPopulation returns an array', () => {
    const service = new GeneticAlgorithmService();
    const pop = service.getPopulation();
    assert.ok(Array.isArray(pop));
  });
});
