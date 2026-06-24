import { PlayingCard } from './Card';

export enum BotBehavior {
  fast = 0,
  aggressive = 1,
  balanced = 2,
}

export enum BotSkillLevel {
  bronze = 0,
  silver = 1,
  difficile = 2,
}

/**
 * Point de traduction UNIQUE string→skill (rétrocompat des libellés persistés).
 *
 * Les anciens paliers gold/platinum (+ or/platine/hard) sont fusionnés en
 * `difficile` (refonte 93b6d42). Renvoie `undefined` pour une chaîne non
 * reconnue afin que CHAQUE appelant applique son propre défaut historique
 * (silver / bronze / 1000…) sans en cacher aucun.
 */
export function tryParseBotSkillLevel(s?: string): BotSkillLevel | undefined {
  switch ((s ?? '').trim().toLowerCase()) {
    case 'bronze':
      return BotSkillLevel.bronze;
    case 'silver':
    case 'argent':
      return BotSkillLevel.silver;
    // Legacy fusionné : gold/platinum/or/platine → difficile.
    case 'gold':
    case 'or':
    case 'platinum':
    case 'platine':
    case 'difficile':
    case 'hard':
      return BotSkillLevel.difficile;
    default:
      return undefined;
  }
}

/** Variante non-nullable avec le défaut le plus courant (silver). */
export function botSkillLevelFromString(s?: string): BotSkillLevel {
  return tryParseBotSkillLevel(s) ?? BotSkillLevel.silver;
}

/**
 * Désérialisation par index avec rétrocompat des objets sérialisés AVANT la
 * fusion : ancien index 2 (gold) ET index 3 (platinum) → difficile.
 * difficile s'écrit désormais en index 2. Index hors borne → silver.
 */
export function botSkillLevelFromIndex(i?: number): BotSkillLevel {
  switch (i) {
    case 0:
      return BotSkillLevel.bronze;
    case 1:
      return BotSkillLevel.silver;
    case 2: // ex-gold, désormais difficile
    case 3: // ex-platinum (rétrocompat anti-crash)
      return BotSkillLevel.difficile;
    default:
      return BotSkillLevel.silver;
  }
}

export interface Player {
  id: string;
  name: string;
  username?: string;
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
  userId?: string,
  username?: string
): Player {
  return {
    id,
    name,
    username,
    isHuman,
    clientId,
    userId,
    connected: isHuman ? true : undefined,
    focused: isHuman ? true : undefined,
    isSpectator: false,
    lastSeenAt: isHuman ? Date.now() : undefined,
    ready: !isHuman,
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
