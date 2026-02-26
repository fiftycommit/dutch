import { Socket } from 'socket.io';
import { RoomManager } from '../services/RoomManager';
import { GameLogic } from '../services/GameLogic';
import { GamePhase, getCurrentPlayer } from '../models/GameState';
import { Player } from '../models/Player';
import { SecurityService } from '../services/SecurityService';

export function setupGameHandler(socket: Socket, roomManager: RoomManager) {
  socket.on('game:draw_card', async (data) => {
    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) return;
      const room = roomManager.getRoom(data.roomCode);
      if (!room || !room.gameState) return;

      const currentPlayer = getCurrentPlayer(room.gameState);
      if (currentPlayer.id !== socket.id) return;
      if (currentPlayer.isSpectator) return;

      roomManager.recordPlayerAction(data.roomCode, socket.id);

      GameLogic.drawCard(room.gameState);
      roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT');
    } catch (error) {
      console.error('Error draw_card:', error);
    }
  });

  socket.on('game:replace_card', async (data) => {
    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) return;
      const room = roomManager.getRoom(data.roomCode);
      if (!room || !room.gameState) return;

      const currentPlayer = getCurrentPlayer(room.gameState);
      if (currentPlayer.id !== socket.id) return;
      if (currentPlayer.isSpectator) return;

      roomManager.recordPlayerAction(data.roomCode, socket.id);

      GameLogic.replaceCard(room.gameState, data.cardIndex);
      roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT');

      if (room.gameState.phase === GamePhase.ended) {
        roomManager.handleGameEnd(data.roomCode);
        return;
      }

      if (room.gameState.phase === GamePhase.reaction) {
        const reactionTime =
          typeof room.settings?.reactionTimeMs === 'number'
            ? room.settings.reactionTimeMs
            : 3000;
        roomManager.startReactionTimer(data.roomCode, reactionTime);
        return;
      }

      await roomManager.checkAndPlayBotTurn(data.roomCode);
    } catch (error) {
      console.error('Error replace_card:', error);
    }
  });

  socket.on('game:discard_card', async (data) => {
    try {
      console.log(`[DISCARD] Received from ${socket.id}, roomCode=${data.roomCode}`);
      if (!await SecurityService.checkEventRateLimit(socket.id)) {
        console.log(`[DISCARD] BLOCKED: Rate limited for ${socket.id}`);
        return;
      }
      const room = roomManager.getRoom(data.roomCode);
      if (!room || !room.gameState) {
        console.log(`[DISCARD] BLOCKED: Room not found or no gameState`);
        return;
      }

      const currentPlayer = getCurrentPlayer(room.gameState);
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
      GameLogic.discardDrawnCard(room.gameState);
      console.log(`[DISCARD] After: phase=${room.gameState.phase}, isWaitingForSpecialPower=${room.gameState.isWaitingForSpecialPower}`);

      roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT');

      if (room.gameState.phase === GamePhase.ended) {
        roomManager.handleGameEnd(data.roomCode);
        return;
      }

      if (room.gameState.phase === GamePhase.reaction) {
        const reactionTime =
          typeof room.settings?.reactionTimeMs === 'number'
            ? room.settings.reactionTimeMs
            : 3000;
        console.log(`[DISCARD] Starting reaction timer: ${reactionTime}ms`);
        roomManager.startReactionTimer(data.roomCode, reactionTime);
        return;
      }

      console.log(`[DISCARD] No reaction phase, checking bot turn`);
      await roomManager.checkAndPlayBotTurn(data.roomCode);
    } catch (error) {
      console.error('Error discard_card:', error);
    }
  });

  socket.on('game:take_from_discard', async (data) => {
    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) return;
      const room = roomManager.getRoom(data.roomCode);
      if (!room || !room.gameState) return;

      const currentPlayer = getCurrentPlayer(room.gameState);
      if (currentPlayer.id !== socket.id) return;
      if (currentPlayer.isSpectator) return;

      roomManager.recordPlayerAction(data.roomCode, socket.id);

      GameLogic.takeFromDiscard(room.gameState);
      roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT');

      await roomManager.checkAndPlayBotTurn(data.roomCode);
    } catch (error) {
      console.error('Error take_from_discard:', error);
    }
  });

  socket.on('game:call_dutch', async (data) => {
    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) return;
      const room = roomManager.getRoom(data.roomCode);
      if (!room || !room.gameState) return;

      const player = room.gameState.players.find(
        (p: Player) => p.id === socket.id
      );
      if (!player || player.isSpectator) return;

      roomManager.recordPlayerAction(data.roomCode, socket.id);

      GameLogic.callDutch(room.gameState, player.id);
      roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT', {
        message: `${player.name} appelle DUTCH !`,
      });

      if (room.gameState.phase === GamePhase.ended) {
        roomManager.handleGameEnd(data.roomCode);
      }
    } catch (error) {
      console.error('Error call_dutch:', error);
    }
  });

  socket.on('game:attempt_match', async (data) => {
    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) return;
      // Rate limit spécifique pour éviter le spam de matchs (500ms entre chaque)
      if (!await SecurityService.checkMatchRateLimit(socket.id)) {
        console.log(`[MATCH] Rate limited for ${socket.id} - too many match attempts`);
        return;
      }
      const room = roomManager.getRoom(data.roomCode);
      if (!room || !room.gameState) return;

      if (room.gameState.phase !== GamePhase.reaction) return;

      const player = room.gameState.players.find(
        (p: Player) => p.id === socket.id
      );
      if (!player || player.isSpectator) return;

      roomManager.recordPlayerAction(data.roomCode, socket.id);

      GameLogic.attemptMatch(room.gameState, player.id, data.cardIndex);
      roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT');
    } catch (error) {
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
      if (!await SecurityService.checkEventRateLimit(socket.id)) return;
      const room = roomManager.getRoom(data.roomCode);
      if (!room || !room.gameState) return;

      const currentPlayer = getCurrentPlayer(room.gameState);
      if (currentPlayer.id !== socket.id) return;
      if (currentPlayer.isSpectator) return;

      const specialCard = room.gameState.specialCardToActivate;
      if (!specialCard) return;

      roomManager.recordPlayerAction(data.roomCode, socket.id);

      // Appeler useSpecialPower avec les données appropriées
      const result = GameLogic.useSpecialPower(room.gameState, {
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
            const io = roomManager.getIO();
            io.to(spiedPlayer.id).emit('special_power:spy_notification', {
              byPlayerName: currentPlayer.name,
              cardIndex: data.targetCardIndex,
              roomCode: data.roomCode,
            });
          }
        }
      }

      // Notifications Valet : prévenir les joueurs affectés
      if (result.affectedPlayers && result.affectedPlayers.length > 0) {
        const io = roomManager.getIO();
        for (const affected of result.affectedPlayers) {
          const affectedPlayer = room.gameState.players.find(p => p.id === affected.playerId);
          if (affectedPlayer && affectedPlayer.isHuman) {
            io.to(affected.playerId).emit('special_power:swap_notification', {
              byPlayerName: currentPlayer.name,
              cardIndex: affected.cardIndex,
              swapPartnerName: affected.swapPartnerName,
              receivedCardPosition: affected.receivedCardPosition,
              roomCode: data.roomCode,
            });
          }
        }
      }

      // Notification Joker : prévenir le joueur mélangé
      if (result.shuffledPlayer) {
        const io = roomManager.getIO();
        const shuffledPlayer = room.gameState.players.find(p => p.id === result.shuffledPlayer!.playerId);
        if (shuffledPlayer && shuffledPlayer.isHuman) {
          io.to(result.shuffledPlayer.playerId).emit('special_power:joker_notification', {
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

      if (room.gameState.phase === GamePhase.ended) {
        roomManager.handleGameEnd(data.roomCode);
        return;
      }

      if (room.gameState.phase === GamePhase.reaction) {
        const baseReactionTime =
          typeof room.settings?.reactionTimeMs === 'number'
            ? room.settings.reactionTimeMs
            : 3000;

        // Le temps passé par le joueur à sélectionner le pouvoir est rajouté 
        // à son temps de réaction réel, jusqu'à une limite (ex: 15s max)
        const powerStartTime = room.gameState.specialPowerStartTime ?? Date.now();
        const elapsedSelectingPowerMs = Date.now() - powerStartTime;
        // On limite l'extension à 15s pour éviter l'abus, même si le client a lui-même un timeout de pouvoir spécial
        const reactionTime = baseReactionTime + Math.min(elapsedSelectingPowerMs, 15000);

        roomManager.startReactionTimer(data.roomCode, reactionTime);
        return;
      }

      await roomManager.checkAndPlayBotTurn(data.roomCode);
    } catch (error) {
      console.error('Error use_special_power:', error);
    }
  });

  socket.on('game:skip_special_power', async (data) => {
    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) return;
      const room = roomManager.getRoom(data.roomCode);
      if (!room || !room.gameState) return;

      const currentPlayer = getCurrentPlayer(room.gameState);
      if (currentPlayer.id !== socket.id) return;
      if (currentPlayer.isSpectator) return;

      roomManager.recordPlayerAction(data.roomCode, socket.id);

      GameLogic.skipSpecialPower(room.gameState);
      roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT');

      if (room.gameState.phase === GamePhase.ended) {
        roomManager.handleGameEnd(data.roomCode);
        return;
      }

      if (room.gameState.phase === GamePhase.reaction) {
        const baseReactionTime =
          typeof room.settings?.reactionTimeMs === 'number'
            ? room.settings.reactionTimeMs
            : 3000;

        const powerStartTime = room.gameState.specialPowerStartTime ?? Date.now();
        const elapsedSelectingPowerMs = Date.now() - powerStartTime;
        const reactionTime = baseReactionTime + Math.min(elapsedSelectingPowerMs, 15000);

        roomManager.startReactionTimer(data.roomCode, reactionTime);
        return;
      }

      await roomManager.checkAndPlayBotTurn(data.roomCode);
    } catch (error) {
      console.error('Error skip_special_power:', error);
    }
  });


  socket.on('game:pause', async (data) => {
    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) return;
      const room = roomManager.getRoom(data.roomCode);
      if (!room) return;

      // Allow any player to pause? Or only host? Users usually want anyone to pause in casual games.
      // Let's allow any non-spectator player.
      const player = room.players.find(p => p.id === socket.id);
      if (!player || player.isSpectator) return;

      roomManager.pauseGame(data.roomCode, socket.id, player.name);
    } catch (error) {
      console.error('Error game:pause:', error);
    }
  });

  socket.on('game:resume', async (data) => {
    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) return;
      const room = roomManager.getRoom(data.roomCode);
      if (!room) return;

      const player = room.players.find(p => p.id === socket.id);
      if (!player || player.isSpectator) return;

      roomManager.resumeGame(data.roomCode, socket.id, player.name);
    } catch (error) {
      console.error('Error game:resume:', error);
    }
  });

  socket.on('game:forfeit', async (data) => {
    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) return;
      // data: { roomCode }
      roomManager.forfeitGame(data.roomCode, socket.id);
    } catch (error) {
      console.error('Error game:forfeit:', error);
    }
  });

  // Handle player ready after memorization phase
  socket.on('player:ready', async (data) => {
    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) return;
      const room = roomManager.getRoom(data.roomCode);
      if (!room || !room.gameState) return;

      const player = room.players.find(p => p.id === socket.id);
      if (!player) return;
      if (player.isSpectator) return;

      roomManager.recordPlayerAction(data.roomCode, socket.id);
      const success = roomManager.markPlayerReady(data.roomCode, socket.id);
      if (success) {
        console.log(`[READY] Player ${player.name} marked ready in room ${data.roomCode}`);
      }
    } catch (error) {
      console.error('Error player:ready:', error);
    }
  });

  // Handle room settings update (host only)
  socket.on('room:update_settings', async (data) => {
    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) return;
      const { roomCode, botDifficulty, luckDifficulty } = data;

      const success = roomManager.updateRoomSettings(roomCode, socket.id, {
        botDifficulty,
        luckDifficulty,
      });

      if (success) {
        console.log(`[SETTINGS] Host ${socket.id} updated settings in room ${roomCode}`);
      }
    } catch (error) {
      console.error('Error room:update_settings:', error);
    }
  });
}

