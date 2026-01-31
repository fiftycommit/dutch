import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import { BotPersonalityService } from '../services/BotPersonalityService';

describe('BotPersonalityService', () => {
  let personalityService: BotPersonalityService;

  beforeEach(() => {
    personalityService = new BotPersonalityService();
  });

  describe('getAllPersonalities', () => {
    it('devrait retourner 8 personnalités par défaut', () => {
      const personalities = personalityService.getAllPersonalities();
      
      assert.strictEqual(personalities.length, 8);
      assert.ok(personalities.every(p => p.id && p.name && p.description));
    });

    it('devrait avoir des noms naturels', () => {
      const personalities = personalityService.getAllPersonalities();
      const names = personalities.map(p => p.name);
      
      assert.ok(names.includes('Marco'));
      assert.ok(names.includes('Sophie'));
      assert.ok(names.includes('Alex'));
      assert.ok(names.includes('Emma'));
      assert.ok(names.includes('Lucas'));
      assert.ok(names.includes('Léa'));
      assert.ok(names.includes('Thomas'));
      assert.ok(names.includes('Maxime'));
    });
  });

  describe('getPersonality', () => {
    it('devrait récupérer une personnalité par ID', () => {
      const marco = personalityService.getPersonality('the_shark');
      
      assert.ok(marco !== undefined);
      assert.strictEqual(marco?.name, 'Marco');
      assert.ok((marco?.traits.aggressiveness ?? 0) > 0.9);
    });

    it('devrait retourner undefined pour un ID inexistant', () => {
      const personality = personalityService.getPersonality('nonexistent');
      assert.strictEqual(personality, undefined);
    });
  });

  describe('getRandomPersonality', () => {
    it('devrait retourner une personnalité aléatoire', () => {
      const personality = personalityService.getRandomPersonality();
      
      assert.ok(personality !== undefined);
      assert.ok(personality.id);
      assert.ok(personality.name);
    });

    it('devrait retourner des personnalités différentes', () => {
      const personalities = new Set<string>();
      
      for (let i = 0; i < 20; i++) {
        const p = personalityService.getRandomPersonality();
        personalities.add(p.id);
      }
      
      // Avec 20 tirages, on devrait avoir au moins 2 personnalités différentes
      assert.ok(personalities.size > 1);
    });
  });

  describe('getPersonalityByDifficulty', () => {
    it('devrait retourner Léa pour easy', () => {
      const personality = personalityService.getPersonalityByDifficulty('easy');
      assert.strictEqual(personality.name, 'Léa');
    });

    it('devrait retourner Lucas pour medium', () => {
      const personality = personalityService.getPersonalityByDifficulty('medium');
      assert.strictEqual(personality.name, 'Lucas');
    });

    it('devrait retourner Sophie pour hard', () => {
      const personality = personalityService.getPersonalityByDifficulty('hard');
      assert.strictEqual(personality.name, 'Sophie');
    });
  });

  describe('createBalancedTeam', () => {
    it('devrait créer une équipe équilibrée', () => {
      const team = personalityService.createBalancedTeam(3);
      
      assert.strictEqual(team.length, 3);
      assert.ok(team.every(p => p.id && p.name));
    });

    it('devrait mélanger agressifs, défensifs et équilibrés', () => {
      const team = personalityService.createBalancedTeam(6);
      
      const aggressive = team.filter(p => p.traits.aggressiveness > 0.7).length;
      const defensive = team.filter(p => p.traits.caution > 0.7).length;
      
      // On devrait avoir un mélange
      assert.ok(aggressive > 0);
      assert.ok(defensive > 0);
    });
  });

  describe('personalityToBotParameters', () => {
    it('devrait convertir une personnalité en paramètres', () => {
      const marco = personalityService.getPersonality('the_shark')!;
      const params = personalityService.personalityToBotParameters(marco);
      
      assert.ok('aggressiveness' in params);
      assert.ok('caution' in params);
      assert.ok('dutchThreshold' in params);
      assert.ok('powerUsageRate' in params);
      assert.ok('riskTolerance' in params);
      assert.ok('preferredStrategy' in params);
      
      assert.strictEqual(params.aggressiveness, marco.traits.aggressiveness);
      assert.ok(params.dutchThreshold > 0);
    });

    it('devrait calculer le seuil Dutch moyen', () => {
      const sophie = personalityService.getPersonality('the_professor')!;
      const params = personalityService.personalityToBotParameters(sophie);
      
      const expectedThreshold = (sophie.behaviors.dutchThresholdMin + sophie.behaviors.dutchThresholdMax) / 2;
      assert.strictEqual(params.dutchThreshold, expectedThreshold);
    });
  });

  describe('createCustomPersonality', () => {
    it('devrait créer une personnalité personnalisée', async () => {
      const customPersonality = {
        id: 'test_custom',
        name: 'Test Bot',
        description: 'Un bot de test',
        traits: {
          aggressiveness: 0.5,
          caution: 0.5,
          riskTolerance: 0.5,
          patience: 0.5,
          adaptability: 0.5,
          bluffing: 0.5,
          observation: 0.5,
          calculation: 0.5,
        },
        behaviors: {
          dutchThresholdMin: 10,
          dutchThresholdMax: 15,
          powerUsageRate: 0.5,
          memoryAccuracy: 0.7,
          decisionSpeed: 0.5,
          preferredStrategy: 'balanced',
          reactsToOpponents: true,
          learningRate: 0.1,
        },
        quirks: ['Test quirk'],
        voiceLines: ['Test line'],
      };

      await personalityService.createCustomPersonality(customPersonality);
      
      const retrieved = personalityService.getPersonality('test_custom');
      assert.ok(retrieved !== undefined);
      assert.strictEqual(retrieved?.name, 'Test Bot');
    });
  });

  describe('Validation des personnalités', () => {
    it('toutes les personnalités devraient avoir des traits valides', () => {
      const personalities = personalityService.getAllPersonalities();
      
      personalities.forEach(p => {
        assert.ok(p.traits.aggressiveness >= 0);
        assert.ok(p.traits.aggressiveness <= 1);
        assert.ok(p.traits.caution >= 0);
        assert.ok(p.traits.caution <= 1);
        assert.ok(p.traits.riskTolerance >= 0);
        assert.ok(p.traits.riskTolerance <= 1);
      });
    });

    it('toutes les personnalités devraient avoir des seuils Dutch cohérents', () => {
      const personalities = personalityService.getAllPersonalities();
      
      personalities.forEach(p => {
        assert.ok(p.behaviors.dutchThresholdMin <= p.behaviors.dutchThresholdMax);
        assert.ok(p.behaviors.dutchThresholdMin >= 5);
        assert.ok(p.behaviors.dutchThresholdMax <= 30);
      });
    });

    it('toutes les personnalités devraient avoir des quirks et voiceLines', () => {
      const personalities = personalityService.getAllPersonalities();
      
      personalities.forEach(p => {
        assert.ok(p.quirks.length > 0);
        assert.ok(p.voiceLines !== undefined);
        if (p.voiceLines) {
          assert.ok(p.voiceLines.length > 0);
        }
      });
    });
  });
});
