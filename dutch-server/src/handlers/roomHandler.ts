import { Socket, Server } from 'socket.io';
import { RoomManager } from '../services/RoomManager';
import { onPublicRoomCreated, onPublicRoomPlayerJoined, onPublicRoomPlayerLeft } from './publicRoomHandlers';
import { ValidationService } from '../services/ValidationService';
import { SecurityService } from '../services/SecurityService';
import { AuthenticatedSocket } from '../middleware/socketAuthMiddleware';
import { FriendsService } from '../services/FriendsService';
import { firestoreService } from '../services/FirestoreService';
import { PushNotificationService } from '../services/PushNotificationService';
import { GameMode } from '../models/GameState';
import { RoomStatus } from '../models/Room';
import {
  FIREBASE_UNAVAILABLE_ERROR_CODE,
  isRoomRegistryUnavailableError,
  roomRegistryService,
} from '../services/RoomRegistryService';

export function setupRoomHandler(socket: Socket, roomManager: RoomManager, io?: Server) {
  const authSocket = socket as AuthenticatedSocket;
  const socketUser = authSocket.data.user;

  const firebaseDownPayload = {
    success: false,
    errorCode: FIREBASE_UNAVAILABLE_ERROR_CODE,
    error:
      'Service multijoueur temporairement indisponible (Firebase). Vérifie https://downdetector.com/status/firebase/',
  };

  const authRequiredPayload = {
    success: false,
    errorCode: 'AUTH_REQUIRED',
    error: 'Connexion requise pour le multijoueur.',
  };

  const handleRegistryError = (error: unknown, callback: (payload: Record<string, unknown>) => void) => {
    if (isRoomRegistryUnavailableError(error)) {
      callback(firebaseDownPayload);
      return true;
    }
    return false;
  };

  socket.on('room:create', async (data, callback) => {
    try {
      if (!socketUser?.uid) {
        callback(authRequiredPayload);
        return;
      }
      roomRegistryService.ensureAvailable();

      // Utiliser le nom du compte authentifié
      const playerName = socketUser.displayName || 'Joueur';

      const room = roomManager.createRoom(
        socket.id,
        data.settings,
        playerName,
        data.clientId,
        socketUser?.uid,
        socketUser?.username
      );
      socket.join(room.id);
      let createdPublicRoom = false;

      // Si c'est une room publique, l'ajouter au service
      if (data.settings?.isPublic === true) {
        onPublicRoomCreated(
          room.id,
          playerName,
          data.settings.gameMode || 'quick',
          data.settings.numberOfPlayers || 4,
          undefined,
          data.settings.roomName
        );
        createdPublicRoom = true;
      }

      const localHost = room.players.find((p) => p.id === socket.id);
      try {
        await roomRegistryService.upsertRoom(room);
        if (localHost) {
          await roomRegistryService.upsertMember(room, localHost);
        }
        roomRegistryService.bindSocketMembership(socket.id, room.id, socketUser.uid);
      } catch (syncError) {
        socket.leave(room.id);
        roomManager.handleLeave(room.id, socket.id);
        if (createdPublicRoom) {
          onPublicRoomPlayerLeft(room.id, 0);
        }
        if (handleRegistryError(syncError, callback)) {
          return;
        }
        throw syncError;
      }

      roomManager.broadcastPresence(room.id);
      console.log(`Room created: ${room.id} by ${socket.id}`);

      callback({ success: true, roomCode: room.id, room });
    } catch (error: any) {
      if (handleRegistryError(error, callback)) {
        return;
      }
      console.error('Error creating room:', error);
      callback({ success: false, error: error.message });
    }
  });

  socket.on('room:join', async (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      if (!roomCode) {
        callback({ success: false, error: 'Code de salon invalide' });
        return;
      }
      if (!socketUser?.uid) {
        callback(authRequiredPayload);
        return;
      }
      roomRegistryService.ensureAvailable();

      // Rate limit sur les tentatives de join
      const joinAllowed = await SecurityService.checkJoinAttemptLimit(socket);
      if (!joinAllowed) {
        callback({ success: false, error: 'Trop de tentatives, réessayez dans une minute' });
        return;
      }

      const playerName = socketUser.displayName || 'Joueur';

      const duplicateConnected = roomManager.findConnectedPlayerByUserId(
        roomCode,
        socketUser.uid
      );
      if (duplicateConnected && duplicateConnected.id !== socket.id) {
        io?.to(duplicateConnected.id).emit('room:duplicate_login_attempt', {
          roomCode,
          attemptedAt: Date.now(),
        });
        callback({
          success: false,
          errorCode: 'ALREADY_IN_ROOM',
          error:
            'Tu es déjà dans ce salon sur un autre appareil. Reviens sur ta session active.',
        });
        return;
      }

      roomManager.detachIdentityFromOtherRooms(roomCode, {
        socketId: socket.id,
        userId: socketUser.uid,
        username: socketUser.username,
        clientId: data.clientId?.toString(),
      });

      const result = roomManager.joinRoom(
        roomCode,
        socket.id,
        playerName,
        data.clientId,
        socketUser.uid,
        socketUser.username
      );

      if (result.error || !result.room) {
        callback({ success: false, error: result.error ?? 'Room introuvable' });
        return;
      }

      // Remove previous socket from room channel to avoid duplicate events
      if (result.previousSocketId) {
        const prevSocket = io?.sockets.sockets.get(result.previousSocketId);
        if (prevSocket) {
          prevSocket.leave(roomCode);
        }
      }

      socket.join(roomCode);

      const localPlayer =
        result.player ??
        result.room.players.find(
          (p) => p.id === socket.id || p.userId?.trim() === socketUser.uid
        );

      try {
        await roomRegistryService.upsertRoom(result.room);
        if (localPlayer) {
          await roomRegistryService.upsertMember(result.room, localPlayer);
        }
        roomRegistryService.bindSocketMembership(socket.id, roomCode, socketUser.uid);
      } catch (syncError) {
        socket.leave(roomCode);
        roomManager.handleLeave(roomCode, socket.id);
        if (handleRegistryError(syncError, callback)) {
          return;
        }
        throw syncError;
      }

      if (result.player) {
        roomManager.notifyPlayerJoined(roomCode, result.player);
      }

      roomManager.broadcastPresence(roomCode);

      // Mettre à jour le compteur pour les rooms publiques
      if (result.room) {
        onPublicRoomPlayerJoined(roomCode, result.room.players.length);
      }

      console.log(`Player ${socket.id} joined room ${roomCode}`);
      callback({ success: true, room: result.room });
    } catch (error: any) {
      if (handleRegistryError(error, callback)) {
        return;
      }
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
      const fillBots = data.fillBots === undefined ? room.settings?.fillBots !== false : data.fillBots === true;
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
    const roomCode = data?.roomCode?.toString().toUpperCase();
    if (!roomCode) return;
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

    if (socketUser?.uid) {
      roomRegistryService.unbindSocketMembership(socket.id);
      void roomRegistryService
        .removeMember(roomCode, socketUser.uid)
        .then(async () => {
          const room = roomManager.getRoom(roomCode);
          if (room) {
            await roomRegistryService.upsertRoom(room);
          } else {
            await roomRegistryService.archiveRoom(roomCode, [socketUser.uid]);
          }
        })
        .catch((error) => {
          if (!isRoomRegistryUnavailableError(error)) {
            console.error('Error syncing leave to room registry:', error);
          }
        });
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
        roomRegistryService.unbindSocketMembership(socket.id);
        void roomRegistryService.archiveRoom(roomCode).catch((error) => {
          if (!isRoomRegistryUnavailableError(error)) {
            console.error('Error archiving room in room registry:', error);
          }
        });
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
        if (socketUser?.uid) {
          const room = roomManager.getRoom(roomCode);
          const requester = room?.players.find((p) => p.id === socket.id);
          if (room && requester) {
            void roomRegistryService
              .upsertRoom(room)
              .then(async () => {
                await roomRegistryService.upsertMember(room, requester);
                roomRegistryService.bindSocketMembership(
                  socket.id,
                  roomCode,
                  socketUser.uid
                );
              })
              .catch((error) => {
                if (!isRoomRegistryUnavailableError(error)) {
                  console.error('Error syncing host transfer to room registry:', error);
                }
              });
          }
        }
        console.log(`Host transferred to ${socket.id} in room ${roomCode}`);
      }

      callback({ success });
    } catch (error: any) {
      console.error('Error transferring host:', error);
      callback({ success: false, error: error.message });
    }
  });

  // Récupérer les rooms actives où le joueur est présent
  socket.on('room:my_active', (data, callback) => {
    try {
      const userId = socketUser?.uid;
      if (!userId) {
        callback({ ...authRequiredPayload, rooms: [] });
        return;
      }
      roomRegistryService.ensureAvailable();

      void roomRegistryService.syncFromRoomManager(roomManager);

      roomRegistryService
        .getUserActiveRooms(userId)
        .then(async (entries) => {
          const rooms: Array<{ roomCode: string; status: string; playerCount: number; isHost: boolean }> = [];
          const staleRoomCodes: string[] = [];

          for (const entry of entries) {
            const room = roomManager.getRoom(entry.roomCode);
            if (!room || room.status === 'closing') {
              staleRoomCodes.push(entry.roomCode);
              continue;
            }
            const member = room.players.find(
              (player) => player.isHuman && player.userId?.trim() === userId
            );
            if (!member) {
              staleRoomCodes.push(entry.roomCode);
              continue;
            }
            const host = room.players.find((p) => p.id === room.hostPlayerId);
            const isHost = host?.userId?.trim() === userId;
            const active = roomManager.checkActiveRooms([entry.roomCode])[0];
            rooms.push({
              roomCode: entry.roomCode,
              status: active?.status ?? room.status,
              playerCount: active?.playerCount ?? entry.playerCount,
              isHost,
            });
          }

          for (const staleCode of staleRoomCodes) {
            await roomRegistryService.removeActiveRoomForUser(userId, staleCode);
          }

          callback({ success: true, rooms });
        })
        .catch((error) => {
          if (isRoomRegistryUnavailableError(error)) {
            callback({ ...firebaseDownPayload, rooms: [] });
            return;
          }
          console.error('Error getting my active rooms:', error);
          callback({ rooms: [] });
        });
    } catch (error: any) {
      if (isRoomRegistryUnavailableError(error)) {
        callback({ ...firebaseDownPayload, rooms: [] });
        return;
      }
      console.error('Error getting my active rooms:', error);
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
  socket.on('room:restart', async (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      let success = roomManager.restartGame(roomCode, socket.id);

      if (success) {
        const room = roomManager.getRoom(roomCode);

        if (room?.gameMode === GameMode.tournament &&
            room.status === RoomStatus.waiting) {
          success = roomManager.startGame(roomCode, {
            fillBots: room.settings?.fillBots !== false,
          });

          if (success) {
            roomManager.broadcastGameState(roomCode, 'GAME_STARTED', {
              message: 'La manche suivante commence !',
              reactionTimeMs: room.settings?.reactionTimeMs ?? 3000,
            });
            roomManager.broadcastPresence(roomCode);
            await roomManager.checkAndPlayBotTurn(roomCode);
          }
        }

        console.log(`Game restarted in room ${roomCode} by ${socket.id}`);
      }

      callback({ success });
    } catch (error: any) {
      console.error('Error restarting game:', error);
      callback({ success: false, error: error.message });
    }
  });

  // Retour au salon (n'importe quel joueur, partie terminée)
  socket.on('room:backToLobby', (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      const success = roomManager.backToLobby(roomCode, socket.id);
      callback({ success });
    } catch (error: any) {
      console.error('Error returning to lobby:', error);
      callback({ success: false, error: error.message });
    }
  });

  // Kick un joueur (hôte uniquement) - le joueur PEUT revenir
  socket.on('room:kick', (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      const targetClientId = data.clientId?.toString();
      const roomBefore = roomManager.getRoom(roomCode);
      const kickedUid = roomBefore?.players.find(
        (p) => p.clientId === targetClientId
      )?.userId;

      if (!targetClientId) {
        callback({ success: false, error: 'clientId requis' });
        return;
      }

      const success = roomManager.kickPlayer(roomCode, socket.id, targetClientId);

      if (success) {
        if (kickedUid) {
          void roomRegistryService.removeMember(roomCode, kickedUid).catch((error) => {
            if (!isRoomRegistryUnavailableError(error)) {
              console.error('Error syncing kick to room registry:', error);
            }
          });
        }
        const updatedRoom = roomManager.getRoom(roomCode);
        if (updatedRoom) {
          void roomRegistryService.upsertRoom(updatedRoom).catch((error) => {
            if (!isRoomRegistryUnavailableError(error)) {
              console.error('Error updating room after kick:', error);
            }
          });
        }
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
      const roomBefore = roomManager.getRoom(roomCode);
      const bannedUid = roomBefore?.players.find(
        (p) => p.clientId === targetClientId
      )?.userId;

      if (!targetClientId) {
        callback({ success: false, error: 'clientId requis' });
        return;
      }

      const success = roomManager.banPlayer(roomCode, socket.id, targetClientId);

      if (success) {
        if (bannedUid) {
          void roomRegistryService.removeMember(roomCode, bannedUid).catch((error) => {
            if (!isRoomRegistryUnavailableError(error)) {
              console.error('Error syncing ban to room registry:', error);
            }
          });
        }
        const updatedRoom = roomManager.getRoom(roomCode);
        if (updatedRoom) {
          void roomRegistryService.upsertRoom(updatedRoom).catch((error) => {
            if (!isRoomRegistryUnavailableError(error)) {
              console.error('Error updating room after ban:', error);
            }
          });
        }
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

      const inviterName = socketUser.displayName || socketUser.username;

      // Récupérer les infos de l'ami pour l'ajouter au salon
      const friendUser = await firestoreService.getUser(friendUserId);
      const friendDisplayName = friendUser?.displayName?.trim() || friendUser?.username?.trim() || 'Joueur';
      const friendUsername = friendUser?.username?.trim() || '';

      // Ajouter l'ami comme joueur déconnecté dans la room
      const normalizedRoomCode = roomCode.toString().toUpperCase();
      const player = roomManager.addInvitedPlayer(
        normalizedRoomCode,
        friendUserId,
        friendUsername,
        friendDisplayName
      );
      if (player) {
        const room = roomManager.getRoom(normalizedRoomCode);
        if (room) {
          roomRegistryService.upsertMember(room, player).catch(() => {});
        }
      }

      // Enregistrer le salon dans activeRooms de l'ami
      roomRegistryService.registerInvitedMember(normalizedRoomCode, friendUserId).catch(() => {});

      // Notification temps réel via socket
      const friendSocketIds = FriendsService.getUserSocketIds(friendUserId);
      for (const sid of friendSocketIds) {
        io?.to(sid).emit('room:invite', {
          roomCode: normalizedRoomCode,
          fromUserId: socketUser.uid,
          fromUsername: socketUser.username,
          fromDisplayName: inviterName,
        });
      }

      // Notification push
      await PushNotificationService.notifyRoomInvite(friendUserId, inviterName, normalizedRoomCode);

      callback?.({ success: true });
    } catch (error: any) {
      console.error('Error inviting friend:', error);
      callback?.({ success: false, error: error.message });
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // WIZZ - Notification pour rappeler un joueur absent du lobby
  // ═══════════════════════════════════════════════════════════════════════════

  const wizzCooldowns = new Map<string, number>(); // socketId -> last wizz timestamp

  socket.on('room:wizz', async (data, callback) => {
    try {
      const roomCode = data.roomCode?.toString().toUpperCase();
      const targetClientId = data.targetClientId?.toString();

      if (!roomCode || !targetClientId) {
        callback?.({ success: false, error: 'roomCode et targetClientId requis' });
        return;
      }

      const room = roomManager.getRoom(roomCode);
      if (!room) {
        callback?.({ success: false, error: 'Room introuvable' });
        return;
      }

      // Vérifier que l'expéditeur est dans la room
      const sender = room.players.find((p) => p.id === socket.id);
      if (!sender) {
        callback?.({ success: false, error: 'Vous n\'êtes pas dans cette room' });
        return;
      }

      // Trouver la cible
      const target = room.players.find((p) => p.clientId === targetClientId);
      if (!target) {
        callback?.({ success: false, error: 'Joueur cible introuvable' });
        return;
      }

      // Permission: joueur→hôte OU hôte→joueur
      const senderIsHost = room.hostPlayerId === socket.id;
      const targetIsHost = room.hostPlayerId === target.id;
      if (!senderIsHost && !targetIsHost) {
        callback?.({ success: false, error: 'Vous ne pouvez wizzer que l\'hôte (ou l\'hôte peut wizzer les autres)' });
        return;
      }

      // Vérifier que la cible n'est pas connectée+focused (pas besoin de wizz)
      if (target.connected !== false && target.focused === true) {
        callback?.({ success: false, error: 'Ce joueur est déjà actif dans le lobby' });
        return;
      }

      // Rate limit: 1 wizz / 30s par expéditeur
      const now = Date.now();
      const lastWizz = wizzCooldowns.get(socket.id) ?? 0;
      if (now - lastWizz < 30000) {
        const remaining = Math.ceil((30000 - (now - lastWizz)) / 1000);
        callback?.({ success: false, error: `Attends encore ${remaining}s avant de re-wizzer` });
        return;
      }
      wizzCooldowns.set(socket.id, now);

      // Émettre au socket de la cible si connecté
      if (target.id) {
        io?.to(target.id).emit('room:wizz', {
          fromName: sender.name,
          fromId: sender.clientId,
        });
      }

      // Push notification si la cible est déconnectée
      if (target.connected === false && target.userId) {
        await PushNotificationService.sendToUser(target.userId, {
          title: 'On t\'attend !',
          body: `${sender.name} te rappelle dans le salon`,
          data: { type: 'room_wizz', roomCode },
        });
      }

      console.log(`Wizz sent from ${sender.name} to ${target.name} in room ${roomCode}`);
      callback?.({ success: true });
    } catch (error: any) {
      console.error('Error sending wizz:', error);
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
