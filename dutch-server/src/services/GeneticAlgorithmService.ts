import { promises as fs } from 'node:fs';
import path from 'node:path';

interface BotGenome {
  botId: string;
  generation: number;
  genes: {
    aggressiveness: number;
    caution: number;
    riskTolerance: number;
    patience: number;
    dutchThreshold: number;
    powerUsageRate: number;
    memoryAccuracy: number;
    adaptability: number;
  };
  fitness: number;
  wins: number;
  losses: number;
  avgScore: number;
  mmr: number;
  parents?: [string, string];
  mutations: string[];
}

interface Generation {
  generationNumber: number;
  population: BotGenome[];
  avgFitness: number;
  bestFitness: number;
  bestBot: BotGenome;
  timestamp: string;
}

/**
 * Service d'évolution génétique pour optimiser les bots
 */
export class GeneticAlgorithmService {
  private dataDir: string;
  private currentGeneration: number;
  private population: BotGenome[];
  private populationSize: number;
  private mutationRate: number;
  private eliteSize: number;

  constructor() {
    this.dataDir = path.join(__dirname, '../../data/bot-learning/genetic');
    this.currentGeneration = 0;
    this.population = [];
    this.populationSize = 20; // 20 bots par génération
    this.mutationRate = 0.15; // 15% de chance de mutation
    this.eliteSize = 4; // Garder les 4 meilleurs
    this.ensureDataDirectory();
    this.loadGenerationSync();
  }

  private ensureDataDirectory() {
    try {
      const fsSync = require('node:fs');
      if (!fsSync.existsSync(this.dataDir)) {
        fsSync.mkdirSync(this.dataDir, { recursive: true });
      }
    } catch (error) {
      console.error('❌ Erreur création répertoire genetic:', error);
    }
  }

  /**
   * Initialise la première génération avec des bots aléatoires
   */
  async initializePopulation(): Promise<Generation> {
    console.log('🧬 Initialisation de la population génétique...');

    this.population = [];
    for (let i = 0; i < this.populationSize; i++) {
      const genome = this.createRandomGenome(i);
      this.population.push(genome);
    }

    this.currentGeneration = 1;
    const generation = this.createGenerationSnapshot();
    await this.saveGeneration(generation);

    console.log(`✅ Génération 1 créée avec ${this.populationSize} bots`);
    return generation;
  }

  /**
   * Crée un génome aléatoire
   */
  private createRandomGenome(index: number): BotGenome {
    return {
      botId: `gen1_bot${index}`,
      generation: 1,
      genes: {
        aggressiveness: Math.random(),
        caution: Math.random(),
        riskTolerance: Math.random(),
        patience: Math.random(),
        dutchThreshold: Math.random() * 20 + 5, // 5-25
        powerUsageRate: Math.random(),
        memoryAccuracy: Math.random() * 0.5 + 0.5, // 0.5-1.0
        adaptability: Math.random(),
      },
      fitness: 0,
      wins: 0,
      losses: 0,
      avgScore: 20,
      mmr: 1500,
      mutations: [],
    };
  }

  /**
   * Évalue la fitness d'un bot basée sur ses performances
   */
  calculateFitness(bot: BotGenome): number {
    const winRate = bot.wins / Math.max(1, bot.wins + bot.losses);
    const scoreBonus = (20 - bot.avgScore) / 20; // Meilleur score = plus de fitness
    const mmrBonus = (bot.mmr - 1500) / 1000; // MMR au-dessus de 1500 = bonus

    // Formule de fitness : 40% winrate, 30% score, 30% MMR
    const fitness = (winRate * 0.4) + (scoreBonus * 0.3) + (mmrBonus * 0.3);
    
    return Math.max(0, fitness);
  }

  /**
   * Sélectionne les parents pour la reproduction (sélection par tournoi)
   */
  private selectParents(): [BotGenome, BotGenome] {
    // Sélection par tournoi : prendre 4 bots aléatoires et garder les 2 meilleurs
    const tournament: BotGenome[] = [];
    for (let i = 0; i < 4; i++) {
      const randomBot = this.population[Math.floor(Math.random() * this.population.length)];
      tournament.push(randomBot);
    }

    tournament.sort((a, b) => b.fitness - a.fitness);
    return [tournament[0], tournament[1]];
  }

  /**
   * Croisement (crossover) de deux parents
   */
  private crossover(parent1: BotGenome, parent2: BotGenome, generation: number, index: number): BotGenome {
    const child: BotGenome = {
      botId: `gen${generation}_bot${index}`,
      generation,
      genes: {
        // Mélange aléatoire des gènes des parents
        aggressiveness: Math.random() < 0.5 ? parent1.genes.aggressiveness : parent2.genes.aggressiveness,
        caution: Math.random() < 0.5 ? parent1.genes.caution : parent2.genes.caution,
        riskTolerance: Math.random() < 0.5 ? parent1.genes.riskTolerance : parent2.genes.riskTolerance,
        patience: Math.random() < 0.5 ? parent1.genes.patience : parent2.genes.patience,
        dutchThreshold: Math.random() < 0.5 ? parent1.genes.dutchThreshold : parent2.genes.dutchThreshold,
        powerUsageRate: Math.random() < 0.5 ? parent1.genes.powerUsageRate : parent2.genes.powerUsageRate,
        memoryAccuracy: Math.random() < 0.5 ? parent1.genes.memoryAccuracy : parent2.genes.memoryAccuracy,
        adaptability: Math.random() < 0.5 ? parent1.genes.adaptability : parent2.genes.adaptability,
      },
      fitness: 0,
      wins: 0,
      losses: 0,
      avgScore: 15,
      mmr: (parent1.mmr + parent2.mmr) / 2,
      parents: [parent1.botId, parent2.botId],
      mutations: [],
    };

    return child;
  }

  /**
   * Mutation aléatoire d'un génome
   */
  private mutate(bot: BotGenome): BotGenome {
    const mutated = { ...bot, genes: { ...bot.genes }, mutations: [...bot.mutations] };

    // Chaque gène a une chance de muter
    const genes = Object.keys(mutated.genes) as (keyof typeof mutated.genes)[];
    
    for (const gene of genes) {
      if (Math.random() < this.mutationRate) {
        const currentValue = mutated.genes[gene];
        
        // Mutation : +/- 20% de la valeur actuelle
        const mutationAmount = (Math.random() - 0.5) * 0.4 * currentValue;
        let newValue = currentValue + mutationAmount;

        // Contraintes selon le gène
        if (gene === 'dutchThreshold') {
          newValue = Math.max(5, Math.min(25, newValue));
        } else if (gene === 'memoryAccuracy') {
          newValue = Math.max(0.5, Math.min(1, newValue));
        } else {
          newValue = Math.max(0, Math.min(1, newValue));
        }

        mutated.genes[gene] = newValue;
        mutated.mutations.push(`${gene}: ${currentValue.toFixed(2)} → ${newValue.toFixed(2)}`);
      }
    }

    return mutated;
  }

  /**
   * Évolue vers la prochaine génération
   */
  async evolveGeneration(): Promise<Generation> {
    if (this.population.length === 0) {
      throw new Error('Population vide. Initialisez d\'abord avec initializePopulation()');
    }

    console.log(`🧬 Évolution vers la génération ${this.currentGeneration + 1}...`);

    // 1. Calculer la fitness de tous les bots
    this.population.forEach(bot => {
      bot.fitness = this.calculateFitness(bot);
    });

    // 2. Trier par fitness
    this.population.sort((a, b) => b.fitness - a.fitness);

    // 3. Garder l'élite (les meilleurs)
    const elite = this.population.slice(0, this.eliteSize);
    console.log(`  🏆 Élite conservée: ${elite.length} meilleurs bots`);

    // 4. Créer la nouvelle génération
    const newGeneration: BotGenome[] = [...elite];
    const nextGenNumber = this.currentGeneration + 1;

    // 5. Remplir le reste avec des enfants
    while (newGeneration.length < this.populationSize) {
      const [parent1, parent2] = this.selectParents();
      let child = this.crossover(parent1, parent2, nextGenNumber, newGeneration.length);
      
      // Appliquer des mutations
      child = this.mutate(child);
      
      newGeneration.push(child);
    }

    this.population = newGeneration;
    this.currentGeneration = nextGenNumber;

    const generation = this.createGenerationSnapshot();
    await this.saveGeneration(generation);

    console.log(`✅ Génération ${this.currentGeneration} créée`);
    console.log(`  📊 Fitness moyenne: ${generation.avgFitness.toFixed(3)}`);
    console.log(`  🌟 Meilleur bot: ${generation.bestBot.botId} (fitness: ${generation.bestFitness.toFixed(3)})`);

    return generation;
  }

  /**
   * Met à jour les stats d'un bot après une partie
   */
  updateBotStats(botId: string, won: boolean, score: number, newMMR: number) {
    const bot = this.population.find(b => b.botId === botId);
    if (!bot) return;

    if (won) {
      bot.wins++;
    } else {
      bot.losses++;
    }

    // Moyenne mobile du score
    const totalGames = bot.wins + bot.losses;
    bot.avgScore = (bot.avgScore * (totalGames - 1) + score) / totalGames;
    bot.mmr = newMMR;

    // Recalculer la fitness
    bot.fitness = this.calculateFitness(bot);
  }

  /**
   * Récupère le meilleur bot de la génération actuelle
   */
  getBestBot(): BotGenome | undefined {
    if (this.population.length === 0) return undefined;
    
    return this.population.reduce((best, current) =>
      current.fitness > best.fitness ? current : best
    , this.population[0]);
  }

  /**
   * Récupère toute la population
   */
  getPopulation(): BotGenome[] {
    return [...this.population];
  }

  /**
   * Récupère les stats de l'évolution
   */
  getStats() {
    const avgFitness = this.population.length > 0
      ? this.population.reduce((sum, bot) => sum + bot.fitness, 0) / this.population.length
      : 0;

    const bestBot = this.getBestBot();

    return {
      currentGeneration: this.currentGeneration,
      populationSize: this.population.length,
      avgFitness,
      bestFitness: bestBot?.fitness || 0,
      bestBotId: bestBot?.botId || 'none',
      totalMutations: this.population.reduce((sum, bot) => sum + bot.mutations.length, 0),
    };
  }

  /**
   * Crée un snapshot de la génération actuelle
   */
  private createGenerationSnapshot(): Generation {
    const avgFitness = this.population.reduce((sum, bot) => sum + bot.fitness, 0) / this.population.length;
    const bestBot = this.getBestBot()!;

    return {
      generationNumber: this.currentGeneration,
      population: this.population,
      avgFitness,
      bestFitness: bestBot.fitness,
      bestBot,
      timestamp: new Date().toISOString(),
    };
  }

  /**
   * Sauvegarde une génération
   */
  private async saveGeneration(generation: Generation) {
    try {
      const filePath = path.join(this.dataDir, `generation_${generation.generationNumber}.json`);
      await fs.writeFile(filePath, JSON.stringify(generation, null, 2));
    } catch (error) {
      console.error(`❌ Erreur sauvegarde génération ${generation.generationNumber}:`, error);
    }
  }

  /**
   * Charge la dernière génération
   */
  private loadGenerationSync() {
    try {
      const fsSync = require('node:fs');
      const files: string[] = fsSync.readdirSync(this.dataDir);
      const genFiles = files.filter((f: string) => f.startsWith('generation_') && f.endsWith('.json'));

      if (genFiles.length === 0) {
        console.log('ℹ️ Aucune génération existante');
        return;
      }

      // Trier pour avoir la dernière génération
      genFiles.sort((a: string, b: string) => {
        const numA = Number.parseInt(/\d+/.exec(a)?.[0] || '0');
        const numB = Number.parseInt(/\d+/.exec(b)?.[0] || '0');
        return numB - numA;
      });

      const latestFile = genFiles[0];
      const filePath = path.join(this.dataDir, latestFile);
      const data = fsSync.readFileSync(filePath, 'utf-8');
      const generation: Generation = JSON.parse(data);

      this.currentGeneration = generation.generationNumber;
      this.population = generation.population;

      console.log(`✅ Génération ${this.currentGeneration} chargée (${this.population.length} bots)`);
    } catch {
      console.log('ℹ️ Erreur chargement génération');
    }
  }
}
