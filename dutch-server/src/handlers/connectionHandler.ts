import { Socket } from 'socket.io';
import { RoomManager } from '../services/RoomManager';

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

  socket.on('presence:focus', (data) => {
    const roomCode = data?.roomCode?.toString().toUpperCase();
    if (!roomCode) return;
    roomManager.updateFocus(roomCode, socket.id, data?.focused === true);
  });

  socket.on('presence:ack', (data) => {
    const roomCode = data?.roomCode?.toString().toUpperCase();
    if (!roomCode) return;
    roomManager.confirmPresence(roomCode, socket.id);
  });

  socket.on('disconnect', () => {
    console.log(`Client disconnected: ${socket.id}`);
    roomManager.handleDisconnect(socket.id);
  });
}
