import test from 'node:test';
import assert from 'node:assert/strict';
import { TimerManager } from '../services/TimerManager';
import { Room } from '../models/Room';
import { GamePhase } from '../models/GameState';

test('resuming a restored reaction uses the persisted time remaining', async (t) => {
  const room = { gameState: { phase: GamePhase.reaction, reactionTimeRemaining: 0 } } as Room;
  let complete!: () => void;
  const completed = new Promise<void>((resolve) => { complete = resolve; });
  let ended = false;
  const timers = new TimerManager({
    getRoom: () => room,
    broadcastGameState: () => {},
    endReactionPhase: async () => { ended = true; complete(); },
  });
  t.after(() => timers.clearTimer('room'));
  const timeout = setTimeout(() => complete(), 1000);
  t.after(() => clearTimeout(timeout));
  timers.resumeTimer('room');
  await completed;
  assert.equal(ended, true);
});

test('reaction timer retries a failed Redis lock without an unhandled rejection', async (t) => {
  const room = { gameState: { phase: GamePhase.reaction }, isPaused: false } as Room;
  let attempts = 0;
  let complete!: () => void;
  const completed = new Promise<void>((resolve) => { complete = resolve; });
  const timers = new TimerManager({
    getRoom: () => room,
    broadcastGameState: () => {},
    endReactionPhase: async () => {
      attempts++;
      if (attempts === 1) throw new Error('Redis lock timeout');
      room.gameState!.phase = GamePhase.playing;
      complete();
    },
  });
  t.after(() => timers.clearTimer('room'));
  timers.startReactionTimer('room', 0);
  const timeout = setTimeout(() => complete(), 3000);
  t.after(() => clearTimeout(timeout));
  await completed;
  assert.equal(attempts, 2);
  assert.equal(room.gameState!.phase, GamePhase.playing);
});
