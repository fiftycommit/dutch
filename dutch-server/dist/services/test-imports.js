"use strict";
/**
 * Fichier de test pour vérifier que tous les imports fonctionnent correctement
 */
Object.defineProperty(exports, "__esModule", { value: true });
// Test des imports depuis l'index
const index_1 = require("./index");
// Test des imports depuis les modèles
const GameState_1 = require("../models/GameState");
const Player_1 = require("../models/Player");
const Card_1 = require("../models/Card");
console.log('✓ Tous les imports ont réussi!');
console.log('\nModules disponibles :');
console.log('  - GameLogic');
console.log('  - BotAI');
console.log('  - BotDifficulty');
console.log('\nModèles :');
console.log('  - GameState, GameMode, GamePhase, Difficulty');
console.log('  - Player, BotBehavior, BotSkillLevel');
console.log('  - PlayingCard');
console.log('\nFonctions utilitaires :');
console.log('  - createGameState, addToHistory, getCurrentPlayer');
console.log('  - createPlayer, calculateScore');
console.log('  - createCard, createFullDeck, cardMatches');
// Test de base pour vérifier que tout est défini
const tests = [
    { name: 'GameLogic.initializeGame', value: typeof index_1.GameLogic.initializeGame === 'function' },
    { name: 'BotAI.playBotTurn', value: typeof index_1.BotAI.playBotTurn === 'function' },
    { name: 'BotDifficulty.bronze', value: typeof index_1.BotDifficulty.bronze === 'object' },
    { name: 'GameMode.quick', value: GameState_1.GameMode.quick === 0 },
    { name: 'GamePhase.playing', value: GameState_1.GamePhase.playing === 1 },
    { name: 'BotBehavior.balanced', value: Player_1.BotBehavior.balanced === 2 },
    { name: 'BotSkillLevel.gold', value: Player_1.BotSkillLevel.gold === 2 },
    { name: 'createPlayer', value: typeof Player_1.createPlayer === 'function' },
    { name: 'createFullDeck', value: typeof Card_1.createFullDeck === 'function' },
];
console.log('\n=== Tests de validation ===');
let allPassed = true;
for (const test of tests) {
    const status = test.value ? '✓' : '✗';
    console.log(`  ${status} ${test.name}`);
    if (!test.value)
        allPassed = false;
}
if (allPassed) {
    console.log('\n✓ Tous les tests ont réussi!');
    process.exit(0);
}
else {
    console.log('\n✗ Certains tests ont échoué');
    process.exit(1);
}
