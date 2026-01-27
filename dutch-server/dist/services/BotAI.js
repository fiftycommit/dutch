"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.BotAI = void 0;
const GameState_1 = require("../models/GameState");
const Player_1 = require("../models/Player");
const Card_1 = require("../models/Card");
const GameLogic_1 = require("./GameLogic");
const BotDifficulty_1 = require("./BotDifficulty");
var BotGamePhase;
(function (BotGamePhase) {
    BotGamePhase[BotGamePhase["exploration"] = 0] = "exploration";
    BotGamePhase[BotGamePhase["optimization"] = 1] = "optimization";
    BotGamePhase[BotGamePhase["endgame"] = 2] = "endgame";
})(BotGamePhase || (BotGamePhase = {}));
// Map pour stocker la mémoire des bots (clé: playerId)
const botMemories = new Map();
class BotAI {
    static random() {
        return Math.random();
    }
    static getBotMemory(player) {
        if (!botMemories.has(player.id)) {
            botMemories.set(player.id, {
                mentalMap: new Array(player.hand.length).fill(null),
                consecutiveBadDraws: 0,
                dutchHistory: [],
            });
        }
        return botMemories.get(player.id);
    }
    static initializeBotMemory(player) {
        if (player.isHuman || player.hand.length < 2)
            return;
        const memory = this.getBotMemory(player);
        memory.mentalMap = new Array(player.hand.length).fill(null);
        memory.mentalMap[0] = player.hand[0];
        memory.mentalMap[1] = player.hand[1];
    }
    static updateMentalMap(player, index, card) {
        const memory = this.getBotMemory(player);
        while (memory.mentalMap.length <= index) {
            memory.mentalMap.push(null);
        }
        memory.mentalMap[index] = card;
    }
    static forgetCard(player, index) {
        const memory = this.getBotMemory(player);
        if (index >= 0 && index < memory.mentalMap.length) {
            memory.mentalMap[index] = null;
        }
        if (index >= 0 && index < player.knownCards.length) {
            player.knownCards[index] = false;
        }
    }
    static resetMentalMap(player) {
        const memory = this.getBotMemory(player);
        memory.mentalMap = new Array(player.hand.length).fill(null);
        player.knownCards = new Array(player.hand.length).fill(false);
    }
    static getEstimatedScore(player) {
        if (player.isHuman) {
            return player.hand.reduce((sum, card) => sum + card.points, 0);
        }
        const memory = this.getBotMemory(player);
        let estimatedScore = 0;
        let knownCount = 0;
        let knownSum = 0;
        for (let i = 0; i < player.hand.length; i++) {
            if (i < memory.mentalMap.length && memory.mentalMap[i] !== null) {
                const cardPoints = memory.mentalMap[i].points;
                estimatedScore += cardPoints;
                knownSum += cardPoints;
                knownCount++;
            }
        }
        const unknownCount = player.hand.length - knownCount;
        if (unknownCount > 0) {
            let estimatePerUnknown;
            if (knownCount >= 2) {
                estimatePerUnknown = Math.round(knownSum / knownCount);
                estimatePerUnknown = Math.max(4, Math.min(7, estimatePerUnknown));
            }
            else {
                estimatePerUnknown = 5;
            }
            estimatedScore += unknownCount * estimatePerUnknown;
        }
        return estimatedScore;
    }
    static getKnownCardCount(player) {
        const memory = this.getBotMemory(player);
        let count = 0;
        for (let i = 0; i < memory.mentalMap.length && i < player.hand.length; i++) {
            if (memory.mentalMap[i] !== null)
                count++;
        }
        return count;
    }
    static getCumulativeScore(gameState, player) {
        return gameState.tournamentCumulativeScores[player.id] || 0;
    }
    static getBotPhase(bot, gameState) {
        const knownCount = this.getKnownCardCount(bot);
        const totalCards = bot.hand.length;
        const estimatedScore = this.getEstimatedScore(bot);
        // En tournoi, prendre en compte le score cumulé
        if (gameState.gameMode === GameState_1.GameMode.tournament) {
            const cumulativeScore = this.getCumulativeScore(gameState, bot);
            if (cumulativeScore >= 70) {
                return BotGamePhase.endgame;
            }
        }
        const someoneClose = gameState.players.some((p) => p.hand.length <= 2);
        if (estimatedScore <= 8 || someoneClose) {
            return BotGamePhase.endgame;
        }
        if (knownCount < totalCards) {
            return BotGamePhase.exploration;
        }
        return BotGamePhase.optimization;
    }
    static async playBotTurn(gameState, playerMMR) {
        const bot = (0, GameState_1.getCurrentPlayer)(gameState);
        if (bot.isHuman)
            return;
        const difficulty = playerMMR !== undefined
            ? BotDifficulty_1.BotDifficulty.fromMMR(playerMMR)
            : this.getSkillDifficulty(bot.botSkillLevel);
        const phase = this.getBotPhase(bot, gameState);
        this.applyMemoryDecay(bot, difficulty);
        const thinkingTime = this.getThinkingTime(bot.botBehavior, difficulty, gameState);
        await this.delay(thinkingTime);
        if (this.shouldCallDutch(gameState, bot, difficulty, phase)) {
            GameLogic_1.GameLogic.callDutch(gameState);
            return;
        }
        GameLogic_1.GameLogic.drawCard(gameState);
        await this.delay(1000);
        await this.decideCardAction(gameState, bot, difficulty, phase);
    }
    static shouldCallDutch(gs, bot, difficulty, phase) {
        const estimatedScore = this.getEstimatedScore(bot);
        const behavior = bot.botBehavior;
        if (phase === BotGamePhase.exploration) {
            return false;
        }
        const audacityBonus = this.calculateAudacity(gs, bot, difficulty);
        const confidence = this.calculateDutchConfidence(bot);
        let tournamentPressure = 0.0;
        if (gs.gameMode === GameState_1.GameMode.tournament) {
            const cumulativeScore = this.getCumulativeScore(gs, bot);
            if (cumulativeScore >= 80) {
                tournamentPressure = 3.0;
            }
            else if (cumulativeScore >= 60) {
                tournamentPressure = 2.0;
            }
            else if (cumulativeScore >= 40) {
                tournamentPressure = 1.0;
            }
            else if (cumulativeScore <= 20) {
                tournamentPressure = -1.0;
            }
        }
        let threshold;
        if (phase === BotGamePhase.endgame) {
            switch (behavior) {
                case Player_1.BotBehavior.fast:
                    threshold =
                        difficulty.name === 'Bronze' ? 7 :
                            difficulty.name === 'Argent' ? 6 :
                                difficulty.name === 'Or' ? 3 : 2;
                    break;
                case Player_1.BotBehavior.aggressive:
                    threshold =
                        difficulty.name === 'Bronze' ? 6 :
                            difficulty.name === 'Argent' ? 5 :
                                difficulty.name === 'Or' ? 2 : 1;
                    if (this.isHumanThreatening(gs)) {
                        threshold += 1;
                    }
                    break;
                case Player_1.BotBehavior.balanced:
                    if (difficulty.name === 'Bronze') {
                        threshold = 6;
                    }
                    else if (difficulty.name === 'Argent') {
                        threshold = 5;
                    }
                    else if (difficulty.name === 'Or') {
                        threshold = 2;
                        if (this.random() < 0.50) {
                            for (const p of gs.players) {
                                if (p.id !== bot.id) {
                                    const opponentScore = this.getEstimatedScore(p);
                                    if (opponentScore <= estimatedScore + 1) {
                                        return false;
                                    }
                                }
                            }
                        }
                    }
                    else {
                        threshold = 1;
                        for (const p of gs.players) {
                            if (p.id !== bot.id) {
                                const opponentScore = this.getEstimatedScore(p);
                                if (opponentScore <= estimatedScore) {
                                    return false;
                                }
                            }
                        }
                    }
                    break;
                default:
                    threshold = difficulty.dutchThreshold + 1;
            }
        }
        else {
            // En optimization
            switch (behavior) {
                case Player_1.BotBehavior.fast:
                    threshold =
                        difficulty.name === 'Bronze' ? 6 :
                            difficulty.name === 'Argent' ? 4 :
                                difficulty.name === 'Or' ? 1 : 1;
                    break;
                case Player_1.BotBehavior.aggressive:
                    threshold =
                        difficulty.name === 'Bronze' ? 4 :
                            difficulty.name === 'Argent' ? 3 :
                                difficulty.name === 'Or' ? 1 : 0;
                    break;
                case Player_1.BotBehavior.balanced:
                    threshold =
                        difficulty.name === 'Bronze' ? 5 :
                            difficulty.name === 'Argent' ? 4 :
                                difficulty.name === 'Or' ? 1 : 0;
                    break;
                default:
                    threshold = difficulty.dutchThreshold;
            }
        }
        const adjustedThreshold = threshold + audacityBonus + confidence * 2 + tournamentPressure;
        return estimatedScore <= Math.round(adjustedThreshold);
    }
    static calculateAudacity(gs, bot, difficulty) {
        let audacity = 0.0;
        const cardCount = bot.hand.length;
        if (cardCount === 1) {
            audacity += 3.0;
        }
        else if (cardCount === 2) {
            audacity += 2.0;
        }
        else if (cardCount === 3) {
            audacity += 1.0;
        }
        const memory = this.getBotMemory(bot);
        if (memory.consecutiveBadDraws >= 3) {
            const badDrawBonus = (memory.consecutiveBadDraws - 2) * 0.5;
            audacity += badDrawBonus;
        }
        let dangerousOpponents = 0;
        for (const p of gs.players) {
            if (p.id !== bot.id && p.hand.length <= 2) {
                dangerousOpponents++;
            }
        }
        if (dangerousOpponents > 0) {
            const cautionPenalty = dangerousOpponents * 0.5;
            audacity -= cautionPenalty;
        }
        if (bot.botBehavior === Player_1.BotBehavior.aggressive) {
            audacity += 1.0;
        }
        else if (bot.botBehavior === Player_1.BotBehavior.balanced) {
            audacity -= 1.0;
        }
        if (difficulty.name === 'Bronze') {
            audacity *= 0.5;
        }
        else if (difficulty.name === 'Platine') {
            audacity *= 1.2;
        }
        return Math.max(-3.0, Math.min(5.0, audacity));
    }
    static calculateDutchConfidence(bot) {
        const memory = this.getBotMemory(bot);
        if (memory.dutchHistory.length === 0) {
            return 0.0;
        }
        const recentAttempts = memory.dutchHistory.length > 5
            ? memory.dutchHistory.slice(-5)
            : memory.dutchHistory;
        const wins = recentAttempts.filter((a) => a.won).length;
        const winRate = wins / recentAttempts.length;
        const avgAccuracy = recentAttempts.reduce((sum, a) => {
            const accuracy = Math.abs(a.estimatedScore - a.actualScore) <= 2 ? 1.0 : 0.5;
            return sum + accuracy;
        }, 0) / recentAttempts.length;
        const confidence = winRate * 0.7 + avgAccuracy * 0.3 - 0.5;
        return Math.max(-1.0, Math.min(1.0, confidence));
    }
    static async decideCardAction(gs, bot, difficulty, phase) {
        const drawn = gs.drawnCard;
        if (!drawn)
            return;
        const drawnVal = drawn.points;
        let replaceIdx = -1;
        let isBadDraw = false;
        const memory = this.getBotMemory(bot);
        if (phase === BotGamePhase.exploration) {
            const unknownIndices = [];
            for (let i = 0; i < bot.hand.length; i++) {
                if (i >= memory.mentalMap.length || memory.mentalMap[i] === null) {
                    unknownIndices.push(i);
                }
            }
            if (unknownIndices.length > 0) {
                replaceIdx = unknownIndices[Math.floor(this.random() * unknownIndices.length)];
                const confused = this.random() < difficulty.confusionOnSwap;
                if (!confused) {
                    this.updateMentalMap(bot, replaceIdx, drawn);
                }
                GameLogic_1.GameLogic.replaceCard(gs, replaceIdx);
                return;
            }
        }
        let keepThreshold = difficulty.keepCardThreshold;
        const behavior = bot.botBehavior;
        switch (behavior) {
            case Player_1.BotBehavior.fast:
                keepThreshold = 5;
                break;
            case Player_1.BotBehavior.aggressive:
                keepThreshold += 1;
                break;
            case Player_1.BotBehavior.balanced:
                if (phase === BotGamePhase.endgame) {
                    keepThreshold = Math.floor((5 + difficulty.keepCardThreshold) / 2);
                }
                else {
                    keepThreshold = difficulty.keepCardThreshold;
                }
                break;
        }
        if (phase === BotGamePhase.endgame &&
            behavior !== Player_1.BotBehavior.fast &&
            behavior !== Player_1.BotBehavior.balanced) {
            keepThreshold -= 1;
        }
        let worstKnownValue = -1;
        for (let i = 0; i < memory.mentalMap.length; i++) {
            if (memory.mentalMap[i] !== null) {
                const cardValue = memory.mentalMap[i].points;
                if (cardValue > worstKnownValue && cardValue > drawnVal) {
                    worstKnownValue = cardValue;
                    replaceIdx = i;
                }
            }
        }
        if (replaceIdx !== -1 && drawnVal <= keepThreshold) {
            const confused = this.random() < difficulty.confusionOnSwap;
            if (!confused) {
                this.updateMentalMap(bot, replaceIdx, drawn);
            }
            GameLogic_1.GameLogic.replaceCard(gs, replaceIdx);
            memory.consecutiveBadDraws = 0;
        }
        else if (replaceIdx !== -1 && worstKnownValue > drawnVal + 3) {
            const confused = this.random() < difficulty.confusionOnSwap;
            if (!confused) {
                this.updateMentalMap(bot, replaceIdx, drawn);
            }
            GameLogic_1.GameLogic.replaceCard(gs, replaceIdx);
            memory.consecutiveBadDraws = 0;
        }
        else {
            GameLogic_1.GameLogic.discardDrawnCard(gs);
            isBadDraw = true;
        }
        if (isBadDraw) {
            memory.consecutiveBadDraws++;
        }
    }
    static async tryReactionMatch(gameState, bot, playerMMR) {
        if (gameState.phase !== GameState_1.GamePhase.reaction)
            return false;
        if (bot.isHuman)
            return false;
        if (gameState.discardPile.length === 0)
            return false;
        const difficulty = playerMMR !== undefined
            ? BotDifficulty_1.BotDifficulty.fromMMR(playerMMR)
            : this.getSkillDifficulty(bot.botSkillLevel);
        const phase = this.getBotPhase(bot, gameState);
        let matchChance = difficulty.reactionMatchChance;
        if (bot.hand.length >= 5) {
            matchChance += 0.15;
        }
        else if (bot.hand.length >= 4) {
            matchChance += 0.10;
        }
        if (bot.botBehavior === Player_1.BotBehavior.fast && phase === BotGamePhase.endgame) {
            matchChance = 1.0;
        }
        else if (bot.botBehavior === Player_1.BotBehavior.balanced && phase === BotGamePhase.endgame) {
            matchChance = (matchChance + 1.0) / 2;
        }
        if (gameState.gameMode === GameState_1.GameMode.tournament) {
            const cumulativeScore = this.getCumulativeScore(gameState, bot);
            if (cumulativeScore >= 70) {
                matchChance += 0.20;
            }
        }
        matchChance = Math.max(0.0, Math.min(1.0, matchChance));
        if (this.random() > matchChance) {
            return false;
        }
        const topDiscard = gameState.discardPile[gameState.discardPile.length - 1];
        const memory = this.getBotMemory(bot);
        // Chercher une carte connue qui match
        for (let i = 0; i < bot.hand.length; i++) {
            if (i < memory.mentalMap.length && memory.mentalMap[i] !== null) {
                const knownCard = memory.mentalMap[i];
                if ((0, Card_1.cardMatches)(knownCard, topDiscard)) {
                    if (this.random() < difficulty.matchAccuracy) {
                        const reactionDelay = Math.round(500 * (1 - difficulty.reactionSpeed)) + 200;
                        await this.delay(reactionDelay);
                        const success = GameLogic_1.GameLogic.matchCard(gameState, bot, i);
                        if (success) {
                            if (i < memory.mentalMap.length) {
                                memory.mentalMap.splice(i, 1);
                            }
                            return true;
                        }
                        else {
                            return false;
                        }
                    }
                }
            }
        }
        // Match à l'aveugle pour Or/Platine
        if (difficulty.name === 'Or' || difficulty.name === 'Platine') {
            const blindMatchChance = difficulty.name === 'Platine' ? 0.80 : 0.50;
            if (this.random() < blindMatchChance) {
                const unknownIndices = [];
                for (let i = 0; i < bot.hand.length; i++) {
                    if (i >= memory.mentalMap.length || memory.mentalMap[i] === null) {
                        unknownIndices.push(i);
                    }
                }
                if (unknownIndices.length > 0) {
                    const blindIndex = unknownIndices[Math.floor(this.random() * unknownIndices.length)];
                    const blindCard = bot.hand[blindIndex];
                    if ((0, Card_1.cardMatches)(blindCard, topDiscard)) {
                        const reactionDelay = Math.round(400 * (1 - difficulty.reactionSpeed)) + 150;
                        await this.delay(reactionDelay);
                        const success = GameLogic_1.GameLogic.matchCard(gameState, bot, blindIndex);
                        if (success) {
                            if (blindIndex < memory.mentalMap.length) {
                                memory.mentalMap.splice(blindIndex, 1);
                            }
                        }
                        return success;
                    }
                }
            }
        }
        return false;
    }
    static async useBotSpecialPower(gameState, playerMMR) {
        if (!gameState.isWaitingForSpecialPower || !gameState.specialCardToActivate)
            return;
        const bot = (0, GameState_1.getCurrentPlayer)(gameState);
        const card = gameState.specialCardToActivate;
        const difficulty = playerMMR !== undefined
            ? BotDifficulty_1.BotDifficulty.fromMMR(playerMMR)
            : this.getSkillDifficulty(bot.botSkillLevel);
        await this.delay(1000);
        const val = card.value;
        if (val === '7') {
            const idx = this.chooseCardToLook(bot, difficulty);
            GameLogic_1.GameLogic.lookAtCard(gameState, bot, idx);
            this.updateMentalMap(bot, idx, bot.hand[idx]);
        }
        else if (val === '10') {
            const target = this.chooseSpyTarget(gameState, bot, difficulty);
            if (target && target.hand.length > 0) {
                let idx;
                if ((difficulty.name === 'Or' || difficulty.name === 'Platine') && this.random() < 0.7) {
                    idx = this.random() < 0.5 ? 0 : target.hand.length - 1;
                }
                else {
                    idx = Math.floor(this.random() * target.hand.length);
                }
                GameLogic_1.GameLogic.lookAtCard(gameState, target, idx);
            }
        }
        else if (val === 'V') {
            await this.executeValetStrategy(gameState, bot, difficulty);
        }
        else if (val === 'JOKER') {
            await this.executeJokerStrategy(gameState, bot, difficulty);
        }
        gameState.isWaitingForSpecialPower = false;
        gameState.specialCardToActivate = null;
        (0, GameState_1.addToHistory)(gameState, `${bot.name} a utilisé son pouvoir.`);
    }
    static applyMemoryDecay(bot, difficulty) {
        if (bot.knownCards.length === 0)
            return;
        for (let i = 0; i < bot.knownCards.length; i++) {
            if (bot.knownCards[i] && this.random() < difficulty.forgetChancePerTurn) {
                this.forgetCard(bot, i);
            }
        }
    }
    static getThinkingTime(behavior, difficulty, gameState) {
        if (behavior === undefined)
            return 800;
        if (behavior === Player_1.BotBehavior.balanced) {
            const criticalMoment = gameState.players.some((p) => p.hand.length <= 2);
            switch (difficulty.name) {
                case 'Bronze':
                    return criticalMoment ? 1000 : 800;
                case 'Argent':
                    return criticalMoment ? 1400 : 1000;
                case 'Or':
                    return criticalMoment ? 1800 : 1200;
                case 'Platine':
                    return criticalMoment ? 2000 : 1400;
                default:
                    return 1000;
            }
        }
        if (behavior === Player_1.BotBehavior.aggressive) {
            return difficulty.name === 'Or' || difficulty.name === 'Platine' ? 600 : 500;
        }
        return 900;
    }
    static chooseCardToLook(bot, difficulty) {
        const memory = this.getBotMemory(bot);
        const unknown = [];
        for (let i = 0; i < bot.hand.length; i++) {
            if (i >= memory.mentalMap.length || memory.mentalMap[i] === null) {
                unknown.push(i);
            }
        }
        if (unknown.length > 0) {
            return unknown[Math.floor(this.random() * unknown.length)];
        }
        if (bot.botBehavior === Player_1.BotBehavior.balanced &&
            (difficulty.name === 'Or' || difficulty.name === 'Platine')) {
            let worstIdx = 0;
            let worstVal = -1;
            for (let i = 0; i < memory.mentalMap.length; i++) {
                if (memory.mentalMap[i] !== null && memory.mentalMap[i].points > worstVal) {
                    worstVal = memory.mentalMap[i].points;
                    worstIdx = i;
                }
            }
            return worstIdx;
        }
        return Math.floor(this.random() * bot.hand.length);
    }
    static chooseSpyTarget(gs, bot, difficulty) {
        const opponents = gs.players.filter((p) => p.id !== bot.id && p.hand.length > 0);
        if (opponents.length === 0)
            return null;
        const behavior = bot.botBehavior;
        if (difficulty.name === 'Or' ||
            difficulty.name === 'Platine' ||
            behavior === Player_1.BotBehavior.balanced) {
            opponents.sort((a, b) => this.getEstimatedScore(a) - this.getEstimatedScore(b));
            if (this.random() < 0.80) {
                return opponents[0];
            }
        }
        return opponents[Math.floor(this.random() * opponents.length)];
    }
    static async executeValetStrategy(gs, bot, difficulty) {
        const behavior = bot.botBehavior;
        const target = this.chooseValetTarget(gs, bot, difficulty);
        if (!target || target.hand.length === 0)
            return;
        const myCardIdx = this.chooseBadCard(bot);
        const targetIdx = this.chooseValetTargetCardIndex(target, difficulty, behavior);
        const confused = this.random() < difficulty.confusionOnSwap;
        if (!confused) {
            this.forgetCard(bot, myCardIdx);
        }
        GameLogic_1.GameLogic.swapCards(gs, bot, myCardIdx, target, targetIdx);
    }
    static chooseValetTarget(gs, bot, difficulty) {
        const opponents = gs.players.filter((p) => p.id !== bot.id && p.hand.length > 0);
        if (opponents.length === 0)
            return null;
        const behavior = bot.botBehavior;
        if (difficulty.name === 'Bronze') {
            if (this.random() < 0.25) {
                return this.selectValetTargetWeighted(opponents, difficulty, gs);
            }
            return opponents[Math.floor(this.random() * opponents.length)];
        }
        if (behavior === Player_1.BotBehavior.fast) {
            opponents.sort((a, b) => b.hand.length - a.hand.length);
            return opponents[0];
        }
        if (behavior === Player_1.BotBehavior.aggressive) {
            const human = opponents.find((p) => p.isHuman);
            if (human) {
                let humanBias;
                if (difficulty.name === 'Platine') {
                    humanBias = 0.85;
                }
                else if (difficulty.name === 'Or') {
                    humanBias = 0.75;
                }
                else if (difficulty.name === 'Argent') {
                    humanBias = 0.55;
                }
                else {
                    humanBias = 0.35;
                }
                if (this.random() < humanBias) {
                    return human;
                }
            }
            const lowCardTargets = opponents.filter((p) => p.hand.length <= 3);
            if (lowCardTargets.length > 0 && this.random() < 0.80) {
                return lowCardTargets[Math.floor(this.random() * lowCardTargets.length)];
            }
            return this.selectValetTargetWeighted(opponents, difficulty, gs);
        }
        if (behavior === Player_1.BotBehavior.balanced) {
            if (difficulty.name === 'Bronze' || difficulty.name === 'Argent') {
                if (this.random() < 0.80) {
                    return this.selectValetTargetWeighted(opponents, difficulty, gs);
                }
                return opponents[Math.floor(this.random() * opponents.length)];
            }
            // Or/Platine : hybride
            if (this.random() < 0.35) {
                opponents.sort((a, b) => b.hand.length - a.hand.length);
                return opponents[0];
            }
            else {
                const human = opponents.find((p) => p.isHuman);
                if (human) {
                    const humanBias = difficulty.name === 'Platine' ? 0.75 : 0.65;
                    if (this.random() < humanBias) {
                        return human;
                    }
                }
                return this.selectValetTargetWeighted(opponents, difficulty, gs);
            }
        }
        return opponents[Math.floor(this.random() * opponents.length)];
    }
    static chooseValetTargetCardIndex(target, difficulty, behavior) {
        if (target.hand.length === 0)
            return 0;
        if (target.hand.length === 1)
            return 0;
        const indices = target.hand.map((_, i) => i);
        indices.sort((a, b) => target.hand[a].points - target.hand[b].points);
        const bestIdx = indices[0];
        const secondIdx = indices.length > 1 ? indices[1] : bestIdx;
        let smartChance;
        if (difficulty.name === 'Bronze') {
            smartChance = 0.25;
        }
        else if (difficulty.name === 'Argent') {
            smartChance = 0.50;
        }
        else if (difficulty.name === 'Or') {
            smartChance = 0.80;
        }
        else {
            smartChance = 1.0;
        }
        if (behavior === Player_1.BotBehavior.aggressive) {
            smartChance += 0.10;
        }
        else if (behavior === Player_1.BotBehavior.fast) {
            smartChance -= 0.10;
        }
        if (target.isHuman) {
            smartChance += 0.10;
        }
        smartChance = Math.max(0.0, Math.min(1.0, smartChance));
        if (this.random() < smartChance) {
            return bestIdx;
        }
        const secondChance = difficulty.name === 'Bronze' ? 0.35 : 0.55;
        if (this.random() < secondChance) {
            return secondIdx;
        }
        return Math.floor(this.random() * target.hand.length);
    }
    static selectValetTargetWeighted(opponents, difficulty, gameState) {
        const threatScores = new Map();
        for (const player of opponents) {
            let score = 0.0;
            if (player.isHuman) {
                if (difficulty.name === 'Platine') {
                    score += 60.0;
                }
                else if (difficulty.name === 'Or') {
                    score += 50.0;
                }
                else if (difficulty.name === 'Argent') {
                    score += 35.0;
                }
                else {
                    score += 20.0;
                }
            }
            const cardCount = player.hand.length;
            if (cardCount === 1) {
                score += 130.0;
            }
            else if (cardCount === 2) {
                score += 90.0;
            }
            else if (cardCount === 3) {
                score += 55.0;
            }
            else if (cardCount === 4) {
                score += 25.0;
            }
            else {
                score += 10.0;
            }
            const estimatedScore = this.getEstimatedScore(player);
            if (estimatedScore <= 5) {
                score += 35.0;
            }
            else if (estimatedScore <= 10) {
                score += 22.0;
            }
            else if (estimatedScore <= 15) {
                score += 12.0;
            }
            const bestPoints = this.minPointsInHand(player);
            if (difficulty.name === 'Platine') {
                score += (13 - bestPoints) * 4.0;
            }
            else if (difficulty.name === 'Or') {
                score += (13 - bestPoints) * 3.0;
            }
            else if (difficulty.name === 'Argent') {
                score += (13 - bestPoints) * 2.0;
            }
            else {
                score += (13 - bestPoints) * 1.0;
            }
            if (gameState.gameMode === GameState_1.GameMode.tournament) {
                const cumulativeScore = this.getCumulativeScore(gameState, player);
                if (cumulativeScore <= 20) {
                    score += 25.0;
                }
                else if (cumulativeScore <= 40) {
                    score += 15.0;
                }
                else if (cumulativeScore >= 80) {
                    score -= 20.0;
                }
            }
            const randomBonus = this.random() * 30.0;
            if (difficulty.name === 'Or' || difficulty.name === 'Platine') {
                score += randomBonus * 0.3;
            }
            else {
                score += randomBonus * 1.0;
            }
            threatScores.set(player, score);
        }
        let selectedTarget = opponents[0];
        let maxScore = 0.0;
        threatScores.forEach((score, player) => {
            if (score > maxScore) {
                maxScore = score;
                selectedTarget = player;
            }
        });
        return selectedTarget;
    }
    static async executeJokerStrategy(gs, bot, difficulty) {
        const behavior = bot.botBehavior;
        let possibleTargets = gs.players.filter((p) => p.id !== bot.id);
        if (possibleTargets.length === 0) {
            possibleTargets = [bot];
        }
        let target;
        if (behavior === Player_1.BotBehavior.fast) {
            possibleTargets.sort((a, b) => this.getEstimatedScore(a) - this.getEstimatedScore(b));
            target = possibleTargets[0];
        }
        else if (behavior === Player_1.BotBehavior.aggressive) {
            const human = possibleTargets.find((p) => p.isHuman);
            if (human) {
                let humanBias;
                if (difficulty.name === 'Platine') {
                    humanBias = 0.85;
                }
                else if (difficulty.name === 'Or') {
                    humanBias = 0.75;
                }
                else if (difficulty.name === 'Argent') {
                    humanBias = 0.55;
                }
                else {
                    humanBias = 0.35;
                }
                if (this.random() < humanBias) {
                    target = human;
                }
            }
            if (!target) {
                if (difficulty.name !== 'Bronze' && this.random() < 0.75) {
                    target = this.selectJokerTargetWeighted(possibleTargets, difficulty, gs);
                }
                else {
                    target = possibleTargets[Math.floor(this.random() * possibleTargets.length)];
                }
            }
        }
        else if (behavior === Player_1.BotBehavior.balanced) {
            if (difficulty.name === 'Bronze' || difficulty.name === 'Argent') {
                if (difficulty.name === 'Bronze') {
                    if (this.random() < 0.25) {
                        target = this.selectJokerTargetWeighted(possibleTargets, difficulty, gs);
                    }
                    else {
                        target = possibleTargets[Math.floor(this.random() * possibleTargets.length)];
                    }
                }
                else {
                    target = this.selectJokerTargetWeighted(possibleTargets, difficulty, gs);
                }
            }
            else {
                if (this.random() < 0.35) {
                    possibleTargets.sort((a, b) => this.getEstimatedScore(a) - this.getEstimatedScore(b));
                    target = possibleTargets[0];
                }
                else {
                    const human = possibleTargets.find((p) => p.isHuman);
                    if (human) {
                        const humanBias = difficulty.name === 'Platine' ? 0.80 : 0.70;
                        if (this.random() < humanBias) {
                            target = human;
                        }
                    }
                    if (!target) {
                        target = this.selectJokerTargetWeighted(possibleTargets, difficulty, gs);
                    }
                }
            }
        }
        else {
            if (difficulty.name !== 'Bronze' && this.random() < 0.3) {
                target = this.selectJokerTargetWeighted(possibleTargets, difficulty, gs);
            }
            else {
                target = possibleTargets[Math.floor(this.random() * possibleTargets.length)];
            }
        }
        GameLogic_1.GameLogic.jokerEffect(gs, target);
        if (target.id === bot.id) {
            this.resetMentalMap(bot);
        }
    }
    static selectJokerTargetWeighted(targets, difficulty, gameState) {
        const threatScores = new Map();
        for (const player of targets) {
            let score = 0.0;
            if (player.isHuman) {
                if (difficulty.name === 'Platine') {
                    score += 65.0;
                }
                else if (difficulty.name === 'Or') {
                    score += 55.0;
                }
                else if (difficulty.name === 'Argent') {
                    score += 40.0;
                }
                else {
                    score += 25.0;
                }
            }
            const knownCount = this.getKnownCardCount(player);
            if (knownCount >= 4) {
                score += 24.0;
            }
            else if (knownCount >= 2) {
                score += 16.0;
            }
            else if (knownCount >= 1) {
                score += 8.0;
            }
            const cardCount = player.hand.length;
            if (cardCount <= 2) {
                score += 65.0;
            }
            else if (cardCount === 3) {
                score += 40.0;
            }
            else if (cardCount === 4) {
                score += 20.0;
            }
            const estimatedScore = this.getEstimatedScore(player);
            if (estimatedScore <= 5) {
                score += 28.0;
            }
            else if (estimatedScore <= 10) {
                score += 16.0;
            }
            else if (estimatedScore <= 15) {
                score += 8.0;
            }
            if (gameState.gameMode === GameState_1.GameMode.tournament) {
                const cumulativeScore = this.getCumulativeScore(gameState, player);
                if (cumulativeScore <= 20) {
                    score += 20.0;
                }
                else if (cumulativeScore <= 40) {
                    score += 10.0;
                }
                else if (cumulativeScore >= 80) {
                    score -= 15.0;
                }
            }
            const randomFactor = this.random() * 20.0;
            if (difficulty.name === 'Or' || difficulty.name === 'Platine') {
                score += randomFactor * 0.3;
            }
            else if (difficulty.name === 'Argent') {
                score += randomFactor * 1.0;
            }
            else {
                score += randomFactor * 2.0;
            }
            threatScores.set(player, score);
        }
        let selectedTarget = targets[0];
        let maxScore = 0.0;
        threatScores.forEach((score, player) => {
            if (score > maxScore) {
                maxScore = score;
                selectedTarget = player;
            }
        });
        return selectedTarget;
    }
    static chooseBadCard(bot) {
        const memory = this.getBotMemory(bot);
        let worstIdx = 0;
        let worstValue = -1;
        for (let i = 0; i < memory.mentalMap.length; i++) {
            if (memory.mentalMap[i] !== null && memory.mentalMap[i].points > worstValue) {
                worstValue = memory.mentalMap[i].points;
                worstIdx = i;
            }
        }
        if (worstValue === -1) {
            return this.chooseUnknownCard(bot);
        }
        return worstIdx;
    }
    static chooseUnknownCard(bot) {
        const memory = this.getBotMemory(bot);
        const unknownIndices = [];
        for (let i = 0; i < bot.hand.length; i++) {
            if (i >= memory.mentalMap.length || memory.mentalMap[i] === null) {
                unknownIndices.push(i);
            }
        }
        if (unknownIndices.length > 0) {
            return unknownIndices[Math.floor(this.random() * unknownIndices.length)];
        }
        return 0;
    }
    static minPointsInHand(player) {
        if (player.hand.length === 0)
            return 0;
        let minPoints = player.hand[0].points;
        for (let i = 1; i < player.hand.length; i++) {
            const points = player.hand[i].points;
            if (points < minPoints) {
                minPoints = points;
            }
        }
        return minPoints;
    }
    static getSkillDifficulty(level) {
        if (level === undefined)
            return BotDifficulty_1.BotDifficulty.silver;
        switch (level) {
            case Player_1.BotSkillLevel.bronze:
                return BotDifficulty_1.BotDifficulty.bronze;
            case Player_1.BotSkillLevel.silver:
                return BotDifficulty_1.BotDifficulty.silver;
            case Player_1.BotSkillLevel.gold:
                return BotDifficulty_1.BotDifficulty.gold;
            case Player_1.BotSkillLevel.platinum:
                return BotDifficulty_1.BotDifficulty.platinum;
            default:
                return BotDifficulty_1.BotDifficulty.silver;
        }
    }
    static isHumanThreatening(gs) {
        try {
            const human = gs.players.find((p) => p.isHuman);
            return human ? human.hand.length <= 3 : false;
        }
        catch (e) {
            return false;
        }
    }
    static delay(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
    }
    // Méthode pour nettoyer la mémoire d'un bot (utile lors du reset d'un jeu)
    static clearBotMemory(playerId) {
        botMemories.delete(playerId);
    }
    // Méthode pour nettoyer toutes les mémoires
    static clearAllBotMemories() {
        botMemories.clear();
    }
}
exports.BotAI = BotAI;
