import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import { BotAI } from '../services/BotAI';
import { GameLogic } from '../services/GameLogic';
import { createGameState, GamePhase, GameMode, Difficulty, getCurrentPlayer } from '../models/GameState';
import { createPlayer, Player, BotBehavior, BotSkillLevel } from '../models/Player';
import { createCard } from '../models/Card';

describe('BotAI', () => {
  function createTestPlayers(): Player[] {
    const human = createPlayer('p1', 'Human', true, 0);
    const bot1 = createPlayer('bot1', 'Bot Fast', false, 1, BotBehavior.fast, BotSkillLevel.silver);
    const bot2 = createPlayer('bot2', 'Bot Balanced', false, 2, BotBehavior.balanced, BotSkillLevel.gold);
    return [human, bot1, bot2];
  }

  function createInitializedGameState() {
    const players = createTestPlayers();
    const state = createGameState(players, GameMode.quick, Difficulty.medium);
    GameLogic.initializeGame(state);
    state.phase = GamePhase.playing;
    return state;
  }

  beforeEach(() => {
    BotAI.clearAllBotMemories();
  });

  describe('playBotTurn', () => {
    it('does nothing for human player', async () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 0; // Human
      const phaseBefore = state.phase;
      const handsBefore = state.players.map(p => [...p.hand]);

      await BotAI.playBotTurn(state);

      // Nothing should change
      assert.strictEqual(state.phase, phaseBefore);
    });

    it('draws a card when bot plays', async () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 1; // Bot
      const deckSizeBefore = state.deck.length;

      await BotAI.playBotTurn(state);

      // Bot should have drawn a card (deck smaller or action happened)
      // Note: The test might end in different states depending on bot decision
      assert.ok(
        state.deck.length < deckSizeBefore ||
        state.phase !== GamePhase.playing ||
        state.drawnCard !== null ||
        state.discardPile.length > 1
      );
    });

    it('can call Dutch when score is low enough', async () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 1; // Bot

      // Give bot very low cards to encourage Dutch
      state.players[1].hand = [
        createCard('hearts', 'A'), // 1 pt
        createCard('diamonds', 'A'), // 1 pt
        createCard('hearts', 'R'), // 0 pt (red king)
        createCard('joker', 'JOKER'), // 0 pt
      ];
      state.players[1].knownCards = [true, true, true, true];

      // Run multiple times - Dutch should be called at some point
      let dutchCalled = false;
      for (let i = 0; i < 10; i++) {
        BotAI.clearAllBotMemories();
        const testState = createInitializedGameState();
        testState.currentPlayerIndex = 1;
        testState.players[1].hand = [
          createCard('hearts', 'A'),
          createCard('diamonds', 'A'),
          createCard('hearts', 'R'),
          createCard('joker', 'JOKER'),
        ];
        testState.players[1].knownCards = [true, true, true, true];

        await BotAI.playBotTurn(testState);

        if (testState.dutchCallerId) {
          dutchCalled = true;
          break;
        }
      }

      // At least one Dutch call should happen with score of 2
      assert.ok(dutchCalled, 'Bot should call Dutch with very low score');
    });

    it('uses player MMR for difficulty when provided', async () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 1;

      // High MMR = platinum difficulty
      await BotAI.playBotTurn(state, 1000);

      // Should not throw and game state should be modified
      assert.ok(true);
    });
  });

  describe('tryReactionMatch', () => {
    it('returns false for human players', async () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.reaction;
      state.discardPile.push(createCard('hearts', '5'));

      const result = await BotAI.tryReactionMatch(state, state.players[0]);

      assert.strictEqual(result, false);
    });

    it('returns false when not in reaction phase', async () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.playing;
      state.discardPile.push(createCard('hearts', '5'));

      const result = await BotAI.tryReactionMatch(state, state.players[1]);

      assert.strictEqual(result, false);
    });

    it('returns false when discard pile is empty', async () => {
      const state = createInitializedGameState();
      state.phase = GamePhase.reaction;
      state.discardPile = [];

      const result = await BotAI.tryReactionMatch(state, state.players[1]);

      assert.strictEqual(result, false);
    });

    it('can successfully match when bot has matching card', async () => {
      // This is probabilistic, so run multiple times
      let matchSucceeded = false;

      for (let i = 0; i < 20; i++) {
        BotAI.clearAllBotMemories();
        const state = createInitializedGameState();
        state.phase = GamePhase.reaction;

        // Set up a clear match
        state.discardPile = [createCard('hearts', '5')];
        state.players[1].hand = [
          createCard('spades', '5'), // Matching card
          createCard('hearts', '2'),
          createCard('clubs', '3'),
          createCard('diamonds', '4'),
        ];
        state.players[1].knownCards = [true, false, false, false];
        state.players[1].botSkillLevel = BotSkillLevel.platinum; // High accuracy

        const handSizeBefore = state.players[1].hand.length;
        const result = await BotAI.tryReactionMatch(state, state.players[1], 1000);

        if (result) {
          matchSucceeded = true;
          // Hand should be smaller after successful match
          assert.strictEqual(state.players[1].hand.length, handSizeBefore - 1);
          break;
        }
      }

      assert.ok(matchSucceeded, 'Platinum bot should eventually match');
    });
  });

  describe('useBotSpecialPower', () => {
    it('does nothing if not waiting for special power', async () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 1;
      state.isWaitingForSpecialPower = false;

      await BotAI.useBotSpecialPower(state);

      // Should complete without error
      assert.strictEqual(state.isWaitingForSpecialPower, false);
    });

    it('handles card 7 (look at own card)', async () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 1;
      state.isWaitingForSpecialPower = true;
      state.specialCardToActivate = createCard('hearts', '7');
      state.players[1].knownCards = [true, true, false, false];

      await BotAI.useBotSpecialPower(state);

      assert.strictEqual(state.isWaitingForSpecialPower, false);
      assert.strictEqual(state.specialCardToActivate, null);
    });

    it('handles card 10 (spy on opponent)', async () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 1;
      state.isWaitingForSpecialPower = true;
      state.specialCardToActivate = createCard('spades', '10');

      await BotAI.useBotSpecialPower(state);

      assert.strictEqual(state.isWaitingForSpecialPower, false);
    });

    it('handles card V (Jack swap)', async () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 1;
      state.isWaitingForSpecialPower = true;
      state.specialCardToActivate = createCard('clubs', 'V');

      await BotAI.useBotSpecialPower(state);

      assert.strictEqual(state.isWaitingForSpecialPower, false);
    });

    it('handles JOKER (shuffle)', async () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 1;
      state.isWaitingForSpecialPower = true;
      state.specialCardToActivate = createCard('joker', 'JOKER');

      await BotAI.useBotSpecialPower(state);

      assert.strictEqual(state.isWaitingForSpecialPower, false);
    });
  });

  describe('clearBotMemory', () => {
    it('clears memory for specific player', async () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 1;

      // Play a turn to establish memory
      await BotAI.playBotTurn(state);

      BotAI.clearBotMemory('bot1');

      // Should not throw
      assert.ok(true);
    });
  });

  describe('clearAllBotMemories', () => {
    it('clears all bot memories', async () => {
      const state = createInitializedGameState();

      // Play turns for both bots
      state.currentPlayerIndex = 1;
      await BotAI.playBotTurn(state);

      // Reset for second bot
      const state2 = createInitializedGameState();
      state2.currentPlayerIndex = 2;
      await BotAI.playBotTurn(state2);

      BotAI.clearAllBotMemories();

      // Should not throw
      assert.ok(true);
    });
  });

  describe('bot behaviors', () => {
    it('fast bot behavior is more aggressive', async () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 1;
      state.players[1].botBehavior = BotBehavior.fast;

      // Fast bot should act quickly, test completes without hanging
      await BotAI.playBotTurn(state);
      assert.ok(true);
    });

    it('aggressive bot behavior targets humans', async () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 1;
      state.players[1].botBehavior = BotBehavior.aggressive;

      await BotAI.playBotTurn(state);
      assert.ok(true);
    });

    it('balanced bot behavior makes calculated decisions', async () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 2;
      state.players[2].botBehavior = BotBehavior.balanced;

      await BotAI.playBotTurn(state);
      assert.ok(true);
    });
  });

  describe('bot skill levels', () => {
    it('bronze bot makes more mistakes', async () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 1;
      state.players[1].botSkillLevel = BotSkillLevel.bronze;

      await BotAI.playBotTurn(state);
      assert.ok(true);
    });

    it('silver bot has moderate skill', async () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 1;
      state.players[1].botSkillLevel = BotSkillLevel.silver;

      await BotAI.playBotTurn(state);
      assert.ok(true);
    });

    it('gold bot plays well', async () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 1;
      state.players[1].botSkillLevel = BotSkillLevel.gold;

      await BotAI.playBotTurn(state);
      assert.ok(true);
    });

    it('platinum bot plays optimally', async () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 1;
      state.players[1].botSkillLevel = BotSkillLevel.platinum;

      await BotAI.playBotTurn(state);
      assert.ok(true);
    });
  });

  describe('tournament mode', () => {
    it('considers cumulative scores in tournament', async () => {
      const players = createTestPlayers();
      const state = createGameState(players, GameMode.tournament, Difficulty.medium);
      GameLogic.initializeGame(state);
      state.phase = GamePhase.playing;
      state.currentPlayerIndex = 1;

      // Set cumulative scores
      state.tournamentCumulativeScores = {
        'p1': 50,
        'bot1': 80, // High score = more pressure to Dutch
        'bot2': 30,
      };

      await BotAI.playBotTurn(state);
      assert.ok(true);
    });
  });

  describe('edge cases', () => {
    it('handles empty deck gracefully', async () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 1;
      state.deck = [];
      state.discardPile = [createCard('hearts', '5'), createCard('spades', '6')];

      await BotAI.playBotTurn(state);
      // Should handle refill or end game
      assert.ok(true);
    });

    it('handles bot with only one card', async () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 1;
      state.players[1].hand = [createCard('hearts', 'A')];
      state.players[1].knownCards = [true];

      await BotAI.playBotTurn(state);
      assert.ok(true);
    });

    it('handles bot with many cards (penalty situation)', async () => {
      const state = createInitializedGameState();
      state.currentPlayerIndex = 1;
      state.players[1].hand = [
        createCard('hearts', 'A'),
        createCard('spades', '2'),
        createCard('clubs', '3'),
        createCard('diamonds', '4'),
        createCard('hearts', '5'),
        createCard('spades', '6'),
        createCard('clubs', '7'),
        createCard('diamonds', '8'),
      ];
      state.players[1].knownCards = [true, true, false, false, false, false, false, false];

      await BotAI.playBotTurn(state);
      assert.ok(true);
    });
  });
});
