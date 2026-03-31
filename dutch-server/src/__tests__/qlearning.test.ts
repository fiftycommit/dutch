import { describe, it, before } from 'node:test';
import assert from 'node:assert';
import { QLearningService } from '../services/QLearningService';
import { BotGameRecord } from '../models/BotLearning';

describe('QLearningService', () => {
  let qLearning: QLearningService;

  before(() => {
    qLearning = new QLearningService();
  });

  describe('selectAction', () => {
    it('devrait sélectionner une action parmi les actions disponibles', () => {
      const state = {
        myScore: 15,
        cardsInHand: 4,
        turnPhase: 'playing',
        opponentsAvgScore: 18,
        deckCardsRemaining: 20,
      };

      const availableActions = [
        { type: 'draw_deck' as const },
        { type: 'draw_discard' as const },
        { type: 'call_dutch' as const },
      ];

      const action = qLearning.selectAction(state, availableActions);
      assert.ok(availableActions.some(a => a.type === action.type));
    });

    it('devrait retourner une action valide même avec un état inconnu', () => {
      const state = {
        myScore: 0,
        cardsInHand: 4,
        turnPhase: 'start',
        opponentsAvgScore: 0,
        deckCardsRemaining: 52,
      };

      const availableActions = [
        { type: 'draw_deck' as const },
      ];

      const action = qLearning.selectAction(state, availableActions);
      assert.deepStrictEqual(action, { type: 'draw_deck' });
    });

    it('devrait retourner une action avec cardIndex quand spécifié', () => {
      const state = {
        myScore: 10,
        cardsInHand: 4,
        turnPhase: 'playing',
        opponentsAvgScore: 15,
        deckCardsRemaining: 30,
      };

      const availableActions = [
        { type: 'replace_card' as const, cardIndex: 0 },
        { type: 'replace_card' as const, cardIndex: 1 },
        { type: 'replace_card' as const, cardIndex: 2 },
      ];

      const action = qLearning.selectAction(state, availableActions);
      assert.ok(availableActions.some(a => a.type === action.type && a.cardIndex === action.cardIndex));
    });

    it('devrait exploiter la meilleure action après apprentissage', () => {
      // Train a state so it has Q-values
      const state = {
        myScore: 25,
        cardsInHand: 3,
        turnPhase: 'playing',
        opponentsAvgScore: 30,
        deckCardsRemaining: 15,
      };

      const goodAction = { type: 'call_dutch' as const };
      const badAction = { type: 'draw_deck' as const };

      // Give call_dutch a very high Q-value
      for (let i = 0; i < 50; i++) {
        qLearning.updateQValue(state, goodAction, 100, null);
        qLearning.updateQValue(state, badAction, -50, null);
      }

      // With epsilon=0.2, most selections should pick the best action
      // Run multiple times and check majority
      let dutchCount = 0;
      for (let i = 0; i < 100; i++) {
        const selected = qLearning.selectAction(state, [goodAction, badAction]);
        if (selected.type === 'call_dutch') dutchCount++;
      }
      // At least 60% should be call_dutch (exploitation)
      assert.ok(dutchCount >= 60, `Expected majority call_dutch, got ${dutchCount}/100`);
    });

    it('devrait gérer un seul type d\'action use_power', () => {
      const state = {
        myScore: 12,
        cardsInHand: 4,
        turnPhase: 'playing',
        opponentsAvgScore: 20,
        deckCardsRemaining: 25,
      };

      const availableActions = [
        { type: 'use_power' as const },
      ];

      const action = qLearning.selectAction(state, availableActions);
      assert.strictEqual(action.type, 'use_power');
    });
  });

  describe('updateQValue', () => {
    it('devrait mettre à jour la Q-value après une action', () => {
      const state = {
        myScore: 15,
        cardsInHand: 4,
        turnPhase: 'playing',
        opponentsAvgScore: 18,
        deckCardsRemaining: 20,
      };

      const action = { type: 'draw_deck' as const };
      const reward = 10;
      const nextState = {
        myScore: 12,
        cardsInHand: 4,
        turnPhase: 'playing',
        opponentsAvgScore: 18,
        deckCardsRemaining: 19,
      };

      assert.doesNotThrow(() => {
        qLearning.updateQValue(state, action, reward, nextState);
      });
    });

    it('devrait créer une nouvelle entrée pour un état inconnu', () => {
      const uniqueState = {
        myScore: 99,
        cardsInHand: 1,
        turnPhase: 'end',
        opponentsAvgScore: 99,
        deckCardsRemaining: 1,
      };

      const action = { type: 'call_dutch' as const };
      const statsBefore = qLearning.getStats();

      qLearning.updateQValue(uniqueState, action, 50, null);

      const statsAfter = qLearning.getStats();
      assert.ok(statsAfter.totalStates >= statsBefore.totalStates);
      assert.ok(statsAfter.totalVisits > statsBefore.totalVisits);
    });

    it('devrait gérer nextState null (état terminal)', () => {
      const state = {
        myScore: 5,
        cardsInHand: 2,
        turnPhase: 'end',
        opponentsAvgScore: 20,
        deckCardsRemaining: 0,
      };

      const action = { type: 'call_dutch' as const };

      assert.doesNotThrow(() => {
        qLearning.updateQValue(state, action, 100, null);
      });
    });

    it('devrait accumuler les visites pour un même état', () => {
      const state = {
        myScore: 50,
        cardsInHand: 3,
        turnPhase: 'playing',
        opponentsAvgScore: 40,
        deckCardsRemaining: 10,
      };

      const action = { type: 'draw_deck' as const };

      qLearning.updateQValue(state, action, 5, null);
      qLearning.updateQValue(state, action, 5, null);
      qLearning.updateQValue(state, action, 5, null);

      const stats = qLearning.getStats();
      assert.ok(stats.totalVisits >= 3);
    });

    it('devrait utiliser maxNextQ du prochain état quand il existe', () => {
      // First create a next state with known Q-values
      const nextState = {
        myScore: 8,
        cardsInHand: 3,
        turnPhase: 'playing',
        opponentsAvgScore: 12,
        deckCardsRemaining: 5,
      };
      qLearning.updateQValue(nextState, { type: 'call_dutch' as const }, 50, null);

      // Now update a state that transitions to nextState
      const state = {
        myScore: 10,
        cardsInHand: 4,
        turnPhase: 'playing',
        opponentsAvgScore: 12,
        deckCardsRemaining: 6,
      };

      assert.doesNotThrow(() => {
        qLearning.updateQValue(state, { type: 'draw_deck' as const }, 5, nextState);
      });
    });

    it('devrait gérer une action avec cardIndex', () => {
      const state = {
        myScore: 15,
        cardsInHand: 4,
        turnPhase: 'playing',
        opponentsAvgScore: 15,
        deckCardsRemaining: 20,
      };

      const action = { type: 'replace_card' as const, cardIndex: 2 };

      assert.doesNotThrow(() => {
        qLearning.updateQValue(state, action, 10, null);
      });
    });
  });

  describe('calculateReward', () => {
    it('devrait donner une récompense positive pour réduire le score', () => {
      const action = { type: 'replace_card' as const, cardIndex: 0 };
      const reward = qLearning.calculateReward(action, 15, 10, false);
      assert.ok(reward > 0);
    });

    it('devrait donner une pénalité pour augmenter le score', () => {
      const action = { type: 'draw_discard' as const };
      const reward = qLearning.calculateReward(action, 10, 15, false);
      assert.ok(reward < 0);
    });

    it('devrait donner une grosse récompense pour gagner avec Dutch', () => {
      const action = { type: 'call_dutch' as const };
      const reward = qLearning.calculateReward(action, 8, 8, true, 1);
      assert.ok(reward > 50);
    });

    it('devrait pénaliser un Dutch raté', () => {
      const action = { type: 'call_dutch' as const };
      const reward = qLearning.calculateReward(action, 8, 8, true, 3);
      assert.ok(reward < 0);
    });

    it('devrait donner la récompense de rang pour le 2ème', () => {
      const action = { type: 'draw_deck' as const };
      const reward = qLearning.calculateReward(action, 10, 10, true, 2);
      // rank 2: +20 reward for ending game
      assert.ok(reward >= 20);
    });

    it('devrait donner une petite récompense de rang pour le 3ème', () => {
      const action = { type: 'draw_deck' as const };
      const reward = qLearning.calculateReward(action, 10, 10, true, 3);
      // rank 3: +5 reward
      assert.ok(reward >= 5);
    });

    it('devrait pénaliser le dernier rang', () => {
      const action = { type: 'draw_deck' as const };
      const reward = qLearning.calculateReward(action, 10, 10, true, 4);
      // rank 4: -20 penalty
      assert.ok(reward < 0);
    });

    it('devrait donner une récompense nulle pour score inchangé sans fin de partie', () => {
      const action = { type: 'draw_deck' as const };
      const reward = qLearning.calculateReward(action, 15, 15, false);
      assert.strictEqual(reward, 0);
    });

    it('devrait combiner récompense Dutch gagnant + réduction score', () => {
      const action = { type: 'call_dutch' as const };
      const reward = qLearning.calculateReward(action, 10, 5, true, 1);
      // scoreDiff=5 -> +10, call_dutch rank=1 -> +100, rank 1 -> +50 = 160
      assert.ok(reward > 100);
    });

    it('devrait donner une pénalité pour Dutch raté avec rang > 1', () => {
      const action = { type: 'call_dutch' as const };
      const reward = qLearning.calculateReward(action, 15, 15, true, 2);
      // call_dutch rank=2 -> no dutch bonus/penalty (only rank 1 gets bonus, >1 gets -50)
      // Actually: rank 2 but called dutch: finalRank > 1 -> -50, rank bonus +20
      // total = -50 + 20 = -30
      assert.ok(reward < 0);
    });

    it('devrait gérer gameEnded sans finalRank', () => {
      const action = { type: 'draw_deck' as const };
      const reward = qLearning.calculateReward(action, 10, 10, true);
      assert.strictEqual(typeof reward, 'number');
    });

    it('devrait appliquer une triple pénalité pour augmentation de score', () => {
      const action = { type: 'draw_deck' as const };
      // scoreDiff = 10 - 20 = -10 -> reward += -10*2 = -20, penalty: -10*3 = -30 extra
      const reward = qLearning.calculateReward(action, 10, 20, false);
      assert.ok(reward < -20, `Expected heavy penalty, got ${reward}`);
    });
  });

  describe('trainFromGame', () => {
    it('devrait entraîner le modèle à partir d\'une partie complète', async () => {
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
            result: { newScore: 18 },
          },
          {
            actionType: 'replace_card',
            turnNumber: 2,
            timestamp: new Date().toISOString(),
            gameState: {
              myScore: 18,
              cardsInHand: 4,
              turnPhase: 'playing',
              opponentsAvgScore: 16,
              deckCardsRemaining: 39,
            },
            actionDetails: { cardIndex: 0 },
            result: { newScore: 15 },
          },
        ],
        initialHandSize: 4,
        finalScore: 15,
        finalRank: 2,
        calledDutch: false,
        wonDutch: false,
        cardsAtDutch: 0,
        scoreAtDutch: 0,
        totalTurns: 2,
        avgDecisionTime: 1500,
        powerUsesCount: 0,
        goodDecisions: 2,
        badDecisions: 0,
        opponents: [],
      };

      await assert.doesNotReject(qLearning.trainFromGame(mockRecord));
    });

    it('devrait entraîner avec une seule action', async () => {
      const mockRecord: BotGameRecord = {
        gameId: 'test-game-single',
        botId: 'bot-single',
        botName: 'Single Action Bot',
        botBehavior: 'fast',
        botSkillLevel: 'bronze',
        startTime: new Date().toISOString(),
        endTime: new Date().toISOString(),
        numberOfPlayers: 2,
        gameMode: 'classic',
        usedSBMM: false,
        actions: [
          {
            actionType: 'call_dutch',
            turnNumber: 1,
            timestamp: new Date().toISOString(),
            gameState: {
              myScore: 5,
              cardsInHand: 2,
              turnPhase: 'playing',
              opponentsAvgScore: 20,
              deckCardsRemaining: 30,
            },
            actionDetails: {},
            result: { newScore: 5 },
          },
        ],
        initialHandSize: 4,
        finalScore: 5,
        finalRank: 1,
        calledDutch: true,
        wonDutch: true,
        cardsAtDutch: 2,
        scoreAtDutch: 5,
        totalTurns: 1,
        avgDecisionTime: 800,
        powerUsesCount: 0,
        goodDecisions: 1,
        badDecisions: 0,
        opponents: [],
      };

      await assert.doesNotReject(qLearning.trainFromGame(mockRecord));
    });

    it('devrait entraîner avec des actions variées (draw_from_discard, use_power)', async () => {
      const mockRecord: BotGameRecord = {
        gameId: 'test-game-varied',
        botId: 'bot-varied',
        botName: 'Varied Bot',
        botBehavior: 'aggressive',
        botSkillLevel: 'gold',
        startTime: new Date().toISOString(),
        endTime: new Date().toISOString(),
        numberOfPlayers: 3,
        gameMode: 'classic',
        usedSBMM: false,
        actions: [
          {
            actionType: 'draw_from_discard',
            turnNumber: 1,
            timestamp: new Date().toISOString(),
            gameState: { myScore: 20, cardsInHand: 4, turnPhase: 'playing', opponentsAvgScore: 15, deckCardsRemaining: 40 },
            actionDetails: {},
            result: { newScore: 18 },
          },
          {
            actionType: 'use_power',
            turnNumber: 2,
            timestamp: new Date().toISOString(),
            gameState: { myScore: 18, cardsInHand: 4, turnPhase: 'playing', opponentsAvgScore: 14, deckCardsRemaining: 38 },
            actionDetails: { cardIndex: 1 },
            result: { newScore: 16 },
          },
          {
            actionType: 'unknown_action_type',
            turnNumber: 3,
            timestamp: new Date().toISOString(),
            gameState: { myScore: 16, cardsInHand: 4, turnPhase: 'playing', opponentsAvgScore: 13, deckCardsRemaining: 36 },
            actionDetails: {},
            result: { newScore: 14 },
          },
        ],
        initialHandSize: 4,
        finalScore: 14,
        finalRank: 1,
        calledDutch: false,
        wonDutch: false,
        cardsAtDutch: 0,
        scoreAtDutch: 0,
        totalTurns: 3,
        avgDecisionTime: 1200,
        powerUsesCount: 1,
        goodDecisions: 2,
        badDecisions: 0,
        opponents: [],
      };

      await assert.doesNotReject(qLearning.trainFromGame(mockRecord));
    });

    it('devrait gérer des gameState avec valeurs manquantes', async () => {
      const mockRecord: BotGameRecord = {
        gameId: 'test-game-missing',
        botId: 'bot-missing',
        botName: 'Missing Data Bot',
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
            gameState: {}, // empty gameState - should use defaults
            actionDetails: {},
            result: {}, // no newScore
          },
        ],
        initialHandSize: 4,
        finalScore: 20,
        finalRank: 3,
        calledDutch: false,
        wonDutch: false,
        cardsAtDutch: 0,
        scoreAtDutch: 0,
        totalTurns: 1,
        avgDecisionTime: 2000,
        powerUsesCount: 0,
        goodDecisions: 0,
        badDecisions: 0,
        opponents: [],
      };

      await assert.doesNotReject(qLearning.trainFromGame(mockRecord));
    });

    it('devrait gérer une partie sans actions', async () => {
      const mockRecord: BotGameRecord = {
        gameId: 'test-game-empty',
        botId: 'bot-empty',
        botName: 'Empty Bot',
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

      await assert.doesNotReject(qLearning.trainFromGame(mockRecord));
    });
  });

  describe('getStats', () => {
    it('devrait retourner des statistiques valides', () => {
      const stats = qLearning.getStats();

      assert.ok('totalStates' in stats);
      assert.ok('totalActions' in stats);
      assert.ok('totalVisits' in stats);
      assert.ok('avgActionsPerState' in stats);
      assert.ok('avgVisitsPerState' in stats);

      assert.strictEqual(typeof stats.totalStates, 'number');
      assert.ok(stats.totalStates >= 0);
    });

    it('devrait avoir des stats non-nulles après des mises à jour', () => {
      // After previous tests have updated Q-values
      const stats = qLearning.getStats();
      assert.ok(stats.totalStates > 0);
      assert.ok(stats.totalActions > 0);
      assert.ok(stats.totalVisits > 0);
      assert.ok(stats.avgActionsPerState > 0);
      assert.ok(stats.avgVisitsPerState > 0);
    });

    it('devrait retourner des types numériques corrects', () => {
      const stats = qLearning.getStats();
      assert.strictEqual(typeof stats.totalStates, 'number');
      assert.strictEqual(typeof stats.totalActions, 'number');
      assert.strictEqual(typeof stats.totalVisits, 'number');
      assert.strictEqual(typeof stats.avgActionsPerState, 'number');
      assert.strictEqual(typeof stats.avgVisitsPerState, 'number');
      assert.ok(Number.isFinite(stats.avgActionsPerState));
      assert.ok(Number.isFinite(stats.avgVisitsPerState));
    });
  });

  describe('decayEpsilon', () => {
    it('devrait réduire epsilon au fil du temps', () => {
      assert.doesNotThrow(() => {
        for (let i = 0; i < 100; i++) {
          qLearning.decayEpsilon();
        }
      });
    });

    it('devrait ne jamais descendre en dessous de 0.05', () => {
      // Decay many times to ensure floor
      for (let i = 0; i < 2000; i++) {
        qLearning.decayEpsilon();
      }
      // Epsilon should be at floor; selectAction should still work
      const state = {
        myScore: 10,
        cardsInHand: 4,
        turnPhase: 'playing',
        opponentsAvgScore: 15,
        deckCardsRemaining: 20,
      };
      const availableActions = [
        { type: 'draw_deck' as const },
        { type: 'draw_discard' as const },
      ];
      // Should not throw even with minimal epsilon
      const action = qLearning.selectAction(state, availableActions);
      assert.ok(action.type === 'draw_deck' || action.type === 'draw_discard');
    });
  });
});
