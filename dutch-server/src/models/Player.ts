import { PlayingCard } from './Card';

export enum BotBehavior {
  fast = 0,
  aggressive = 1,
  balanced = 2,
}

export enum BotSkillLevel {
  bronze = 0,
  silver = 1,
  gold = 2,
  platinum = 3,
}

export interface Player {
  id: string;
  name: string;
  isHuman: boolean;
  clientId?: string;
  userId?: string;
  connected?: boolean;
  focused?: boolean;
  isSpectator?: boolean;
  lastSeenAt?: number;
  ready?: boolean;
  botBehavior?: BotBehavior;
  botSkillLevel?: BotSkillLevel;
  position: number;
  hand: PlayingCard[];
  knownCards: boolean[];
  hasFolded?: boolean;
  // Note: mentalMap, dutchHistory et consecutiveBadDraws
  // sont gérés séparément côté serveur pour les bots
}

export function createPlayer(
  id: string,
  name: string,
  isHuman: boolean,
  position: number,
  botBehavior?: BotBehavior,
  botSkillLevel?: BotSkillLevel,
  clientId?: string,
  userId?: string
): Player {
  return {
    id,
    name,
    isHuman,
    clientId,
    userId,
    connected: isHuman ? true : undefined,
    focused: isHuman ? true : undefined,
    isSpectator: false,
    lastSeenAt: isHuman ? Date.now() : undefined,
    ready: isHuman ? false : true,
    botBehavior,
    botSkillLevel,
    position,
    hand: [],
    knownCards: [],
  };
}

export function calculateScore(player: Player): number {
  // Si le joueur a abandonné ou est spectateur (mais avec des cartes), pénalité max
  if (player.isSpectator || player.hasFolded) {
    return 100; // Score maximum arbitraire pour être dernier
  }
  return player.hand.reduce((sum, card) => sum + card.points, 0);
}
