import { PlayingCard } from './Card';
import { Player } from './Player';

export enum GameMode {
  quick = 0,
  tournament = 1,
}

export enum GamePhase {
  setup = 0,
  playing = 1,
  specialPower = 2,
  reaction = 3,
  dutchCalled = 4,
  ended = 5,
}

export enum Difficulty {
  easy = 0,
  medium = 1,
  hard = 2,
}

export interface PendingMatchPower {
  playerId: string;
  playerName: string;
  card: PlayingCard;
  drawNumber?: number; // numéro tiré lors de la loterie
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
  specialPowerStartTime: number | null; // Track when the special power decision started
  specialCardToActivate: PlayingCard | null;
  specialPowerPlayerId: string | null; // joueur qui utilise le pouvoir (peut différer du currentPlayer lors d'un match)
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
  // Timer de tour pour l'affichage visuel
  turnStartTime: number | null; // Timestamp en ms
  turnTimeoutMs: number; // Durée max du tour en ms (multijoueur)
  // Joueurs prêts (ont terminé la mémorisation)
  readyPlayerIds: string[];
  // Pouvoirs en attente suite à des matchs pendant la phase de réaction
  pendingMatchPowers: PendingMatchPower[];
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
    specialPowerStartTime: null,
    specialCardToActivate: null,
    specialPowerPlayerId: null,
    dutchCallerId: null,
    reactionStartTime: null,
    actionHistory: [],
    reactionTimeRemaining: 0,
    lastSpiedCard: null,
    pendingSwap: null,
    tournamentCumulativeScores: {},
    turnStartTime: null,
    turnTimeoutMs: 90000, // 1min30 par défaut
    readyPlayerIds: [],
    pendingMatchPowers: [],
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
  for (const _ of gameState.players) {
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
