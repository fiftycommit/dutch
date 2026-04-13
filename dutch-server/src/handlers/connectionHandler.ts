import { Socket } from 'socket.io';
import { RoomManager } from '../services/RoomManager';
import { roomRegistryService } from '../services/RoomRegistryService';
import { userFocused } from '../middleware/socketAuthMiddleware';

export function setupConnectionHandler(socket: Socket, roomManager: RoomManager) {
  socket.on(
    'client:ping',
    (data: any, callback?: (response: { serverTime: number; clientTime?: number }) => void) => {
      roomManager.touchPlayer(socket.id);
      if (typeof callback === 'function') {
        callback({
          serverTime: Date.now(),
          clientTime: data?.clientTime,
        });
      }
    }
  );

  socket.on('presence:focus', async (data) => {
    const roomCode = data?.roomCode?.toString().toUpperCase();
    if (!roomCode) return;
    await roomManager.withRoomMutation(roomCode, async () => {
      roomManager.updateFocus(roomCode, socket.id, data?.focused === true);
    });
  });

  // Mise à jour du focus utilisateur global (hors room) — permet de détecter app en arrière-plan
  socket.on('user:focus', (data) => {
    const uid = (socket as any).data?.user?.uid;
    if (!uid) return;
    userFocused.set(uid, data?.focused === true);
  });

  socket.on('presence:ack', async (data) => {
    const roomCode = data?.roomCode?.toString().toUpperCase();
    if (!roomCode) return;
    await roomManager.withRoomMutation(roomCode, async () => {
      roomManager.confirmPresence(roomCode, socket.id);
    });
  });

  socket.on('presence:timeout_kick', async (data) => {
    const roomCode = data?.roomCode?.toString().toUpperCase();
    const playerId = data?.playerId?.toString();
    const isForeground = data?.isForeground === true;

    if (!roomCode || !playerId) return;

    await roomManager.withRoomMutation(roomCode, async () => {
      if (isForeground) {
        roomManager.kickPlayer(roomCode, playerId, 'Inactif sur un pouvoir (Forfait)');
      } else {
        roomManager.triggerPresenceCheck(roomCode, playerId, 'Inactif sur un pouvoir', {
          deadlineMs: 10000,
          sendPush: true,
        });
      }
    });
  });

  socket.on('disconnect', () => {
    console.log(`Client disconnected: ${socket.id}`);
    roomManager.handleDisconnect(socket.id);
    void roomRegistryService.handleSocketDisconnected(socket.id).catch((error) => {
      console.error('Room registry disconnect sync error:', error);
    });
    // Note: Les rooms publiques vides sont nettoyées automatiquement
    // par le publicRoomService toutes les minutes
  });
}
