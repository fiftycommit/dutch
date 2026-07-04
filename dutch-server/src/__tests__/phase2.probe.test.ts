import test from 'node:test';
import assert from 'node:assert/strict';
import { Server } from 'socket.io';
import { RoomManager } from '../services/RoomManager';
import { RoomStatus } from '../models/Room';

class FakeServer {
  events: Array<{ target: string; event: string; data: any }> = [];
  private currentTarget = '';
  to(target: string) { this.currentTarget = target; return this; }
  emit(event: string, data: any) { this.events.push({ target: this.currentTarget, event, data }); return true; }
}
function createManager() {
  const io = new FakeServer();
  const manager = new RoomManager(io as unknown as Server, { cleanupIntervalMs: 10_000, roomTtlMs: 60_000 });
  return { io, manager };
}

// Phase 2 — reconnexions rapides répétées : un même joueur (identité stable) qui
// enchaîne disconnect/reconnect ne doit jamais produire de doublon ni casser l'hôte.
test('phase2: reconnexions rapides répétées -> pas de doublon, un seul joueur/identité, hôte cohérent', (t) => {
  const { manager } = createManager();
  t.after(() => manager.dispose());

  const room = manager.createRoom('p1', { minPlayers: 2, maxPlayers: 4, fillBots: false }, 'P1', 'c1', 'u1');
  manager.joinRoom(room.id, 'p2', 'P2', 'c2', 'u2');

  // p2 fait 5 cycles disconnect/reconnect rapides (nouveau socketId à chaque fois)
  let sock = 'p2';
  for (let i = 0; i < 5; i++) {
    manager.handleDisconnect(sock);
    const next = `p2-r${i}`;
    manager.detachIdentityFromOtherRooms(room.id, { socketId: next, userId: 'u2', username: 'p2', clientId: 'c2' });
    const res = manager.joinRoom(room.id, next, 'P2', 'c2', 'u2');
    assert.ok(res.player, 'rejoin doit réussir');
    sock = next;
  }

  const p2Instances = room.players.filter((p) => p.userId === 'u2');
  assert.equal(p2Instances.length, 1, `un seul joueur pour l'identité u2 (trouvé ${p2Instances.length})`);
  const connectedHumans = room.players.filter((p) => p.isHuman && p.connected);
  assert.equal(connectedHumans.length, 2, 'p1 + p2 connectés, pas de fantômes');
  const host = room.players.find((p) => p.id === room.hostPlayerId);
  assert.ok(host && host.isHuman && host.connected, 'hôte = un humain connecté');
});

// Phase 2 — tous les joueurs sauf un quittent une room en attente, puis un des
// partis revient : état propre (pas de doublon, hôte cohérent, room vivante).
test('phase2: tous partent sauf un puis un revient -> état propre', (t) => {
  const { manager } = createManager();
  t.after(() => manager.dispose());

  const room = manager.createRoom('p1', { minPlayers: 2, maxPlayers: 4, fillBots: false }, 'P1', 'c1', 'u1');
  manager.joinRoom(room.id, 'p2', 'P2', 'c2', 'u2');
  manager.joinRoom(room.id, 'p3', 'P3', 'c3', 'u3');

  // p2 et p3 quittent proprement -> reste p1
  manager.handleLeave(room.id, 'p2');
  manager.handleLeave(room.id, 'p3');
  assert.ok(manager.getRoom(room.id), 'room encore là (p1 reste)');
  assert.equal(room.hostPlayerId, 'p1');

  // p2 revient (nouveau socket)
  manager.detachIdentityFromOtherRooms(room.id, { socketId: 'p2-back', userId: 'u2', username: 'p2', clientId: 'c2' });
  const res = manager.joinRoom(room.id, 'p2-back', 'P2', 'c2', 'u2');
  assert.ok(res.player, 'p2 rejoint');
  const u2 = room.players.filter((p) => p.userId === 'u2');
  assert.equal(u2.length, 1, 'un seul p2');
  assert.equal(room.status, RoomStatus.waiting, 'room en attente');
});

// Phase 2 — un joueur qui rejoint pendant qu'une action est en cours de résolution
// (drawnCard posé) : le nouveau venu (spectateur) reçoit un état cohérent, sans
// planter, et sans voir la carte piochée (déjà couvert par la privacy, re-vérifié ici).
test('phase2: rejoindre pendant une résolution en cours -> spectateur, état cohérent', (t) => {
  const { io, manager } = createManager();
  t.after(() => manager.dispose());

  const room = manager.createRoom('p1', { minPlayers: 2, maxPlayers: 4, fillBots: true }, 'P1', 'c1', 'u1');
  manager.joinRoom(room.id, 'p2', 'P2', 'c2', 'u2');
  manager.setReady(room.id, 'p1', true);
  manager.setReady(room.id, 'p2', true);
  assert.equal(manager.startGame(room.id, { fillBots: true }), true);

  // action en cours : une carte est piochée
  room.gameState!.drawnCard = { suit: 'hearts', value: '7', points: 7, isSpecial: true, id: '7_hearts' } as any;

  io.events.length = 0;
  const joined = manager.joinRoom(room.id, 'late', 'Late', 'cL', 'uL');
  assert.equal(joined.player?.isSpectator, true, 'rejoint en pleine résolution -> spectateur');

  // l'état complet envoyé au nouveau venu ne doit pas planter ni fuiter drawnCard
  const full = io.events.find((e) => e.target === 'late' && e.event === 'game:full_state');
  assert.ok(full, 'un game:full_state est envoyé au spectateur');
  const d = full!.data.gameState.drawnCard;
  assert.ok(d === null || d.hidden === true, 'le spectateur ne voit pas la carte en cours de pioche');
});
