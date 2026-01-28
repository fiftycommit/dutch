"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.setupGameHandler = setupGameHandler;
const GameLogic_1 = require("../services/GameLogic");
const GameState_1 = require("../models/GameState");
const SecurityService_1 = require("../services/SecurityService");
function setupGameHandler(socket, roomManager) {
    socket.on('game:draw_card', async (data) => {
        try {
            if (!await SecurityService_1.SecurityService.checkEventRateLimit(socket.id))
                return;
            const room = roomManager.getRoom(data.roomCode);
            if (!room || !room.gameState)
                return;
            const currentPlayer = (0, GameState_1.getCurrentPlayer)(room.gameState);
            if (currentPlayer.id !== socket.id)
                return;
            if (currentPlayer.isSpectator)
                return;
            roomManager.recordPlayerAction(data.roomCode, socket.id);
            GameLogic_1.GameLogic.drawCard(room.gameState);
            roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT');
        }
        catch (error) {
            console.error('Error draw_card:', error);
        }
    });
    socket.on('game:replace_card', async (data) => {
        try {
            if (!await SecurityService_1.SecurityService.checkEventRateLimit(socket.id))
                return;
            const room = roomManager.getRoom(data.roomCode);
            if (!room || !room.gameState)
                return;
            const currentPlayer = (0, GameState_1.getCurrentPlayer)(room.gameState);
            if (currentPlayer.id !== socket.id)
                return;
            if (currentPlayer.isSpectator)
                return;
            roomManager.recordPlayerAction(data.roomCode, socket.id);
            GameLogic_1.GameLogic.replaceCard(room.gameState, data.cardIndex);
            roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT');
            if (room.gameState.phase === GameState_1.GamePhase.ended) {
                roomManager.handleGameEnd(data.roomCode);
                return;
            }
            if (room.gameState.phase === GameState_1.GamePhase.reaction) {
                const reactionTime = typeof room.settings?.reactionTimeMs === 'number'
                    ? room.settings.reactionTimeMs
                    : 3000;
                roomManager.startReactionTimer(data.roomCode, reactionTime);
                return;
            }
            await roomManager.checkAndPlayBotTurn(data.roomCode);
        }
        catch (error) {
            console.error('Error replace_card:', error);
        }
    });
    socket.on('game:discard_card', async (data) => {
        try {
            console.log(`[DISCARD] Received from ${socket.id}, roomCode=${data.roomCode}`);
            if (!await SecurityService_1.SecurityService.checkEventRateLimit(socket.id)) {
                console.log(`[DISCARD] BLOCKED: Rate limited for ${socket.id}`);
                return;
            }
            const room = roomManager.getRoom(data.roomCode);
            if (!room || !room.gameState) {
                console.log(`[DISCARD] BLOCKED: Room not found or no gameState`);
                return;
            }
            const currentPlayer = (0, GameState_1.getCurrentPlayer)(room.gameState);
            console.log(`[DISCARD] currentPlayer.id=${currentPlayer.id}, socket.id=${socket.id}`);
            if (currentPlayer.id !== socket.id) {
                console.log(`[DISCARD] BLOCKED: Not current player's turn`);
                return;
            }
            if (currentPlayer.isSpectator) {
                console.log(`[DISCARD] BLOCKED: Player is spectator`);
                return;
            }
            roomManager.recordPlayerAction(data.roomCode, socket.id);
            console.log(`[DISCARD] Before: phase=${room.gameState.phase}, isWaitingForSpecialPower=${room.gameState.isWaitingForSpecialPower}`);
            GameLogic_1.GameLogic.discardDrawnCard(room.gameState);
            console.log(`[DISCARD] After: phase=${room.gameState.phase}, isWaitingForSpecialPower=${room.gameState.isWaitingForSpecialPower}`);
            roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT');
            if (room.gameState.phase === GameState_1.GamePhase.ended) {
                roomManager.handleGameEnd(data.roomCode);
                return;
            }
            if (room.gameState.phase === GameState_1.GamePhase.reaction) {
                const reactionTime = typeof room.settings?.reactionTimeMs === 'number'
                    ? room.settings.reactionTimeMs
                    : 3000;
                console.log(`[DISCARD] Starting reaction timer: ${reactionTime}ms`);
                roomManager.startReactionTimer(data.roomCode, reactionTime);
                return;
            }
            console.log(`[DISCARD] No reaction phase, checking bot turn`);
            await roomManager.checkAndPlayBotTurn(data.roomCode);
        }
        catch (error) {
            console.error('Error discard_card:', error);
        }
    });
    socket.on('game:take_from_discard', async (data) => {
        try {
            if (!await SecurityService_1.SecurityService.checkEventRateLimit(socket.id))
                return;
            const room = roomManager.getRoom(data.roomCode);
            if (!room || !room.gameState)
                return;
            const currentPlayer = (0, GameState_1.getCurrentPlayer)(room.gameState);
            if (currentPlayer.id !== socket.id)
                return;
            if (currentPlayer.isSpectator)
                return;
            roomManager.recordPlayerAction(data.roomCode, socket.id);
            GameLogic_1.GameLogic.takeFromDiscard(room.gameState);
            roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT');
            await roomManager.checkAndPlayBotTurn(data.roomCode);
        }
        catch (error) {
            console.error('Error take_from_discard:', error);
        }
    });
    socket.on('game:call_dutch', async (data) => {
        try {
            if (!await SecurityService_1.SecurityService.checkEventRateLimit(socket.id))
                return;
            const room = roomManager.getRoom(data.roomCode);
            if (!room || !room.gameState)
                return;
            const player = room.gameState.players.find((p) => p.id === socket.id);
            if (!player || player.isSpectator)
                return;
            roomManager.recordPlayerAction(data.roomCode, socket.id);
            GameLogic_1.GameLogic.callDutch(room.gameState, player.id);
            roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT', {
                message: `${player.name} appelle DUTCH !`,
            });
            if (room.gameState.phase === GameState_1.GamePhase.ended) {
                roomManager.handleGameEnd(data.roomCode);
            }
        }
        catch (error) {
            console.error('Error call_dutch:', error);
        }
    });
    socket.on('game:attempt_match', async (data) => {
        try {
            if (!await SecurityService_1.SecurityService.checkEventRateLimit(socket.id))
                return;
            const room = roomManager.getRoom(data.roomCode);
            if (!room || !room.gameState)
                return;
            if (room.gameState.phase !== GameState_1.GamePhase.reaction)
                return;
            const player = room.gameState.players.find((p) => p.id === socket.id);
            if (!player || player.isSpectator)
                return;
            roomManager.recordPlayerAction(data.roomCode, socket.id);
            GameLogic_1.GameLogic.attemptMatch(room.gameState, player.id, data.cardIndex);
            roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT');
        }
        catch (error) {
            console.error('Error attempt_match:', error);
        }
    });
    /**
     * Handler pour les pouvoirs spéciaux - Aligné sur le mode solo
     *
     * Format des données attendues selon la carte :
     * - Carte 7 : { roomCode, cardIndex } - Regarder sa propre carte
     * - Carte 10 : { roomCode, targetPlayerIndex, targetCardIndex } - Espionner un adversaire
     * - Carte V : { roomCode, player1Index, card1Index, player2Index, card2Index } - Échange universel
     * - JOKER : { roomCode, targetPlayerIndex } - Mélanger n'importe qui
     */
    socket.on('game:use_special_power', async (data) => {
        try {
            if (!await SecurityService_1.SecurityService.checkEventRateLimit(socket.id))
                return;
            const room = roomManager.getRoom(data.roomCode);
            if (!room || !room.gameState)
                return;
            const currentPlayer = (0, GameState_1.getCurrentPlayer)(room.gameState);
            if (currentPlayer.id !== socket.id)
                return;
            if (currentPlayer.isSpectator)
                return;
            const specialCard = room.gameState.specialCardToActivate;
            if (!specialCard)
                return;
            roomManager.recordPlayerAction(data.roomCode, socket.id);
            // Appeler useSpecialPower avec les données appropriées
            const result = GameLogic_1.GameLogic.useSpecialPower(room.gameState, {
                cardIndex: data.cardIndex,
                targetPlayerIndex: data.targetPlayerIndex,
                targetCardIndex: data.targetCardIndex,
                player1Index: data.player1Index,
                card1Index: data.card1Index,
                player2Index: data.player2Index,
                card2Index: data.card2Index,
            });
            // Envoyer la carte espionnée au joueur (pour 7 et 10)
            if (result.spiedCard) {
                socket.emit('game:spied_card', {
                    roomCode: data.roomCode,
                    card: result.spiedCard,
                    targetPlayerName: specialCard.value === '7' ? 'vous' :
                        (data.targetPlayerIndex !== undefined ?
                            room.gameState.players[data.targetPlayerIndex]?.name : 'Anonyme')
                });
                // Notification au joueur espionné (pouvoir 10 uniquement)
                if (specialCard.value === '10' && data.targetPlayerIndex !== undefined) {
                    const spiedPlayer = room.gameState.players[data.targetPlayerIndex];
                    if (spiedPlayer && spiedPlayer.isHuman && spiedPlayer.id !== currentPlayer.id) {
                        socket.to(spiedPlayer.id).emit('special_power:spy_notification', {
                            byPlayerName: currentPlayer.name,
                            cardIndex: data.targetCardIndex,
                            roomCode: data.roomCode,
                        });
                    }
                }
            }
            // Notifications Valet : prévenir les joueurs affectés
            if (result.affectedPlayers && result.affectedPlayers.length > 0) {
                for (const affected of result.affectedPlayers) {
                    const affectedPlayer = room.gameState.players.find(p => p.id === affected.playerId);
                    if (affectedPlayer && affectedPlayer.isHuman) {
                        socket.to(affected.playerId).emit('special_power:swap_notification', {
                            byPlayerName: currentPlayer.name,
                            cardIndex: affected.cardIndex,
                            roomCode: data.roomCode,
                        });
                    }
                }
            }
            // Notification Joker : prévenir le joueur mélangé
            if (result.shuffledPlayer) {
                const shuffledPlayer = room.gameState.players.find(p => p.id === result.shuffledPlayer.playerId);
                if (shuffledPlayer && shuffledPlayer.isHuman) {
                    socket.to(result.shuffledPlayer.playerId).emit('special_power:joker_notification', {
                        byPlayerName: currentPlayer.name,
                        roomCode: data.roomCode,
                    });
                }
            }
            roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT', {
                specialPowerUsed: {
                    byPlayerId: currentPlayer.id,
                    byPlayerName: currentPlayer.name,
                    powerType: specialCard.value,
                },
            });
            if (room.gameState.phase === GameState_1.GamePhase.ended) {
                roomManager.handleGameEnd(data.roomCode);
                return;
            }
            if (room.gameState.phase === GameState_1.GamePhase.reaction) {
                const reactionTime = typeof room.settings?.reactionTimeMs === 'number'
                    ? room.settings.reactionTimeMs
                    : 3000;
                roomManager.startReactionTimer(data.roomCode, reactionTime);
                return;
            }
            await roomManager.checkAndPlayBotTurn(data.roomCode);
        }
        catch (error) {
            console.error('Error use_special_power:', error);
        }
    });
    socket.on('game:skip_special_power', async (data) => {
        try {
            if (!await SecurityService_1.SecurityService.checkEventRateLimit(socket.id))
                return;
            const room = roomManager.getRoom(data.roomCode);
            if (!room || !room.gameState)
                return;
            const currentPlayer = (0, GameState_1.getCurrentPlayer)(room.gameState);
            if (currentPlayer.id !== socket.id)
                return;
            if (currentPlayer.isSpectator)
                return;
            roomManager.recordPlayerAction(data.roomCode, socket.id);
            GameLogic_1.GameLogic.skipSpecialPower(room.gameState);
            roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT');
            if (room.gameState.phase === GameState_1.GamePhase.ended) {
                roomManager.handleGameEnd(data.roomCode);
                return;
            }
            if (room.gameState.phase === GameState_1.GamePhase.reaction) {
                const reactionTime = typeof room.settings?.reactionTimeMs === 'number'
                    ? room.settings.reactionTimeMs
                    : 3000;
                roomManager.startReactionTimer(data.roomCode, reactionTime);
                return;
            }
            await roomManager.checkAndPlayBotTurn(data.roomCode);
        }
        catch (error) {
            console.error('Error skip_special_power:', error);
        }
    });
    socket.on('game:pause', async (data) => {
        try {
            if (!await SecurityService_1.SecurityService.checkEventRateLimit(socket.id))
                return;
            const room = roomManager.getRoom(data.roomCode);
            if (!room)
                return;
            // Allow any player to pause? Or only host? Users usually want anyone to pause in casual games.
            // Let's allow any non-spectator player.
            const player = room.players.find(p => p.id === socket.id);
            if (!player || player.isSpectator)
                return;
            roomManager.pauseGame(data.roomCode, player.name);
        }
        catch (error) {
            console.error('Error game:pause:', error);
        }
    });
    socket.on('game:resume', async (data) => {
        try {
            if (!await SecurityService_1.SecurityService.checkEventRateLimit(socket.id))
                return;
            const room = roomManager.getRoom(data.roomCode);
            if (!room)
                return;
            const player = room.players.find(p => p.id === socket.id);
            if (!player || player.isSpectator)
                return;
            roomManager.resumeGame(data.roomCode, player.name);
        }
        catch (error) {
            console.error('Error game:resume:', error);
        }
    });
}
