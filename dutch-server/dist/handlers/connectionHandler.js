"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.setupConnectionHandler = setupConnectionHandler;
const RoomRegistryService_1 = require("../services/RoomRegistryService");
function setupConnectionHandler(socket, roomManager) {
    socket.on('client:ping', (data, callback) => {
        roomManager.touchPlayer(socket.id);
        if (typeof callback === 'function') {
            callback({
                serverTime: Date.now(),
                clientTime: data?.clientTime,
            });
        }
    });
    socket.on('presence:focus', (data) => {
        const roomCode = data?.roomCode?.toString().toUpperCase();
        if (!roomCode)
            return;
        roomManager.updateFocus(roomCode, socket.id, data?.focused === true);
    });
    socket.on('presence:ack', (data) => {
        const roomCode = data?.roomCode?.toString().toUpperCase();
        if (!roomCode)
            return;
        roomManager.confirmPresence(roomCode, socket.id);
    });
    socket.on('disconnect', () => {
        console.log(`Client disconnected: ${socket.id}`);
        roomManager.handleDisconnect(socket.id);
        void RoomRegistryService_1.roomRegistryService.handleSocketDisconnected(socket.id).catch((error) => {
            console.error('Room registry disconnect sync error:', error);
        });
        // Note: Les rooms publiques vides sont nettoyées automatiquement
        // par le publicRoomService toutes les minutes
    });
}
