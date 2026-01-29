import { describe, it } from 'node:test';
import assert from 'node:assert';
import { GameLogic } from '../services/GameLogic';
import { createGameState, GamePhase, GameMode, Difficulty, getCurrentPlayer } from '../models/GameState';
import { createPlayer, Player } from '../models/Player';
import { createCard, PlayingCard } from '../models/Card';

describe('GameLogic', () => {
  function createTestPlayers(): Player[] {
    return [
      createPlayer('p1', 'Player 1', true, 0),
      createPlayer('p2', 'Player 2', true, 1),
      createPlayer('p3', 'Bot', false, 2),
    ];
  }

  function createInitializedGameState() {
    const players = createTestPlayers();
    const state = createGameState(players, GameMode.quick, Difficulty.medium);
    GameLogic.initializeGame(state);
    return state;
  }

  describe('initializeGame', () => {
    it('creates and shuffles a full deck', () => {
      const players = createTestPlayers();
      const state = createGameState(players, GameMode.quick, Difficulty.medium);

      GameLogic.initializeGame(state);

      // Deck + dealt cards + discard should equal 54
      const totalCards = state.deck.length +
        state.players.reduce((sum, p) => sum + p.hand.length, 0) +
        state.discardPile.length;
      assert.strictEqual(totalCards, 54);
    });

    it('deals 4 cards to each player', () => {
      const state = createInitializedGameState();

      for (const player of state.players) {
        assert.strictEqual(player.hand.length, 4);
        assert.strictEqual(player.knownCards.length, 4);
      }
    });

    it('sets phase to setup', () => {
      const state = createInitializedGameState();
      assert.strictEqual(state.phase, GamePhase.setup);
    });

    it('places one card in discard pile', () => {
      const state = createInitializedGameState();
      assert.strictEqual(state.discardPile.length, 1);
    });

    it('initializes bot memory (knows first 2 cards)', () => {
      const state = createInitializedGameState();
      const bot = state.players.find(p => !p.isHuman);

      assert.ok(bot);
      assert.strictEqual(bot.knownCards[0], true);
      assert.strictEqual(bot.knownCards[1], true);
      assert.strictEqual(bot.knownCards[2], false);
      assert.strictEqual(bot.knownCards[3], false);
    });

    it('human players start with no known cards', () => {
      const state = createInitializedGameState();
      const human = state.players.find(p => p.isHuman);

      assert.ok(human);
      assert.ok(human.knownCards.every(k => k === false));
    });

    it('adds starting message to history', () => {
      const state = createInitializedGameState();
      assert.ok(state.actionHistory.length > 0);
      assert.ok(state.actionHistory.some(h => h.includes('commence') || h.includes('Tirage')));
    });
  });

  describe('initialReveal', () => {
    it('marks selected cards as known for human player', () => {
      const state = createInitializedGameState();
      const human = state.players.find(p => p.isHuman)!;

      GameLogic.initialReveal(state, [0, 2]);

      assert.strictEqual(human.knownCards[0], true);
      assert.strictEqual(human.knownCards[1], false);
      assert.strictEqual(human.knownCards[2], true);
      assert.strictEqual(human.knownCards[3], false);
    });

    it('adds history entry', () => {
      const state = createInitializedGameState();
      const historyLengthBefore = state.actionHistory.length;

      GameLogic.initialReveal(state, [0, 1]);

      assert.ok(state.actionHistory.length > historyLengthBefore);
      assert.ok(state.actionHistory.some(h => h.includes('mémorisé')));
    });

    it('ignores invalid indices', () => {
      const state = createInitializedGameState();
      const human = state.players.find(p => p.isHuman)!;

      GameLogic.initialReveal(state, [-1, 10, 0]);

      assert.strictEqual(human.knownCards[0], true);
      // Should not throw and only valid index processed
    });
  });

  describe('drawCard', () => {
    it('removes card from deck and sets as drawnCard', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      const deckSizeBefore = state.deck.length;

      GameLogic.drawCard(state);

      assert.strictEqual(state.deck.length, deckSizeBefore - 1);
      assert.ok(state.drawnCard);
    });

    it('adds history entry', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      const historyLengthBefore = state.actionHistory.length;

      GameLogic.drawCard(state);

      assert.ok(state.actionHistory.length > historyLengthBefore);
      assert.ok(state.actionHistory.some(h => h.includes('pioche')));
    });

    it('refills deck from discard when empty', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;

      // Empty the deck
      state.deck = [];
      state.discardPile = [
        createCard('hearts', '5'),
        createCard('spades', '6'),
        createCard('clubs', '7'),
      ];

      GameLogic.drawCard(state);

      // Should have drawn a card
      assert.ok(state.drawnCard);
      // Deck should be refilled (2 cards moved, 1 drawn)
      // Discard should keep only top card
      assert.strictEqual(state.discardPile.length, 1);
    });

    it('ends game when no cards available', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      state.deck = [];
      state.discardPile = [createCard('hearts', 'A')]; // Only 1 card, can't refill

      GameLogic.drawCard(state);

      assert.strictEqual(state.phase, GamePhase.ended);
    });
  });

  describe('discardDrawnCard', () => {
    it('puts drawn card in discard pile', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      const card = createCard('hearts', '5');
      state.drawnCard = card;

      GameLogic.discardDrawnCard(state);

      assert.strictEqual(state.drawnCard, null);
      assert.strictEqual(state.discardPile[state.discardPile.length - 1], card);
    });

    it('does nothing if no drawn card', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      state.drawnCard = null;
      const discardLength = state.discardPile.length;

      GameLogic.discardDrawnCard(state);

      assert.strictEqual(state.discardPile.length, discardLength);
    });

    it('triggers special power check for special cards', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      state.drawnCard = createCard('hearts', '7');

      GameLogic.discardDrawnCard(state);

      assert.strictEqual(state.isWaitingForSpecialPower, true);
      assert.ok(state.specialCardToActivate);
      assert.strictEqual(state.specialCardToActivate!.value, '7');
    });

    it('starts reaction phase for non-special cards', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      state.drawnCard = createCard('hearts', '5');

      GameLogic.discardDrawnCard(state);

      assert.strictEqual(state.phase, GamePhase.reaction);
      assert.ok(state.reactionStartTime);
    });
  });

  describe('replaceCard', () => {
    it('swaps drawn card with hand card', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      const drawnCard = createCard('hearts', 'A');
      const handCard = state.players[0].hand[1];
      state.drawnCard = drawnCard;
      state.currentPlayerIndex = 0;

      GameLogic.replaceCard(state, 1);

      assert.strictEqual(state.players[0].hand[1], drawnCard);
      assert.strictEqual(state.discardPile[state.discardPile.length - 1], handCard);
      assert.strictEqual(state.drawnCard, null);
    });

    it('marks replaced card position as known', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      state.drawnCard = createCard('hearts', 'A');
      state.currentPlayerIndex = 0;
      state.players[0].knownCards[2] = false;

      GameLogic.replaceCard(state, 2);

      assert.strictEqual(state.players[0].knownCards[2], true);
    });

    it('does nothing if no drawn card', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      state.drawnCard = null;
      const handBefore = [...state.players[0].hand];

      GameLogic.replaceCard(state, 0);

      assert.deepStrictEqual(state.players[0].hand, handBefore);
    });

    it('does nothing for invalid card index', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      state.drawnCard = createCard('hearts', 'A');
      const handBefore = [...state.players[0].hand];

      GameLogic.replaceCard(state, -1);
      assert.deepStrictEqual(state.players[0].hand, handBefore);

      GameLogic.replaceCard(state, 10);
      assert.deepStrictEqual(state.players[0].hand, handBefore);
    });

    it('triggers special power for discarded special card', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      state.drawnCard = createCard('hearts', 'A');
      state.currentPlayerIndex = 0;
      state.players[0].hand[0] = createCard('spades', '10');

      GameLogic.replaceCard(state, 0);

      assert.strictEqual(state.isWaitingForSpecialPower, true);
    });
  });

  describe('matchCard', () => {
    it('returns true and removes card on successful match', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.reaction;
      const matchingCard = createCard('hearts', '5');
      state.discardPile.push(createCard('spades', '5'));
      state.players[0].hand[0] = matchingCard;
      state.players[0].knownCards[0] = true;
      const handSizeBefore = state.players[0].hand.length;

      const result = GameLogic.matchCard(state, state.players[0], 0);

      assert.strictEqual(result, true);
      assert.strictEqual(state.players[0].hand.length, handSizeBefore - 1);
      assert.ok(!state.players[0].hand.includes(matchingCard));
    });

    it('returns false and applies penalty on failed match', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.reaction;
      state.discardPile.push(createCard('spades', '5'));
      state.players[0].hand[0] = createCard('hearts', '6'); // Different value
      const handSizeBefore = state.players[0].hand.length;

      const result = GameLogic.matchCard(state, state.players[0], 0);

      assert.strictEqual(result, false);
      // Hand size should increase (failed match = penalty card)
      assert.strictEqual(state.players[0].hand.length, handSizeBefore + 1);
    });

    it('returns false for empty discard pile', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.reaction;
      state.discardPile = [];

      const result = GameLogic.matchCard(state, state.players[0], 0);

      assert.strictEqual(result, false);
    });

    it('returns false for invalid card index', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.reaction;
      state.discardPile.push(createCard('spades', '5'));

      assert.strictEqual(GameLogic.matchCard(state, state.players[0], -1), false);
      assert.strictEqual(GameLogic.matchCard(state, state.players[0], 10), false);
    });
  });

  describe('applyPenalty', () => {
    it('adds a penalty card to player hand', () => {
      const state = createInitializedGameState();
      const player = state.players[0];
      const handSizeBefore = player.hand.length;
      const knownSizeBefore = player.knownCards.length;

      GameLogic.applyPenalty(state, player);

      assert.strictEqual(player.hand.length, handSizeBefore + 1);
      assert.strictEqual(player.knownCards.length, knownSizeBefore + 1);
      assert.strictEqual(player.knownCards[player.knownCards.length - 1], false);
    });

    it('refills deck if empty before applying penalty', () => {
      const state = createInitializedGameState();
      state.deck = [];
      state.discardPile = [
        createCard('hearts', '5'),
        createCard('spades', '6'),
      ];
      const player = state.players[0];
      const handSizeBefore = player.hand.length;

      GameLogic.applyPenalty(state, player);

      assert.strictEqual(player.hand.length, handSizeBefore + 1);
    });
  });

  describe('swapCards', () => {
    it('swaps cards between two players', () => {
      const state = createInitializedGameState();
      const p1 = state.players[0];
      const p2 = state.players[1];
      const card1 = p1.hand[0];
      const card2 = p2.hand[1];

      GameLogic.swapCards(state, p1, 0, p2, 1);

      assert.strictEqual(p1.hand[0], card2);
      assert.strictEqual(p2.hand[1], card1);
    });

    it('resets knownCards for swapped positions', () => {
      const state = createInitializedGameState();
      const p1 = state.players[0];
      const p2 = state.players[1];
      p1.knownCards[0] = true;
      p2.knownCards[1] = true;

      GameLogic.swapCards(state, p1, 0, p2, 1);

      assert.strictEqual(p1.knownCards[0], false);
      assert.strictEqual(p2.knownCards[1], false);
    });

    it('does nothing for invalid indices', () => {
      const state = createInitializedGameState();
      const p1 = state.players[0];
      const p2 = state.players[1];
      const hand1Before = [...p1.hand];
      const hand2Before = [...p2.hand];

      GameLogic.swapCards(state, p1, -1, p2, 0);
      assert.deepStrictEqual(p1.hand, hand1Before);

      GameLogic.swapCards(state, p1, 0, p2, 10);
      assert.deepStrictEqual(p2.hand, hand2Before);
    });
  });

  describe('jokerEffect', () => {
    it('shuffles target player hand', () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 0;
      const target = state.players[1];
      const originalHand = [...target.hand];

      // Note: shuffle might result in same order by chance
      // We mainly test that the operation completes
      GameLogic.jokerEffect(state, target);

      // Hand length should remain the same
      assert.strictEqual(target.hand.length, originalHand.length);
      // All original cards should still be present (just shuffled)
      for (const card of originalHand) {
        assert.ok(target.hand.some(c => c.id === card.id));
      }
    });

    it('resets all knownCards to false', () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 0;
      const target = state.players[1];
      target.knownCards = [true, true, true, true];

      GameLogic.jokerEffect(state, target);

      assert.ok(target.knownCards.every(k => k === false));
    });

    it('adds history entry', () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 0;
      const historyBefore = state.actionHistory.length;

      GameLogic.jokerEffect(state, state.players[1]);

      assert.ok(state.actionHistory.length > historyBefore);
      assert.ok(state.actionHistory.some(h => h.includes('JOKER') || h.includes('mélange')));
    });
  });

  describe('callDutch', () => {
    it('sets dutchCallerId and changes phase', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;

      GameLogic.callDutch(state, 'p1');

      assert.strictEqual(state.dutchCallerId, 'p1');
      // After calling Dutch, game should end immediately per code
      assert.strictEqual(state.phase, GamePhase.ended);
    });

    it('uses current player if no playerId provided', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      state.currentPlayerIndex = 1;

      GameLogic.callDutch(state);

      assert.strictEqual(state.dutchCallerId, 'p2');
    });

    it('does not allow second Dutch call', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      state.dutchCallerId = 'p1';

      GameLogic.callDutch(state, 'p2');

      assert.strictEqual(state.dutchCallerId, 'p1'); // Should not change
    });
  });

  describe('takeFromDiscard', () => {
    it('takes top card from discard as drawn card', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      const topCard = state.discardPile[state.discardPile.length - 1];
      const discardSizeBefore = state.discardPile.length;

      GameLogic.takeFromDiscard(state);

      assert.strictEqual(state.drawnCard, topCard);
      assert.strictEqual(state.discardPile.length, discardSizeBefore - 1);
    });

    it('does nothing if discard pile is empty', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      state.discardPile = [];

      GameLogic.takeFromDiscard(state);

      assert.strictEqual(state.drawnCard, null);
    });
  });

  describe('attemptMatch', () => {
    it('finds player by id and attempts match', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.reaction;
      state.discardPile.push(createCard('hearts', '5'));
      state.players[1].hand[0] = createCard('spades', '5');

      const result = GameLogic.attemptMatch(state, 'p2', 0);

      assert.strictEqual(result, true);
    });

    it('returns false for non-existent player', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.reaction;
      state.discardPile.push(createCard('hearts', '5'));

      const result = GameLogic.attemptMatch(state, 'nonexistent', 0);

      assert.strictEqual(result, false);
    });
  });

  describe('useSpecialPower', () => {
    it('handles card 7 - look at own card', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      state.currentPlayerIndex = 0;
      state.isWaitingForSpecialPower = true;
      state.specialCardToActivate = createCard('hearts', '7');
      state.players[0].knownCards[2] = false;

      const result = GameLogic.useSpecialPower(state, { cardIndex: 2 });

      assert.ok(result.spiedCard);
      assert.strictEqual(state.players[0].knownCards[2], true);
      assert.strictEqual(state.isWaitingForSpecialPower, false);
    });

    it('handles card 10 - spy on opponent', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      state.currentPlayerIndex = 0;
      state.isWaitingForSpecialPower = true;
      state.specialCardToActivate = createCard('spades', '10');

      const result = GameLogic.useSpecialPower(state, {
        targetPlayerIndex: 1,
        targetCardIndex: 0,
      });

      assert.ok(result.spiedCard);
      assert.strictEqual(result.spiedCard, state.players[1].hand[0]);
    });

    it('handles card V (Jack) - swap between any two players', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      state.currentPlayerIndex = 0;
      state.isWaitingForSpecialPower = true;
      state.specialCardToActivate = createCard('clubs', 'V');
      const card1 = state.players[1].hand[0];
      const card2 = state.players[2].hand[1];

      const result = GameLogic.useSpecialPower(state, {
        player1Index: 1,
        card1Index: 0,
        player2Index: 2,
        card2Index: 1,
      });

      assert.strictEqual(state.players[1].hand[0], card2);
      assert.strictEqual(state.players[2].hand[1], card1);
      assert.ok(result.affectedPlayers);
      assert.strictEqual(result.affectedPlayers!.length, 2);
    });

    it('handles JOKER - shuffle target player hand', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      state.currentPlayerIndex = 0;
      state.isWaitingForSpecialPower = true;
      state.specialCardToActivate = createCard('joker', 'JOKER');
      state.players[1].knownCards = [true, true, true, true];

      const result = GameLogic.useSpecialPower(state, { targetPlayerIndex: 1 });

      assert.ok(state.players[1].knownCards.every(k => k === false));
      assert.ok(result.shuffledPlayer);
      assert.strictEqual(result.shuffledPlayer!.playerId, 'p2');
    });

    it('returns empty object if not waiting for special power', () => {
      const state = createInitializedGameState();
      state.isWaitingForSpecialPower = false;

      const result = GameLogic.useSpecialPower(state, { cardIndex: 0 });

      assert.deepStrictEqual(result, {});
    });

    it('starts reaction phase after power use', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      state.currentPlayerIndex = 0;
      state.isWaitingForSpecialPower = true;
      state.specialCardToActivate = createCard('hearts', '7');

      GameLogic.useSpecialPower(state, { cardIndex: 0 });

      assert.strictEqual(state.phase, GamePhase.reaction);
    });
  });

  describe('skipSpecialPower', () => {
    it('clears special power state', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      state.isWaitingForSpecialPower = true;
      state.specialCardToActivate = createCard('hearts', '7');

      GameLogic.skipSpecialPower(state);

      assert.strictEqual(state.isWaitingForSpecialPower, false);
      assert.strictEqual(state.specialCardToActivate, null);
    });

    it('starts reaction phase', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      state.isWaitingForSpecialPower = true;
      state.specialCardToActivate = createCard('hearts', '7');

      GameLogic.skipSpecialPower(state);

      assert.strictEqual(state.phase, GamePhase.reaction);
    });
  });

  describe('endGame', () => {
    it('sets phase to ended', () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;

      GameLogic.endGame(state);

      assert.strictEqual(state.phase, GamePhase.ended);
    });

    it('reveals all cards (sets all knownCards to true)', () => {
      const state = createInitializedGameState();

      GameLogic.endGame(state);

      for (const player of state.players) {
        assert.ok(player.knownCards.every(k => k === true));
      }
    });
  });

  describe('nextPlayer', () => {
    it('advances to next player', () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 0;

      GameLogic.nextPlayer(state);

      assert.strictEqual(state.currentPlayerIndex, 1);
    });
  });
});
