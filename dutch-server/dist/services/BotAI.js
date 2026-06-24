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
// Compteur partagé des Valets utilisés sur l'humain par manche (Bronze uniquement)
// Clé = ID du joueur humain, valeur = nombre de Valets utilisés sur lui cette manche
const valetAttacksOnHuman = new Map();
const MAX_VALET_ATTACKS_BRONZE = 2;
class BotAI {
    static random() {
        return Math.random();
    }
    // ============================================================
    // GESTION VALETS BRONZE (limite partagée entre tous les bots)
    // ============================================================
    /**
     * Retourne l'ID du joueur humain pour tracker les attaques.
     */
    static getHumanId(gs) {
        const human = gs.players.find(p => p.isHuman);
        return human?.id ?? null;
    }
    /**
     * Vérifie si les bots Bronze peuvent encore Valet l'humain (limite de 2 par manche).
     */
    static canValetHuman(gs) {
        const humanId = this.getHumanId(gs);
        if (!humanId)
            return false;
        const attacks = valetAttacksOnHuman.get(humanId) ?? 0;
        return attacks < MAX_VALET_ATTACKS_BRONZE;
    }
    /**
     * Incrémente le compteur de Valets sur l'humain.
     */
    static recordValetOnHuman(gs) {
        const humanId = this.getHumanId(gs);
        if (!humanId)
            return;
        const current = valetAttacksOnHuman.get(humanId) ?? 0;
        valetAttacksOnHuman.set(humanId, current + 1);
    }
    /**
     * Reset le compteur de Valets sur l'humain (appelé au début de chaque manche).
     */
    static resetValetCountForRound(gs) {
        const humanId = this.getHumanId(gs);
        if (humanId) {
            valetAttacksOnHuman.set(humanId, 0);
        }
    }
    // ============================================================
    // MÉMOIRE
    // ============================================================
    static getBotMemory(player) {
        if (!botMemories.has(player.id)) {
            botMemories.set(player.id, {
                mentalMap: new Array(player.hand.length).fill(null),
                discoveredAtTurn: new Array(player.hand.length).fill(null),
                consecutiveBadDraws: 0,
                dutchHistory: [],
                spiedCards: [],
                turnCounter: 0,
                minTurnsBeforeDutch: 0,
                discardTracker: new Map(),
                opponentSwapHistory: [],
                pendingMatchFromSpy: null,
            });
        }
        return botMemories.get(player.id);
    }
    static initializeBotMemory(player, difficulty) {
        if (player.isHuman || player.hand.length < 2)
            return;
        const memory = this.getBotMemory(player);
        memory.mentalMap = new Array(player.hand.length).fill(null);
        memory.discoveredAtTurn = new Array(player.hand.length).fill(null);
        // Minimum de tours avant Dutch
        if (difficulty.name === 'Bronze') {
            memory.minTurnsBeforeDutch = 5 + Math.floor(this.random() * 5); // 5-9
        }
        else if (difficulty.name === 'Argent') {
            memory.minTurnsBeforeDutch = 2 + Math.floor(this.random() * 4); // 2-5
        }
        else {
            memory.minTurnsBeforeDutch = 0;
        }
        // Choisir 2 positions aléatoires parmi les cartes disponibles
        const indices = Array.from({ length: player.hand.length }, (_, i) => i);
        const idx1 = indices.splice(Math.floor(this.random() * indices.length), 1)[0];
        const idx2 = indices[Math.floor(this.random() * indices.length)];
        // Bronze : 30% ne retient qu'1 carte, 15% inverse les 2 positions
        // Argent : 15% ne retient qu'1 carte, 8% inverse les 2 positions
        let forgetSecond = 0;
        if (difficulty.name === 'Bronze')
            forgetSecond = 0.3;
        else if (difficulty.name === 'Argent')
            forgetSecond = 0.15;
        let swapPositions = 0;
        if (difficulty.name === 'Bronze')
            swapPositions = 0.15;
        else if (difficulty.name === 'Argent')
            swapPositions = 0.08;
        if (forgetSecond > 0 && this.random() < forgetSecond) {
            // N'enregistre qu'1 carte
            memory.mentalMap[idx1] = player.hand[idx1];
            memory.discoveredAtTurn[idx1] = 0;
            player.knownCards[idx1] = true;
        }
        else if (swapPositions > 0 && this.random() < swapPositions) {
            // Inverse les 2 positions dans sa tête (croit que carte de gauche est à droite)
            memory.mentalMap[idx1] = player.hand[idx2]; // pense que idx1 contient la carte de idx2
            memory.mentalMap[idx2] = player.hand[idx1]; // et vice-versa
            memory.discoveredAtTurn[idx1] = 0;
            memory.discoveredAtTurn[idx2] = 0;
            player.knownCards[idx1] = true;
            player.knownCards[idx2] = true;
        }
        else {
            // Mémorisation parfaite
            memory.mentalMap[idx1] = player.hand[idx1];
            memory.mentalMap[idx2] = player.hand[idx2];
            memory.discoveredAtTurn[idx1] = 0;
            memory.discoveredAtTurn[idx2] = 0;
            player.knownCards[idx1] = true;
            player.knownCards[idx2] = true;
        }
    }
    static updateMentalMap(player, index, card) {
        const memory = this.getBotMemory(player);
        while (memory.mentalMap.length <= index) {
            memory.mentalMap.push(null);
            memory.discoveredAtTurn.push(null);
        }
        memory.mentalMap[index] = card;
        memory.discoveredAtTurn[index] = memory.turnCounter;
    }
    static forgetCard(player, index) {
        const memory = this.getBotMemory(player);
        if (index >= 0 && index < memory.mentalMap.length) {
            memory.mentalMap[index] = null;
        }
        if (index >= 0 && index < memory.discoveredAtTurn.length) {
            memory.discoveredAtTurn[index] = null;
        }
        if (index >= 0 && index < player.knownCards.length) {
            player.knownCards[index] = false;
        }
    }
    static resetMentalMap(player) {
        const memory = this.getBotMemory(player);
        memory.mentalMap = new Array(player.hand.length).fill(null);
        memory.discoveredAtTurn = new Array(player.hand.length).fill(null);
        player.knownCards = new Array(player.hand.length).fill(false);
        // Si 1 seule carte, on la connaît encore (une seule position possible)
        if (player.hand.length === 1) {
            memory.mentalMap[0] = player.hand[0];
            memory.discoveredAtTurn[0] = memory.turnCounter;
            player.knownCards[0] = true;
        }
    }
    // Confusion passive — distrait par les défausses des autres
    static applyPassiveConfusion(bot, gs, difficulty) {
        // Or/Platine : pas affecté
        if (difficulty.name === 'Or' || difficulty.name === 'Platine')
            return;
        const memory = this.getBotMemory(bot);
        const knownIndices = [];
        for (let i = 0; i < bot.hand.length; i++) {
            if (i < memory.mentalMap.length && memory.mentalMap[i] !== null) {
                knownIndices.push(i);
            }
        }
        if (knownIndices.length < 2)
            return;
        // Compter les défausses récentes dans l'historique (les 10 dernières entrées)
        let recentDiscards = 0;
        const recentHistory = gs.actionHistory.slice(0, 10);
        for (const entry of recentHistory) {
            if (entry.includes('défausse')) {
                recentDiscards++;
            }
        }
        const confuseChance = difficulty.name === 'Bronze' ? 0.3 : 0.15;
        const forgetChance = difficulty.name === 'Bronze' ? 0.2 : 0.1;
        // >= 3 défausses récentes : chance de confondre 2 positions
        if (recentDiscards >= 3 && this.random() < confuseChance) {
            const a = knownIndices[Math.floor(this.random() * knownIndices.length)];
            let b = a;
            while (b === a && knownIndices.length > 1) {
                b = knownIndices[Math.floor(this.random() * knownIndices.length)];
            }
            // Swap les 2 entrées dans mentalMap (le bot confond les positions)
            const tmp = memory.mentalMap[a];
            memory.mentalMap[a] = memory.mentalMap[b];
            memory.mentalMap[b] = tmp;
        }
        // >= 4 défausses : chance supplémentaire d'oublier 1 carte
        if (recentDiscards >= 4 && this.random() < forgetChance) {
            const idx = knownIndices[Math.floor(this.random() * knownIndices.length)];
            this.forgetCard(bot, idx);
        }
    }
    // Oubli contextuel — le cerveau est occupé ailleurs
    static applyContextualForget(bot, difficulty, context) {
        if (context === 'joker_self') {
            this.resetMentalMap(bot);
            return;
        }
        let forgetChance = 0;
        if (context === 'valet') {
            if (difficulty.name === 'Bronze')
                forgetChance = 0.4;
            else if (difficulty.name === 'Argent')
                forgetChance = 0.2;
            else if (difficulty.name === 'Or')
                forgetChance = 0.05;
        }
        else if (context === 'spy') {
            if (difficulty.name === 'Bronze')
                forgetChance = 0.25;
            else if (difficulty.name === 'Argent')
                forgetChance = 0.1;
            else if (difficulty.name === 'Or')
                forgetChance = 0.02;
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
            else if (bot.knownCards[i]) {
                score += bot.hand[i].points;
            }
        }
        return score;
    }
    static knowsAllCards(bot) {
        const memory = this.getBotMemory(bot);
        for (let i = 0; i < bot.hand.length; i++) {
            const inMentalMap = i < memory.mentalMap.length && memory.mentalMap[i] !== null;
            if (!inMentalMap && !bot.knownCards[i])
                return false;
        }
        return true;
    }
    static getKnownCardValue(bot, index) {
        const memory = this.getBotMemory(bot);
        const mapped = memory.mentalMap[index];
        if (index < memory.mentalMap.length && mapped !== null && mapped !== undefined) {
            return mapped.points;
        }
        if (bot.knownCards[index]) {
            return bot.hand[index].points;
        }
        return null;
    }
    static getKnownCard(bot, index) {
        const memory = this.getBotMemory(bot);
        const mapped = memory.mentalMap[index];
        if (index < memory.mentalMap.length && mapped !== null && mapped !== undefined) {
            return mapped;
        }
        if (bot.knownCards[index]) {
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
            if (entry.includes(player.name) && entry.includes('a raté son match')) {
                count++;
            }
        }
        return count;
    }
    static getHumanTarget(opponents) {
        return opponents.find((p) => p.isHuman) || null;
    }
    /**
     * Calcule un score de menace contextuel pour un joueur.
     * Critères : nombre de cartes, taux de défausse (main stable), cartes espionnées, tournoi.
     * L'humain reçoit un léger tiebreaker (+3) : à menace égale, on préfère le cibler.
     */
    static calculateThreatScore(gs, bot, target) {
        let score = 0;
        // 1) Nombre de cartes (le plus important)
        const cards = target.hand.length;
        if (cards === 1)
            score += 50;
        else if (cards === 2)
            score += 30;
        else if (cards === 3)
            score += 15;
        else if (cards === 4)
            score += 5;
        // 2) Taux de défausse élevé = main probablement bonne (il rejette les pioches)
        const discardRate = this.getDiscardRate(gs, target);
        if (discardRate > 0.7)
            score += 20;
        else if (discardRate > 0.5)
            score += 12;
        else if (discardRate > 0.3)
            score += 5;
        // 3) Intel espionnage : si on connaît des cartes basses chez lui
        const memory = this.getBotMemory(bot);
        let knownLowCards = 0;
        for (const spy of memory.spiedCards) {
            if (spy.playerId === target.id && memory.turnCounter - spy.turnNumber <= 5) {
                if (spy.cardPoints <= 3)
                    knownLowCards++;
            }
        }
        if (knownLowCards >= 2)
            score += 15;
        else if (knownLowCards >= 1)
            score += 8;
        // 4) Tournoi : score cumulé bas = menaçant
        if (gs.gameMode === GameState_1.GameMode.tournament) {
            const cumul = this.getCumulativeScore(gs, target);
            if (cumul <= 20)
                score += 15;
            else if (cumul <= 40)
                score += 8;
            else if (cumul >= 80)
                score -= 10;
        }
        // 5) Tiebreaker humain : à menace égale, préférer cibler l'humain
        if (target.isHuman) {
            score += 3;
        }
        return score;
    }
    /**
     * Choisit la cible la plus menaçante parmi les adversaires.
     * Si l'humain est dans le top 2, il est ciblé.
     */
    static pickMostThreateningTarget(gs, bot, candidates) {
        const scored = candidates.map(p => ({
            player: p,
            threat: this.calculateThreatScore(gs, bot, p),
        }));
        scored.sort((a, b) => b.threat - a.threat);
        // Si l'humain est dans le top 2, le cibler
        const top2 = scored.slice(0, 2);
        const humanInTop2 = top2.find(s => s.player.isHuman);
        if (humanInTop2)
            return humanInTop2.player;
        return scored[0].player;
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
        const difficulty = playerMMR === undefined
            ? this.getSkillDifficulty(bot.botSkillLevel)
            : BotDifficulty_1.BotDifficulty.fromMMR(playerMMR);
        const memory = this.getBotMemory(bot);
        memory.turnCounter++;
        // Premier tour : initialiser la mémoire avec erreurs selon le niveau
        if (memory.turnCounter === 1) {
            this.initializeBotMemory(bot, difficulty);
            // Reset du compteur de Valets Bronze sur l'humain au début de la manche
            this.resetValetCountForRound(gameState);
        }
        // Confusion passive (Bronze/Argent : distraits par les défausses)
        this.applyPassiveConfusion(bot, gameState, difficulty);
        // Platine : observer la table (défausse, swaps adverses, matchs)
        if (difficulty.name === 'Platine') {
            this.updateDiscardTracker(gameState, bot);
            this.updateOpponentObservation(gameState, bot);
        }
        const phase = this.getBotPhase(bot, gameState);
        // Délai de réflexion (max 600ms)
        let thinkDelay = 200;
        if (difficulty.name === 'Bronze')
            thinkDelay = 500;
        else if (difficulty.name === 'Argent')
            thinkDelay = 400;
        else if (difficulty.name === 'Or')
            thinkDelay = 300;
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
        // 0 cartes → Dutch immédiat (tous niveaux)
        if (bot.hand.length === 0) {
            return true;
        }
        // Bronze/Argent : minimum de tours avant Dutch
        const memory = this.getBotMemory(bot);
        if (memory.minTurnsBeforeDutch > 0 && memory.turnCounter < memory.minTurnsBeforeDutch) {
            return false;
        }
        // Bronze : Dutch impulsif, aucune analyse
        if (difficulty.name === 'Bronze') {
            return this.shouldCallDutchBronze(bot);
        }
        // Argent en endgame : se concentre → stratégie Platine avec seuil 4
        if (difficulty.name === 'Argent' && phase === BotGamePhase.endgame) {
            return this.shouldCallDutchArgentEndgame(gs, bot, difficulty);
        }
        // Argent en mode normal : Dutch basique
        if (difficulty.name === 'Argent') {
            return this.shouldCallDutchArgent(gs, bot);
        }
        // --- Or / Platine : algorithme complet ---
        // Jamais en exploration — on ne connaît pas toutes nos cartes
        if (phase === BotGamePhase.exploration) {
            return false;
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
    // Bronze : "j'ai un petit score, j'y vais" — sans regarder les autres
    static shouldCallDutchBronze(bot) {
        if (!this.knowsAllCards(bot))
            return false;
        const knownScore = this.getKnownScore(bot);
        if (knownScore === 0)
            return true;
        return knownScore <= 7;
    }
    // Argent normal : score + 1 menace basique
    static shouldCallDutchArgent(gs, bot) {
        if (!this.knowsAllCards(bot))
            return false;
        const knownScore = this.getKnownScore(bot);
        if (knownScore === 0)
            return true;
        if (knownScore > 5)
            return false;
        // Vérifie UNE menace : adversaire avec 0 carte
        const opponents = gs.players.filter((p) => p.id !== bot.id && !p.isSpectator);
        for (const opp of opponents) {
            if (opp.hand.length === 0)
                return false;
        }
        // Spy intel : si Argent a mémorisé une grosse carte chez un adversaire, Dutch plus sûr
        if (this.canDutchFromSpyIntel(gs, bot, knownScore, opponents))
            return true;
        return true;
    }
    // Argent en endgame : se concentre → analyse complète avec seuil 4
    static shouldCallDutchArgentEndgame(gs, bot, difficulty) {
        if (!this.knowsAllCards(bot))
            return false;
        const knownScore = this.getKnownScore(bot);
        if (knownScore === 0)
            return true;
        const opponents = gs.players.filter((p) => p.id !== bot.id && !p.isSpectator);
        // Mode tournoi
        if (gs.gameMode === GameState_1.GameMode.tournament) {
            return this.shouldCallDutchTournament(gs, bot, knownScore, opponents, difficulty);
        }
        // Analyse complète (comme Platine) mais seuil = 4
        if (this.canDutchFromSpyIntel(gs, bot, knownScore, opponents))
            return true;
        for (const opp of opponents) {
            if (opp.hand.length === 0)
                return false;
            if (opp.hand.length === 1 && knownScore > 2)
                return false;
        }
        if (knownScore > 4)
            return false;
        // Évaluer adversaires en difficulté
        let opponentsInTrouble = 0;
        for (const opp of opponents) {
            const failedMatches = this.getFailedMatchCount(gs, opp);
            if (failedMatches >= 2 || opp.hand.length >= 5)
                opponentsInTrouble++;
        }
        if (opponentsInTrouble >= Math.ceil(opponents.length / 2))
            return true;
        if (knownScore <= 2)
            return true;
        const dangerousDiscardRate = opponents.some((opp) => this.getDiscardRate(gs, opp) > 0.6);
        if (dangerousDiscardRate && knownScore > 3)
            return false;
        return false;
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
        // Espion intel en tournoi : Platine uniquement
        if (difficulty.name === 'Platine' && this.canDutchFromSpyIntel(gs, bot, knownScore, opponents)) {
            return true;
        }
        // Sinon → ne PAS Dutch en tournoi
        return false;
    }
    static shouldCallDutchQuick(gs, bot, knownScore, opponents, difficulty) {
        // Espion intel : Or et Platine utilisent le spy intel pour décider Dutch
        if ((difficulty.name === 'Platine' || difficulty.name === 'Or') && this.canDutchFromSpyIntel(gs, bot, knownScore, opponents)) {
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
        let baseThreshold = 3;
        if (difficulty.name === 'Bronze')
            baseThreshold = 7;
        else if (difficulty.name === 'Argent')
            baseThreshold = 5;
        else if (difficulty.name === 'Or')
            baseThreshold = 4;
        if (knownScore > baseThreshold) {
            return false;
        }
        // Évaluer si les adversaires sont en difficulté
        let opponentsInTrouble = 0;
        let highThreatCount = 0;
        for (const opp of opponents) {
            if (difficulty.name === 'Platine') {
                // Platine : évaluation complète (matchs, swaps, discard rate fenêtre)
                const threat = this.assessOpponentThreat(gs, bot, opp);
                if (threat >= 3)
                    highThreatCount++;
                if (threat <= -1)
                    opponentsInTrouble++;
            }
            else {
                // Or et en-dessous : évaluation basique
                const failedMatches = this.getFailedMatchCount(gs, opp);
                const hasMany = opp.hand.length >= 5;
                if (failedMatches >= 2 || hasMany) {
                    opponentsInTrouble++;
                }
            }
        }
        // Platine : si un adversaire est très dangereux, ne pas Dutch sauf score très bas
        if (difficulty.name === 'Platine' && highThreatCount > 0 && knownScore > 2) {
            return false;
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
        if (difficulty.name === 'Platine') {
            // Platine : fenêtre glissante (5 derniers tours)
            const dangerousRecentRate = opponents.some((opp) => this.getRecentDiscardRate(gs, opp) > 0.7);
            if (dangerousRecentRate && knownScore > 3) {
                return false;
            }
        }
        else {
            const dangerousDiscardRate = opponents.some((opp) => this.getDiscardRate(gs, opp) > 0.6);
            if (dangerousDiscardRate && knownScore > 3) {
                return false; // Un adversaire a probablement une bonne main
            }
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
                if (lastAction?.includes('défausse sa pioche')) {
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
        // === BRONZE : défausser la carte identique vue avec le pouvoir 10 au tour précédent ===
        // PHILOSOPHIE BRONZE : si le bot a vu une carte identique avec le 10, il la défausse
        // au tour suivant pour permettre au joueur de matcher
        if (difficulty.name === 'Bronze' && memory.pendingMatchFromSpy) {
            const pending = memory.pendingMatchFromSpy;
            const cardToDiscard = memory.mentalMap[pending.cardIndex];
            // Vérifier que la carte est toujours là et correspond
            if (cardToDiscard && cardToDiscard.value === pending.cardValue) {
                // Remplacer cette carte par la pioche (défausser l'identique)
                const confused = this.random() < difficulty.confusionOnSwap;
                if (!confused) {
                    this.updateMentalMap(bot, pending.cardIndex, drawn);
                }
                GameLogic_1.GameLogic.replaceCard(gs, pending.cardIndex);
                // Nettoyer le pending
                memory.pendingMatchFromSpy = null;
                return;
            }
            // La carte n'est plus là (échangée, etc.) — annuler le pending
            memory.pendingMatchFromSpy = null;
        }
        // === POWER-AWARE : défausser un 7/10 pioché pour déclencher le pouvoir ===
        // Tous sauf Bronze — le bot comprend que défausser une carte à pouvoir a une valeur ajoutée
        if (difficulty.name !== 'Bronze' && drawn.isSpecial && (drawn.value === '7' || drawn.value === '10')) {
            const hasUnknownCards = this.getKnownCardCount(bot) < bot.hand.length;
            if (hasUnknownCards) {
                // Ai-je une carte connue pire que la pioche ? Si oui, la swapper est plus rentable
                let worstKnown = -1;
                for (let i = 0; i < bot.hand.length; i++) {
                    const val = this.getKnownCardValue(bot, i);
                    if (val !== null && val > worstKnown)
                        worstKnown = val;
                }
                if (worstKnown <= drawnVal) {
                    // Aucune carte connue pire que la pioche → défausser pour le pouvoir
                    // 7 pts pas gardés + pouvoir look, ou 10 pts pas gardés + pouvoir spy
                    GameLogic_1.GameLogic.discardDrawnCard(gs);
                    memory.consecutiveBadDraws = 0;
                    return;
                }
                // Sinon : une carte pire existe → on la swappera via la logique standard (plus rentable)
            }
        }
        // === EXPLORATION : doublon-aware (Or/Platine toujours, Argent 50%, Bronze jamais) ===
        if (phase === BotGamePhase.exploration) {
            let checksDoublons = true;
            if (difficulty.name === 'Bronze')
                checksDoublons = false;
            else if (difficulty.name === 'Argent')
                checksDoublons = this.random() < 0.5;
            if (checksDoublons) {
                const duplicateIdx = this.findDuplicateInHand(bot, drawn);
                if (duplicateIdx !== null) {
                    GameLogic_1.GameLogic.discardDrawnCard(gs);
                    memory.consecutiveBadDraws = 0;
                    return;
                }
            }
            // Pas de doublon trouvé : échanger contre une carte inconnue pour apprendre
            const unknownIndices = [];
            for (let i = 0; i < bot.hand.length; i++) {
                if (i >= memory.mentalMap.length || memory.mentalMap[i] === null) {
                    unknownIndices.push(i);
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
        // Tactique 1 : doublon pioche/main (Argent/Or/Platine, pas Bronze)
        if (difficulty.name !== 'Bronze') {
            const duplicateIdx = this.findDuplicateInHand(bot, drawn);
            if (duplicateIdx !== null) {
                GameLogic_1.GameLogic.discardDrawnCard(gs);
                memory.consecutiveBadDraws = 0;
                return;
            }
        }
        // Tactique 2 : doublon en main, pioche meilleure
        // Argent : seulement si les 2 cartes ont été vues récemment (< 3 tours)
        // Or : seulement si hand <= 4 (perd le fil avec trop de cartes)
        // Platine : toujours
        if (difficulty.name !== 'Bronze') {
            let checkDoublonPair = false;
            if (difficulty.name === 'Platine') {
                checkDoublonPair = true;
            }
            else if (difficulty.name === 'Or') {
                checkDoublonPair = bot.hand.length <= 4;
            }
            else if (difficulty.name === 'Argent') {
                // Argent détecte si les 2 cartes du doublon sont fraîches en mémoire
                checkDoublonPair = true; // on vérifie après la fraîcheur
            }
            if (checkDoublonPair) {
                const doublonPair = this.findDoublonPairInHand(bot);
                if (doublonPair) {
                    const [idx1, idx2] = doublonPair;
                    // Argent : vérifier la fraîcheur des 2 cartes
                    if (difficulty.name === 'Argent') {
                        const freshness1 = idx1 < memory.discoveredAtTurn.length ? memory.discoveredAtTurn[idx1] : null;
                        const freshness2 = idx2 < memory.discoveredAtTurn.length ? memory.discoveredAtTurn[idx2] : null;
                        if (freshness1 === null || freshness2 === null ||
                            memory.turnCounter - freshness1 > 3 || memory.turnCounter - freshness2 > 3) {
                            // Une des 2 cartes est trop ancienne → Argent ne fait pas la connexion
                            // On continue vers la logique standard
                        }
                        else {
                            // Les 2 cartes sont fraîches → Argent détecte le doublon
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
                    }
                    else {
                        // Or / Platine : détection directe
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
                }
            }
        }
        // Standard avec power-aware : choisir la meilleure carte à swapper
        // Pour chaque carte connue avec valeur > pioche, évaluer valeur + bonus pouvoir
        const hasUnknownCards = this.getKnownCardCount(bot) < bot.hand.length;
        let bestSwapIdx = -1;
        let bestSwapScore = -1;
        for (let i = 0; i < bot.hand.length; i++) {
            const val = this.getKnownCardValue(bot, i);
            if (val === null || val <= drawnVal)
                continue;
            const knownCard = this.getKnownCard(bot, i);
            if (!knownCard)
                continue;
            // Ne JAMAIS swapper un Joker (0 pts, trop précieux)
            if (knownCard.value === 'JOKER')
                continue;
            let score = val; // score de base = points de la carte
            // Bonus pouvoir si la carte est spéciale et que le bot en comprend la valeur
            if (knownCard.isSpecial && hasUnknownCards && difficulty.name !== 'Bronze') {
                const powerBonus = this.getPowerSwapBonus(knownCard, difficulty, hasUnknownCards);
                score += powerBonus;
            }
            // Platine : bonus si la carte est quasi-impossible à matcher (3+ exemplaires dans la défausse)
            if (difficulty.name === 'Platine') {
                const discardCount = memory.discardTracker.get(knownCard.value) || 0;
                if (discardCount >= 3) {
                    // 3 des 4 exemplaires sont dans la défausse → cette carte ne sera jamais matchée
                    // Prio pour s'en débarrasser
                    score += 2;
                }
            }
            if (score > bestSwapScore) {
                bestSwapScore = score;
                bestSwapIdx = i;
            }
        }
        if (bestSwapIdx !== -1) {
            const confused = this.random() < difficulty.confusionOnSwap;
            if (!confused) {
                this.updateMentalMap(bot, bestSwapIdx, drawn);
            }
            GameLogic_1.GameLogic.replaceCard(gs, bestSwapIdx);
            memory.consecutiveBadDraws = 0;
        }
        else {
            GameLogic_1.GameLogic.discardDrawnCard(gs);
            memory.consecutiveBadDraws++;
        }
    }
    // Bonus pouvoir pour le power-aware swap
    // Retourne un bonus qui favorise le swap de cartes spéciales pour déclencher leur pouvoir
    static getPowerSwapBonus(card, difficulty, hasUnknownCards) {
        // Argent : comprend seulement le bonus du 7 ("je me débarrasse du 7 et je regarde une carte")
        if (difficulty.name === 'Argent') {
            if (card.value === '7' && hasUnknownCards)
                return 3; // bonus info
            return 0;
        }
        // Or : comprend le bonus du 7 et du Valet
        if (difficulty.name === 'Or') {
            if (card.value === '7' && hasUnknownCards)
                return 3;
            if (card.value === 'V')
                return 2; // bonus déstabilisation
            return 0;
        }
        // Platine : comprend tous les bonus, choix optimal
        if (card.value === '7' && hasUnknownCards)
            return 3;
        if (card.value === 'V')
            return 2;
        if (card.value === '10')
            return 2; // bonus espionnage
        return 0;
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
        const difficulty = playerMMR === undefined
            ? this.getSkillDifficulty(bot.botSkillLevel)
            : BotDifficulty_1.BotDifficulty.fromMMR(playerMMR);
        const topDiscard = gameState.discardPile[gameState.discardPile.length - 1];
        const memory = this.getBotMemory(bot);
        // === BRONZE : panique sous pression ===
        // Quand les adversaires matchent bien, Bronze panique et tente à l'aveugle
        if (difficulty.name === 'Bronze' && bot.hand.length > 1) {
            let recentOpponentMatches = 0;
            const recentHistory = gameState.actionHistory.slice(0, 10);
            for (const entry of recentHistory) {
                if (entry.includes('MATCH') && !entry.includes(bot.name)) {
                    recentOpponentMatches++;
                }
            }
            if (recentOpponentMatches >= 2) {
                // Bronze panique : tente un match sur une carte au hasard
                await this.delay(300); // réaction impulsive
                const panicIdx = Math.floor(this.random() * bot.hand.length);
                const success = GameLogic_1.GameLogic.matchCard(gameState, bot, panicIdx);
                if (success && panicIdx < memory.mentalMap.length) {
                    memory.mentalMap.splice(panicIdx, 1);
                    memory.discoveredAtTurn.splice(panicIdx, 1);
                }
                return success;
            }
        }
        // Parcourir la mentalMap : est-ce que je CONNAIS une carte qui matche ?
        // Fallback sur knownCards + hand si la mentalMap est vide (ex: mémoire réinitialisée)
        for (let i = 0; i < bot.hand.length; i++) {
            const knownCard = (i < memory.mentalMap.length && memory.mentalMap[i] !== null)
                ? memory.mentalMap[i]
                : (bot.knownCards[i] ? bot.hand[i] : null);
            if (knownCard && (0, Card_1.cardMatches)(knownCard, topDiscard)) {
                // Je connais cette carte et elle matche → match immédiat
                let reactionDelay = 400;
                if (difficulty.name === 'Platine')
                    reactionDelay = 150;
                else if (difficulty.name === 'Or')
                    reactionDelay = 250;
                else if (difficulty.name === 'Argent')
                    reactionDelay = 350;
                await this.delay(reactionDelay);
                // Erreur de position : "c'est celle d'à côté"
                let matchIdx = i;
                let positionError = 0;
                if (difficulty.name === 'Bronze')
                    positionError = 0.25;
                else if (difficulty.name === 'Argent')
                    positionError = 0.1;
                else if (difficulty.name === 'Or')
                    positionError = 0.02;
                if (positionError > 0 && this.random() < positionError) {
                    // Décaler de ±1
                    const offset = this.random() < 0.5 ? -1 : 1;
                    const wrongIdx = i + offset;
                    if (wrongIdx >= 0 && wrongIdx < bot.hand.length) {
                        matchIdx = wrongIdx;
                    }
                }
                const success = GameLogic_1.GameLogic.matchCard(gameState, bot, matchIdx);
                if (success && matchIdx < memory.mentalMap.length) {
                    memory.mentalMap.splice(matchIdx, 1);
                    memory.discoveredAtTurn.splice(matchIdx, 1);
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
        if (gameState.phase !== GameState_1.GamePhase.specialPower || !gameState.specialCardToActivate)
            return;
        // Le joueur qui utilise le pouvoir peut être différent du currentPlayer (cas des matchs)
        const bot = gameState.specialPowerPlayerId
            ? gameState.players.find(p => p.id === gameState.specialPowerPlayerId) ?? (0, GameState_1.getCurrentPlayer)(gameState)
            : (0, GameState_1.getCurrentPlayer)(gameState);
        const card = gameState.specialCardToActivate;
        const difficulty = playerMMR === undefined
            ? this.getSkillDifficulty(bot.botSkillLevel)
            : BotDifficulty_1.BotDifficulty.fromMMR(playerMMR);
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
    }
    // Carte 7 : regarder sa propre carte — toujours utile
    static usePower7(gs, bot, difficulty) {
        const idx = this.chooseCardToLook(bot, difficulty);
        GameLogic_1.GameLogic.lookAtCard(gs, bot, idx);
        this.updateMentalMap(bot, idx, bot.hand[idx]);
    }
    // Carte 10 : espionner un adversaire — décision par phase et niveau
    static usePower10(gs, bot, difficulty, phase) {
        const opponents = gs.players.filter((p) => p.id !== bot.id && p.hand.length > 0);
        if (opponents.length === 0) {
            GameLogic_1.GameLogic.skipSpecialPower(gs);
            return;
        }
        // Bronze : toujours utiliser, cible aléatoire
        // PHILOSOPHIE BRONZE : si le bot voit une carte identique à l'une des siennes,
        // il va défausser sa carte au tour d'après (permettant un match au joueur humain)
        if (difficulty.name === 'Bronze') {
            const target = opponents[Math.floor(this.random() * opponents.length)];
            const idx = Math.floor(this.random() * target.hand.length);
            GameLogic_1.GameLogic.lookAtCard(gs, target, idx);
            // Vérifier si le bot a une carte identique dans sa main (même valeur)
            const spiedCard = target.hand[idx];
            const memory = this.getBotMemory(bot);
            for (let i = 0; i < bot.hand.length; i++) {
                // On ne vérifie que les cartes connues du bot
                if (memory.mentalMap[i] && memory.mentalMap[i].value === spiedCard.value) {
                    // Le bot a une carte identique ! Il va la défausser au prochain tour
                    memory.pendingMatchFromSpy = {
                        cardValue: spiedCard.value,
                        cardIndex: i,
                        turnSpied: memory.turnCounter,
                    };
                    break;
                }
            }
            // Bronze oublie normalement
            this.applyContextualForget(bot, difficulty, 'spy');
            return;
        }
        // Argent : cible la menace (joueur avec le moins de cartes), stockage si info frappante
        if (difficulty.name === 'Argent') {
            // Cibler la menace visible : joueur avec le moins de cartes
            const sorted = [...opponents].sort((a, b) => a.hand.length - b.hand.length);
            const target = sorted[0];
            const idx = Math.floor(this.random() * target.hand.length);
            GameLogic_1.GameLogic.lookAtCard(gs, target, idx);
            // Stockage contextuel : Argent mémorise ce qui est frappant (carte >= 7 pts)
            const spiedValue = target.hand[idx].points;
            if (spiedValue >= 7) {
                const memory = this.getBotMemory(bot);
                memory.spiedCards.push({
                    playerId: target.id,
                    cardPoints: spiedValue,
                    cardIndex: idx,
                    turnNumber: memory.turnCounter,
                });
            }
            // L'oubli contextuel s'applique toujours
            this.applyContextualForget(bot, difficulty, 'spy');
            return;
        }
        // --- Or / Platine : logique intelligente ---
        // Cas spécial duel : 2 joueurs, chacun avec 1 carte → TOUJOURS espionner
        const activePlayers = gs.players.filter((p) => !p.isSpectator && p.hand.length > 0);
        const duelMode = activePlayers.length === 2 && bot.hand.length <= 1;
        if (duelMode) {
            const target = opponents[0];
            const idx = Math.floor(this.random() * target.hand.length);
            GameLogic_1.GameLogic.lookAtCard(gs, target, idx);
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
        // Platine en exploration : skip (focus sur sa propre main d'abord)
        // Or en exploration : utilise le 10 (l'info est utile pour plus tard)
        if (phase === BotGamePhase.exploration && difficulty.name === 'Platine') {
            GameLogic_1.GameLogic.skipSpecialPower(gs);
            return;
        }
        // Choisir la cible via l'analyse de menace contextuelle
        const target = this.pickMostThreateningTarget(gs, bot, opponents);
        const idx = Math.floor(this.random() * target.hand.length);
        GameLogic_1.GameLogic.lookAtCard(gs, target, idx);
        // Stocker l'info espionnée (Or/Platine uniquement)
        const memory = this.getBotMemory(bot);
        memory.spiedCards.push({
            playerId: target.id,
            cardPoints: target.hand[idx].points,
            cardIndex: idx,
            turnNumber: memory.turnCounter,
        });
        this.applyContextualForget(bot, difficulty, 'spy');
    }
    // Carte V (Valet) : déstabiliser les AUTRES — par niveau
    static usePowerValet(gs, bot, difficulty) {
        const opponents = gs.players.filter((p) => p.id !== bot.id && p.hand.length > 0);
        if (opponents.length === 0) {
            GameLogic_1.GameLogic.skipSpecialPower(gs);
            return;
        }
        // Bronze : Valet utilisé de façon bienveillante
        // PHILOSOPHIE BRONZE : 
        // - N'attaquer l'humain QUE s'il est dangereux (≤ 2 cartes) ET quota pas atteint (2 max par manche)
        // - Sinon, échanger entre bots ou avec soi-même contre un bot
        if (difficulty.name === 'Bronze') {
            const human = opponents.find(p => p.isHuman);
            const nonHumanOpponents = opponents.filter(p => !p.isHuman);
            // L'humain est ciblable s'il a ≤ 2 cartes ET qu'on peut encore le Valet
            const canTargetHuman = human && human.hand.length <= 2 && this.canValetHuman(gs);
            if (opponents.length >= 2 && this.random() < 0.5) {
                // Cas 1 : Échange entre 2 adversaires (pas soi-même)
                if (canTargetHuman && nonHumanOpponents.length >= 1) {
                    // L'humain est dangereux et ciblable → l'inclure dans l'échange
                    const otherTarget = nonHumanOpponents[Math.floor(this.random() * nonHumanOpponents.length)];
                    const idx1 = Math.floor(this.random() * human.hand.length);
                    const idx2 = Math.floor(this.random() * otherTarget.hand.length);
                    this.recordValetOnHuman(gs);
                    GameLogic_1.GameLogic.swapCards(gs, human, idx1, otherTarget, idx2);
                }
                else if (nonHumanOpponents.length >= 2) {
                    // L'humain n'est pas ciblable → échange entre 2 bots uniquement
                    const t1 = nonHumanOpponents[Math.floor(this.random() * nonHumanOpponents.length)];
                    let t2 = t1;
                    while (t2 === t1) {
                        t2 = nonHumanOpponents[Math.floor(this.random() * nonHumanOpponents.length)];
                    }
                    const idx1 = Math.floor(this.random() * t1.hand.length);
                    const idx2 = Math.floor(this.random() * t2.hand.length);
                    GameLogic_1.GameLogic.swapCards(gs, t1, idx1, t2, idx2);
                }
                else {
                    // Pas assez de bots, skip
                    GameLogic_1.GameLogic.skipSpecialPower(gs);
                    return;
                }
            }
            else {
                // Cas 2 : Échange sa propre carte avec un adversaire
                let target;
                if (canTargetHuman) {
                    // L'humain est dangereux et ciblable → le cibler
                    this.recordValetOnHuman(gs);
                    target = human;
                }
                else if (nonHumanOpponents.length > 0) {
                    // L'humain n'est pas dangereux → cibler un bot
                    target = nonHumanOpponents[Math.floor(this.random() * nonHumanOpponents.length)];
                }
                else {
                    // Seulement l'humain disponible et il n'est pas dangereux → skip
                    GameLogic_1.GameLogic.skipSpecialPower(gs);
                    return;
                }
                const myIdx = Math.floor(this.random() * bot.hand.length);
                const targetIdx = Math.floor(this.random() * target.hand.length);
                this.forgetCard(bot, myIdx);
                GameLogic_1.GameLogic.swapCards(gs, bot, myIdx, target, targetIdx);
            }
            this.applyContextualForget(bot, difficulty, 'valet');
            return;
        }
        // Argent : cible la menace visible (peu de cartes = dangereux)
        if (difficulty.name === 'Argent') {
            if (opponents.length >= 2) {
                // Menace = joueur avec le moins de cartes → inclus dans l'échange
                // Perturbé = joueur avec le plus de cartes → reçoit une carte de la menace
                const sorted = [...opponents].sort((a, b) => a.hand.length - b.hand.length);
                const threat = sorted[0]; // le plus dangereux
                const weakest = sorted[sorted.length - 1]; // le plus gros jeu
                const idx1 = Math.floor(this.random() * threat.hand.length);
                const idx2 = Math.floor(this.random() * weakest.hand.length);
                GameLogic_1.GameLogic.swapCards(gs, threat, idx1, weakest, idx2);
            }
            else {
                // 1 seul adversaire : échange aléatoire avec soi
                const myIdx = Math.floor(this.random() * bot.hand.length);
                const targetIdx = Math.floor(this.random() * opponents[0].hand.length);
                this.forgetCard(bot, myIdx);
                GameLogic_1.GameLogic.swapCards(gs, bot, myIdx, opponents[0], targetIdx);
            }
            this.applyContextualForget(bot, difficulty, 'valet');
            return;
        }
        // --- Or / Platine : stratégie intelligente ---
        if (opponents.length >= 2) {
            const targets = this.chooseValetTargets(gs, bot, opponents);
            const idx1 = Math.floor(this.random() * targets[0].hand.length);
            const idx2 = Math.floor(this.random() * targets[1].hand.length);
            GameLogic_1.GameLogic.swapCards(gs, targets[0], idx1, targets[1], idx2);
        }
        else {
            // 1v1 — algo contextuel
            const opponent = opponents[0];
            const shouldSwap = this.shouldValetSwap1v1(gs, bot, opponent);
            if (shouldSwap) {
                const myCardIdx = this.chooseBadCard(bot);
                const targetIdx = Math.floor(this.random() * opponent.hand.length);
                this.forgetCard(bot, myCardIdx);
                GameLogic_1.GameLogic.swapCards(gs, bot, myCardIdx, opponent, targetIdx);
            }
            else {
                GameLogic_1.GameLogic.skipSpecialPower(gs);
                return;
            }
        }
        this.applyContextualForget(bot, difficulty, 'valet');
    }
    // Valet 1v1 : décision contextuelle — ai-je intérêt à échanger ?
    static shouldValetSwap1v1(gs, bot, opponent) {
        const memory = this.getBotMemory(bot);
        // Trouver ma pire carte connue
        let worstKnownValue = -1;
        for (let i = 0; i < bot.hand.length; i++) {
            const val = this.getKnownCardValue(bot, i);
            if (val !== null && val > worstKnownValue) {
                worstKnownValue = val;
            }
        }
        // Si aucune carte connue → skip (trop risqué à l'aveugle)
        if (worstKnownValue === -1)
            return false;
        // Si toutes mes cartes connues sont bonnes (pire <= 3) → skip
        if (worstKnownValue <= 3)
            return false;
        // Ma pire carte est mauvaise (>= 8) → fort intérêt, vérifier si l'adversaire a une bonne main
        // Pire entre 4-7 → intérêt modéré
        // Vérifier le spy intel : a-t-on vu une carte de l'adversaire ?
        for (const spy of memory.spiedCards) {
            if (spy.playerId === opponent.id && memory.turnCounter - spy.turnNumber <= 3) {
                // On a de l'intel récent
                if (spy.cardPoints < worstKnownValue) {
                    // Sa carte est meilleure que notre pire → swap pour récupérer mieux
                    return true;
                }
                else {
                    // Sa carte est pire ou égale → pas d'intérêt
                    return false;
                }
            }
        }
        // Pas d'intel → évaluer via le discard rate
        const discardRate = this.getDiscardRate(gs, opponent);
        if (discardRate > 0.6) {
            // Il rejette beaucoup de pioches → sa main est probablement bonne → swap intéressant
            return true;
        }
        // Pire >= 8 sans info → swap quand même (rien à perdre avec une grosse carte)
        if (worstKnownValue >= 8)
            return true;
        // Pire entre 4-7, pas d'info claire → skip (trop incertain)
        return false;
    }
    // Choisir 2 cibles pour le Valet parmi les adversaires
    // Algorithme contextuel : cible les 2 joueurs les plus menaçants
    // Si l'humain est dans le top 2, il est inclus
    static chooseValetTargets(gs, bot, opponents) {
        const scored = opponents.map(p => ({
            player: p,
            threat: this.calculateThreatScore(gs, bot, p),
        }));
        scored.sort((a, b) => b.threat - a.threat);
        // Si l'humain est dans le top 2, s'assurer qu'il est inclus
        const top2 = scored.slice(0, 2);
        const humanInTop2 = top2.find(s => s.player.isHuman);
        if (humanInTop2) {
            const other = top2.find(s => !s.player.isHuman);
            if (other)
                return [humanInTop2.player, other.player];
        }
        return [scored[0].player, scored[1].player];
    }
    // Carte Joker : mélanger un adversaire — par niveau
    static usePowerJoker(gs, bot, difficulty) {
        // Bronze : JAMAIS cibler le joueur humain avec le Joker
        // Le Joker vide aussi la mémoire du bot qui l'utilise
        if (difficulty.name === 'Bronze') {
            // Ne cibler que les autres bots, jamais l'humain
            const nonHumanTargets = gs.players.filter((p) => p.id !== bot.id && !p.isHuman && p.hand.length > 0);
            if (nonHumanTargets.length === 0) {
                // Aucun bot disponible → skip le pouvoir (ne pas cibler l'humain)
                GameLogic_1.GameLogic.skipSpecialPower(gs);
                return;
            }
            const target = nonHumanTargets[Math.floor(this.random() * nonHumanTargets.length)];
            GameLogic_1.GameLogic.jokerEffect(gs, target);
            // Le bot Bronze vide systématiquement sa mémoire après avoir utilisé le Joker
            this.resetMentalMap(bot);
            return;
        }
        // Argent : filtre >= 2 cartes, cible la menace (joueur avec le moins de cartes)
        if (difficulty.name === 'Argent') {
            const validTargets = gs.players.filter((p) => p.id !== bot.id && p.hand.length >= 2);
            if (validTargets.length === 0) {
                GameLogic_1.GameLogic.skipSpecialPower(gs);
                return;
            }
            // "Celui-là a trop peu de cartes, il va Dutch, je le mélange"
            validTargets.sort((a, b) => a.hand.length - b.hand.length);
            GameLogic_1.GameLogic.jokerEffect(gs, validTargets[0]);
            return;
        }
        // --- Or / Platine : ciblage intelligent via analyse de menace ---
        const validTargets = gs.players.filter((p) => p.id !== bot.id && p.hand.length >= 2);
        if (validTargets.length === 0) {
            GameLogic_1.GameLogic.skipSpecialPower(gs);
            return;
        }
        // Cibler le joueur le plus menaçant (humain préféré si top 2)
        const target = this.pickMostThreateningTarget(gs, bot, validTargets);
        GameLogic_1.GameLogic.jokerEffect(gs, target);
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
            case Player_1.BotSkillLevel.difficile:
                return BotDifficulty_1.BotDifficulty.difficult;
            default:
                return BotDifficulty_1.BotDifficulty.silver;
        }
    }
    static delay(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
    }
    // ============================================================
    // PLATINE EXCLUSIF — observation de la table
    // ============================================================
    // E1 — Compter les cartes dans la défausse
    static updateDiscardTracker(gs, bot) {
        const memory = this.getBotMemory(bot);
        // Reconstruire le tracker à partir de la pile de défausse actuelle
        // (plus fiable que le tracking incrémental, et gère le reset au remélange)
        memory.discardTracker.clear();
        for (const card of gs.discardPile) {
            const count = memory.discardTracker.get(card.value) || 0;
            memory.discardTracker.set(card.value, count + 1);
        }
    }
    // E2 — Observer les swaps et matchs des adversaires
    static updateOpponentObservation(gs, bot) {
        const memory = this.getBotMemory(bot);
        // Scanner l'historique récent pour les swaps adverses
        // On ne regarde que les 10 dernières entrées pour éviter de re-parser tout
        const recentHistory = gs.actionHistory.slice(0, 10);
        for (const entry of recentHistory) {
            if (entry.includes('échange une carte') && !entry.includes(bot.name)) {
                // Trouver quel adversaire a swappé
                const opponent = gs.players.find((p) => p.id !== bot.id && entry.includes(p.name));
                if (opponent) {
                    // Éviter les doublons (même entrée déjà trackée)
                    const alreadyTracked = memory.opponentSwapHistory.some((s) => s.playerId === opponent.id && s.turnNumber === memory.turnCounter);
                    if (!alreadyTracked) {
                        memory.opponentSwapHistory.push({
                            playerId: opponent.id,
                            cardIndex: -1, // on ne sait pas quelle position exactement
                            turnNumber: memory.turnCounter,
                        });
                    }
                }
            }
            // E4 — Mémoire des échanges Valet : mettre à jour spiedCards
            if (entry.includes('Échange :') && !entry.includes(bot.name)) {
                this.updateSpiedCardsAfterValet(gs, bot, entry);
            }
        }
    }
    // E3 — Compteur de matchs réussis adverses
    static getSuccessfulMatchCount(gs, player) {
        let count = 0;
        for (const entry of gs.actionHistory) {
            if (entry.includes('MATCH') && entry.includes(player.name)) {
                count++;
            }
        }
        return count;
    }
    // E4 — Mise à jour des spiedCards quand un Valet déplace des cartes
    static updateSpiedCardsAfterValet(gs, bot, historyEntry) {
        const memory = this.getBotMemory(bot);
        // Format: "Échange : Player1 carte #X ↔ Player2 carte #Y."
        const match = /Échange : (.+) carte #(\d+) ↔ (.+) carte #(\d+)/.exec(historyEntry);
        if (!match)
            return;
        const [, name1, cardIdx1Str, name2, cardIdx2Str] = match;
        const cardIdx1 = Number.parseInt(cardIdx1Str, 10) - 1; // 1-indexed → 0-indexed
        const cardIdx2 = Number.parseInt(cardIdx2Str, 10) - 1;
        const player1 = gs.players.find((p) => p.name === name1);
        const player2 = gs.players.find((p) => p.name === name2);
        if (!player1 || !player2)
            return;
        // Vérifier si Platine avait de l'intel sur ces positions
        for (const spy of memory.spiedCards) {
            if (spy.playerId === player1.id && spy.cardIndex === cardIdx1) {
                // Cette carte a été déplacée chez player2 à la position cardIdx2
                spy.playerId = player2.id;
                spy.cardIndex = cardIdx2;
                spy.displaced = true;
            }
            else if (spy.playerId === player2.id && spy.cardIndex === cardIdx2) {
                // Cette carte a été déplacée chez player1 à la position cardIdx1
                spy.playerId = player1.id;
                spy.cardIndex = cardIdx1;
                spy.displaced = true;
            }
        }
    }
    // E5 — Discard rate affiné (fenêtre glissante sur les derniers tours)
    static getRecentDiscardRate(gs, player, windowSize = 15) {
        let discards = 0;
        let swaps = 0;
        const recentHistory = gs.actionHistory.slice(0, windowSize);
        for (const entry of recentHistory) {
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
    // Évaluer le danger d'un adversaire (Platine uniquement)
    // Combine discard rate, matchs réussis, swaps récents pour un diagnostic complet
    static assessOpponentThreat(gs, bot, opponent) {
        const memory = this.getBotMemory(bot);
        let threatLevel = 0;
        // Moins de cartes = plus dangereux
        if (opponent.hand.length <= 2)
            threatLevel += 3;
        else if (opponent.hand.length <= 3)
            threatLevel += 1;
        // Matchs réussis = a perdu des cartes efficacement
        const successMatches = this.getSuccessfulMatchCount(gs, opponent);
        if (successMatches >= 2)
            threatLevel += 2;
        // Matchs ratés = désorganisé
        const failedMatches = this.getFailedMatchCount(gs, opponent);
        if (failedMatches >= 2)
            threatLevel -= 2;
        // Discard rate récent élevé = main probablement bonne
        const recentRate = this.getRecentDiscardRate(gs, opponent);
        if (recentRate > 0.7)
            threatLevel += 2;
        else if (recentRate < 0.3)
            threatLevel -= 1;
        // Swap récent = a amélioré sa main
        const recentSwaps = memory.opponentSwapHistory.filter((s) => s.playerId === opponent.id && memory.turnCounter - s.turnNumber <= 2);
        if (recentSwaps.length > 0)
            threatLevel += 1;
        return threatLevel;
    }
    static clearBotMemory(playerId) {
        botMemories.delete(playerId);
    }
    static clearAllBotMemories() {
        botMemories.clear();
    }
}
exports.BotAI = BotAI;
//# sourceMappingURL=BotAI.js.map