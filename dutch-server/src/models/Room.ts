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
  isPublic?: boolean;
  useSBMM?: boolean;
  numberOfBots?: number;
  hostClientId?: string;
  sbmmBotLevels?: number[]; // BotSkillLevel[] pour chaque bot (SBMM per-bot)
}

export enum RoomStatus {
  waiting = 'waiting',
  playing = 'playing',
  ended = 'ended',
  closing = 'closing', // Room en cours de fermeture, en attente de transfert d'hôte
}

export interface Room {
  id: string; // Code room (ex: "AB12CD34")
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
  isPaused?: boolean;
  pausedByPlayerId?: string;   // socket.id du joueur qui a mis pause
  pausedByName?: string;       // nom affiché
  pauseStartTime?: number;     // Date.now() au moment de la pause
  pauseTimeoutHandle?: ReturnType<typeof setTimeout>; // timer d'expulsion auto
  emptyAt?: number; // Timestamp quand la room est devenue vide
  bannedClientIds?: Set<string>; // clientIds des joueurs BANNIS (ne peuvent plus rejoindre)
  creatorUserId?: string; // userId persistant du créateur (pour restaurer l'hôte à la reconnexion)
  lastStartingPlayerId?: string; // ID du joueur qui a commencé la partie précédente (pour éviter répétition)
  playersInResults?: Set<string>; // socketIds des joueurs encore sur l'écran de résultats
}

export function createRoom(
  id: string,
  hostPlayerId: string,
  settings: GameSettings,
  expiresAt: number,
  creatorUserId?: string
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
    isPaused: false,
    creatorUserId,
  };
}
