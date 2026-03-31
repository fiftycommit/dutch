import { describe, it } from 'node:test';
import assert from 'node:assert';
import { NeuralNetworkService } from '../services/NeuralNetworkService';
import { BotGameRecord } from '../models/BotLearning';

// Create at module level to avoid serialization issues with Node.js test runner IPC
const neuralNet = new NeuralNetworkService();

describe('NeuralNetworkService', () => {

  describe('predict', () => {
    it('devrait retourner un tableau de probabilités', () => {
      const input = new Array(15).fill(0.5);
      const predictions = neuralNet.predict(input);

      assert.strictEqual(predictions.length, 8);
      assert.ok(predictions.every(p => p >= 0 && p <= 1));

      // La somme des probabilités devrait être proche de 1 (softmax)
      const sum = predictions.reduce((a, b) => a + b, 0);
      assert.ok(Math.abs(sum - 1) < 0.01, `Sum should be ~1, got ${sum}`);
    });

    it('devrait gérer des inputs variés', () => {
      const input = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 0, 0.5, 0.3, 0.7, 0.2];
      const predictions = neuralNet.predict(input);

      assert.strictEqual(predictions.length, 8);
      assert.ok(predictions.every(p => !Number.isNaN(p)));
    });

    it('devrait gérer des inputs à zéro', () => {
      const input = new Array(15).fill(0);
      const predictions = neuralNet.predict(input);

      assert.strictEqual(predictions.length, 8);
      assert.ok(predictions.every(p => p >= 0 && p <= 1));
      const sum = predictions.reduce((a, b) => a + b, 0);
      assert.ok(Math.abs(sum - 1) < 0.01);
    });

    it('devrait gérer des inputs à 1', () => {
      const input = new Array(15).fill(1);
      const predictions = neuralNet.predict(input);

      assert.strictEqual(predictions.length, 8);
      assert.ok(predictions.every(p => !Number.isNaN(p)));
      assert.ok(predictions.every(p => Number.isFinite(p)));
    });

    it('devrait gérer des inputs négatifs', () => {
      const input = new Array(15).fill(-0.5);
      const predictions = neuralNet.predict(input);

      assert.strictEqual(predictions.length, 8);
      assert.ok(predictions.every(p => p >= 0 && p <= 1));
    });

    it('devrait retourner des résultats différents pour des inputs différents', () => {
      const input1 = new Array(15).fill(0);
      const input2 = new Array(15).fill(1);
      const predictions1 = neuralNet.predict(input1);
      const predictions2 = neuralNet.predict(input2);

      // At least one prediction should differ
      let differs = false;
      for (let i = 0; i < 8; i++) {
        if (Math.abs(predictions1[i] - predictions2[i]) > 0.001) {
          differs = true;
          break;
        }
      }
      assert.ok(differs, 'Predictions should differ for different inputs');
    });

    it('devrait retourner des résultats déterministes pour le même input', () => {
      const input = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 0, 0.5, 0.3, 0.7, 0.2];
      const predictions1 = neuralNet.predict(input);
      const predictions2 = neuralNet.predict(input);

      for (let i = 0; i < 8; i++) {
        assert.strictEqual(predictions1[i], predictions2[i]);
      }
    });

    it('devrait retourner des probabilités dont la somme est exactement ~1 (softmax)', () => {
      const input = [0.5, 0.8, 0.1, 0.3, 1, 0, 0, 0.4, 0, 0.2, 0, 0.6, 0.1, -0.3, 0.9];
      const predictions = neuralNet.predict(input);
      const sum = predictions.reduce((a, b) => a + b, 0);
      assert.ok(Math.abs(sum - 1) < 0.001, `Softmax sum should be ~1, got ${sum}`);
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
      } as any;

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

    it('devrait gérer un gameState avec des valeurs manquantes', () => {
      const gameState = {}; // all undefined, should use defaults via || 0
      const action = { turnNumber: 0, actionType: 'draw_from_deck' } as any;

      const bestAction = neuralNet.predictBestAction(gameState, action);
      assert.strictEqual(typeof bestAction, 'string');
      assert.ok(bestAction.length > 0);
    });

    it('devrait gérer un gameState avec calledDutch=true', () => {
      const gameState = {
        myScore: 5,
        cardsInHand: 2,
        turnPhase: 'end',
        opponentsAvgScore: 25,
        deckCardsRemaining: 10,
        calledDutch: true,
        powerUsesCount: 3,
        scoreAtDutch: 5,
        estimatedRank: 1,
        visibleOpponentCards: 12,
        scoreVsLeader: 0,
        estimatedTurnsLeft: 2,
      };

      const action = { turnNumber: 15, actionType: 'call_dutch' } as any;
      const bestAction = neuralNet.predictBestAction(gameState, action);
      assert.strictEqual(typeof bestAction, 'string');
    });

    it('devrait gérer les différentes phases de jeu', () => {
      const phases = ['start', 'playing', 'end'];
      const validActions = [
        'draw_from_deck', 'draw_from_discard', 'replace_card', 'call_dutch',
        'use_power_peek', 'use_power_swap', 'use_power_steal', 'pass',
      ];

      for (const phase of phases) {
        const gameState = {
          myScore: 10,
          cardsInHand: 4,
          turnPhase: phase,
          opponentsAvgScore: 15,
          deckCardsRemaining: 20,
          calledDutch: false,
          powerUsesCount: 0,
          scoreAtDutch: 0,
          estimatedRank: 2,
          visibleOpponentCards: 4,
          scoreVsLeader: -5,
          estimatedTurnsLeft: 10,
        };
        const action = { turnNumber: 3, actionType: 'draw_from_deck' } as any;
        const bestAction = neuralNet.predictBestAction(gameState, action);
        assert.ok(validActions.includes(bestAction), `Invalid action for phase ${phase}: ${bestAction}`);
      }
    });

    it('devrait gérer des valeurs extrêmes de scoreVsLeader', () => {
      const gameState = {
        myScore: 0,
        cardsInHand: 1,
        turnPhase: 'playing',
        opponentsAvgScore: 100,
        deckCardsRemaining: 5,
        calledDutch: false,
        powerUsesCount: 10,
        scoreAtDutch: 100,
        estimatedRank: 4,
        visibleOpponentCards: 16,
        scoreVsLeader: -100, // extreme negative (clamped to -1)
        estimatedTurnsLeft: 50,
      };
      const action = { turnNumber: 50, actionType: 'draw_from_deck' } as any;
      const bestAction = neuralNet.predictBestAction(gameState, action);
      assert.strictEqual(typeof bestAction, 'string');
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

    it('devrait modifier les prédictions après entraînement', () => {
      const input = new Array(15).fill(0.5);
      const target = [1, 0, 0, 0, 0, 0, 0, 0]; // "draw_from_deck"

      const predBefore = neuralNet.predict(input);

      // Train many times on the same data
      const trainingData = [{ input, output: target }];
      for (let i = 0; i < 100; i++) {
        neuralNet.train(trainingData);
      }

      const predAfter = neuralNet.predict(input);

      // The first output should have increased after training towards target[0]=1
      assert.ok(predAfter[0] > predBefore[0] || predAfter[0] > 0.3,
        `Expected first prediction to improve after training. Before: ${predBefore[0]}, After: ${predAfter[0]}`);
    });

    it('devrait gérer un batch vide sans erreur', () => {
      assert.doesNotThrow(() => {
        neuralNet.train([]);
      });
    });

    it('devrait gérer un batch avec un seul élément', () => {
      assert.doesNotThrow(() => {
        neuralNet.train([{
          input: new Array(15).fill(0.1),
          output: [0, 0, 0, 1, 0, 0, 0, 0],
        }]);
      });
    });

    it('devrait gérer plusieurs epochs d\'entraînement', () => {
      const trainingData = [
        { input: new Array(15).fill(0.2), output: [1, 0, 0, 0, 0, 0, 0, 0] },
        { input: new Array(15).fill(0.4), output: [0, 0, 1, 0, 0, 0, 0, 0] },
        { input: new Array(15).fill(0.6), output: [0, 0, 0, 0, 0, 1, 0, 0] },
        { input: new Array(15).fill(0.8), output: [0, 0, 0, 0, 0, 0, 0, 1] },
      ];

      assert.doesNotThrow(() => {
        for (let epoch = 0; epoch < 10; epoch++) {
          neuralNet.train(trainingData);
        }
      });
    });

    it('devrait pouvoir prédire correctement après entraînement intensif', () => {
      // Train heavily on one pattern
      const input = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
      const target = [0, 0, 0, 1, 0, 0, 0, 0]; // call_dutch
      const trainingData = [{ input, output: target }];

      for (let i = 0; i < 500; i++) {
        neuralNet.train(trainingData);
      }

      const predictions = neuralNet.predict(input);
      // After heavy training, the target index (3) should be the highest
      let maxIdx = 0;
      for (let i = 1; i < predictions.length; i++) {
        if (predictions[i] > predictions[maxIdx]) maxIdx = i;
      }
      assert.strictEqual(maxIdx, 3, `Expected action index 3 (call_dutch), got ${maxIdx}`);
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

    it('devrait entraîner avec des actions variées', async () => {
      const mockRecord: BotGameRecord = {
        gameId: 'test-game-varied-nn',
        botId: 'bot-varied-nn',
        botName: 'Varied NN Bot',
        botBehavior: 'aggressive',
        botSkillLevel: 'gold',
        startTime: new Date().toISOString(),
        endTime: new Date().toISOString(),
        numberOfPlayers: 3,
        gameMode: 'classic',
        usedSBMM: false,
        actions: [
          {
            actionType: 'draw_from_deck',
            turnNumber: 1,
            timestamp: new Date().toISOString(),
            gameState: { myScore: 20, cardsInHand: 4, turnPhase: 'start', opponentsAvgScore: 18, deckCardsRemaining: 40 },
            actionDetails: {},
            result: {},
          },
          {
            actionType: 'draw_from_discard',
            turnNumber: 2,
            timestamp: new Date().toISOString(),
            gameState: { myScore: 18, cardsInHand: 4, turnPhase: 'playing', opponentsAvgScore: 16, deckCardsRemaining: 38 },
            actionDetails: {},
            result: {},
          },
          {
            actionType: 'replace_card',
            turnNumber: 3,
            timestamp: new Date().toISOString(),
            gameState: { myScore: 16, cardsInHand: 4, turnPhase: 'playing', opponentsAvgScore: 14, deckCardsRemaining: 36 },
            actionDetails: { cardIndex: 2 },
            result: {},
          },
          {
            actionType: 'call_dutch',
            turnNumber: 4,
            timestamp: new Date().toISOString(),
            gameState: { myScore: 10, cardsInHand: 3, turnPhase: 'end', opponentsAvgScore: 12, deckCardsRemaining: 34 },
            actionDetails: {},
            result: {},
          },
          {
            actionType: 'use_power_peek',
            turnNumber: 5,
            timestamp: new Date().toISOString(),
            gameState: { myScore: 10, cardsInHand: 3, turnPhase: 'playing', opponentsAvgScore: 12, deckCardsRemaining: 33 },
            actionDetails: {},
            result: {},
          },
          {
            actionType: 'use_power_swap',
            turnNumber: 6,
            timestamp: new Date().toISOString(),
            gameState: { myScore: 8, cardsInHand: 3, turnPhase: 'playing', opponentsAvgScore: 11, deckCardsRemaining: 31 },
            actionDetails: {},
            result: {},
          },
          {
            actionType: 'use_power_steal',
            turnNumber: 7,
            timestamp: new Date().toISOString(),
            gameState: { myScore: 6, cardsInHand: 3, turnPhase: 'playing', opponentsAvgScore: 10, deckCardsRemaining: 29 },
            actionDetails: {},
            result: {},
          },
          {
            actionType: 'pass',
            turnNumber: 8,
            timestamp: new Date().toISOString(),
            gameState: { myScore: 5, cardsInHand: 3, turnPhase: 'playing', opponentsAvgScore: 10, deckCardsRemaining: 28 },
            actionDetails: {},
            result: {},
          },
        ],
        initialHandSize: 4,
        finalScore: 5,
        finalRank: 1,
        calledDutch: true,
        wonDutch: true,
        cardsAtDutch: 3,
        scoreAtDutch: 10,
        totalTurns: 8,
        avgDecisionTime: 1000,
        powerUsesCount: 3,
        goodDecisions: 6,
        badDecisions: 1,
        opponents: [],
      };

      await assert.doesNotReject(neuralNet.trainFromGame(mockRecord));
    });

    it('devrait gérer une partie sans actions', async () => {
      const mockRecord: BotGameRecord = {
        gameId: 'test-game-empty-nn',
        botId: 'bot-empty-nn',
        botName: 'Empty NN Bot',
        botBehavior: 'balanced',
        botSkillLevel: 'silver',
        startTime: new Date().toISOString(),
        endTime: new Date().toISOString(),
        numberOfPlayers: 4,
        gameMode: 'classic',
        usedSBMM: false,
        actions: [],
        initialHandSize: 4,
        finalScore: 20,
        finalRank: 4,
        calledDutch: false,
        wonDutch: false,
        cardsAtDutch: 0,
        scoreAtDutch: 0,
        totalTurns: 0,
        avgDecisionTime: 0,
        powerUsesCount: 0,
        goodDecisions: 0,
        badDecisions: 0,
        opponents: [],
      };

      await assert.doesNotReject(neuralNet.trainFromGame(mockRecord));
    });

    it('devrait gérer un actionType non reconnu', async () => {
      const mockRecord: BotGameRecord = {
        gameId: 'test-game-unknown-nn',
        botId: 'bot-unknown-nn',
        botName: 'Unknown Action NN Bot',
        botBehavior: 'balanced',
        botSkillLevel: 'silver',
        startTime: new Date().toISOString(),
        endTime: new Date().toISOString(),
        numberOfPlayers: 4,
        gameMode: 'classic',
        usedSBMM: false,
        actions: [
          {
            actionType: 'some_unknown_action',
            turnNumber: 1,
            timestamp: new Date().toISOString(),
            gameState: { myScore: 15, cardsInHand: 4, turnPhase: 'playing', opponentsAvgScore: 15, deckCardsRemaining: 30 },
            actionDetails: {},
            result: {},
          },
        ],
        initialHandSize: 4,
        finalScore: 15,
        finalRank: 3,
        calledDutch: false,
        wonDutch: false,
        cardsAtDutch: 0,
        scoreAtDutch: 0,
        totalTurns: 1,
        avgDecisionTime: 1500,
        powerUsesCount: 0,
        goodDecisions: 0,
        badDecisions: 0,
        opponents: [],
      };

      // Should not crash, just produce all-zero output vector
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

    it('devrait avoir la bonne architecture 15 -> 32 -> 16 -> 8', () => {
      const stats = neuralNet.getStats();
      assert.strictEqual(stats.architecture, '15 -> 32 -> 16 -> 8');
    });

    it('devrait avoir le bon nombre de poids', () => {
      const stats = neuralNet.getStats();
      // Layer 1: 15*32 = 480 weights
      // Layer 2: 32*16 = 512 weights
      // Layer 3: 16*8 = 128 weights
      // Total weights = 480 + 512 + 128 = 1120
      assert.strictEqual(stats.totalWeights, 1120);
    });

    it('devrait avoir le bon nombre de biais', () => {
      const stats = neuralNet.getStats();
      // Layer 1: 32 biases
      // Layer 2: 16 biases
      // Layer 3: 8 biases
      // Total biases = 32 + 16 + 8 = 56
      assert.strictEqual(stats.totalBiases, 56);
    });

    it('devrait avoir totalParameters = totalWeights + totalBiases', () => {
      const stats = neuralNet.getStats();
      assert.strictEqual(stats.totalParameters, stats.totalWeights + stats.totalBiases);
    });

    it('devrait avoir exactement 3 couches', () => {
      const stats = neuralNet.getStats();
      assert.strictEqual(stats.totalLayers, 3);
    });
  });
});
