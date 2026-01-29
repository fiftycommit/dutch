import { describe, it } from 'node:test';
import assert from 'node:assert';
import { createCard, createFullDeck, cardMatches, PlayingCard } from '../models/Card';

describe('Card', () => {
  describe('createCard', () => {
    it('creates a numeric card with correct points', () => {
      const card = createCard('hearts', '5');
      assert.strictEqual(card.suit, 'hearts');
      assert.strictEqual(card.value, '5');
      assert.strictEqual(card.points, 5);
      assert.strictEqual(card.isSpecial, false);
      assert.strictEqual(card.id, '5_hearts');
    });

    it('creates an Ace with 1 point', () => {
      const card = createCard('spades', 'A');
      assert.strictEqual(card.points, 1);
      assert.strictEqual(card.isSpecial, false);
    });

    it('creates a Jack (Valet) with 11 points and isSpecial=true', () => {
      const card = createCard('clubs', 'V');
      assert.strictEqual(card.points, 11);
      assert.strictEqual(card.isSpecial, true);
    });

    it('creates a Queen (Dame) with 12 points', () => {
      const card = createCard('diamonds', 'D');
      assert.strictEqual(card.points, 12);
      assert.strictEqual(card.isSpecial, false);
    });

    it('creates a red King with 0 points', () => {
      const cardHearts = createCard('hearts', 'R');
      const cardDiamonds = createCard('diamonds', 'R');
      assert.strictEqual(cardHearts.points, 0);
      assert.strictEqual(cardDiamonds.points, 0);
    });

    it('creates a black King with 13 points', () => {
      const cardSpades = createCard('spades', 'R');
      const cardClubs = createCard('clubs', 'R');
      assert.strictEqual(cardSpades.points, 13);
      assert.strictEqual(cardClubs.points, 13);
    });

    it('creates a Joker with 0 points and isSpecial=true', () => {
      const card = createCard('joker', 'JOKER');
      assert.strictEqual(card.points, 0);
      assert.strictEqual(card.isSpecial, true);
    });

    it('creates a 7 card as special', () => {
      const card = createCard('hearts', '7');
      assert.strictEqual(card.points, 7);
      assert.strictEqual(card.isSpecial, true);
    });

    it('creates a 10 card as special', () => {
      const card = createCard('spades', '10');
      assert.strictEqual(card.points, 10);
      assert.strictEqual(card.isSpecial, true);
    });
  });

  describe('createFullDeck', () => {
    it('creates a deck with 54 cards (52 + 2 jokers)', () => {
      const deck = createFullDeck();
      assert.strictEqual(deck.length, 54);
    });

    it('contains 4 suits with 13 cards each', () => {
      const deck = createFullDeck();
      const suits = ['hearts', 'diamonds', 'clubs', 'spades'];

      for (const suit of suits) {
        const suitCards = deck.filter(c => c.suit === suit);
        assert.strictEqual(suitCards.length, 13, `Expected 13 ${suit} cards`);
      }
    });

    it('contains exactly 2 jokers', () => {
      const deck = createFullDeck();
      const jokers = deck.filter(c => c.value === 'JOKER');
      assert.strictEqual(jokers.length, 2);
    });

    it('contains all values for each suit', () => {
      const deck = createFullDeck();
      const values = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'V', 'D', 'R'];

      const hearts = deck.filter(c => c.suit === 'hearts');
      const heartValues = hearts.map(c => c.value);

      for (const value of values) {
        assert.ok(heartValues.includes(value), `Missing ${value} in hearts`);
      }
    });

    it('has correct total points distribution', () => {
      const deck = createFullDeck();
      // 2 red kings (0) + 2 black kings (13) + 2 jokers (0) = 26
      const kings = deck.filter(c => c.value === 'R');
      const jokers = deck.filter(c => c.value === 'JOKER');

      assert.strictEqual(kings.length, 4);
      assert.strictEqual(jokers.length, 2);

      // Red kings = 0, Black kings = 13
      const redKings = kings.filter(c => c.suit === 'hearts' || c.suit === 'diamonds');
      const blackKings = kings.filter(c => c.suit === 'spades' || c.suit === 'clubs');

      assert.strictEqual(redKings.every(k => k.points === 0), true);
      assert.strictEqual(blackKings.every(k => k.points === 13), true);
    });
  });

  describe('cardMatches', () => {
    it('returns true for same value cards', () => {
      const card1 = createCard('hearts', '5');
      const card2 = createCard('spades', '5');
      assert.strictEqual(cardMatches(card1, card2), true);
    });

    it('returns false for different value cards', () => {
      const card1 = createCard('hearts', '5');
      const card2 = createCard('hearts', '6');
      assert.strictEqual(cardMatches(card1, card2), false);
    });

    it('matches Kings regardless of color', () => {
      const redKing = createCard('hearts', 'R');
      const blackKing = createCard('spades', 'R');
      assert.strictEqual(cardMatches(redKing, blackKing), true);
    });

    it('matches two Jokers', () => {
      const joker1 = createCard('joker', 'JOKER');
      const joker2 = createCard('joker', 'JOKER');
      assert.strictEqual(cardMatches(joker1, joker2), true);
    });

    it('does not match different face cards', () => {
      const jack = createCard('hearts', 'V');
      const queen = createCard('hearts', 'D');
      assert.strictEqual(cardMatches(jack, queen), false);
    });

    it('matches Aces', () => {
      const ace1 = createCard('hearts', 'A');
      const ace2 = createCard('clubs', 'A');
      assert.strictEqual(cardMatches(ace1, ace2), true);
    });

    it('matches 10s', () => {
      const ten1 = createCard('diamonds', '10');
      const ten2 = createCard('spades', '10');
      assert.strictEqual(cardMatches(ten1, ten2), true);
    });
  });
});
