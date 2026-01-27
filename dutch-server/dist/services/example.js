"use strict";
/**
 * Exemple d'utilisation des services de jeu Dutch
 *
 * Ce fichier montre comment utiliser GameLogic et BotAI
 * pour simuler une partie de Dutch côté serveur.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.simulateGame = simulateGame;
const index_1 = require("./index");
const GameState_1 = require("../models/GameState");
const Player_1 = require("../models/Player");
async function simulateGame() {
    console.log('=== Simulation d\'une partie de Dutch ===\n');
    // 1. Créer les joueurs
    const players = [
        (0, Player_1.createPlayer)('player-1', 'Alice (Humain)', true, 0),
        (0, Player_1.createPlayer)('bot-1', 'Bob (Bot Équilibré)', false, 1, Player_1.BotBehavior.balanced, Player_1.BotSkillLevel.gold),
        (0, Player_1.createPlayer)('bot-2', 'Charlie (Bot Agressif)', false, 2, Player_1.BotBehavior.aggressive, Player_1.BotSkillLevel.silver),
    ];
    console.log('Joueurs créés :');
    players.forEach(p => {
        const type = p.isHuman ? 'Humain' : `Bot ${Player_1.BotBehavior[p.botBehavior]} (${Player_1.BotSkillLevel[p.botSkillLevel]})`;
        console.log(`  - ${p.name} (${type})`);
    });
    console.log();
    // 2. Créer et initialiser l'état du jeu
    const gameState = (0, GameState_1.createGameState)(players, GameState_1.GameMode.quick, GameState_1.Difficulty.medium);
    console.log('État du jeu créé avec :');
    console.log(`  - Mode : ${GameState_1.GameMode[gameState.gameMode]}`);
    console.log(`  - Difficulté : ${GameState_1.Difficulty[gameState.difficulty]}`);
    console.log();
    index_1.GameLogic.initializeGame(gameState);
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
            index_1.GameLogic.drawCard(gameState);
            if (gameState.drawnCard) {
                index_1.GameLogic.discardDrawnCard(gameState);
            }
        }
        else {
            console.log(`Tour ${turn} : ${currentPlayer.name} (Bot) joue...`);
            await index_1.BotAI.playBotTurn(gameState);
            // Afficher les actions
            if (gameState.actionHistory.length > 0) {
                console.log(`  Actions: ${gameState.actionHistory[0]}`);
            }
        }
        // Passer au joueur suivant
        if (gameState.phase !== GameState_1.GamePhase.ended && gameState.phase !== GameState_1.GamePhase.dutchCalled) {
            index_1.GameLogic.nextPlayer(gameState);
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
    console.log(`Phase : ${GameState_1.GamePhase[gameState.phase]}`);
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
    index_1.BotAI.clearAllBotMemories();
    console.log('Mémoires effacées.');
    console.log();
    console.log('=== Fin de la simulation ===');
}
// Exécuter la simulation si ce fichier est lancé directement
if (require.main === module) {
    simulateGame().catch(console.error);
}
