import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';
import '../../../services/multiplayer/multiplayer_service.dart';

/// Gère la connexion et la reconnexion silencieuse du mode multijoueur
/// Principe GRASP: Pure Fabrication - Responsabilité unique de gestion de la connexion
class MultiplayerConnectionManager {
  final MultiplayerService _multiplayerService;
  final VoidCallback _notifyListeners;
  final Future<void> Function(String roomCode, String playerName)? _onReconnectToRoom;

  SocketConnectionState _connectionState = SocketConnectionState.disconnected;
  SocketConnectionState get connectionState => _connectionState;

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  // Reconnexion silencieuse
  Timer? _reconnectionTimer;
  DateTime? _disconnectionTime;
  bool _isSilentReconnecting = false;
  bool get isSilentReconnecting => _isSilentReconnecting;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  MultiplayerConnectionManager({
    required MultiplayerService multiplayerService,
    required VoidCallback notifyListeners,
    Future<void> Function(String roomCode, String playerName)? onReconnectToRoom,
  })  : _multiplayerService = multiplayerService,
        _notifyListeners = notifyListeners,
        _onReconnectToRoom = onReconnectToRoom;

  void handleConnectionStateChanged(
    SocketConnectionState state,
    SocketConnectionState previousState,
    String? roomCode,
    List<Map<String, dynamic>> playersInLobby,
    String? playerId,
  ) {
    debugPrint('🔌 Connection state: $state');
    _connectionState = state;

    // Gestion de la reconnexion silencieuse
    if (state == SocketConnectionState.disconnected &&
        previousState == SocketConnectionState.connected) {
      _disconnectionTime = DateTime.now();
      _startSilentReconnection(roomCode, playersInLobby, playerId);
    } else if (state == SocketConnectionState.connected &&
        previousState == SocketConnectionState.disconnected) {
      _cancelSilentReconnection();
      if (_isSilentReconnecting) {
        debugPrint('✅ Reconnexion silencieuse réussie');
        _isSilentReconnecting = false;
      }
    }

    // Utiliser addPostFrameCallback pour éviter setState during build
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyListeners();
    });
  }

  void _startSilentReconnection(
    String? roomCode,
    List<Map<String, dynamic>> playersInLobby,
    String? playerId,
  ) {
    if (_isSilentReconnecting) return;

    debugPrint('🔄 Démarrage de la reconnexion silencieuse...');
    _isSilentReconnecting = true;

    // Annuler après 3 secondes si pas reconnecté
    _reconnectionTimer = Timer(const Duration(seconds: 3), () {
      if (_connectionState != SocketConnectionState.connected) {
        debugPrint('❌ Reconnexion silencieuse échouée après 3s');
        _isSilentReconnecting = false;
        if (_disconnectionTime != null) {
          final elapsed = DateTime.now().difference(_disconnectionTime!);
          if (elapsed.inSeconds >= 3) {
            _errorMessage = 'Connexion perdue avec le serveur';
          }
        }
        _notifyListeners();
      }
    });

    // Tenter de reconnecter immédiatement
    _attemptSilentReconnect(roomCode, playersInLobby, playerId);
  }

  void _cancelSilentReconnection() {
    _reconnectionTimer?.cancel();
    _reconnectionTimer = null;
    _disconnectionTime = null;
  }

  Future<void> _attemptSilentReconnect(
    String? roomCode,
    List<Map<String, dynamic>> playersInLobby,
    String? playerId,
  ) async {
    if (roomCode == null || roomCode.isEmpty) return;

    try {
      await Future.delayed(const Duration(milliseconds: 500));

      if (_connectionState == SocketConnectionState.connected) {
        return;
      }

      await _multiplayerService.connect();

      if (_connectionState == SocketConnectionState.connected && _onReconnectToRoom != null) {
        final savedPlayerName = playersInLobby.firstWhere(
              (p) => p['id'] == playerId,
              orElse: () => {'name': 'Joueur'},
            )['name'] as String? ??
            'Joueur';

        await _onReconnectToRoom!(roomCode, savedPlayerName);
      }
    } catch (e) {
      debugPrint('❌ Erreur lors de la reconnexion silencieuse: $e');
    }
  }

  Future<bool> reconnect(
    String? roomCode,
    List<Map<String, dynamic>> playersInLobby,
    String? playerId,
    void Function(bool inLobby) setInLobby,
  ) async {
    _errorMessage = null;
    _isConnecting = true;
    _notifyListeners();

    try {
      _multiplayerService.disconnect();
      await Future.delayed(const Duration(milliseconds: 500));
      await _multiplayerService.connect();

      if (roomCode != null && roomCode.isNotEmpty) {
        final savedPlayerName = playersInLobby.firstWhere(
              (p) => p['id'] == playerId,
              orElse: () => {'name': 'Joueur'},
            )['name'] as String? ??
            'Joueur';

        final rejoined = await _multiplayerService.joinRoom(
          roomCode: roomCode,
          playerName: savedPlayerName,
        );
        if (rejoined != null) {
          setInLobby(true);
          _isConnecting = false;
          _notifyListeners();
          return true;
        }
      }

      _isConnecting = false;
      _notifyListeners();
      return _multiplayerService.isConnected;
    } catch (e) {
      _errorMessage = 'Échec de la reconnexion: $e';
      _isConnecting = false;
      _notifyListeners();
      return false;
    }
  }

  Future<bool> checkServerReachable() async {
    return await _multiplayerService.checkServerHealth();
  }

  void setConnecting(bool connecting) {
    _isConnecting = connecting;
    _notifyListeners();
  }

  void setError(String? error) {
    _errorMessage = error;
    _notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    _notifyListeners();
  }

  void reset() {
    _connectionState = SocketConnectionState.disconnected;
    _isConnecting = false;
    _isSilentReconnecting = false;
    _errorMessage = null;
    _cancelSilentReconnection();
  }

  void dispose() {
    _reconnectionTimer?.cancel();
  }
}
