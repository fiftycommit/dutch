"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const node_assert_1 = __importDefault(require("node:assert"));
const GameLogic_1 = require("../services/GameLogic");
const GameState_1 = require("../models/GameState");
const Player_1 = require("../models/Player");
const Card_1 = require("../models/Card");
(0, node_test_1.describe)('GameLogic', () => {
    function createTestPlayers() {
        return [
            (0, Player_1.createPlayer)('p1', 'Player 1', true, 0),
            (0, Player_1.createPlayer)('p2', 'Player 2', true, 1),
            (0, Player_1.createPlayer)('p3', 'Bot', false, 2),
        ];
    }
    function createInitializedGameState() {
        const players = createTestPlayers();
        const state = (0, GameState_1.createGameState)(players, GameState_1.GameMode.quick, GameState_1.Difficulty.medium);
        GameLogic_1.GameLogic.initializeGame(state);
        return state;
    }
    (0, node_test_1.describe)('initializeGame', () => {
        (0, node_test_1.it)('creates and shuffles a full deck', () => {
            const players = createTestPlayers();
            const state = (0, GameState_1.createGameState)(players, GameState_1.GameMode.quick, GameState_1.Difficulty.medium);
            GameLogic_1.GameLogic.initializeGame(state);
            // Deck + dealt cards + discard should equal 54
            const totalCards = state.deck.length +
                state.players.reduce((sum, p) => sum + p.hand.length, 0) +
                state.discardPile.length;
            node_assert_1.default.strictEqual(totalCards, 54);
        });
        (0, node_test_1.it)('deals 4 cards to each player', () => {
            const state = createInitializedGameState();
            for (const player of state.players) {
                node_assert_1.default.strictEqual(player.hand.length, 4);
                node_assert_1.default.strictEqual(player.knownCards.length, 4);
            }
        });
        (0, node_test_1.it)('sets phase to setup', () => {
            const state = createInitializedGameState();
            node_assert_1.default.strictEqual(state.phase, GameState_1.GamePhase.setup);
        });
        (0, node_test_1.it)('places one card in discard pile', () => {
            const state = createInitializedGameState();
            node_assert_1.default.strictEqual(state.discardPile.length, 1);
        });
        (0, node_test_1.it)('initializes bot memory (knows first 2 cards)', () => {
            const state = createInitializedGameState();
            const bot = state.players.find(p => !p.isHuman);
            node_assert_1.default.ok(bot);
            node_assert_1.default.strictEqual(bot.knownCards[0], true);
            node_assert_1.default.strictEqual(bot.knownCards[1], true);
            node_assert_1.default.strictEqual(bot.knownCards[2], false);
            node_assert_1.default.strictEqual(bot.knownCards[3], false);
        });
        (0, node_test_1.it)('human players start with no known cards', () => {
            const state = createInitializedGameState();
            const human = state.players.find(p => p.isHuman);
            node_assert_1.default.ok(human);
            node_assert_1.default.ok(human.knownCards.every(k => k === false));
        });
        (0, node_test_1.it)('adds starting message to history', () => {
            const state = createInitializedGameState();
            node_assert_1.default.ok(state.actionHistory.length > 0);
            node_assert_1.default.ok(state.actionHistory.some(h => h.includes('commence') || h.includes('Tirage')));
        });
    });
    (0, node_test_1.describe)('initialReveal', () => {
        (0, node_test_1.it)('marks selected cards as known for human player', () => {
            const state = createInitializedGameState();
            const human = state.players.find(p => p.isHuman);
            GameLogic_1.GameLogic.initialReveal(state, [0, 2]);
            node_assert_1.default.strictEqual(human.knownCards[0], true);
            node_assert_1.default.strictEqual(human.knownCards[1], false);
            node_assert_1.default.strictEqual(human.knownCards[2], true);
            node_assert_1.default.strictEqual(human.knownCards[3], false);
        });
        (0, node_test_1.it)('adds history entry', () => {
            const state = createInitializedGameState();
            const historyLengthBefore = state.actionHistory.length;
            GameLogic_1.GameLogic.initialReveal(state, [0, 1]);
            node_assert_1.default.ok(state.actionHistory.length > historyLengthBefore);
            node_assert_1.default.ok(state.actionHistory.some(h => h.includes('Mémorisation initiale')));
        });
        (0, node_test_1.it)('ignores invalid indices', () => {
            const state = createInitializedGameState();
            const human = state.players.find(p => p.isHuman);
            GameLogic_1.GameLogic.initialReveal(state, [-1, 10, 0]);
            node_assert_1.default.strictEqual(human.knownCards[0], true);
            // Should not throw and only valid index processed
        });
    });
    (0, node_test_1.describe)('drawCard', () => {
        (0, node_test_1.it)('removes card from deck and sets as drawnCard', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            const deckSizeBefore = state.deck.length;
            GameLogic_1.GameLogic.drawCard(state);
            node_assert_1.default.strictEqual(state.deck.length, deckSizeBefore - 1);
            node_assert_1.default.ok(state.drawnCard);
        });
        (0, node_test_1.it)('adds history entry', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            const historyLengthBefore = state.actionHistory.length;
            GameLogic_1.GameLogic.drawCard(state);
            node_assert_1.default.ok(state.actionHistory.length > historyLengthBefore);
            node_assert_1.default.ok(state.actionHistory.some(h => h.includes('pioch')));
        });
        (0, node_test_1.it)('refills deck from discard when empty', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            // Empty the deck
            state.deck = [];
            state.discardPile = [
                (0, Card_1.createCard)('hearts', '5'),
                (0, Card_1.createCard)('spades', '6'),
                (0, Card_1.createCard)('clubs', '7'),
            ];
            GameLogic_1.GameLogic.drawCard(state);
            // Should have drawn a card
            node_assert_1.default.ok(state.drawnCard);
            // Deck should be refilled (2 cards moved, 1 drawn)
            // Discard should keep only top card
            node_assert_1.default.strictEqual(state.discardPile.length, 1);
        });
        (0, node_test_1.it)('ends game when no cards available', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            state.deck = [];
            state.discardPile = [(0, Card_1.createCard)('hearts', 'A')]; // Only 1 card, can't refill
            GameLogic_1.GameLogic.drawCard(state);
            node_assert_1.default.strictEqual(state.phase, GameState_1.GamePhase.ended);
        });
    });
    (0, node_test_1.describe)('discardDrawnCard', () => {
        (0, node_test_1.it)('puts drawn card in discard pile', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            const card = (0, Card_1.createCard)('hearts', '5');
            state.drawnCard = card;
            GameLogic_1.GameLogic.discardDrawnCard(state);
            node_assert_1.default.strictEqual(state.drawnCard, null);
            node_assert_1.default.strictEqual(state.discardPile[state.discardPile.length - 1], card);
        });
        (0, node_test_1.it)('does nothing if no drawn card', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            state.drawnCard = null;
            const discardLength = state.discardPile.length;
            GameLogic_1.GameLogic.discardDrawnCard(state);
            node_assert_1.default.strictEqual(state.discardPile.length, discardLength);
        });
        (0, node_test_1.it)('triggers special power check for special cards', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            state.drawnCard = (0, Card_1.createCard)('hearts', '7');
            GameLogic_1.GameLogic.discardDrawnCard(state);
            node_assert_1.default.strictEqual(state.isWaitingForSpecialPower, true);
            node_assert_1.default.ok(state.specialCardToActivate);
            node_assert_1.default.strictEqual(state.specialCardToActivate.value, '7');
        });
        (0, node_test_1.it)('starts reaction phase for non-special cards', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            state.drawnCard = (0, Card_1.createCard)('hearts', '5');
            GameLogic_1.GameLogic.discardDrawnCard(state);
            node_assert_1.default.strictEqual(state.phase, GameState_1.GamePhase.reaction);
            node_assert_1.default.ok(state.reactionStartTime);
        });
    });
    (0, node_test_1.describe)('replaceCard', () => {
        (0, node_test_1.it)('swaps drawn card with hand card', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            const drawnCard = (0, Card_1.createCard)('hearts', 'A');
            const handCard = state.players[0].hand[1];
            state.drawnCard = drawnCard;
            state.currentPlayerIndex = 0;
            GameLogic_1.GameLogic.replaceCard(state, 1);
            node_assert_1.default.strictEqual(state.players[0].hand[1], drawnCard);
            node_assert_1.default.strictEqual(state.discardPile[state.discardPile.length - 1], handCard);
            node_assert_1.default.strictEqual(state.drawnCard, null);
        });
        (0, node_test_1.it)('marks replaced card position as known', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            state.drawnCard = (0, Card_1.createCard)('hearts', 'A');
            state.currentPlayerIndex = 0;
            state.players[0].knownCards[2] = false;
            GameLogic_1.GameLogic.replaceCard(state, 2);
            node_assert_1.default.strictEqual(state.players[0].knownCards[2], true);
        });
        (0, node_test_1.it)('does nothing if no drawn card', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            state.drawnCard = null;
            const handBefore = [...state.players[0].hand];
            GameLogic_1.GameLogic.replaceCard(state, 0);
            node_assert_1.default.deepStrictEqual(state.players[0].hand, handBefore);
        });
        (0, node_test_1.it)('does nothing for invalid card index', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            state.drawnCard = (0, Card_1.createCard)('hearts', 'A');
            const handBefore = [...state.players[0].hand];
            GameLogic_1.GameLogic.replaceCard(state, -1);
            node_assert_1.default.deepStrictEqual(state.players[0].hand, handBefore);
            GameLogic_1.GameLogic.replaceCard(state, 10);
            node_assert_1.default.deepStrictEqual(state.players[0].hand, handBefore);
        });
        (0, node_test_1.it)('triggers special power for discarded special card', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            state.drawnCard = (0, Card_1.createCard)('hearts', 'A');
            state.currentPlayerIndex = 0;
            state.players[0].hand[0] = (0, Card_1.createCard)('spades', '10');
            GameLogic_1.GameLogic.replaceCard(state, 0);
            node_assert_1.default.strictEqual(state.isWaitingForSpecialPower, true);
        });
    });
    (0, node_test_1.describe)('matchCard', () => {
        (0, node_test_1.it)('returns true and removes card on successful match', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.reaction;
            const matchingCard = (0, Card_1.createCard)('hearts', '5');
            state.discardPile.push((0, Card_1.createCard)('spades', '5'));
            state.players[0].hand[0] = matchingCard;
            state.players[0].knownCards[0] = true;
            const handSizeBefore = state.players[0].hand.length;
            const result = GameLogic_1.GameLogic.matchCard(state, state.players[0], 0);
            node_assert_1.default.strictEqual(result, true);
            node_assert_1.default.strictEqual(state.players[0].hand.length, handSizeBefore - 1);
            node_assert_1.default.ok(!state.players[0].hand.includes(matchingCard));
        });
        (0, node_test_1.it)('returns false and applies penalty on failed match', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.reaction;
            state.discardPile.push((0, Card_1.createCard)('spades', '5'));
            state.players[0].hand[0] = (0, Card_1.createCard)('hearts', '6'); // Different value
            const handSizeBefore = state.players[0].hand.length;
            const result = GameLogic_1.GameLogic.matchCard(state, state.players[0], 0);
            node_assert_1.default.strictEqual(result, false);
            // Hand size should increase (failed match = penalty card)
            node_assert_1.default.strictEqual(state.players[0].hand.length, handSizeBefore + 1);
        });
        (0, node_test_1.it)('returns false for empty discard pile', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.reaction;
            state.discardPile = [];
            const result = GameLogic_1.GameLogic.matchCard(state, state.players[0], 0);
            node_assert_1.default.strictEqual(result, false);
        });
        (0, node_test_1.it)('returns false for invalid card index', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.reaction;
            state.discardPile.push((0, Card_1.createCard)('spades', '5'));
            node_assert_1.default.strictEqual(GameLogic_1.GameLogic.matchCard(state, state.players[0], -1), false);
            node_assert_1.default.strictEqual(GameLogic_1.GameLogic.matchCard(state, state.players[0], 10), false);
        });
    });
    (0, node_test_1.describe)('applyPenalty', () => {
        (0, node_test_1.it)('adds a penalty card to player hand', () => {
            const state = createInitializedGameState();
            const player = state.players[0];
            const handSizeBefore = player.hand.length;
            const knownSizeBefore = player.knownCards.length;
            GameLogic_1.GameLogic.applyPenalty(state, player);
            node_assert_1.default.strictEqual(player.hand.length, handSizeBefore + 1);
            node_assert_1.default.strictEqual(player.knownCards.length, knownSizeBefore + 1);
            node_assert_1.default.strictEqual(player.knownCards[player.knownCards.length - 1], false);
        });
        (0, node_test_1.it)('refills deck if empty before applying penalty', () => {
            const state = createInitializedGameState();
            state.deck = [];
            state.discardPile = [
                (0, Card_1.createCard)('hearts', '5'),
                (0, Card_1.createCard)('spades', '6'),
            ];
            const player = state.players[0];
            const handSizeBefore = player.hand.length;
            GameLogic_1.GameLogic.applyPenalty(state, player);
            node_assert_1.default.strictEqual(player.hand.length, handSizeBefore + 1);
        });
    });
    (0, node_test_1.describe)('swapCards', () => {
        (0, node_test_1.it)('swaps cards between two players', () => {
            const state = createInitializedGameState();
            const p1 = state.players[0];
            const p2 = state.players[1];
            const card1 = p1.hand[0];
            const card2 = p2.hand[1];
            GameLogic_1.GameLogic.swapCards(state, p1, 0, p2, 1);
            node_assert_1.default.strictEqual(p1.hand[0], card2);
            node_assert_1.default.strictEqual(p2.hand[1], card1);
        });
        (0, node_test_1.it)('resets knownCards for swapped positions', () => {
            const state = createInitializedGameState();
            const p1 = state.players[0];
            const p2 = state.players[1];
            p1.knownCards[0] = true;
            p2.knownCards[1] = true;
            GameLogic_1.GameLogic.swapCards(state, p1, 0, p2, 1);
            node_assert_1.default.strictEqual(p1.knownCards[0], false);
            node_assert_1.default.strictEqual(p2.knownCards[1], false);
        });
        (0, node_test_1.it)('does nothing for invalid indices', () => {
            const state = createInitializedGameState();
            const p1 = state.players[0];
            const p2 = state.players[1];
            const hand1Before = [...p1.hand];
            const hand2Before = [...p2.hand];
            GameLogic_1.GameLogic.swapCards(state, p1, -1, p2, 0);
            node_assert_1.default.deepStrictEqual(p1.hand, hand1Before);
            GameLogic_1.GameLogic.swapCards(state, p1, 0, p2, 10);
            node_assert_1.default.deepStrictEqual(p2.hand, hand2Before);
        });
    });
    (0, node_test_1.describe)('jokerEffect', () => {
        (0, node_test_1.it)('shuffles target player hand', () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 0;
            const target = state.players[1];
            const originalHand = [...target.hand];
            // Note: shuffle might result in same order by chance
            // We mainly test that the operation completes
            GameLogic_1.GameLogic.jokerEffect(state, target);
            // Hand length should remain the same
            node_assert_1.default.strictEqual(target.hand.length, originalHand.length);
            // All original cards should still be present (just shuffled)
            for (const card of originalHand) {
                node_assert_1.default.ok(target.hand.some(c => c.id === card.id));
            }
        });
        (0, node_test_1.it)('resets all knownCards to false', () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 0;
            const target = state.players[1];
            target.knownCards = [true, true, true, true];
            GameLogic_1.GameLogic.jokerEffect(state, target);
            node_assert_1.default.ok(target.knownCards.every(k => k === false));
        });
        (0, node_test_1.it)('adds history entry', () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 0;
            const historyBefore = state.actionHistory.length;
            GameLogic_1.GameLogic.jokerEffect(state, state.players[1]);
            node_assert_1.default.ok(state.actionHistory.length > historyBefore);
            node_assert_1.default.ok(state.actionHistory.some(h => h.includes('JOKER') || h.includes('mélange')));
        });
    });
    (0, node_test_1.describe)('callDutch', () => {
        (0, node_test_1.it)('sets dutchCallerId and changes phase', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            GameLogic_1.GameLogic.callDutch(state, 'p1');
            node_assert_1.default.strictEqual(state.dutchCallerId, 'p1');
            // After calling Dutch, game should end immediately per code
            node_assert_1.default.strictEqual(state.phase, GameState_1.GamePhase.ended);
        });
        (0, node_test_1.it)('uses current player if no playerId provided', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            state.currentPlayerIndex = 1;
            GameLogic_1.GameLogic.callDutch(state);
            node_assert_1.default.strictEqual(state.dutchCallerId, 'p2');
        });
        (0, node_test_1.it)('does not allow second Dutch call', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            state.dutchCallerId = 'p1';
            GameLogic_1.GameLogic.callDutch(state, 'p2');
            node_assert_1.default.strictEqual(state.dutchCallerId, 'p1'); // Should not change
        });
    });
    (0, node_test_1.describe)('takeFromDiscard', () => {
        (0, node_test_1.it)('takes top card from discard as drawn card', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            const topCard = state.discardPile[state.discardPile.length - 1];
            const discardSizeBefore = state.discardPile.length;
            GameLogic_1.GameLogic.takeFromDiscard(state);
            node_assert_1.default.strictEqual(state.drawnCard, topCard);
            node_assert_1.default.strictEqual(state.discardPile.length, discardSizeBefore - 1);
        });
        (0, node_test_1.it)('does nothing if discard pile is empty', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            state.discardPile = [];
            GameLogic_1.GameLogic.takeFromDiscard(state);
            node_assert_1.default.strictEqual(state.drawnCard, null);
        });
    });
    (0, node_test_1.describe)('attemptMatch', () => {
        (0, node_test_1.it)('finds player by id and attempts match', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.reaction;
            state.discardPile.push((0, Card_1.createCard)('hearts', '5'));
            state.players[1].hand[0] = (0, Card_1.createCard)('spades', '5');
            const result = GameLogic_1.GameLogic.attemptMatch(state, 'p2', 0);
            node_assert_1.default.strictEqual(result, true);
        });
        (0, node_test_1.it)('returns false for non-existent player', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.reaction;
            state.discardPile.push((0, Card_1.createCard)('hearts', '5'));
            const result = GameLogic_1.GameLogic.attemptMatch(state, 'nonexistent', 0);
            node_assert_1.default.strictEqual(result, false);
        });
    });
    (0, node_test_1.describe)('useSpecialPower', () => {
        (0, node_test_1.it)('handles card 7 - look at own card', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.specialPower;
            state.currentPlayerIndex = 0;
            state.isWaitingForSpecialPower = true;
            state.specialCardToActivate = (0, Card_1.createCard)('hearts', '7');
            state.players[0].knownCards[2] = false;
            const result = GameLogic_1.GameLogic.useSpecialPower(state, { cardIndex: 2 });
            node_assert_1.default.ok(result.spiedCard);
            node_assert_1.default.strictEqual(state.players[0].knownCards[2], true);
            node_assert_1.default.strictEqual(state.isWaitingForSpecialPower, false);
        });
        (0, node_test_1.it)('handles card 10 - spy on opponent', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.specialPower;
            state.currentPlayerIndex = 0;
            state.isWaitingForSpecialPower = true;
            state.specialCardToActivate = (0, Card_1.createCard)('spades', '10');
            const result = GameLogic_1.GameLogic.useSpecialPower(state, {
                targetPlayerIndex: 1,
                targetCardIndex: 0,
            });
            node_assert_1.default.ok(result.spiedCard);
            node_assert_1.default.strictEqual(result.spiedCard, state.players[1].hand[0]);
        });
        (0, node_test_1.it)('handles card V (Jack) - swap between any two players', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.specialPower;
            state.currentPlayerIndex = 0;
            state.isWaitingForSpecialPower = true;
            state.specialCardToActivate = (0, Card_1.createCard)('clubs', 'V');
            const card1 = state.players[1].hand[0];
            const card2 = state.players[2].hand[1];
            const result = GameLogic_1.GameLogic.useSpecialPower(state, {
                player1Index: 1,
                card1Index: 0,
                player2Index: 2,
                card2Index: 1,
            });
            node_assert_1.default.strictEqual(state.players[1].hand[0], card2);
            node_assert_1.default.strictEqual(state.players[2].hand[1], card1);
            node_assert_1.default.ok(result.affectedPlayers);
            node_assert_1.default.strictEqual(result.affectedPlayers.length, 2);
        });
        (0, node_test_1.it)('handles JOKER - shuffle target player hand', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.specialPower;
            state.currentPlayerIndex = 0;
            state.isWaitingForSpecialPower = true;
            state.specialCardToActivate = (0, Card_1.createCard)('joker', 'JOKER');
            state.players[1].knownCards = [true, true, true, true];
            const result = GameLogic_1.GameLogic.useSpecialPower(state, { targetPlayerIndex: 1 });
            node_assert_1.default.ok(state.players[1].knownCards.every(k => k === false));
            node_assert_1.default.ok(result.shuffledPlayer);
            node_assert_1.default.strictEqual(result.shuffledPlayer.playerId, 'p2');
        });
        (0, node_test_1.it)('returns empty object if not waiting for special power', () => {
            const state = createInitializedGameState();
            state.isWaitingForSpecialPower = false;
            const result = GameLogic_1.GameLogic.useSpecialPower(state, { cardIndex: 0 });
            node_assert_1.default.deepStrictEqual(result, {});
        });
        (0, node_test_1.it)('starts reaction phase after power use', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.specialPower;
            state.currentPlayerIndex = 0;
            state.isWaitingForSpecialPower = true;
            state.specialCardToActivate = (0, Card_1.createCard)('hearts', '7');
            GameLogic_1.GameLogic.useSpecialPower(state, { cardIndex: 0 });
            node_assert_1.default.strictEqual(state.phase, GameState_1.GamePhase.reaction);
        });
    });
    (0, node_test_1.describe)('skipSpecialPower', () => {
        (0, node_test_1.it)('clears special power state', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            state.isWaitingForSpecialPower = true;
            state.specialCardToActivate = (0, Card_1.createCard)('hearts', '7');
            GameLogic_1.GameLogic.skipSpecialPower(state);
            node_assert_1.default.strictEqual(state.isWaitingForSpecialPower, false);
            node_assert_1.default.strictEqual(state.specialCardToActivate, null);
        });
        (0, node_test_1.it)('starts reaction phase', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            state.isWaitingForSpecialPower = true;
            state.specialCardToActivate = (0, Card_1.createCard)('hearts', '7');
            GameLogic_1.GameLogic.skipSpecialPower(state);
            node_assert_1.default.strictEqual(state.phase, GameState_1.GamePhase.reaction);
        });
    });
    (0, node_test_1.describe)('endGame', () => {
        (0, node_test_1.it)('sets phase to ended', () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            GameLogic_1.GameLogic.endGame(state);
            node_assert_1.default.strictEqual(state.phase, GameState_1.GamePhase.ended);
        });
        (0, node_test_1.it)('reveals all cards (sets all knownCards to true)', () => {
            const state = createInitializedGameState();
            GameLogic_1.GameLogic.endGame(state);
            for (const player of state.players) {
                node_assert_1.default.ok(player.knownCards.every(k => k === true));
            }
        });
    });
    (0, node_test_1.describe)('nextPlayer', () => {
        (0, node_test_1.it)('advances to next player', () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 0;
            GameLogic_1.GameLogic.nextPlayer(state);
            node_assert_1.default.strictEqual(state.currentPlayerIndex, 1);
        });
    });
});
//# sourceMappingURL=gameLogic.test.js.map