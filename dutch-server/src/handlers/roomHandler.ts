import { Socket, Server } from 'socket.io';
import { RoomManager } from '../services/RoomManager';
import { onPublicRoomCreated, onPublicRoomPlayerJoined, onPublicRoomPlayerLeft } from './publicRoomHandlers';
import { ValidationService } from '../services/ValidationService';
import { SecurityService } from '../services/SecurityService';
import { AuthenticatedSocket } from '../middleware/socketAuthMiddleware';
import { FriendsService } from '../services/FriendsService';
import { firestoreService } from '../services/FirestoreService';
import { PushNotificationService } from '../services/PushNotificationService';

export function setupRoomHandler(socket: Socket, roomManager: RoomManager, io?: Server) {
  const authSocket = socket as AuthenticatedSocket;
  const socketUser = authSocket.data.user;

  socket.on('room:create', (data, callback) => {
    try {
      // Utiliser le nom du compte si authentifié, sinon sanitize le nom fourni
      const playerName = socketUser?.displayName
        || ValidationService.sanitizePlayerName(data.playerName);

      const room = roomManager.createRoom(
        socket.id,
        data.settings,
        playerName,
        data.clientId,
        socketUser?.uid
      );
      socket.join(room.id);
      roomManager.broadcastPresence(room.id);

      console.log(`Room created: ${room.id} by ${socket.id}`);

      // Si c'est une room publique, l'ajouter au service
      if (data.settings?.isPublic === true) {
        onPublicRoomCreated(
          room.id,
          data.playerName || 'Joueur',
          data.settings.gameMode || 'quick',
          data.settings.numberOfPlayers || 4,
          undefined,
          data.settings.roomName
        );
      }

      // Sauvegarder en DB si authentifié
      if (socketUser?.uid) {
        firestoreService.saveRoomToUser(socketUser.uid, room.id, true).catch(() => { /* best effort */ });
      }

      callback({ success: true, roomCode: room.id, room });
    } catch (error: any) {
      console.error('Error creating room:', error);
      callback({ success: false, error: error.message });
    }
  });

  socket.on('room:join', async (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();

      // Rate limit sur les tentatives de join
      const joinAllowed = await SecurityService.checkJoinAttemptLimit(socket.handshake.address);
      if (!joinAllowed) {
        callback({ success: false, error: 'Trop de tentatives, réessayez dans une minute' });
        return;
      }

      const playerName = socketUser?.displayName
        || ValidationService.sanitizePlayerName(data.playerName);

      const result = roomManager.joinRoom(
        roomCode,
        socket.id,
        playerName,
        data.clientId,
        socketUser?.uid
      );

      if (result.error || !result.room) {
        callback({ success: false, error: result.error ?? 'Room introuvable' });
        return;
      }

      socket.join(roomCode);
      if (result.player) {
        roomManager.notifyPlayerJoined(roomCode, result.player);
      }

      roomManager.broadcastPresence(roomCode);

      // Mettre à jour le compteur pour les rooms publiques
      if (result.room) {
        onPublicRoomPlayerJoined(roomCode, result.room.players.length);
      }

      // Sauvegarder en DB si authentifié
      if (socketUser?.uid) {
        firestoreService.saveRoomToUser(socketUser.uid, roomCode, false).catch(() => { /* best effort */ });
      }

      console.log(`Player ${socket.id} joined room ${roomCode}`);
      callback({ success: true, room: result.room });
    } catch (error: any) {
      console.error('Error joining room:', error);
      callback({ success: false, error: error.message });
    }
  });

  socket.on('room:ready', (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      const ready = data.ready !== false;
      const success = roomManager.setReady(roomCode, socket.id, ready);
      callback?.({ success });
    } catch (error: any) {
      console.error('Error setting ready state:', error);
      callback?.({ success: false, error: error.message });
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

      const minPlayers =
        typeof room.settings?.minPlayers === 'number'
          ? room.settings.minPlayers
          : 2;
      const readyHumans = room.players.filter(
        (p) => p.isHuman && p.connected !== false && p.ready
      ).length;
      if (!room.players.find((p) => p.id === socket.id)?.ready) {
        callback({
          success: false,
          error: "L'hôte doit être prêt",
        });
        return;
      }
      if (readyHumans < minPlayers) {
        callback({
          success: false,
          error: `Minimum ${minPlayers} joueurs prêts requis`,
        });
        return;
      }

      // Utiliser fillBots des settings de la room par défaut, sauf si explicitement spécifié
      const fillBots = data.fillBots !== undefined ? data.fillBots === true : room.settings?.fillBots !== false;
      const started = roomManager.startGame(roomCode, {
        fillBots,
      });
      callback({ success: started });

      if (!started) return;

      console.log(`Game started in room ${roomCode}`);

      roomManager.broadcastGameState(roomCode, 'GAME_STARTED', {
        message: 'La partie commence !',
        reactionTimeMs: room.settings?.reactionTimeMs ?? 3000,
      });
      roomManager.broadcastPresence(roomCode);

      await roomManager.checkAndPlayBotTurn(roomCode);
    } catch (error: any) {
      console.error('Error starting game:', error);
      callback({ success: false, error: error.message });
    }
  });

  socket.on('chat:send', (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      const message = ValidationService.sanitizeChatMessage(data.message);
      if (!message) {
        callback?.({ success: false, error: 'Message vide' });
        return;
      }
      const success = roomManager.sendChat(roomCode, socket.id, message);
      callback?.({ success });
    } catch (error: any) {
      console.error('Error sending chat message:', error);
      callback?.({ success: false, error: error.message });
    }
  });

  socket.on('room:leave', (data) => {
    const { roomCode } = data;
    socket.leave(roomCode);
    roomManager.handleLeave(roomCode, socket.id);

    // Mettre à jour le compteur pour les rooms publiques
    const updatedRoom = roomManager.getRoom(roomCode);
    if (updatedRoom) {
      onPublicRoomPlayerLeft(roomCode, updatedRoom.players.length);
    } else {
      // La room n'existe plus, la supprimer du service public
      onPublicRoomPlayerLeft(roomCode, 0);
    }

    console.log(`Player ${socket.id} left room ${roomCode}`);
  });

  // Fermer la room (hôte uniquement)
  socket.on('room:close', (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      const result = roomManager.closeRoom(roomCode, socket.id);

      if (result.success) {
        socket.leave(roomCode);
        // Supprimer du service de rooms publiques
        onPublicRoomPlayerLeft(roomCode, 0);
        console.log(`Room ${roomCode} closed by host ${socket.id}`);
      }

      callback(result);
    } catch (error: any) {
      console.error('Error closing room:', error);
      callback({ success: false, reason: error.message });
    }
  });

  // Devenir hôte d'une room fermée
  socket.on('room:transfer_host', (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      const success = roomManager.transferHost(roomCode, socket.id);

      if (success) {
        console.log(`Host transferred to ${socket.id} in room ${roomCode}`);
      }

      callback({ success });
    } catch (error: any) {
      console.error('Error transferring host:', error);
      callback({ success: false, error: error.message });
    }
  });

  // Vérifier quelles rooms sont actives
  socket.on('room:check_active', (data, callback) => {
    try {
      const roomCodes = data.roomCodes as string[] | undefined;
      if (!roomCodes || !Array.isArray(roomCodes)) {
        callback({ rooms: [] });
        return;
      }

      const activeRooms = roomManager.checkActiveRooms(roomCodes);
      callback({ rooms: activeRooms });
    } catch (error: any) {
      console.error('Error checking active rooms:', error);
      callback({ rooms: [] });
    }
  });

  // Changer le mode de jeu (hôte uniquement, en lobby)
  socket.on('room:set_game_mode', (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      const gameMode = data.gameMode as number;

      const success = roomManager.setGameMode(roomCode, socket.id, gameMode);

      if (success) {
        console.log(`Game mode changed to ${gameMode} in room ${roomCode}`);
      }

      callback({ success });
    } catch (error: any) {
      console.error('Error setting game mode:', error);
      callback({ success: false, error: error.message });
    }
  });

  // Demande de synchronisation complète de l'état
  socket.on('game:request_state', (data) => {
    const roomCode = data.roomCode?.toString().toUpperCase();
    roomManager.sendFullStateToPlayer(roomCode, socket.id);
  });

  // Relancer une partie (rematch)
  socket.on('room:restart', (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      const success = roomManager.restartGame(roomCode, socket.id);

      if (success) {
        console.log(`Game restarted in room ${roomCode} by ${socket.id}`);
      }

      callback({ success });
    } catch (error: any) {
      console.error('Error restarting game:', error);
      callback({ success: false, error: error.message });
    }
  });

  // Kick un joueur (hôte uniquement) - le joueur PEUT revenir
  socket.on('room:kick', (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      const targetClientId = data.clientId?.toString();

      if (!targetClientId) {
        callback({ success: false, error: 'clientId requis' });
        return;
      }

      const success = roomManager.kickPlayer(roomCode, socket.id, targetClientId);

      if (success) {
        console.log(`Player ${targetClientId} kicked from ${roomCode} (can rejoin)`);
      }

      callback({ success });
    } catch (error: any) {
      console.error('Error kicking player:', error);
      callback({ success: false, error: error.message });
    }
  });

  // Envoyer un emote à tous les joueurs de la room
  socket.on('game:emote', (data) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      if (!roomCode) return;

      // Broadcast l'emote à tous les joueurs de la room (y compris l'envoyeur)
      socket.to(roomCode).emit('game:emote', {
        emoji: data.emoji,
        playerName: data.playerName,
        playerId: socket.id,
      });
    } catch (error) {
      console.error('Error sending emote:', error);
    }
  });

  // Bannir un joueur définitivement (hôte uniquement) - le joueur NE PEUT PAS revenir
  socket.on('room:ban', (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      const targetClientId = data.clientId?.toString();

      if (!targetClientId) {
        callback({ success: false, error: 'clientId requis' });
        return;
      }

      const success = roomManager.banPlayer(roomCode, socket.id, targetClientId);

      if (success) {
        console.log(`Player ${targetClientId} BANNED from ${roomCode}`);
      }

      callback({ success });
    } catch (error: any) {
      console.error('Error banning player:', error);
      callback({ success: false, error: error.message });
    }
  });

  // Inviter un ami dans un salon (authentifié uniquement)
  socket.on('room:invite', async (data, callback) => {
    try {
      if (!socketUser) {
        callback?.({ success: false, error: 'Authentification requise' });
        return;
      }

      const { roomCode, friendUserId } = data;
      if (!roomCode || !friendUserId) {
        callback?.({ success: false, error: 'roomCode et friendUserId requis' });
        return;
      }

      // Vérifier que c'est bien un ami
      const friends = await FriendsService.getFriends(socketUser.uid);
      const isFriend = friends.some(f => f.userId === friendUserId);
      if (!isFriend) {
        callback?.({ success: false, error: 'Ce joueur n\'est pas ton ami' });
        return;
      }

      // Notification temps réel via socket
      const friendSocketIds = FriendsService.getUserSocketIds(friendUserId);
      const inviterName = socketUser.displayName || socketUser.username;
      for (const sid of friendSocketIds) {
        io?.to(sid).emit('room:invite', {
          roomCode,
          fromUserId: socketUser.uid,
          fromUsername: socketUser.username,
          fromDisplayName: inviterName,
        });
      }

      // Notification push
      await PushNotificationService.notifyRoomInvite(friendUserId, inviterName, roomCode);

      callback?.({ success: true });
    } catch (error: any) {
      console.error('Error inviting friend:', error);
      callback?.({ success: false, error: error.message });
    }
  });

  // Notifications friend temps réel (envoyées quand des actions friends arrivent via REST)
  // Ces listeners sont pour les événements émis par le serveur lui-même
  socket.on('friend:send_request', async (data, callback) => {
    try {
      if (!socketUser) {
        callback?.({ success: false, error: 'Authentification requise' });
        return;
      }

      const { username } = data;
      const result = await FriendsService.sendRequest(socketUser.uid, username);

      if (result.success && result.toUserId) {
        // Notifier le destinataire via socket
        const targetSocketIds = FriendsService.getUserSocketIds(result.toUserId);
        const senderUser = await firestoreService.getUser(socketUser.uid);
        for (const sid of targetSocketIds) {
          io?.to(sid).emit('friend:request_received', {
            requestId: result.requestId,
            fromUserId: socketUser.uid,
            fromUsername: socketUser.username,
            fromDisplayName: senderUser?.displayName || socketUser.username,
          });
        }

        // Push notification
        await PushNotificationService.notifyFriendRequest(
          result.toUserId,
          socketUser.username,
          senderUser?.displayName || socketUser.username
        );
      }

      callback?.(result);
    } catch (error: any) {
      callback?.({ success: false, error: error.message });
    }
  });

  socket.on('friend:accept_request', async (data, callback) => {
    try {
      if (!socketUser) {
        callback?.({ success: false, error: 'Authentification requise' });
        return;
      }

      const { requestId } = data;
      const result = await FriendsService.acceptRequest(socketUser.uid, requestId);

      if (result.success && result.toUserId) {
        // Notifier l'expéditeur original
        const targetSocketIds = FriendsService.getUserSocketIds(result.toUserId);
        const accepterUser = await firestoreService.getUser(socketUser.uid);
        for (const sid of targetSocketIds) {
          io?.to(sid).emit('friend:accepted', {
            userId: socketUser.uid,
            username: socketUser.username,
            displayName: accepterUser?.displayName || socketUser.username,
          });
        }

        // Push notification
        await PushNotificationService.notifyFriendAccepted(
          result.toUserId,
          socketUser.username,
          accepterUser?.displayName || socketUser.username
        );
      }

      callback?.(result);
    } catch (error: any) {
      callback?.({ success: false, error: error.message });
    }
  });
}
