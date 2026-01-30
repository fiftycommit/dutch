"use strict";
/**
 * Handlers pour les rooms publiques
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.setupPublicRoomHandlers = setupPublicRoomHandlers;
exports.onPublicRoomCreated = onPublicRoomCreated;
exports.onPublicRoomPlayerJoined = onPublicRoomPlayerJoined;
exports.onPublicRoomPlayerLeft = onPublicRoomPlayerLeft;
exports.onPublicRoomClosed = onPublicRoomClosed;
exports.isPublicRoom = isPublicRoom;
const publicRoomService_1 = require("../services/publicRoomService");
/**
 * Configure les handlers pour les rooms publiques
 */
function setupPublicRoomHandlers(socket, rooms) {
    /**
     * Récupérer la liste des rooms publiques disponibles
     */
    socket.on('rooms:getPublic', (callback) => {
        try {
            const availableRooms = publicRoomService_1.publicRoomService.getAvailableRooms();
            // Formater les rooms pour le client
            const formattedRooms = availableRooms.map(room => ({
                code: room.code,
                players: room.players,
                maxPlayers: room.maxPlayers,
                gameMode: room.gameMode,
                host: room.host,
                hostMMR: room.hostMMR,
            }));
            console.log(`🔍 ${socket.id} demande les rooms publiques: ${formattedRooms.length} trouvées`);
            if (typeof callback === 'function') {
                callback({
                    success: true,
                    rooms: formattedRooms,
                });
            }
        }
        catch (error) {
            console.error('❌ Erreur lors de la récupération des rooms publiques:', error);
            if (typeof callback === 'function') {
                callback({
                    success: false,
                    error: 'Erreur lors de la récupération des rooms',
                });
            }
        }
    });
    /**
     * Obtenir les statistiques des rooms publiques
     */
    socket.on('rooms:stats', (callback) => {
        try {
            const stats = publicRoomService_1.publicRoomService.getStats();
            console.log(`📊 ${socket.id} demande les stats: ${JSON.stringify(stats)}`);
            if (typeof callback === 'function') {
                callback({
                    success: true,
                    stats,
                });
            }
        }
        catch (error) {
            console.error('❌ Erreur lors de la récupération des stats:', error);
            if (typeof callback === 'function') {
                callback({
                    success: false,
                    error: 'Erreur lors de la récupération des statistiques',
                });
            }
        }
    });
}
/**
 * Notifie le service qu'une room publique a été créée
 */
function onPublicRoomCreated(roomCode, hostName, gameMode, maxPlayers, hostMMR) {
    publicRoomService_1.publicRoomService.addPublicRoom(roomCode, hostName, gameMode, maxPlayers, hostMMR);
}
/**
 * Notifie le service qu'un joueur a rejoint une room publique
 */
function onPublicRoomPlayerJoined(roomCode, playerCount) {
    publicRoomService_1.publicRoomService.updatePlayerCount(roomCode, playerCount);
}
/**
 * Notifie le service qu'un joueur a quitté une room publique
 */
function onPublicRoomPlayerLeft(roomCode, playerCount) {
    publicRoomService_1.publicRoomService.updatePlayerCount(roomCode, playerCount);
}
/**
 * Notifie le service qu'une room publique a été fermée
 */
function onPublicRoomClosed(roomCode) {
    publicRoomService_1.publicRoomService.removePublicRoom(roomCode);
}
/**
 * Vérifie si une room est publique
 */
function isPublicRoom(roomCode) {
    return publicRoomService_1.publicRoomService.isPublicRoom(roomCode);
}
