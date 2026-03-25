import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import { NeuralNetworkService } from '../services/NeuralNetworkService';
import { BotGameRecord } from '../models/BotLearning';

describe('NeuralNetworkService', () => {
  let neuralNet: NeuralNetworkService;

  beforeEach(() => {
    neuralNet = new NeuralNetworkService();
  });

  describe('predict', () => {
    it('devrait retourner un tableau de probabilités', () => {
      const input = new Array(15).fill(0.5);
      const predictions = neuralNet.predict(input);

      assert.strictEqual(predictions.length, 8);
      assert.ok(predictions.every(p => p >= 0 && p <= 1));

      // La somme des probabilités devrait être proche de 1 (softmax)
      const sum = predictions.reduce((a, b) => a + b, 0);
      assert.ok(Math.abs(sum - 1) < 0.1);
    });

    it('devrait gérer des inputs variés', () => {
      const input = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 0, 0.5, 0.3, 0.7, 0.2];
      const predictions = neuralNet.predict(input);

      assert.strictEqual(predictions.length, 8);
      assert.ok(predictions.every(p => !Number.isNaN(p)));
    });
  });

  describe('predictBestAction', () => {
    it('devrait prédire une action valide', () => {
      const gameState = {
        myScore: 15,
        cardsInHand: 4,
        turnPhase: 'playing',
        opponentsAvgScore: 18,
        deckCardsRemaining: 20,
        calledDutch: false,
        powerUsesCount: 1,
        scoreAtDutch: 0,
        estimatedRank: 2,
        visibleOpponentCards: 8,
        scoreVsLeader: -3,
        estimatedTurnsLeft: 10,
      };

      const action = {
        turnNumber: 5,
        actionType: 'draw_from_deck',
      };

      const bestAction = neuralNet.predictBestAction(gameState, action);

      const validActions = [
        'draw_from_deck',
        'draw_from_discard',
        'replace_card',
        'call_dutch',
        'use_power_peek',
        'use_power_swap',
        'use_power_steal',
        'pass',
      ];

      assert.ok(validActions.includes(bestAction));
    });
  });

  describe('train', () => {
    it('devrait entraîner le réseau sans erreur', () => {
      const trainingData = [
        {
          input: new Array(15).fill(0.5),
          output: [1, 0, 0, 0, 0, 0, 0, 0],
        },
        {
          input: new Array(15).fill(0.3),
          output: [0, 1, 0, 0, 0, 0, 0, 0],
        },
      ];

      assert.doesNotThrow(() => {
        neuralNet.train(trainingData);
      });
    });
  });

  describe('trainFromGame', () => {
    it('devrait entraîner à partir d\'une partie complète', async () => {
      const mockRecord: BotGameRecord = {
        gameId: 'test-game-1',
        botId: 'bot-1',
        botName: 'Test Bot',
        botBehavior: 'balanced',
        botSkillLevel: 'silver',
        startTime: new Date().toISOString(),
        endTime: new Date().toISOString(),
        numberOfPlayers: 4,
        gameMode: 'classic',
        usedSBMM: false,
        actions: [
          {
            actionType: 'draw_from_deck',
            turnNumber: 1,
            timestamp: new Date().toISOString(),
            gameState: {
              myScore: 20,
              cardsInHand: 4,
              turnPhase: 'playing',
              opponentsAvgScore: 18,
              deckCardsRemaining: 40,
            },
            actionDetails: {},
            result: {},
          },
        ],
        initialHandSize: 4,
        finalScore: 15,
        finalRank: 2,
        calledDutch: false,
        wonDutch: false,
        cardsAtDutch: 0,
        scoreAtDutch: 0,
        totalTurns: 1,
        avgDecisionTime: 1500,
        powerUsesCount: 0,
        goodDecisions: 1,
        badDecisions: 0,
        opponents: [],
      };

      await assert.doesNotReject(neuralNet.trainFromGame(mockRecord));
    });
  });

  describe('getStats', () => {
    it('devrait retourner les stats du réseau', () => {
      const stats = neuralNet.getStats();

      assert.ok('architecture' in stats);
      assert.ok('totalLayers' in stats);
      assert.ok('totalWeights' in stats);
      assert.ok('totalBiases' in stats);
      assert.ok('totalParameters' in stats);

      assert.ok(stats.architecture.includes('15'));
      assert.ok(stats.architecture.includes('8'));
      assert.strictEqual(stats.totalLayers, 3);
      assert.ok(stats.totalParameters > 0);
    });
  });
});
