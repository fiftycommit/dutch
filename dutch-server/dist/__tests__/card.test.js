"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const node_assert_1 = __importDefault(require("node:assert"));
const Card_1 = require("../models/Card");
(0, node_test_1.describe)('Card', () => {
    (0, node_test_1.describe)('createCard', () => {
        (0, node_test_1.it)('creates a numeric card with correct points', () => {
            const card = (0, Card_1.createCard)('hearts', '5');
            node_assert_1.default.strictEqual(card.suit, 'hearts');
            node_assert_1.default.strictEqual(card.value, '5');
            node_assert_1.default.strictEqual(card.points, 5);
            node_assert_1.default.strictEqual(card.isSpecial, false);
            node_assert_1.default.strictEqual(card.id, '5_hearts');
        });
        (0, node_test_1.it)('creates an Ace with 1 point', () => {
            const card = (0, Card_1.createCard)('spades', 'A');
            node_assert_1.default.strictEqual(card.points, 1);
            node_assert_1.default.strictEqual(card.isSpecial, false);
        });
        (0, node_test_1.it)('creates a Jack (Valet) with 11 points and isSpecial=true', () => {
            const card = (0, Card_1.createCard)('clubs', 'V');
            node_assert_1.default.strictEqual(card.points, 11);
            node_assert_1.default.strictEqual(card.isSpecial, true);
        });
        (0, node_test_1.it)('creates a Queen (Dame) with 12 points', () => {
            const card = (0, Card_1.createCard)('diamonds', 'D');
            node_assert_1.default.strictEqual(card.points, 12);
            node_assert_1.default.strictEqual(card.isSpecial, false);
        });
        (0, node_test_1.it)('creates a red King with 0 points', () => {
            const cardHearts = (0, Card_1.createCard)('hearts', 'R');
            const cardDiamonds = (0, Card_1.createCard)('diamonds', 'R');
            node_assert_1.default.strictEqual(cardHearts.points, 0);
            node_assert_1.default.strictEqual(cardDiamonds.points, 0);
        });
        (0, node_test_1.it)('creates a black King with 13 points', () => {
            const cardSpades = (0, Card_1.createCard)('spades', 'R');
            const cardClubs = (0, Card_1.createCard)('clubs', 'R');
            node_assert_1.default.strictEqual(cardSpades.points, 13);
            node_assert_1.default.strictEqual(cardClubs.points, 13);
        });
        (0, node_test_1.it)('creates a Joker with 0 points and isSpecial=true', () => {
            const card = (0, Card_1.createCard)('joker', 'JOKER');
            node_assert_1.default.strictEqual(card.points, 0);
            node_assert_1.default.strictEqual(card.isSpecial, true);
        });
        (0, node_test_1.it)('creates a 7 card as special', () => {
            const card = (0, Card_1.createCard)('hearts', '7');
            node_assert_1.default.strictEqual(card.points, 7);
            node_assert_1.default.strictEqual(card.isSpecial, true);
        });
        (0, node_test_1.it)('creates a 10 card as special', () => {
            const card = (0, Card_1.createCard)('spades', '10');
            node_assert_1.default.strictEqual(card.points, 10);
            node_assert_1.default.strictEqual(card.isSpecial, true);
        });
    });
    (0, node_test_1.describe)('createFullDeck', () => {
        (0, node_test_1.it)('creates a deck with 54 cards (52 + 2 jokers)', () => {
            const deck = (0, Card_1.createFullDeck)();
            node_assert_1.default.strictEqual(deck.length, 54);
        });
        (0, node_test_1.it)('contains 4 suits with 13 cards each', () => {
            const deck = (0, Card_1.createFullDeck)();
            const suits = ['hearts', 'diamonds', 'clubs', 'spades'];
            for (const suit of suits) {
                const suitCards = deck.filter(c => c.suit === suit);
                node_assert_1.default.strictEqual(suitCards.length, 13, `Expected 13 ${suit} cards`);
            }
        });
        (0, node_test_1.it)('contains exactly 2 jokers', () => {
            const deck = (0, Card_1.createFullDeck)();
            const jokers = deck.filter(c => c.value === 'JOKER');
            node_assert_1.default.strictEqual(jokers.length, 2);
        });
        (0, node_test_1.it)('contains all values for each suit', () => {
            const deck = (0, Card_1.createFullDeck)();
            const values = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'V', 'D', 'R'];
            const hearts = deck.filter(c => c.suit === 'hearts');
            const heartValues = hearts.map(c => c.value);
            for (const value of values) {
                node_assert_1.default.ok(heartValues.includes(value), `Missing ${value} in hearts`);
            }
        });
        (0, node_test_1.it)('has correct total points distribution', () => {
            const deck = (0, Card_1.createFullDeck)();
            // 2 red kings (0) + 2 black kings (13) + 2 jokers (0) = 26
            const kings = deck.filter(c => c.value === 'R');
            const jokers = deck.filter(c => c.value === 'JOKER');
            node_assert_1.default.strictEqual(kings.length, 4);
            node_assert_1.default.strictEqual(jokers.length, 2);
            // Red kings = 0, Black kings = 13
            const redKings = kings.filter(c => c.suit === 'hearts' || c.suit === 'diamonds');
            const blackKings = kings.filter(c => c.suit === 'spades' || c.suit === 'clubs');
            node_assert_1.default.strictEqual(redKings.every(k => k.points === 0), true);
            node_assert_1.default.strictEqual(blackKings.every(k => k.points === 13), true);
        });
    });
    (0, node_test_1.describe)('cardMatches', () => {
        (0, node_test_1.it)('returns true for same value cards', () => {
            const card1 = (0, Card_1.createCard)('hearts', '5');
            const card2 = (0, Card_1.createCard)('spades', '5');
            node_assert_1.default.strictEqual((0, Card_1.cardMatches)(card1, card2), true);
        });
        (0, node_test_1.it)('returns false for different value cards', () => {
            const card1 = (0, Card_1.createCard)('hearts', '5');
            const card2 = (0, Card_1.createCard)('hearts', '6');
            node_assert_1.default.strictEqual((0, Card_1.cardMatches)(card1, card2), false);
        });
        (0, node_test_1.it)('matches Kings regardless of color', () => {
            const redKing = (0, Card_1.createCard)('hearts', 'R');
            const blackKing = (0, Card_1.createCard)('spades', 'R');
            node_assert_1.default.strictEqual((0, Card_1.cardMatches)(redKing, blackKing), true);
        });
        (0, node_test_1.it)('matches two Jokers', () => {
            const joker1 = (0, Card_1.createCard)('joker', 'JOKER');
            const joker2 = (0, Card_1.createCard)('joker', 'JOKER');
            node_assert_1.default.strictEqual((0, Card_1.cardMatches)(joker1, joker2), true);
        });
        (0, node_test_1.it)('does not match different face cards', () => {
            const jack = (0, Card_1.createCard)('hearts', 'V');
            const queen = (0, Card_1.createCard)('hearts', 'D');
            node_assert_1.default.strictEqual((0, Card_1.cardMatches)(jack, queen), false);
        });
        (0, node_test_1.it)('matches Aces', () => {
            const ace1 = (0, Card_1.createCard)('hearts', 'A');
            const ace2 = (0, Card_1.createCard)('clubs', 'A');
            node_assert_1.default.strictEqual((0, Card_1.cardMatches)(ace1, ace2), true);
        });
        (0, node_test_1.it)('matches 10s', () => {
            const ten1 = (0, Card_1.createCard)('diamonds', '10');
            const ten2 = (0, Card_1.createCard)('spades', '10');
            node_assert_1.default.strictEqual((0, Card_1.cardMatches)(ten1, ten2), true);
        });
    });
});
