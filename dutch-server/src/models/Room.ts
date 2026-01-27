import { Player } from './Player';
import { GameState, GameMode } from './GameState';

export interface GameSettings {
  gameMode: GameMode;
  botDifficulty: number;
  luckDifficulty: number;
  reactionTimeMs: number;
  minPlayers: number;
  maxPlayers: number;
  fillBots: boolean;
}

export enum RoomStatus {
  waiting = 'waiting',
  playing = 'playing',
  ended = 'ended',
  closing = 'closing', // Room en cours de fermeture, en attente de transfert d'hôte
}

export interface Room {
  id: string; // Code room (ex: "ABC123")
  hostPlayerId: string;
  settings: GameSettings;
  gameMode: GameMode;
  players: Player[];
  gameState: GameState | null;
  status: RoomStatus;
  createdAt: Date;
  lastActivityAt: number;
  expiresAt: number;
  tournamentRound?: number;
  closingAt?: number; // Timestamp d'expiration pour transfert d'hôte
  cumulativeScores?: Map<string, number>; // clientId -> score total (classement permanent)
}

export function createRoom(
  id: string,
  hostPlayerId: string,
  settings: GameSettings,
  expiresAt: number
): Room {
  return {
    id,
    hostPlayerId,
    settings,
    gameMode: settings.gameMode,
    players: [],
    gameState: null,
    status: RoomStatus.waiting,
    createdAt: new Date(),
    lastActivityAt: Date.now(),
    expiresAt,
    tournamentRound: 1,
  };
}
