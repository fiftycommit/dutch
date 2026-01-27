import { Socket } from 'socket.io';
import { RoomManager } from '../services/RoomManager';
import { GameLogic } from '../services/GameLogic';
import { GamePhase, getCurrentPlayer } from '../models/GameState';
import { Player } from '../models/Player';

export function setupGameHandler(socket: Socket, roomManager: RoomManager) {
  socket.on('game:draw_card', async (data) => {
    try {
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
      const room = roomManager.getRoom(data.roomCode);
      if (!room || !room.gameState) return;

      const currentPlayer = getCurrentPlayer(room.gameState);
      if (currentPlayer.id !== socket.id) return;
      if (currentPlayer.isSpectator) return;

      roomManager.recordPlayerAction(data.roomCode, socket.id);

      GameLogic.discardDrawnCard(room.gameState);
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
      console.error('Error discard_card:', error);
    }
  });

  socket.on('game:take_from_discard', async (data) => {
    try {
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

  socket.on('game:use_special_power', async (data) => {
    try {
      const room = roomManager.getRoom(data.roomCode);
      if (!room || !room.gameState) return;

      const currentPlayer = getCurrentPlayer(room.gameState);
      if (currentPlayer.id !== socket.id) return;
      if (currentPlayer.isSpectator) return;

      roomManager.recordPlayerAction(data.roomCode, socket.id);

      GameLogic.useSpecialPower(
        room.gameState,
        data.targetPlayerIndex,
        data.targetCardIndex
      );

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
      console.error('Error use_special_power:', error);
    }
  });

  socket.on('game:complete_swap', async (data) => {
    try {
      const room = roomManager.getRoom(data.roomCode);
      if (!room || !room.gameState) return;

      const currentPlayer = getCurrentPlayer(room.gameState);
      if (currentPlayer.id !== socket.id) return;
      if (currentPlayer.isSpectator) return;

      roomManager.recordPlayerAction(data.roomCode, socket.id);

      GameLogic.completeSwap(room.gameState, data.ownCardIndex);
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
      console.error('Error complete_swap:', error);
    }
  });

  socket.on('game:skip_special_power', async (data) => {
    try {
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
        const reactionTime =
          typeof room.settings?.reactionTimeMs === 'number'
            ? room.settings.reactionTimeMs
            : 3000;
        roomManager.startReactionTimer(data.roomCode, reactionTime);
        return;
      }

      await roomManager.checkAndPlayBotTurn(data.roomCode);
    } catch (error) {
      console.error('Error skip_special_power:', error);
    }
  });
}
