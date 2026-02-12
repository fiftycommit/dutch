import { Socket } from 'socket.io';
import { AuthService, JwtPayload } from '../services/AuthService';

// Map userId -> Set<socketId> pour tracker les users en ligne
export const onlineUsers = new Map<number, Set<string>>();

export interface AuthenticatedSocket extends Socket {
  data: {
    user?: JwtPayload & { displayName?: string };
  };
}

export function socketAuthMiddleware(socket: Socket, next: (err?: Error) => void) {
  const token = socket.handshake.auth?.token;

  if (!token) {
    // Mode invité : pas de token, on laisse passer pour la rétrocompatibilité
    socket.data.user = null;
    next();
    return;
  }

  try {
    const payload = AuthService.verifyToken(token);
    const user = AuthService.getUser(payload.userId);

    if (!user) {
      next(new Error('Utilisateur introuvable'));
      return;
    }

    socket.data.user = {
      userId: payload.userId,
      username: payload.username,
      displayName: user.displayName,
    };

    // Tracker l'utilisateur en ligne
    if (!onlineUsers.has(payload.userId)) {
      onlineUsers.set(payload.userId, new Set());
    }
    onlineUsers.get(payload.userId)!.add(socket.id);

    next();
  } catch {
    next(new Error('Token invalide'));
  }
}

export function handleSocketDisconnect(socket: Socket) {
  const user = socket.data.user;
  if (user?.userId) {
    const sockets = onlineUsers.get(user.userId);
    if (sockets) {
      sockets.delete(socket.id);
      if (sockets.size === 0) {
        onlineUsers.delete(user.userId);
      }
    }
  }
}
