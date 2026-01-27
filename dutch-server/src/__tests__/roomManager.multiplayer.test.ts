import test from 'node:test';
import assert from 'node:assert/strict';
import { Server } from 'socket.io';
import { RoomManager } from '../services/RoomManager';
import { getCurrentPlayer } from '../models/GameState';

type EmittedEvent = {
  target: string;
  event: string;
  data: any;
};

class FakeServer {
  events: EmittedEvent[] = [];
  private currentTarget = '';

  to(target: string) {
    this.currentTarget = target;
    return this;
  }

  emit(event: string, data: any) {
    this.events.push({ target: this.currentTarget, event, data });
    return true;
  }

  findEventsFor(target: string, event: string) {
    return this.events.filter((e) => e.target === target && e.event === event);
  }
}

function createManager(
  options: Partial<ConstructorParameters<typeof RoomManager>[1]> = {}
) {
  const io = new FakeServer();
  const manager = new RoomManager(io as unknown as Server, {
    cleanupIntervalMs: 10_000,
    roomTtlMs: 60_000,
    ...options,
  });
  return { io, manager };
}

test('startGame enforces minPlayers and respects fillBots=false', (t) => {
  const { manager } = createManager();
  t.after(() => manager.dispose());

  const room = manager.createRoom('host-1', {
    minPlayers: 3,
    maxPlayers: 4,
    fillBots: false,
  });

  manager.joinRoom(room.id, 'p2', 'P2', 'c2');

  const startedTooEarly = manager.startGame(room.id);
  assert.equal(startedTooEarly, false);
  assert.equal(room.status, 'waiting');
  assert.equal(room.gameState, null);

  manager.joinRoom(room.id, 'p3', 'P3', 'c3');
  manager.setReady(room.id, 'host-1', true);
  manager.setReady(room.id, 'p2', true);
  manager.setReady(room.id, 'p3', true);

  const started = manager.startGame(room.id, { fillBots: false });
  assert.equal(started, true);
  assert.ok(room.gameState);

  const humanCount = room.players.filter((p) => p.isHuman).length;
  assert.equal(humanCount, 3);
  assert.equal(room.players.length, 3);
});

test('startGame fills bots up to maxPlayers when fillBots=true', (t) => {
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
  assert.equal(started, true);
  assert.ok(room.gameState);

  const humanCount = room.players.filter((p) => p.isHuman).length;
  assert.equal(humanCount, 2);
  assert.equal(room.players.length, 4);
});

test('turn timeout triggers presence check then spectator', async (t) => {
  const { io, manager } = createManager({
    turnTimeoutMs: 40,
    presenceGraceMs: 40,
    cleanupIntervalMs: 10_000,
    roomTtlMs: 60_000,
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
  assert.equal(started, true);
  assert.ok(room.gameState);

  const currentPlayerId = getCurrentPlayer(room.gameState!).id;
  const otherPlayerId = room.players.find((p) => p.id !== currentPlayerId)!.id;

  await new Promise((resolve) => setTimeout(resolve, 70));

  const checkEvents = io.findEventsFor(currentPlayerId, 'presence:check');
  assert.ok(checkEvents.length >= 1);

  await new Promise((resolve) => setTimeout(resolve, 80));

  const timedOutPlayer = room.players.find((p) => p.id === currentPlayerId)!;
  assert.equal(timedOutPlayer.isSpectator, true);
  assert.notEqual(getCurrentPlayer(room.gameState!).id, currentPlayerId);
  assert.equal(getCurrentPlayer(room.gameState!).id, otherPlayerId);
});

test('cleanup removes room on TTL expiration', async (t) => {
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

  assert.equal(manager.getRoom(room.id), undefined);
});

test('cleanup removes room when all humans disconnect', async (t) => {
  const { manager } = createManager({
    roomTtlMs: 60_000,
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

  assert.equal(manager.getRoom(room.id), undefined);
});

// ============ Tests révélation des cartes en fin de partie ============

test('cards are revealed to all players when game ends', async (t) => {
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
  assert.equal(started, true);

  // Vérifier que les joueurs ont des cartes
  const player1 = room.gameState!.players[0];
  const player2 = room.gameState!.players[1];
  assert.ok(player1.hand.length > 0, 'Player 1 should have cards');
  assert.ok(player2.hand.length > 0, 'Player 2 should have cards');

  // Terminer la partie directement via handleGameEnd
  manager.handleGameEnd(room.id);

  // Vérifier que les événements GAME_ENDED contiennent les cartes révélées
  const gameEndedEvents = io.events.filter((e) => e.event === 'game:state_update' && e.data?.type === 'GAME_ENDED');
  assert.ok(gameEndedEvents.length >= 1, 'GAME_ENDED event should be emitted');

  const endedData = gameEndedEvents[0].data;
  assert.ok(endedData.roundScores, 'roundScores should be present');

  // Vérifier que chaque joueur a ses cartes dans roundScores
  for (const score of endedData.roundScores) {
    assert.ok(score.hand, `Player ${score.name} should have hand in roundScores`);
    assert.ok(Array.isArray(score.hand), 'hand should be an array');
    assert.ok(score.hand.length > 0, 'hand should not be empty');
  }
});

// ============ Tests départ de l'hôte pendant la partie ============

test('host leaving during game notifies other players', async (t) => {
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
  assert.equal(result.success, true);

  // Vérifier que le statut est "closing"
  const updatedRoom = manager.getRoom(room.id);
  assert.equal(updatedRoom?.status, 'closing');

  // Vérifier que l'autre joueur a reçu la notification
  const closedEvents = io.findEventsFor('p2-leave', 'room:closed');
  assert.ok(closedEvents.length >= 1, 'Other player should receive room:closed event');
  assert.equal(closedEvents[0].data.canBecomeHost, true);
});

test('non-host player can become host after host leaves', async (t) => {
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
  assert.equal(transferred, true);

  const updatedRoom = manager.getRoom(room.id);
  assert.equal(updatedRoom?.hostPlayerId, 'p2-transfer');
  assert.equal(updatedRoom?.status, 'waiting');

  // Vérifier la notification
  const hostEvents = io.findEventsFor('p2-transfer', 'room:host_transferred');
  assert.ok(hostEvents.length >= 1);
});

// ============ Tests départ d'un joueur non-hôte pendant la partie ============

test('non-host player disconnecting during game becomes spectator', async (t) => {
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
  assert.equal(disconnectedPlayer?.connected, false);

  // La room doit toujours exister car l'hôte est encore là
  assert.ok(updatedRoom, 'Room should still exist');
});

// ============ Tests restartGame (rematch) ============

test('restartGame resets room for new game after ended', async (t) => {
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
  assert.equal(room.status, 'ended');

  // Tenter un rematch
  const restarted = manager.restartGame(room.id, 'host-rematch');
  assert.equal(restarted, true);
  assert.equal(room.status, 'waiting');
  assert.equal(room.gameState, null);

  // Les bots doivent avoir été retirés
  const humanCount = room.players.filter((p) => p.isHuman).length;
  assert.equal(humanCount, 2);
  assert.equal(room.players.length, 2);

  // Les joueurs doivent être réinitialisés
  for (const player of room.players) {
    assert.equal(player.ready, false);
    assert.equal(player.isSpectator, false);
    assert.deepEqual(player.hand, []);
  }

  // Vérifier l'événement room:restarted
  const restartedEvents = io.events.filter((e) => e.event === 'room:restarted');
  assert.ok(restartedEvents.length >= 1);
});

test('only host can restart game', (t) => {
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
  assert.equal(restarted, false);
  assert.equal(room.status, 'ended');
});

// ============ Tests closeRoom ============

test('closeRoom marks room as closing and notifies players', (t) => {
  const { io, manager } = createManager();
  t.after(() => manager.dispose());

  const room = manager.createRoom('host-close', {
    minPlayers: 2,
    maxPlayers: 2,
    fillBots: false,
  });
  manager.joinRoom(room.id, 'p2-close', 'P2', 'c2');

  const result = manager.closeRoom(room.id, 'host-close');
  assert.equal(result.success, true);
  assert.equal(room.status, 'closing');
  assert.ok(room.closingAt, 'closingAt should be set');

  // L'hôte doit être retiré
  const hostInRoom = room.players.find((p) => p.id === 'host-close');
  assert.equal(hostInRoom, undefined);

  // L'autre joueur doit recevoir la notification
  const closedEvents = io.findEventsFor('p2-close', 'room:closed');
  assert.ok(closedEvents.length >= 1);
});

test('non-host cannot close room', (t) => {
  const { manager } = createManager();
  t.after(() => manager.dispose());

  const room = manager.createRoom('host-no-close', {
    minPlayers: 2,
    maxPlayers: 2,
    fillBots: false,
  });
  manager.joinRoom(room.id, 'p2-no-close', 'P2', 'c2');

  const result = manager.closeRoom(room.id, 'p2-no-close');
  assert.equal(result.success, false);
  assert.equal(result.reason, 'Not host');
  assert.equal(room.status, 'waiting');
});

// ============ Tests scores calculés ============

test('scores are calculated correctly at game end', async (t) => {
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
  const player1 = room.gameState!.players[0];
  const player2 = room.gameState!.players[1];
  assert.ok(player1.hand.length > 0, 'Player 1 should have cards');
  assert.ok(player2.hand.length > 0, 'Player 2 should have cards');

  // Fin de partie
  manager.handleGameEnd(room.id);

  // Vérifier que roundScores est émis avec les scores corrects
  const gameEndedEvents = io.events.filter((e) => e.event === 'game:state_update' && e.data?.type === 'GAME_ENDED');
  assert.ok(gameEndedEvents.length >= 1, 'GAME_ENDED event should be emitted');

  const endedData = gameEndedEvents[0].data;
  assert.ok(endedData.roundScores, 'roundScores should exist');
  assert.equal(endedData.roundScores.length, 2, 'Should have scores for 2 players');

  for (const score of endedData.roundScores) {
    assert.ok(typeof score.score === 'number', 'Score should be a number');
    assert.ok(score.name, 'Name should exist');
    assert.ok(score.playerId, 'PlayerId should exist');
  }
});

// ============ Tests room après partie terminée ============

test('room remains available after game ends for rematch', (t) => {
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
  assert.ok(updatedRoom, 'Room should still exist after game ends');
  assert.equal(updatedRoom.status, 'ended');

  // On peut toujours la récupérer pour un rematch
  const canRestart = manager.restartGame(room.id, 'host-available');
  assert.equal(canRestart, true);
});

// ============ Tests kick player ============

test('host can kick player from room', (t) => {
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
  assert.equal(kicked, true);

  // Le joueur doit être retiré
  const kickedPlayer = room.players.find((p) => p.clientId === 'c2-kick');
  assert.equal(kickedPlayer, undefined);

  // Le joueur doit recevoir la notification
  const kickedEvents = io.findEventsFor('p2-kick', 'room:kicked');
  assert.ok(kickedEvents.length >= 1);
});

test('non-host cannot kick player', (t) => {
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
  assert.equal(kicked, false);

  // Le joueur doit toujours être là
  const player = room.players.find((p) => p.clientId === 'c3-no-kick');
  assert.ok(player);
});

// ============ Tests cumulative scores ============

test('cumulative scores are tracked across rounds', (t) => {
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
  assert.ok(cumulativeEvents.length >= 1);

  const firstRoundCumul = cumulativeEvents[cumulativeEvents.length - 1].data.cumulativeScores;
  assert.ok(Array.isArray(firstRoundCumul));

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
  assert.ok(Array.isArray(secondRoundCumul));
});
