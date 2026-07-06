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

// Bug n°1 : la pastille de présence reste verte après qu'un joueur soit parti.
// Cause : en pleine partie, handleDisconnect ne rediffusait QUE la présence
// (presence:update), jamais le gameState. Le client construit la connexion in-game
// à partir de gameState.players ; sans rediffusion, l'état de jeu des autres
// clients gardait le joueur `connected` (et le client fail-open l'affichait vert).
// Preuve serveur : après un disconnect en partie, les autres joueurs doivent
// recevoir une mise à jour de l'ÉTAT DE JEU où le partant est connected=false.
test('bug#1: un disconnect en partie rediffuse le gameState avec connected=false', (t) => {
  const { io, manager } = createManager();
  t.after(() => manager.dispose());

  const room = manager.createRoom('host', { minPlayers: 2, maxPlayers: 2, fillBots: false }, 'Host', 'cHost', 'uHost');
  manager.joinRoom(room.id, 'p2', 'P2', 'cP2', 'uP2');
  manager.setReady(room.id, 'host', true);
  manager.setReady(room.id, 'p2', true);
  assert.equal(manager.startGame(room.id, { fillBots: false }), true);

  io.events.length = 0; // ne garder que ce qui suit le disconnect
  manager.handleDisconnect('p2');

  // L'hôte (toujours là) doit recevoir une mise à jour de l'état de jeu marquant p2 hors ligne.
  const stateUpdates = io.events.filter(
    (e) => e.target === 'host' && e.event === 'game:state_update'
  );
  const p2Offline = stateUpdates.some((e) =>
    (e.data?.gameState?.players ?? []).some(
      (p: any) => p.id === 'p2' && p.connected === false
    )
  );
  assert.equal(p2Offline, true, 'les autres joueurs doivent voir p2 connected=false dans le gameState');
});

// Bug n°1 (sens reconnexion) : un joueur qui revient doit repasser EN LIGNE sur
// l'écran des autres (sinon la pastille reste « Hors ligne » à vie).
test('bug#1: une reconnexion en partie rediffuse le gameState avec connected=true', (t) => {
  const { io, manager } = createManager();
  t.after(() => manager.dispose());

  const room = manager.createRoom('host', { minPlayers: 2, maxPlayers: 3, fillBots: false }, 'Host', 'cHost', 'uHost');
  manager.joinRoom(room.id, 'p2', 'P2', 'cP2', 'uP2');
  manager.joinRoom(room.id, 'p3', 'P3', 'cP3', 'uP3');
  manager.setReady(room.id, 'host', true);
  manager.setReady(room.id, 'p2', true);
  manager.setReady(room.id, 'p3', true);
  assert.equal(manager.startGame(room.id, { fillBots: false }), true);

  manager.handleDisconnect('p2'); // 2 humains restants -> la partie continue
  assert.equal(room.status, RoomStatus.playing);

  io.events.length = 0;
  // p2 revient avec un NOUVEAU socket (même identité uP2)
  manager.joinRoom(room.id, 'p2-new', 'P2', 'cP2', 'uP2');

  const updates = io.events.filter((e) => e.target === 'host' && e.event === 'game:state_update');
  const backOnline = updates.some((e) =>
    (e.data?.gameState?.players ?? []).some(
      (p: any) => p.id === 'p2-new' && p.connected === true
    )
  );
  assert.equal(backOnline, true, 'les autres joueurs doivent voir le revenant connected=true');
});
