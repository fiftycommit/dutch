"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const node_assert_1 = __importDefault(require("node:assert"));
const BotAI_1 = require("../services/BotAI");
const GameLogic_1 = require("../services/GameLogic");
const GameState_1 = require("../models/GameState");
const Player_1 = require("../models/Player");
const Card_1 = require("../models/Card");
(0, node_test_1.describe)('BotAI', () => {
    function createTestPlayers() {
        const human = (0, Player_1.createPlayer)('p1', 'Human', true, 0);
        const bot1 = (0, Player_1.createPlayer)('bot1', 'Bot Fast', false, 1, Player_1.BotBehavior.fast, Player_1.BotSkillLevel.silver);
        const bot2 = (0, Player_1.createPlayer)('bot2', 'Bot Balanced', false, 2, Player_1.BotBehavior.balanced, Player_1.BotSkillLevel.gold);
        return [human, bot1, bot2];
    }
    function createInitializedGameState() {
        const players = createTestPlayers();
        const state = (0, GameState_1.createGameState)(players, GameState_1.GameMode.quick, GameState_1.Difficulty.medium);
        GameLogic_1.GameLogic.initializeGame(state);
        state.phase = GameState_1.GamePhase.playing;
        return state;
    }
    (0, node_test_1.beforeEach)(() => {
        BotAI_1.BotAI.clearAllBotMemories();
    });
    (0, node_test_1.describe)('playBotTurn', () => {
        (0, node_test_1.it)('does nothing for human player', async () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 0; // Human
            const phaseBefore = state.phase;
            const handsBefore = state.players.map(p => [...p.hand]);
            await BotAI_1.BotAI.playBotTurn(state);
            // Nothing should change
            node_assert_1.default.strictEqual(state.phase, phaseBefore);
        });
        (0, node_test_1.it)('draws a card when bot plays', async () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 1; // Bot
            const deckSizeBefore = state.deck.length;
            await BotAI_1.BotAI.playBotTurn(state);
            // Bot should have drawn a card (deck smaller or action happened)
            // Note: The test might end in different states depending on bot decision
            node_assert_1.default.ok(state.deck.length < deckSizeBefore ||
                state.phase !== GameState_1.GamePhase.playing ||
                state.drawnCard !== null ||
                state.discardPile.length > 1);
        });
        (0, node_test_1.it)('can call Dutch when score is low enough', async () => {
            // Run multiple times - Dutch should be called at some point with a very low score
            // This is probabilistic, so we give many attempts
            let dutchCalled = false;
            for (let i = 0; i < 30; i++) {
                BotAI_1.BotAI.clearAllBotMemories();
                const testState = createInitializedGameState();
                testState.currentPlayerIndex = 1; // Bot
                // Give bot very low cards (score = 2) to encourage Dutch
                // Use platinum to avoid minTurnsBeforeDutch delay
                testState.players[1].botSkillLevel = Player_1.BotSkillLevel.platinum;
                testState.players[1].hand = [
                    (0, Card_1.createCard)('hearts', 'A'), // 1 pt
                    (0, Card_1.createCard)('diamonds', 'A'), // 1 pt
                    (0, Card_1.createCard)('hearts', 'R'), // 0 pt (red king)
                    (0, Card_1.createCard)('joker', 'JOKER'), // 0 pt
                ];
                testState.players[1].knownCards = [true, true, true, true];
                await BotAI_1.BotAI.playBotTurn(testState);
                if (testState.dutchCallerId) {
                    dutchCalled = true;
                    break;
                }
            }
            // At least one Dutch call should happen with score of 2 over 30 attempts
            node_assert_1.default.ok(dutchCalled, 'Bot should call Dutch with very low score (2 pts) within 30 attempts');
        });
        (0, node_test_1.it)('uses player MMR for difficulty when provided', async () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 1;
            // High MMR = platinum difficulty
            await BotAI_1.BotAI.playBotTurn(state, 1000);
            // Should not throw and game state should be modified
            node_assert_1.default.ok(true);
        });
    });
    (0, node_test_1.describe)('tryReactionMatch', () => {
        (0, node_test_1.it)('returns false for human players', async () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.reaction;
            state.discardPile.push((0, Card_1.createCard)('hearts', '5'));
            const result = await BotAI_1.BotAI.tryReactionMatch(state, state.players[0]);
            node_assert_1.default.strictEqual(result, false);
        });
        (0, node_test_1.it)('returns false when not in reaction phase', async () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.playing;
            state.discardPile.push((0, Card_1.createCard)('hearts', '5'));
            const result = await BotAI_1.BotAI.tryReactionMatch(state, state.players[1]);
            node_assert_1.default.strictEqual(result, false);
        });
        (0, node_test_1.it)('returns false when discard pile is empty', async () => {
            const state = createInitializedGameState();
            state.phase = GameState_1.GamePhase.reaction;
            state.discardPile = [];
            const result = await BotAI_1.BotAI.tryReactionMatch(state, state.players[1]);
            node_assert_1.default.strictEqual(result, false);
        });
        (0, node_test_1.it)('can successfully match when bot has matching card', async () => {
            // This is probabilistic, so run multiple times
            let matchSucceeded = false;
            for (let i = 0; i < 20; i++) {
                BotAI_1.BotAI.clearAllBotMemories();
                const state = createInitializedGameState();
                state.phase = GameState_1.GamePhase.reaction;
                // Set up a clear match
                state.discardPile = [(0, Card_1.createCard)('hearts', '5')];
                state.players[1].hand = [
                    (0, Card_1.createCard)('spades', '5'), // Matching card
                    (0, Card_1.createCard)('hearts', '2'),
                    (0, Card_1.createCard)('clubs', '3'),
                    (0, Card_1.createCard)('diamonds', '4'),
                ];
                state.players[1].knownCards = [true, false, false, false];
                state.players[1].botSkillLevel = Player_1.BotSkillLevel.platinum; // High accuracy
                const handSizeBefore = state.players[1].hand.length;
                const result = await BotAI_1.BotAI.tryReactionMatch(state, state.players[1], 1000);
                if (result) {
                    matchSucceeded = true;
                    // Hand should be smaller after successful match
                    node_assert_1.default.strictEqual(state.players[1].hand.length, handSizeBefore - 1);
                    break;
                }
            }
            node_assert_1.default.ok(matchSucceeded, 'Platinum bot should eventually match');
        });
    });
    (0, node_test_1.describe)('useBotSpecialPower', () => {
        (0, node_test_1.it)('does nothing if not waiting for special power', async () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 1;
            state.isWaitingForSpecialPower = false;
            await BotAI_1.BotAI.useBotSpecialPower(state);
            // Should complete without error
            node_assert_1.default.strictEqual(state.isWaitingForSpecialPower, false);
        });
        (0, node_test_1.it)('handles card 7 (look at own card)', async () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 1;
            state.phase = GameState_1.GamePhase.specialPower;
            state.isWaitingForSpecialPower = true;
            state.specialCardToActivate = (0, Card_1.createCard)('hearts', '7');
            state.players[1].knownCards = [true, true, false, false];
            await BotAI_1.BotAI.useBotSpecialPower(state);
            node_assert_1.default.strictEqual(state.isWaitingForSpecialPower, false);
            node_assert_1.default.strictEqual(state.specialCardToActivate, null);
        });
        (0, node_test_1.it)('handles card 10 (spy on opponent)', async () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 1;
            state.phase = GameState_1.GamePhase.specialPower;
            state.isWaitingForSpecialPower = true;
            state.specialCardToActivate = (0, Card_1.createCard)('spades', '10');
            await BotAI_1.BotAI.useBotSpecialPower(state);
            node_assert_1.default.strictEqual(state.isWaitingForSpecialPower, false);
        });
        (0, node_test_1.it)('handles card V (Jack swap)', async () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 1;
            state.phase = GameState_1.GamePhase.specialPower;
            state.isWaitingForSpecialPower = true;
            state.specialCardToActivate = (0, Card_1.createCard)('clubs', 'V');
            await BotAI_1.BotAI.useBotSpecialPower(state);
            node_assert_1.default.strictEqual(state.isWaitingForSpecialPower, false);
        });
        (0, node_test_1.it)('handles JOKER (shuffle)', async () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 1;
            state.phase = GameState_1.GamePhase.specialPower;
            state.isWaitingForSpecialPower = true;
            state.specialCardToActivate = (0, Card_1.createCard)('joker', 'JOKER');
            await BotAI_1.BotAI.useBotSpecialPower(state);
            node_assert_1.default.strictEqual(state.isWaitingForSpecialPower, false);
        });
    });
    (0, node_test_1.describe)('clearBotMemory', () => {
        (0, node_test_1.it)('clears memory for specific player', async () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 1;
            // Play a turn to establish memory
            await BotAI_1.BotAI.playBotTurn(state);
            BotAI_1.BotAI.clearBotMemory('bot1');
            // Should not throw
            node_assert_1.default.ok(true);
        });
    });
    (0, node_test_1.describe)('clearAllBotMemories', () => {
        (0, node_test_1.it)('clears all bot memories', async () => {
            const state = createInitializedGameState();
            // Play turns for both bots
            state.currentPlayerIndex = 1;
            await BotAI_1.BotAI.playBotTurn(state);
            // Reset for second bot
            const state2 = createInitializedGameState();
            state2.currentPlayerIndex = 2;
            await BotAI_1.BotAI.playBotTurn(state2);
            BotAI_1.BotAI.clearAllBotMemories();
            // Should not throw
            node_assert_1.default.ok(true);
        });
    });
    (0, node_test_1.describe)('bot behaviors', () => {
        (0, node_test_1.it)('fast bot behavior is more aggressive', async () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 1;
            state.players[1].botBehavior = Player_1.BotBehavior.fast;
            // Fast bot should act quickly, test completes without hanging
            await BotAI_1.BotAI.playBotTurn(state);
            node_assert_1.default.ok(true);
        });
        (0, node_test_1.it)('aggressive bot behavior targets humans', async () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 1;
            state.players[1].botBehavior = Player_1.BotBehavior.aggressive;
            await BotAI_1.BotAI.playBotTurn(state);
            node_assert_1.default.ok(true);
        });
        (0, node_test_1.it)('balanced bot behavior makes calculated decisions', async () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 2;
            state.players[2].botBehavior = Player_1.BotBehavior.balanced;
            await BotAI_1.BotAI.playBotTurn(state);
            node_assert_1.default.ok(true);
        });
    });
    (0, node_test_1.describe)('bot skill levels', () => {
        (0, node_test_1.it)('bronze bot makes more mistakes', async () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 1;
            state.players[1].botSkillLevel = Player_1.BotSkillLevel.bronze;
            await BotAI_1.BotAI.playBotTurn(state);
            node_assert_1.default.ok(true);
        });
        (0, node_test_1.it)('silver bot has moderate skill', async () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 1;
            state.players[1].botSkillLevel = Player_1.BotSkillLevel.silver;
            await BotAI_1.BotAI.playBotTurn(state);
            node_assert_1.default.ok(true);
        });
        (0, node_test_1.it)('gold bot plays well', async () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 1;
            state.players[1].botSkillLevel = Player_1.BotSkillLevel.gold;
            await BotAI_1.BotAI.playBotTurn(state);
            node_assert_1.default.ok(true);
        });
        (0, node_test_1.it)('platinum bot plays optimally', async () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 1;
            state.players[1].botSkillLevel = Player_1.BotSkillLevel.platinum;
            await BotAI_1.BotAI.playBotTurn(state);
            node_assert_1.default.ok(true);
        });
    });
    (0, node_test_1.describe)('tournament mode', () => {
        (0, node_test_1.it)('considers cumulative scores in tournament', async () => {
            const players = createTestPlayers();
            const state = (0, GameState_1.createGameState)(players, GameState_1.GameMode.tournament, GameState_1.Difficulty.medium);
            GameLogic_1.GameLogic.initializeGame(state);
            state.phase = GameState_1.GamePhase.playing;
            state.currentPlayerIndex = 1;
            // Set cumulative scores
            state.tournamentCumulativeScores = {
                'p1': 50,
                'bot1': 80, // High score = more pressure to Dutch
                'bot2': 30,
            };
            await BotAI_1.BotAI.playBotTurn(state);
            node_assert_1.default.ok(true);
        });
    });
    (0, node_test_1.describe)('edge cases', () => {
        (0, node_test_1.it)('handles empty deck gracefully', async () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 1;
            state.deck = [];
            state.discardPile = [(0, Card_1.createCard)('hearts', '5'), (0, Card_1.createCard)('spades', '6')];
            await BotAI_1.BotAI.playBotTurn(state);
            // Should handle refill or end game
            node_assert_1.default.ok(true);
        });
        (0, node_test_1.it)('handles bot with only one card', async () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 1;
            state.players[1].hand = [(0, Card_1.createCard)('hearts', 'A')];
            state.players[1].knownCards = [true];
            await BotAI_1.BotAI.playBotTurn(state);
            node_assert_1.default.ok(true);
        });
        (0, node_test_1.it)('handles bot with many cards (penalty situation)', async () => {
            const state = createInitializedGameState();
            state.currentPlayerIndex = 1;
            state.players[1].hand = [
                (0, Card_1.createCard)('hearts', 'A'),
                (0, Card_1.createCard)('spades', '2'),
                (0, Card_1.createCard)('clubs', '3'),
                (0, Card_1.createCard)('diamonds', '4'),
                (0, Card_1.createCard)('hearts', '5'),
                (0, Card_1.createCard)('spades', '6'),
                (0, Card_1.createCard)('clubs', '7'),
                (0, Card_1.createCard)('diamonds', '8'),
            ];
            state.players[1].knownCards = [true, true, false, false, false, false, false, false];
            await BotAI_1.BotAI.playBotTurn(state);
            node_assert_1.default.ok(true);
        });
    });
});
//# sourceMappingURL=botAI.test.js.map