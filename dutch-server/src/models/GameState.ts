import { PlayingCard } from './Card';
import { Player } from './Player';

export enum GameMode {
  quick = 0,
  tournament = 1,
}

export enum GamePhase {
  setup = 0,
  playing = 1,
  reaction = 2,
  dutchCalled = 3,
  ended = 4,
}

export enum Difficulty {
  easy = 0,
  medium = 1,
  hard = 2,
}

export interface GameState {
  players: Player[];
  deck: PlayingCard[];
  discardPile: PlayingCard[];
  currentPlayerIndex: number;
  gameMode: GameMode;
  phase: GamePhase;
  difficulty: Difficulty;
  tournamentRound: number;
  eliminatedPlayerIds: string[];
  drawnCard: PlayingCard | null;
  isWaitingForSpecialPower: boolean;
  specialCardToActivate: PlayingCard | null;
  dutchCallerId: string | null;
  reactionStartTime: Date | null;
  actionHistory: string[];
  reactionTimeRemaining: number;
  lastSpiedCard: PlayingCard | null;
  pendingSwap: {
    targetPlayer: number;
    targetCard: number;
    ownCard: number | null;
  } | null;
  tournamentCumulativeScores: { [playerId: string]: number };
}

export function createGameState(
  players: Player[],
  gameMode: GameMode,
  difficulty: Difficulty
): GameState {
  return {
    players,
    deck: [],
    discardPile: [],
    currentPlayerIndex: 0,
    gameMode,
    phase: GamePhase.setup,
    difficulty,
    tournamentRound: 1,
    eliminatedPlayerIds: [],
    drawnCard: null,
    isWaitingForSpecialPower: false,
    specialCardToActivate: null,
    dutchCallerId: null,
    reactionStartTime: null,
    actionHistory: [],
    reactionTimeRemaining: 0,
    lastSpiedCard: null,
    pendingSwap: null,
    tournamentCumulativeScores: {},
  };
}

export function getCurrentPlayer(gameState: GameState): Player {
  return gameState.players[gameState.currentPlayerIndex];
}

export function addToHistory(gameState: GameState, action: string): void {
  const now = new Date();
  const time = `${now.getHours()}:${now.getMinutes().toString().padStart(2, '0')}`;
  gameState.actionHistory.unshift(`[${time}] ${action}`);

  // Limiter à 50 entrées
  if (gameState.actionHistory.length > 50) {
    gameState.actionHistory = gameState.actionHistory.slice(0, 50);
  }
}

export function nextPlayer(gameState: GameState): void {
  for (let i = 0; i < gameState.players.length; i++) {
    gameState.currentPlayerIndex =
      (gameState.currentPlayerIndex + 1) % gameState.players.length;

    const current = getCurrentPlayer(gameState);
    if (
      !gameState.eliminatedPlayerIds.includes(current.id) &&
      !current.isSpectator
    ) {
      break;
    }
  }
}
