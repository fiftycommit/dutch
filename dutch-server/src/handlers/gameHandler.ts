import { Socket } from 'socket.io';
import { RoomManager } from '../services/RoomManager';
import { GameLogic } from '../services/GameLogic';
import { GamePhase, getCurrentPlayer } from '../models/GameState';
import { Player } from '../models/Player';
import { SecurityService } from '../services/SecurityService';
import { createCard } from '../models/Card';

type ActionAck = (payload: Record<string, unknown>) => void;

function createActionReply(data: any, ack?: ActionAck): ActionAck {
  const actionId = data?.actionId;
  let ackSent = false;
  return (payload: Record<string, unknown>) => {
    if (ackSent || typeof ack !== 'function') return;
    ackSent = true;
    ack({ actionId, ...payload });
  };
}

function areTestHooksEnabled(): boolean {
  return process.env.NODE_ENV !== 'production' &&
    (process.env.E2E_TEST_HOOKS === '1' || process.env.AUTH_ABUSE_DISABLED === '1');
}

function cardsFromValues(values: unknown): ReturnType<typeof createCard>[] | null {
  if (!Array.isArray(values)) return null;
  const suits = ['hearts', 'diamonds', 'clubs', 'spades'];
  return values.map((value, index) => createCard(suits[index % suits.length], String(value)));
}

function readPhaseAfterMutation(gameState: { phase: GamePhase }): GamePhase {
  return gameState.phase;
}

export function setupGameHandler(socket: Socket, roomManager: RoomManager) {
  socket.on('test:force_special_power', async (data, ack?: ActionAck) => {
    const reply = createActionReply(data, ack);
    if (!areTestHooksEnabled()) {
      reply({ ok: false, error: 'test_hooks_disabled' });
      return;
    }

    try {
      await roomManager.withRoomMutation(data.roomCode, async (room) => {
        if (!room?.gameState) {
          reply({ ok: false, error: 'room_not_ready' });
          return;
        }

        const actorId = typeof data.actorId === 'string' ? data.actorId : socket.id;
        const actorIndex = room.gameState.players.findIndex((p: Player) => p.id === actorId);
        const requester = room.gameState.players.find((p: Player) => p.id === socket.id);
        if (actorIndex < 0 || !requester || requester.isSpectator) {
          reply({ ok: false, error: 'not_authorized' });
          return;
        }

        const handValuesByPlayer = data.hands && typeof data.hands === 'object'
          ? data.hands as Record<string, unknown>
          : {};
        for (const player of room.gameState.players) {
          const cards = cardsFromValues(handValuesByPlayer[player.id]);
          if (!cards) continue;
          player.hand = cards;
          player.knownCards = cards.map(() => false);
        }

        const power = String(data.power);
        if (!['7', '10', 'V', 'JOKER'].includes(power)) {
          reply({ ok: false, error: 'invalid_power' });
          return;
        }

        roomManager.clearReactionTimer(data.roomCode);
        roomManager.clearTurnTimer(data.roomCode);
        room.gameState.currentPlayerIndex = actorIndex;
        room.gameState.phase = GamePhase.specialPower;
        room.gameState.isWaitingForSpecialPower = true;
        room.gameState.specialCardToActivate = createCard(
          power === 'JOKER' ? 'joker' : 'hearts',
          power,
        );
        room.gameState.specialPowerPlayerId = null;
        room.gameState.drawnCard = null;
        room.gameState.lastSpiedCard = null;
        roomManager.broadcastGameState(data.roomCode, 'TEST_FORCE_SPECIAL_POWER');
        reply({ ok: true });
      });
    } catch (error) {
      console.error('Error test:force_special_power:', error);
      reply({ ok: false, error: 'internal_error' });
    }
  });

  socket.on('game:draw_card', async (data, ack?: (payload: Record<string, unknown>) => void) => {
    const reply = createActionReply(data, ack);

    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) {
        reply({ ok: false, error: 'rate_limited' });
        return;
      }
      await roomManager.withRoomMutation(data.roomCode, async (room) => {
        if (!room?.gameState) {
          reply({ ok: false, error: 'room_not_ready' });
          return;
        }

        const currentPlayer = getCurrentPlayer(room.gameState);
        if (currentPlayer.id !== socket.id) {
          reply({ ok: false, error: 'not_current_player' });
          return;
        }
        if (currentPlayer.isSpectator) {
          reply({ ok: false, error: 'spectator' });
          return;
        }

        roomManager.recordPlayerAction(data.roomCode, socket.id);

        GameLogic.drawCard(room.gameState);
        roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT');
        reply({ ok: true });
      });
    } catch (error) {
      console.error('Error draw_card:', error);
      reply({ ok: false, error: 'internal_error' });
    }
  });

  socket.on('game:replace_card', async (data, ack?: ActionAck) => {
    const reply = createActionReply(data, ack);

    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) {
        reply({ ok: false, error: 'rate_limited' });
        return;
      }
      await roomManager.withRoomMutation(data.roomCode, async (room) => {
        if (!room?.gameState) {
          reply({ ok: false, error: 'room_not_ready' });
          return;
        }

        const currentPlayer = getCurrentPlayer(room.gameState);
        if (currentPlayer.id !== socket.id) {
          reply({ ok: false, error: 'not_current_player' });
          return;
        }
        if (currentPlayer.isSpectator) {
          reply({ ok: false, error: 'spectator' });
          return;
        }
        if (!room.gameState.drawnCard) {
          reply({ ok: false, error: 'no_drawn_card' });
          return;
        }
        const cardIndex = Number(data.cardIndex);
        if (!Number.isInteger(cardIndex) || cardIndex < 0 || cardIndex >= currentPlayer.hand.length) {
          reply({ ok: false, error: 'invalid_card_index' });
          return;
        }

        roomManager.recordPlayerAction(data.roomCode, socket.id);

        GameLogic.replaceCard(room.gameState, cardIndex);
        roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT');
        reply({ ok: true });

        const phaseAfterPower = readPhaseAfterMutation(room.gameState);
        if (phaseAfterPower === GamePhase.ended) {
          roomManager.handleGameEnd(data.roomCode);
          return;
        }

        if (room.gameState.phase === GamePhase.specialPower) {
          roomManager.startTurnTimer(data.roomCode);
          return;
        }

        if (phaseAfterPower === GamePhase.reaction) {
          const reactionTime =
            typeof room.settings?.reactionTimeMs === 'number'
              ? room.settings.reactionTimeMs
              : 3000;
          roomManager.startReactionTimer(data.roomCode, reactionTime);
          return;
        }

        await roomManager.checkAndPlayBotTurn(data.roomCode, { lockAlreadyHeld: true });
      });
    } catch (error) {
      console.error('Error replace_card:', error);
      reply({ ok: false, error: 'internal_error' });
    }
  });

  socket.on('game:discard_card', async (data, ack?: ActionAck) => {
    const reply = createActionReply(data, ack);

    try {
      console.log(`[DISCARD] Received from ${socket.id}, roomCode=${data.roomCode}`);
      if (!await SecurityService.checkEventRateLimit(socket.id)) {
        console.log(`[DISCARD] BLOCKED: Rate limited for ${socket.id}`);
        reply({ ok: false, error: 'rate_limited' });
        return;
      }
      await roomManager.withRoomMutation(data.roomCode, async (room) => {
        if (!room?.gameState) {
          console.log('[DISCARD] BLOCKED: Room not found or no gameState');
          reply({ ok: false, error: 'room_not_ready' });
          return;
        }

        const currentPlayer = getCurrentPlayer(room.gameState);
        console.log(`[DISCARD] currentPlayer.id=${currentPlayer.id}, socket.id=${socket.id}`);
        if (currentPlayer.id !== socket.id) {
          console.log('[DISCARD] BLOCKED: Not current player\'s turn');
          reply({ ok: false, error: 'not_current_player' });
          return;
        }
        if (currentPlayer.isSpectator) {
          console.log('[DISCARD] BLOCKED: Player is spectator');
          reply({ ok: false, error: 'spectator' });
          return;
        }

        roomManager.recordPlayerAction(data.roomCode, socket.id);

        console.log(`[DISCARD] Before: phase=${room.gameState.phase}, isWaitingForSpecialPower=${room.gameState.isWaitingForSpecialPower}`);
        GameLogic.discardDrawnCard(room.gameState);
        console.log(`[DISCARD] After: phase=${room.gameState.phase}, isWaitingForSpecialPower=${room.gameState.isWaitingForSpecialPower}`);

        roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT');
        reply({ ok: true });

        const phaseAfterSkip = readPhaseAfterMutation(room.gameState);
        if (phaseAfterSkip === GamePhase.ended) {
          roomManager.handleGameEnd(data.roomCode);
          return;
        }

        if (room.gameState.phase === GamePhase.specialPower) {
          console.log('[DISCARD] Special power phase, starting power timer');
          roomManager.startTurnTimer(data.roomCode);
          return;
        }

        if (phaseAfterSkip === GamePhase.reaction) {
          const reactionTime =
            typeof room.settings?.reactionTimeMs === 'number'
              ? room.settings.reactionTimeMs
              : 3000;
          console.log(`[DISCARD] Starting reaction timer: ${reactionTime}ms`);
          roomManager.startReactionTimer(data.roomCode, reactionTime);
          return;
        }

        console.log('[DISCARD] No reaction phase, checking bot turn');
        await roomManager.checkAndPlayBotTurn(data.roomCode, { lockAlreadyHeld: true });
      });
    } catch (error) {
      console.error('Error discard_card:', error);
      reply({ ok: false, error: 'internal_error' });
    }
  });

  socket.on('game:call_dutch', async (data, ack?: ActionAck) => {
    const reply = createActionReply(data, ack);

    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) {
        reply({ ok: false, error: 'rate_limited' });
        return;
      }
      await roomManager.withRoomMutation(data.roomCode, async (room) => {
        if (!room?.gameState) {
          reply({ ok: false, error: 'room_not_ready' });
          return;
        }

        if (room.gameState.phase !== GamePhase.playing || room.gameState.drawnCard) {
          reply({ ok: false, error: 'invalid_phase' });
          return;
        }

        const currentPlayer = getCurrentPlayer(room.gameState);
        if (currentPlayer.id !== socket.id) {
          reply({ ok: false, error: 'not_current_player' });
          return;
        }
        if (currentPlayer.isSpectator) {
          reply({ ok: false, error: 'spectator' });
          return;
        }

        roomManager.recordPlayerAction(data.roomCode, socket.id);

        GameLogic.callDutch(room.gameState, currentPlayer.id);
        roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT', {
          message: `${currentPlayer.name} appelle DUTCH !`,
        });
        reply({ ok: true });
      });
    } catch (error) {
      console.error('Error call_dutch:', error);
      reply({ ok: false, error: 'internal_error' });
    }
  });

  socket.on('game:attempt_match', async (data, ack?: ActionAck) => {
    const reply = createActionReply(data, ack);

    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) {
        reply({ ok: false, error: 'rate_limited' });
        return;
      }
      // Rate limit spécifique pour éviter le spam de matchs (500ms entre chaque)
      if (!await SecurityService.checkMatchRateLimit(socket.id)) {
        console.log(`[MATCH] Rate limited for ${socket.id} - too many match attempts`);
        reply({ ok: false, error: 'match_rate_limited' });
        return;
      }
      await roomManager.withRoomMutation(data.roomCode, async (room) => {
        if (!room?.gameState) {
          reply({ ok: false, error: 'room_not_ready' });
          return;
        }

        if (room.gameState.phase !== GamePhase.reaction) {
          reply({ ok: false, error: 'invalid_phase' });
          return;
        }

        const player = room.gameState.players.find(
          (p: Player) => p.id === socket.id
        );
        if (!player || player.isSpectator) {
          reply({ ok: false, error: player ? 'spectator' : 'player_not_found' });
          return;
        }

        roomManager.recordPlayerAction(data.roomCode, socket.id);

        GameLogic.attemptMatch(room.gameState, player.id, data.cardIndex);
        roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT');
        reply({ ok: true });
      });
    } catch (error) {
      console.error('Error attempt_match:', error);
      reply({ ok: false, error: 'internal_error' });
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
  socket.on('special_power:target_selection', async (data) => {
    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) return;
      const room = await roomManager.loadRoom(data.roomCode);
      if (!room?.gameState) return;

      const currentPlayer = getCurrentPlayer(room.gameState);
      if (currentPlayer.id !== socket.id) return;

      // Broadcast the partial selection to all OTHER players in the room
      socket.to(data.roomCode).emit('special_power:target_selection', data);
    } catch (error) {
      console.error('Error special_power:target_selection:', error);
    }
  });

  socket.on('game:use_special_power', async (data, ack?: ActionAck) => {
    const reply = createActionReply(data, ack);

    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) {
        reply({ ok: false, error: 'rate_limited' });
        return;
      }
      await roomManager.withRoomMutation(data.roomCode, async (room) => {
        if (!room?.gameState) {
          reply({ ok: false, error: 'room_not_ready' });
          return;
        }

        if (room.gameState.phase !== GamePhase.specialPower ||
            !room.gameState.isWaitingForSpecialPower) {
          reply({ ok: false, error: 'invalid_phase' });
          return;
        }

        const isMatchPower = room.gameState.specialPowerPlayerId != null;
        const authorizedPlayerId = isMatchPower
          ? room.gameState.specialPowerPlayerId
          : getCurrentPlayer(room.gameState).id;
        if (authorizedPlayerId !== socket.id) {
          reply({ ok: false, error: 'not_authorized' });
          return;
        }

        const currentPlayer = room.gameState.players.find(p => p.id === socket.id);
        if (!currentPlayer || currentPlayer.isSpectator) {
          reply({ ok: false, error: currentPlayer ? 'spectator' : 'player_not_found' });
          return;
        }

        const specialCard = room.gameState.specialCardToActivate;
        if (!specialCard) {
          reply({ ok: false, error: 'no_special_power' });
          return;
        }

        roomManager.recordPlayerAction(data.roomCode, socket.id);

        const result = GameLogic.useSpecialPower(room.gameState, {
          cardIndex: data.cardIndex,
          targetPlayerIndex: data.targetPlayerIndex,
          targetCardIndex: data.targetCardIndex,
          player1Index: data.player1Index,
          card1Index: data.card1Index,
          player2Index: data.player2Index,
          card2Index: data.card2Index,
        });

        if (result.spiedCard) {
          socket.emit('game:spied_card', {
            roomCode: data.roomCode,
            card: result.spiedCard,
            targetPlayerName: specialCard.value === '7' ? 'vous' :
              (data.targetPlayerIndex === undefined ?
                'Anonyme' : room.gameState.players[data.targetPlayerIndex]?.name)
          });

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

        if (result.affectedPlayers && result.affectedPlayers.length > 0) {
          const io = roomManager.getIO();
          for (const affected of result.affectedPlayers) {
            const affectedPlayer = room.gameState.players.find(p => p.id === affected.playerId);
            if (affectedPlayer?.isHuman) {
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

        if (result.shuffledPlayer) {
          const io = roomManager.getIO();
          const shuffledPlayer = room.gameState.players.find(p => p.id === result.shuffledPlayer!.playerId);
          if (shuffledPlayer?.isHuman) {
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
        reply({ ok: true });

        const phaseAfterPower = readPhaseAfterMutation(room.gameState);
        if (phaseAfterPower === GamePhase.ended) {
          roomManager.handleGameEnd(data.roomCode);
          return;
        }

        if (isMatchPower) {
          room.gameState.specialPowerPlayerId = null;
          roomManager.activateNextPendingPower(data.roomCode, { lockAlreadyHeld: true });
          return;
        }

        if (phaseAfterPower === GamePhase.reaction) {
          const baseReactionTime =
            typeof room.settings?.reactionTimeMs === 'number'
              ? room.settings.reactionTimeMs
              : 3000;

          roomManager.startReactionTimer(data.roomCode, baseReactionTime);
          return;
        }

        await roomManager.checkAndPlayBotTurn(data.roomCode, { lockAlreadyHeld: true });
      });
    } catch (error) {
      console.error('Error use_special_power:', error);
      reply({ ok: false, error: 'internal_error' });
    }
  });

  socket.on('game:skip_special_power', async (data, ack?: ActionAck) => {
    const reply = createActionReply(data, ack);

    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) {
        reply({ ok: false, error: 'rate_limited' });
        return;
      }
      await roomManager.withRoomMutation(data.roomCode, async (room) => {
        if (!room?.gameState) {
          reply({ ok: false, error: 'room_not_ready' });
          return;
        }

        if (room.gameState.phase !== GamePhase.specialPower ||
            !room.gameState.isWaitingForSpecialPower) {
          reply({ ok: false, error: 'invalid_phase' });
          return;
        }

        const isMatchPower = room.gameState.specialPowerPlayerId != null;
        const authorizedPlayerId = isMatchPower
          ? room.gameState.specialPowerPlayerId
          : getCurrentPlayer(room.gameState).id;
        if (authorizedPlayerId !== socket.id) {
          reply({ ok: false, error: 'not_authorized' });
          return;
        }

        const player = room.gameState.players.find(p => p.id === socket.id);
        if (!player || player.isSpectator) {
          reply({ ok: false, error: player ? 'spectator' : 'player_not_found' });
          return;
        }

        roomManager.recordPlayerAction(data.roomCode, socket.id);

        GameLogic.skipSpecialPower(room.gameState);
        roomManager.broadcastGameState(data.roomCode, 'ACTION_RESULT');
        reply({ ok: true });

        const phaseAfterSkip = readPhaseAfterMutation(room.gameState);
        if (phaseAfterSkip === GamePhase.ended) {
          roomManager.handleGameEnd(data.roomCode);
          return;
        }

        if (isMatchPower) {
          room.gameState.specialPowerPlayerId = null;
          roomManager.activateNextPendingPower(data.roomCode, { lockAlreadyHeld: true });
          return;
        }

        if (phaseAfterSkip === GamePhase.reaction) {
          const baseReactionTime =
            typeof room.settings?.reactionTimeMs === 'number'
              ? room.settings.reactionTimeMs
              : 3000;

          roomManager.startReactionTimer(data.roomCode, baseReactionTime);
          return;
        }

        await roomManager.checkAndPlayBotTurn(data.roomCode, { lockAlreadyHeld: true });
      });
    } catch (error) {
      console.error('Error skip_special_power:', error);
      reply({ ok: false, error: 'internal_error' });
    }
  });


  socket.on('game:pause', async (data) => {
    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) return;
      await roomManager.withRoomMutation(data.roomCode, async (room) => {
        if (!room) return;

        const player = room.players.find(p => p.id === socket.id);
        if (!player || player.isSpectator) return;

        roomManager.pauseGame(data.roomCode, socket.id, player.name);
      });
    } catch (error) {
      console.error('Error game:pause:', error);
    }
  });

  socket.on('game:resume', async (data) => {
    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) return;
      await roomManager.withRoomMutation(data.roomCode, async (room) => {
        if (!room) return;

        const player = room.players.find(p => p.id === socket.id);
        if (!player || player.isSpectator) return;

        roomManager.resumeGame(data.roomCode, socket.id, player.name);
      });
    } catch (error) {
      console.error('Error game:resume:', error);
    }
  });

  socket.on('game:forfeit', async (data) => {
    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) return;
      await roomManager.withRoomMutation(data.roomCode, async () => {
        roomManager.forfeitGame(data.roomCode, socket.id);
      });
    } catch (error) {
      console.error('Error game:forfeit:', error);
    }
  });

  // Handle player ready after memorization phase
  socket.on('player:ready', async (data) => {
    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) return;
      await roomManager.withRoomMutation(data.roomCode, async (room) => {
        if (!room?.gameState) return;

        const player = room.players.find(p => p.id === socket.id);
        if (!player) return;
        if (player.isSpectator) return;

        roomManager.recordPlayerAction(data.roomCode, socket.id);
        const success = roomManager.markPlayerReady(data.roomCode, socket.id);
        if (success) {
          console.log(`[READY] Player ${player.name} marked ready in room ${data.roomCode}`);
        }
      });
    } catch (error) {
      console.error('Error player:ready:', error);
    }
  });

  // Handle room settings update (host only)
  socket.on('room:update_settings', async (data) => {
    try {
      if (!await SecurityService.checkEventRateLimit(socket.id)) return;
      const { roomCode, botDifficulty, luckDifficulty } = data;

      let success = false;
      await roomManager.withRoomMutation(roomCode, async () => {
        success = roomManager.updateRoomSettings(roomCode, socket.id, {
          botDifficulty,
          luckDifficulty,
        });
      });

      if (success) {
        console.log(`[SETTINGS] Host ${socket.id} updated settings in room ${roomCode}`);
      }
    } catch (error) {
      console.error('Error room:update_settings:', error);
    }
  });
}
