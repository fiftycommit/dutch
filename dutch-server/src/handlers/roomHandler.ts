import { Socket } from 'socket.io';
import { RoomManager } from '../services/RoomManager';

export function setupRoomHandler(socket: Socket, roomManager: RoomManager) {
  socket.on('room:create', (data, callback) => {
    try {
      const room = roomManager.createRoom(
        socket.id,
        data.settings,
        data.playerName,
        data.clientId
      );
      socket.join(room.id);
      roomManager.broadcastPresence(room.id);

      console.log(`Room created: ${room.id} by ${socket.id}`);
      callback({ success: true, roomCode: room.id, room });
    } catch (error: any) {
      console.error('Error creating room:', error);
      callback({ success: false, error: error.message });
    }
  });

  socket.on('room:join', (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      const result = roomManager.joinRoom(
        roomCode,
        socket.id,
        data.playerName,
        data.clientId
      );

      if (result.error || !result.room) {
        callback({ success: false, error: result.error ?? 'Room introuvable' });
        return;
      }

      socket.join(roomCode);
      if (result.player) {
        roomManager.notifyPlayerJoined(roomCode, result.player);
      }

      roomManager.broadcastPresence(roomCode);

      console.log(`Player ${socket.id} joined room ${roomCode}`);
      callback({ success: true, room: result.room });
    } catch (error: any) {
      console.error('Error joining room:', error);
      callback({ success: false, error: error.message });
    }
  });

  socket.on('room:ready', (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      const ready = data.ready !== false;
      const success = roomManager.setReady(roomCode, socket.id, ready);
      callback?.({ success });
    } catch (error: any) {
      console.error('Error setting ready state:', error);
      callback?.({ success: false, error: error.message });
    }
  });

  socket.on('room:start_game', async (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      const room = roomManager.getRoom(roomCode);

      if (!room) {
        callback({ success: false, error: 'Room introuvable' });
        return;
      }

      if (room.hostPlayerId !== socket.id) {
        callback({ success: false, error: "Seul l'hôte peut démarrer" });
        return;
      }

      const minPlayers =
        typeof room.settings?.minPlayers === 'number'
          ? room.settings.minPlayers
          : 2;
      const readyHumans = room.players.filter(
        (p) => p.isHuman && p.connected !== false && p.ready
      ).length;
      if (!room.players.find((p) => p.id === socket.id)?.ready) {
        callback({
          success: false,
          error: "L'hôte doit être prêt",
        });
        return;
      }
      if (readyHumans < minPlayers) {
        callback({
          success: false,
          error: `Minimum ${minPlayers} joueurs prêts requis`,
        });
        return;
      }

      const started = roomManager.startGame(roomCode, {
        fillBots: data.fillBots === true,
      });
      callback({ success: started });

      if (!started) return;

      console.log(`Game started in room ${roomCode}`);

      roomManager.broadcastGameState(roomCode, 'GAME_STARTED', {
        message: 'La partie commence !',
        reactionTimeMs: room.settings?.reactionTimeMs ?? 3000,
      });
      roomManager.broadcastPresence(roomCode);

      await roomManager.checkAndPlayBotTurn(roomCode);
    } catch (error: any) {
      console.error('Error starting game:', error);
      callback({ success: false, error: error.message });
    }
  });

  socket.on('chat:send', (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      const message = data.message?.toString() ?? '';
      const success = roomManager.sendChat(roomCode, socket.id, message);
      callback?.({ success });
    } catch (error: any) {
      console.error('Error sending chat message:', error);
      callback?.({ success: false, error: error.message });
    }
  });

  socket.on('room:leave', (data) => {
    const { roomCode } = data;
    socket.leave(roomCode);
    roomManager.handleLeave(roomCode, socket.id);
    console.log(`Player ${socket.id} left room ${roomCode}`);
  });

  // Fermer la room (hôte uniquement)
  socket.on('room:close', (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      const result = roomManager.closeRoom(roomCode, socket.id);

      if (result.success) {
        socket.leave(roomCode);
        console.log(`Room ${roomCode} closed by host ${socket.id}`);
      }

      callback(result);
    } catch (error: any) {
      console.error('Error closing room:', error);
      callback({ success: false, reason: error.message });
    }
  });

  // Devenir hôte d'une room fermée
  socket.on('room:transfer_host', (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      const success = roomManager.transferHost(roomCode, socket.id);

      if (success) {
        console.log(`Host transferred to ${socket.id} in room ${roomCode}`);
      }

      callback({ success });
    } catch (error: any) {
      console.error('Error transferring host:', error);
      callback({ success: false, error: error.message });
    }
  });

  // Vérifier quelles rooms sont actives
  socket.on('room:check_active', (data, callback) => {
    try {
      const roomCodes = data.roomCodes as string[] | undefined;
      if (!roomCodes || !Array.isArray(roomCodes)) {
        callback({ rooms: [] });
        return;
      }

      const activeRooms = roomManager.checkActiveRooms(roomCodes);
      callback({ rooms: activeRooms });
    } catch (error: any) {
      console.error('Error checking active rooms:', error);
      callback({ rooms: [] });
    }
  });

  // Changer le mode de jeu (hôte uniquement, en lobby)
  socket.on('room:set_game_mode', (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      const gameMode = data.gameMode as number;

      const success = roomManager.setGameMode(roomCode, socket.id, gameMode);

      if (success) {
        console.log(`Game mode changed to ${gameMode} in room ${roomCode}`);
      }

      callback({ success });
    } catch (error: any) {
      console.error('Error setting game mode:', error);
      callback({ success: false, error: error.message });
    }
  });

  // Demande de synchronisation complète de l'état
  socket.on('game:request_state', (data) => {
    const roomCode = data.roomCode?.toString().toUpperCase();
    roomManager.sendFullStateToPlayer(roomCode, socket.id);
  });

  // Relancer une partie (rematch)
  socket.on('room:restart', (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      const success = roomManager.restartGame(roomCode, socket.id);

      if (success) {
        console.log(`Game restarted in room ${roomCode} by ${socket.id}`);
      }

      callback({ success });
    } catch (error: any) {
      console.error('Error restarting game:', error);
      callback({ success: false, error: error.message });
    }
  });

  // Kick un joueur (hôte uniquement)
  socket.on('room:kick', (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      const targetClientId = data.clientId?.toString();

      if (!targetClientId) {
        callback({ success: false, error: 'clientId requis' });
        return;
      }

      const success = roomManager.kickPlayer(roomCode, socket.id, targetClientId);

      if (success) {
        console.log(`Player ${targetClientId} kicked from ${roomCode}`);
      }

      callback({ success });
    } catch (error: any) {
      console.error('Error kicking player:', error);
      callback({ success: false, error: error.message });
    }
  });
}
