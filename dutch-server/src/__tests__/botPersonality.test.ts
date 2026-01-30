import { BotPersonalityService } from '../services/BotPersonalityService';

describe('BotPersonalityService', () => {
  let personalityService: BotPersonalityService;

  beforeEach(() => {
    personalityService = new BotPersonalityService();
  });

  describe('getAllPersonalities', () => {
    it('devrait retourner 8 personnalités par défaut', () => {
      const personalities = personalityService.getAllPersonalities();
      
      expect(personalities).toHaveLength(8);
      expect(personalities.every(p => p.id && p.name && p.description)).toBe(true);
    });

    it('devrait avoir des noms naturels', () => {
      const personalities = personalityService.getAllPersonalities();
      const names = personalities.map(p => p.name);
      
      expect(names).toContain('Marco');
      expect(names).toContain('Sophie');
      expect(names).toContain('Alex');
      expect(names).toContain('Emma');
      expect(names).toContain('Lucas');
      expect(names).toContain('Léa');
      expect(names).toContain('Thomas');
      expect(names).toContain('Maxime');
    });
  });

  describe('getPersonality', () => {
    it('devrait récupérer une personnalité par ID', () => {
      const marco = personalityService.getPersonality('the_shark');
      
      expect(marco).toBeDefined();
      expect(marco?.name).toBe('Marco');
      expect(marco?.traits.aggressiveness).toBeGreaterThan(0.9);
    });

    it('devrait retourner undefined pour un ID inexistant', () => {
      const personality = personalityService.getPersonality('nonexistent');
      expect(personality).toBeUndefined();
    });
  });

  describe('getRandomPersonality', () => {
    it('devrait retourner une personnalité aléatoire', () => {
      const personality = personalityService.getRandomPersonality();
      
      expect(personality).toBeDefined();
      expect(personality.id).toBeTruthy();
      expect(personality.name).toBeTruthy();
    });

    it('devrait retourner des personnalités différentes', () => {
      const personalities = new Set();
      
      for (let i = 0; i < 20; i++) {
        const p = personalityService.getRandomPersonality();
        personalities.add(p.id);
      }
      
      // Avec 20 tirages, on devrait avoir au moins 2 personnalités différentes
      expect(personalities.size).toBeGreaterThan(1);
    });
  });

  describe('getPersonalityByDifficulty', () => {
    it('devrait retourner Léa pour easy', () => {
      const personality = personalityService.getPersonalityByDifficulty('easy');
      expect(personality.name).toBe('Léa');
    });

    it('devrait retourner Lucas pour medium', () => {
      const personality = personalityService.getPersonalityByDifficulty('medium');
      expect(personality.name).toBe('Lucas');
    });

    it('devrait retourner Sophie pour hard', () => {
      const personality = personalityService.getPersonalityByDifficulty('hard');
      expect(personality.name).toBe('Sophie');
    });
  });

  describe('createBalancedTeam', () => {
    it('devrait créer une équipe équilibrée', () => {
      const team = personalityService.createBalancedTeam(3);
      
      expect(team).toHaveLength(3);
      expect(team.every(p => p.id && p.name)).toBe(true);
    });

    it('devrait mélanger agressifs, défensifs et équilibrés', () => {
      const team = personalityService.createBalancedTeam(6);
      
      const aggressive = team.filter(p => p.traits.aggressiveness > 0.7).length;
      const defensive = team.filter(p => p.traits.caution > 0.7).length;
      
      // On devrait avoir un mélange
      expect(aggressive).toBeGreaterThan(0);
      expect(defensive).toBeGreaterThan(0);
    });
  });

  describe('personalityToBotParameters', () => {
    it('devrait convertir une personnalité en paramètres', () => {
      const marco = personalityService.getPersonality('the_shark')!;
      const params = personalityService.personalityToBotParameters(marco);
      
      expect(params).toHaveProperty('aggressiveness');
      expect(params).toHaveProperty('caution');
      expect(params).toHaveProperty('dutchThreshold');
      expect(params).toHaveProperty('powerUsageRate');
      expect(params).toHaveProperty('riskTolerance');
      expect(params).toHaveProperty('preferredStrategy');
      
      expect(params.aggressiveness).toBe(marco.traits.aggressiveness);
      expect(params.dutchThreshold).toBeGreaterThan(0);
    });

    it('devrait calculer le seuil Dutch moyen', () => {
      const sophie = personalityService.getPersonality('the_professor')!;
      const params = personalityService.personalityToBotParameters(sophie);
      
      const expectedThreshold = (sophie.behaviors.dutchThresholdMin + sophie.behaviors.dutchThresholdMax) / 2;
      expect(params.dutchThreshold).toBe(expectedThreshold);
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
      expect(retrieved).toBeDefined();
      expect(retrieved?.name).toBe('Test Bot');
    });
  });

  describe('Validation des personnalités', () => {
    it('toutes les personnalités devraient avoir des traits valides', () => {
      const personalities = personalityService.getAllPersonalities();
      
      personalities.forEach(p => {
        expect(p.traits.aggressiveness).toBeGreaterThanOrEqual(0);
        expect(p.traits.aggressiveness).toBeLessThanOrEqual(1);
        expect(p.traits.caution).toBeGreaterThanOrEqual(0);
        expect(p.traits.caution).toBeLessThanOrEqual(1);
        expect(p.traits.riskTolerance).toBeGreaterThanOrEqual(0);
        expect(p.traits.riskTolerance).toBeLessThanOrEqual(1);
      });
    });

    it('toutes les personnalités devraient avoir des seuils Dutch cohérents', () => {
      const personalities = personalityService.getAllPersonalities();
      
      personalities.forEach(p => {
        expect(p.behaviors.dutchThresholdMin).toBeLessThanOrEqual(p.behaviors.dutchThresholdMax);
        expect(p.behaviors.dutchThresholdMin).toBeGreaterThanOrEqual(5);
        expect(p.behaviors.dutchThresholdMax).toBeLessThanOrEqual(30);
      });
    });

    it('toutes les personnalités devraient avoir des quirks et voiceLines', () => {
      const personalities = personalityService.getAllPersonalities();
      
      personalities.forEach(p => {
        expect(p.quirks.length).toBeGreaterThan(0);
        expect(p.voiceLines).toBeDefined();
        if (p.voiceLines) {
          expect(p.voiceLines.length).toBeGreaterThan(0);
        }
      });
    });
  });
});
