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
  const manager = new RoomManager(io as unknown as Server, {
    cleanupIntervalMs: 10_000,
    roomTtlMs: 60_000,
  });
  return { io, manager };
}

// Scénario 4 — l'hôte part et il ne reste QUE des bots. Le salon ne doit pas
// rester dans un état fantôme (partie qui tourne toute seule avec des bots).
test('bug#2.4: hôte part, plus aucun humain -> le salon ne reste pas fantôme', (t) => {
  const { manager } = createManager();
  t.after(() => manager.dispose());

  const room = manager.createRoom('p1', { minPlayers: 2, maxPlayers: 4, fillBots: true }, 'P1', 'c1', 'u1');
  manager.joinRoom(room.id, 'p2', 'P2', 'c2', 'u2');
  manager.setReady(room.id, 'p1', true);
  manager.setReady(room.id, 'p2', true);
  assert.equal(manager.startGame(room.id, { fillBots: true }), true);

  // Les deux humains décrochent -> il ne reste que des bots
  manager.handleDisconnect('p1');
  manager.handleDisconnect('p2');

  const room2 = manager.getRoom(room.id);
  const humansConnected = room2
    ? room2.players.filter((p) => p.isHuman && p.connected).length
    : 0;
  assert.equal(humansConnected, 0);
  // La partie ne doit pas continuer indéfiniment avec 0 humain : soit la room est
  // supprimée, soit la partie est terminée.
  const stillRunning = room2 && room2.status === RoomStatus.playing;
  assert.ok(!stillRunning,
    `un salon sans aucun humain ne doit pas rester en 'playing' (fantôme)`);
});
