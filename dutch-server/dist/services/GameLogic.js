"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.GameLogic = void 0;
const Card_1 = require("../models/Card");
const GameState_1 = require("../models/GameState");
const HistoryFormatter_1 = require("../utils/HistoryFormatter");
class GameLogic {
    static random() {
        return Math.random();
    }
    static initializeGame(gameState) {
        const deck = (0, Card_1.createFullDeck)();
        gameState.deck = deck;
        // Réinitialiser les mains et mémoires des joueurs
        for (const player of gameState.players) {
            player.hand = [];
            player.knownCards = [];
        }
        gameState.discardPile = [];
        gameState.phase = GameState_1.GamePhase.setup;
        // Mélanger et distribuer
        this.smartShuffle(gameState);
        this.dealCards(gameState);
        // Initialiser la mémoire des bots
        for (const player of gameState.players) {
            if (!player.isHuman) {
                this.initializeBotMemory(player);
            }
        }
        // Retourner la première carte de la défausse
        if (gameState.deck.length > 0) {
            const firstCard = gameState.deck.pop();
            gameState.discardPile.push(firstCard);
        }
        // Choisir un joueur aléatoire pour commencer
        if (gameState.players.length > 0) {
            const randomIndex = Math.floor(this.random() * gameState.players.length);
            gameState.currentPlayerIndex = randomIndex;
            const starter = gameState.players[randomIndex];
            console.log(`🎲 Premier joueur : ${starter.name} (index ${randomIndex}/${gameState.players.length})`);
            (0, GameState_1.addToHistory)(gameState, HistoryFormatter_1.HistoryFormatter.formatStartingPlayer(starter.name));
        }
    }
    static initializeBotMemory(player) {
        if (player.isHuman || player.hand.length < 2)
            return;
        // Les bots connaissent leurs 2 premières cartes
        player.knownCards = new Array(player.hand.length).fill(false);
        player.knownCards[0] = true;
        player.knownCards[1] = true;
    }
    static initialReveal(gameState, selectedIndices) {
        const human = gameState.players.find((p) => p.isHuman);
        if (!human)
            return;
        for (const index of selectedIndices) {
            if (index >= 0 && index < human.knownCards.length) {
                human.knownCards[index] = true;
            }
        }
        (0, GameState_1.addToHistory)(gameState, HistoryFormatter_1.HistoryFormatter.formatInitialMemorization());
    }
    static drawCard(gameState) {
        if (gameState.deck.length === 0) {
            this.refillDeck(gameState);
        }
        if (gameState.deck.length > 0) {
            gameState.drawnCard = gameState.deck.pop();
            (0, GameState_1.addToHistory)(gameState, HistoryFormatter_1.HistoryFormatter.formatDrawCard((0, GameState_1.getCurrentPlayer)(gameState).name));
        }
        else {
            this.endGame(gameState);
        }
    }
    static discardDrawnCard(gameState) {
        if (!gameState.drawnCard)
            return;
        const card = gameState.drawnCard;
        gameState.drawnCard = null;
        gameState.discardPile.push(card);
        // Check if card has a special power BEFORE generating the message
        const powerCards = ['7', '10', 'V', 'JOKER'];
        const hasPower = powerCards.includes(card.value);
        (0, GameState_1.addToHistory)(gameState, HistoryFormatter_1.HistoryFormatter.formatDiscardDrawn((0, GameState_1.getCurrentPlayer)(gameState).name, card, hasPower));
        this.checkSpecialPower(gameState, card);
        if (gameState.phase !== GameState_1.GamePhase.specialPower) {
            this.startReactionPhase(gameState);
        }
    }
    static startReactionPhase(gameState, delayMs = 0) {
        gameState.phase = GameState_1.GamePhase.reaction;
        // Si on a un délai (ex: suite à un pouvoir spécial), on démarre le timestamp de réaction dans le futur
        gameState.reactionStartTime = new Date(Date.now() + delayMs);
    }
    static replaceCard(gameState, cardIndex) {
        if (!gameState.drawnCard)
            return;
        const player = (0, GameState_1.getCurrentPlayer)(gameState);
        if (cardIndex < 0 || cardIndex >= player.hand.length) {
            return;
        }
        const newCard = gameState.drawnCard;
        const oldCard = player.hand[cardIndex];
        player.hand[cardIndex] = newCard;
        player.knownCards[cardIndex] = true;
        gameState.drawnCard = null;
        gameState.discardPile.push(oldCard);
        (0, GameState_1.addToHistory)(gameState, HistoryFormatter_1.HistoryFormatter.formatReplaceDrawn(player.name, oldCard));
        this.checkSpecialPower(gameState, oldCard);
        if (gameState.phase !== GameState_1.GamePhase.specialPower) {
            this.startReactionPhase(gameState);
        }
    }
    static matchCard(gameState, player, cardIndex) {
        if (gameState.discardPile.length === 0)
            return false;
        if (cardIndex < 0 || cardIndex >= player.hand.length) {
            return false;
        }
        const playerCard = player.hand[cardIndex];
        const topDiscard = gameState.discardPile[gameState.discardPile.length - 1];
        if ((0, Card_1.cardMatches)(playerCard, topDiscard)) {
            gameState.discardPile.push(playerCard);
            // Retirer la carte de la main
            player.hand.splice(cardIndex, 1);
            player.knownCards.splice(cardIndex, 1);
            (0, GameState_1.addToHistory)(gameState, HistoryFormatter_1.HistoryFormatter.formatMatchSuccess(player.name, playerCard));
            if (gameState.phase === GameState_1.GamePhase.reaction) {
                // Pendant la réaction, stocker le pouvoir pour résolution après
                this.addPendingMatchPower(gameState, player, playerCard);
            }
            else {
                this.checkSpecialPower(gameState, playerCard);
            }
            return true;
        }
        else {
            (0, GameState_1.addToHistory)(gameState, HistoryFormatter_1.HistoryFormatter.formatMatchFail(player.name, playerCard, topDiscard));
            this.applyPenalty(gameState, player);
            return false;
        }
    }
    static applyPenalty(gameState, player) {
        if (gameState.deck.length === 0) {
            this.refillDeck(gameState);
        }
        if (gameState.deck.length === 0)
            return;
        const penaltyCard = gameState.deck.pop();
        player.hand.push(penaltyCard);
        player.knownCards.push(false);
        (0, GameState_1.addToHistory)(gameState, HistoryFormatter_1.HistoryFormatter.formatPenalty(player.name));
    }
    static lookAtCard(gameState, target, cardIndex) {
        if (cardIndex >= 0 && cardIndex < target.knownCards.length) {
            // Note: Logic to show card to requester is handled by client/provider
            (0, GameState_1.addToHistory)(gameState, HistoryFormatter_1.HistoryFormatter.formatPowerSpy((0, GameState_1.getCurrentPlayer)(gameState).name, target.name));
        }
    }
    static swapCards(gameState, p1, idx1, p2, idx2) {
        if (idx1 < 0 ||
            idx1 >= p1.hand.length ||
            idx2 < 0 ||
            idx2 >= p2.hand.length) {
            return;
        }
        const c1 = p1.hand[idx1];
        const c2 = p2.hand[idx2];
        p1.hand[idx1] = c2;
        p2.hand[idx2] = c1;
        if (idx1 < p1.knownCards.length)
            p1.knownCards[idx1] = false;
        if (idx2 < p2.knownCards.length)
            p2.knownCards[idx2] = false;
        (0, GameState_1.addToHistory)(gameState, HistoryFormatter_1.HistoryFormatter.formatPowerSwap(p1.name, idx1, p2.name, idx2));
    }
    static jokerEffect(gameState, targetPlayer) {
        // Mélanger la main du joueur cible
        const shuffledHand = [...targetPlayer.hand];
        for (let i = shuffledHand.length - 1; i > 0; i--) {
            const j = Math.floor(this.random() * (i + 1));
            [shuffledHand[i], shuffledHand[j]] = [shuffledHand[j], shuffledHand[i]];
        }
        targetPlayer.hand = shuffledHand;
        // Réinitialiser les connaissances
        targetPlayer.knownCards = new Array(targetPlayer.hand.length).fill(false);
        (0, GameState_1.addToHistory)(gameState, HistoryFormatter_1.HistoryFormatter.formatPowerJoker((0, GameState_1.getCurrentPlayer)(gameState).name, targetPlayer.name));
    }
    static checkSpecialPower(gameState, card) {
        // Only cards with actual implemented powers: 7 (spy), 10 (swap), V (exchange), JOKER (shuffle)
        const powerCards = ['7', '10', 'V', 'JOKER'];
        if (powerCards.includes(card.value)) {
            const now = Date.now();
            gameState.phase = GameState_1.GamePhase.specialPower;
            gameState.isWaitingForSpecialPower = true;
            gameState.specialCardToActivate = card;
            gameState.specialPowerPlayerId = null; // currentPlayer par défaut
            gameState.specialPowerStartTime = now;
            // Synchroniser turnStartTime et turnTimeoutMs immédiatement pour que
            // le premier broadcast (ACTION_RESULT) inclue les bonnes valeurs du timer.
            // Sans ça, les joueurs en attente reçoivent l'ancien turnTimeoutMs (90s de la phase playing)
            // au lieu du timeout du pouvoir spécial (60s), ce qui désynchronise leur barre de progression.
            gameState.turnStartTime = now;
            gameState.turnTimeoutMs = 60000; // 60s pour utiliser le pouvoir (synchronisé avec RoomManager.specialPowerTimeoutMs)
        }
    }
    /** Ajoute un pouvoir en attente suite à un match pendant la phase de réaction */
    static addPendingMatchPower(gameState, player, card) {
        const powerCards = ['7', '10', 'V', 'JOKER'];
        if (powerCards.includes(card.value)) {
            gameState.pendingMatchPowers.push({
                playerId: player.id,
                playerName: player.name,
                card: { ...card },
            });
        }
    }
    static callDutch(gameState, playerId) {
        if (gameState.dutchCallerId)
            return;
        gameState.dutchCallerId = playerId || (0, GameState_1.getCurrentPlayer)(gameState).id;
        gameState.phase = GameState_1.GamePhase.dutchCalled;
        const player = gameState.players.find(p => p.id === gameState.dutchCallerId);
        (0, GameState_1.addToHistory)(gameState, HistoryFormatter_1.HistoryFormatter.formatDutchCall(player?.name || 'Joueur'));
        // Stop game immediately (as per user request to match Solo mode)
        this.endGame(gameState);
    }
    // Méthodes supplémentaires pour le serveur multijoueur
    static takeFromDiscard(gameState) {
        if (gameState.discardPile.length === 0)
            return;
        const card = gameState.discardPile.pop();
        gameState.drawnCard = card;
        (0, GameState_1.addToHistory)(gameState, HistoryFormatter_1.HistoryFormatter.formatTakeFromDiscard((0, GameState_1.getCurrentPlayer)(gameState).name));
    }
    static attemptMatch(gameState, playerId, cardIndex) {
        const player = gameState.players.find(p => p.id === playerId);
        if (!player)
            return false;
        return this.matchCard(gameState, player, cardIndex);
    }
    /**
     * Utilise un pouvoir spécial - Aligné sur le mode solo
     *
     * @param data Les paramètres dépendent de la carte:
     *   - Carte 7: { cardIndex } - Regarder sa propre carte
     *   - Carte 10: { targetPlayerIndex, targetCardIndex } - Espionner un adversaire
     *   - Carte V: { player1Index, card1Index, player2Index, card2Index } - Échange universel
     *   - JOKER: { targetPlayerIndex } - Mélanger n'importe qui (y compris soi)
     *
     * @returns Informations sur les joueurs affectés pour les notifications
     */
    static useSpecialPower(gameState, data) {
        if (gameState.phase !== GameState_1.GamePhase.specialPower || !gameState.specialCardToActivate) {
            return {};
        }
        // Utiliser le joueur pouvoiré (match power) ou le joueur actif (normal)
        const currentPlayer = gameState.specialPowerPlayerId
            ? gameState.players.find(p => p.id === gameState.specialPowerPlayerId) ?? (0, GameState_1.getCurrentPlayer)(gameState)
            : (0, GameState_1.getCurrentPlayer)(gameState);
        const card = gameState.specialCardToActivate;
        let result = {};
        if (card.value === '7') {
            // Carte 7 : Regarder SA PROPRE carte (comme en solo)
            const cardIndex = data.cardIndex ?? 0;
            if (cardIndex >= 0 && cardIndex < currentPlayer.hand.length) {
                gameState.lastSpiedCard = currentPlayer.hand[cardIndex];
                currentPlayer.knownCards[cardIndex] = true;
                (0, GameState_1.addToHistory)(gameState, `${currentPlayer.name} a regardé une de ses cartes.`);
                result.spiedCard = currentPlayer.hand[cardIndex];
            }
        }
        else if (card.value === '10') {
            // Carte 10 : Espionner une carte adversaire (pas d'échange)
            const targetPlayerIndex = data.targetPlayerIndex ?? 0;
            const targetCardIndex = data.targetCardIndex ?? 0;
            if (targetPlayerIndex >= 0 && targetPlayerIndex < gameState.players.length) {
                const targetPlayer = gameState.players[targetPlayerIndex];
                if (targetCardIndex >= 0 && targetCardIndex < targetPlayer.hand.length) {
                    gameState.lastSpiedCard = targetPlayer.hand[targetCardIndex];
                    (0, GameState_1.addToHistory)(gameState, `${currentPlayer.name} a espionné une carte de ${targetPlayer.name}.`);
                    result.spiedCard = targetPlayer.hand[targetCardIndex];
                }
            }
        }
        else if (card.value === 'V') {
            // Carte V (Valet) : Échange universel entre 2 joueurs quelconques
            const { player1Index, card1Index, player2Index, card2Index } = data;
            if (player1Index !== undefined && card1Index !== undefined &&
                player2Index !== undefined && card2Index !== undefined &&
                player1Index >= 0 && player1Index < gameState.players.length &&
                player2Index >= 0 && player2Index < gameState.players.length) {
                const p1 = gameState.players[player1Index];
                const p2 = gameState.players[player2Index];
                if (card1Index >= 0 && card1Index < p1.hand.length &&
                    card2Index >= 0 && card2Index < p2.hand.length) {
                    this.swapCards(gameState, p1, card1Index, p2, card2Index);
                    // Retourner les joueurs affectés (sauf celui qui utilise le pouvoir)
                    result.affectedPlayers = [];
                    if (p1.id !== currentPlayer.id) {
                        result.affectedPlayers.push({
                            playerId: p1.id,
                            playerName: p1.name,
                            cardIndex: card1Index,
                            swapPartnerName: p2.name,
                            receivedCardPosition: card2Index + 1, // position (1-based) chez p2
                        });
                    }
                    if (p2.id !== currentPlayer.id) {
                        result.affectedPlayers.push({
                            playerId: p2.id,
                            playerName: p2.name,
                            cardIndex: card2Index,
                            swapPartnerName: p1.name,
                            receivedCardPosition: card1Index + 1, // position (1-based) chez p1
                        });
                    }
                }
            }
        }
        else if (card.value === 'JOKER') {
            // JOKER : Mélanger n'importe qui (y compris soi-même)
            const targetPlayerIndex = data.targetPlayerIndex ?? 0;
            if (targetPlayerIndex >= 0 && targetPlayerIndex < gameState.players.length) {
                const targetPlayer = gameState.players[targetPlayerIndex];
                this.jokerEffect(gameState, targetPlayer);
                // Retourner le joueur affecté (sauf si c'est soi-même)
                if (targetPlayer.id !== currentPlayer.id) {
                    result.shuffledPlayer = {
                        playerId: targetPlayer.id,
                        playerName: targetPlayer.name
                    };
                }
            }
        }
        gameState.isWaitingForSpecialPower = false;
        gameState.specialCardToActivate = null;
        this.startReactionPhase(gameState);
        return result;
    }
    static skipSpecialPower(gameState) {
        // Déterminer le joueur qui avait le pouvoir
        const powerPlayer = gameState.specialPowerPlayerId
            ? gameState.players.find(p => p.id === gameState.specialPowerPlayerId)
            : (0, GameState_1.getCurrentPlayer)(gameState);
        gameState.isWaitingForSpecialPower = false;
        gameState.specialCardToActivate = null;
        gameState.specialPowerPlayerId = null;
        (0, GameState_1.addToHistory)(gameState, HistoryFormatter_1.HistoryFormatter.formatPowerSkip(powerPlayer?.name ?? 'Joueur'));
        this.startReactionPhase(gameState);
    }
    static endGame(gameState) {
        gameState.phase = GameState_1.GamePhase.ended;
        for (const player of gameState.players) {
            for (let i = 0; i < player.knownCards.length; i++) {
                player.knownCards[i] = true;
            }
        }
    }
    static nextPlayer(gameState) {
        (0, GameState_1.nextPlayer)(gameState);
    }
    static refillDeck(gameState) {
        if (gameState.discardPile.length > 1) {
            const top = gameState.discardPile.pop();
            gameState.deck.push(...gameState.discardPile);
            gameState.discardPile = [top];
            // Mélanger le nouveau deck
            this.shuffleDeck(gameState.deck);
            (0, GameState_1.addToHistory)(gameState, HistoryFormatter_1.HistoryFormatter.formatDeckRefill(gameState.deck.length));
        }
        else {
            if (gameState.dutchCallerId) {
                gameState.phase = GameState_1.GamePhase.dutchCalled;
                (0, GameState_1.addToHistory)(gameState, HistoryFormatter_1.HistoryFormatter.formatEmptyDeckEnd());
            }
            else {
                this.endGame(gameState);
            }
        }
    }
    static smartShuffle(gameState) {
        // Pour l'instant, on fait un shuffle simple
        // La logique complète de smartShuffle avec les difficultés sera implémentée plus tard
        this.shuffleDeck(gameState.deck);
    }
    static dealCards(gameState) {
        // Distribution simple : 4 cartes par joueur
        for (const player of gameState.players) {
            player.hand = [];
            player.knownCards = [];
            for (let i = 0; i < 4; i++) {
                if (gameState.deck.length > 0) {
                    player.hand.push(gameState.deck.pop());
                    player.knownCards.push(false);
                }
            }
        }
    }
    static shuffleDeck(deck) {
        for (let i = deck.length - 1; i > 0; i--) {
            const j = Math.floor(this.random() * (i + 1));
            [deck[i], deck[j]] = [deck[j], deck[i]];
        }
    }
    static getCardDisplayName(card) {
        if (card.value === 'R') {
            return card.suit === 'hearts' || card.suit === 'diamonds'
                ? 'Roi Rouge'
                : 'Roi Noir';
        }
        if (card.value === 'JOKER')
            return 'Joker';
        if (card.value === 'A')
            return 'A';
        if (card.value === 'V')
            return 'Valet';
        if (card.value === 'D')
            return 'Dame';
        return card.value;
    }
}
exports.GameLogic = GameLogic;
//# sourceMappingURL=GameLogic.js.map