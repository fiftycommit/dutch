import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../models/game_state.dart';
import '../../models/game_settings.dart';
import '../../models/playing_card.dart';
import 'socket_connection_handler.dart';
import 'saved_rooms_repository.dart';
import 'game_actions_emitter.dart';

export 'socket_connection_handler.dart' show SocketConnectionState;
export 'saved_rooms_repository.dart' show SavedRoom;

/// MultiplayerService refactoré - Orchestrateur (~350 lignes au lieu de 1136)
/// Principe GRASP: Controller - Coordonne les sous-modules
class MultiplayerService {
  final SocketConnectionHandler _connectionHandler = SocketConnectionHandler();
  final SavedRoomsRepository _roomsRepository = SavedRoomsRepository();
  late final GameActionsEmitter _actionsEmitter;

  String? _currentRoomCode;

  MultiplayerService() {
    _actionsEmitter = GameActionsEmitter(
      getSocket: () => _connectionHandler.socket,
      getRoomCode: () => _currentRoomCode,
    );
    _connectionHandler.onReconnectToRoom = (roomCode, playerName) async {
      await joinRoom(roomCode: roomCode, playerName: playerName);
    };
  }

  // Délégations vers SocketConnectionHandler
  io.Socket? get socket => _connectionHandler.socket;
  bool get isConnected => _connectionHandler.isConnected;
  String? get playerId => _connectionHandler.playerId;
  String? get clientId => _connectionHandler.clientId;
  int get latencyMs => _connectionHandler.latencyMs;
  int get serverTimeOffsetMs => _connectionHandler.serverTimeOffsetMs;
  int get serverNowMs => _connectionHandler.serverNowMs;
  SocketConnectionState get connectionState =>
      _connectionHandler.connectionState;
  String? get currentRoomCode => _currentRoomCode;

  // Callbacks pour les événements
  Function(GameState)? onGameStateUpdate;
  Function(PlayingCard?)? onPreloadedDeckCardUpdate;
  Function(String)? onError;
  Function(Map<String, dynamic>)? onPlayerJoined;
  Function(int)? onTimerUpdate;
  Function(String)? onGameStarted;
  Function(int)? onReactionTimeConfig;
  Function(Map<String, dynamic>)? onPresenceUpdate;
  Function(Map<String, dynamic>)? onPresenceCheck;
  Function(Map<String, dynamic>)? onChatMessage;
  Function(SocketConnectionState)? onSocketConnectionStateChanged;
  Function(Map<String, dynamic>)? onRoomClosed;
  Function(Map<String, dynamic>)? onRoomRestarted;
  Function(Map<String, dynamic>)? onKicked;
  Function(Map<String, dynamic>)? onBanned;
  Function(Map<String, dynamic>)? onPlayerLeft;
  Function(Map<String, dynamic>)? onPlayerAfk;
  Function(Map<String, dynamic>)? onSpecialPowerTargeted;
  Function(Map<String, dynamic>)? onSpecialPowerTargetSelection;
  Function(PlayingCard, String)? onSpiedCard;
  Function(Map<String, dynamic>)? onSwapNotification;
  Function(Map<String, dynamic>)? onJokerNotification;
  Function(Map<String, dynamic>)? onSpyNotification;
  Function(String pausedByName, String pausedByPlayerId, int pauseDeadline)?
      onGamePaused;
  Function(String)? onGameResumed;
  Function(String pausedByName, int secondsRemaining)? onPauseWarning;
  Function(Map<String, dynamic>)? onGameAllReady;
  Function(Map<String, dynamic>)? onEmoteReceived;
  Function(Map<String, dynamic>)? onTournamentEliminated;
  Function(Map<String, dynamic>)? onTournamentEnded;
  Function(Map<String, dynamic>)? onDuplicateLoginAttempt;
  Function(String roomCode, String fromDisplayName)? onRoomInviteReceived;
  Function(Map<String, dynamic>)? onFriendRequestReceived;
  Function(Map<String, dynamic>)? onFriendAccepted;
  Function(Map<String, dynamic>)? onPrivateMessage;
  Function(Map<String, dynamic>)? onWizzReceived;

  // ═══════════════════════════════════════════════════════════════════════════
  // CONNEXION
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> checkServerHealth() async {
    try {
      final uri = Uri.parse('${SocketConnectionHandler.serverUrl}/health');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Server health check failed: $e');
      return false;
    }
  }

  /// Setter pour le token d'authentification (appelé par le provider)
  void setAuthToken(String? token) {
    _connectionHandler.setAuthToken(token);
    _roomsRepository.setAuthToken(token);
  }

  Future<void> connect() async {
    _connectionHandler.onConnectionStateChanged =
        onSocketConnectionStateChanged;
    _connectionHandler.onError = onError;
    await _connectionHandler.connect(_setupEventListeners);
  }

  void disconnect() {
    leaveRoom();
    _connectionHandler.disconnect();
  }

  void sendPresenceTimeoutKick(bool isForeground) {
    if (_currentRoomCode == null || playerId == null) return;
    socket?.emit('presence:timeout_kick', {
      'roomCode': _currentRoomCode,
      'playerId': playerId,
      'isForeground': isForeground,
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ROOMS SAUVEGARDÉES
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> removeSavedRoom(String roomCode) =>
      _roomsRepository.removeRoom(roomCode);

  Future<List<Map<String, dynamic>>?> getMyActiveRooms(
      {String? clientId}) async {
    try {
      if (!isConnected) await connect();
    } catch (_) {
      return null;
    }
    if (!isConnected || socket == null) return null;

    String? resolvedClientId = clientId;
    if (resolvedClientId == null || resolvedClientId.trim().isEmpty) {
      try {
        resolvedClientId = await _connectionHandler.ensureClientId();
      } catch (_) {
        resolvedClientId = null;
      }
    }

    final completer = Completer<List<Map<String, dynamic>>?>();

    socket?.emitWithAck(
      'room:my_active',
      {'clientId': resolvedClientId},
      ack: (response) {
        if (response == null) {
          completer.complete(null);
          return;
        }
        if (response is Map && response['success'] == false) {
          if (kDebugMode) {
            debugPrint(
                '⚠️ room:my_active error: ${_socketErrorMessage(response)}');
          }
          completer.complete(null);
          return;
        }
        if (response['rooms'] == null) {
          completer.complete(null);
          return;
        }
        final rooms = (response['rooms'] as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        completer.complete(rooms);
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () => null,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GESTION DES ROOMS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String?> createRoom(
      {required GameSettings settings, required String playerName}) async {
    if (!isConnected) await connect();

    final completer = Completer<String?>();
    final clientId = await _connectionHandler.ensureClientId();
    _connectionHandler.lastPlayerName = playerName;

    if (kDebugMode) debugPrint('🎲 Création d\'une room...');

    socket!.emitWithAck('room:create', {
      'settings': settings.toJson(),
      'playerName': playerName,
      'clientId': clientId,
    }, ack: (response) {
      if (response == null) {
        completer.completeError('Pas de réponse du serveur');
        return;
      }
      if (response['success'] == true) {
        _currentRoomCode = response['roomCode'];
        _connectionHandler.lastRoomCode = response['roomCode'];
        completer.complete(response['roomCode']);
      } else {
        completer.completeError(_socketErrorMessage(response));
      }
    });

    return completer.future;
  }

  Future<List<Map<String, dynamic>>?> getPublicRooms() async {
    if (!isConnected) await connect();

    final completer = Completer<List<Map<String, dynamic>>?>();

    try {
      socket!.emitWithAck('rooms:getPublic', {}, ack: (response) {
        if (completer.isCompleted) return;
        if (response == null) {
          completer.complete([]);
          return;
        }
        if (response is Map && response['success'] == true) {
          final rooms = response['rooms'] as List<dynamic>?;
          completer.complete(
              rooms?.map((r) => r as Map<String, dynamic>).toList() ?? []);
        } else {
          completer.complete([]);
        }
      });
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ fetchPublicRooms error: $e');
      completer.complete([]);
    }

    return completer.future
        .timeout(const Duration(seconds: 5), onTimeout: () => []);
  }

  Future<Map<String, dynamic>?> joinRoom(
      {required String roomCode, required String playerName}) async {
    if (!isConnected) await connect();

    final completer = Completer<Map<String, dynamic>?>();
    final clientId = await _connectionHandler.ensureClientId();
    _connectionHandler.lastPlayerName = playerName;

    socket!.emitWithAck('room:join', {
      'roomCode': roomCode.toUpperCase(),
      'playerName': playerName,
      'clientId': clientId,
    }, ack: (response) {
      if (response == null) {
        completer.completeError('Pas de réponse du serveur');
        return;
      }
      if (response['success'] == true) {
        _currentRoomCode = roomCode.toUpperCase();
        _connectionHandler.lastRoomCode = roomCode.toUpperCase();
        completer.complete(response['room'] as Map<String, dynamic>?);
      } else {
        completer.completeError(_socketErrorMessage(response));
      }
    });

    return completer.future;
  }

  void leaveRoom() {
    if (_currentRoomCode != null) {
      socket?.emit('room:leave', {'roomCode': _currentRoomCode});
      _connectionHandler.lastRoomCode = null;
      _currentRoomCode = null;
    }
  }

  Future<bool> closeRoom() async {
    if (_currentRoomCode == null) return false;
    final completer = Completer<bool>();

    socket?.emitWithAck('room:close', {'roomCode': _currentRoomCode},
        ack: (response) {
      final success = response?['success'] == true;
      if (success) {
        _connectionHandler.lastRoomCode = null;
        _currentRoomCode = null;
      }
      completer.complete(success);
    });

    return completer.future;
  }

  Future<bool> becomeHost(String roomCode) async {
    final completer = Completer<bool>();

    socket?.emitWithAck('room:transfer_host', {'roomCode': roomCode},
        ack: (response) {
      final success = response?['success'] == true;
      if (success) {
        _currentRoomCode = roomCode;
        _connectionHandler.lastRoomCode = roomCode;
      }
      completer.complete(success);
    });

    return completer.future;
  }

  Future<bool> startGame(
      {bool fillBots = false,
      int? numberOfBots,
      bool? useSBMM,
      int? botDifficulty}) async {
    if (_currentRoomCode == null) return false;
    final completer = Completer<bool>();

    final data = <String, dynamic>{
      'roomCode': _currentRoomCode,
      'fillBots': fillBots
    };
    if (numberOfBots != null) data['numberOfBots'] = numberOfBots;
    if (useSBMM != null) data['useSBMM'] = useSBMM;
    if (botDifficulty != null) data['botDifficulty'] = botDifficulty;

    socket!.emitWithAck('room:start_game', data, ack: (response) {
      completer.complete(response?['success'] == true);
    });

    return completer.future;
  }

  Future<bool> restartGame() async {
    if (_currentRoomCode == null) return false;
    final completer = Completer<bool>();

    socket?.emitWithAck('room:restart', {'roomCode': _currentRoomCode},
        ack: (response) {
      completer.complete(response?['success'] == true);
    });

    return completer.future;
  }

  Future<bool> kickPlayer(String clientId) async {
    if (_currentRoomCode == null) return false;
    final completer = Completer<bool>();

    socket?.emitWithAck(
        'room:kick', {'roomCode': _currentRoomCode, 'clientId': clientId},
        ack: (response) {
      completer.complete(response?['success'] == true);
    });

    return completer.future;
  }

  /// Bannir un joueur définitivement (ne peut plus revenir)
  Future<bool> banPlayer(String clientId) async {
    if (_currentRoomCode == null) return false;
    final completer = Completer<bool>();

    socket?.emitWithAck(
        'room:ban', {'roomCode': _currentRoomCode, 'clientId': clientId},
        ack: (response) {
      completer.complete(response?['success'] == true);
    });

    return completer.future;
  }

  Future<bool> setGameMode(int gameMode) async {
    if (_currentRoomCode == null) return false;
    final completer = Completer<bool>();

    socket?.emitWithAck('room:set_game_mode',
        {'roomCode': _currentRoomCode, 'gameMode': gameMode}, ack: (response) {
      completer.complete(response?['success'] == true);
    });

    return completer.future;
  }

  Future<bool> updateRoomSettings(
      {int? botDifficulty, int? luckDifficulty}) async {
    if (_currentRoomCode == null) return false;
    final completer = Completer<bool>();

    socket?.emitWithAck('room:update_settings', {
      'roomCode': _currentRoomCode,
      if (botDifficulty != null) 'botDifficulty': botDifficulty,
      if (luckDifficulty != null) 'luckDifficulty': luckDifficulty,
    }, ack: (response) {
      completer.complete(response?['success'] == true);
    });

    return completer.future;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS DE JEU (délégation)
  // ═══════════════════════════════════════════════════════════════════════════

  void drawCard() => _actionsEmitter.drawCard();
  void replaceCard(int cardIndex) => _actionsEmitter.replaceCard(cardIndex);
  void discardDrawnCard() => _actionsEmitter.discardDrawnCard();
  void takeFromDiscard() => _actionsEmitter.takeFromDiscard();
  void callDutch() => _actionsEmitter.callDutch();
  void attemptMatch(int cardIndex) => _actionsEmitter.attemptMatch(cardIndex);
  void usePower7LookOwnCard(int cardIndex) =>
      _actionsEmitter.usePower7LookOwnCard(cardIndex);
  void usePower10SpyOpponent(int targetPlayerIndex, int targetCardIndex) =>
      _actionsEmitter.usePower10SpyOpponent(targetPlayerIndex, targetCardIndex);
  void usePowerValetSwap(int p1, int c1, int p2, int c2) =>
      _actionsEmitter.usePowerValetSwap(p1, c1, p2, c2);
  void sendSpecialPowerTargetSelection(int? p1, int? c1, int? p2, int? c2) =>
      _actionsEmitter.sendSpecialPowerTargetSelection(p1, c1, p2, c2);
  void usePowerJokerShuffle(int targetPlayerIndex) =>
      _actionsEmitter.usePowerJokerShuffle(targetPlayerIndex);
  void skipSpecialPower() => _actionsEmitter.skipSpecialPower();
  void setReady(bool ready) => _actionsEmitter.setReady(ready);
  void sendChatMessage(String message) =>
      _actionsEmitter.sendChatMessage(message);
  void setFocused(bool focused) => _actionsEmitter.setFocused(focused);

  /// Émet le focus utilisateur global (indépendant de la room)
  /// Permet au serveur de marquer l'utilisateur hors-ligne quand l'app est en arrière-plan
  void setUserFocused(bool focused) {
    _connectionHandler.socket?.emit('user:focus', {'focused': focused});
  }

  Future<bool> sendWizz(String targetClientId) async {
    if (_currentRoomCode == null) return false;
    final completer = Completer<bool>();

    socket?.emitWithAck('room:wizz', {
      'roomCode': _currentRoomCode,
      'targetClientId': targetClientId,
    }, ack: (response) {
      completer.complete(response?['success'] == true);
    });

    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );
  }

  void confirmPresence() => _actionsEmitter.confirmPresence();
  void markReady() => _actionsEmitter.markReady();
  void cancelGame() => _actionsEmitter.cancelGame();
  void requestFullState() => _actionsEmitter.requestFullState();

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT LISTENERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _setupEventListeners(io.Socket socket) {
    // Nettoyer les anciens listeners pour éviter les doublons
    socket.clearListeners();

    socket.on('connect', (_) {
      if (kDebugMode) debugPrint('📡 Connecté au serveur Socket.IO');
    });

    socket.on('disconnect', (reason) {
      _connectionHandler.handleDisconnect(
          reason.toString(), _setupEventListeners);
    });

    socket.on('connect_error', (error) {
      onError?.call('Erreur de connexion: $error');
    });

    socket.on('game:state_update', (data) => _handleGameStateUpdate(data));
    socket.on('room:player_joined', (data) => onPlayerJoined?.call(data));
    socket.on('error', (error) => onError?.call(error.toString()));
    socket.on('presence:update', (data) {
      if (data is Map) onPresenceUpdate?.call(data.cast<String, dynamic>());
    });
    socket.on('presence:check', (data) {
      if (data is Map) onPresenceCheck?.call(data.cast<String, dynamic>());
    });
    socket.on('chat:message', (data) {
      if (data is Map) onChatMessage?.call(data.cast<String, dynamic>());
    });
    socket.on('room:closed', (data) {
      if (data is Map) onRoomClosed?.call(data.cast<String, dynamic>());
    });
    socket.on('game:all_ready', (data) {
      if (data is Map) onGameAllReady?.call(data.cast<String, dynamic>());
    });
    socket.on('room:restarted', (data) {
      if (data is Map) onRoomRestarted?.call(data.cast<String, dynamic>());
    });

    socket.on('room:kicked', (data) {
      // Kické mais peut revenir
      _currentRoomCode = null;
      _connectionHandler.lastRoomCode = null;
      if (data is Map) onKicked?.call(data.cast<String, dynamic>());
    });

    socket.on('room:banned', (data) {
      // Banni définitivement - ne peut plus revenir
      _currentRoomCode = null;
      _connectionHandler.lastRoomCode = null;
      if (data is Map) onBanned?.call(data.cast<String, dynamic>());
    });

    socket.on('player:left', (data) {
      if (data is Map) onPlayerLeft?.call(data.cast<String, dynamic>());
    });
    socket.on('player:afk', (data) {
      if (data is Map) onPlayerAfk?.call(data.cast<String, dynamic>());
    });
    socket.on('special_power:targeted', (data) {
      if (data is Map) {
        onSpecialPowerTargeted?.call(data.cast<String, dynamic>());
      }
    });
    socket.on('special_power:target_selection', (data) {
      if (data is Map) {
        onSpecialPowerTargetSelection?.call(data.cast<String, dynamic>());
      }
    });
    socket.on('special_power:swap_notification', (data) {
      if (data is Map) onSwapNotification?.call(data.cast<String, dynamic>());
    });
    socket.on('special_power:joker_notification', (data) {
      if (data is Map) onJokerNotification?.call(data.cast<String, dynamic>());
    });
    socket.on('special_power:spy_notification', (data) {
      if (data is Map) onSpyNotification?.call(data.cast<String, dynamic>());
    });

    socket.on('game:emote', (data) {
      if (data is Map) onEmoteReceived?.call(data.cast<String, dynamic>());
    });
    socket.on('tournament:eliminated', (data) {
      if (data is Map) {
        onTournamentEliminated?.call(data.cast<String, dynamic>());
      }
    });
    socket.on('tournament:ended', (data) {
      if (data is Map) onTournamentEnded?.call(data.cast<String, dynamic>());
    });
    socket.on('room:duplicate_login_attempt', (data) {
      if (data is Map) {
        onDuplicateLoginAttempt?.call(data.cast<String, dynamic>());
      }
    });

    socket.on('game:full_state', (data) {
      if (data is Map) {
        final gameStateJson = data['gameState'] as Map<String, dynamic>?;
        if (gameStateJson != null) {
          try {
            onGameStateUpdate?.call(GameState.fromJson(gameStateJson));
          } catch (_) {}
        }
      }
    });

    socket.on('room:invite', (data) {
      if (data is Map) {
        final roomCode = data['roomCode'] as String?;
        final fromDisplayName = data['fromDisplayName'] as String? ?? 'Un ami';
        if (roomCode != null) {
          onRoomInviteReceived?.call(roomCode.toUpperCase(), fromDisplayName);
        }
      }
    });

    socket.on('friend:request_received', (data) {
      if (data is Map) {
        onFriendRequestReceived?.call(data.cast<String, dynamic>());
      }
    });
    socket.on('friend:accepted', (data) {
      if (data is Map) {
        onFriendAccepted?.call(data.cast<String, dynamic>());
      }
    });
    socket.on('chat:private_message', (data) {
      if (data is Map) {
        onPrivateMessage?.call(data.cast<String, dynamic>());
      }
    });

    socket.on('room:wizz', (data) {
      if (data is Map) {
        onWizzReceived?.call(data.cast<String, dynamic>());
      }
    });

    socket.on('game:pause_warning', (data) {
      if (data is Map) {
        final pausedBy = data['pausedBy'] as String? ?? 'Inconnu';
        final secondsRemaining = data['secondsRemaining'] as int? ?? 0;
        onPauseWarning?.call(pausedBy, secondsRemaining);
      }
    });

    socket.on('game:spied_card', (data) {
      if (data is Map) {
        try {
          final cardJson = data['card'] as Map<String, dynamic>?;
          final targetName = data['targetPlayerName'] as String? ?? 'Inconnu';
          if (cardJson != null) {
            onSpiedCard?.call(PlayingCard.fromJson(cardJson), targetName);
          }
        } catch (_) {}
      }
    });
  }

  String _socketErrorMessage(dynamic response) {
    if (response is! Map) return 'Erreur inconnue';
    final code = response['errorCode']?.toString();
    final fallback = response['error']?.toString() ?? 'Erreur inconnue';
    switch (code) {
      case 'BACKEND_UNAVAILABLE_FIREBASE':
        return 'Service multijoueur temporairement indisponible (Firebase). Vérifie https://downdetector.com/status/firebase/';
      case 'ALREADY_IN_ROOM':
        return 'Tu es déjà dans ce salon sur un autre appareil.';
      case 'AUTH_REQUIRED':
        return 'Connexion requise pour le multijoueur.';
      default:
        return fallback;
    }
  }

  void _handleGameStateUpdate(dynamic data) {
    final updateType = data['type'] as String?;
    final gameStateJson = data['gameState'] as Map<String, dynamic>?;

    if (updateType == 'GAME_STARTED') {
      onGameStarted?.call(data['message'] as String? ?? '');
    } else if (updateType == 'GAME_PAUSED') {
      final pausedBy = data['pausedBy'] as String? ?? 'Inconnu';
      final pausedByPlayerId = data['pausedByPlayerId'] as String? ?? '';
      final pauseDeadline = data['pauseDeadline'] as int? ?? 0;
      onGamePaused?.call(pausedBy, pausedByPlayerId, pauseDeadline);
    } else if (updateType == 'GAME_RESUMED') {
      onGameResumed?.call(data['resumedBy'] as String? ?? 'Inconnu');
    }

    final reactionTimeMs = data['reactionTimeMs'];
    if (reactionTimeMs is int) onReactionTimeConfig?.call(reactionTimeMs);

    if (gameStateJson != null) {
      try {
        onGameStateUpdate?.call(GameState.fromJson(gameStateJson));

        // Extraire la carte préchargée pour optimiser l'affichage de la pioche
        final preloadedCardJson =
            gameStateJson['preloadedDeckCard'] as Map<String, dynamic>?;
        if (preloadedCardJson != null) {
          onPreloadedDeckCardUpdate
              ?.call(PlayingCard.fromJson(preloadedCardJson));
        } else {
          onPreloadedDeckCardUpdate?.call(null);
        }
      } catch (_) {}
    }

    if (updateType == 'TIMER_UPDATE') {
      final remaining = data['reactionTimeRemaining'] as int?;
      if (remaining != null) onTimerUpdate?.call(remaining);
    }
  }
}
