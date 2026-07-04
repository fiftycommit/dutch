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

// Bug n°3 : rejoindre un salon où une partie a déjà eu lieu.
// Scénario défavorable : la partie se termine (écran de résultats), UN joueur
// DÉCROCHE (disconnect) sur les résultats au lieu de cliquer « retour au salon ».
// handleDisconnect ne le retire pas de `playersInResults` -> le reset ne se
// déclenche jamais -> la room reste bloquée en `ended` avec un `gameState`
// périmé, et un nouveau venu reçoit l'ancienne partie terminée.
test('bug#3: un disconnect sur les résultats ne doit pas bloquer la room en ended', (t) => {
  const { manager } = createManager();
  t.after(() => manager.dispose());

  const room = manager.createRoom('host', { minPlayers: 2, maxPlayers: 2, fillBots: false }, 'Host', 'cHost', 'uHost');
  manager.joinRoom(room.id, 'p2', 'P2', 'cP2', 'uP2');
  manager.setReady(room.id, 'host', true);
  manager.setReady(room.id, 'p2', true);
  assert.equal(manager.startGame(room.id, { fillBots: false }), true, 'la partie doit démarrer');

  // Fin de partie -> écran de résultats
  manager.handleGameEnd(room.id);
  assert.equal(room.status, RoomStatus.ended);
  assert.notEqual(room.gameState, null);

  // L'hôte quitte proprement les résultats
  manager.backToLobby(room.id, 'host');
  // L'autre joueur DÉCROCHE sur les résultats (ferme l'app / coupure réseau)
  manager.handleDisconnect('p2');

  // Comportement attendu : plus personne n'observe réellement les résultats
  // (l'hôte est parti, p2 a décroché) -> la room doit se réinitialiser pour
  // qu'un nouveau venu tombe sur un lobby propre, pas sur l'ancienne partie.
  assert.equal(room.status, RoomStatus.waiting, 'la room devrait être réinitialisée en waiting');
  assert.equal(room.gameState, null, 'le gameState périmé devrait être purgé');
});
