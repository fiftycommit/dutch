import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  createGameState,
  getCurrentPlayer,
  addToHistory,
  nextPlayer,
  GameMode,
  GamePhase,
  Difficulty,
  GameState,
} from '../models/GameState';
import { createPlayer, Player } from '../models/Player';

describe('GameState', () => {
  function createTestPlayers(): Player[] {
    return [
      createPlayer('p1', 'Player 1', true, 0),
      createPlayer('p2', 'Player 2', true, 1),
      createPlayer('p3', 'Player 3', false, 2),
    ];
  }

  describe('createGameState', () => {
    it('creates a game state with correct initial values', () => {
      const players = createTestPlayers();
      const state = createGameState(players, GameMode.quick, Difficulty.medium);

      assert.strictEqual(state.players.length, 3);
      assert.deepStrictEqual(state.deck, []);
      assert.deepStrictEqual(state.discardPile, []);
      assert.strictEqual(state.currentPlayerIndex, 0);
      assert.strictEqual(state.gameMode, GameMode.quick);
      assert.strictEqual(state.phase, GamePhase.setup);
      assert.strictEqual(state.difficulty, Difficulty.medium);
      assert.strictEqual(state.tournamentRound, 1);
      assert.deepStrictEqual(state.eliminatedPlayerIds, []);
      assert.strictEqual(state.drawnCard, null);
      assert.strictEqual(state.isWaitingForSpecialPower, false);
      assert.strictEqual(state.specialCardToActivate, null);
      assert.strictEqual(state.dutchCallerId, null);
      assert.strictEqual(state.reactionStartTime, null);
      assert.deepStrictEqual(state.actionHistory, []);
      assert.strictEqual(state.reactionTimeRemaining, 0);
      assert.strictEqual(state.lastSpiedCard, null);
      assert.strictEqual(state.pendingSwap, null);
      assert.deepStrictEqual(state.tournamentCumulativeScores, {});
      assert.strictEqual(state.turnStartTime, null);
      assert.strictEqual(state.turnTimeoutMs, 90000);
      assert.deepStrictEqual(state.readyPlayerIds, []);
    });

    it('creates tournament mode game state', () => {
      const players = createTestPlayers();
      const state = createGameState(players, GameMode.tournament, Difficulty.hard);

      assert.strictEqual(state.gameMode, GameMode.tournament);
      assert.strictEqual(state.difficulty, Difficulty.hard);
    });
  });

  describe('getCurrentPlayer', () => {
    it('returns the player at currentPlayerIndex', () => {
      const players = createTestPlayers();
      const state = createGameState(players, GameMode.quick, Difficulty.easy);

      state.currentPlayerIndex = 0;
      assert.strictEqual(getCurrentPlayer(state).id, 'p1');

      state.currentPlayerIndex = 1;
      assert.strictEqual(getCurrentPlayer(state).id, 'p2');

      state.currentPlayerIndex = 2;
      assert.strictEqual(getCurrentPlayer(state).id, 'p3');
    });
  });

  describe('addToHistory', () => {
    it('adds an action to the history', () => {
      const players = createTestPlayers();
      const state = createGameState(players, GameMode.quick, Difficulty.easy);

      addToHistory(state, 'Player 1 draws a card');

      assert.strictEqual(state.actionHistory.length, 1);
      assert.ok(state.actionHistory[0].includes('Player 1 draws a card'));
    });

    it('prepends new actions (most recent first)', () => {
      const players = createTestPlayers();
      const state = createGameState(players, GameMode.quick, Difficulty.easy);

      addToHistory(state, 'First action');
      addToHistory(state, 'Second action');

      assert.ok(state.actionHistory[0].includes('Second action'));
      assert.ok(state.actionHistory[1].includes('First action'));
    });

    it('includes timestamp in history entry', () => {
      const players = createTestPlayers();
      const state = createGameState(players, GameMode.quick, Difficulty.easy);

      addToHistory(state, 'Test action');

      // Check format [HH:MM] Action
      assert.ok(state.actionHistory[0].match(/^\[\d+:\d{2}\]/));
    });

    it('limits history to 50 entries', () => {
      const players = createTestPlayers();
      const state = createGameState(players, GameMode.quick, Difficulty.easy);

      // Add 60 entries
      for (let i = 0; i < 60; i++) {
        addToHistory(state, `Action ${i}`);
      }

      assert.strictEqual(state.actionHistory.length, 50);
      // Most recent should be first
      assert.ok(state.actionHistory[0].includes('Action 59'));
    });
  });

  describe('nextPlayer', () => {
    it('moves to the next player', () => {
      const players = createTestPlayers();
      const state = createGameState(players, GameMode.quick, Difficulty.easy);
      state.currentPlayerIndex = 0;

      nextPlayer(state);
      assert.strictEqual(state.currentPlayerIndex, 1);

      nextPlayer(state);
      assert.strictEqual(state.currentPlayerIndex, 2);
    });

    it('wraps around to first player after last', () => {
      const players = createTestPlayers();
      const state = createGameState(players, GameMode.quick, Difficulty.easy);
      state.currentPlayerIndex = 2;

      nextPlayer(state);
      assert.strictEqual(state.currentPlayerIndex, 0);
    });

    it('skips eliminated players', () => {
      const players = createTestPlayers();
      const state = createGameState(players, GameMode.quick, Difficulty.easy);
      state.currentPlayerIndex = 0;
      state.eliminatedPlayerIds = ['p2'];

      nextPlayer(state);
      // Should skip p2 and go to p3
      assert.strictEqual(state.currentPlayerIndex, 2);
    });

    it('skips spectator players', () => {
      const players = createTestPlayers();
      const state = createGameState(players, GameMode.quick, Difficulty.easy);
      state.currentPlayerIndex = 0;
      state.players[1].isSpectator = true;

      nextPlayer(state);
      // Should skip p2 (spectator) and go to p3
      assert.strictEqual(state.currentPlayerIndex, 2);
    });

    it('skips both eliminated and spectator players', () => {
      const players = createTestPlayers();
      const state = createGameState(players, GameMode.quick, Difficulty.easy);
      state.currentPlayerIndex = 0;
      state.eliminatedPlayerIds = ['p2'];
      state.players[2].isSpectator = true;

      nextPlayer(state);
      // Should skip p2 and p3, wrap to p1
      assert.strictEqual(state.currentPlayerIndex, 0);
    });
  });

  describe('GamePhase enum', () => {
    it('has all expected phases', () => {
      assert.strictEqual(GamePhase.setup, 0);
      assert.strictEqual(GamePhase.playing, 1);
      assert.strictEqual(GamePhase.specialPower, 2);
      assert.strictEqual(GamePhase.reaction, 3);
      assert.strictEqual(GamePhase.dutchCalled, 4);
      assert.strictEqual(GamePhase.ended, 5);
    });
  });

  describe('GameMode enum', () => {
    it('has quick and tournament modes', () => {
      assert.strictEqual(GameMode.quick, 0);
      assert.strictEqual(GameMode.tournament, 1);
    });
  });

  describe('Difficulty enum', () => {
    it('has all difficulty levels', () => {
      assert.strictEqual(Difficulty.easy, 0);
      assert.strictEqual(Difficulty.medium, 1);
      assert.strictEqual(Difficulty.hard, 2);
    });
  });
});
