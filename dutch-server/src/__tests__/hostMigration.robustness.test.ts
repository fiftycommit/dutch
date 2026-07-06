import test from 'node:test';
import assert from 'node:assert/strict';
import { Server } from 'socket.io';
import { RoomManager } from '../services/RoomManager';
import { RoomStatus } from '../models/Room';
import { GamePhase } from '../models/GameState';

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
function lastHostBroadcast(io: FakeServer, roomCode: string): string | undefined {
  const pres = io.events.filter((e) => e.target === roomCode && e.event === 'presence:update');
  return pres.length ? pres[pres.length - 1].data?.hostPlayerId : undefined;
}

// Scénario 1 — l'hôte DÉCROCHE pendant l'attente (lobby). Le statut d'hôte doit
// passer à un autre joueur humain connecté, et le BROADCAST reçu par les clients
// doit refléter le nouvel hôte (pas juste un changement interne serveur).
test('bug#2.1: hôte qui décroche en attente -> l\'hôte migre vers un autre joueur (broadcast)', (t) => {
  const { io, manager } = createManager();
  t.after(() => manager.dispose());

  const room = manager.createRoom('p1', { minPlayers: 2, maxPlayers: 4, fillBots: false }, 'P1', 'c1', 'u1');
  manager.joinRoom(room.id, 'p2', 'P2', 'c2', 'u2');
  assert.equal(room.hostPlayerId, 'p1');

  io.events.length = 0;
  manager.handleDisconnect('p1');

  assert.equal(lastHostBroadcast(io, room.id), 'p2',
    'le broadcast présence doit annoncer p2 comme nouvel hôte');
});

// Scénario 2 — l'hôte DÉCROCHE en pleine partie active. La partie continue avec
// un nouvel hôte (les autres joueurs doivent pouvoir agir en fin de partie).
test('bug#2.2: hôte qui décroche en pleine partie -> l\'hôte migre (broadcast)', (t) => {
  const { io, manager } = createManager();
  t.after(() => manager.dispose());

  const room = manager.createRoom('p1', { minPlayers: 2, maxPlayers: 4, fillBots: true }, 'P1', 'c1', 'u1');
  manager.joinRoom(room.id, 'p2', 'P2', 'c2', 'u2');
  manager.setReady(room.id, 'p1', true);
  manager.setReady(room.id, 'p2', true);
  assert.equal(manager.startGame(room.id, { fillBots: true }), true);
  assert.equal(room.status, RoomStatus.playing);

  io.events.length = 0;
  manager.handleDisconnect('p1');

  // p2 (humain connecté) doit devenir hôte ; sinon plus personne ne peut relancer.
  assert.equal(room.hostPlayerId, 'p2', 'l\'hôte doit migrer vers p2 pendant la partie');
});

test('bug#2.2b: hôte courant qui décroche en pleine partie -> le tour avance', (t) => {
  const { manager } = createManager();
  t.after(() => manager.dispose());

  const room = manager.createRoom('p1', { minPlayers: 2, maxPlayers: 4, fillBots: false }, 'P1', 'c1', 'u1');
  manager.joinRoom(room.id, 'p2', 'P2', 'c2', 'u2');
  manager.setReady(room.id, 'p1', true);
  manager.setReady(room.id, 'p2', true);
  assert.equal(manager.startGame(room.id, { fillBots: false }), true);
  assert.ok(room.gameState);
  room.gameState.phase = GamePhase.playing;
  room.gameState.currentPlayerIndex = room.gameState.players.findIndex((p) => p.id === 'p1');

  manager.handleDisconnect('p1');

  assert.equal(room.hostPlayerId, 'p2', 'l\'hôte doit migrer vers p2');
  const p1Room = room.players.find((p) => p.id === 'p1');
  assert.equal(p1Room?.connected, false, 'p1 doit être hors ligne');
  assert.equal(p1Room?.isSpectator, true, 'p1 doit être retiré de la partie active');
  assert.notEqual(room.gameState.players[room.gameState.currentPlayerIndex].id, 'p1',
    'le tour ne doit pas rester bloqué sur le joueur déconnecté');
});

// Scénario 3 — l'hôte d'origine (créateur) revient APRÈS un transfert déjà fait.
// Le créateur ne doit pas reprendre l'hôte : le joueur qui l'a reçu le garde.
test('bug#2.3: créateur qui revient après transfert -> le nouvel hôte reste hôte', (t) => {
  const { manager } = createManager();
  t.after(() => manager.dispose());

  const room = manager.createRoom('p1', { minPlayers: 2, maxPlayers: 4, fillBots: false }, 'P1', 'c1', 'u1');
  manager.joinRoom(room.id, 'p2', 'P2', 'c2', 'u2');
  // p1 (créateur) décroche -> transfert vers p2
  manager.handleDisconnect('p1');

  // p1 revient avec un nouveau socket (même identité u1)
  manager.joinRoom(room.id, 'p1-new', 'P1', 'c1', 'u1');

  const hostId = room.hostPlayerId;
  assert.equal(hostId, 'p2', 'le créateur reconnecté ne doit pas reprendre l\'hôte');
  const hosts = room.players.filter((p) => p.id === hostId);
  assert.equal(hosts.length, 1, 'exactement un joueur correspond à hostPlayerId');
  const host = hosts[0];
  assert.ok(host.isHuman && host.connected, 'l\'hôte doit être un joueur humain connecté');
  // pas de joueur « fantôme » disconnecté encore marqué hôte
  assert.ok(!room.players.some((p) => p.id !== hostId && p.id === 'p1'),
    'l\'ancien socket disconnecté ne doit pas subsister comme hôte');
});
