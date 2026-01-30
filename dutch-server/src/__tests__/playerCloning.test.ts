import { PlayerCloningService } from '../services/PlayerCloningService';

describe('PlayerCloningService', () => {
  let cloningService: PlayerCloningService;

  beforeEach(() => {
    cloningService = new PlayerCloningService();
  });

  describe('analyzePlayerGames', () => {
    it('devrait analyser les parties d\'un joueur', async () => {
      const games = [
        {
          actions: [
            {
              actionType: 'draw_from_deck',
              decisionTime: 1000,
              gameState: { myScore: 15 },
              actionDetails: {},
            },
            {
              actionType: 'draw_from_discard',
              decisionTime: 1200,
              gameState: { myScore: 12 },
              actionDetails: {},
            },
            {
              actionType: 'replace_card',
              decisionTime: 800,
              gameState: { myScore: 10 },
              actionDetails: { cardIndex: 0 },
            },
          ],
          calledDutch: true,
          scoreAtDutch: 10,
        },
      ];

      const pattern = await cloningService.analyzePlayerGames('player1', games);

      expect(pattern).toHaveProperty('avgDecisionTime');
      expect(pattern).toHaveProperty('dutchThresholdPattern');
      expect(pattern).toHaveProperty('aggressivenessScore');
      expect(pattern).toHaveProperty('riskTakingScore');
      expect(pattern).toHaveProperty('powerUsageFrequency');
      expect(pattern).toHaveProperty('cardReplacementPattern');
      expect(pattern).toHaveProperty('preferredActions');
      expect(pattern).toHaveProperty('playStyle');

      expect(pattern.avgDecisionTime).toBeGreaterThan(0);
      expect(pattern.dutchThresholdPattern).toBe(10);
    });

    it('devrait lancer une erreur si aucune partie', async () => {
      await expect(
        cloningService.analyzePlayerGames('player1', [])
      ).rejects.toThrow('Aucune partie à analyser');
    });

    it('devrait déterminer le style de jeu correctement', async () => {
      const aggressiveGames = [
        {
          actions: Array(10).fill({
            actionType: 'draw_from_discard',
            decisionTime: 500,
            gameState: { myScore: 20 },
            actionDetails: {},
          }),
          calledDutch: false,
        },
      ];

      const pattern = await cloningService.analyzePlayerGames('player1', aggressiveGames);
      expect(['aggressive', 'opportunistic']).toContain(pattern.playStyle);
    });
  });

  describe('createClone', () => {
    it('devrait créer un clone à partir des parties', async () => {
      const games = [
        {
          actions: [
            {
              actionType: 'draw_from_deck',
              decisionTime: 1000,
              gameState: { myScore: 15 },
              actionDetails: {},
            },
          ],
          calledDutch: false,
        },
      ];

      const clone = await cloningService.createClone('player1', 'Alice', games);

      expect(clone).toHaveProperty('playerId', 'player1');
      expect(clone).toHaveProperty('playerName', 'Alice');
      expect(clone).toHaveProperty('clonedBotId');
      expect(clone).toHaveProperty('gamesAnalyzed', 1);
      expect(clone).toHaveProperty('accuracy');
      expect(clone).toHaveProperty('pattern');

      expect(clone.clonedBotId).toContain('clone_player1_');
    });

    it('devrait calculer la précision selon le nombre de parties', async () => {
      const games = Array(3).fill({
        actions: [{ actionType: 'draw_from_deck', decisionTime: 1000, gameState: {}, actionDetails: {} }],
        calledDutch: false,
      });

      const clone = await cloningService.createClone('player1', 'Alice', games);
      expect(clone.accuracy).toBe(0.5); // < 5 parties = 50%
    });
  });

  describe('patternToBotParameters', () => {
    it('devrait convertir un pattern en paramètres de bot', () => {
      const pattern = {
        avgDecisionTime: 1500,
        dutchThresholdPattern: 12,
        aggressivenessScore: 0.7,
        riskTakingScore: 0.6,
        powerUsageFrequency: 0.5,
        cardReplacementPattern: [0.25, 0.25, 0.25, 0.25],
        preferredActions: new Map(),
        playStyle: 'aggressive' as const,
      };

      const params = cloningService.patternToBotParameters(pattern);

      expect(params).toHaveProperty('aggressiveness', 0.7);
      expect(params).toHaveProperty('caution', 0.4); // 1 - riskTakingScore
      expect(params).toHaveProperty('dutchThreshold', 12);
      expect(params).toHaveProperty('powerUsageRate', 0.5);
      expect(params).toHaveProperty('riskTolerance', 0.6);
      expect(params).toHaveProperty('decisionDelay', 1500);
      expect(params).toHaveProperty('playStyle', 'aggressive');
    });
  });

  describe('listClones', () => {
    it('devrait retourner une liste vide si aucun clone', async () => {
      const clones = await cloningService.listClones();
      expect(Array.isArray(clones)).toBe(true);
    });
  });

  describe('getClone', () => {
    it('devrait retourner null si le clone n\'existe pas', async () => {
      const clone = await cloningService.getClone('nonexistent');
      expect(clone).toBeNull();
    });
  });
});
