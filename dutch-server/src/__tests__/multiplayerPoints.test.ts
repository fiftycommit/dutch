import test from 'node:test';
import assert from 'node:assert/strict';
import { Server } from 'socket.io';
import { RoomManager } from '../services/RoomManager';
import { createCard } from '../models/Card';
import { RoomSnapshotCodec } from '../services/RoomSnapshotCodec';
import { GameMode } from '../models/GameState';

function fixture(t: { after(fn: () => void): void }, scores: number[], caller?: number, gameMode = GameMode.quick) {
  const events: Array<{ target: string; event: string; data: any }> = [];
  let target = '';
  const io = { to(id: string) { target = id; return this; }, emit(event: string, data: any) { events.push({ target, event, data }); return true; } };
  const manager = new RoomManager(io as unknown as Server);
  t.after(() => manager.dispose());
  const room = manager.createRoom('p0', { gameMode, minPlayers: 2, maxPlayers: scores.length, fillBots: false }, 'P0', 'c0');
  for (let i = 1; i < scores.length; i++) manager.joinRoom(room.id, `p${i}`, `P${i}`, `c${i}`);
  for (let i = 0; i < scores.length; i++) manager.setReady(room.id, `p${i}`, true);
  assert.equal(manager.startGame(room.id, { fillBots: false }), true);
  room.gameState!.players.forEach((player, i) => { player.hand = scores[i] === 0 ? [] : [createCard('hearts', String(scores[i]))]; });
  room.gameState!.dutchCallerId = caller === undefined ? null : `p${caller}`;
  return { manager, room, events };
}

test('a winning Dutch caller is the only first place even with tied card scores', (t) => {
  const { manager, room } = fixture(t, [5, 5, 5, 10], 0);
  manager.handleGameEnd(room.id);
  assert.deepEqual(room.gameState!.roundScores!.map(s => [s.rank, s.rpChange]), [[1, 62], [2, 21], [2, 21], [4, -70]]);
});

test('a failed Dutch caller receives last-place RP and the Dutch penalty', (t) => {
  const { manager, room } = fixture(t, [7, 5, 10, 12], 0);
  manager.handleGameEnd(room.id);
  assert.deepEqual(room.gameState!.roundScores!.map(s => [s.rank, s.rpChange]), [[4, -100], [1, 42], [2, 21], [3, -35]]);
});

test('spectators finish last and a failed Dutch is last among active players', (t) => {
  const { manager, room } = fixture(t, [7, 5, 10, 12], 0);
  room.gameState!.players[3].isSpectator = true;
  manager.handleGameEnd(room.id);
  assert.deepEqual(room.gameState!.roundScores!.map(s => s.rank), [3, 1, 2, 4]);
  const state = (manager as any).getPersonalizedState(room.gameState, 'p0');
  assert.equal(state.players[3].score, 100);
});

test('tournament elimination follows the failed-Dutch rank used for RP', (t) => {
  const { manager, room } = fixture(t, [7, 5, 10, 12], 0, GameMode.tournament);
  manager.handleGameEnd(room.id);
  assert.equal(manager.restartGame(room.id, 'p1'), true);
  assert.equal(room.players.find(p => p.id === 'p0')!.isSpectator, true);
  assert.equal(room.players.find(p => p.id === 'p3')!.isSpectator, false);
});

test('ties without Dutch keep competition ranks and a perfect Dutch gets its bonus', (t) => {
  const normal = fixture(t, [5, 5, 10, 12]);
  normal.manager.handleGameEnd(normal.room.id);
  assert.deepEqual(normal.room.gameState!.roundScores!.map(s => s.rank), [1, 1, 3, 4]);
  const perfect = fixture(t, [0, 5, 10, 12], 0);
  perfect.manager.handleGameEnd(perfect.room.id);
  assert.equal(perfect.room.gameState!.roundScores![0].rpChange, 92);
});

test('settling a round twice cannot credit RP twice', (t) => {
  const { manager, room, events } = fixture(t, [5, 10], 0);
  manager.handleGameEnd(room.id);
  const firstScores = [...room.cumulativeScores!];
  const firstEvents = events.filter(e => e.data.type === 'GAME_ENDED').length;
  manager.handleGameEnd(room.id);
  assert.deepEqual([...room.cumulativeScores!], firstScores);
  assert.equal(events.filter(e => e.data.type === 'GAME_ENDED').length, firstEvents);
});

test('round RP survive Redis snapshots and are included in restored player results', (t) => {
  const { manager, room, events } = fixture(t, [5, 10], 0);
  manager.handleGameEnd(room.id);
  const restored = RoomSnapshotCodec.deserialize(RoomSnapshotCodec.serialize(room));
  assert.equal(restored.gameState!.roundScores![0].rpChange, 50);
  // Exercise the same masking path used for reconnects and full-state requests.
  const state = (manager as any).getPersonalizedState(restored.gameState, 'p0');
  assert.deepEqual(state.players.map((p: any) => p.rpChange), [50, -50]);
  const event = events.find(e => e.target === 'p0' && e.data.type === 'GAME_ENDED')!;
  assert.equal(event.data.gameState.players[0].rpChange, room.cumulativeScores!.get('c0'));
  assert.equal(manager.backToLobby(room.id, 'p0'), true);
  assert.equal(manager.backToLobby(room.id, 'p1'), true);
  for (const id of ['p0', 'p1']) manager.setReady(room.id, id, true);
  assert.equal(manager.startGame(room.id, { fillBots: false }), true);
  assert.equal(room.gameState!.roundScores, undefined);
});

test('intermediate negative RP use truncation consistently for five and six players', (t) => {
  const five = fixture(t, [1, 2, 3, 4, 5]);
  five.manager.handleGameEnd(five.room.id);
  assert.equal(five.room.gameState!.roundScores![3].rpChange, -59);
  const six = fixture(t, [1, 2, 3, 4, 5, 6]);
  six.manager.handleGameEnd(six.room.id);
  assert.equal(six.room.gameState!.roundScores![4].rpChange, -74);
});
