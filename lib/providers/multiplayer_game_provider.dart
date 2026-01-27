import 'dart:async';
import 'package:flutter/widgets.dart';
import '../models/game_state.dart';
import '../models/game_settings.dart';
import '../services/multiplayer_service.dart';

class MultiplayerGameProvider with ChangeNotifier, WidgetsBindingObserver {
  final MultiplayerService _multiplayerService;

  GameState? _gameState;
  GameState? get gameState => _gameState;

  String? _roomCode;
  String? get roomCode => _roomCode;

  bool _isHost = false;
  bool get isHost => _isHost;

  List<Map<String, dynamic>> _playersInLobby = [];
  List<Map<String, dynamic>> get playersInLobby => _playersInLobby;

  GameSettings? _roomSettings;
  GameSettings? get roomSettings => _roomSettings;

  Map<String, Map<String, dynamic>> _presenceById = {};
  Map<String, Map<String, dynamic>> _presenceByClientId = {};
  Map<String, Map<String, dynamic>> get presenceById => _presenceById;
  Map<String, Map<String, dynamic>> get presenceByClientId =>
      _presenceByClientId;

  bool _presenceCheckActive = false;
  String? _presenceCheckReason;
  int _presenceCheckDeadlineMs = 0;
  bool get presenceCheckActive => _presenceCheckActive;
  String? get presenceCheckReason => _presenceCheckReason;
  int get presenceCheckDeadlineMs => _presenceCheckDeadlineMs;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  bool _isInLobby = false;
  bool get isInLobby => _isInLobby;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  int _reactionTimeMs = 3000;
  int get reactionTimeMs => _reactionTimeMs;

  Timer? _reactionTick;
  int _reactionAnchorRemainingMs = 0;
  int _reactionAnchorLocalMs = 0;

  String? get playerId => _multiplayerService.playerId;
  String? get clientId => _multiplayerService.clientId;
  bool get isConnected => _multiplayerService.isConnected;

  MultiplayerGameProvider({MultiplayerService? multiplayerService})
      : _multiplayerService = multiplayerService ?? MultiplayerService() {
    WidgetsBinding.instance.addObserver(this);
    _setupListeners();
  }

  void _setupListeners() {
    _multiplayerService.onGameStateUpdate = (gameState) {
      debugPrint('📥 Received game state update');
      _gameState = gameState;
      _isPlaying = true;
      _isInLobby = false;
      _syncReactionPhase();
    };

    _multiplayerService.onTimerUpdate = (remaining) {
      if (_gameState == null) return;
      _applyReactionServerUpdate(remaining);
    };

    _multiplayerService.onPlayerJoined = (data) {
      debugPrint('👥 Player joined: ${data['player']}');
      // Mettre à jour la liste des joueurs dans le lobby
      final player = data['player'];
      if (player == null) return;
      final clientId = player['clientId'];
      if (clientId != null) {
        final index =
            _playersInLobby.indexWhere((p) => p['clientId'] == clientId);
        if (index >= 0) {
          _playersInLobby[index] = player;
        } else {
          _playersInLobby.add(player);
        }
      } else if (!_playersInLobby.any((p) => p['id'] == player['id'])) {
        _playersInLobby.add(player);
      }
      notifyListeners();
    };

    _multiplayerService.onGameStarted = (message) {
      debugPrint('🎮 Game started: $message');
      _isInLobby = false;
      _isPlaying = true;
      notifyListeners();
    };

    _multiplayerService.onReactionTimeConfig = (ms) {
      if (ms <= 0) return;
      _reactionTimeMs = ms;
      _syncReactionPhase();
    };

    _multiplayerService.onPresenceUpdate = (players) {
      final byId = <String, Map<String, dynamic>>{};
      final byClient = <String, Map<String, dynamic>>{};
      for (final entry in players) {
        if (entry is Map<String, dynamic>) {
          final id = entry['id'];
          final clientId = entry['clientId'];
          if (id is String) byId[id] = entry;
          if (clientId is String) byClient[clientId] = entry;
        }
      }
      _presenceById = byId;
      _presenceByClientId = byClient;
      notifyListeners();
    };

    _multiplayerService.onPresenceCheck = (data) {
      _presenceCheckActive = true;
      _presenceCheckReason = data['reason']?.toString();
      _presenceCheckDeadlineMs =
          data['deadlineMs'] is int ? data['deadlineMs'] as int : 5000;
      notifyListeners();
    };

    _multiplayerService.onError = (error) {
      debugPrint('❌ Error: $error');
      _errorMessage = error;
      _isConnecting = false;
      notifyListeners();
    };
  }

  int _adjustForLatency(int remaining) {
    final latency = _multiplayerService.latencyMs;
    if (latency <= 0) return remaining;
    final adjusted = remaining - (latency ~/ 2);
    return adjusted < 0 ? 0 : adjusted;
  }

  void _applyReactionServerUpdate(int remaining) {
    final adjusted = _adjustForLatency(remaining);
    _reactionAnchorRemainingMs = adjusted;
    _reactionAnchorLocalMs = DateTime.now().millisecondsSinceEpoch;
    if (_gameState != null) {
      _gameState!.reactionTimeRemaining = adjusted;
    }
    _startReactionTicker();
    notifyListeners();
  }

  void _syncReactionPhase() {
    if (_gameState == null) return;

    if (_gameState!.phase == GamePhase.reaction) {
      final startTime = _gameState!.reactionStartTime;
      if (startTime != null) {
        final serverNow = _multiplayerService.serverNowMs;
        final elapsed = serverNow - startTime.millisecondsSinceEpoch;
        final remaining = (_reactionTimeMs - elapsed).clamp(0, 600000);
        _applyReactionServerUpdate(remaining);
        return;
      }

      _applyReactionServerUpdate(_gameState!.reactionTimeRemaining);
      return;
    }

    _stopReactionTicker();
    notifyListeners();
  }

  void _startReactionTicker() {
    if (_reactionTick != null) return;
    _reactionTick =
        Timer.periodic(const Duration(milliseconds: 50), (_) => _tickReaction());
  }

  void _stopReactionTicker() {
    _reactionTick?.cancel();
    _reactionTick = null;
  }

  void _tickReaction() {
    if (_gameState == null || _gameState!.phase != GamePhase.reaction) {
      _stopReactionTicker();
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - _reactionAnchorLocalMs;
    final remaining = (_reactionAnchorRemainingMs - elapsed).clamp(0, 600000);

    if (remaining != _gameState!.reactionTimeRemaining) {
      _gameState!.reactionTimeRemaining = remaining;
      notifyListeners();
    }
  }

  Future<void> createRoom({
    required GameSettings settings,
    required String playerName,
  }) async {
    try {
      _isConnecting = true;
      _errorMessage = null;
      _reactionTimeMs = settings.reactionTimeMs;
      notifyListeners();

      _roomCode = await _multiplayerService.createRoom(
        settings: settings,
        playerName: playerName,
      );

      if (_roomCode != null) {
        _isHost = true;
        _isInLobby = true;
        _roomSettings = settings;
        _playersInLobby = [
          {
            'id': _multiplayerService.playerId,
            'clientId': _multiplayerService.clientId,
            'name': playerName,
            'isHuman': true,
          }
        ];
        _multiplayerService.setFocused(true);
      }

      _isConnecting = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isConnecting = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> joinRoom({
    required String roomCode,
    required String playerName,
  }) async {
    try {
      _isConnecting = true;
      _errorMessage = null;
      notifyListeners();

      final room = await _multiplayerService.joinRoom(
        roomCode: roomCode,
        playerName: playerName,
      );

      _roomCode = roomCode;
      _isHost = false;
      _isInLobby = true;
      if (room != null && room['players'] is List) {
        _playersInLobby =
            (room['players'] as List).cast<Map<String, dynamic>>();
        if (room['settings'] is Map<String, dynamic>) {
          _roomSettings = GameSettings.fromJson(
            (room['settings'] as Map<String, dynamic>),
          );
        }
      } else {
        _playersInLobby = [
          {
            'id': _multiplayerService.playerId,
            'clientId': _multiplayerService.clientId,
            'name': playerName,
            'isHuman': true,
          }
        ];
      }
      _multiplayerService.setFocused(true);
      _isConnecting = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isConnecting = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> startGame() async {
    if (!_isHost) {
      _errorMessage = "Seul l'hôte peut démarrer la partie";
      notifyListeners();
      return;
    }

    try {
      _errorMessage = null;
      final success = await _multiplayerService.startGame();

      if (!success) {
        _errorMessage = "Erreur lors du démarrage de la partie";
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  // Actions de jeu - déléguer au service
  void drawCard() {
    if (_gameState == null) return;
    _multiplayerService.drawCard();
  }

  void replaceCard(int cardIndex) {
    if (_gameState == null) return;
    _multiplayerService.replaceCard(cardIndex);
  }

  void discardDrawnCard() {
    if (_gameState == null) return;
    _multiplayerService.discardDrawnCard();
  }

  void takeFromDiscard() {
    if (_gameState == null) return;
    _multiplayerService.takeFromDiscard();
  }

  void callDutch() {
    if (_gameState == null) return;
    _multiplayerService.callDutch();
  }

  void attemptMatch(int cardIndex) {
    if (_gameState == null) return;
    _multiplayerService.attemptMatch(cardIndex);
  }

  void useSpecialPower(int targetPlayerIndex, int targetCardIndex) {
    if (_gameState == null) return;
    _multiplayerService.useSpecialPower(targetPlayerIndex, targetCardIndex);
  }

  void completeSwap(int ownCardIndex) {
    if (_gameState == null) return;
    _multiplayerService.completeSwap(ownCardIndex);
  }

  void skipSpecialPower() {
    if (_gameState == null) return;
    _multiplayerService.skipSpecialPower();
  }

  void leaveRoom() {
    _multiplayerService.leaveRoom();
    _roomCode = null;
    _gameState = null;
    _isHost = false;
    _isInLobby = false;
    _isPlaying = false;
    _playersInLobby = [];
    _roomSettings = null;
    _presenceById = {};
    _presenceByClientId = {};
    _presenceCheckActive = false;
    _presenceCheckReason = null;
    _presenceCheckDeadlineMs = 0;
    _reactionTimeMs = 3000;
    _stopReactionTicker();
    notifyListeners();
  }

  void confirmPresence() {
    _multiplayerService.confirmPresence();
    _presenceCheckActive = false;
    _presenceCheckReason = null;
    _presenceCheckDeadlineMs = 0;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!isConnected || _roomCode == null) return;
    _multiplayerService.setFocused(state == AppLifecycleState.resumed);
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _multiplayerService.disconnect();
    _stopReactionTicker();
    super.dispose();
  }
}
