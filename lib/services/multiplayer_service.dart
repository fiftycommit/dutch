import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../models/game_state.dart';
import '../models/game_settings.dart';

class MultiplayerService {
  static const String _serverUrl = 'https://dutch-game.me';

  io.Socket? _socket;
  String? _currentRoomCode;
  String? _playerId;
  String? _clientId;
  Timer? _pingTimer;
  int _latencyMs = 0;
  int _serverTimeOffsetMs = 0;

  bool get isConnected => _socket?.connected ?? false;
  String? get currentRoomCode => _currentRoomCode;
  String? get playerId => _playerId;
  String? get clientId => _clientId;
  int get latencyMs => _latencyMs;
  int get serverTimeOffsetMs => _serverTimeOffsetMs;
  int get serverNowMs =>
      DateTime.now().millisecondsSinceEpoch + _serverTimeOffsetMs;

  Future<String> _ensureClientId() async {
    if (_clientId != null) return _clientId!;
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('multiplayer_client_id');
    if (existing != null && existing.isNotEmpty) {
      _clientId = existing;
      return existing;
    }
    final random = Random();
    final newId =
        '${DateTime.now().millisecondsSinceEpoch}-${random.nextInt(1 << 30)}';
    await prefs.setString('multiplayer_client_id', newId);
    _clientId = newId;
    return newId;
  }

  // Callbacks pour les événements
  Function(GameState)? onGameStateUpdate;
  Function(String)? onError;
  Function(Map<String, dynamic>)? onPlayerJoined;
  Function(int)? onTimerUpdate;
  Function(String)? onGameStarted;
  Function(int)? onReactionTimeConfig;
  Function(List<dynamic>)? onPresenceUpdate;
  Function(Map<String, dynamic>)? onPresenceCheck;

  // Connexion au serveur
  Future<void> connect() async {
    if (isConnected) return;

    _socket = io.io(_serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    _setupEventListeners();
    _socket!.connect();

    // Attendre la connexion
    await Future.delayed(const Duration(seconds: 2));

    if (!isConnected) {
      throw Exception('Impossible de se connecter au serveur');
    }

    _playerId = _socket!.id;
    debugPrint('✅ Connecté au serveur - ID: $_playerId');
  }

  // Configuration des listeners d'événements
  void _setupEventListeners() {
    _socket!.on('connect', (_) {
      debugPrint('📡 Connecté au serveur Socket.IO');
      _playerId = _socket!.id;
      _startPingLoop();
    });

    _socket!.on('disconnect', (_) {
      debugPrint('❌ Déconnecté du serveur');
      _stopPingLoop();
      _latencyMs = 0;
      _serverTimeOffsetMs = 0;
    });

    _socket!.on('connect_error', (error) {
      debugPrint('⚠️ Erreur de connexion: $error');
      onError?.call('Erreur de connexion: $error');
    });

    // Événements de jeu
    _socket!.on('game:state_update', (data) {
      debugPrint('🎮 Mise à jour de l\'état du jeu: ${data['type']}');

      final updateType = data['type'] as String?;
      final gameStateJson = data['gameState'] as Map<String, dynamic>?;

      if (updateType == 'GAME_STARTED') {
        final message = data['message'] as String?;
        if (message != null) {
          onGameStarted?.call(message);
        }
      }

      final reactionTimeMs = data['reactionTimeMs'];
      if (reactionTimeMs is int) {
        onReactionTimeConfig?.call(reactionTimeMs);
      }

      if (gameStateJson != null) {
        try {
          final gameState = GameState.fromJson(gameStateJson);
          onGameStateUpdate?.call(gameState);
        } catch (e) {
          debugPrint('❌ Erreur parsing GameState: $e');
          onError?.call('Erreur lors de la mise à jour du jeu');
        }
      }

      if (updateType == 'TIMER_UPDATE') {
        final remaining = data['reactionTimeRemaining'] as int?;
        if (remaining != null) {
          onTimerUpdate?.call(remaining);
        }
      }
    });

    _socket!.on('room:player_joined', (data) {
      debugPrint('👥 Nouveau joueur dans la room');
      onPlayerJoined?.call(data);
    });

    _socket!.on('error', (error) {
      debugPrint('❌ Erreur: $error');
      onError?.call(error.toString());
    });

    _socket!.on('presence:update', (data) {
      if (data is Map && data['players'] is List) {
        onPresenceUpdate?.call(data['players'] as List);
      }
    });

    _socket!.on('presence:check', (data) {
      if (data is Map) {
        onPresenceCheck?.call(data.cast<String, dynamic>());
      }
    });
  }

  void _startPingLoop() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _sendPing());
    _sendPing();
  }

  void _stopPingLoop() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _sendPing() {
    final socket = _socket;
    if (socket == null || !socket.connected) return;

    final clientTime = DateTime.now().millisecondsSinceEpoch;
    socket.emitWithAck('client:ping', {'clientTime': clientTime}, ack: (response) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final rtt = (now - clientTime).clamp(0, 10000);
      _latencyMs = rtt;

      final serverTime = response is Map ? response['serverTime'] : null;
      if (serverTime is int) {
        _serverTimeOffsetMs = serverTime - (clientTime + (rtt ~/ 2));
      }
    });
  }

  // Créer une room
  Future<String?> createRoom({
    required GameSettings settings,
    required String playerName,
  }) async {
    if (!isConnected) await connect();

    final completer = Completer<String?>();
    final clientId = await _ensureClientId();

    debugPrint('🎲 Création d\'une room...');

    _socket!.emitWithAck('room:create', {
      'settings': settings.toJson(),
      'playerName': playerName,
      'clientId': clientId,
    }, ack: (response) {
      if (response == null) {
        debugPrint('❌ Pas de réponse du serveur');
        completer.completeError('Pas de réponse du serveur');
        return;
      }

      if (response['success'] == true) {
        _currentRoomCode = response['roomCode'];
        debugPrint('✅ Room créée: ${response['roomCode']}');
        completer.complete(response['roomCode']);
      } else {
        final error = response['error'] ?? 'Erreur inconnue';
        debugPrint('❌ Erreur création room: $error');
        completer.completeError(error);
      }
    });

    return completer.future;
  }

  // Rejoindre une room
  Future<Map<String, dynamic>?> joinRoom({
    required String roomCode,
    required String playerName,
  }) async {
    if (!isConnected) await connect();

    final completer = Completer<Map<String, dynamic>?>();
    final clientId = await _ensureClientId();

    debugPrint('🚪 Rejoindre room $roomCode...');

    _socket!.emitWithAck('room:join', {
      'roomCode': roomCode.toUpperCase(),
      'playerName': playerName,
      'clientId': clientId,
    }, ack: (response) {
      if (response == null) {
        debugPrint('❌ Pas de réponse du serveur');
        completer.completeError('Pas de réponse du serveur');
        return;
      }

      if (response['success'] == true) {
        _currentRoomCode = roomCode.toUpperCase();
        debugPrint('✅ Room rejointe: $_currentRoomCode');
        final room = response['room'] as Map<String, dynamic>?;
        completer.complete(room);
      } else {
        final error = response['error'] ?? 'Erreur inconnue';
        debugPrint('❌ Erreur rejoindre room: $error');
        completer.completeError(error);
      }
    });

    return completer.future;
  }

  // Démarrer la partie (hôte uniquement)
  Future<bool> startGame() async {
    if (_currentRoomCode == null) {
      debugPrint('❌ Pas de room active');
      return false;
    }

    final completer = Completer<bool>();

    debugPrint('🎮 Démarrage de la partie...');

    _socket!.emitWithAck('room:start_game', {
      'roomCode': _currentRoomCode,
    }, ack: (response) {
      if (response == null) {
        debugPrint('❌ Pas de réponse du serveur');
        completer.complete(false);
        return;
      }

      final success = response['success'] == true;
      if (success) {
        debugPrint('✅ Partie démarrée');
      } else {
        debugPrint('❌ Erreur démarrage: ${response['error']}');
      }
      completer.complete(success);
    });

    return completer.future;
  }

  // Actions de jeu (à implémenter côté serveur)
  void drawCard() {
    debugPrint('🃏 Pioche une carte');
    _socket!.emit('game:draw_card', {'roomCode': _currentRoomCode});
  }

  void replaceCard(int cardIndex) {
    debugPrint('🔄 Remplace carte $cardIndex');
    _socket!.emit('game:replace_card', {
      'roomCode': _currentRoomCode,
      'cardIndex': cardIndex,
    });
  }

  void discardDrawnCard() {
    debugPrint('🗑️ Rejette la carte piochée');
    _socket!.emit('game:discard_card', {'roomCode': _currentRoomCode});
  }

  void takeFromDiscard() {
    debugPrint('♻️ Prend de la défausse');
    _socket!.emit('game:take_from_discard', {'roomCode': _currentRoomCode});
  }

  void callDutch() {
    debugPrint('📢 DUTCH !');
    _socket!.emit('game:call_dutch', {'roomCode': _currentRoomCode});
  }

  void attemptMatch(int cardIndex) {
    debugPrint('🎯 Tente de matcher carte $cardIndex');
    _socket!.emit('game:attempt_match', {
      'roomCode': _currentRoomCode,
      'cardIndex': cardIndex,
    });
  }

  void useSpecialPower(int targetPlayerIndex, int targetCardIndex) {
    debugPrint('✨ Utilise pouvoir spécial');
    _socket!.emit('game:use_special_power', {
      'roomCode': _currentRoomCode,
      'targetPlayerIndex': targetPlayerIndex,
      'targetCardIndex': targetCardIndex,
    });
  }

  void completeSwap(int ownCardIndex) {
    debugPrint('🔁 Complete l\'échange');
    _socket!.emit('game:complete_swap', {
      'roomCode': _currentRoomCode,
      'ownCardIndex': ownCardIndex,
    });
  }

  void skipSpecialPower() {
    debugPrint('⏭️ Ignore le pouvoir spécial');
    _socket!.emit('game:skip_special_power', {'roomCode': _currentRoomCode});
  }

  void setFocused(bool focused) {
    if (_currentRoomCode == null) return;
    _socket?.emit('presence:focus', {
      'roomCode': _currentRoomCode,
      'focused': focused,
    });
  }

  void confirmPresence() {
    if (_currentRoomCode == null) return;
    _socket?.emit('presence:ack', {'roomCode': _currentRoomCode});
  }

  // Quitter la room
  void leaveRoom() {
    if (_currentRoomCode != null) {
      debugPrint('🚪 Quitte la room $_currentRoomCode');
      _socket!.emit('room:leave', {'roomCode': _currentRoomCode});
      _currentRoomCode = null;
    }
  }

  // Déconnexion
  void disconnect() {
    debugPrint('👋 Déconnexion du serveur');
    leaveRoom();
    _stopPingLoop();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _playerId = null;
  }
}
