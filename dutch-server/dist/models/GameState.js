"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.Difficulty = exports.GamePhase = exports.GameMode = void 0;
exports.createGameState = createGameState;
exports.getCurrentPlayer = getCurrentPlayer;
exports.addToHistory = addToHistory;
exports.nextPlayer = nextPlayer;
var GameMode;
(function (GameMode) {
    GameMode[GameMode["quick"] = 0] = "quick";
    GameMode[GameMode["tournament"] = 1] = "tournament";
})(GameMode || (exports.GameMode = GameMode = {}));
var GamePhase;
(function (GamePhase) {
    GamePhase[GamePhase["setup"] = 0] = "setup";
    GamePhase[GamePhase["playing"] = 1] = "playing";
    GamePhase[GamePhase["reaction"] = 2] = "reaction";
    GamePhase[GamePhase["dutchCalled"] = 3] = "dutchCalled";
    GamePhase[GamePhase["ended"] = 4] = "ended";
})(GamePhase || (exports.GamePhase = GamePhase = {}));
var Difficulty;
(function (Difficulty) {
    Difficulty[Difficulty["easy"] = 0] = "easy";
    Difficulty[Difficulty["medium"] = 1] = "medium";
    Difficulty[Difficulty["hard"] = 2] = "hard";
})(Difficulty || (exports.Difficulty = Difficulty = {}));
function createGameState(players, gameMode, difficulty) {
    return {
        players,
        deck: [],
        discardPile: [],
        currentPlayerIndex: 0,
        gameMode,
        phase: GamePhase.setup,
        difficulty,
        tournamentRound: 1,
        eliminatedPlayerIds: [],
        drawnCard: null,
        isWaitingForSpecialPower: false,
        specialCardToActivate: null,
        dutchCallerId: null,
        reactionStartTime: null,
        actionHistory: [],
        reactionTimeRemaining: 0,
        lastSpiedCard: null,
        pendingSwap: null,
        tournamentCumulativeScores: {},
        turnStartTime: null,
        turnTimeoutMs: 20000, // 20 secondes par défaut
    };
}
function getCurrentPlayer(gameState) {
    return gameState.players[gameState.currentPlayerIndex];
}
function addToHistory(gameState, action) {
    const now = new Date();
    const time = `${now.getHours()}:${now.getMinutes().toString().padStart(2, '0')}`;
    gameState.actionHistory.unshift(`[${time}] ${action}`);
    // Limiter à 50 entrées
    if (gameState.actionHistory.length > 50) {
        gameState.actionHistory = gameState.actionHistory.slice(0, 50);
    }
}
function nextPlayer(gameState) {
    for (let i = 0; i < gameState.players.length; i++) {
        gameState.currentPlayerIndex =
            (gameState.currentPlayerIndex + 1) % gameState.players.length;
        const current = getCurrentPlayer(gameState);
        if (!gameState.eliminatedPlayerIds.includes(current.id) &&
            !current.isSpectator) {
            break;
        }
    }
}
