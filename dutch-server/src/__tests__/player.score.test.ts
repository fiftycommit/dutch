import { describe, it } from 'node:test';
import assert from 'node:assert';
import { calculateScore, createPlayer } from '../models/Player';
import { createCard } from '../models/Card';

describe('calculateScore', () => {
    it('calculates sum of card points for normal player', () => {
        // createPlayer(id, name, isHuman, position, ...)
        const player = createPlayer('socket1', 'Player 1', true, 0);
        player.hand = [
            createCard('hearts', '5'), // 5 pts
            createCard('spades', 'D')  // 12 pts (Queen/Dame is 12 in this game?) Check calculatePoints. 'D' is 12.
        ];
        // 5 + 12 = 17
        assert.strictEqual(calculateScore(player), 17);
    });

    it('returns 100 points for folded player', () => {
        const player = createPlayer('socket2', 'Player 2', true, 1);
        player.hand = [createCard('hearts', 'A')]; // 1 pt
        player.hasFolded = true;
        assert.strictEqual(calculateScore(player), 100);
    });

    it('returns 100 points for spectator player (who was playing)', () => {
        const player = createPlayer('socket3', 'Player 3', true, 2);
        player.hand = [createCard('clubs', '2')]; // 2 pts
        player.isSpectator = true;
        assert.strictEqual(calculateScore(player), 100);
    });
});

