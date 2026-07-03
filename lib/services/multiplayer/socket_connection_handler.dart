import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'client_id_service.dart';

/// État de la connexion Socket.IO
enum SocketConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Gère la connexion Socket.IO, reconnexion et ping
/// Principe GRASP: Information Expert - Gère tout ce qui concerne la connexion
class SocketConnectionHandler {
  // Prod par défaut ; surchargeable en dev/test local (émulateurs) via
  // --dart-define=DEV_SERVER_URL=http://localhost:3000. La prod ne définit pas
  // cette variable et garde donc l'URL de production.
  static const String serverUrl = String.fromEnvironment(
    'DEV_SERVER_URL',
    defaultValue: 'https://dutch-game.me',
  );
  static const int _maxReconnectAttempts = 5;

  io.Socket? _socket;
  String? _playerId;
  String? _clientId;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _latencyMs = 0;
  int _serverTimeOffsetMs = 0;
  int _reconnectAttempts = 0;
  bool _isReconnecting = false;
  SocketConnectionState _connectionState = SocketConnectionState.disconnected;

  // Pour la reconnexion automatique
  String? lastRoomCode;
  String? lastPlayerName;
  final List<Map<String, dynamic>> pendingActions = [];

  // Callbacks
  Function(SocketConnectionState)? onConnectionStateChanged;
  Function(String)? onError;
  Future<void> Function(String roomCode, String playerName)? onReconnectToRoom;

  io.Socket? get socket => _socket;
  bool get isConnected => _socket?.connected ?? false;
  String? get playerId => _playerId;
  String? get clientId => _clientId;
  int get latencyMs => _latencyMs;
  int get serverTimeOffsetMs => _serverTimeOffsetMs;
  int get serverNowMs =>
      DateTime.now().millisecondsSinceEpoch + _serverTimeOffsetMs;
  SocketConnectionState get connectionState => _connectionState;

  Future<String> ensureClientId() async {
    if (_clientId != null) return _clientId!;
    final ensured = await ClientIdService.ensureClientId();
    _clientId = ensured;
    return ensured;
  }

  String? _authToken;
  String? _authUid;

  /// Firebase UID extrait du JWT courant (null si non authentifié).
  String? get authUid => _authUid;

  String? _extractUidFromJwt(String? token) {
    if (token == null || token.isEmpty) return null;
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map<String, dynamic>) return null;
      return (payload['user_id'] ?? payload['sub'])?.toString();
    } catch (_) {
      return null;
    }
  }

  void setAuthToken(String? token) {
    final newUid = _extractUidFromJwt(token);
    final identityChanged = (_authUid ?? '') != (newUid ?? '');
    _authToken = token;
    _authUid = newUid;
    if (identityChanged && isConnected) {
      disconnect();
    }
  }

  Future<void> connect(void Function(io.Socket) setupListeners) async {
    // Guard: ne jamais créer 2 connexions en parallèle
    if (_connectionState == SocketConnectionState.connected ||
        _connectionState == SocketConnectionState.connecting) {
      return;
    }

    _setConnectionState(SocketConnectionState.connecting);

    // Nettoyer tout ancien socket résiduel
    _socket?.clearListeners();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;

    final options = <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'reconnection': false,
      'forceNew': true,
    };

    if (_authToken != null) {
      final authPayload = <String, dynamic>{'token': _authToken};
      try {
        final appCheckToken = await FirebaseAppCheck.instance.getToken();
        if (appCheckToken != null && appCheckToken.isNotEmpty) {
          authPayload['appCheckToken'] = appCheckToken;
        }
      } catch (_) {
        // On laisse la connexion tenter sa chance; le serveur tranchera.
      }
      options['auth'] = authPayload;
    }

    _socket = io.io(serverUrl, options);

    setupListeners(_socket!);
    _socket!.connect();

    final completer = Completer<void>();

    void connectHandler(_) {
      if (!completer.isCompleted) completer.complete();
    }

    void errorHandler(err) {
      if (!completer.isCompleted) completer.completeError(err);
    }

    _socket!.on('connect', connectHandler);
    _socket!.on('connect_error', errorHandler);
    _socket!.on('connect_timeout', errorHandler);

    try {
      await completer.future.timeout(const Duration(seconds: 10));

      _playerId = _socket!.id;
      _reconnectAttempts = 0;
      _setConnectionState(SocketConnectionState.connected);
      _startPingLoop();
      if (kDebugMode) debugPrint('✅ Connecté au serveur - ID: $_playerId');
    } catch (e) {
      _socket?.clearListeners();
      _socket?.disconnect();
      _socket?.dispose();
      _socket = null;
      _setConnectionState(SocketConnectionState.disconnected);
      throw Exception('Impossible de se connecter au serveur : $e');
    } finally {
      // Les handlers temporaires sont nettoyés même en cas de succès
      _socket?.off('connect', connectHandler);
      _socket?.off('connect_error', errorHandler);
      _socket?.off('connect_timeout', errorHandler);
    }
  }

  void _setConnectionState(SocketConnectionState state) {
    if (_connectionState != state) {
      _connectionState = state;
      onConnectionStateChanged?.call(state);
    }
  }

  void handleDisconnect(
      String reason, void Function(io.Socket) setupListeners) {
    if (kDebugMode) debugPrint('❌ Déconnecté du serveur: $reason');
    _stopPingLoop();
    _latencyMs = 0;
    _serverTimeOffsetMs = 0;

    if (_connectionState == SocketConnectionState.connected) {
      _attemptReconnect(setupListeners);
    }
  }

  Future<void> _attemptReconnect(
      void Function(io.Socket) setupListeners) async {
    if (_isReconnecting) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      if (kDebugMode) {
        debugPrint('❌ Nombre maximum de tentatives de reconnexion atteint');
      }
      _setConnectionState(SocketConnectionState.disconnected);
      onError?.call('Connexion perdue. Veuillez réessayer.');
      return;
    }

    _isReconnecting = true;
    _setConnectionState(SocketConnectionState.reconnecting);

    final delay = Duration(seconds: pow(2, _reconnectAttempts).toInt());
    _reconnectAttempts++;

    debugPrint(
        '🔄 Tentative de reconnexion $_reconnectAttempts/$_maxReconnectAttempts dans ${delay.inSeconds}s...');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      try {
        _socket?.clearListeners();
        _socket?.disconnect();
        _socket?.dispose();
        _socket = null;
        // Reset state pour que connect() passe le guard
        _connectionState = SocketConnectionState.disconnected;

        await connect(setupListeners);

        _isReconnecting = false;

        if (isConnected && lastRoomCode != null && lastPlayerName != null) {
          if (kDebugMode) {
            debugPrint('🔄 Tentative de rejoindre la room $lastRoomCode...');
          }
          try {
            await onReconnectToRoom?.call(lastRoomCode!, lastPlayerName!);
            if (kDebugMode) debugPrint('✅ Room rejointe après reconnexion');
            flushPendingActions();
          } catch (e) {
            if (kDebugMode) {
              debugPrint('⚠️ Impossible de rejoindre la room: $e');
            }
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('❌ Échec de la reconnexion: $e');
        _isReconnecting = false;
        _attemptReconnect(setupListeners);
      }
    });
  }

  void flushPendingActions() {
    if (pendingActions.isEmpty) return;

    if (kDebugMode) {
      debugPrint(
          '📤 Envoi de ${pendingActions.length} action(s) en attente...');
    }

    for (final action in pendingActions) {
      final event = action['event'] as String;
      final data = action['data'] as Map<String, dynamic>;
      _socket?.emit(event, data);
    }

    pendingActions.clear();
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
    if (_socket == null || !_socket!.connected) return;

    final clientTime = DateTime.now().millisecondsSinceEpoch;
    _socket!.emitWithAck('client:ping', {'clientTime': clientTime},
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

  void disconnect() {
    if (kDebugMode) debugPrint('👋 Déconnexion du serveur');
    _setConnectionState(SocketConnectionState.disconnected);
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _isReconnecting = false;
    _stopPingLoop();
    _socket?.clearListeners();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _playerId = null;
  }
}
