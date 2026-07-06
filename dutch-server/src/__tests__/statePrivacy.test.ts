import test from 'node:test';
import assert from 'node:assert/strict';
import { Server } from 'socket.io';
import { RoomManager } from '../services/RoomManager';
import { createCard } from '../models/Card';

// Confidentialité de l'état diffusé : la valeur d'une carte privée ne doit
// JAMAIS être présente dans le payload reçu par un autre joueur (pas juste
// « le client ne l'affiche pas » — la valeur ne doit pas partir sur le fil).

class FakeServer {
  events: Array<{ target: string; event: string; data: any }> = [];
  private currentTarget = '';
  to(target: string) { this.currentTarget = target; return this; }
  emit(event: string, data: any) { this.events.push({ target: this.currentTarget, event, data }); return true; }
}

function createManager() {
  const io = new FakeServer();
  const manager = new RoomManager(io as unknown as Server, {
    cleanupIntervalMs: 10_000,
    roomTtlMs: 60_000,
  });
  return { io, manager };
}

function startTwoPlayerGame(manager: RoomManager) {
  const room = manager.createRoom('p1', { minPlayers: 2, maxPlayers: 2, fillBots: false }, 'P1', 'c1', 'u1');
  manager.joinRoom(room.id, 'p2', 'P2', 'c2', 'u2');
  manager.setReady(room.id, 'p1', true);
  manager.setReady(room.id, 'p2', true);
  assert.equal(manager.startGame(room.id, { fillBots: false }), true);
  return room;
}

function lastStateFor(io: FakeServer, target: string) {
  const updates = io.events.filter(
    (e) => e.target === target && e.event === 'game:state_update'
  );
  assert.ok(updates.length > 0, `aucun game:state_update reçu par ${target}`);
  return updates[updates.length - 1].data.gameState;
}

test('privacy: drawnCard n\'est envoyée en clair qu\'au joueur qui a pioché', (t) => {
  const { io, manager } = createManager();
  t.after(() => manager.dispose());

  const room = startTwoPlayerGame(manager);
  const gs = room.gameState!;
  const drawerId = gs.players[gs.currentPlayerIndex].id;
  const otherId = drawerId === 'p1' ? 'p2' : 'p1';

  // Le joueur courant pioche : drawnCard porte une vraie carte
  gs.drawnCard = createCard('hearts', '7');
  io.events.length = 0;
  manager.broadcastGameState(room.id, 'ACTION_RESULT');

  const drawerState = lastStateFor(io, drawerId);
  assert.equal(drawerState.drawnCard?.value, '7', 'le pilocheur doit voir sa carte');
  assert.equal(drawerState.drawnCard?.suit, 'hearts');

  const otherState = lastStateFor(io, otherId);
  const other = otherState.drawnCard;
  assert.ok(other === null || (other.hidden === true && other.value === undefined && other.suit === undefined),
    `l'adversaire ne doit pas recevoir la valeur (reçu: ${JSON.stringify(other)})`);
});

test('privacy: lastSpiedCard n\'est envoyée en clair qu\'au joueur qui espionne', (t) => {
  const { io, manager } = createManager();
  t.after(() => manager.dispose());

  const room = startTwoPlayerGame(manager);
  const gs = room.gameState!;
  const spyId = gs.players[gs.currentPlayerIndex].id;
  const otherId = spyId === 'p1' ? 'p2' : 'p1';

  // Pouvoir 7/10 : le joueur courant regarde une carte
  gs.lastSpiedCard = createCard('spades', 'K');
  gs.specialPowerPlayerId = spyId;
  io.events.length = 0;
  manager.broadcastGameState(room.id, 'ACTION_RESULT');

  const otherState = lastStateFor(io, otherId);
  const other = otherState.lastSpiedCard;
  assert.ok(other === null || (other.hidden === true && other.value === undefined),
    `l'adversaire ne doit pas recevoir la carte espionnée (reçu: ${JSON.stringify(other)})`);
});

test('privacy: lastSpiedCard masquée aussi quand specialPowerPlayerId est null (pouvoir du joueur courant)', (t) => {
  const { io, manager } = createManager();
  t.after(() => manager.dispose());

  const room = startTwoPlayerGame(manager);
  const gs = room.gameState!;
  const spyId = gs.players[gs.currentPlayerIndex].id;
  const otherId = spyId === 'p1' ? 'p2' : 'p1';

  // specialPowerPlayerId=null => le pouvoir appartient au joueur courant
  gs.lastSpiedCard = createCard('diamonds', 'Q');
  gs.specialPowerPlayerId = null;
  io.events.length = 0;
  manager.broadcastGameState(room.id, 'ACTION_RESULT');

  const other = lastStateFor(io, otherId).lastSpiedCard;
  assert.ok(other === null || (other.hidden === true && other.value === undefined),
    `l'adversaire ne doit pas recevoir la carte espionnée (reçu: ${JSON.stringify(other)})`);
});

test('privacy: un spectateur ne reçoit ni drawnCard ni lastSpiedCard en clair', (t) => {
  const { io, manager } = createManager();
  t.after(() => manager.dispose());

  const room = startTwoPlayerGame(manager);
  const gs = room.gameState!;
  // Un 3e client rejoint en pleine partie -> spectateur automatique
  const joined = manager.joinRoom(room.id, 'spec', 'Spec', 'cS', 'uS');
  assert.equal(joined.player?.isSpectator, true, 'doit rejoindre en spectateur');

  gs.drawnCard = createCard('clubs', 'A');
  gs.lastSpiedCard = createCard('hearts', '9');
  io.events.length = 0;
  manager.broadcastGameState(room.id, 'ACTION_RESULT');

  const specState = lastStateFor(io, 'spec');
  const d = specState.drawnCard;
  const s = specState.lastSpiedCard;
  assert.ok(d === null || (d.hidden === true && d.value === undefined),
    `spectateur: drawnCard en clair (reçu: ${JSON.stringify(d)})`);
  assert.ok(s === null || (s.hidden === true && s.value === undefined),
    `spectateur: lastSpiedCard en clair (reçu: ${JSON.stringify(s)})`);
});

test('privacy: fin de partie — les mains restent révélées à tous (résolution Dutch inchangée)', (t) => {
  const { io, manager } = createManager();
  t.after(() => manager.dispose());

  const room = startTwoPlayerGame(manager);
  manager.handleGameEnd(room.id);

  const p2State = lastStateFor(io, 'p2');
  const p1Hand = p2State.players.find((p: any) => p.id === 'p1')?.hand ?? [];
  assert.ok(p1Hand.length > 0, 'main de p1 présente');
  for (const card of p1Hand) {
    assert.ok(card.value !== undefined && card.hidden !== true,
      `à la résolution, les mains sont publiques (reçu: ${JSON.stringify(card)})`);
  }
});
