import { describe, it } from 'node:test';
import assert from 'node:assert';
import { simulateGame } from '../services/example';

describe('example — simulateGame', () => {
  it('runs without error', async () => {
    // Redirect console.log to suppress output
    const origLog = console.log;
    console.log = () => {};
    try {
      await simulateGame();
      assert.ok(true);
    } finally {
      console.log = origLog;
    }
  });
});
