"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const node_assert_1 = __importDefault(require("node:assert"));
const Player_1 = require("../models/Player");
const Card_1 = require("../models/Card");
(0, node_test_1.describe)('calculateScore', () => {
    (0, node_test_1.it)('calculates sum of card points for normal player', () => {
        // createPlayer(id, name, isHuman, position, ...)
        const player = (0, Player_1.createPlayer)('socket1', 'Player 1', true, 0);
        player.hand = [
            (0, Card_1.createCard)('hearts', '5'), // 5 pts
            (0, Card_1.createCard)('spades', 'D') // 12 pts (Queen/Dame is 12 in this game?) Check calculatePoints. 'D' is 12.
        ];
        // 5 + 12 = 17
        node_assert_1.default.strictEqual((0, Player_1.calculateScore)(player), 17);
    });
    (0, node_test_1.it)('returns 100 points for folded player', () => {
        const player = (0, Player_1.createPlayer)('socket2', 'Player 2', true, 1);
        player.hand = [(0, Card_1.createCard)('hearts', 'A')]; // 1 pt
        player.hasFolded = true;
        node_assert_1.default.strictEqual((0, Player_1.calculateScore)(player), 100);
    });
    (0, node_test_1.it)('returns 100 points for spectator player (who was playing)', () => {
        const player = (0, Player_1.createPlayer)('socket3', 'Player 3', true, 2);
        player.hand = [(0, Card_1.createCard)('clubs', '2')]; // 2 pts
        player.isSpectator = true;
        node_assert_1.default.strictEqual((0, Player_1.calculateScore)(player), 100);
    });
});
//# sourceMappingURL=player.score.test.js.map