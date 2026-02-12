import { messaging } from './FirebaseAdmin';
import { firestoreService } from './FirestoreService';

// ─── Push Notification Service ──────────────────────────────────────────────
// Utilise le module centralisé FirebaseAdmin au lieu de sa propre initialisation.

export interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

export class PushNotificationService {
  static get isAvailable(): boolean {
    return messaging !== null;
  }

  static async sendToUser(userId: string, payload: PushPayload): Promise<void> {
    if (!messaging) return;

    const tokens = await firestoreService.getDeviceTokens(userId);
    if (tokens.length === 0) return;

    const message = {
      notification: {
        title: payload.title,
        body: payload.body,
      },
      data: payload.data || {},
      tokens,
    };

    try {
      const response = await messaging.sendEachForMulticast(message);

      // Nettoyer les tokens invalides
      if (response.failureCount > 0) {
        response.responses.forEach((resp: any, idx: number) => {
          if (!resp.success && resp.error?.code === 'messaging/registration-token-not-registered') {
            firestoreService.removeDeviceToken(userId, tokens[idx]);
          }
        });
      }
    } catch (error) {
      console.error('Erreur envoi push notification:', error);
    }
  }

  static async notifyFriendRequest(toUserId: string, fromUsername: string, fromDisplayName: string): Promise<void> {
    await this.sendToUser(toUserId, {
      title: 'Demande d\'ami',
      body: `${fromDisplayName} (@${fromUsername}) veut être ton ami !`,
      data: { type: 'friend_request', fromUsername },
    });
  }

  static async notifyFriendAccepted(toUserId: string, fromUsername: string, fromDisplayName: string): Promise<void> {
    await this.sendToUser(toUserId, {
      title: 'Ami accepté !',
      body: `${fromDisplayName} (@${fromUsername}) a accepté ta demande d'ami`,
      data: { type: 'friend_accepted', fromUsername },
    });
  }

  static async notifyRoomInvite(toUserId: string, fromDisplayName: string, roomCode: string): Promise<void> {
    await this.sendToUser(toUserId, {
      title: 'Invitation salon',
      body: `${fromDisplayName} t'invite à rejoindre une partie !`,
      data: { type: 'room_invite', roomCode },
    });
  }
}
