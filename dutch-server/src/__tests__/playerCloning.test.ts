import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
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

      assert.ok('avgDecisionTime' in pattern);
      assert.ok('dutchThresholdPattern' in pattern);
      assert.ok('aggressivenessScore' in pattern);
      assert.ok('riskTakingScore' in pattern);
      assert.ok('powerUsageFrequency' in pattern);
      assert.ok('cardReplacementPattern' in pattern);
      assert.ok('preferredActions' in pattern);
      assert.ok('playStyle' in pattern);

      assert.ok(pattern.avgDecisionTime > 0);
      assert.strictEqual(pattern.dutchThresholdPattern, 10);
    });

    it('devrait lancer une erreur si aucune partie', async () => {
      await assert.rejects(
        cloningService.analyzePlayerGames('player1', []),
        { message: 'Aucune partie à analyser' }
      );
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
      assert.ok(['aggressive', 'opportunistic'].includes(pattern.playStyle));
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

      assert.strictEqual(clone.playerId, 'player1');
      assert.strictEqual(clone.playerName, 'Alice');
      assert.ok('clonedBotId' in clone);
      assert.strictEqual(clone.gamesAnalyzed, 1);
      assert.ok('accuracy' in clone);
      assert.ok('pattern' in clone);

      assert.ok(clone.clonedBotId.includes('clone_player1_'));
    });

    it('devrait calculer la précision selon le nombre de parties', async () => {
      const games = Array(3).fill({
        actions: [{ actionType: 'draw_from_deck', decisionTime: 1000, gameState: {}, actionDetails: {} }],
        calledDutch: false,
      });

      const clone = await cloningService.createClone('player1', 'Alice', games);
      assert.strictEqual(clone.accuracy, 0.5); // < 5 parties = 50%
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

      assert.strictEqual(params.aggressiveness, 0.7);
      assert.strictEqual(params.caution, 0.4); // 1 - riskTakingScore
      assert.strictEqual(params.dutchThreshold, 12);
      assert.strictEqual(params.powerUsageRate, 0.5);
      assert.strictEqual(params.riskTolerance, 0.6);
      assert.strictEqual(params.decisionDelay, 1500);
      assert.strictEqual(params.playStyle, 'aggressive');
    });
  });

  describe('listClones', () => {
    it('devrait retourner une liste vide si aucun clone', async () => {
      const clones = await cloningService.listClones();
      assert.ok(Array.isArray(clones));
    });
  });

  describe('getClone', () => {
    it('devrait retourner null si le clone n\'existe pas', async () => {
      const clone = await cloningService.getClone('nonexistent');
      assert.strictEqual(clone, null);
    });
  });
});
