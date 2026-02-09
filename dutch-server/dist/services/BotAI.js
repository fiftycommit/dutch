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
const botMemories = new Map();
class BotAI {
    static random() {
        return Math.random();
    }
    // ============================================================
    // MÉMOIRE
    // ============================================================
    static getBotMemory(player) {
        if (!botMemories.has(player.id)) {
            botMemories.set(player.id, {
                mentalMap: new Array(player.hand.length).fill(null),
                consecutiveBadDraws: 0,
                dutchHistory: [],
                spiedCards: [],
                turnCounter: 0,
            });
        }
        return botMemories.get(player.id);
    }
    static initializeBotMemory(player) {
        if (player.isHuman || player.hand.length < 2)
            return;
        const memory = this.getBotMemory(player);
        memory.mentalMap = new Array(player.hand.length).fill(null);
        // Choisir 2 positions aléatoires parmi les cartes disponibles
        const indices = Array.from({ length: player.hand.length }, (_, i) => i);
        const idx1 = indices.splice(Math.floor(this.random() * indices.length), 1)[0];
        const idx2 = indices[Math.floor(this.random() * indices.length)];
        memory.mentalMap[idx1] = player.hand[idx1];
        memory.mentalMap[idx2] = player.hand[idx2];
        player.knownCards[idx1] = true;
        player.knownCards[idx2] = true;
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
        // Si 1 seule carte, on la connaît encore (une seule position possible)
        if (player.hand.length === 1) {
            memory.mentalMap[0] = player.hand[0];
            player.knownCards[0] = true;
        }
    }
    // Oubli contextuel — le cerveau est occupé ailleurs
    static applyContextualForget(bot, difficulty, context) {
        if (context === 'joker_self') {
            this.resetMentalMap(bot);
            return;
        }
        let forgetChance;
        if (context === 'valet') {
            forgetChance =
                difficulty.name === 'Bronze' ? 0.40 :
                    difficulty.name === 'Argent' ? 0.20 :
                        difficulty.name === 'Or' ? 0.05 : 0.0;
        }
        else {
            // spy
            forgetChance =
                difficulty.name === 'Bronze' ? 0.25 :
                    difficulty.name === 'Argent' ? 0.10 :
                        difficulty.name === 'Or' ? 0.02 : 0.0;
        }
        if (forgetChance > 0 && this.random() < forgetChance) {
            // Oublier 1 carte connue au hasard
            const memory = this.getBotMemory(bot);
            const knownIndices = [];
            for (let i = 0; i < bot.hand.length; i++) {
                if (i < memory.mentalMap.length && memory.mentalMap[i] !== null) {
                    knownIndices.push(i);
                }
            }
            if (knownIndices.length > 0) {
                const idx = knownIndices[Math.floor(this.random() * knownIndices.length)];
                this.forgetCard(bot, idx);
            }
        }
    }
    // ============================================================
    // SCORE & CONNAISSANCE
    // ============================================================
    static getKnownScore(bot) {
        const memory = this.getBotMemory(bot);
        let score = 0;
        for (let i = 0; i < bot.hand.length; i++) {
            if (i < memory.mentalMap.length && memory.mentalMap[i] !== null) {
                score += memory.mentalMap[i].points;
            }
            else if (i < bot.knownCards.length && bot.knownCards[i]) {
                score += bot.hand[i].points;
            }
        }
        return score;
    }
    static knowsAllCards(bot) {
        const memory = this.getBotMemory(bot);
        for (let i = 0; i < bot.hand.length; i++) {
            const inMental = i < memory.mentalMap.length && memory.mentalMap[i] !== null;
            const inKnown = i < bot.knownCards.length && bot.knownCards[i];
            if (!inMental && !inKnown)
                return false;
        }
        return true;
    }
    static getKnownCardValue(bot, index) {
        const memory = this.getBotMemory(bot);
        if (index < memory.mentalMap.length && memory.mentalMap[index] !== null) {
            return memory.mentalMap[index].points;
        }
        if (index < bot.knownCards.length && bot.knownCards[index]) {
            return bot.hand[index].points;
        }
        return null;
    }
    static getKnownCard(bot, index) {
        const memory = this.getBotMemory(bot);
        if (index < memory.mentalMap.length && memory.mentalMap[index] !== null) {
            return memory.mentalMap[index];
        }
        if (index < bot.knownCards.length && bot.knownCards[index]) {
            return bot.hand[index];
        }
        return null;
    }
    static getKnownCardCount(bot) {
        let count = 0;
        for (let i = 0; i < bot.hand.length; i++) {
            if (this.getKnownCard(bot, i) !== null)
                count++;
        }
        return count;
    }
    // ============================================================
    // OBSERVATION — données tirées de l'historique visible
    // ============================================================
    static getDiscardRate(gs, player) {
        let discards = 0;
        let swaps = 0;
        for (const entry of gs.actionHistory) {
            if (entry.includes(player.name)) {
                if (entry.includes('défausse sa pioche')) {
                    discards++;
                }
                else if (entry.includes('échange une carte')) {
                    swaps++;
                }
            }
        }
        const total = discards + swaps;
        if (total === 0)
            return 0;
        return discards / total;
    }
    static getFailedMatchCount(gs, player) {
        let count = 0;
        for (const entry of gs.actionHistory) {
            if (entry.includes(player.name) && entry.includes('rate son match')) {
                count++;
            }
        }
        return count;
    }
    static getHumanTarget(opponents) {
        return opponents.find((p) => p.isHuman) || null;
    }
    static getCumulativeScore(gameState, player) {
        return gameState.tournamentCumulativeScores[player.id] || 0;
    }
    // ============================================================
    // PHASES DE JEU
    // ============================================================
    static getBotPhase(bot, gameState) {
        if (!this.knowsAllCards(bot)) {
            return BotGamePhase.exploration;
        }
        if (gameState.gameMode === GameState_1.GameMode.tournament) {
            const cumulativeScore = this.getCumulativeScore(gameState, bot);
            if (cumulativeScore >= 70) {
                return BotGamePhase.endgame;
            }
        }
        const someoneClose = gameState.players.some((p) => p.id !== bot.id && p.hand.length <= 2);
        if (someoneClose) {
            return BotGamePhase.endgame;
        }
        return BotGamePhase.optimization;
    }
    // ============================================================
    // DOUBLONS
    // ============================================================
    static findDuplicateInHand(bot, drawnCard) {
        for (let i = 0; i < bot.hand.length; i++) {
            const known = this.getKnownCard(bot, i);
            if (known && (0, Card_1.cardMatches)(known, drawnCard)) {
                return i;
            }
        }
        return null;
    }
    static findDoublonPairInHand(bot) {
        const knownCards = [];
        for (let i = 0; i < bot.hand.length; i++) {
            const card = this.getKnownCard(bot, i);
            if (card)
                knownCards.push({ idx: i, card });
        }
        for (let a = 0; a < knownCards.length; a++) {
            for (let b = a + 1; b < knownCards.length; b++) {
                if ((0, Card_1.cardMatches)(knownCards[a].card, knownCards[b].card)) {
                    return [knownCards[a].idx, knownCards[b].idx];
                }
            }
        }
        return null;
    }
    // ============================================================
    // TOUR PRINCIPAL
    // ============================================================
    static async playBotTurn(gameState, playerMMR) {
        const bot = (0, GameState_1.getCurrentPlayer)(gameState);
        if (bot.isHuman)
            return;
        const difficulty = playerMMR !== undefined
            ? BotDifficulty_1.BotDifficulty.fromMMR(playerMMR)
            : this.getSkillDifficulty(bot.botSkillLevel);
        const memory = this.getBotMemory(bot);
        memory.turnCounter++;
        const phase = this.getBotPhase(bot, gameState);
        // Délai de réflexion (max 600ms)
        const thinkDelay = difficulty.name === 'Bronze' ? 500 :
            difficulty.name === 'Argent' ? 400 :
                difficulty.name === 'Or' ? 300 : 200;
        await this.delay(thinkDelay);
        if (this.shouldCallDutch(gameState, bot, difficulty, phase)) {
            GameLogic_1.GameLogic.callDutch(gameState);
            return;
        }
        GameLogic_1.GameLogic.drawCard(gameState);
        await this.delay(300);
        await this.decideCardAction(gameState, bot, difficulty, phase);
    }
    // ============================================================
    // DUTCH — algorithme contextuel
    // ============================================================
    static shouldCallDutch(gs, bot, difficulty, phase) {
        // Jamais en exploration — on ne connaît pas toutes nos cartes
        if (phase === BotGamePhase.exploration) {
            return false;
        }
        // 0 cartes → Dutch immédiat
        if (bot.hand.length === 0) {
            return true;
        }
        // On doit connaître toutes nos cartes
        if (!this.knowsAllCards(bot)) {
            return false;
        }
        const knownScore = this.getKnownScore(bot);
        // Score = 0 → Dutch immédiat
        if (knownScore === 0) {
            return true;
        }
        const opponents = gs.players.filter((p) => p.id !== bot.id && !p.isSpectator);
        // Mode tournoi : ULTRA PRUDENT
        if (gs.gameMode === GameState_1.GameMode.tournament) {
            return this.shouldCallDutchTournament(gs, bot, knownScore, opponents, difficulty);
        }
        // Mode partie rapide : analyse contextuelle
        return this.shouldCallDutchQuick(gs, bot, knownScore, opponents, difficulty);
    }
    static shouldCallDutchTournament(gs, bot, knownScore, opponents, difficulty) {
        // En tournoi, Dutch raté = éliminé. Tant qu'on n'est pas dernier, on reste en course.
        // Score = 1 ET tous les adversaires ont >= 3 cartes → Dutch
        if (knownScore === 1) {
            const allHaveMany = opponents.every((p) => p.hand.length >= 3);
            if (allHaveMany)
                return true;
        }
        // Pression extrême : score cumulé >= 90 → se permettre de Dutch avec score <= 2
        const cumulativeScore = this.getCumulativeScore(gs, bot);
        if (cumulativeScore >= 90 && knownScore <= 2) {
            const noDangerousOpponent = opponents.every((p) => p.hand.length >= 2);
            if (noDangerousOpponent)
                return true;
        }
        // Espion intel en tournoi aussi
        if (this.canDutchFromSpyIntel(gs, bot, knownScore, opponents)) {
            return true;
        }
        // Sinon → ne PAS Dutch en tournoi
        return false;
    }
    static shouldCallDutchQuick(gs, bot, knownScore, opponents, difficulty) {
        // Espion intel : si j'ai vu une carte adverse plus grosse que mon score
        if (this.canDutchFromSpyIntel(gs, bot, knownScore, opponents)) {
            return true;
        }
        // Vérifier les menaces
        for (const opp of opponents) {
            // Adversaire avec 0 carte = score 0 garanti → ne Dutch que si notre score = 0
            if (opp.hand.length === 0) {
                return false; // knownScore > 0 ici, donc on ne peut pas battre un 0
            }
            // Adversaire avec 1 carte = très dangereux
            if (opp.hand.length === 1 && knownScore > 2) {
                return false;
            }
        }
        // Seuil de base par difficulté
        const baseThreshold = difficulty.name === 'Bronze' ? 7 :
            difficulty.name === 'Argent' ? 5 :
                difficulty.name === 'Or' ? 4 : 3;
        if (knownScore > baseThreshold) {
            return false;
        }
        // Évaluer si les adversaires sont en difficulté
        let opponentsInTrouble = 0;
        for (const opp of opponents) {
            const failedMatches = this.getFailedMatchCount(gs, opp);
            const hasMany = opp.hand.length >= 5;
            if (failedMatches >= 2 || hasMany) {
                opponentsInTrouble++;
            }
        }
        // Si la majorité des adversaires sont en difficulté → Dutch
        if (opponentsInTrouble >= Math.ceil(opponents.length / 2)) {
            return true;
        }
        // Si on a un très bon score ET pas de menace directe → Dutch
        if (knownScore <= 2) {
            return true;
        }
        // Vérifier le taux de défausse des adversaires
        const dangerousDiscardRate = opponents.some((opp) => this.getDiscardRate(gs, opp) > 0.6);
        if (dangerousDiscardRate && knownScore > 3) {
            return false; // Un adversaire a probablement une bonne main
        }
        // Historique Dutch : confiance basée sur les résultats passés
        const memory = this.getBotMemory(bot);
        if (memory.dutchHistory.length >= 2) {
            const recentWins = memory.dutchHistory.slice(-3).filter((a) => a.won).length;
            if (recentWins >= 2) {
                return true; // Confiance élevée
            }
        }
        return false;
    }
    // Utiliser l'intelligence du 10 (espion) pour décider Dutch
    static canDutchFromSpyIntel(gs, bot, knownScore, opponents) {
        const memory = this.getBotMemory(bot);
        if (memory.spiedCards.length === 0)
            return false;
        for (const spy of memory.spiedCards) {
            // Info trop ancienne (plus de 3 tours) → obsolète
            if (memory.turnCounter - spy.turnNumber > 3)
                continue;
            const target = opponents.find((p) => p.id === spy.playerId);
            if (!target)
                continue;
            // La carte vue est plus grosse que notre score → on a de bonnes chances
            if (spy.cardPoints > knownScore) {
                // Vérifier que l'adversaire n'a pas échangé depuis (il a défaussé sa pioche = main intacte)
                const lastAction = gs.actionHistory.find((e) => e.includes(target.name));
                if (lastAction && lastAction.includes('défausse sa pioche')) {
                    return true;
                }
            }
        }
        return false;
    }
    // ============================================================
    // ACTION APRÈS PIOCHE
    // ============================================================
    static async decideCardAction(gs, bot, difficulty, phase) {
        const drawn = gs.drawnCard;
        if (!drawn)
            return;
        const drawnVal = drawn.points;
        const memory = this.getBotMemory(bot);
        // === EXPLORATION : doublon-aware ===
        if (phase === BotGamePhase.exploration) {
            // D'abord vérifier les doublons (même en exploration)
            const duplicateIdx = this.findDuplicateInHand(bot, drawn);
            if (duplicateIdx !== null) {
                // Défausser la pioche → réaction → matcher le doublon en main
                GameLogic_1.GameLogic.discardDrawnCard(gs);
                memory.consecutiveBadDraws = 0;
                return;
            }
            // Pas de doublon : échanger contre une carte inconnue pour apprendre
            const unknownIndices = [];
            for (let i = 0; i < bot.hand.length; i++) {
                if (i >= memory.mentalMap.length || memory.mentalMap[i] === null) {
                    if (i >= bot.knownCards.length || !bot.knownCards[i]) {
                        unknownIndices.push(i);
                    }
                }
            }
            if (unknownIndices.length > 0) {
                const replaceIdx = unknownIndices[Math.floor(this.random() * unknownIndices.length)];
                const confused = this.random() < difficulty.confusionOnSwap;
                if (!confused) {
                    this.updateMentalMap(bot, replaceIdx, drawn);
                }
                GameLogic_1.GameLogic.replaceCard(gs, replaceIdx);
                return;
            }
        }
        // === OPTIMIZATION / ENDGAME ===
        // Tactique 1 : doublon pioche/main → défausser la pioche, matcher en réaction
        const duplicateIdx = this.findDuplicateInHand(bot, drawn);
        if (duplicateIdx !== null) {
            GameLogic_1.GameLogic.discardDrawnCard(gs);
            memory.consecutiveBadDraws = 0;
            return;
        }
        // Tactique 2 : doublon en main, pioche meilleure → échanger + matcher l'autre
        const doublonPair = this.findDoublonPairInHand(bot);
        if (doublonPair) {
            const [idx1, idx2] = doublonPair;
            const val1 = this.getKnownCardValue(bot, idx1);
            if (val1 !== null && drawnVal < val1) {
                const confused = this.random() < difficulty.confusionOnSwap;
                if (!confused) {
                    this.updateMentalMap(bot, idx1, drawn);
                }
                GameLogic_1.GameLogic.replaceCard(gs, idx1);
                memory.consecutiveBadDraws = 0;
                return;
            }
        }
        // Standard : si pioche < pire carte connue → échanger
        let worstKnownValue = -1;
        let worstKnownIdx = -1;
        for (let i = 0; i < bot.hand.length; i++) {
            const val = this.getKnownCardValue(bot, i);
            if (val !== null && val > worstKnownValue) {
                worstKnownValue = val;
                worstKnownIdx = i;
            }
        }
        if (worstKnownIdx !== -1 && drawnVal < worstKnownValue) {
            const confused = this.random() < difficulty.confusionOnSwap;
            if (!confused) {
                this.updateMentalMap(bot, worstKnownIdx, drawn);
            }
            GameLogic_1.GameLogic.replaceCard(gs, worstKnownIdx);
            memory.consecutiveBadDraws = 0;
        }
        else {
            GameLogic_1.GameLogic.discardDrawnCard(gs);
            memory.consecutiveBadDraws++;
        }
    }
    // ============================================================
    // RÉACTION / MATCH — déterministe
    // ============================================================
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
        const topDiscard = gameState.discardPile[gameState.discardPile.length - 1];
        const memory = this.getBotMemory(bot);
        // Parcourir la mentalMap : est-ce que je CONNAIS une carte qui matche ?
        for (let i = 0; i < bot.hand.length; i++) {
            const knownCard = (i < memory.mentalMap.length && memory.mentalMap[i] !== null)
                ? memory.mentalMap[i]
                : (i < bot.knownCards.length && bot.knownCards[i]) ? bot.hand[i] : null;
            if (knownCard && (0, Card_1.cardMatches)(knownCard, topDiscard)) {
                // Je connais cette carte et elle matche → match immédiat
                const reactionDelay = difficulty.name === 'Platine' ? 150 :
                    difficulty.name === 'Or' ? 250 :
                        difficulty.name === 'Argent' ? 350 : 400;
                await this.delay(reactionDelay);
                const success = GameLogic_1.GameLogic.matchCard(gameState, bot, i);
                if (success && i < memory.mentalMap.length) {
                    memory.mentalMap.splice(i, 1);
                }
                return success;
            }
        }
        // Je ne connais aucune carte qui matche → ne rien faire (ZERO match aveugle)
        return false;
    }
    // ============================================================
    // POUVOIRS SPÉCIAUX
    // ============================================================
    static async useBotSpecialPower(gameState, playerMMR) {
        if (!gameState.isWaitingForSpecialPower || !gameState.specialCardToActivate)
            return;
        const bot = (0, GameState_1.getCurrentPlayer)(gameState);
        const card = gameState.specialCardToActivate;
        const difficulty = playerMMR !== undefined
            ? BotDifficulty_1.BotDifficulty.fromMMR(playerMMR)
            : this.getSkillDifficulty(bot.botSkillLevel);
        const phase = this.getBotPhase(bot, gameState);
        await this.delay(400);
        const val = card.value;
        if (val === '7') {
            this.usePower7(gameState, bot, difficulty);
        }
        else if (val === '10') {
            this.usePower10(gameState, bot, difficulty, phase);
        }
        else if (val === 'V') {
            this.usePowerValet(gameState, bot, difficulty);
        }
        else if (val === 'JOKER') {
            this.usePowerJoker(gameState, bot, difficulty);
        }
        gameState.isWaitingForSpecialPower = false;
        gameState.specialCardToActivate = null;
        (0, GameState_1.addToHistory)(gameState, `${bot.name} a utilisé son pouvoir.`);
    }
    // Carte 7 : regarder sa propre carte — toujours utile
    static usePower7(gs, bot, difficulty) {
        const idx = this.chooseCardToLook(bot, difficulty);
        GameLogic_1.GameLogic.lookAtCard(gs, bot, idx);
        this.updateMentalMap(bot, idx, bot.hand[idx]);
    }
    // Carte 10 : espionner un adversaire — décision par phase
    static usePower10(gs, bot, difficulty, phase) {
        const opponents = gs.players.filter((p) => p.id !== bot.id && p.hand.length > 0);
        if (opponents.length === 0) {
            GameLogic_1.GameLogic.skipSpecialPower(gs);
            return;
        }
        // Cas spécial duel : 2 joueurs, chacun avec 1 carte → TOUJOURS espionner
        const activePlayers = gs.players.filter((p) => !p.isSpectator && p.hand.length > 0);
        const duelMode = activePlayers.length === 2 && bot.hand.length <= 1;
        if (duelMode) {
            const target = opponents[0];
            const idx = Math.floor(this.random() * target.hand.length);
            GameLogic_1.GameLogic.lookAtCard(gs, target, idx);
            // Stocker l'info espionnée
            const memory = this.getBotMemory(bot);
            memory.spiedCards.push({
                playerId: target.id,
                cardPoints: target.hand[idx].points,
                cardIndex: idx,
                turnNumber: memory.turnCounter,
            });
            this.applyContextualForget(bot, difficulty, 'spy');
            return;
        }
        // Platine/Or en exploration : skip (pas utile quand on ne connaît pas ses propres cartes)
        if (phase === BotGamePhase.exploration) {
            if (difficulty.name === 'Platine' || difficulty.name === 'Or') {
                GameLogic_1.GameLogic.skipSpecialPower(gs);
                return;
            }
            // Argent : skip si on ne connaît que 0-1 de nos cartes
            if (difficulty.name === 'Argent') {
                const knownCount = this.getKnownCardCount(bot);
                if (knownCount <= 1) {
                    GameLogic_1.GameLogic.skipSpecialPower(gs);
                    return;
                }
            }
            // Bronze : utilise toujours (ne réfléchit pas)
        }
        // Choisir la cible : priorité humain, sinon joueur dangereux
        let target;
        const human = this.getHumanTarget(opponents);
        if (human) {
            target = human;
        }
        else {
            // Le joueur avec le moins de cartes (menace potentielle)
            opponents.sort((a, b) => a.hand.length - b.hand.length);
            target = opponents[0];
        }
        const idx = Math.floor(this.random() * target.hand.length);
        GameLogic_1.GameLogic.lookAtCard(gs, target, idx);
        // Stocker l'info espionnée
        const memory = this.getBotMemory(bot);
        memory.spiedCards.push({
            playerId: target.id,
            cardPoints: target.hand[idx].points,
            cardIndex: idx,
            turnNumber: memory.turnCounter,
        });
        this.applyContextualForget(bot, difficulty, 'spy');
    }
    // Carte V (Valet) : déstabiliser les AUTRES
    static usePowerValet(gs, bot, difficulty) {
        const opponents = gs.players.filter((p) => p.id !== bot.id && p.hand.length > 0);
        if (opponents.length === 0) {
            GameLogic_1.GameLogic.skipSpecialPower(gs);
            return;
        }
        if (opponents.length >= 2) {
            // >= 2 adversaires : échanger entre eux, le bot ne perd rien
            const targets = this.chooseValetTargets(gs, bot, opponents);
            const idx1 = Math.floor(this.random() * targets[0].hand.length);
            const idx2 = Math.floor(this.random() * targets[1].hand.length);
            GameLogic_1.GameLogic.swapCards(gs, targets[0], idx1, targets[1], idx2);
        }
        else {
            // 1 seul adversaire
            const opponent = opponents[0];
            if (opponent.hand.length <= 2) {
                // Adversaire avec 1-2 cartes = forte probabilité de bonne carte
                // Échanger notre pire carte contre la sienne
                const myCardIdx = this.chooseBadCard(bot);
                const targetIdx = Math.floor(this.random() * opponent.hand.length);
                this.forgetCard(bot, myCardIdx);
                GameLogic_1.GameLogic.swapCards(gs, bot, myCardIdx, opponent, targetIdx);
            }
            else {
                // Adversaire avec >= 3 cartes : pas intéressant → passer
                GameLogic_1.GameLogic.skipSpecialPower(gs);
                return;
            }
        }
        this.applyContextualForget(bot, difficulty, 'valet');
    }
    // Choisir 2 cibles pour le Valet parmi les adversaires
    static chooseValetTargets(gs, bot, opponents) {
        // Priorité : humain + joueur le plus dangereux
        const human = this.getHumanTarget(opponents);
        if (human) {
            // L'humain + l'autre adversaire le plus dangereux
            const others = opponents.filter((p) => p.id !== human.id);
            if (others.length > 0) {
                // Joueur avec le moins de cartes (dangereux) ou taux de défausse élevé
                others.sort((a, b) => a.hand.length - b.hand.length);
                return [human, others[0]];
            }
        }
        // Pas d'humain ou humain seul : les deux joueurs les plus dangereux
        const sorted = [...opponents].sort((a, b) => a.hand.length - b.hand.length);
        return [sorted[0], sorted[1]];
    }
    // Carte Joker : mélanger un adversaire — ciblage intelligent
    static usePowerJoker(gs, bot, difficulty) {
        // Filtrer cibles valides : adversaires avec >= 2 cartes (mélanger 0 ou 1 = inutile)
        const validTargets = gs.players.filter((p) => p.id !== bot.id && p.hand.length >= 2);
        if (validTargets.length === 0) {
            // Aucune cible valide → passer le pouvoir
            GameLogic_1.GameLogic.skipSpecialPower(gs);
            return;
        }
        // Priorité : humain
        const human = this.getHumanTarget(validTargets);
        if (human) {
            GameLogic_1.GameLogic.jokerEffect(gs, human);
            return;
        }
        // Sinon : joueur avec le moins de cartes (>= 2) → connaissait sa main
        validTargets.sort((a, b) => a.hand.length - b.hand.length);
        const target = validTargets[0];
        // Ou le joueur avec le taux de défausse le plus élevé (main stable)
        let bestTarget = target;
        let bestRate = this.getDiscardRate(gs, target);
        for (const t of validTargets) {
            const rate = this.getDiscardRate(gs, t);
            if (rate > bestRate) {
                bestRate = rate;
                bestTarget = t;
            }
        }
        GameLogic_1.GameLogic.jokerEffect(gs, bestTarget);
    }
    // ============================================================
    // UTILITAIRES
    // ============================================================
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
        // Toutes connues : re-vérifier la pire (rafraîchir la mémoire)
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
    static delay(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
    }
    static clearBotMemory(playerId) {
        botMemories.delete(playerId);
    }
    static clearAllBotMemories() {
        botMemories.clear();
    }
}
exports.BotAI = BotAI;
