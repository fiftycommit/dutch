/**
 * Handlers pour les rooms publiques
 */

import { Socket } from 'socket.io';
import { publicRoomService } from '../services/publicRoomService';

/**
 * Configure les handlers pour les rooms publiques
 */
export function setupPublicRoomHandlers(socket: Socket, rooms: Map<string, any>): void {
  
  /**
   * Récupérer la liste des rooms publiques disponibles
   */
  socket.on('rooms:getPublic', (data, callback) => {
    try {
      console.log(`🔍 ${socket.id} demande les rooms publiques - data:`, data, 'callback type:', typeof callback);
      
      const availableRooms = publicRoomService.getAvailableRooms();
      
      // Formater les rooms pour le client
      const formattedRooms = availableRooms.map(room => ({
        code: room.code,
        roomName: room.roomName,
        players: room.players,
        maxPlayers: room.maxPlayers,
        gameMode: room.gameMode,
        host: room.host,
        hostMMR: room.hostMMR,
        isPublic: true,
      }));

      console.log(`✅ ${formattedRooms.length} rooms trouvées, callback est ${typeof callback}`);

      if (typeof callback === 'function') {
        console.log(`📤 Envoi de la réponse au client ${socket.id}`);
        callback({
          success: true,
          rooms: formattedRooms,
        });
        console.log(`✅ Réponse envoyée`);
      } else {
        console.log(`❌ Callback n'est pas une fonction: ${typeof callback}`);
      }
    } catch (error) {
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
      const stats = publicRoomService.getStats();
      
      console.log(`📊 ${socket.id} demande les stats: ${JSON.stringify(stats)}`);

      if (typeof callback === 'function') {
        callback({
          success: true,
          stats,
        });
      }
    } catch (error) {
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
export function onPublicRoomCreated(
  roomCode: string,
  hostName: string,
  gameMode: string,
  maxPlayers: number,
  hostMMR?: number,
  roomName?: string
): void {
  publicRoomService.addPublicRoom(roomCode, hostName, gameMode, maxPlayers, hostMMR, roomName);
}

/**
 * Notifie le service qu'un joueur a rejoint une room publique
 */
export function onPublicRoomPlayerJoined(roomCode: string, playerCount: number): void {
  publicRoomService.updatePlayerCount(roomCode, playerCount);
}

/**
 * Notifie le service qu'un joueur a quitté une room publique
 */
export function onPublicRoomPlayerLeft(roomCode: string, playerCount: number): void {
  publicRoomService.updatePlayerCount(roomCode, playerCount);
}

/**
 * Notifie le service qu'une room publique a été fermée
 */
export function onPublicRoomClosed(roomCode: string): void {
  publicRoomService.removePublicRoom(roomCode);
}

/**
 * Vérifie si une room est publique
 */
export function isPublicRoom(roomCode: string): boolean {
  return publicRoomService.isPublicRoom(roomCode);
}
