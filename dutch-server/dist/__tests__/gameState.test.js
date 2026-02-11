"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const node_assert_1 = __importDefault(require("node:assert"));
const GameState_1 = require("../models/GameState");
const Player_1 = require("../models/Player");
(0, node_test_1.describe)('GameState', () => {
    function createTestPlayers() {
        return [
            (0, Player_1.createPlayer)('p1', 'Player 1', true, 0),
            (0, Player_1.createPlayer)('p2', 'Player 2', true, 1),
            (0, Player_1.createPlayer)('p3', 'Player 3', false, 2),
        ];
    }
    (0, node_test_1.describe)('createGameState', () => {
        (0, node_test_1.it)('creates a game state with correct initial values', () => {
            const players = createTestPlayers();
            const state = (0, GameState_1.createGameState)(players, GameState_1.GameMode.quick, GameState_1.Difficulty.medium);
            node_assert_1.default.strictEqual(state.players.length, 3);
            node_assert_1.default.deepStrictEqual(state.deck, []);
            node_assert_1.default.deepStrictEqual(state.discardPile, []);
            node_assert_1.default.strictEqual(state.currentPlayerIndex, 0);
            node_assert_1.default.strictEqual(state.gameMode, GameState_1.GameMode.quick);
            node_assert_1.default.strictEqual(state.phase, GameState_1.GamePhase.setup);
            node_assert_1.default.strictEqual(state.difficulty, GameState_1.Difficulty.medium);
            node_assert_1.default.strictEqual(state.tournamentRound, 1);
            node_assert_1.default.deepStrictEqual(state.eliminatedPlayerIds, []);
            node_assert_1.default.strictEqual(state.drawnCard, null);
            node_assert_1.default.strictEqual(state.isWaitingForSpecialPower, false);
            node_assert_1.default.strictEqual(state.specialCardToActivate, null);
            node_assert_1.default.strictEqual(state.dutchCallerId, null);
            node_assert_1.default.strictEqual(state.reactionStartTime, null);
            node_assert_1.default.deepStrictEqual(state.actionHistory, []);
            node_assert_1.default.strictEqual(state.reactionTimeRemaining, 0);
            node_assert_1.default.strictEqual(state.lastSpiedCard, null);
            node_assert_1.default.strictEqual(state.pendingSwap, null);
            node_assert_1.default.deepStrictEqual(state.tournamentCumulativeScores, {});
            node_assert_1.default.strictEqual(state.turnStartTime, null);
            node_assert_1.default.strictEqual(state.turnTimeoutMs, 70000);
            node_assert_1.default.deepStrictEqual(state.readyPlayerIds, []);
        });
        (0, node_test_1.it)('creates tournament mode game state', () => {
            const players = createTestPlayers();
            const state = (0, GameState_1.createGameState)(players, GameState_1.GameMode.tournament, GameState_1.Difficulty.hard);
            node_assert_1.default.strictEqual(state.gameMode, GameState_1.GameMode.tournament);
            node_assert_1.default.strictEqual(state.difficulty, GameState_1.Difficulty.hard);
        });
    });
    (0, node_test_1.describe)('getCurrentPlayer', () => {
        (0, node_test_1.it)('returns the player at currentPlayerIndex', () => {
            const players = createTestPlayers();
            const state = (0, GameState_1.createGameState)(players, GameState_1.GameMode.quick, GameState_1.Difficulty.easy);
            state.currentPlayerIndex = 0;
            node_assert_1.default.strictEqual((0, GameState_1.getCurrentPlayer)(state).id, 'p1');
            state.currentPlayerIndex = 1;
            node_assert_1.default.strictEqual((0, GameState_1.getCurrentPlayer)(state).id, 'p2');
            state.currentPlayerIndex = 2;
            node_assert_1.default.strictEqual((0, GameState_1.getCurrentPlayer)(state).id, 'p3');
        });
    });
    (0, node_test_1.describe)('addToHistory', () => {
        (0, node_test_1.it)('adds an action to the history', () => {
            const players = createTestPlayers();
            const state = (0, GameState_1.createGameState)(players, GameState_1.GameMode.quick, GameState_1.Difficulty.easy);
            (0, GameState_1.addToHistory)(state, 'Player 1 draws a card');
            node_assert_1.default.strictEqual(state.actionHistory.length, 1);
            node_assert_1.default.ok(state.actionHistory[0].includes('Player 1 draws a card'));
        });
        (0, node_test_1.it)('prepends new actions (most recent first)', () => {
            const players = createTestPlayers();
            const state = (0, GameState_1.createGameState)(players, GameState_1.GameMode.quick, GameState_1.Difficulty.easy);
            (0, GameState_1.addToHistory)(state, 'First action');
            (0, GameState_1.addToHistory)(state, 'Second action');
            node_assert_1.default.ok(state.actionHistory[0].includes('Second action'));
            node_assert_1.default.ok(state.actionHistory[1].includes('First action'));
        });
        (0, node_test_1.it)('includes timestamp in history entry', () => {
            const players = createTestPlayers();
            const state = (0, GameState_1.createGameState)(players, GameState_1.GameMode.quick, GameState_1.Difficulty.easy);
            (0, GameState_1.addToHistory)(state, 'Test action');
            // Check format [HH:MM] Action
            node_assert_1.default.ok(state.actionHistory[0].match(/^\[\d+:\d{2}\]/));
        });
        (0, node_test_1.it)('limits history to 50 entries', () => {
            const players = createTestPlayers();
            const state = (0, GameState_1.createGameState)(players, GameState_1.GameMode.quick, GameState_1.Difficulty.easy);
            // Add 60 entries
            for (let i = 0; i < 60; i++) {
                (0, GameState_1.addToHistory)(state, `Action ${i}`);
            }
            node_assert_1.default.strictEqual(state.actionHistory.length, 50);
            // Most recent should be first
            node_assert_1.default.ok(state.actionHistory[0].includes('Action 59'));
        });
    });
    (0, node_test_1.describe)('nextPlayer', () => {
        (0, node_test_1.it)('moves to the next player', () => {
            const players = createTestPlayers();
            const state = (0, GameState_1.createGameState)(players, GameState_1.GameMode.quick, GameState_1.Difficulty.easy);
            state.currentPlayerIndex = 0;
            (0, GameState_1.nextPlayer)(state);
            node_assert_1.default.strictEqual(state.currentPlayerIndex, 1);
            (0, GameState_1.nextPlayer)(state);
            node_assert_1.default.strictEqual(state.currentPlayerIndex, 2);
        });
        (0, node_test_1.it)('wraps around to first player after last', () => {
            const players = createTestPlayers();
            const state = (0, GameState_1.createGameState)(players, GameState_1.GameMode.quick, GameState_1.Difficulty.easy);
            state.currentPlayerIndex = 2;
            (0, GameState_1.nextPlayer)(state);
            node_assert_1.default.strictEqual(state.currentPlayerIndex, 0);
        });
        (0, node_test_1.it)('skips eliminated players', () => {
            const players = createTestPlayers();
            const state = (0, GameState_1.createGameState)(players, GameState_1.GameMode.quick, GameState_1.Difficulty.easy);
            state.currentPlayerIndex = 0;
            state.eliminatedPlayerIds = ['p2'];
            (0, GameState_1.nextPlayer)(state);
            // Should skip p2 and go to p3
            node_assert_1.default.strictEqual(state.currentPlayerIndex, 2);
        });
        (0, node_test_1.it)('skips spectator players', () => {
            const players = createTestPlayers();
            const state = (0, GameState_1.createGameState)(players, GameState_1.GameMode.quick, GameState_1.Difficulty.easy);
            state.currentPlayerIndex = 0;
            state.players[1].isSpectator = true;
            (0, GameState_1.nextPlayer)(state);
            // Should skip p2 (spectator) and go to p3
            node_assert_1.default.strictEqual(state.currentPlayerIndex, 2);
        });
        (0, node_test_1.it)('skips both eliminated and spectator players', () => {
            const players = createTestPlayers();
            const state = (0, GameState_1.createGameState)(players, GameState_1.GameMode.quick, GameState_1.Difficulty.easy);
            state.currentPlayerIndex = 0;
            state.eliminatedPlayerIds = ['p2'];
            state.players[2].isSpectator = true;
            (0, GameState_1.nextPlayer)(state);
            // Should skip p2 and p3, wrap to p1
            node_assert_1.default.strictEqual(state.currentPlayerIndex, 0);
        });
    });
    (0, node_test_1.describe)('GamePhase enum', () => {
        (0, node_test_1.it)('has all expected phases', () => {
            node_assert_1.default.strictEqual(GameState_1.GamePhase.setup, 0);
            node_assert_1.default.strictEqual(GameState_1.GamePhase.playing, 1);
            node_assert_1.default.strictEqual(GameState_1.GamePhase.reaction, 2);
            node_assert_1.default.strictEqual(GameState_1.GamePhase.dutchCalled, 3);
            node_assert_1.default.strictEqual(GameState_1.GamePhase.ended, 4);
        });
    });
    (0, node_test_1.describe)('GameMode enum', () => {
        (0, node_test_1.it)('has quick and tournament modes', () => {
            node_assert_1.default.strictEqual(GameState_1.GameMode.quick, 0);
            node_assert_1.default.strictEqual(GameState_1.GameMode.tournament, 1);
        });
    });
    (0, node_test_1.describe)('Difficulty enum', () => {
        (0, node_test_1.it)('has all difficulty levels', () => {
            node_assert_1.default.strictEqual(GameState_1.Difficulty.easy, 0);
            node_assert_1.default.strictEqual(GameState_1.Difficulty.medium, 1);
            node_assert_1.default.strictEqual(GameState_1.Difficulty.hard, 2);
        });
    });
});
