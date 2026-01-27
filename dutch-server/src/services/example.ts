/**
 * Exemple d'utilisation des services de jeu Dutch
 *
 * Ce fichier montre comment utiliser GameLogic et BotAI
 * pour simuler une partie de Dutch côté serveur.
 */

import { GameLogic, BotAI } from './index';
import { GameState, createGameState, GameMode, GamePhase, Difficulty } from '../models/GameState';
import { Player, createPlayer, BotBehavior, BotSkillLevel } from '../models/Player';

async function simulateGame() {
  console.log('=== Simulation d\'une partie de Dutch ===\n');

  // 1. Créer les joueurs
  const players: Player[] = [
    createPlayer('player-1', 'Alice (Humain)', true, 0),
    createPlayer('bot-1', 'Bob (Bot Équilibré)', false, 1, BotBehavior.balanced, BotSkillLevel.gold),
    createPlayer('bot-2', 'Charlie (Bot Agressif)', false, 2, BotBehavior.aggressive, BotSkillLevel.silver),
  ];

  console.log('Joueurs créés :');
  players.forEach(p => {
    const type = p.isHuman ? 'Humain' : `Bot ${BotBehavior[p.botBehavior!]} (${BotSkillLevel[p.botSkillLevel!]})`;
    console.log(`  - ${p.name} (${type})`);
  });
  console.log();

  // 2. Créer et initialiser l'état du jeu
  const gameState = createGameState(players, GameMode.quick, Difficulty.medium);
  console.log('État du jeu créé avec :');
  console.log(`  - Mode : ${GameMode[gameState.gameMode]}`);
  console.log(`  - Difficulté : ${Difficulty[gameState.difficulty]}`);
  console.log();

  GameLogic.initializeGame(gameState);
  console.log('Partie initialisée !');
  console.log(`  - ${gameState.deck.length} cartes dans la pioche`);
  console.log(`  - ${gameState.discardPile.length} carte(s) dans la défausse`);
  console.log(`  - Joueur actuel : ${gameState.players[gameState.currentPlayerIndex].name}`);
  console.log();

  // 3. Afficher les mains de départ
  console.log('Mains de départ :');
  for (const player of gameState.players) {
    const handStr = player.hand.map(c => `${c.value}${c.suit[0]}`).join(', ');
    const knownStr = player.knownCards.map((k, i) => k ? '✓' : '?').join(' ');
    console.log(`  ${player.name}: [${handStr}] (connu: ${knownStr})`);
  }
  console.log();

  // 4. Simuler quelques tours de bots
  console.log('=== Simulation de 3 tours de bots ===\n');

  for (let turn = 1; turn <= 3; turn++) {
    const currentPlayer = gameState.players[gameState.currentPlayerIndex];

    if (currentPlayer.isHuman) {
      console.log(`Tour ${turn} : ${currentPlayer.name} (Humain) - Action manuelle requise`);
      // Dans un vrai serveur, on attendrait l'action du joueur humain
      GameLogic.drawCard(gameState);
      if (gameState.drawnCard) {
        GameLogic.discardDrawnCard(gameState);
      }
    } else {
      console.log(`Tour ${turn} : ${currentPlayer.name} (Bot) joue...`);
      await BotAI.playBotTurn(gameState);

      // Afficher les actions
      if (gameState.actionHistory.length > 0) {
        console.log(`  Actions: ${gameState.actionHistory[0]}`);
      }
    }

    // Passer au joueur suivant
    if (gameState.phase !== GamePhase.ended && gameState.phase !== GamePhase.dutchCalled) {
      GameLogic.nextPlayer(gameState);
    }

    console.log();
  }

  // 5. Afficher l'historique des actions
  console.log('=== Historique des 5 dernières actions ===');
  gameState.actionHistory.slice(0, 5).forEach(action => {
    console.log(`  ${action}`);
  });
  console.log();

  // 6. Afficher l'état final
  console.log('=== État actuel de la partie ===');
  console.log(`Phase : ${GamePhase[gameState.phase]}`);
  console.log(`Cartes restantes dans la pioche : ${gameState.deck.length}`);
  console.log(`Défausse : ${gameState.discardPile.length} carte(s)`);
  console.log();

  console.log('Mains actuelles :');
  for (const player of gameState.players) {
    const handStr = player.hand.map(c => `${c.value}${c.suit[0]}`).join(', ');
    const score = player.hand.reduce((sum, card) => sum + card.points, 0);
    console.log(`  ${player.name}: [${handStr}] (${player.hand.length} cartes, ${score} points)`);
  }
  console.log();

  // 7. Nettoyer la mémoire des bots
  console.log('Nettoyage des mémoires des bots...');
  BotAI.clearAllBotMemories();
  console.log('Mémoires effacées.');
  console.log();

  console.log('=== Fin de la simulation ===');
}

// Exécuter la simulation si ce fichier est lancé directement
if (require.main === module) {
  simulateGame().catch(console.error);
}

export { simulateGame };
