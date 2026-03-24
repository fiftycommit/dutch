"use strict";
/**
 * Service de gestion des rooms publiques
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.publicRoomService = void 0;
class PublicRoomService {
    constructor() {
        this.publicRooms = new Map();
        this.cleanupInterval = null;
        this.startCleanupTimer();
    }
    /**
     * Ajoute une room à la liste des rooms publiques
     */
    addPublicRoom(code, host, gameMode, maxPlayers = 6, hostMMR, roomName) {
        this.publicRooms.set(code, {
            code,
            roomName,
            players: 1,
            maxPlayers,
            gameMode,
            host,
            hostMMR,
            createdAt: new Date(),
            isPublic: true,
        });
        console.log(`📢 Room publique créée: ${code}${roomName ? ` "${roomName}"` : ''} (${gameMode}) - MMR: ${hostMMR || 'N/A'}`);
    }
    /**
     * Retire une room de la liste des rooms publiques
     */
    removePublicRoom(code) {
        if (this.publicRooms.has(code)) {
            this.publicRooms.delete(code);
            console.log(`🗑️ Room publique supprimée: ${code}`);
        }
    }
    /**
     * Met à jour le nombre de joueurs dans une room
     */
    updatePlayerCount(code, count) {
        const room = this.publicRooms.get(code);
        if (room) {
            room.players = count;
            console.log(`👥 Room ${code}: ${count}/${room.maxPlayers} joueurs`);
            // Retirer la room si elle est pleine ou vide
            if (count >= room.maxPlayers || count <= 0) {
                this.removePublicRoom(code);
            }
        }
    }
    /**
     * Récupère toutes les rooms publiques disponibles
     */
    getAvailableRooms() {
        const now = new Date();
        const availableRooms = [];
        for (const room of this.publicRooms.values()) {
            // Filtrer les rooms qui ne sont pas pleines et pas trop anciennes
            const ageMinutes = (now.getTime() - room.createdAt.getTime()) / 60000;
            if (room.players < room.maxPlayers && ageMinutes < 10) {
                availableRooms.push(room);
            }
        }
        // Trier par nombre de joueurs (les plus remplies en premier)
        return availableRooms.sort((a, b) => b.players - a.players);
    }
    /**
     * Vérifie si une room est publique
     */
    isPublicRoom(code) {
        return this.publicRooms.has(code);
    }
    /**
     * Nettoie les rooms expirées ou vides
     */
    cleanup() {
        const now = new Date();
        let cleaned = 0;
        for (const [code, room] of this.publicRooms.entries()) {
            const ageMinutes = (now.getTime() - room.createdAt.getTime()) / 60000;
            // Supprimer si:
            // - Aucun joueur
            // - Plus de 10 minutes d'existence
            if (room.players === 0 || ageMinutes > 10) {
                this.publicRooms.delete(code);
                cleaned++;
            }
        }
        if (cleaned > 0) {
            console.log(`🧹 ${cleaned} room(s) publique(s) nettoyée(s)`);
        }
    }
    /**
     * Démarre le timer de nettoyage automatique
     */
    startCleanupTimer() {
        // Nettoyer toutes les minutes
        this.cleanupInterval = setInterval(() => {
            this.cleanup();
        }, 60000);
        console.log('⏰ Timer de nettoyage des rooms publiques démarré');
    }
    /**
     * Arrête le timer de nettoyage
     */
    stopCleanupTimer() {
        if (this.cleanupInterval) {
            clearInterval(this.cleanupInterval);
            this.cleanupInterval = null;
            console.log('⏰ Timer de nettoyage des rooms publiques arrêté');
        }
    }
    /**
     * Obtient les statistiques des rooms publiques
     */
    getStats() {
        let totalPlayers = 0;
        for (const room of this.publicRooms.values()) {
            totalPlayers += room.players;
        }
        const totalRooms = this.publicRooms.size;
        const averagePlayersPerRoom = totalRooms > 0 ? totalPlayers / totalRooms : 0;
        return {
            totalRooms,
            totalPlayers,
            averagePlayersPerRoom: Math.round(averagePlayersPerRoom * 10) / 10,
        };
    }
}
// Export singleton
exports.publicRoomService = new PublicRoomService();
//# sourceMappingURL=publicRoomService.js.map