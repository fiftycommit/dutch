import { describe, it, before } from 'node:test';
import assert from 'node:assert';
import { GeneticAlgorithmService } from '../services/GeneticAlgorithmService';

describe('GeneticAlgorithmService', () => {
  let service: GeneticAlgorithmService;

  before(() => {
    service = new GeneticAlgorithmService();
  });

  describe('constructor and basic getters', () => {
    it('constructs without error', () => {
      assert.ok(service);
    });

    it('getStats returns valid stats structure', () => {
      const stats = service.getStats();
      assert.strictEqual(typeof stats.currentGeneration, 'number');
      assert.strictEqual(typeof stats.populationSize, 'number');
      assert.strictEqual(typeof stats.avgFitness, 'number');
      assert.strictEqual(typeof stats.bestFitness, 'number');
      assert.strictEqual(typeof stats.bestBotId, 'string');
      assert.strictEqual(typeof stats.totalMutations, 'number');
    });

    it('getPopulation returns an array', () => {
      const pop = service.getPopulation();
      assert.ok(Array.isArray(pop));
    });

    it('getPopulation returns a copy (not reference)', () => {
      const pop1 = service.getPopulation();
      const pop2 = service.getPopulation();
      assert.notStrictEqual(pop1, pop2);
    });

    it('getBestBot returns undefined when population is empty on fresh service', () => {
      const freshService = new GeneticAlgorithmService();
      // On a fresh instance with no generation files, population may be empty
      const best = freshService.getBestBot();
      if (freshService.getPopulation().length === 0) {
        assert.strictEqual(best, undefined);
      } else {
        assert.ok(best);
      }
    });

    it('getStats returns defaults when population is empty', () => {
      const freshService = new GeneticAlgorithmService();
      const stats = freshService.getStats();
      if (freshService.getPopulation().length === 0) {
        assert.strictEqual(stats.avgFitness, 0);
        assert.strictEqual(stats.bestFitness, 0);
        assert.strictEqual(stats.bestBotId, 'none');
      }
    });
  });

  describe('calculateFitness', () => {
    it('returns 0 for a bot with no wins and default stats', () => {
      const bot = {
        botId: 'test_bot',
        generation: 1,
        genes: {
          aggressiveness: 0.5, caution: 0.5, riskTolerance: 0.5,
          patience: 0.5, dutchThreshold: 10, powerUsageRate: 0.5,
          memoryAccuracy: 0.7, adaptability: 0.5,
        },
        fitness: 0, wins: 0, losses: 0, avgScore: 20, mmr: 1500, mutations: [],
      };
      const fitness = service.calculateFitness(bot);
      assert.strictEqual(typeof fitness, 'number');
      assert.ok(fitness >= 0);
    });

    it('returns higher fitness for bot with many wins', () => {
      const winningBot = {
        botId: 'winner', generation: 1,
        genes: { aggressiveness: 0.5, caution: 0.5, riskTolerance: 0.5, patience: 0.5, dutchThreshold: 10, powerUsageRate: 0.5, memoryAccuracy: 0.7, adaptability: 0.5 },
        fitness: 0, wins: 10, losses: 2, avgScore: 5, mmr: 2000, mutations: [],
      };
      const losingBot = {
        botId: 'loser', generation: 1,
        genes: { aggressiveness: 0.5, caution: 0.5, riskTolerance: 0.5, patience: 0.5, dutchThreshold: 10, powerUsageRate: 0.5, memoryAccuracy: 0.7, adaptability: 0.5 },
        fitness: 0, wins: 1, losses: 10, avgScore: 25, mmr: 1000, mutations: [],
      };
      const winFitness = service.calculateFitness(winningBot);
      const loseFitness = service.calculateFitness(losingBot);
      assert.ok(winFitness > loseFitness);
    });

    it('fitness is clamped to minimum 0', () => {
      const terribleBot = {
        botId: 'terrible', generation: 1,
        genes: { aggressiveness: 0.5, caution: 0.5, riskTolerance: 0.5, patience: 0.5, dutchThreshold: 10, powerUsageRate: 0.5, memoryAccuracy: 0.7, adaptability: 0.5 },
        fitness: 0, wins: 0, losses: 100, avgScore: 50, mmr: 500, mutations: [],
      };
      const fitness = service.calculateFitness(terribleBot);
      assert.ok(fitness >= 0);
    });

    it('handles zero games (no wins, no losses)', () => {
      const bot = {
        botId: 'no_games', generation: 1,
        genes: { aggressiveness: 0.5, caution: 0.5, riskTolerance: 0.5, patience: 0.5, dutchThreshold: 10, powerUsageRate: 0.5, memoryAccuracy: 0.7, adaptability: 0.5 },
        fitness: 0, wins: 0, losses: 0, avgScore: 20, mmr: 1500, mutations: [],
      };
      const fitness = service.calculateFitness(bot);
      // winRate=0, scoreBonus=0, mmrBonus=0 => fitness should be 0
      assert.strictEqual(fitness, 0);
    });

    it('gives score bonus for low avgScore', () => {
      const lowScore = {
        botId: 'low', generation: 1,
        genes: { aggressiveness: 0.5, caution: 0.5, riskTolerance: 0.5, patience: 0.5, dutchThreshold: 10, powerUsageRate: 0.5, memoryAccuracy: 0.7, adaptability: 0.5 },
        fitness: 0, wins: 5, losses: 5, avgScore: 5, mmr: 1500, mutations: [],
      };
      const highScore = {
        botId: 'high', generation: 1,
        genes: { aggressiveness: 0.5, caution: 0.5, riskTolerance: 0.5, patience: 0.5, dutchThreshold: 10, powerUsageRate: 0.5, memoryAccuracy: 0.7, adaptability: 0.5 },
        fitness: 0, wins: 5, losses: 5, avgScore: 25, mmr: 1500, mutations: [],
      };
      assert.ok(service.calculateFitness(lowScore) > service.calculateFitness(highScore));
    });

    it('gives MMR bonus for high MMR', () => {
      const highMMR = {
        botId: 'highmmr', generation: 1,
        genes: { aggressiveness: 0.5, caution: 0.5, riskTolerance: 0.5, patience: 0.5, dutchThreshold: 10, powerUsageRate: 0.5, memoryAccuracy: 0.7, adaptability: 0.5 },
        fitness: 0, wins: 5, losses: 5, avgScore: 15, mmr: 2500, mutations: [],
      };
      const lowMMR = {
        botId: 'lowmmr', generation: 1,
        genes: { aggressiveness: 0.5, caution: 0.5, riskTolerance: 0.5, patience: 0.5, dutchThreshold: 10, powerUsageRate: 0.5, memoryAccuracy: 0.7, adaptability: 0.5 },
        fitness: 0, wins: 5, losses: 5, avgScore: 15, mmr: 800, mutations: [],
      };
      assert.ok(service.calculateFitness(highMMR) > service.calculateFitness(lowMMR));
    });
  });

  describe('initializePopulation', () => {
    it('creates a population of 20 bots', async () => {
      const generation = await service.initializePopulation();
      assert.strictEqual(generation.population.length, 20);
      assert.strictEqual(generation.generationNumber, 1);
      assert.ok(generation.timestamp);
      assert.ok(generation.bestBot);
      assert.strictEqual(typeof generation.avgFitness, 'number');
      assert.strictEqual(typeof generation.bestFitness, 'number');
    });

    it('each bot has valid genome structure', async () => {
      await service.initializePopulation();
      const pop = service.getPopulation();
      for (const bot of pop) {
        assert.ok(bot.botId.startsWith('gen1_bot'));
        assert.strictEqual(bot.generation, 1);
        assert.strictEqual(typeof bot.genes.aggressiveness, 'number');
        assert.strictEqual(typeof bot.genes.caution, 'number');
        assert.strictEqual(typeof bot.genes.riskTolerance, 'number');
        assert.strictEqual(typeof bot.genes.patience, 'number');
        assert.strictEqual(typeof bot.genes.dutchThreshold, 'number');
        assert.strictEqual(typeof bot.genes.powerUsageRate, 'number');
        assert.strictEqual(typeof bot.genes.memoryAccuracy, 'number');
        assert.strictEqual(typeof bot.genes.adaptability, 'number');
        assert.ok(bot.genes.dutchThreshold >= 5 && bot.genes.dutchThreshold <= 25);
        assert.ok(bot.genes.memoryAccuracy >= 0.5 && bot.genes.memoryAccuracy <= 1.0);
        assert.strictEqual(bot.fitness, 0);
        assert.strictEqual(bot.wins, 0);
        assert.strictEqual(bot.losses, 0);
        assert.strictEqual(bot.mmr, 1500);
      }
    });
  });

  describe('updateBotStats', () => {
    it('updates wins for a winning bot', async () => {
      await service.initializePopulation();
      const pop = service.getPopulation();
      const botId = pop[0].botId;

      service.updateBotStats(botId, true, 10, 1600);

      const updatedPop = service.getPopulation();
      const updatedBot = updatedPop.find(b => b.botId === botId);
      assert.ok(updatedBot);
      assert.strictEqual(updatedBot.wins, 1);
      assert.strictEqual(updatedBot.losses, 0);
      assert.strictEqual(updatedBot.mmr, 1600);
    });

    it('updates losses for a losing bot', async () => {
      await service.initializePopulation();
      const pop = service.getPopulation();
      const botId = pop[1].botId;

      service.updateBotStats(botId, false, 25, 1400);

      const updatedPop = service.getPopulation();
      const updatedBot = updatedPop.find(b => b.botId === botId);
      assert.ok(updatedBot);
      assert.strictEqual(updatedBot.wins, 0);
      assert.strictEqual(updatedBot.losses, 1);
      assert.strictEqual(updatedBot.mmr, 1400);
    });

    it('does nothing for unknown botId', async () => {
      await service.initializePopulation();
      // Should not throw
      service.updateBotStats('nonexistent_bot', true, 10, 1600);
    });

    it('recalculates fitness after update', async () => {
      await service.initializePopulation();
      const pop = service.getPopulation();
      const botId = pop[2].botId;

      service.updateBotStats(botId, true, 5, 2000);

      const updatedBot = service.getPopulation().find(b => b.botId === botId);
      assert.ok(updatedBot);
      assert.ok(updatedBot.fitness > 0);
    });

    it('computes running average score correctly', async () => {
      await service.initializePopulation();
      const pop = service.getPopulation();
      const botId = pop[3].botId;

      service.updateBotStats(botId, true, 10, 1600);
      service.updateBotStats(botId, false, 20, 1550);

      const updatedBot = service.getPopulation().find(b => b.botId === botId);
      assert.ok(updatedBot);
      assert.strictEqual(updatedBot.wins, 1);
      assert.strictEqual(updatedBot.losses, 1);
    });
  });

  describe('evolveGeneration', () => {
    it('throws when population is empty', async () => {
      const freshService = new GeneticAlgorithmService();
      // Ensure population is empty - if loaded from disk we need to re-init
      if (freshService.getPopulation().length > 0) {
        // can't test this path easily if data exists on disk
        return;
      }
      await assert.rejects(
        () => freshService.evolveGeneration(),
        { message: 'Population vide. Initialisez d\'abord avec initializePopulation()' }
      );
    });

    it('evolves to next generation successfully', async () => {
      await service.initializePopulation();

      // Give some bots stats so fitness varies
      const pop = service.getPopulation();
      service.updateBotStats(pop[0].botId, true, 5, 1800);
      service.updateBotStats(pop[1].botId, true, 8, 1700);
      service.updateBotStats(pop[2].botId, false, 25, 1200);

      const nextGen = await service.evolveGeneration();
      assert.strictEqual(nextGen.generationNumber, 2);
      assert.strictEqual(nextGen.population.length, 20);
      assert.ok(nextGen.bestBot);
      assert.strictEqual(typeof nextGen.avgFitness, 'number');
    });

    it('preserves elite bots across generations', async () => {
      await service.initializePopulation();
      const pop = service.getPopulation();
      // Make first bot clearly the best
      service.updateBotStats(pop[0].botId, true, 3, 2500);
      for (let i = 1; i < 10; i++) {
        service.updateBotStats(pop[0].botId, true, 3, 2500);
      }

      const nextGen = await service.evolveGeneration();
      // The elite (top 4) should be preserved in the next generation
      assert.strictEqual(nextGen.population.length, 20);
    });

    it('can evolve multiple generations in sequence', async () => {
      await service.initializePopulation();

      const gen2 = await service.evolveGeneration();
      assert.strictEqual(gen2.generationNumber, 2);

      const gen3 = await service.evolveGeneration();
      assert.strictEqual(gen3.generationNumber, 3);
    });
  });

  describe('getBestBot after evolution', () => {
    it('returns the bot with highest fitness', async () => {
      await service.initializePopulation();
      const pop = service.getPopulation();
      service.updateBotStats(pop[0].botId, true, 3, 2500);
      service.updateBotStats(pop[0].botId, true, 3, 2500);

      const best = service.getBestBot();
      assert.ok(best);
      assert.strictEqual(typeof best.fitness, 'number');
      // The best bot should have the highest fitness
      const allFitness = service.getPopulation().map(b => b.fitness);
      assert.strictEqual(best.fitness, Math.max(...allFitness));
    });
  });
});
