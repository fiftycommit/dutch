/**
 * Fichier de test pour vérifier que tous les imports fonctionnent correctement
 */

// Test des imports depuis l'index
import { GameLogic, BotAI, BotDifficulty } from './index';

// Test des imports depuis les modèles
import {
  GameState,
  createGameState,
  GameMode,
  GamePhase,
  Difficulty,
  addToHistory,
  getCurrentPlayer,
} from '../models/GameState';

import {
  Player,
  createPlayer,
  BotBehavior,
  BotSkillLevel,
  calculateScore,
} from '../models/Player';

import {
  PlayingCard,
  createCard,
  createFullDeck,
  cardMatches,
} from '../models/Card';

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
  { name: 'GameLogic.initializeGame', value: typeof GameLogic.initializeGame === 'function' },
  { name: 'BotAI.playBotTurn', value: typeof BotAI.playBotTurn === 'function' },
  { name: 'BotDifficulty.bronze', value: typeof BotDifficulty.bronze === 'object' },
  { name: 'GameMode.quick', value: GameMode.quick === 0 },
  { name: 'GamePhase.playing', value: GamePhase.playing === 1 },
  { name: 'BotBehavior.balanced', value: BotBehavior.balanced === 2 },
  { name: 'BotSkillLevel.gold', value: BotSkillLevel.gold === 2 },
  { name: 'createPlayer', value: typeof createPlayer === 'function' },
  { name: 'createFullDeck', value: typeof createFullDeck === 'function' },
];

console.log('\n=== Tests de validation ===');
let allPassed = true;
for (const test of tests) {
  const status = test.value ? '✓' : '✗';
  console.log(`  ${status} ${test.name}`);
  if (!test.value) allPassed = false;
}

if (allPassed) {
  console.log('\n✓ Tous les tests ont réussi!');
  process.exit(0);
} else {
  console.log('\n✗ Certains tests ont échoué');
  process.exit(1);
}
