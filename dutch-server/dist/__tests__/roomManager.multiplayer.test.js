"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = __importDefault(require("node:test"));
const strict_1 = __importDefault(require("node:assert/strict"));
const RoomManager_1 = require("../services/RoomManager");
const GameState_1 = require("../models/GameState");
class FakeServer {
    constructor() {
        this.events = [];
        this.currentTarget = '';
    }
    to(target) {
        this.currentTarget = target;
        return this;
    }
    emit(event, data) {
        this.events.push({ target: this.currentTarget, event, data });
        return true;
    }
    findEventsFor(target, event) {
        return this.events.filter((e) => e.target === target && e.event === event);
    }
}
function createManager(options = {}) {
    const io = new FakeServer();
    const manager = new RoomManager_1.RoomManager(io, {
        cleanupIntervalMs: 10000,
        roomTtlMs: 60000,
        ...options,
    });
    return { io, manager };
}
(0, node_test_1.default)('startGame enforces minPlayers and respects fillBots=false', (t) => {
    const { manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-1', {
        minPlayers: 3,
        maxPlayers: 4,
        fillBots: false,
    });
    manager.joinRoom(room.id, 'p2', 'P2', 'c2');
    const startedTooEarly = manager.startGame(room.id);
    strict_1.default.equal(startedTooEarly, false);
    strict_1.default.equal(room.status, 'waiting');
    strict_1.default.equal(room.gameState, null);
    manager.joinRoom(room.id, 'p3', 'P3', 'c3');
    manager.setReady(room.id, 'host-1', true);
    manager.setReady(room.id, 'p2', true);
    manager.setReady(room.id, 'p3', true);
    const started = manager.startGame(room.id, { fillBots: false });
    strict_1.default.equal(started, true);
    strict_1.default.ok(room.gameState);
    const humanCount = room.players.filter((p) => p.isHuman).length;
    strict_1.default.equal(humanCount, 3);
    strict_1.default.equal(room.players.length, 3);
});
(0, node_test_1.default)('startGame fills bots up to maxPlayers when fillBots=true', (t) => {
    const { manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-2', {
        minPlayers: 2,
        maxPlayers: 4,
        fillBots: true,
    });
    manager.joinRoom(room.id, 'p2', 'P2', 'c2');
    manager.setReady(room.id, 'host-2', true);
    manager.setReady(room.id, 'p2', true);
    const started = manager.startGame(room.id, { fillBots: true });
    strict_1.default.equal(started, true);
    strict_1.default.ok(room.gameState);
    const humanCount = room.players.filter((p) => p.isHuman).length;
    strict_1.default.equal(humanCount, 2);
    strict_1.default.equal(room.players.length, 4);
});
(0, node_test_1.default)('turn timeout triggers presence check then spectator', async (t) => {
    const { io, manager } = createManager({
        turnTimeoutMs: 40,
        presenceGraceMs: 40,
        cleanupIntervalMs: 10000,
        roomTtlMs: 60000,
    });
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-3', {
        minPlayers: 2,
        maxPlayers: 2,
        fillBots: false,
    });
    manager.joinRoom(room.id, 'p2', 'P2', 'c2');
    manager.setReady(room.id, 'host-3', true);
    manager.setReady(room.id, 'p2', true);
    const started = manager.startGame(room.id, { fillBots: false });
    strict_1.default.equal(started, true);
    strict_1.default.ok(room.gameState);
    const currentPlayerId = (0, GameState_1.getCurrentPlayer)(room.gameState).id;
    const otherPlayerId = room.players.find((p) => p.id !== currentPlayerId).id;
    await new Promise((resolve) => setTimeout(resolve, 70));
    const checkEvents = io.findEventsFor(currentPlayerId, 'presence:check');
    strict_1.default.ok(checkEvents.length >= 1);
    await new Promise((resolve) => setTimeout(resolve, 80));
    const timedOutPlayer = room.players.find((p) => p.id === currentPlayerId);
    strict_1.default.equal(timedOutPlayer.isSpectator, true);
    strict_1.default.notEqual((0, GameState_1.getCurrentPlayer)(room.gameState).id, currentPlayerId);
    strict_1.default.equal((0, GameState_1.getCurrentPlayer)(room.gameState).id, otherPlayerId);
});
(0, node_test_1.default)('cleanup removes room on TTL expiration', async (t) => {
    const { manager } = createManager({
        roomTtlMs: 50,
        cleanupIntervalMs: 20,
    });
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-4', {
        minPlayers: 2,
        maxPlayers: 4,
        fillBots: true,
    });
    await new Promise((resolve) => setTimeout(resolve, 120));
    strict_1.default.equal(manager.getRoom(room.id), undefined);
});
(0, node_test_1.default)('cleanup removes room when all humans disconnect', async (t) => {
    const { manager } = createManager({
        roomTtlMs: 60000,
        cleanupIntervalMs: 20,
    });
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-5', {
        minPlayers: 2,
        maxPlayers: 4,
        fillBots: false,
    });
    manager.joinRoom(room.id, 'p2', 'P2', 'c2');
    manager.handleDisconnect('host-5');
    manager.handleDisconnect('p2');
    await new Promise((resolve) => setTimeout(resolve, 80));
    strict_1.default.equal(manager.getRoom(room.id), undefined);
});
// ============ Tests révélation des cartes en fin de partie ============
(0, node_test_1.default)('cards are revealed to all players when game ends', async (t) => {
    const { io, manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-reveal', {
        minPlayers: 2,
        maxPlayers: 2,
        fillBots: false,
    });
    manager.joinRoom(room.id, 'p2-reveal', 'P2', 'c2');
    manager.setReady(room.id, 'host-reveal', true);
    manager.setReady(room.id, 'p2-reveal', true);
    const started = manager.startGame(room.id, { fillBots: false });
    strict_1.default.equal(started, true);
    // Vérifier que les joueurs ont des cartes
    const player1 = room.gameState.players[0];
    const player2 = room.gameState.players[1];
    strict_1.default.ok(player1.hand.length > 0, 'Player 1 should have cards');
    strict_1.default.ok(player2.hand.length > 0, 'Player 2 should have cards');
    // Terminer la partie directement via handleGameEnd
    manager.handleGameEnd(room.id);
    // Vérifier que les événements GAME_ENDED contiennent les cartes révélées
    const gameEndedEvents = io.events.filter((e) => e.event === 'game:state_update' && e.data?.type === 'GAME_ENDED');
    strict_1.default.ok(gameEndedEvents.length >= 1, 'GAME_ENDED event should be emitted');
    const endedData = gameEndedEvents[0].data;
    strict_1.default.ok(endedData.roundScores, 'roundScores should be present');
    // Vérifier que chaque joueur a ses cartes dans roundScores
    for (const score of endedData.roundScores) {
        strict_1.default.ok(score.hand, `Player ${score.name} should have hand in roundScores`);
        strict_1.default.ok(Array.isArray(score.hand), 'hand should be an array');
        strict_1.default.ok(score.hand.length > 0, 'hand should not be empty');
    }
});
// ============ Tests départ de l'hôte pendant la partie ============
(0, node_test_1.default)('host leaving during game notifies other players', async (t) => {
    const { io, manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-leave', {
        minPlayers: 2,
        maxPlayers: 2,
        fillBots: false,
    });
    manager.joinRoom(room.id, 'p2-leave', 'P2', 'c2');
    manager.setReady(room.id, 'host-leave', true);
    manager.setReady(room.id, 'p2-leave', true);
    manager.startGame(room.id, { fillBots: false });
    // L'hôte ferme la room
    const result = manager.closeRoom(room.id, 'host-leave');
    strict_1.default.equal(result.success, true);
    // Vérifier que le statut est "closing"
    const updatedRoom = manager.getRoom(room.id);
    strict_1.default.equal(updatedRoom?.status, 'closing');
    // Vérifier que l'autre joueur a reçu la notification
    const closedEvents = io.findEventsFor('p2-leave', 'room:closed');
    strict_1.default.ok(closedEvents.length >= 1, 'Other player should receive room:closed event');
    strict_1.default.equal(closedEvents[0].data.canBecomeHost, true);
});
(0, node_test_1.default)('non-host player can become host after host leaves', async (t) => {
    const { io, manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-transfer', {
        minPlayers: 2,
        maxPlayers: 2,
        fillBots: false,
    });
    manager.joinRoom(room.id, 'p2-transfer', 'P2', 'c2');
    manager.setReady(room.id, 'host-transfer', true);
    manager.setReady(room.id, 'p2-transfer', true);
    manager.startGame(room.id, { fillBots: false });
    // L'hôte ferme la room
    manager.closeRoom(room.id, 'host-transfer');
    // L'autre joueur demande à devenir hôte
    const transferred = manager.transferHost(room.id, 'p2-transfer');
    strict_1.default.equal(transferred, true);
    const updatedRoom = manager.getRoom(room.id);
    strict_1.default.equal(updatedRoom?.hostPlayerId, 'p2-transfer');
    strict_1.default.equal(updatedRoom?.status, 'waiting');
    // Vérifier la notification
    const hostEvents = io.findEventsFor('p2-transfer', 'room:host_transferred');
    strict_1.default.ok(hostEvents.length >= 1);
});
// ============ Tests départ d'un joueur non-hôte pendant la partie ============
(0, node_test_1.default)('non-host player disconnecting during game becomes spectator', async (t) => {
    const { io, manager } = createManager({
        turnTimeoutMs: 30,
        presenceGraceMs: 30,
    });
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-stay', {
        minPlayers: 2,
        maxPlayers: 2,
        fillBots: false,
    });
    manager.joinRoom(room.id, 'p2-disconnect', 'P2', 'c2');
    manager.setReady(room.id, 'host-stay', true);
    manager.setReady(room.id, 'p2-disconnect', true);
    manager.startGame(room.id, { fillBots: false });
    // Le joueur non-hôte se déconnecte
    manager.handleDisconnect('p2-disconnect');
    const updatedRoom = manager.getRoom(room.id);
    const disconnectedPlayer = updatedRoom?.players.find((p) => p.id === 'p2-disconnect');
    strict_1.default.equal(disconnectedPlayer?.connected, false);
    // La room doit toujours exister car l'hôte est encore là
    strict_1.default.ok(updatedRoom, 'Room should still exist');
});
// ============ Tests restartGame (rematch) ============
(0, node_test_1.default)('restartGame resets room for new game after ended', async (t) => {
    const { io, manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-rematch', {
        minPlayers: 2,
        maxPlayers: 4,
        fillBots: true,
    });
    manager.joinRoom(room.id, 'p2-rematch', 'P2', 'c2');
    manager.setReady(room.id, 'host-rematch', true);
    manager.setReady(room.id, 'p2-rematch', true);
    manager.startGame(room.id, { fillBots: true });
    // Simuler fin de partie
    manager.handleGameEnd(room.id);
    strict_1.default.equal(room.status, 'ended');
    // Tenter un rematch
    const restarted = manager.restartGame(room.id, 'host-rematch');
    strict_1.default.equal(restarted, true);
    strict_1.default.equal(room.status, 'waiting');
    strict_1.default.equal(room.gameState, null);
    // Les bots doivent avoir été retirés
    const humanCount = room.players.filter((p) => p.isHuman).length;
    strict_1.default.equal(humanCount, 2);
    strict_1.default.equal(room.players.length, 2);
    // Les joueurs doivent être réinitialisés
    for (const player of room.players) {
        strict_1.default.equal(player.ready, false);
        strict_1.default.equal(player.isSpectator, false);
        strict_1.default.deepEqual(player.hand, []);
    }
    // Vérifier l'événement room:restarted
    const restartedEvents = io.events.filter((e) => e.event === 'room:restarted');
    strict_1.default.ok(restartedEvents.length >= 1);
});
(0, node_test_1.default)('only host can restart game', (t) => {
    const { manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-only-restart', {
        minPlayers: 2,
        maxPlayers: 2,
        fillBots: false,
    });
    manager.joinRoom(room.id, 'p2-only', 'P2', 'c2');
    manager.setReady(room.id, 'host-only-restart', true);
    manager.setReady(room.id, 'p2-only', true);
    manager.startGame(room.id, { fillBots: false });
    manager.handleGameEnd(room.id);
    // Un non-hôte ne peut pas relancer
    const restarted = manager.restartGame(room.id, 'p2-only');
    strict_1.default.equal(restarted, false);
    strict_1.default.equal(room.status, 'ended');
});
// ============ Tests closeRoom ============
(0, node_test_1.default)('closeRoom marks room as closing and notifies players', (t) => {
    const { io, manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-close', {
        minPlayers: 2,
        maxPlayers: 2,
        fillBots: false,
    });
    manager.joinRoom(room.id, 'p2-close', 'P2', 'c2');
    const result = manager.closeRoom(room.id, 'host-close');
    strict_1.default.equal(result.success, true);
    strict_1.default.equal(room.status, 'closing');
    strict_1.default.ok(room.closingAt, 'closingAt should be set');
    // L'hôte doit être retiré
    const hostInRoom = room.players.find((p) => p.id === 'host-close');
    strict_1.default.equal(hostInRoom, undefined);
    // L'autre joueur doit recevoir la notification
    const closedEvents = io.findEventsFor('p2-close', 'room:closed');
    strict_1.default.ok(closedEvents.length >= 1);
});
(0, node_test_1.default)('non-host cannot close room', (t) => {
    const { manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-no-close', {
        minPlayers: 2,
        maxPlayers: 2,
        fillBots: false,
    });
    manager.joinRoom(room.id, 'p2-no-close', 'P2', 'c2');
    const result = manager.closeRoom(room.id, 'p2-no-close');
    strict_1.default.equal(result.success, false);
    strict_1.default.equal(result.reason, 'Not host');
    strict_1.default.equal(room.status, 'waiting');
});
// ============ Tests scores calculés ============
(0, node_test_1.default)('scores are calculated correctly at game end', async (t) => {
    const { io, manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-score', {
        minPlayers: 2,
        maxPlayers: 2,
        fillBots: false,
    });
    manager.joinRoom(room.id, 'p2-score', 'P2', 'c2');
    manager.setReady(room.id, 'host-score', true);
    manager.setReady(room.id, 'p2-score', true);
    manager.startGame(room.id, { fillBots: false });
    // Les joueurs ont des cartes maintenant
    const player1 = room.gameState.players[0];
    const player2 = room.gameState.players[1];
    strict_1.default.ok(player1.hand.length > 0, 'Player 1 should have cards');
    strict_1.default.ok(player2.hand.length > 0, 'Player 2 should have cards');
    // Fin de partie
    manager.handleGameEnd(room.id);
    // Vérifier que roundScores est émis avec les scores corrects
    const gameEndedEvents = io.events.filter((e) => e.event === 'game:state_update' && e.data?.type === 'GAME_ENDED');
    strict_1.default.ok(gameEndedEvents.length >= 1, 'GAME_ENDED event should be emitted');
    const endedData = gameEndedEvents[0].data;
    strict_1.default.ok(endedData.roundScores, 'roundScores should exist');
    strict_1.default.equal(endedData.roundScores.length, 2, 'Should have scores for 2 players');
    for (const score of endedData.roundScores) {
        strict_1.default.ok(typeof score.score === 'number', 'Score should be a number');
        strict_1.default.ok(score.name, 'Name should exist');
        strict_1.default.ok(score.playerId, 'PlayerId should exist');
    }
});
// ============ Tests room après partie terminée ============
(0, node_test_1.default)('room remains available after game ends for rematch', (t) => {
    const { manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-available', {
        minPlayers: 2,
        maxPlayers: 2,
        fillBots: false,
    });
    manager.joinRoom(room.id, 'p2-available', 'P2', 'c2');
    manager.setReady(room.id, 'host-available', true);
    manager.setReady(room.id, 'p2-available', true);
    manager.startGame(room.id, { fillBots: false });
    manager.handleGameEnd(room.id);
    // La room doit toujours exister
    const updatedRoom = manager.getRoom(room.id);
    strict_1.default.ok(updatedRoom, 'Room should still exist after game ends');
    strict_1.default.equal(updatedRoom.status, 'ended');
    // On peut toujours la récupérer pour un rematch
    const canRestart = manager.restartGame(room.id, 'host-available');
    strict_1.default.equal(canRestart, true);
});
// ============ Tests kick player ============
(0, node_test_1.default)('host can kick player from room', (t) => {
    const { io, manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-kick', {
        minPlayers: 2,
        maxPlayers: 4,
        fillBots: false,
    });
    manager.joinRoom(room.id, 'p2-kick', 'P2', 'c2-kick');
    manager.joinRoom(room.id, 'p3-kick', 'P3', 'c3-kick');
    const kicked = manager.kickPlayer(room.id, 'host-kick', 'c2-kick');
    strict_1.default.equal(kicked, true);
    // Le joueur doit être retiré
    const kickedPlayer = room.players.find((p) => p.clientId === 'c2-kick');
    strict_1.default.equal(kickedPlayer, undefined);
    // Le joueur doit recevoir la notification
    const kickedEvents = io.findEventsFor('p2-kick', 'room:kicked');
    strict_1.default.ok(kickedEvents.length >= 1);
});
(0, node_test_1.default)('non-host cannot kick player', (t) => {
    const { manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-no-kick', {
        minPlayers: 2,
        maxPlayers: 4,
        fillBots: false,
    });
    manager.joinRoom(room.id, 'p2-no-kick', 'P2', 'c2-no-kick');
    manager.joinRoom(room.id, 'p3-no-kick', 'P3', 'c3-no-kick');
    const kicked = manager.kickPlayer(room.id, 'p2-no-kick', 'c3-no-kick');
    strict_1.default.equal(kicked, false);
    // Le joueur doit toujours être là
    const player = room.players.find((p) => p.clientId === 'c3-no-kick');
    strict_1.default.ok(player);
});
// ============ Tests cumulative scores ============
(0, node_test_1.default)('cumulative scores are tracked across rounds', (t) => {
    const { io, manager } = createManager();
    t.after(() => manager.dispose());
    const room = manager.createRoom('host-cumul', {
        minPlayers: 2,
        maxPlayers: 2,
        fillBots: false,
    });
    manager.joinRoom(room.id, 'p2-cumul', 'P2', 'c2-cumul');
    manager.setReady(room.id, 'host-cumul', true);
    manager.setReady(room.id, 'p2-cumul', true);
    manager.startGame(room.id, { fillBots: false });
    // Première partie
    manager.handleGameEnd(room.id);
    // Vérifier les scores cumulés après première partie
    let cumulativeEvents = io.events.filter((e) => e.event === 'game:state_update' && e.data?.cumulativeScores);
    strict_1.default.ok(cumulativeEvents.length >= 1);
    const firstRoundCumul = cumulativeEvents[cumulativeEvents.length - 1].data.cumulativeScores;
    strict_1.default.ok(Array.isArray(firstRoundCumul));
    // Relancer pour une deuxième partie
    manager.restartGame(room.id, 'host-cumul');
    manager.setReady(room.id, 'host-cumul', true);
    manager.setReady(room.id, 'p2-cumul', true);
    manager.startGame(room.id, { fillBots: false });
    manager.handleGameEnd(room.id);
    // Vérifier que les scores cumulés incluent les deux rounds
    cumulativeEvents = io.events.filter((e) => e.event === 'game:state_update' && e.data?.cumulativeScores);
    const secondRoundCumul = cumulativeEvents[cumulativeEvents.length - 1].data.cumulativeScores;
    // Les scores doivent avoir augmenté
    strict_1.default.ok(Array.isArray(secondRoundCumul));
});
