"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.BotSkillLevel = exports.BotBehavior = void 0;
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
    BotSkillLevel[BotSkillLevel["gold"] = 2] = "gold";
    BotSkillLevel[BotSkillLevel["platinum"] = 3] = "platinum";
})(BotSkillLevel || (exports.BotSkillLevel = BotSkillLevel = {}));
function createPlayer(id, name, isHuman, position, botBehavior, botSkillLevel, clientId) {
    return {
        id,
        name,
        isHuman,
        clientId,
        connected: isHuman ? true : undefined,
        focused: isHuman ? true : undefined,
        isSpectator: false,
        lastSeenAt: isHuman ? Date.now() : undefined,
        botBehavior,
        botSkillLevel,
        position,
        hand: [],
        knownCards: [],
    };
}
function calculateScore(player) {
    return player.hand.reduce((sum, card) => sum + card.points, 0);
}
