import { AuthService } from './AuthService';

// Firebase Admin est optionnel — dégradation gracieuse si non configuré
let firebaseAdmin: any = null;
let messaging: any = null;

try {
  const admin = require('firebase-admin');
  const path = require('path');
  const fs = require('fs');


  const serviceAccountPath = path.join(__dirname, '../../data/firebase-service-account.json');

  // 1. Essayer via Variable d'environnement (Production)
  if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    try {
      const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });
      messaging = admin.messaging();
      firebaseAdmin = admin;
      console.log('🔔 Firebase Cloud Messaging initialisé (via ENV)');
    } catch (e) {
      console.error('❌ Erreur parsing FIREBASE_SERVICE_ACCOUNT_JSON:', e);
    }
  }
  // 2. Essayer via Fichier (Local / Dev)
  else if (fs.existsSync(serviceAccountPath)) {
    const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf-8'));
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    messaging = admin.messaging();
    firebaseAdmin = admin;
    console.log('🔔 Firebase Cloud Messaging initialisé (via FILE)');
  } else {
    console.log('⚠️ Firebase non configuré (ni ENV ni FILE). Push notifications désactivées.');
  }
} catch (e) {
  console.log('⚠️ Firebase Admin non disponible:', e);
}

export interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

export class PushNotificationService {
  static get isAvailable(): boolean {
    return messaging !== null;
  }

  static async sendToUser(userId: number, payload: PushPayload): Promise<void> {
    if (!messaging) return;

    const tokens = AuthService.getDeviceTokens(userId);
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
            AuthService.removeDeviceToken(tokens[idx]);
          }
        });
      }
    } catch (error) {
      console.error('Erreur envoi push notification:', error);
    }
  }

  static async notifyFriendRequest(toUserId: number, fromUsername: string, fromDisplayName: string): Promise<void> {
    await this.sendToUser(toUserId, {
      title: 'Demande d\'ami',
      body: `${fromDisplayName} (@${fromUsername}) veut être ton ami !`,
      data: { type: 'friend_request', fromUsername },
    });
  }

  static async notifyFriendAccepted(toUserId: number, fromUsername: string, fromDisplayName: string): Promise<void> {
    await this.sendToUser(toUserId, {
      title: 'Ami accepté !',
      body: `${fromDisplayName} (@${fromUsername}) a accepté ta demande d'ami`,
      data: { type: 'friend_accepted', fromUsername },
    });
  }

  static async notifyRoomInvite(toUserId: number, fromDisplayName: string, roomCode: string): Promise<void> {
    await this.sendToUser(toUserId, {
      title: 'Invitation salon',
      body: `${fromDisplayName} t'invite à rejoindre une partie !`,
      data: { type: 'room_invite', roomCode },
    });
  }
}
