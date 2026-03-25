import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import { BotGameRecord, BotAction } from '../models/BotLearning';

interface NetworkLayer {
  weights: number[][];
  biases: number[];
}

interface NeuralNetwork {
  layers: NetworkLayer[];
  inputSize: number;
  hiddenSizes: number[];
  outputSize: number;
}

interface TrainingData {
  input: number[];
  output: number[];
}

export class NeuralNetworkService {
  private network: NeuralNetwork;
  private learningRate: number = 0.01;
  private dataDir: string;

  constructor() {
    this.dataDir = path.join(__dirname, '../../data/bot-learning/neural');
    this.ensureDataDirectory();

    // Architecture du réseau: 15 inputs -> 32 -> 16 -> 8 outputs
    this.network = this.createNetwork(15, [32, 16], 8);
    this.loadNetworkSync();
  }

  private ensureDataDirectory() {
    try {
      const fsSync = require('node:fs');
      if (!fsSync.existsSync(this.dataDir)) {
        fsSync.mkdirSync(this.dataDir, { recursive: true });
      }
    } catch (error) {
      console.error('❌ Erreur création répertoire neural:', error instanceof Error ? error.message : String(error));
    }
  }

  /**
   * Crée un nouveau réseau de neurones
   */
  private createNetwork(inputSize: number, hiddenSizes: number[], outputSize: number): NeuralNetwork {
    const layers: NetworkLayer[] = [];
    const sizes = [inputSize, ...hiddenSizes, outputSize];
    
    for (let i = 0; i < sizes.length - 1; i++) {
      const inputCount = sizes[i];
      const outputCount = sizes[i + 1];
      
      const weights: number[][] = [];
      for (let j = 0; j < outputCount; j++) {
        const row: number[] = [];
        for (let k = 0; k < inputCount; k++) {
          // Initialisation Xavier
          row.push((Math.random() - 0.5) * 2 * Math.sqrt(6 / (inputCount + outputCount)));
        }
        weights.push(row);
      }
      
      const biases = new Array(outputCount).fill(0).map(() => (Math.random() - 0.5) * 0.1);
      
      layers.push({ weights, biases });
    }
    
    return {
      layers,
      inputSize,
      hiddenSizes,
      outputSize,
    };
  }

  /**
   * Fonction d'activation ReLU
   */
  private relu(x: number): number {
    return Math.max(0, x);
  }

  /**
   * Dérivée de ReLU
   */
  private reluDerivative(x: number): number {
    return x > 0 ? 1 : 0;
  }

  /**
   * Fonction d'activation Softmax
   */
  private softmax(values: number[]): number[] {
    const max = Math.max(...values);
    const exps = values.map(v => Math.exp(v - max));
    const sum = exps.reduce((a, b) => a + b, 0);
    return exps.map(e => e / sum);
  }

  /**
   * Forward pass du réseau
   */
  private forward(input: number[]): { outputs: number[][], activations: number[][] } {
    const outputs: number[][] = [input];
    const activations: number[][] = [input];
    
    for (let i = 0; i < this.network.layers.length; i++) {
      const layer = this.network.layers[i];
      const prevActivation = activations[i];
      const output: number[] = [];
      
      for (let j = 0; j < layer.weights.length; j++) {
        let sum = layer.biases[j];
        for (let k = 0; k < prevActivation.length; k++) {
          sum += layer.weights[j][k] * prevActivation[k];
        }
        output.push(sum);
      }
      
      outputs.push(output);
      
      // Activation: ReLU pour les couches cachées, Softmax pour la sortie
      if (i === this.network.layers.length - 1) {
        activations.push(this.softmax(output));
      } else {
        activations.push(output.map(v => this.relu(v)));
      }
    }
    
    return { outputs, activations };
  }

  /**
   * Backward pass et mise à jour des poids
   */
  private backward(
    input: number[],
    target: number[],
    outputs: number[][],
    activations: number[][]
  ) {
    const deltas: number[][] = [];
    
    // Calculer le delta de la couche de sortie
    const outputDelta: number[] = [];
    for (let i = 0; i < activations[activations.length - 1].length; i++) {
      outputDelta.push(activations[activations.length - 1][i] - target[i]);
    }
    deltas.unshift(outputDelta);
    
    // Backpropagation pour les couches cachées
    for (let i = this.network.layers.length - 2; i >= 0; i--) {
      const layer = this.network.layers[i + 1];
      const delta: number[] = [];
      
      for (let j = 0; j < layer.weights[0].length; j++) {
        let error = 0;
        for (let k = 0; k < layer.weights.length; k++) {
          error += layer.weights[k][j] * deltas[0][k];
        }
        delta.push(error * this.reluDerivative(outputs[i + 1][j]));
      }
      
      deltas.unshift(delta);
    }
    
    // Mise à jour des poids et biais
    for (let i = 0; i < this.network.layers.length; i++) {
      const layer = this.network.layers[i];
      const delta = deltas[i];
      const activation = activations[i];
      
      for (let j = 0; j < layer.weights.length; j++) {
        for (let k = 0; k < layer.weights[j].length; k++) {
          layer.weights[j][k] -= this.learningRate * delta[j] * activation[k];
        }
        layer.biases[j] -= this.learningRate * delta[j];
      }
    }
  }

  /**
   * Entraîne le réseau sur un batch de données
   */
  train(trainingData: TrainingData[]) {
    for (const data of trainingData) {
      const { outputs, activations } = this.forward(data.input);
      this.backward(data.input, data.output, outputs, activations);
    }
  }

  /**
   * Prédit l'action à prendre
   */
  predict(input: number[]): number[] {
    const { activations } = this.forward(input);
    return activations[activations.length - 1];
  }

  /**
   * Convertit l'état du jeu en vecteur d'entrée
   */
  private gameStateToInput(gameState: any, action: BotAction): number[] {
    return [
      // Score normalisé (0-1)
      (gameState.myScore || 0) / 100,
      // Nombre de cartes (0-1)
      (gameState.cardsInHand || 4) / 4,
      // Score moyen des adversaires (0-1)
      (gameState.opponentsAvgScore || 0) / 100,
      // Cartes restantes dans le deck (0-1)
      (gameState.deckCardsRemaining || 20) / 52,
      // Phase de jeu (one-hot encoding)
      gameState.turnPhase === 'start' ? 1 : 0,
      gameState.turnPhase === 'playing' ? 1 : 0,
      gameState.turnPhase === 'end' ? 1 : 0,
      // Numéro du tour (0-1)
      (action.turnNumber || 0) / 50,
      // A appelé Dutch
      gameState.calledDutch ? 1 : 0,
      // Nombre de pouvoirs utilisés (0-1)
      (gameState.powerUsesCount || 0) / 10,
      // Score à Dutch (0-1)
      (gameState.scoreAtDutch || 0) / 100,
      // Rang actuel estimé (0-1)
      (gameState.estimatedRank || 2) / 4,
      // Cartes visibles des adversaires (0-1)
      (gameState.visibleOpponentCards || 0) / 16,
      // Différence de score avec le leader (0-1, peut être négatif)
      Math.max(-1, Math.min(1, (gameState.scoreVsLeader || 0) / 50)),
      // Temps restant estimé (0-1)
      (gameState.estimatedTurnsLeft || 10) / 50,
    ];
  }

  /**
   * Convertit une action en vecteur de sortie (one-hot)
   */
  private actionToOutput(actionType: string): number[] {
    const actions = [
      'draw_from_deck',
      'draw_from_discard',
      'replace_card',
      'call_dutch',
      'use_power_peek',
      'use_power_swap',
      'use_power_steal',
      'pass',
    ];
    
    const output = new Array(8).fill(0);
    const index = actions.indexOf(actionType);
    if (index !== -1) {
      output[index] = 1;
    }
    
    return output;
  }

  /**
   * Entraîne le réseau à partir d'une partie complète
   */
  async trainFromGame(record: BotGameRecord) {
    const trainingData: TrainingData[] = [];
    
    for (const action of record.actions) {
      const input = this.gameStateToInput(action.gameState, action);
      const output = this.actionToOutput(action.actionType);
      
      trainingData.push({ input, output });
    }
    
    // Entraîner sur plusieurs epochs
    for (let epoch = 0; epoch < 5; epoch++) {
      this.train(trainingData);
    }
    
    await this.saveNetwork();
    console.log(`✅ Réseau de neurones entraîné sur partie ${record.gameId}`);
  }

  /**
   * Prédit la meilleure action pour un état donné
   */
  predictBestAction(gameState: any, action: BotAction): string {
    const input = this.gameStateToInput(gameState, action);
    const predictions = this.predict(input);
    
    const actions = [
      'draw_from_deck',
      'draw_from_discard',
      'replace_card',
      'call_dutch',
      'use_power_peek',
      'use_power_swap',
      'use_power_steal',
      'pass',
    ];
    
    let bestIndex = 0;
    let bestValue = predictions[0];
    
    for (let i = 1; i < predictions.length; i++) {
      if (predictions[i] > bestValue) {
        bestValue = predictions[i];
        bestIndex = i;
      }
    }
    
    return actions[bestIndex];
  }

  /**
   * Sauvegarde le réseau sur le disque
   */
  private async saveNetwork() {
    try {
      const filepath = path.join(this.dataDir, 'network.json');
      await fs.writeFile(filepath, JSON.stringify(this.network, null, 2));
    } catch (error) {
      console.error('❌ Erreur sauvegarde réseau:', error instanceof Error ? error.message : String(error));
    }
  }

  /**
   * Charge le réseau depuis le disque
   */
  private loadNetworkSync() {
    try {
      const fsSync = require('node:fs');
      const filepath = path.join(this.dataDir, 'network.json');
      const data = fsSync.readFileSync(filepath, 'utf-8');
      this.network = JSON.parse(data);
      console.log(`✅ Réseau de neurones chargé`);
    } catch {
      console.log('ℹ️ Nouveau réseau de neurones créé');
    }
  }

  /**
   * Obtient les statistiques du réseau
   */
  getStats() {
    let totalWeights = 0;
    let totalBiases = 0;
    
    for (const layer of this.network.layers) {
      totalWeights += layer.weights.reduce((sum, row) => sum + row.length, 0);
      totalBiases += layer.biases.length;
    }
    
    return {
      architecture: `${this.network.inputSize} -> ${this.network.hiddenSizes.join(' -> ')} -> ${this.network.outputSize}`,
      totalLayers: this.network.layers.length,
      totalWeights,
      totalBiases,
      totalParameters: totalWeights + totalBiases,
    };
  }
}
