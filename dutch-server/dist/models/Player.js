"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.BotSkillLevel = exports.BotBehavior = void 0;
exports.tryParseBotSkillLevel = tryParseBotSkillLevel;
exports.botSkillLevelFromString = botSkillLevelFromString;
exports.botSkillLevelFromIndex = botSkillLevelFromIndex;
exports.createPlayer = createPlayer;
exports.calculateScore = calculateScore;
var BotBehavior;
(function (BotBehavior) {
    BotBehavior[BotBehavior["fast"] = 0] = "fast";
    BotBehavior[BotBehavior["aggressive"] = 1] = "aggressive";
    BotBehavior[BotBehavior["balanced"] = 2] = "balanced";
})(BotBehavior || (exports.BotBehavior = BotBehavior = {}));
var BotSkillLevel;
(function (BotSkillLevel) {
    BotSkillLevel[BotSkillLevel["bronze"] = 0] = "bronze";
    BotSkillLevel[BotSkillLevel["silver"] = 1] = "silver";
    BotSkillLevel[BotSkillLevel["difficile"] = 2] = "difficile";
})(BotSkillLevel || (exports.BotSkillLevel = BotSkillLevel = {}));
/**
 * Point de traduction UNIQUE string→skill (rétrocompat des libellés persistés).
 *
 * Les anciens paliers gold/platinum (+ or/platine/hard) sont fusionnés en
 * `difficile` (refonte 93b6d42). Renvoie `undefined` pour une chaîne non
 * reconnue afin que CHAQUE appelant applique son propre défaut historique
 * (silver / bronze / 1000…) sans en cacher aucun.
 */
function tryParseBotSkillLevel(s) {
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
function botSkillLevelFromString(s) {
    return tryParseBotSkillLevel(s) ?? BotSkillLevel.silver;
}
/**
 * Désérialisation par index avec rétrocompat des objets sérialisés AVANT la
 * fusion : ancien index 2 (gold) ET index 3 (platinum) → difficile.
 * difficile s'écrit désormais en index 2. Index hors borne → silver.
 */
function botSkillLevelFromIndex(i) {
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
function createPlayer(id, name, isHuman, position, botBehavior, botSkillLevel, clientId, userId, username) {
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
function calculateScore(player) {
    // Si le joueur a abandonné ou est spectateur (mais avec des cartes), pénalité max
    if (player.isSpectator || player.hasFolded) {
        return 100; // Score maximum arbitraire pour être dernier
    }
    return player.hand.reduce((sum, card) => sum + card.points, 0);
}
//# sourceMappingURL=Player.js.map