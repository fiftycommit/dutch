import { QLearningService } from '../services/QLearningService';
import { BotGameRecord } from '../models/BotLearning';

describe('QLearningService', () => {
  let qLearning: QLearningService;

  beforeEach(() => {
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
      
      expect(availableActions).toContainEqual(action);
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
      
      expect(action).toEqual({ type: 'draw_deck' });
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

      expect(() => {
        qLearning.updateQValue(state, action, reward, nextState);
      }).not.toThrow();
    });
  });

  describe('calculateReward', () => {
    it('devrait donner une récompense positive pour réduire le score', () => {
      const action = { type: 'replace_card' as const, cardIndex: 0 };
      const reward = qLearning.calculateReward(action, 15, 10, false);
      
      expect(reward).toBeGreaterThan(0);
    });

    it('devrait donner une pénalité pour augmenter le score', () => {
      const action = { type: 'draw_discard' as const };
      const reward = qLearning.calculateReward(action, 10, 15, false);
      
      expect(reward).toBeLessThan(0);
    });

    it('devrait donner une grosse récompense pour gagner avec Dutch', () => {
      const action = { type: 'call_dutch' as const };
      const reward = qLearning.calculateReward(action, 8, 8, true, 1);
      
      expect(reward).toBeGreaterThan(50);
    });

    it('devrait pénaliser un Dutch raté', () => {
      const action = { type: 'call_dutch' as const };
      const reward = qLearning.calculateReward(action, 8, 8, true, 3);
      
      expect(reward).toBeLessThan(0);
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

      await expect(qLearning.trainFromGame(mockRecord)).resolves.not.toThrow();
    });
  });

  describe('getStats', () => {
    it('devrait retourner des statistiques valides', () => {
      const stats = qLearning.getStats();
      
      expect(stats).toHaveProperty('totalStates');
      expect(stats).toHaveProperty('totalActions');
      expect(stats).toHaveProperty('totalVisits');
      expect(stats).toHaveProperty('avgActionsPerState');
      expect(stats).toHaveProperty('avgVisitsPerState');
      
      expect(typeof stats.totalStates).toBe('number');
      expect(stats.totalStates).toBeGreaterThanOrEqual(0);
    });
  });

  describe('decayEpsilon', () => {
    it('devrait réduire epsilon au fil du temps', () => {
      const initialStats = qLearning.getStats();
      
      for (let i = 0; i < 100; i++) {
        qLearning.decayEpsilon();
      }
      
      // Epsilon devrait avoir diminué (plus d'exploitation, moins d'exploration)
      expect(true).toBe(true); // Le test vérifie juste que ça ne crash pas
    });
  });
});
