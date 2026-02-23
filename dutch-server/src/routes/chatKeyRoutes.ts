import { Router } from 'express';
import { createHmac, randomBytes } from 'crypto';
import { requireAuth, AuthenticatedRequest } from '../middleware/authMiddleware';
import { firestore } from '../services/FirebaseAdmin';
import { PushNotificationService } from '../services/PushNotificationService';

const router = Router();

// Récupère ou génère le secret 32-bytes d'un utilisateur (stocké dans user_secrets, hors users)
async function getOrCreateSecret(uid: string): Promise<Buffer> {
  if (!firestore) throw new Error('Firestore non initialisé');
  const ref = firestore.collection('user_secrets').doc(uid);
  const doc = await ref.get();
  if (doc.exists) {
    return Buffer.from(doc.data()!.secret as string, 'hex');
  }
  const secret = randomBytes(32);
  await ref.set({ secret: secret.toString('hex'), createdAt: new Date() });
  return secret;
}

// Dérivation de clé : HKDF simplifié avec HMAC-SHA256
// XOR des 2 secrets (commutatif → même clé des 2 côtés) puis HKDF avec le chatId
function deriveKey(secret1: Buffer, secret2: Buffer, chatId: string): string {
  const combined = Buffer.alloc(32);
  for (let i = 0; i < 32; i++) {
    combined[i] = secret1[i] ^ secret2[i];
  }
  // Extract (PRK)
  const prk = createHmac('sha256', Buffer.from('dutch-chat-v1')).update(combined).digest();
  // Expand (OKM)
  const okm = createHmac('sha256', prk).update(chatId + '\x01').digest();
  return okm.toString('base64');
}

// GET /api/chats/:friendId/key
// Retourne la clé de chiffrement symétrique pour la conversation avec un ami.
// La clé est déterministe : même résultat que l'ami appelle lui aussi cet endpoint.
router.get('/:friendId/key', requireAuth, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const myId = authReq.user!.uid;
  const friendId = String(req.params.friendId);

  if (!friendId || friendId === myId) {
    res.status(400).json({ success: false, error: 'friendId invalide' });
    return;
  }

  try {
    const [mySecret, friendSecret] = await Promise.all([
      getOrCreateSecret(myId),
      getOrCreateSecret(friendId),
    ]);

    // chatId déterministe (même convention que le client)
    const sorted = [myId, friendId].sort();
    const chatId = `${sorted[0]}_${sorted[1]}`;

    const key = deriveKey(mySecret, friendSecret, chatId);
    res.json({ success: true, key });
  } catch (err) {
    console.error('[chatKey] Erreur:', err);
    res.status(500).json({ success: false, error: 'Erreur serveur' });
  }
});

// POST /api/chats/:chatId/notify
// Envoie une push notification au destinataire d'un message.
router.post('/:chatId/notify', requireAuth, async (req, res) => {
  const authReq = req as AuthenticatedRequest;
  const senderId = authReq.user!.uid;
  const { chatId } = req.params;
  const { recipientId, senderName, preview } = req.body as {
    recipientId?: string;
    senderName?: string;
    preview?: string;
  };

  if (!recipientId || !senderName) {
    res.status(400).json({ success: false, error: 'recipientId et senderName requis' });
    return;
  }

  // Vérifier que le sender fait partie du chat (chatId = sorted(uid1, uid2))
  const parts = chatId.split('_');
  if (!parts.includes(senderId)) {
    res.status(403).json({ success: false, error: 'Accès refusé' });
    return;
  }

  try {
    await PushNotificationService.sendToUser(recipientId, {
      title: senderName,
      body: preview || '📩 Nouveau message',
      data: { type: 'chat_message', chatId, senderId },
    });
    res.json({ success: true });
  } catch (err) {
    console.error('[chatNotify] Erreur:', err);
    res.status(500).json({ success: false, error: 'Erreur serveur' });
  }
});

export default router;
