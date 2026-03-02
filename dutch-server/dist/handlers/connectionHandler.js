"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.setupConnectionHandler = setupConnectionHandler;
const RoomRegistryService_1 = require("../services/RoomRegistryService");
const socketAuthMiddleware_1 = require("../middleware/socketAuthMiddleware");
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
    // Mise à jour du focus utilisateur global (hors room) — permet de détecter app en arrière-plan
    socket.on('user:focus', (data) => {
        const uid = socket.data?.user?.uid;
        if (!uid)
            return;
        socketAuthMiddleware_1.userFocused.set(uid, data?.focused === true);
    });
    socket.on('presence:ack', (data) => {
        const roomCode = data?.roomCode?.toString().toUpperCase();
        if (!roomCode)
            return;
        roomManager.confirmPresence(roomCode, socket.id);
    });
    socket.on('presence:timeout_kick', (data) => {
        const roomCode = data?.roomCode?.toString().toUpperCase();
        const playerId = data?.playerId?.toString();
        const isForeground = data?.isForeground === true;
        if (!roomCode || !playerId)
            return;
        if (isForeground) {
            roomManager.kickPlayer(roomCode, playerId, 'Inactif sur un pouvoir (Forfait)');
        }
        else {
            roomManager.triggerPresenceCheck(roomCode, playerId, 'Inactif sur un pouvoir', {
                deadlineMs: 10000,
                sendPush: true,
            });
        }
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
