import * as fs from 'fs/promises';
import * as path from 'path';

interface Personality {
  id: string;
  name: string;
  description: string;
  traits: {
    aggressiveness: number;
    caution: number;
    riskTolerance: number;
    patience: number;
    adaptability: number;
    bluffing: number;
    observation: number;
    calculation: number;
  };
  behaviors: {
    dutchThresholdMin: number;
    dutchThresholdMax: number;
    powerUsageRate: number;
    memoryAccuracy: number;
    decisionSpeed: number;
    preferredStrategy: string;
    reactsToOpponents: boolean;
    learningRate: number;
  };
  quirks: string[];
  voiceLines?: string[];
}

export class BotPersonalityService {
  private personalities: Map<string, Personality>;
  private dataDir: string;

  constructor() {
    this.personalities = new Map();
    this.dataDir = path.join(__dirname, '../../data/bot-learning/personalities');
    this.ensureDataDirectory();
    this.initializeDefaultPersonalities();
  }

  private async ensureDataDirectory() {
    try {
      const fsSync = require('fs');
      if (!fsSync.existsSync(this.dataDir)) {
        fsSync.mkdirSync(this.dataDir, { recursive: true });
      }
    } catch (error) {
      console.error('❌ Erreur création répertoire personalities:', error);
    }
  }

  /**
   * Initialise les personnalités par défaut
   */
  private initializeDefaultPersonalities() {
    const defaultPersonalities: Personality[] = [
      {
        id: 'the_shark',
        name: 'Marco',
        description: 'Joueur agressif qui aime prendre le contrôle',
        traits: {
          aggressiveness: 0.95,
          caution: 0.2,
          riskTolerance: 0.9,
          patience: 0.1,
          adaptability: 0.6,
          bluffing: 0.8,
          observation: 0.7,
          calculation: 0.5,
        },
        behaviors: {
          dutchThresholdMin: 18,
          dutchThresholdMax: 25,
          powerUsageRate: 0.9,
          memoryAccuracy: 0.7,
          decisionSpeed: 0.3,
          preferredStrategy: 'aggressive_dutch',
          reactsToOpponents: true,
          learningRate: 0.15,
        },
        quirks: [
          'Appelle Dutch même avec un score élevé pour intimider',
          'Utilise tous ses pouvoirs dès que possible',
          'Pioche toujours de la défausse si la carte est basse',
        ],
        voiceLines: [
          'Allez, on accélère',
          'Je prends les devants',
          'Dutch !',
        ],
      },
      {
        id: 'the_professor',
        name: 'Sophie',
        description: 'Joueuse méthodique qui réfléchit avant d\'agir',
        traits: {
          aggressiveness: 0.3,
          caution: 0.9,
          riskTolerance: 0.3,
          patience: 0.95,
          adaptability: 0.8,
          bluffing: 0.4,
          observation: 0.95,
          calculation: 0.98,
        },
        behaviors: {
          dutchThresholdMin: 8,
          dutchThresholdMax: 12,
          powerUsageRate: 0.6,
          memoryAccuracy: 0.95,
          decisionSpeed: 0.9,
          preferredStrategy: 'optimal_calculation',
          reactsToOpponents: true,
          learningRate: 0.08,
        },
        quirks: [
          'Mémorise toutes les cartes jouées',
          'Calcule les probabilités avant chaque action',
          'N\'appelle Dutch que quand c\'est mathématiquement optimal',
        ],
        voiceLines: [
          'Laisse-moi réfléchir',
          'Hmm, intéressant',
          'Ça devrait marcher',
        ],
      },
      {
        id: 'the_gambler',
        name: 'Alex',
        description: 'Joueur imprévisible qui aime tenter sa chance',
        traits: {
          aggressiveness: 0.7,
          caution: 0.2,
          riskTolerance: 0.95,
          patience: 0.3,
          adaptability: 0.9,
          bluffing: 0.9,
          observation: 0.5,
          calculation: 0.4,
        },
        behaviors: {
          dutchThresholdMin: 12,
          dutchThresholdMax: 22,
          powerUsageRate: 0.7,
          memoryAccuracy: 0.6,
          decisionSpeed: 0.2,
          preferredStrategy: 'high_variance',
          reactsToOpponents: false,
          learningRate: 0.12,
        },
        quirks: [
          'Prend des décisions aléatoires pour déstabiliser',
          'Peut appeler Dutch très tôt ou très tard',
          'Change de stratégie en cours de partie',
        ],
        voiceLines: [
          'Allez, on tente',
          'Pourquoi pas ?',
          'On verra bien',
        ],
      },
      {
        id: 'the_turtle',
        name: 'Emma',
        description: 'Joueuse prudente qui prend son temps',
        traits: {
          aggressiveness: 0.2,
          caution: 0.95,
          riskTolerance: 0.15,
          patience: 0.9,
          adaptability: 0.4,
          bluffing: 0.2,
          observation: 0.7,
          calculation: 0.7,
        },
        behaviors: {
          dutchThresholdMin: 6,
          dutchThresholdMax: 10,
          powerUsageRate: 0.4,
          memoryAccuracy: 0.8,
          decisionSpeed: 0.7,
          preferredStrategy: 'minimize_risk',
          reactsToOpponents: false,
          learningRate: 0.05,
        },
        quirks: [
          'Pioche toujours du deck pour éviter les surprises',
          'Remplace ses cartes une par une',
          'Attend le moment parfait pour Dutch',
        ],
        voiceLines: [
          'Pas si vite',
          'Je préfère être sûre',
          'Doucement',
        ],
      },
      {
        id: 'the_chameleon',
        name: 'Lucas',
        description: 'Joueur qui s\'adapte au style des autres',
        traits: {
          aggressiveness: 0.5,
          caution: 0.5,
          riskTolerance: 0.5,
          patience: 0.6,
          adaptability: 0.98,
          bluffing: 0.7,
          observation: 0.9,
          calculation: 0.8,
        },
        behaviors: {
          dutchThresholdMin: 10,
          dutchThresholdMax: 18,
          powerUsageRate: 0.6,
          memoryAccuracy: 0.85,
          decisionSpeed: 0.5,
          preferredStrategy: 'adaptive',
          reactsToOpponents: true,
          learningRate: 0.2,
        },
        quirks: [
          'Copie le style du joueur le plus performant',
          'Ajuste sa stratégie toutes les 3 tours',
          'Devient agressif contre des joueurs défensifs et vice-versa',
        ],
        voiceLines: [
          'Je change de stratégie',
          'Voyons voir...',
          'Intéressant',
        ],
      },
      {
        id: 'the_rookie',
        name: 'Léa',
        description: 'Joueuse qui découvre encore le jeu',
        traits: {
          aggressiveness: 0.4,
          caution: 0.6,
          riskTolerance: 0.4,
          patience: 0.5,
          adaptability: 0.7,
          bluffing: 0.3,
          observation: 0.4,
          calculation: 0.3,
        },
        behaviors: {
          dutchThresholdMin: 14,
          dutchThresholdMax: 20,
          powerUsageRate: 0.3,
          memoryAccuracy: 0.5,
          decisionSpeed: 0.6,
          preferredStrategy: 'learning',
          reactsToOpponents: false,
          learningRate: 0.25,
        },
        quirks: [
          'Fait parfois des erreurs évidentes',
          'Oublie des cartes vues',
          'S\'améliore rapidement au fil de la partie',
        ],
        voiceLines: [
          'Euh... voyons',
          'Je pense que...',
          'Ah d\'accord',
        ],
      },
      {
        id: 'the_veteran',
        name: 'Thomas',
        description: 'Joueur expérimenté qui connaît bien le jeu',
        traits: {
          aggressiveness: 0.6,
          caution: 0.7,
          riskTolerance: 0.6,
          patience: 0.7,
          adaptability: 0.8,
          bluffing: 0.6,
          observation: 0.85,
          calculation: 0.85,
        },
        behaviors: {
          dutchThresholdMin: 10,
          dutchThresholdMax: 15,
          powerUsageRate: 0.7,
          memoryAccuracy: 0.9,
          decisionSpeed: 0.5,
          preferredStrategy: 'balanced_optimal',
          reactsToOpponents: true,
          learningRate: 0.1,
        },
        quirks: [
          'Sait quand être agressif et quand être prudent',
          'Lit bien le jeu des adversaires',
          'Optimise chaque décision',
        ],
        voiceLines: [
          'Je connais ça',
          'Vu et revu',
          'Comme d\'hab',
        ],
      },
      {
        id: 'the_psycho',
        name: 'Maxime',
        description: 'Joueur complètement imprévisible',
        traits: {
          aggressiveness: 0.85,
          caution: 0.1,
          riskTolerance: 0.99,
          patience: 0.05,
          adaptability: 0.5,
          bluffing: 0.95,
          observation: 0.6,
          calculation: 0.2,
        },
        behaviors: {
          dutchThresholdMin: 5,
          dutchThresholdMax: 30,
          powerUsageRate: 0.95,
          memoryAccuracy: 0.4,
          decisionSpeed: 0.1,
          preferredStrategy: 'chaos',
          reactsToOpponents: true,
          learningRate: 0.3,
        },
        quirks: [
          'Peut appeler Dutch avec n\'importe quel score',
          'Utilise les pouvoirs de manière chaotique',
          'Déstabilise complètement les adversaires',
        ],
        voiceLines: [
          'Haha !',
          'Et hop !',
          'Surprise',
        ],
      },
    ];

    for (const personality of defaultPersonalities) {
      this.personalities.set(personality.id, personality);
    }

    this.saveAllPersonalities();
  }

  /**
   * Récupère une personnalité par son ID
   */
  getPersonality(id: string): Personality | undefined {
    return this.personalities.get(id);
  }

  /**
   * Liste toutes les personnalités disponibles
   */
  getAllPersonalities(): Personality[] {
    return Array.from(this.personalities.values());
  }

  /**
   * Crée une nouvelle personnalité personnalisée
   */
  async createCustomPersonality(personality: Personality): Promise<void> {
    this.personalities.set(personality.id, personality);
    await this.savePersonality(personality);
    console.log(`✅ Personnalité créée: ${personality.name}`);
  }

  /**
   * Convertit une personnalité en paramètres de bot
   */
  personalityToBotParameters(personality: Personality): Record<string, any> {
    return {
      aggressiveness: personality.traits.aggressiveness,
      caution: personality.traits.caution,
      dutchThreshold: Math.round(
        (personality.behaviors.dutchThresholdMin + personality.behaviors.dutchThresholdMax) / 2
      ),
      dutchThresholdVariance: personality.behaviors.dutchThresholdMax - personality.behaviors.dutchThresholdMin,
      powerUsageRate: personality.behaviors.powerUsageRate,
      memoryAccuracy: personality.behaviors.memoryAccuracy,
      riskTolerance: personality.traits.riskTolerance,
      patience: personality.traits.patience,
      adaptability: personality.traits.adaptability,
      bluffing: personality.traits.bluffing,
      observation: personality.traits.observation,
      calculation: personality.traits.calculation,
      decisionSpeed: personality.behaviors.decisionSpeed,
      preferredStrategy: personality.behaviors.preferredStrategy,
      reactsToOpponents: personality.behaviors.reactsToOpponents,
      learningRate: personality.behaviors.learningRate,
      quirks: personality.quirks,
      voiceLines: personality.voiceLines,
    };
  }

  /**
   * Sélectionne une personnalité aléatoire
   */
  getRandomPersonality(): Personality {
    const personalities = Array.from(this.personalities.values());
    return personalities[Math.floor(Math.random() * personalities.length)];
  }

  /**
   * Sélectionne une personnalité basée sur le niveau de difficulté
   */
  getPersonalityByDifficulty(difficulty: 'easy' | 'medium' | 'hard'): Personality {
    const personalities = Array.from(this.personalities.values());
    
    switch (difficulty) {
      case 'easy':
        return personalities.find(p => p.id === 'the_rookie') || personalities[0];
      case 'medium':
        return personalities.find(p => p.id === 'the_chameleon') || personalities[0];
      case 'hard':
        return personalities.find(p => p.id === 'the_professor') || personalities[0];
      default:
        return this.getRandomPersonality();
    }
  }

  /**
   * Crée une équipe équilibrée de personnalités
   */
  createBalancedTeam(count: number): Personality[] {
    const team: Personality[] = [];
    const personalities = Array.from(this.personalities.values());
    
    const categories = {
      aggressive: personalities.filter(p => p.traits.aggressiveness > 0.7),
      defensive: personalities.filter(p => p.traits.caution > 0.7),
      balanced: personalities.filter(p => 
        p.traits.aggressiveness > 0.4 && p.traits.aggressiveness < 0.7 &&
        p.traits.caution > 0.4 && p.traits.caution < 0.7
      ),
    };
    
    for (let i = 0; i < count; i++) {
      let category: Personality[];
      if (i % 3 === 0) category = categories.aggressive;
      else if (i % 3 === 1) category = categories.defensive;
      else category = categories.balanced;
      
      if (category.length > 0) {
        const personality = category[Math.floor(Math.random() * category.length)];
        team.push(personality);
      } else {
        team.push(this.getRandomPersonality());
      }
    }
    
    return team;
  }

  /**
   * Sauvegarde une personnalité
   */
  private async savePersonality(personality: Personality) {
    try {
      const filepath = path.join(this.dataDir, `${personality.id}.json`);
      await fs.writeFile(filepath, JSON.stringify(personality, null, 2));
    } catch (error) {
      console.error(`❌ Erreur sauvegarde personnalité ${personality.id}:`, error);
    }
  }

  /**
   * Sauvegarde toutes les personnalités
   */
  private async saveAllPersonalities() {
    for (const personality of this.personalities.values()) {
      await this.savePersonality(personality);
    }
    console.log(`✅ ${this.personalities.size} personnalités sauvegardées`);
  }

  /**
   * Charge toutes les personnalités depuis le disque
   */
  async loadPersonalities() {
    try {
      const files = await fs.readdir(this.dataDir);
      
      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        
        const data = await fs.readFile(path.join(this.dataDir, file), 'utf-8');
        const personality: Personality = JSON.parse(data);
        this.personalities.set(personality.id, personality);
      }
      
      console.log(`✅ ${this.personalities.size} personnalités chargées`);
    } catch (error) {
      console.log('ℹ️ Initialisation des personnalités par défaut');
    }
  }
}
