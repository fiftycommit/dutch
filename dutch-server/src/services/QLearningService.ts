import * as fs from 'fs/promises';
import * as path from 'path';
import { BotAction, BotGameRecord } from '../models/BotLearning';

interface QState {
  myScore: number;
  cardsInHand: number;
  turnPhase: string;
  opponentsAvgScore: number;
  deckCardsRemaining: number;
}

interface QAction {
  type: 'draw_deck' | 'draw_discard' | 'call_dutch' | 'use_power' | 'replace_card';
  cardIndex?: number;
}

interface QTableEntry {
  state: string;
  actions: Map<string, number>;
  visits: number;
}

export class QLearningService {
  private qTable: Map<string, QTableEntry>;
  private alpha: number = 0.1; // Taux d'apprentissage
  private gamma: number = 0.95; // Facteur de discount
  private epsilon: number = 0.2; // Taux d'exploration
  private dataDir: string;

  constructor() {
    this.qTable = new Map();
    this.dataDir = path.join(__dirname, '../../data/bot-learning/qlearning');
    this.ensureDataDirectory();
    this.loadQTable();
  }

  private async ensureDataDirectory() {
    try {
      await fs.mkdir(this.dataDir, { recursive: true });
    } catch (error) {
      console.error('❌ Erreur création répertoire qlearning:', error);
    }
  }

  /**
   * Charge la Q-Table depuis le disque
   */
  private async loadQTable() {
    try {
      const filepath = path.join(this.dataDir, 'qtable.json');
      const data = await fs.readFile(filepath, 'utf-8');
      const parsed = JSON.parse(data);
      
      this.qTable = new Map();
      for (const [stateKey, entry] of Object.entries(parsed)) {
        const typedEntry = entry as any;
        this.qTable.set(stateKey, {
          state: stateKey,
          actions: new Map(Object.entries(typedEntry.actions)),
          visits: typedEntry.visits,
        });
      }
      
      console.log(`✅ Q-Table chargée: ${this.qTable.size} états`);
    } catch (error) {
      console.log('ℹ️ Nouvelle Q-Table créée');
    }
  }

  /**
   * Sauvegarde la Q-Table sur le disque
   */
  private async saveQTable() {
    try {
      const filepath = path.join(this.dataDir, 'qtable.json');
      const obj: any = {};
      
      for (const [stateKey, entry] of this.qTable.entries()) {
        obj[stateKey] = {
          state: entry.state,
          actions: Object.fromEntries(entry.actions),
          visits: entry.visits,
        };
      }
      
      await fs.writeFile(filepath, JSON.stringify(obj, null, 2));
    } catch (error) {
      console.error('❌ Erreur sauvegarde Q-Table:', error);
    }
  }

  /**
   * Convertit un état de jeu en clé de state
   */
  private stateToKey(state: QState): string {
    const scoreBucket = Math.floor(state.myScore / 5) * 5;
    const cardsBucket = Math.min(4, state.cardsInHand);
    const oppScoreBucket = Math.floor(state.opponentsAvgScore / 5) * 5;
    
    return `${scoreBucket}_${cardsBucket}_${state.turnPhase}_${oppScoreBucket}`;
  }

  /**
   * Convertit une action en clé
   */
  private actionToKey(action: QAction): string {
    if (action.cardIndex !== undefined) {
      return `${action.type}_${action.cardIndex}`;
    }
    return action.type;
  }

  /**
   * Sélectionne la meilleure action pour un état donné (epsilon-greedy)
   */
  selectAction(state: QState, availableActions: QAction[]): QAction {
    const stateKey = this.stateToKey(state);
    
    // Exploration vs Exploitation
    if (Math.random() < this.epsilon) {
      // Exploration: action aléatoire
      return availableActions[Math.floor(Math.random() * availableActions.length)];
    }
    
    // Exploitation: meilleure action connue
    const entry = this.qTable.get(stateKey);
    if (!entry) {
      return availableActions[Math.floor(Math.random() * availableActions.length)];
    }
    
    let bestAction = availableActions[0];
    let bestValue = -Infinity;
    
    for (const action of availableActions) {
      const actionKey = this.actionToKey(action);
      const value = entry.actions.get(actionKey) || 0;
      
      if (value > bestValue) {
        bestValue = value;
        bestAction = action;
      }
    }
    
    return bestAction;
  }

  /**
   * Met à jour la Q-Table après une action
   */
  updateQValue(
    state: QState,
    action: QAction,
    reward: number,
    nextState: QState | null
  ) {
    const stateKey = this.stateToKey(state);
    const actionKey = this.actionToKey(action);
    
    // Créer l'entrée si elle n'existe pas
    if (!this.qTable.has(stateKey)) {
      this.qTable.set(stateKey, {
        state: stateKey,
        actions: new Map(),
        visits: 0,
      });
    }
    
    const entry = this.qTable.get(stateKey)!;
    entry.visits++;
    
    const currentQ = entry.actions.get(actionKey) || 0;
    
    // Calculer la valeur maximale du prochain état
    let maxNextQ = 0;
    if (nextState) {
      const nextStateKey = this.stateToKey(nextState);
      const nextEntry = this.qTable.get(nextStateKey);
      
      if (nextEntry) {
        maxNextQ = Math.max(...Array.from(nextEntry.actions.values()));
      }
    }
    
    // Formule Q-Learning: Q(s,a) = Q(s,a) + α * (r + γ * max(Q(s',a')) - Q(s,a))
    const newQ = currentQ + this.alpha * (reward + this.gamma * maxNextQ - currentQ);
    entry.actions.set(actionKey, newQ);
  }

  /**
   * Calcule la récompense pour une action
   */
  calculateReward(
    action: QAction,
    previousScore: number,
    newScore: number,
    gameEnded: boolean,
    finalRank?: number
  ): number {
    let reward = 0;
    
    // Récompense basée sur la différence de score
    const scoreDiff = previousScore - newScore;
    reward += scoreDiff * 2; // Réduire le score est bien
    
    // Pénalité pour augmenter le score
    if (scoreDiff < 0) {
      reward -= Math.abs(scoreDiff) * 3;
    }
    
    // Récompense pour appeler Dutch
    if (action.type === 'call_dutch') {
      if (gameEnded && finalRank === 1) {
        reward += 100; // Grosse récompense pour gagner avec Dutch
      } else if (gameEnded && finalRank && finalRank > 1) {
        reward -= 50; // Pénalité pour Dutch raté
      }
    }
    
    // Récompense finale basée sur le rang
    if (gameEnded && finalRank) {
      if (finalRank === 1) reward += 50;
      else if (finalRank === 2) reward += 20;
      else if (finalRank === 3) reward += 5;
      else reward -= 20;
    }
    
    return reward;
  }

  /**
   * Entraîne le modèle à partir d'une partie complète
   */
  async trainFromGame(record: BotGameRecord) {
    const actions = record.actions;
    
    for (let i = 0; i < actions.length; i++) {
      const action = actions[i];
      const nextAction = i < actions.length - 1 ? actions[i + 1] : null;
      
      const state: QState = {
        myScore: action.gameState.myScore || 0,
        cardsInHand: action.gameState.cardsInHand || 4,
        turnPhase: action.gameState.turnPhase || 'playing',
        opponentsAvgScore: action.gameState.opponentsAvgScore || 0,
        deckCardsRemaining: action.gameState.deckCardsRemaining || 20,
      };
      
      const qAction: QAction = {
        type: this.mapActionType(action.actionType),
        cardIndex: action.actionDetails.cardIndex,
      };
      
      const nextState: QState | null = nextAction ? {
        myScore: nextAction.gameState.myScore || 0,
        cardsInHand: nextAction.gameState.cardsInHand || 4,
        turnPhase: nextAction.gameState.turnPhase || 'playing',
        opponentsAvgScore: nextAction.gameState.opponentsAvgScore || 0,
        deckCardsRemaining: nextAction.gameState.deckCardsRemaining || 20,
      } : null;
      
      const previousScore = action.gameState.myScore || 0;
      const newScore = action.result.newScore || previousScore;
      const gameEnded = i === actions.length - 1;
      
      const reward = this.calculateReward(
        qAction,
        previousScore,
        newScore,
        gameEnded,
        gameEnded ? record.finalRank : undefined
      );
      
      this.updateQValue(state, qAction, reward, nextState);
    }
    
    await this.saveQTable();
    console.log(`✅ Q-Learning entraîné sur partie ${record.gameId}`);
  }

  /**
   * Mappe les types d'actions du jeu vers les types Q-Learning
   */
  private mapActionType(actionType: string): QAction['type'] {
    switch (actionType) {
      case 'draw_from_deck':
        return 'draw_deck';
      case 'draw_from_discard':
        return 'draw_discard';
      case 'call_dutch':
        return 'call_dutch';
      case 'use_power':
        return 'use_power';
      case 'replace_card':
        return 'replace_card';
      default:
        return 'draw_deck';
    }
  }

  /**
   * Obtient les statistiques de la Q-Table
   */
  getStats() {
    const totalStates = this.qTable.size;
    let totalActions = 0;
    let totalVisits = 0;
    
    for (const entry of this.qTable.values()) {
      totalActions += entry.actions.size;
      totalVisits += entry.visits;
    }
    
    return {
      totalStates,
      totalActions,
      totalVisits,
      avgActionsPerState: totalStates > 0 ? totalActions / totalStates : 0,
      avgVisitsPerState: totalStates > 0 ? totalVisits / totalStates : 0,
    };
  }

  /**
   * Réduit le taux d'exploration au fil du temps
   */
  decayEpsilon() {
    this.epsilon = Math.max(0.05, this.epsilon * 0.995);
  }
}
