import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../models/game_state.dart';
import '../models/game_settings.dart';
import '../models/card.dart';

/// État de la connexion Socket.IO
enum SocketConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Informations sur une room sauvegardée
class SavedRoom {
  final String roomCode;
  final bool isHost;
  final DateTime joinedAt;

  SavedRoom({
    required this.roomCode,
    required this.isHost,
    required this.joinedAt,
  });

  Map<String, dynamic> toJson() => {
        'roomCode': roomCode,
        'isHost': isHost,
        'joinedAt': joinedAt.toIso8601String(),
      };

  factory SavedRoom.fromJson(Map<String, dynamic> json) => SavedRoom(
        roomCode: json['roomCode'] as String,
        isHost: json['isHost'] as bool,
        joinedAt: DateTime.parse(json['joinedAt'] as String),
      );
}

class MultiplayerService {
  static const String _serverUrl = 'https://dutch-game.me';
  static const int _maxReconnectAttempts = 5;
  static const String _myRoomsKey = 'my_multiplayer_rooms';

  io.Socket? _socket;
  String? _currentRoomCode;
  String? _playerId;
  String? _clientId;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _latencyMs = 0;
  int _serverTimeOffsetMs = 0;
  int _reconnectAttempts = 0;
  SocketConnectionState _connectionState = SocketConnectionState.disconnected;
  String? _lastRoomCode; // Pour rejoindre automatiquement après reconnexion
  String? _lastPlayerName; // Nom du joueur pour rejoindre
  final List<Map<String, dynamic>> _pendingActions =
      []; // File d'attente d'actions

  io.Socket? get socket => _socket;
  bool get isConnected => _socket?.connected ?? false;
  String? get currentRoomCode => _currentRoomCode;
  String? get playerId => _playerId;
  String? get clientId => _clientId;
  int get latencyMs => _latencyMs;
  int get serverTimeOffsetMs => _serverTimeOffsetMs;
  int get serverNowMs =>
      DateTime.now().millisecondsSinceEpoch + _serverTimeOffsetMs;
  SocketConnectionState get connectionState => _connectionState;

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
  Function(Map<String, dynamic>)? onPresenceUpdate;
  Function(Map<String, dynamic>)? onPresenceCheck;
  Function(Map<String, dynamic>)? onChatMessage;
  Function(SocketConnectionState)? onSocketConnectionStateChanged;
  Function(Map<String, dynamic>)? onRoomClosed; // Quand l'hôte ferme la room
  Function(Map<String, dynamic>)? onRoomRestarted; // Quand l'hôte relance
  Function(Map<String, dynamic>)? onKicked; // Quand on est kick
  Function(Map<String, dynamic>)? onPlayerLeft; // Quand un joueur quitte
  Function(Map<String, dynamic>)?
      onSpecialPowerTargeted; // Pouvoir spécial sur nous (ancien)
  Function(PlayingCard, String)? onSpiedCard; // Carte espionnée (pouvoir 7/10)
  Function(Map<String, dynamic>)?
      onSwapNotification; // Notification Valet : notre carte a été échangée
  Function(Map<String, dynamic>)?
      onJokerNotification; // Notification Joker : nos cartes ont été mélangées
  Function(Map<String, dynamic>)?
      onSpyNotification; // Notification Espionnage : quelqu'un regarde notre carte
  Function(String)? onGamePaused; // Jeu mis en pause (par qui)
  Function(String)? onGameResumed; // Jeu repris (par qui)

  /// Check if server is reachable via HTTP (without establishing socket connection)
  Future<bool> checkServerHealth() async {
    try {
      final uri = Uri.parse('$_serverUrl/health');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('⚠️ Server health check failed: $e');
      return false;
    }
  }

  // Connexion au serveur
  Future<void> connect() async {
    if (isConnected) return;

    _setSocketConnectionState(SocketConnectionState.connecting);

    _socket = io.io(_serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'reconnection': false, // On gère la reconnexion nous-mêmes
    });

    _setupEventListeners();
    _socket!.connect();

    // Attendre la connexion effective ou une erreur/timeout
    final completer = Completer<void>();

    // Listeners temporaires pour l'initialisation
    final connectHandler = (_) {
      if (!completer.isCompleted) completer.complete();
    };
    final errorHandler = (err) {
      if (!completer.isCompleted) completer.completeError(err);
    };

    _socket!.on('connect', connectHandler);
    _socket!.on('connect_error', errorHandler);
    _socket!.on('connect_timeout', errorHandler);

    try {
      // Timeout raisonnable de 10s pour la connexion réelle (réseau lent)
      // Mais retournera immédiatement dès que 'connect' est émis
      await completer.future.timeout(const Duration(seconds: 10));

      _playerId = _socket!.id;
      _reconnectAttempts = 0;
      _setSocketConnectionState(SocketConnectionState.connected);
      debugPrint('✅ Connecté au serveur - ID: $_playerId');
    } catch (e) {
      _setSocketConnectionState(SocketConnectionState.disconnected);
      // Nettoyage si échec
      _socket?.disconnect();
      throw Exception('Impossible de se connecter au serveur : $e');
    } finally {
      // Nettoyer les listeners temporaires
      _socket!.off('connect', connectHandler);
      _socket!.off('connect_error', errorHandler);
      _socket!.off('connect_timeout', errorHandler);
    }
  }

  void _setSocketConnectionState(SocketConnectionState state) {
    if (_connectionState != state) {
      _connectionState = state;
      onSocketConnectionStateChanged?.call(state);
    }
  }

  /// Reconnexion automatique avec backoff exponentiel
  Future<void> _attemptReconnect() async {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('❌ Nombre maximum de tentatives de reconnexion atteint');
      _setSocketConnectionState(SocketConnectionState.disconnected);
      onError?.call('Connexion perdue. Veuillez réessayer.');
      return;
    }

    _setSocketConnectionState(SocketConnectionState.reconnecting);

    // Backoff exponentiel: 1s, 2s, 4s, 8s, 16s
    final delay = Duration(seconds: pow(2, _reconnectAttempts).toInt());
    _reconnectAttempts++;

    debugPrint(
        '🔄 Tentative de reconnexion $_reconnectAttempts/$_maxReconnectAttempts dans ${delay.inSeconds}s...');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      try {
        // Réinitialiser le socket
        _socket?.disconnect();
        _socket?.dispose();
        _socket = null;

        await connect();

        // Si on était dans une room, essayer de la rejoindre
        if (isConnected && _lastRoomCode != null && _lastPlayerName != null) {
          debugPrint('🔄 Tentative de rejoindre la room $_lastRoomCode...');
          try {
            await joinRoom(
              roomCode: _lastRoomCode!,
              playerName: _lastPlayerName!,
            );
            debugPrint('✅ Room rejointe après reconnexion');

            // Exécuter les actions en attente
            _flushPendingActions();
          } catch (e) {
            debugPrint('⚠️ Impossible de rejoindre la room: $e');
          }
        }
      } catch (e) {
        debugPrint('❌ Échec de la reconnexion: $e');
        // Réessayer
        _attemptReconnect();
      }
    });
  }

  /// Exécute les actions en attente après reconnexion
  void _flushPendingActions() {
    if (_pendingActions.isEmpty) return;

    debugPrint('📤 Envoi de ${_pendingActions.length} action(s) en attente...');

    for (final action in _pendingActions) {
      final event = action['event'] as String;
      final data = action['data'] as Map<String, dynamic>;
      _socket?.emit(event, data);
    }

    _pendingActions.clear();
  }

  /// Ajoute une action à la file d'attente si déconnecté
  // Previously used to queue actions when disconnected. Kept for reference.
  // If you need to queue actions, use `_pendingActions.add(...)` and call `_flushPendingActions()` after reconnect.

  // Configuration des listeners d'événements
  void _setupEventListeners() {
    _socket!.on('connect', (_) {
      debugPrint('📡 Connecté au serveur Socket.IO');
      _playerId = _socket!.id;
      _startPingLoop();
    });

    _socket!.on('disconnect', (reason) {
      debugPrint('❌ Déconnecté du serveur: $reason');
      _stopPingLoop();
      _latencyMs = 0;
      _serverTimeOffsetMs = 0;

      // Tenter une reconnexion automatique si on était connecté
      if (_connectionState == SocketConnectionState.connected) {
        _attemptReconnect();
      }
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
      } else if (updateType == 'GAME_PAUSED') {
        final pausedBy = data['pausedBy'] as String? ?? 'Inconnu';
        onGamePaused?.call(pausedBy);
      } else if (updateType == 'GAME_RESUMED') {
        final resumedBy = data['resumedBy'] as String? ?? 'Inconnu';
        onGameResumed?.call(resumedBy);
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
      if (data is Map) {
        onPresenceUpdate?.call(data.cast<String, dynamic>());
      }
    });

    _socket!.on('presence:check', (data) {
      if (data is Map) {
        onPresenceCheck?.call(data.cast<String, dynamic>());
      }
    });

    _socket!.on('chat:message', (data) {
      if (data is Map) {
        onChatMessage?.call(data.cast<String, dynamic>());
      }
    });

    // Quand l'hôte ferme la room
    _socket!.on('room:closed', (data) {
      debugPrint('🚪 Room fermée par l\'hôte');
      if (data is Map) {
        onRoomClosed?.call(data.cast<String, dynamic>());
      }
    });

    // Quand l'hôte relance la partie
    _socket!.on('room:restarted', (data) {
      debugPrint('🔄 Partie relancée');
      if (data is Map) {
        onRoomRestarted?.call(data.cast<String, dynamic>());
      }
    });

    // Quand on est kick
    _socket!.on('room:kicked', (data) {
      debugPrint('👢 Vous avez été exclu');
      _currentRoomCode = null;
      _lastRoomCode = null;
      if (data is Map) {
        onKicked?.call(data.cast<String, dynamic>());
      }
    });

    // Quand un joueur quitte la partie
    _socket!.on('player:left', (data) {
      debugPrint('👋 Un joueur a quitté: ${data['playerName']}');
      if (data is Map) {
        onPlayerLeft?.call(data.cast<String, dynamic>());
      }
    });

    // Quand un pouvoir spécial est utilisé sur nous (ancien événement générique)
    _socket!.on('special_power:targeted', (data) {
      debugPrint(
          '✨ Pouvoir spécial utilisé sur vous par ${data['byPlayerName']}');
      if (data is Map) {
        onSpecialPowerTargeted?.call(data.cast<String, dynamic>());
      }
    });

    // Notification Valet : notre carte a été échangée
    _socket!.on('special_power:swap_notification', (data) {
      debugPrint(
          '🔄 Valet ! ${data['byPlayerName']} a échangé votre carte #${(data['cardIndex'] ?? 0) + 1}');
      if (data is Map) {
        onSwapNotification?.call(data.cast<String, dynamic>());
      }
    });

    // Notification Joker : nos cartes ont été mélangées
    _socket!.on('special_power:joker_notification', (data) {
      debugPrint('🃏 Joker ! ${data['byPlayerName']} a mélangé vos cartes');
      if (data is Map) {
        onJokerNotification?.call(data.cast<String, dynamic>());
      }
    });

    // Notification Espionnage : quelqu'un regarde notre carte (pouvoir 10)
    _socket!.on('special_power:spy_notification', (data) {
      debugPrint(
          '👁️ Espionnage ! ${data['byPlayerName']} regarde votre carte #${(data['cardIndex'] ?? 0) + 1}');
      if (data is Map) {
        onSpyNotification?.call(data.cast<String, dynamic>());
      }
    });

    // Demande de synchronisation complète de l'état
    _socket!.on('game:full_state', (data) {
      debugPrint('🔄 Synchronisation complète de l\'état');
      if (data is Map) {
        final gameStateJson = data['gameState'] as Map<String, dynamic>?;
        if (gameStateJson != null) {
          try {
            final gameState = GameState.fromJson(gameStateJson);
            onGameStateUpdate?.call(gameState);
          } catch (e) {
            debugPrint('❌ Erreur parsing GameState (full_state): $e');
          }
        }
      }
    });

    // Carte espionnée (pouvoir 7)
    _socket!.on('game:spied_card', (data) {
      debugPrint('👁️ Carte espionnée reçue');
      if (data is Map) {
        try {
          final cardJson = data['card'] as Map<String, dynamic>?;
          final targetName = data['targetPlayerName'] as String? ?? 'Inconnu';
          if (cardJson != null) {
            final card = PlayingCard.fromJson(cardJson);
            onSpiedCard?.call(card, targetName);
          }
        } catch (e) {
          debugPrint('❌ Erreur parsing spied card: $e');
        }
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
    socket.emitWithAck('client:ping', {'clientTime': clientTime},
        ack: (response) {
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

    // Sauvegarder pour la reconnexion
    _lastPlayerName = playerName;

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
        _lastRoomCode = response['roomCode'];
        debugPrint('✅ Room créée: ${response['roomCode']}');

        // Sauvegarder la room (hôte)
        _saveMyRoom(response['roomCode'] as String, isHost: true);

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

    // Sauvegarder pour la reconnexion
    _lastPlayerName = playerName;

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
        _lastRoomCode = roomCode.toUpperCase();
        debugPrint('✅ Room rejointe: $_currentRoomCode');

        // Sauvegarder la room (non-hôte)
        _saveMyRoom(roomCode.toUpperCase(), isHost: false);

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
  Future<bool> startGame({bool fillBots = false}) async {
    if (_currentRoomCode == null) {
      debugPrint('❌ Pas de room active');
      return false;
    }

    final completer = Completer<bool>();

    debugPrint('🎮 Démarrage de la partie...');

    _socket!.emitWithAck('room:start_game', {
      'roomCode': _currentRoomCode,
      'fillBots': fillBots,
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

  /// Carte 7 : Regarder sa propre carte
  void usePower7LookOwnCard(int cardIndex) {
    debugPrint('👁️ Pouvoir 7 : Regarde sa carte #${cardIndex + 1}');
    _socket!.emit('game:use_special_power', {
      'roomCode': _currentRoomCode,
      'cardIndex': cardIndex,
    });
  }

  /// Carte 10 : Espionner une carte adversaire
  void usePower10SpyOpponent(int targetPlayerIndex, int targetCardIndex) {
    debugPrint(
        '🔍 Pouvoir 10 : Espionne joueur $targetPlayerIndex carte #${targetCardIndex + 1}');
    _socket!.emit('game:use_special_power', {
      'roomCode': _currentRoomCode,
      'targetPlayerIndex': targetPlayerIndex,
      'targetCardIndex': targetCardIndex,
    });
  }

  /// Carte V (Valet) : Échange universel entre 2 joueurs
  void usePowerValetSwap(
      int player1Index, int card1Index, int player2Index, int card2Index) {
    debugPrint(
        '🔄 Pouvoir Valet : Échange joueur $player1Index carte #${card1Index + 1} ↔ joueur $player2Index carte #${card2Index + 1}');
    _socket!.emit('game:use_special_power', {
      'roomCode': _currentRoomCode,
      'player1Index': player1Index,
      'card1Index': card1Index,
      'player2Index': player2Index,
      'card2Index': card2Index,
    });
  }

  /// JOKER : Mélanger la main d'un joueur (y compris soi-même)
  void usePowerJokerShuffle(int targetPlayerIndex) {
    debugPrint('🃏 Pouvoir Joker : Mélange joueur $targetPlayerIndex');
    _socket!.emit('game:use_special_power', {
      'roomCode': _currentRoomCode,
      'targetPlayerIndex': targetPlayerIndex,
    });
  }

  /// Méthode générique pour compatibilité (utilisée par l'ancien code)
  @Deprecated('Utiliser les méthodes spécifiques usePower7/10/Valet/Joker')
  void useSpecialPower(int targetPlayerIndex, int targetCardIndex) {
    debugPrint('✨ Utilise pouvoir spécial (ancienne méthode)');
    _socket!.emit('game:use_special_power', {
      'roomCode': _currentRoomCode,
      'targetPlayerIndex': targetPlayerIndex,
      'targetCardIndex': targetCardIndex,
    });
  }

  void skipSpecialPower() {
    debugPrint('⏭️ Ignore le pouvoir spécial');
    _socket!.emit('game:skip_special_power', {'roomCode': _currentRoomCode});
  }

  void setReady(bool ready) {
    if (_currentRoomCode == null) return;
    _socket?.emitWithAck(
      'room:ready',
      {'roomCode': _currentRoomCode, 'ready': ready},
      ack: (_) {},
    );
  }

  void sendChatMessage(String message) {
    if (_currentRoomCode == null) return;
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    _socket?.emitWithAck(
      'chat:send',
      {'roomCode': _currentRoomCode, 'message': trimmed},
      ack: (_) {},
    );
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

  // Quitter la room (sans la fermer)
  void leaveRoom() {
    if (_currentRoomCode != null) {
      debugPrint('🚪 Quitte la room $_currentRoomCode');
      _socket?.emit('room:leave', {'roomCode': _currentRoomCode});
      _lastRoomCode = null;
      _currentRoomCode = null;
    }
  }

  /// Fermer la room (hôte uniquement) - la room reste disponible pour transfert
  Future<bool> closeRoom() async {
    if (_currentRoomCode == null) return false;

    final completer = Completer<bool>();

    debugPrint('🔒 Fermeture de la room $_currentRoomCode...');

    _socket?.emitWithAck('room:close', {
      'roomCode': _currentRoomCode,
    }, ack: (response) {
      if (response == null) {
        completer.complete(false);
        return;
      }

      final success = response['success'] == true;
      if (success) {
        debugPrint('✅ Room fermée');
        _removeMyRoom(_currentRoomCode!);
        _lastRoomCode = null;
        _currentRoomCode = null;
      } else {
        debugPrint('❌ Erreur fermeture: ${response['reason']}');
      }
      completer.complete(success);
    });

    return completer.future;
  }

  /// Demander à devenir hôte d'une room fermée
  Future<bool> becomeHost(String roomCode) async {
    final completer = Completer<bool>();

    debugPrint('👑 Demande de devenir hôte de $roomCode...');

    _socket?.emitWithAck('room:transfer_host', {
      'roomCode': roomCode,
    }, ack: (response) {
      if (response == null) {
        completer.complete(false);
        return;
      }

      final success = response['success'] == true;
      if (success) {
        debugPrint('✅ Vous êtes maintenant l\'hôte');
        _currentRoomCode = roomCode;
        _lastRoomCode = roomCode;
        _saveMyRoom(roomCode, isHost: true);
      } else {
        debugPrint('❌ Échec du transfert');
      }
      completer.complete(success);
    });

    return completer.future;
  }

  /// Relancer une partie (rematch) - hôte uniquement
  Future<bool> restartGame() async {
    if (_currentRoomCode == null) return false;

    final completer = Completer<bool>();

    debugPrint('🔄 Relance de la partie...');

    _socket?.emitWithAck('room:restart', {
      'roomCode': _currentRoomCode,
    }, ack: (response) {
      final success = response?['success'] == true;
      if (success) {
        debugPrint('✅ Partie relancée');
      } else {
        debugPrint('❌ Échec du rematch');
      }
      completer.complete(success);
    });

    return completer.future;
  }

  /// Kick un joueur (hôte uniquement)
  Future<bool> kickPlayer(String clientId) async {
    if (_currentRoomCode == null) return false;

    final completer = Completer<bool>();

    debugPrint('👢 Kick du joueur $clientId...');

    _socket?.emitWithAck('room:kick', {
      'roomCode': _currentRoomCode,
      'clientId': clientId,
    }, ack: (response) {
      final success = response?['success'] == true;
      if (success) {
        debugPrint('✅ Joueur exclu');
      } else {
        debugPrint('❌ Échec du kick');
      }
      completer.complete(success);
    });

    return completer.future;
  }

  /// Changer le mode de jeu (hôte uniquement, en lobby)
  Future<bool> setGameMode(int gameMode) async {
    if (_currentRoomCode == null) return false;

    final completer = Completer<bool>();

    _socket?.emitWithAck('room:set_game_mode', {
      'roomCode': _currentRoomCode,
      'gameMode': gameMode,
    }, ack: (response) {
      final success = response?['success'] == true;
      completer.complete(success);
    });

    return completer.future;
  }

  /// Demander une synchronisation complète de l'état du jeu
  void requestFullState() {
    if (_currentRoomCode == null) return;
    debugPrint('🔄 Demande de synchronisation...');
    _socket?.emit('game:request_state', {'roomCode': _currentRoomCode});
  }

  // ============ Gestion des rooms sauvegardées ============

  /// Sauvegarder une room dans les préférences
  Future<void> _saveMyRoom(String roomCode, {required bool isHost}) async {
    final prefs = await SharedPreferences.getInstance();
    final roomsJson = prefs.getStringList(_myRoomsKey) ?? [];

    // Supprimer si déjà existant
    roomsJson.removeWhere((json) {
      try {
        final data = Map<String, dynamic>.from(
            (json as dynamic) is String ? _parseJson(json) : {});
        return data['roomCode'] == roomCode;
      } catch (_) {
        return false;
      }
    });

    // Ajouter la nouvelle entrée
    final room = SavedRoom(
      roomCode: roomCode,
      isHost: isHost,
      joinedAt: DateTime.now(),
    );
    roomsJson.add(_encodeJson(room.toJson()));

    // Limiter à 10 rooms max
    while (roomsJson.length > 10) {
      roomsJson.removeAt(0);
    }

    await prefs.setStringList(_myRoomsKey, roomsJson);
  }

  /// Supprimer une room des préférences
  Future<void> _removeMyRoom(String roomCode) async {
    final prefs = await SharedPreferences.getInstance();
    final roomsJson = prefs.getStringList(_myRoomsKey) ?? [];

    roomsJson.removeWhere((json) {
      try {
        final data = _parseJson(json);
        return data['roomCode'] == roomCode;
      } catch (_) {
        return false;
      }
    });

    await prefs.setStringList(_myRoomsKey, roomsJson);
  }

  /// Récupérer la liste des rooms sauvegardées
  Future<List<SavedRoom>> getMyRooms() async {
    final prefs = await SharedPreferences.getInstance();
    final roomsJson = prefs.getStringList(_myRoomsKey) ?? [];

    final rooms = <SavedRoom>[];
    for (final json in roomsJson) {
      try {
        final data = _parseJson(json);
        rooms.add(SavedRoom.fromJson(data));
      } catch (_) {
        // Ignorer les entrées invalides
      }
    }

    return rooms;
  }

  /// Vérifier quelles rooms sont encore actives sur le serveur
  Future<List<Map<String, dynamic>>> checkActiveRooms(
      List<String> roomCodes) async {
    if (!isConnected || roomCodes.isEmpty) return [];

    final completer = Completer<List<Map<String, dynamic>>>();

    _socket?.emitWithAck('room:check_active', {
      'roomCodes': roomCodes,
    }, ack: (response) {
      if (response == null || response['rooms'] == null) {
        completer.complete([]);
        return;
      }

      final rooms = (response['rooms'] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      completer.complete(rooms);
    });

    return completer.future;
  }

  /// Nettoyer les rooms inactives des préférences
  Future<void> cleanupInactiveRooms() async {
    final myRooms = await getMyRooms();
    if (myRooms.isEmpty) return;

    final roomCodes = myRooms.map((r) => r.roomCode).toList();
    final activeRooms = await checkActiveRooms(roomCodes);
    final activeCodes = activeRooms.map((r) => r['roomCode'] as String).toSet();

    // Supprimer les rooms inactives
    for (final room in myRooms) {
      if (!activeCodes.contains(room.roomCode)) {
        await _removeMyRoom(room.roomCode);
      }
    }
  }

  // Helpers JSON (simple encoding sans import dart:convert)
  Map<String, dynamic> _parseJson(String json) {
    // Simple JSON parser pour notre format
    final map = <String, dynamic>{};
    final content = json.trim();
    if (!content.startsWith('{') || !content.endsWith('}')) return map;

    final inner = content.substring(1, content.length - 1);
    final parts = inner.split(',');

    for (final part in parts) {
      final kv = part.split(':');
      if (kv.length >= 2) {
        final key = kv[0].trim().replaceAll('"', '');
        var value = kv.sublist(1).join(':').trim();

        if (value.startsWith('"') && value.endsWith('"')) {
          map[key] = value.substring(1, value.length - 1);
        } else if (value == 'true') {
          map[key] = true;
        } else if (value == 'false') {
          map[key] = false;
        } else {
          map[key] = value;
        }
      }
    }
    return map;
  }

  String _encodeJson(Map<String, dynamic> map) {
    final pairs = map.entries.map((e) {
      final value = e.value;
      if (value is String) {
        return '"${e.key}":"$value"';
      } else if (value is bool) {
        return '"${e.key}":$value';
      } else {
        return '"${e.key}":"$value"';
      }
    });
    return '{${pairs.join(',')}}';
  }

  // Déconnexion
  void disconnect() {
    debugPrint('👋 Déconnexion du serveur');
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    leaveRoom();
    _stopPingLoop();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _playerId = null;
    _setSocketConnectionState(SocketConnectionState.disconnected);
  }
}
