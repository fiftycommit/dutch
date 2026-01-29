/**
 * Service de gestion des rooms publiques
 */

interface PublicRoom {
  code: string;
  players: number;
  maxPlayers: number;
  gameMode: string;
  host: string;
  createdAt: Date;
  isPublic: boolean;
}

class PublicRoomService {
  private publicRooms: Map<string, PublicRoom> = new Map();
  private cleanupInterval: NodeJS.Timeout | null = null;

  constructor() {
    this.startCleanupTimer();
  }

  /**
   * Ajoute une room à la liste des rooms publiques
   */
  addPublicRoom(
    code: string,
    host: string,
    gameMode: string,
    maxPlayers: number = 4
  ): void {
    this.publicRooms.set(code, {
      code,
      players: 1,
      maxPlayers,
      gameMode,
      host,
      createdAt: new Date(),
      isPublic: true,
    });
    console.log(`📢 Room publique créée: ${code} (${gameMode})`);
  }

  /**
   * Retire une room de la liste des rooms publiques
   */
  removePublicRoom(code: string): void {
    if (this.publicRooms.has(code)) {
      this.publicRooms.delete(code);
      console.log(`🗑️ Room publique supprimée: ${code}`);
    }
  }

  /**
   * Met à jour le nombre de joueurs dans une room
   */
  updatePlayerCount(code: string, count: number): void {
    const room = this.publicRooms.get(code);
    if (room) {
      room.players = count;
      console.log(`👥 Room ${code}: ${count}/${room.maxPlayers} joueurs`);

      // Retirer la room si elle est pleine
      if (count >= room.maxPlayers) {
        this.removePublicRoom(code);
      }
    }
  }

  /**
   * Récupère toutes les rooms publiques disponibles
   */
  getAvailableRooms(): PublicRoom[] {
    const now = new Date();
    const availableRooms: PublicRoom[] = [];

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
  isPublicRoom(code: string): boolean {
    return this.publicRooms.has(code);
  }

  /**
   * Nettoie les rooms expirées ou vides
   */
  private cleanup(): void {
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
  private startCleanupTimer(): void {
    // Nettoyer toutes les minutes
    this.cleanupInterval = setInterval(() => {
      this.cleanup();
    }, 60000);

    console.log('⏰ Timer de nettoyage des rooms publiques démarré');
  }

  /**
   * Arrête le timer de nettoyage
   */
  stopCleanupTimer(): void {
    if (this.cleanupInterval) {
      clearInterval(this.cleanupInterval);
      this.cleanupInterval = null;
      console.log('⏰ Timer de nettoyage des rooms publiques arrêté');
    }
  }

  /**
   * Obtient les statistiques des rooms publiques
   */
  getStats(): {
    totalRooms: number;
    totalPlayers: number;
    averagePlayersPerRoom: number;
  } {
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
export const publicRoomService = new PublicRoomService();
