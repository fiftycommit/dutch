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
            // Récupérer le joueur ciblé avant d'utiliser le pouvoir
            const targetPlayer = room.gameState.players[data.targetPlayerIndex];
            const drawnCard = room.gameState.drawnCard;
            // Déterminer le type de pouvoir basé sur la valeur de la carte
            let powerType = 'unknown';
            if (drawnCard) {
                if (drawnCard.value === 'V') {
                    powerType = 'swap_adjacent'; // Valet : Échanger des cartes adjacentes
                }
                else if (drawnCard.value === 'D') {
                    powerType = 'peek'; // Dame : Regarder une carte (si implémenté ainsi, sinon voir GameLogic)
                }
                else if (drawnCard.value === '7') {
                    powerType = 'spy'; // 7 : Espionner une carte
                }
                else if (drawnCard.value === '10' || drawnCard.value === 'R') {
                    // 10 ou Roi (selon règles, ici R sembait être swap dans le code original, mais 10 est souvent échange)
                    // Le code original avait R = swap. On garde la compatibilité si c'est ce qui est voulu,
                    // mais GameLogic.ts dit: 10 (swap), V (exchange), JOKER (shuffle), 7 (spy).
                    // On va se fier à GameLogic.ts pour la vérité terrain.
                    if (drawnCard.value === '10')
                        powerType = 'swap';
                    if (drawnCard.value === 'R')
                        powerType = 'swap'; // Si R est aussi swap ?
                }
                else if (drawnCard.value === 'JOKER') {
                    powerType = 'joker'; // Pouvoir Joker
                }
            }
            // Si c'est un 7 (spy), on doit capturer la carte retournée par GameLogic
            // GameLogic.useSpecialPower ne retourne rien mais met à jour lastSpiedCard dans room.gameState
            // On vérifiera après l'appel.
            roomManager.recordPlayerAction(data.roomCode, socket.id);
            GameLogic_1.GameLogic.useSpecialPower(room.gameState, data.targetPlayerIndex, data.targetCardIndex);
            // Notifier le joueur ciblé qu'un pouvoir a été utilisé sur lui
            if (targetPlayer && targetPlayer.isHuman && targetPlayer.id !== currentPlayer.id) {
                socket.to(targetPlayer.id).emit('special_power:targeted', {
                    byPlayerId: currentPlayer.id,
                    byPlayerName: currentPlayer.name,
                    powerType,
                    targetCardIndex: data.targetCardIndex,
                    roomCode: data.roomCode,
                });
            }
            roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT', {
                specialPowerUsed: {
                    byPlayerId: currentPlayer.id,
                    byPlayerName: currentPlayer.name,
                    targetPlayerId: targetPlayer?.id,
                    targetPlayerName: targetPlayer?.name,
                    powerType,
                },
            });
            // Si c'est un pouvoir d'espionnage (7), on renvoie l'info au joueur qui a espionné
            if (powerType === 'spy' && room.gameState.lastSpiedCard) {
                socket.emit('game:spied_card', {
                    roomCode: data.roomCode,
                    card: room.gameState.lastSpiedCard,
                    targetPlayerName: targetPlayer?.name ?? 'Anonyme'
                });
            }
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
    socket.on('game:complete_swap', async (data) => {
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
            GameLogic_1.GameLogic.completeSwap(room.gameState, data.ownCardIndex);
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
            console.error('Error complete_swap:', error);
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
