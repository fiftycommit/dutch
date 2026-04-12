import { Socket } from 'socket.io';
import { admin, auth } from '../services/FirebaseAdmin';
import { firestoreService } from '../services/FirestoreService';
import { SecurityService } from '../services/SecurityService';

// Map uid -> Set<socketId> pour tracker les users en ligne
export const onlineUsers = new Map<string, Set<string>>();

// Map uid -> boolean pour tracker si l'app est au premier plan (focus)
// undefined = inconnu (jamais envoyé), true = premier plan, false = arrière-plan
export const userFocused = new Map<string, boolean>();

export interface FirebaseUserPayload {
  uid: string;
  email: string | null;
  displayName: string;
  username: string;
}

export interface AuthenticatedSocket extends Socket {
  data: {
    user?: FirebaseUserPayload;
  };
}

export async function socketAuthMiddleware(socket: Socket, next: (err?: Error) => void) {
  const token = socket.handshake.auth?.token;
  const ip = SecurityService.getSocketClientIp(socket);

  if (process.env.NODE_ENV === 'production') {
    const appCheckToken = typeof socket.handshake.auth?.appCheckToken === 'string'
      ? socket.handshake.auth.appCheckToken.trim()
      : '';

    if (admin.apps.length === 0) {
      next(new Error('Firebase App Check non configure'));
      return;
    }

    if (!appCheckToken) {
      console.warn(`[SECURITY] Socket connection rejected - no App Check - IP: ${ip}, time: ${new Date().toISOString()}`);
      next(new Error('App Check requis'));
      return;
    }

    try {
      await admin.appCheck().verifyToken(appCheckToken);
    } catch {
      console.warn(`[SECURITY] Socket connection rejected - invalid App Check - IP: ${ip}, time: ${new Date().toISOString()}`);
      next(new Error('App Check invalide'));
      return;
    }
  }

  if (!token) {
    console.warn(`[SECURITY] Socket connection rejected — no token — IP: ${ip}, time: ${new Date().toISOString()}`);
    next(new Error('Authentication required'));
    return;
  }

  if (!auth) {
    next(new Error('Firebase Auth non configuré'));
    return;
  }

  try {
    const decoded = await auth.verifyIdToken(token);

    // Check if user is banned
    if (await firestoreService.isUserBanned(decoded.uid)) {
      console.warn(`[SECURITY] Banned user rejected — uid: ${decoded.uid}, IP: ${ip}`);
      next(new Error('Compte banni'));
      return;
    }

    // Charger ou créer le profil Firestore
    const profile = await firestoreService.getOrCreateUser(decoded.uid, {
      email: decoded.email || null,
      displayName: decoded.name || decoded.email?.split('@')[0] || 'Joueur',
      username: decoded.email?.split('@')[0]?.toLowerCase() || decoded.uid.slice(0, 8),
    });

    socket.data.user = {
      uid: decoded.uid,
      email: decoded.email || null,
      displayName: profile.displayName,
      username: profile.username,
    };

    // Tracker l'utilisateur en ligne
    if (!onlineUsers.has(decoded.uid)) {
      onlineUsers.set(decoded.uid, new Set());
    }
    onlineUsers.get(decoded.uid)!.add(socket.id);
    userFocused.set(decoded.uid, true);

    next();
  } catch {
    console.warn(`[SECURITY] Socket auth failed — invalid token — IP: ${ip}, time: ${new Date().toISOString()}`);
    next(new Error('Token invalide'));
  }
}

export function handleSocketDisconnect(socket: Socket) {
  const user = socket.data.user;
  if (user?.uid) {
    const sockets = onlineUsers.get(user.uid);
    if (sockets) {
      sockets.delete(socket.id);
      if (sockets.size === 0) {
        onlineUsers.delete(user.uid);
        userFocused.delete(user.uid); // Nettoyer le focus quand plus de sockets
      }
    }
  }
}
