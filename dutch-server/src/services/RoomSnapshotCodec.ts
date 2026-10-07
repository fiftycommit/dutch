import { GameState } from '../models/GameState';
import { Room } from '../models/Room';

interface SerializedGameState extends Omit<GameState, 'reactionStartTime'> {
  reactionStartTime: string | null;
}

interface SerializedRoom extends Omit<
  Room,
  'createdAt' | 'cumulativeScores' | 'bannedClientIds' | 'playersInResults' | 'pauseTimeoutHandle' | 'gameState'
> {
  createdAt: string;
  cumulativeScores?: Record<string, number>;
  bannedClientIds?: string[];
  playersInResults?: string[];
  gameState: SerializedGameState | null;
}

function serializeGameState(gameState: GameState | null): SerializedGameState | null {
  if (!gameState) {
    return null;
  }

  return {
    ...gameState,
    reactionStartTime: gameState.reactionStartTime?.toISOString() ?? null,
  };
}

function deserializeGameState(gameState: SerializedGameState | null): GameState | null {
  if (!gameState) {
    return null;
  }

  return {
    ...gameState,
    reactionStartTime: gameState.reactionStartTime
      ? new Date(gameState.reactionStartTime)
      : null,
  };
}

export class RoomSnapshotCodec {
  static serialize(room: Room): string {
    const { pauseTimeoutHandle: _pauseTimeoutHandle, ...persistentRoom } = room;
    const payload: SerializedRoom = {
      ...persistentRoom,
      createdAt: room.createdAt.toISOString(),
      cumulativeScores: room.cumulativeScores
        ? Object.fromEntries(room.cumulativeScores.entries())
        : undefined,
      bannedClientIds: room.bannedClientIds
        ? Array.from(room.bannedClientIds)
        : undefined,
      playersInResults: room.playersInResults
        ? Array.from(room.playersInResults)
        : undefined,
      gameState: serializeGameState(room.gameState),
    };

    return JSON.stringify(payload);
  }

  static deserialize(raw: string): Room {
    const payload = JSON.parse(raw) as SerializedRoom;
    const gameState = deserializeGameState(payload.gameState);
    // JSON duplique les joueurs présents dans les deux tableaux. Restaurer
    // leurs références communes, en gardant les cartes de l'état de jeu et
    // les informations de connexion du salon.
    const players = payload.players.map((player) => {
      const gamePlayer = gameState?.players.find((candidate) => candidate.id === player.id);
      if (!gamePlayer) return player;
      Object.assign(gamePlayer, {
        name: player.name,
        username: player.username,
        clientId: player.clientId,
        userId: player.userId,
        connected: player.connected,
        focused: player.focused,
        lastSeenAt: player.lastSeenAt,
        ready: player.ready,
      });
      return gamePlayer;
    });

    return {
      ...payload,
      players,
      createdAt: new Date(payload.createdAt),
      cumulativeScores: payload.cumulativeScores
        ? new Map(Object.entries(payload.cumulativeScores))
        : undefined,
      bannedClientIds: payload.bannedClientIds
        ? new Set(payload.bannedClientIds)
        : undefined,
      playersInResults: payload.playersInResults
        ? new Set(payload.playersInResults)
        : undefined,
      pauseTimeoutHandle: undefined,
      gameState,
    };
  }
}
