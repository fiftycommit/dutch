"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.setupRoomHandler = setupRoomHandler;
function setupRoomHandler(socket, roomManager) {
    socket.on('room:create', (data, callback) => {
        try {
            const room = roomManager.createRoom(socket.id, data.settings, data.playerName, data.clientId);
            socket.join(room.id);
            roomManager.broadcastPresence(room.id);
            console.log(`Room created: ${room.id} by ${socket.id}`);
            callback({ success: true, roomCode: room.id, room });
        }
        catch (error) {
            console.error('Error creating room:', error);
            callback({ success: false, error: error.message });
        }
    });
    socket.on('room:join', (data, callback) => {
        try {
            const roomCode = data.roomCode?.toString().toUpperCase();
            const result = roomManager.joinRoom(roomCode, socket.id, data.playerName, data.clientId);
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
        }
        catch (error) {
            console.error('Error joining room:', error);
            callback({ success: false, error: error.message });
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
            const minPlayers = typeof room.settings?.minPlayers === 'number'
                ? room.settings.minPlayers
                : 2;
            const humanCount = room.players.filter((p) => p.isHuman).length;
            if (humanCount < minPlayers) {
                callback({
                    success: false,
                    error: `Minimum ${minPlayers} joueurs requis`,
                });
                return;
            }
            const started = roomManager.startGame(roomCode);
            callback({ success: started });
            if (!started)
                return;
            console.log(`Game started in room ${roomCode}`);
            roomManager.broadcastGameState(roomCode, 'GAME_STARTED', {
                message: 'La partie commence !',
                reactionTimeMs: room.settings?.reactionTimeMs ?? 3000,
            });
            roomManager.broadcastPresence(roomCode);
            await roomManager.checkAndPlayBotTurn(roomCode);
        }
        catch (error) {
            console.error('Error starting game:', error);
            callback({ success: false, error: error.message });
        }
    });
    socket.on('room:leave', (data) => {
        const { roomCode } = data;
        socket.leave(roomCode);
        roomManager.handleLeave(roomCode, socket.id);
        console.log(`Player ${socket.id} left room ${roomCode}`);
        // TODO: gérer déconnexion mid-game proprement
    });
}
