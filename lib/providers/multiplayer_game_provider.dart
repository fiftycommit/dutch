import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import '../models/game_state.dart';
import '../models/game_settings.dart';
import '../services/multiplayer_service.dart';
import '../services/haptic_service.dart';
import '../services/emote_service.dart';
import '../models/card.dart';
import '../models/player.dart';

enum GameEventType {
  playerJoined,
  playerLeft,
  error,
  kicked,
  gameStarted,
  info
}

class GameEvent {
  final GameEventType type;
  final String message;
  final Map<String, dynamic>? data;

  GameEvent(this.type, this.message, {this.data});
}

class MultiplayerGameProvider with ChangeNotifier, WidgetsBindingObserver {
  final MultiplayerService _multiplayerService;

  // Event Stream for UI feedback (Snackbars, etc.)
  final StreamController<GameEvent> _eventController =
      StreamController<GameEvent>.broadcast();
  Stream<GameEvent> get events => _eventController.stream;

  GameState? _gameState;
  GameState? get gameState => _gameState;

  String? _roomCode;
  String? get roomCode => _roomCode;

  // État de connexion
  SocketConnectionState _connectionState = SocketConnectionState.disconnected;
  SocketConnectionState get connectionState => _connectionState;

  // Room fermée par l'hôte
  bool _roomClosedByHost = false;
  bool get roomClosedByHost => _roomClosedByHost;
  String? _closedRoomCode;
  String? get closedRoomCode => _closedRoomCode;

  // Kick par l'hôte
  bool _wasKicked = false;
  bool get wasKicked => _wasKicked;
  String? _kickedMessage;
  String? get kickedMessage => _kickedMessage;

  // Notification: joueur parti
  bool _playerLeftNotification = false;
  bool get playerLeftNotification => _playerLeftNotification;
  String? _lastPlayerLeftName;
  String? get lastPlayerLeftName => _lastPlayerLeftName;

  // Notification: pouvoir spécial utilisé sur nous (ancien générique)
  bool _specialPowerNotification = false;
  bool get specialPowerNotification => _specialPowerNotification;
  String? _specialPowerByName;
  String? get specialPowerByName => _specialPowerByName;
  String? _specialPowerType;
  String? get specialPowerType => _specialPowerType;

  // Notification Valet : notre carte a été échangée
  Map<String, dynamic>? _pendingSwapNotification;
  Map<String, dynamic>? get pendingSwapNotification => _pendingSwapNotification;

  // Notification Joker : nos cartes ont été mélangées
  Map<String, dynamic>? _pendingJokerNotification;
  Map<String, dynamic>? get pendingJokerNotification =>
      _pendingJokerNotification;

  // Notification Espionnage : quelqu'un regarde notre carte
  Map<String, dynamic>? _pendingSpyNotification;
  Map<String, dynamic>? get pendingSpyNotification => _pendingSpyNotification;

  String? _hostPlayerId;
  String? get hostPlayerId => _hostPlayerId;

  bool _isHost = false;
  bool get isHost => _isHost;

  // Processing flag to prevent UI debounce loops (e.g. Special Power dialogs)
  bool _isProcessingAction = false;
  bool get isProcessing => _isProcessingAction;

  List<Map<String, dynamic>> _playersInLobby = [];
  List<Map<String, dynamic>> get playersInLobby => _playersInLobby;

  GameSettings? _roomSettings;
  GameSettings? get roomSettings => _roomSettings;

  // Scores cumulés (classement permanent)
  List<Map<String, dynamic>> _cumulativeScores = [];
  List<Map<String, dynamic>> get cumulativeScores => _cumulativeScores;

  // Mode de jeu actuel de la room
  GameMode _roomGameMode = GameMode.quick;
  GameMode get roomGameMode => _roomGameMode;

  // Statut actuel de la room
  String _roomStatus = 'waiting';
  String get roomStatus => _roomStatus;

  final List<Map<String, dynamic>> _chatMessages = [];
  List<Map<String, dynamic>> get chatMessages =>
      List.unmodifiable(_chatMessages);

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

  // Reconnexion silencieuse
  Timer? _reconnectionTimer;
  DateTime? _disconnectionTime;
  bool _isSilentReconnecting = false;
  bool get isSilentReconnecting => _isSilentReconnecting;

  // Émotes
  final EmoteService _emoteService = EmoteService();
  Stream<EmoteEvent> get emoteStream => _emoteService.emoteStream;
  final List<EmoteEvent> _recentEmotes = [];
  List<EmoteEvent> get recentEmotes => List.unmodifiable(_recentEmotes);

  bool _isInLobby = false;
  bool get isInLobby => _isInLobby;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  // Compatibility fields used by game-screen layout logic
  Set<int> shakingCardIndices = {};

  int get currentReactionTimeMs => _reactionTimeMs;

  bool _isPaused = false;
  bool get isPaused => _isPaused;

  String? _pausedByName;
  String? get pausedByName => _pausedByName;

  // New: Spied Card info
  PlayingCard? _lastSpiedCard;
  PlayingCard? get lastSpiedCard => _lastSpiedCard;
  String? _spiedTargetName;
  String? get spiedTargetName => _spiedTargetName;
  bool _showSpiedCardDialog = false;
  bool get showSpiedCardDialog => _showSpiedCardDialog;

  int _reactionTimeMs = 3000;
  int get reactionTimeMs => _reactionTimeMs;

  Timer? _reactionTick;
  int _reactionAnchorRemainingMs = 0;
  int _reactionAnchorLocalMs = 0;

  String? get playerId => _multiplayerService.playerId;
  String? get clientId => _multiplayerService.clientId;
  bool get isConnected => _multiplayerService.isConnected;
  bool get isReady => _localPresence?['ready'] == true;
  int get serverTimeOffsetMs => _multiplayerService.serverTimeOffsetMs;

  // Joueurs marqués comme AFK (timeout atteint)
  final Set<String> _afkPlayerIds = {};
  Set<String> get afkPlayerIds => Set.unmodifiable(_afkPlayerIds);

  bool isPlayerAfk(String playerId) => _afkPlayerIds.contains(playerId);

  int get readyHumanCount => _playersInLobby.where((p) {
        if (p['isHuman'] != true) return false;
        if (p['isSpectator'] == true) return false;
        if (p['connected'] == false) return false;
        return p['ready'] == true;
      }).length;

  MultiplayerGameProvider({MultiplayerService? multiplayerService})
      : _multiplayerService = multiplayerService ?? MultiplayerService() {
    WidgetsBinding.instance.addObserver(this);
    _setupListeners();
    // Nettoyer les rooms inactives au démarrage
    _multiplayerService.cleanupInactiveRooms();
  }

  Map<String, dynamic>? get _localPresence {
    final cid = _multiplayerService.clientId;
    if (cid != null) {
      final byClient = _presenceByClientId[cid];
      if (byClient != null) return byClient;
    }
    final pid = _multiplayerService.playerId;
    if (pid != null) {
      return _presenceById[pid];
    }
    return null;
  }

  void _setupListeners() {
    _multiplayerService.onGameStateUpdate = (gameState) {
      debugPrint('📥 Received game state update');

      // Detect turn change for notification
      final wasMyTurn = _gameState?.currentPlayer.id == playerId;
      final isNowMyTurn = gameState.currentPlayer.id == playerId &&
          gameState.phase == GamePhase.playing;

      if (!wasMyTurn && isNowMyTurn) {
        // C'est à nous de jouer !
        HapticService.importantAction();
        // Note: Sound could be played here if AudioService is accessible
      }

      _gameState = gameState;

      // Update local player state
      Player? me;
      try {
        me = gameState.players.firstWhere((p) => p.id == playerId);
      } catch (e) {
        me = null;
      }

      // Auto-switch to game view ONLY if we are an active player in the game
      if (me != null && !me.isSpectator) {
        _isPlaying = true;
        _isInLobby = false;
      }
      // If we are spectator (or not in player list), only switch if we were already watching
      // or if we are not in lobby (e.g. connection lost/restored while watching)
      else if (!_isInLobby && !_isPlaying) {
        // Auto-resume watching
        _isPlaying = true;
      }

      _syncReactionPhase();

      // If only one non-eliminated player remains, end the game locally
      // Local end-game detection disabled to rely on server authority
      // and avoid race conditions during phase transitions (like memorization)
      /*
      try {
        final alive = _gameState!.players
            .where((p) => !_gameState!.eliminatedPlayerIds.contains(p.id))
            .toList();
        if (alive.length <= 1 && _gameState!.phase != GamePhase.ended) {
          _gameState!.phase = GamePhase.ended;
          _isPlaying = false;
        }
      } catch (_) {}
      */
      notifyListeners();
    };

    _multiplayerService.onTimerUpdate = (remaining) {
      if (_gameState == null) return;
      _applyReactionServerUpdate(remaining);
    };

    _multiplayerService.onGameAllReady = (data) {
      _eventController.add(GameEvent(
          GameEventType.gameStarted, data['message'] ?? 'Le jeu commence !'));
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
      _eventController.add(GameEvent(
          GameEventType.playerJoined, "${player['name']} a rejoint la partie"));
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

    _multiplayerService.onPresenceUpdate = (data) {
      final hostId = data['hostPlayerId'];
      if (hostId is String) {
        _hostPlayerId = hostId;
      }

      final players = data['players'];
      if (players is List) {
        final normalized = players
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList()
          ..sort((a, b) => ((a['position'] as num?)?.toInt() ?? 0)
              .compareTo((b['position'] as num?)?.toInt() ?? 0));
        _playersInLobby = normalized;
      }

      final byId = <String, Map<String, dynamic>>{};
      final byClient = <String, Map<String, dynamic>>{};
      for (final entry in (players is List ? players : const [])) {
        if (entry is Map) {
          final map = entry.cast<String, dynamic>();
          final id = map['id'];
          final clientId = map['clientId'];
          if (id is String) byId[id] = map;
          if (clientId is String) byClient[clientId] = map;
        }
      }
      _presenceById = byId;
      _presenceByClientId = byClient;

      // Mode de jeu
      final gameMode = data['gameMode'];
      if (gameMode is int) {
        _roomGameMode = GameMode.values[gameMode];
      }

      // Statut de la room
      final status = data['status'];
      if (status is String) {
        _roomStatus = status;
      }

      // Scores cumulés
      final scores = data['cumulativeScores'];
      if (scores is List) {
        _cumulativeScores = scores
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }

      notifyListeners();
    };

    _multiplayerService.onPresenceCheck = (data) {
      _presenceCheckActive = true;
      _presenceCheckReason = data['reason']?.toString();
      _presenceCheckDeadlineMs =
          data['deadlineMs'] is int ? data['deadlineMs'] as int : 5000;
      notifyListeners();
    };

    _multiplayerService.onChatMessage = (data) {
      _chatMessages.add(data);
      if (_chatMessages.length > 120) {
        _chatMessages.removeAt(0);
      }
      notifyListeners();
    };

    _multiplayerService.onError = (error) {
      debugPrint('❌ Error: $error');
      _errorMessage = error;
      _isConnecting = false;
      notifyListeners();
    };

    _multiplayerService.onSocketConnectionStateChanged = (state) {
      debugPrint('🔌 Connection state: $state');
      final previousState = _connectionState;
      _connectionState = state;
      
      // Gestion de la reconnexion silencieuse
      if (state == SocketConnectionState.disconnected && 
          previousState == SocketConnectionState.connected) {
        _disconnectionTime = DateTime.now();
        _startSilentReconnection();
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
        notifyListeners();
      });
    };

    _multiplayerService.onRoomClosed = (data) {
      debugPrint('🚪 Room closed by host');
      _roomClosedByHost = true;
      _closedRoomCode = data['roomCode']?.toString();
      notifyListeners();
    };

    _multiplayerService.onRoomRestarted = (data) {
      debugPrint('🔄 Room restarted');
      _gameState = null;
      _isPlaying = false;
      _isInLobby = true;
      // Réinitialiser les joueurs à non-prêts
      for (final player in _playersInLobby) {
        player['ready'] = false;
      }
      notifyListeners();
    };

    _multiplayerService.onKicked = (data) {
      debugPrint('👢 Kicked from room');
      _wasKicked = true;
      _kickedMessage = data['message']?.toString() ?? 'Vous avez été exclu';
      _resetRoomState();
      notifyListeners();
    };

    _multiplayerService.onPlayerLeft = (data) {
      debugPrint('👋 Player left: ${data['playerName']}');
      _lastPlayerLeftName = data['playerName']?.toString();
      _playerLeftNotification = true;
      notifyListeners();
      // Auto-clear après 3 secondes
      Future.delayed(const Duration(seconds: 3), () {
        _playerLeftNotification = false;
        notifyListeners();
      });
    };

    _multiplayerService.onPlayerAfk = (data) {
      debugPrint('💤 Player AFK: ${data['playerName']} (${data['reason']})');
      final playerId = data['playerId']?.toString();
      final playerName = data['playerName']?.toString();
      if (playerId != null) {
        _afkPlayerIds.add(playerId);
      }
      // Réutiliser la notification de départ pour l'AFK
      _lastPlayerLeftName = playerName != null ? '$playerName (AFK)' : 'Joueur AFK';
      _playerLeftNotification = true;
      notifyListeners();
      // Auto-clear après 3 secondes
      Future.delayed(const Duration(seconds: 3), () {
        _playerLeftNotification = false;
        notifyListeners();
      });
    };

    _multiplayerService.onSpecialPowerTargeted = (data) {
      debugPrint('✨ Special power targeted by: ${data['byPlayerName']}');
      _specialPowerByName = data['byPlayerName']?.toString();
      _specialPowerType = data['powerType']?.toString();
      _specialPowerNotification = true;
      notifyListeners();
      // Auto-clear après 3 secondes
      Future.delayed(const Duration(seconds: 3), () {
        _specialPowerNotification = false;
        notifyListeners();
      });
    };

    _multiplayerService.onSpiedCard = (card, targetName) {
      debugPrint('👁️ Revealed card from $targetName: ${card.toString()}');
      _lastSpiedCard = card;
      _spiedTargetName = targetName;
      _showSpiedCardDialog = true;
      notifyListeners();
    };

    // Notification Valet : notre carte a été échangée par un autre joueur
    _multiplayerService.onSwapNotification = (data) {
      debugPrint(
          '🔄 Swap notification: ${data['byPlayerName']} échangé carte #${data['cardIndex']}');
      _pendingSwapNotification = data;
      notifyListeners();
    };

    // Notification Joker : nos cartes ont été mélangées par un autre joueur
    _multiplayerService.onJokerNotification = (data) {
      debugPrint(
          '🃏 Joker notification: ${data['byPlayerName']} a mélangé nos cartes');
      _pendingJokerNotification = data;
      notifyListeners();
    };

    // Notification Espionnage : quelqu'un regarde notre carte (pouvoir 10)
    _multiplayerService.onSpyNotification = (data) {
      debugPrint(
          '👁️ Spy notification: ${data['byPlayerName']} espionne notre carte #${data['cardIndex']}');
      _pendingSpyNotification = data;
      notifyListeners();
    };

    _multiplayerService.onGamePaused = (pausedBy) {
      debugPrint('⏸️ Game paused by $pausedBy');
      _isPaused = true;
      notifyListeners();
    };

    _multiplayerService.onGameResumed = (resumedBy) {
      debugPrint('▶️ Game resumed by $resumedBy');
      _isPaused = false;
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
    _reactionTick = Timer.periodic(
        const Duration(milliseconds: 50), (_) => _tickReaction());
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
        _hostPlayerId = _multiplayerService.playerId;
        _playersInLobby = [
          {
            'id': _multiplayerService.playerId,
            'clientId': _multiplayerService.clientId,
            'name': playerName,
            'isHuman': true,
            'ready': false,
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

  // Créer une room publique et aller au lobby
  Future<void> createPublicRoom({String playerName = 'Joueur'}) async {
    try {
      _isConnecting = true;
      _errorMessage = null;
      notifyListeners();

      await createRoom(
        settings: GameSettings(
          gameMode: GameMode.quick,
          numberOfPlayers: 4,
          isPublic: true,
          minPlayers: 2,
          maxPlayers: 4,
        ),
        playerName: playerName,
      );

      _isConnecting = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isConnecting = false;
      notifyListeners();
      rethrow;
    }
  }

  // Chercher et rejoindre une room publique existante
  Future<void> searchAndJoinPublicRoom({String playerName = 'Joueur'}) async {
    try {
      _isConnecting = true;
      _errorMessage = null;
      notifyListeners();

      // Chercher des rooms publiques disponibles
      final publicRooms = await _multiplayerService.getPublicRooms();
      
      if (publicRooms != null && publicRooms.isNotEmpty) {
        // Rejoindre la première room disponible
        final room = publicRooms.first;
        await joinRoom(
          roomCode: room['code'] as String,
          playerName: playerName,
        );
      } else {
        // Aucune room disponible
        throw Exception('Aucune partie publique disponible');
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

  Future<List<Map<String, dynamic>>?> getPublicRooms() async {
    try {
      return await _multiplayerService.getPublicRooms();
    } catch (e) {
      debugPrint('Error getting public rooms: $e');
      return null;
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
        final hostId = room['hostPlayerId'];
        if (hostId is String) {
          _hostPlayerId = hostId;
        }
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
            'ready': false,
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

  Future<void> startGame({bool fillBots = false}) async {
    if (!_isHost) {
      _errorMessage = "Seul l'hôte peut démarrer la partie";
      notifyListeners();
      return;
    }

    final minPlayers = _roomSettings?.minPlayers ?? 2;
    if (!isReady) {
      _errorMessage = "Vous devez être prêt pour démarrer";
      notifyListeners();
      return;
    }
    if (readyHumanCount < minPlayers) {
      _errorMessage = "Minimum $minPlayers joueurs prêts requis";
      notifyListeners();
      return;
    }

    try {
      _errorMessage = null;
      final success = await _multiplayerService.startGame(fillBots: fillBots);

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

  @Deprecated('Utiliser les méthodes spécifiques usePower7/10/Valet/Joker')
  void useSpecialPower(int targetPlayerIndex, int targetCardIndex) {
    if (_gameState == null || _isProcessingAction) return;
    _isProcessingAction = true;
    notifyListeners(); // Immediate update to lock UI
    _multiplayerService.usePower10SpyOpponent(
        targetPlayerIndex, targetCardIndex);
    // Auto-clear processing after delay in case of server lag, or rely on game state update?
    // Let's rely on gamestate update to unlock, or a short timeout.
    // Safe fallback:
    Future.delayed(const Duration(seconds: 2), () {
      if (_isProcessingAction) {
        _isProcessingAction = false;
        notifyListeners();
      }
    });
  }

  void skipSpecialPower() {
    if (_gameState == null || _isProcessingAction) return;
    _isProcessingAction = true;
    notifyListeners();
    _multiplayerService.skipSpecialPower();
    // Safe fallback
    Future.delayed(const Duration(seconds: 2), () {
      if (_isProcessingAction) {
        _isProcessingAction = false;
        notifyListeners();
      }
    });
  }

  /// Carte 7 : Regarder sa propre carte
  void usePower7LookOwnCard(int cardIndex) {
    if (_gameState == null || _isProcessingAction) return;
    _isProcessingAction = true;
    notifyListeners();
    _multiplayerService.usePower7LookOwnCard(cardIndex);
    Future.delayed(const Duration(seconds: 2), () {
      if (_isProcessingAction) {
        _isProcessingAction = false;
        notifyListeners();
      }
    });
  }

  /// Carte 10 : Espionner une carte adversaire
  void usePower10SpyOpponent(int targetPlayerIndex, int targetCardIndex) {
    if (_gameState == null || _isProcessingAction) return;
    _isProcessingAction = true;
    notifyListeners();
    _multiplayerService.usePower10SpyOpponent(
        targetPlayerIndex, targetCardIndex);
    Future.delayed(const Duration(seconds: 2), () {
      if (_isProcessingAction) {
        _isProcessingAction = false;
        notifyListeners();
      }
    });
  }

  /// Carte V (Valet) : Échange universel entre 2 joueurs
  void usePowerValetSwap(
      int player1Index, int card1Index, int player2Index, int card2Index) {
    if (_gameState == null || _isProcessingAction) return;
    _isProcessingAction = true;
    notifyListeners();
    _multiplayerService.usePowerValetSwap(
        player1Index, card1Index, player2Index, card2Index);
    Future.delayed(const Duration(seconds: 2), () {
      if (_isProcessingAction) {
        _isProcessingAction = false;
        notifyListeners();
      }
    });
  }

  /// JOKER : Mélanger la main d'un joueur (y compris soi-même)
  void usePowerJokerShuffle(int targetPlayerIndex) {
    if (_gameState == null || _isProcessingAction) return;
    _isProcessingAction = true;
    notifyListeners();
    _multiplayerService.usePowerJokerShuffle(targetPlayerIndex);
    Future.delayed(const Duration(seconds: 2), () {
      if (_isProcessingAction) {
        _isProcessingAction = false;
        notifyListeners();
      }
    });
  }

  /// Effacer la notification Valet après affichage du dialog
  void clearSwapNotification() {
    _pendingSwapNotification = null;
    notifyListeners();
  }

  /// Effacer la notification Joker après affichage du dialog
  void clearJokerNotification() {
    _pendingJokerNotification = null;
    notifyListeners();
  }

  /// Effacer la notification Espionnage après affichage du dialog
  void clearSpyNotification() {
    _pendingSpyNotification = null;
    notifyListeners();
  }

  Future<void> leaveRoom() async {
    if (_isHost) {
      // Si on est l'hôte, on ferme la salle pour tout le monde
      await closeRoom();
    } else {
      // Sinon on quitte juste
      _multiplayerService.leaveRoom();
    }
    _resetRoomState();
  }

  /// Tente de reconnecter au serveur.
  /// Si un roomCode était en cours, tente de rejoindre automatiquement.
  Future<bool> reconnect() async {
    _errorMessage = null;
    _isConnecting = true;
    notifyListeners();

    try {
      // Disconnect cleanly first
      _multiplayerService.disconnect();

      // Small delay to allow cleanup
      await Future.delayed(const Duration(milliseconds: 500));

      // Reconnect
      await _multiplayerService.connect();

      // If we had a room, try to rejoin
      if (_roomCode != null && _roomCode!.isNotEmpty) {
        final savedPlayerName = _playersInLobby.firstWhere(
              (p) => p['id'] == playerId,
              orElse: () => {'name': 'Joueur'},
            )['name'] as String? ??
            'Joueur';

        final rejoined = await _multiplayerService.joinRoom(
          roomCode: _roomCode!,
          playerName: savedPlayerName,
        );
        if (rejoined != null) {
          _isInLobby = true;
          _isConnecting = false;
          notifyListeners();
          return true;
        }
      }

      _isConnecting = false;
      notifyListeners();
      return _multiplayerService.isConnected;
    } catch (e) {
      _errorMessage = 'Échec de la reconnexion: $e';
      _isConnecting = false;
      notifyListeners();
      return false;
    }
  }

  /// Clear error message after user acknowledges
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Check if server is reachable (HTTP check only, no socket connection)
  Future<bool> checkServerReachable() async {
    return await _multiplayerService.checkServerHealth();
  }

  /// Ferme la room (hôte uniquement)
  Future<bool> closeRoom() async {
    if (!_isHost) return false;

    final success = await _multiplayerService.closeRoom();
    if (success) {
      _resetRoomState();
    }
    return success;
  }

  /// Devenir hôte d'une room fermée
  Future<bool> becomeHost() async {
    if (_closedRoomCode == null) return false;

    final success = await _multiplayerService.becomeHost(_closedRoomCode!);
    if (success) {
      _roomCode = _closedRoomCode;
      _isHost = true;
      _isInLobby = true;
      _roomClosedByHost = false;
      _closedRoomCode = null;
      notifyListeners();
    }
    return success;
  }

  /// Quitte définitivement après fermeture par l'hôte
  void acknowledgeRoomClosed() {
    _roomClosedByHost = false;
    _closedRoomCode = null;
    _resetRoomState();
  }

  /// Réinitialise l'état après avoir été kick
  void acknowledgeKicked() {
    _wasKicked = false;
    _kickedMessage = null;
  }

  /// Relance la partie (rematch) - hôte uniquement
  Future<bool> restartGame() async {
    if (!_isHost) return false;

    final success = await _multiplayerService.restartGame();
    return success;
  }

  /// Kick un joueur (hôte uniquement)
  Future<bool> kickPlayer(String clientId) async {
    if (!_isHost) return false;

    final success = await _multiplayerService.kickPlayer(clientId);
    return success;
  }

  /// Change le mode de jeu (hôte uniquement)
  Future<bool> setGameMode(GameMode mode) async {
    if (!_isHost) return false;

    final success = await _multiplayerService.setGameMode(mode.index);
    if (success && _roomSettings != null) {
      _roomSettings = GameSettings(
        gameMode: mode,
        botDifficulty: _roomSettings!.botDifficulty,
        luckDifficulty: _roomSettings!.luckDifficulty,
        reactionTimeMs: _roomSettings!.reactionTimeMs,
        minPlayers: _roomSettings!.minPlayers,
        maxPlayers: _roomSettings!.maxPlayers,
      );
      notifyListeners();
    }
    return success;
  }

  /// Met à jour les paramètres de la room (hôte uniquement)
  Future<bool> updateRoomSettings({
    Difficulty? botDifficulty,
    Difficulty? luckDifficulty,
  }) async {
    if (!_isHost) return false;

    final success = await _multiplayerService.updateRoomSettings(
      botDifficulty: botDifficulty?.index,
      luckDifficulty: luckDifficulty?.index,
    );

    if (success && _roomSettings != null) {
      _roomSettings = GameSettings(
        gameMode: _roomSettings!.gameMode,
        botDifficulty: botDifficulty ?? _roomSettings!.botDifficulty,
        luckDifficulty: luckDifficulty ?? _roomSettings!.luckDifficulty,
        reactionTimeMs: _roomSettings!.reactionTimeMs,
        minPlayers: _roomSettings!.minPlayers,
        maxPlayers: _roomSettings!.maxPlayers,
      );
      notifyListeners();
    }
    return success;
  }

  /// Vérifie quelles rooms sont actives
  Future<List<Map<String, dynamic>>?> checkActiveRooms(
      List<String> roomCodes) async {
    return await _multiplayerService.checkActiveRooms(roomCodes);
  }

  /// Nettoie les rooms inactives
  Future<void> cleanupInactiveRooms() async {
    await _multiplayerService.cleanupInactiveRooms();
  }

  /// Demande une synchronisation complète
  void requestFullState() {
    _multiplayerService.requestFullState();
  }

  /// Pause la partie (demande serveur)
  void pauseGame() {
    _multiplayerService.socket?.emit('game:pause', {'roomCode': _roomCode});
  }

  /// Reprend la partie (demande serveur)
  void resumeGame() {
    _multiplayerService.socket?.emit('game:resume', {'roomCode': _roomCode});
  }

  void closeSpiedCardDialog() {
    _showSpiedCardDialog = false;
    _lastSpiedCard = null;
    notifyListeners();
  }

  void _resetRoomState() {
    _roomCode = null;
    _hostPlayerId = null;
    _gameState = null;
    _isHost = false;
    _isInLobby = false;
    _isPlaying = false;
    _playersInLobby = [];
    _roomSettings = null;
    _cumulativeScores = [];
    _roomGameMode = GameMode.quick;
    _roomStatus = 'waiting';
    _chatMessages.clear();
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

  void setReady(bool ready) {
    _multiplayerService.setReady(ready);
    final cid = _multiplayerService.clientId;
    final pid = _multiplayerService.playerId;
    for (final player in _playersInLobby) {
      if ((cid != null && player['clientId'] == cid) ||
          (pid != null && player['id'] == pid)) {
        player['ready'] = ready;
      }
    }
    notifyListeners();
  }

  void sendChatMessage(String message) {
    _multiplayerService.sendChatMessage(message);
  }

  void sendEmote(String emoji) {
    final playerName = _playersInLobby
        .firstWhere(
          (p) => p['id'] == playerId,
          orElse: () => {'name': 'Joueur'},
        )['name'] as String? ?? 'Joueur';
    
    // Envoyer via le service multiplayer
    _multiplayerService.socket?.emit('game:emote', {
      'roomCode': _roomCode,
      'emoji': emoji,
      'playerName': playerName,
    });
    
    // Ajouter localement
    final emote = EmoteEvent(
      emoji: emoji,
      playerName: playerName,
      playerId: playerId ?? '',
      timestamp: DateTime.now(),
    );
    _emoteService.sendEmote(emoji, playerName, playerId ?? '');
    _recentEmotes.add(emote);
    if (_recentEmotes.length > 10) {
      _recentEmotes.removeAt(0);
    }
    notifyListeners();
  }

  void _startSilentReconnection() {
    if (_isSilentReconnecting) return;
    
    debugPrint('🔄 Démarrage de la reconnexion silencieuse...');
    _isSilentReconnecting = true;
    
    // Annuler après 3 secondes si pas reconnecté
    _reconnectionTimer = Timer(const Duration(seconds: 3), () {
      if (_connectionState != SocketConnectionState.connected) {
        debugPrint('❌ Reconnexion silencieuse échouée après 3s');
        _isSilentReconnecting = false;
        // Afficher l'erreur normale
        if (_disconnectionTime != null) {
          final elapsed = DateTime.now().difference(_disconnectionTime!);
          if (elapsed.inSeconds >= 3) {
            _errorMessage = 'Connexion perdue avec le serveur';
          }
        }
        notifyListeners();
      }
    });
    
    // Tenter de reconnecter immédiatement
    _attemptSilentReconnect();
  }

  void _cancelSilentReconnection() {
    _reconnectionTimer?.cancel();
    _reconnectionTimer = null;
    _disconnectionTime = null;
  }

  Future<void> _attemptSilentReconnect() async {
    if (_roomCode == null || _roomCode!.isEmpty) return;
    
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (_connectionState == SocketConnectionState.connected) {
        // Déjà reconnecté
        return;
      }
      
      // Tenter de reconnecter
      await _multiplayerService.connect();
      
      // Si on avait une room, tenter de rejoindre
      if (_connectionState == SocketConnectionState.connected) {
        final savedPlayerName = _playersInLobby.firstWhere(
              (p) => p['id'] == playerId,
              orElse: () => {'name': 'Joueur'},
            )['name'] as String? ?? 'Joueur';

        await _multiplayerService.joinRoom(
          roomCode: _roomCode!,
          playerName: savedPlayerName,
        );
      }
    } catch (e) {
      debugPrint('❌ Erreur lors de la reconnexion silencieuse: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!isConnected || _roomCode == null) return;
    _multiplayerService.setFocused(state == AppLifecycleState.resumed);
  }

  Future<void> forfeitGame() async {
    _multiplayerService.cancelGame();
    _isPlaying = false;
    _isInLobby = true;
    notifyListeners();
  }

  void markReady() {
    _multiplayerService.markReady();
  }

  void watchGame() {
    if (_gameState != null) {
      _isPlaying = true;
      _isInLobby = false;
      notifyListeners();
    }
  }

  // Gestion des rooms sauvegardées
  Future<List<SavedRoom>> getMyRooms() => _multiplayerService.getMyRooms();
  Future<void> removeRoom(String roomCode) =>
      _multiplayerService.removeSavedRoom(roomCode);

  @override
  void dispose() {
    _eventController.close();
    _reconnectionTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _multiplayerService.disconnect();
    _stopReactionTicker();

    super.dispose();
  }
}
