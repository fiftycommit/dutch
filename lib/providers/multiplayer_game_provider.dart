import 'dart:async';
import 'package:flutter/widgets.dart';
import '../models/game_state.dart';
import '../models/game_settings.dart';
import '../services/multiplayer/multiplayer_service.dart';
import '../core/interfaces/i_haptic_service.dart';
import '../services/ui/emote_service.dart';
import '../models/playing_card.dart';
import '../models/player.dart';
import '../core/interfaces/i_game_controller.dart';
import 'managers/multiplayer/multiplayer_notification_manager.dart';
import 'managers/multiplayer/multiplayer_timer_manager.dart';
import 'managers/multiplayer/multiplayer_chat_manager.dart';
import 'managers/multiplayer/multiplayer_connection_manager.dart';
import '../services/notifications/in_app_notification_service.dart';
import '../router/app_router.dart';
import '../services/web/web_session_storage.dart'
    if (dart.library.io) '../services/web/web_session_storage_stub.dart';

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

/// MultiplayerGameProvider refactoré - ~600 lignes au lieu de 1344
/// Principe SOLID: SRP - Coordination uniquement, logique déléguée aux managers
/// Implements IGameController pour permettre l'UI unifiée
class MultiplayerGameProvider
    with ChangeNotifier, WidgetsBindingObserver
    implements IGameController {
  final MultiplayerService _multiplayerService;
  final IHapticService _hapticService;
  bool _isDisposed = false;

  // Event Stream for UI feedback
  final StreamController<GameEvent> _eventController =
      StreamController<GameEvent>.broadcast();
  Stream<GameEvent> get events => _eventController.stream;

  // Managers
  late final MultiplayerNotificationManager _notificationManager;
  late final MultiplayerTimerManager _timerManager;
  late final MultiplayerChatManager _chatManager;
  late final MultiplayerConnectionManager _connectionManager;

  // État du jeu
  GameState? _gameState;
  @override
  GameState? get gameState => _gameState;

  String? _roomCode;
  String? get roomCode => _roomCode;

  String? _hostPlayerId;
  String? get hostPlayerId => _hostPlayerId;

  /// Computed from server-authoritative _hostPlayerId.
  /// Never stored — always derived to avoid stale host state.
  bool get isHost =>
      _hostPlayerId != null && playerId != null && _hostPlayerId == playerId;

  /// UID Firebase courant (extrait du JWT). Utilisé en filet de sécurité
  /// dans les handlers de notification pour ne jamais afficher une notif
  /// déclenchée par soi-même (au cas où un broadcast serveur fuirait).
  String? get _myAuthUid => _multiplayerService.authUid;

  bool _isProcessingAction = false;
  @override
  bool get isProcessing => _isProcessingAction;

  List<Map<String, dynamic>> _playersInLobby = [];
  List<Map<String, dynamic>> get playersInLobby => _playersInLobby;

  GameSettings? _roomSettings;
  GameSettings? get roomSettings => _roomSettings;

  List<Map<String, dynamic>> _cumulativeScores = [];
  List<Map<String, dynamic>> get cumulativeScores => _cumulativeScores;

  GameMode _roomGameMode = GameMode.quick;
  GameMode get roomGameMode => _roomGameMode;

  String _roomStatus = 'waiting';
  String get roomStatus => _roomStatus;

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

  bool _isInLobby = false;
  bool get isInLobby => _isInLobby;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  @override
  Set<int> shakingCardIndices = {};

  bool _isPaused = false;
  @override
  bool get isPaused => _isPaused;

  @override
  bool get hasActiveGame => _gameState != null && _isPlaying;

  @override
  Player? get localPlayer =>
      _gameState?.players.where((p) => p.id == playerId).firstOrNull;

  @override
  bool get isLocalPlayerTurn {
    final gs = _gameState;
    if (gs == null) return false;
    if (gs.currentPlayerIndex < 0 ||
        gs.currentPlayerIndex >= gs.players.length) {
      return false;
    }
    return gs.players[gs.currentPlayerIndex].id == playerId;
  }

  @override
  bool get canLocalPlayerAct =>
      _gameState != null &&
      isLocalPlayerTurn &&
      _gameState!.phase == GamePhase.playing;

  String? _pausedByName;
  String? get pausedByName => _pausedByName;
  String? _pausedByPlayerId;
  String? get pausedByPlayerId => _pausedByPlayerId;
  int _pauseDeadlineMs = 0;
  int get pauseDeadlineMs => _pauseDeadlineMs;
  bool get isLocalPauser =>
      _pausedByPlayerId != null && _pausedByPlayerId == playerId;

  PlayingCard? _lastSpiedCard;
  PlayingCard? get lastSpiedCard => _lastSpiedCard;
  String? _spiedTargetName;
  String? get spiedTargetName => _spiedTargetName;
  bool _showSpiedCardDialog = false;
  bool get showSpiedCardDialog => _showSpiedCardDialog;

  // Cible de pouvoir en temps réel (Valet)
  int? _pendingValetPlayer1;
  int? _pendingValetCard1;
  int? _pendingValetPlayer2;
  int? _pendingValetCard2;

  int? get pendingValetPlayer1 => _pendingValetPlayer1;
  int? get pendingValetCard1 => _pendingValetCard1;
  int? get pendingValetPlayer2 => _pendingValetPlayer2;
  int? get pendingValetCard2 => _pendingValetCard2;

  // Indices des joueurs ciblés par un pouvoir (pour illuminer leur main)
  Set<int> _powerTargetPlayerIndices = {};

  /// IDs des joueurs dont la main doit être illuminée (pouvoir en cours)
  Set<String> get powerTargetPlayerIds {
    final gs = _gameState;
    if (gs == null) return {};
    return _powerTargetPlayerIndices
        .where((i) => i >= 0 && i < gs.players.length)
        .map((i) => gs.players[i].id)
        .toSet();
  }

  /// Carte préchargée du deck pour éliminer la latence lors de la pioche
  PlayingCard? _preloadedDeckCard;
  bool _hasOptimisticDrawnCard = false;

  final Set<String> _afkPlayerIds = {};
  Set<String> get afkPlayerIds => Set.unmodifiable(_afkPlayerIds);

  // Délégations aux managers
  SocketConnectionState get connectionState =>
      _connectionManager.connectionState;
  bool get isConnecting => _connectionManager.isConnecting;
  bool get isSilentReconnecting => _connectionManager.isSilentReconnecting;
  String? get errorMessage =>
      _notificationManager.errorMessage ?? _connectionManager.errorMessage;

  bool get roomClosedByHost => _notificationManager.roomClosedByHost;
  String? get closedRoomCode => _notificationManager.closedRoomCode;
  bool get wasKicked => _notificationManager.wasKicked;
  String? get kickedMessage => _notificationManager.kickedMessage;
  bool get wasBanned => _notificationManager.wasBanned;
  String? get bannedMessage => _notificationManager.bannedMessage;
  bool get playerLeftNotification =>
      _notificationManager.playerLeftNotification;
  String? get lastPlayerLeftName => _notificationManager.lastPlayerLeftName;
  bool get specialPowerNotification =>
      _notificationManager.specialPowerNotification;
  String? get specialPowerByName => _notificationManager.specialPowerByName;
  String? get specialPowerType => _notificationManager.specialPowerType;
  Map<String, dynamic>? get pendingSwapNotification =>
      _notificationManager.pendingSwapNotification;
  Map<String, dynamic>? get pendingJokerNotification =>
      _notificationManager.pendingJokerNotification;
  Map<String, dynamic>? get pendingSpyNotification =>
      _notificationManager.pendingSpyNotification;

  @override
  int get currentReactionTimeMs => _timerManager.reactionTimeMs;
  int get reactionTimeMs => _timerManager.reactionTimeMs;

  List<Map<String, dynamic>> get chatMessages => _chatManager.chatMessages;
  List<EmoteEvent> get recentEmotes => _chatManager.recentEmotes;
  Stream<EmoteEvent> get emoteStream => _chatManager.emoteStream;

  String? get playerId => _multiplayerService.playerId;
  String? get clientId => _multiplayerService.clientId;
  bool get isConnected => _multiplayerService.isConnected;
  bool get isReady => _localPresence?['ready'] == true;
  int get serverTimeOffsetMs => _multiplayerService.serverTimeOffsetMs;

  bool isPlayerAfk(String playerId) => _afkPlayerIds.contains(playerId);

  // ═══════════════════════════════════════════════════════════════════════════
  // TOURNOI
  // ═══════════════════════════════════════════════════════════════════════════

  /// Nombre total de manches du tournoi (joueurs initiaux - 1)
  int get tournamentTotalRounds {
    if (_gameState == null) return 1;
    // Calcul basé sur le nombre de joueurs initial
    // En manche N, il reste (initialPlayers - N + 1) joueurs
    // Donc initialPlayers = players.length + tournamentRound - 1
    final initialPlayers =
        _gameState!.players.length + _gameState!.tournamentRound - 1;
    return initialPlayers - 1; // On élimine 1 joueur par manche jusqu'à 2
  }

  /// Manche actuelle du tournoi
  int get tournamentRound => _gameState?.tournamentRound ?? 1;

  /// Vérifie si c'est la dernière manche du tournoi
  bool get isTournamentFinalRound {
    if (_gameState?.gameMode != GameMode.tournament) return false;
    return tournamentRound >= tournamentTotalRounds ||
        _gameState!.players.length <= 2;
  }

  /// Vérifie si le joueur local est éliminé dans ce tournoi
  bool isLocalPlayerEliminated() {
    if (_gameState?.gameMode != GameMode.tournament) return false;
    final survivorIds = _getSurvivorIds();
    return playerId != null && !survivorIds.contains(playerId);
  }

  /// Récupère les IDs des joueurs éliminés à cette manche
  Set<String> getEliminatedPlayerIds() {
    if (_gameState?.gameMode != GameMode.tournament) return {};
    if (isTournamentFinalRound) {
      // En finale, tous sauf le gagnant sont "éliminés"
      final ranking = _gameState!.getFinalRanking();
      return ranking.skip(1).map((p) => p.id).toSet();
    }
    final survivorIds = _getSurvivorIds();
    return _gameState!.players
        .where((p) => !survivorIds.contains(p.id))
        .map((p) => p.id)
        .toSet();
  }

  /// Récupère les IDs des survivants (tous sauf le dernier du classement)
  Set<String> _getSurvivorIds() {
    if (_gameState == null) return {};
    final ranking = _gameState!.getFinalRanking();
    final keepCount = (ranking.length - 1).clamp(1, ranking.length);
    return ranking.take(keepCount).map((p) => p.id).toSet();
  }

  /// Vérifie si le tournoi est terminé (finale jouée ou joueur local éliminé)
  bool get isTournamentOver {
    if (_gameState?.gameMode != GameMode.tournament) return false;
    return isTournamentFinalRound || isLocalPlayerEliminated();
  }

  int get readyHumanCount => _playersInLobby.where((p) {
        if (p['isHuman'] != true) return false;
        if (p['isSpectator'] == true) return false;
        if (p['connected'] == false) return false;
        return p['ready'] == true;
      }).length;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Appelé quand l'ami nous a ajouté automatiquement à un salon.
  /// La UI peut s'abonner pour rafraîchir "Mes salons".
  Function(String roomCode)? onRoomAutoJoined;

  // Wizz state
  DateTime? _lastWizzSentAt;
  bool get canSendWizz =>
      _lastWizzSentAt == null ||
      DateTime.now().difference(_lastWizzSentAt!).inSeconds >= 30;
  int get wizzCooldownRemaining {
    if (_lastWizzSentAt == null) return 0;
    final elapsed = DateTime.now().difference(_lastWizzSentAt!).inSeconds;
    return (30 - elapsed).clamp(0, 30);
  }

  String? _wizzFromName;
  String? get wizzFromName => _wizzFromName;
  bool _showWizzAnimation = false;
  bool get showWizzAnimation => _showWizzAnimation;

  void dismissWizzAnimation() {
    _showWizzAnimation = false;
    _wizzFromName = null;
    notifyListeners();
  }

  Future<bool> sendWizz(String targetClientId) async {
    if (!canSendWizz) return false;
    final success = await _multiplayerService.sendWizz(targetClientId);
    if (success) {
      _lastWizzSentAt = DateTime.now();
      notifyListeners();
    }
    return success;
  }

  String? _lastPlayerName;
  void setPlayerName(String name) => _lastPlayerName = name;

  MultiplayerGameProvider({
    MultiplayerService? multiplayerService,
    required IHapticService hapticService,
  })  : _multiplayerService = multiplayerService ?? MultiplayerService(),
        _hapticService = hapticService {
    WidgetsBinding.instance.addObserver(this);

    _notificationManager =
        MultiplayerNotificationManager(notifyListeners: notifyListeners);
    _timerManager = MultiplayerTimerManager(
      notifyListeners: notifyListeners,
      getLatencyMs: () => _multiplayerService.latencyMs,
      getServerNowMs: () => _multiplayerService.serverNowMs,
    );
    _chatManager = MultiplayerChatManager(notifyListeners: notifyListeners);
    _connectionManager = MultiplayerConnectionManager(
      multiplayerService: _multiplayerService,
      notifyListeners: notifyListeners,
      onReconnectToRoom: (roomCode, playerName) async {
        await _multiplayerService.joinRoom(
            roomCode: roomCode, playerName: playerName);
      },
    );

    _setupListeners();
  }

  /// Setter pour le token d'authentification JWT
  void setAuthToken(String? token) {
    _multiplayerService.setAuthToken(token);
  }

  /// Initialize the provider - call this in initState() of multiplayer screens
  /// This performs async operations that shouldn't be in the constructor
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    // Les salons sont chargés via la source active serveur (Firestore).
  }

  /// Lancer la connexion Socket.IO en avance (appelé dès le login).
  Future<void> connectEarly() => _multiplayerService.connect();

  Map<String, dynamic>? get _localPresence {
    final cid = _multiplayerService.clientId;
    if (cid != null) {
      final byClient = _presenceByClientId[cid];
      if (byClient != null) return byClient;
    }
    final pid = _multiplayerService.playerId;
    if (pid != null) return _presenceById[pid];
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LISTENERS SETUP
  // ═══════════════════════════════════════════════════════════════════════════

  void _setupListeners() {
    _multiplayerService.onGameStateUpdate = _handleGameStateUpdate;
    _multiplayerService.onPreloadedDeckCardUpdate = (card) {
      _preloadedDeckCard = card;
    };
    _multiplayerService.onTimerUpdate = (remaining) {
      if (_gameState != null) {
        _timerManager.applyServerUpdate(remaining, _gameState);
      }
    };
    _multiplayerService.onGameAllReady = (data) {
      _eventController.add(GameEvent(
          GameEventType.gameStarted, data['message'] ?? 'Le jeu commence !'));
    };
    _multiplayerService.onPlayerJoined = _handlePlayerJoined;
    _multiplayerService.onGameStarted = (message) {
      _isInLobby = false;
      _isPlaying = true;
      notifyListeners();
    };
    _multiplayerService.onReactionTimeConfig = (ms) {
      _timerManager.setReactionTimeMs(ms);
      _timerManager.syncReactionPhase(_gameState);
    };
    _multiplayerService.onPresenceUpdate = _handlePresenceUpdate;
    _multiplayerService.onPresenceCheck = (data) {
      _presenceCheckActive = true;
      _presenceCheckReason = data['reason']?.toString();
      _presenceCheckDeadlineMs =
          data['deadlineMs'] is int ? data['deadlineMs'] as int : 5000;
      notifyListeners();
    };
    _multiplayerService.onChatMessage = _chatManager.handleChatMessage;
    _multiplayerService.onError = (error) {
      _notificationManager.setError(error);
      _connectionManager.setConnecting(false);
    };
    _multiplayerService.onSocketConnectionStateChanged = (state) {
      _connectionManager.handleConnectionStateChanged(
        state,
        connectionState,
        _roomCode,
        _playersInLobby,
        playerId,
      );
    };
    _multiplayerService.onRoomClosed = _notificationManager.handleRoomClosed;
    _multiplayerService.onRoomRestarted = (data) {
      _gameState = null;
      _isPlaying = false;
      _isInLobby = true;
      _isPaused = false;
      _pausedByName = null;
      _pausedByPlayerId = null;
      _pauseDeadlineMs = 0;
      _preloadedDeckCard = null;
      _afkPlayerIds.clear();
      _timerManager.reset();
      for (final player in _playersInLobby) {
        player['ready'] = false;
      }
      // Update cumulative scores from restart data
      if (data['cumulativeScores'] is List) {
        _cumulativeScores = (data['cumulativeScores'] as List)
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
      }
      notifyListeners();
    };
    _multiplayerService.onKicked = (data) {
      _notificationManager.handleKicked(data);
      // Ne pas appeler _resetRoomState() ici - le dialog de kick naviguera vers /multiplayer
      // et le state sera reset lors de la prochaine connexion à une room
    };
    _multiplayerService.onBanned = (data) {
      _notificationManager.handleBanned(data);
      // Ne pas appeler _resetRoomState() ici - le dialog de ban naviguera vers /multiplayer
      // et le state sera reset lors de la prochaine connexion à une room
    };
    _multiplayerService.onPlayerLeft = _notificationManager.handlePlayerLeft;
    _multiplayerService.onPlayerAfk = (data) {
      final playerId = data['playerId']?.toString();
      if (playerId != null) _afkPlayerIds.add(playerId);
      _notificationManager.handlePlayerAfk(data);
    };
    _multiplayerService.onSpecialPowerTargeted =
        _notificationManager.handleSpecialPowerTargeted;
    _multiplayerService.onSpecialPowerTargetSelection = (data) {
      _pendingValetPlayer1 = data['player1Index'] as int?;
      _pendingValetCard1 = data['card1Index'] as int?;
      _pendingValetPlayer2 = data['player2Index'] as int?;
      _pendingValetCard2 = data['card2Index'] as int?;
      // Mettre à jour les indices pour le highlight des mains ciblées
      _powerTargetPlayerIndices = {
        if (_pendingValetPlayer1 != null) _pendingValetPlayer1!,
        if (_pendingValetPlayer2 != null) _pendingValetPlayer2!,
      };
      notifyListeners();
    };
    _multiplayerService.onSpiedCard = (card, targetName) {
      _lastSpiedCard = card;
      _spiedTargetName = targetName;
      _showSpiedCardDialog = true;
      notifyListeners();
    };
    _multiplayerService.onSwapNotification =
        _notificationManager.handleSwapNotification;
    _multiplayerService.onJokerNotification =
        _notificationManager.handleJokerNotification;
    _multiplayerService.onSpyNotification =
        _notificationManager.handleSpyNotification;
    _multiplayerService.onGamePaused = (pausedBy, pausedByPid, deadline) {
      _isPaused = true;
      _pausedByName = pausedBy;
      _pausedByPlayerId = pausedByPid;
      _pauseDeadlineMs = deadline;
      notifyListeners();
    };
    _multiplayerService.onGameResumed = (resumedBy) {
      _isPaused = false;
      _pausedByName = null;
      _pausedByPlayerId = null;
      _pauseDeadlineMs = 0;
      notifyListeners();
    };
    _multiplayerService.onPauseWarning = (pausedBy, secondsRemaining) {
      _eventController.add(GameEvent(
        GameEventType.info,
        '⚠️ $pausedBy sera expulsé dans $secondsRemaining secondes s\'il ne lève pas la pause.',
      ));
      notifyListeners();
    };
    _multiplayerService.onEmoteReceived = _handleEmoteReceived;
    _multiplayerService.onTournamentEliminated = _handleTournamentEliminated;
    _multiplayerService.onTournamentEnded = _handleTournamentEnded;
    _multiplayerService.onDuplicateLoginAttempt = (_) {
      _eventController.add(GameEvent(
        GameEventType.info,
        'Tentative de connexion détectée sur ce salon depuis un autre appareil.',
      ));
    };
    _multiplayerService.onRoomInviteReceived = (roomCode, fromDisplayName) {
      _handleAutoJoinFromInvite(roomCode);
    };
    _multiplayerService.onFriendRequestReceived = (data) {
      // Filet de sécurité : ne jamais notifier l'expéditeur (le serveur
      // ne devrait pas le faire, mais on s'en assure côté client).
      final fromUserId = data['fromUserId'] as String?;
      if (fromUserId != null && fromUserId == _myAuthUid) return;
      final currentLoc = AppRouter.currentLocation ?? '';
      if (currentLoc.startsWith('/friends')) return;
      final fromName = data['fromDisplayName'] as String? ??
          data['fromUsername'] as String? ??
          'Quelqu\'un';
      InAppNotificationService.instance.show(InAppNotificationPayload(
        type: InAppNotificationType.friendRequest,
        title: 'Demande d\'ami',
        body: '$fromName veut être ton ami',
        route: '/friends?tab=1',
      ));
    };
    _multiplayerService.onFriendAccepted = (data) {
      // Filet de sécurité : ne pas notifier celui qui vient d'accepter.
      final fromUserId = data['userId'] as String?;
      if (fromUserId != null && fromUserId == _myAuthUid) return;
      final currentLoc = AppRouter.currentLocation ?? '';
      if (currentLoc.startsWith('/friends')) return;
      final name = data['displayName'] as String? ??
          data['username'] as String? ??
          'Un ami';
      InAppNotificationService.instance.show(InAppNotificationPayload(
        type: InAppNotificationType.friendAccepted,
        title: 'Ami accepté !',
        body: '$name est maintenant ton ami',
        route: '/friends',
      ));
    };
    _multiplayerService.onWizzReceived = (data) {
      // Filet de sécurité : si l'expéditeur c'est moi (clientId), ignorer.
      final fromId = data['fromId'] as String?;
      if (fromId != null && fromId == clientId) return;

      _wizzFromName = data['fromName'] as String? ?? 'Quelqu\'un';
      _showWizzAnimation = true;
      _hapticService.error();
      notifyListeners();

      // In-app notification si on n'est pas dans le lobby
      if (!_isInRoomScreen()) {
        InAppNotificationService.instance.show(InAppNotificationPayload(
          type: InAppNotificationType.wizz,
          title: 'On t\'attend !',
          body: '$_wizzFromName te rappelle dans le salon',
          route: '/lobby',
        ));
      }

      // Auto-dismiss après 2s
      Future.delayed(const Duration(seconds: 2), () {
        if (_showWizzAnimation) {
          _showWizzAnimation = false;
          _wizzFromName = null;
          notifyListeners();
        }
      });
    };
    _multiplayerService.onPrivateMessage = (data) {
      final senderId = data['senderId'] as String?;
      // Filet de sécurité : ne jamais notifier pour un message envoyé
      // par soi-même (cas multi-device).
      if (senderId != null && senderId == _myAuthUid) return;
      if (senderId != null &&
          senderId == InAppNotificationService.instance.activeChatFriendId) {
        return;
      }
      final senderName = data['senderName'] as String? ?? 'Message';
      final preview = data['preview'] as String? ?? '';
      InAppNotificationService.instance.show(InAppNotificationPayload(
        type: InAppNotificationType.privateMessage,
        title: senderName,
        body: preview,
        route: senderId != null ? '/friends/chat/$senderId' : null,
      ));
    };
  }

  Future<void> _handleAutoJoinFromInvite(String roomCode) async {
    // Ne pas rejoindre si on est déjà dans une partie en cours
    if (_isPlaying) return;
    // Ne pas rejoindre si on est déjà dans ce salon
    if (_roomCode?.toUpperCase() == roomCode.toUpperCase()) return;
    try {
      final name = _lastPlayerName ?? 'Joueur';
      await joinRoom(roomCode: roomCode, playerName: name);
      // Le joueur n'est pas dans le lobby → marquer comme non-focused
      // Le lobby initState() appellera setScreenFocused(true) quand il s'ouvrira
      setScreenFocused(false);
      onRoomAutoJoined?.call(roomCode);
    } catch (_) {
      // Silencieux — l'invitation peut échouer si la room est pleine, etc.
    }
  }

  void _handleEmoteReceived(Map<String, dynamic> data) {
    final emoji = data['emoji'] as String?;
    final playerName = data['playerName'] as String?;
    final senderId = data['playerId'] as String?;
    if (emoji == null || playerName == null) return;
    // Ne pas afficher l'emote si c'est nous qui l'avons envoyé (déjà affiché localement)
    if (senderId != null && senderId == playerId) return;
    _chatManager.addLocalEmote(emoji, playerName, senderId ?? '');
  }

  // État pour le tournoi
  bool _tournamentEliminated = false;
  String? _tournamentEliminatedMessage;
  bool _tournamentEnded = false;
  String? _tournamentWinner;

  bool get tournamentEliminated => _tournamentEliminated;
  String? get tournamentEliminatedMessage => _tournamentEliminatedMessage;
  bool get tournamentEnded => _tournamentEnded;
  String? get tournamentWinner => _tournamentWinner;

  void _handleTournamentEliminated(Map<String, dynamic> data) {
    _tournamentEliminated = true;
    _tournamentEliminatedMessage =
        data['message']?.toString() ?? 'Vous avez été éliminé du tournoi !';
    notifyListeners();
  }

  void _handleTournamentEnded(Map<String, dynamic> data) {
    _tournamentEnded = true;
    _tournamentWinner = data['winner']?.toString();
    notifyListeners();
  }

  void acknowledgeTournamentEliminated() {
    _tournamentEliminated = false;
    _tournamentEliminatedMessage = null;
    notifyListeners();
  }

  void acknowledgeTournamentEnded() {
    _tournamentEnded = false;
    _tournamentWinner = null;
  }

  void _handleGameStateUpdate(GameState gameState) {
    final wasMyTurn = _gameState != null &&
        _gameState!.currentPlayerIndex >= 0 &&
        _gameState!.currentPlayerIndex < _gameState!.players.length &&
        _gameState!.players[_gameState!.currentPlayerIndex].id == playerId;
    final isNowMyTurn = gameState.currentPlayerIndex >= 0 &&
        gameState.currentPlayerIndex < gameState.players.length &&
        gameState.players[gameState.currentPlayerIndex].id == playerId &&
        (gameState.phase == GamePhase.playing ||
            gameState.phase == GamePhase.specialPower);
    if (!wasMyTurn && isNowMyTurn) {
      _hapticService.importantAction();
      // Notification in-app si le joueur n'est pas sur l'écran de jeu
      if (!_isInRoomScreen()) {
        InAppNotificationService.instance.show(InAppNotificationPayload(
          type: InAppNotificationType.yourTurn,
          title: 'C\'est ton tour !',
          body: 'Reviens vite jouer ta carte',
          route: '/multiplayer/game',
        ));
      }
    }

    // Ajuster specialPowerStartTime avec l'offset serveur (même correction que turnStartTime)
    if (gameState.specialPowerStartTime != null) {
      gameState.specialPowerStartTime =
          gameState.specialPowerStartTime! - serverTimeOffsetMs;
    }

    // Fallback : si le serveur ne fournit pas turnStartTime en phase playing,
    // l'initialiser côté client pour que la progress bar du turn timer s'affiche
    if ((gameState.phase == GamePhase.playing ||
            gameState.phase == GamePhase.specialPower) &&
        gameState.turnStartTime == null) {
      gameState.turnStartTime =
          DateTime.now().millisecondsSinceEpoch + serverTimeOffsetMs;
    }

    _gameState = gameState;
    _hasOptimisticDrawnCard = false;

    // Clear pending valet selection when state updates natively
    _pendingValetPlayer1 = null;
    _pendingValetCard1 = null;
    _pendingValetPlayer2 = null;
    _pendingValetCard2 = null;
    _powerTargetPlayerIndices = {};

    // Reset le flag de processing quand on reçoit une mise à jour du serveur
    // Cela évite les blocages si une action n'a pas été confirmée
    if (_isProcessingAction) {
      _isProcessingAction = false;
    }

    final me = gameState.players.where((p) => p.id == playerId).firstOrNull;

    if (me != null && !me.isSpectator) {
      _isPlaying = true;
      _isInLobby = false;
    } else if (gameState.phase == GamePhase.ended && me != null) {
      // Spectator (forfeited player) should still see results when game ends
      _isPlaying = true;
      _isInLobby = false;
    } else if (me == null) {
      // Joueur éliminé d'un tournoi: il reste dans la room
      // mais ne fait pas partie de la manche suivante.
      _isPlaying = false;
      _isInLobby = _roomCode != null;
    }

    _timerManager.syncReactionPhase(_gameState);
    notifyListeners();
  }

  void _handlePlayerJoined(Map<String, dynamic> data) {
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

    // Détecte "c'est moi" via plusieurs identifiants pour résister aux
    // courses possibles (playerId/clientId pas encore résolus) :
    //  - id socket courant
    //  - clientId stable persisté
    //  - userId Firebase éventuellement présent dans la payload
    final myUid = _myAuthUid;
    final playerUserId = player['userId'] as String?;
    bool isMe = player['id'] == playerId || player['clientId'] == this.clientId;
    if (!isMe && myUid != null && playerUserId == myUid) {
      isMe = true;
    }
    // Filet final : si je viens d'arriver dans une lobby qui ne contient
    // que ce joueur, c'est forcément moi (création de salon).
    if (!isMe && _playersInLobby.length == 1) {
      isMe = true;
    }

    final inGameContext = _isInRoomScreen();

    if (isMe) {
      // Si c'est moi l'hôte, pas de notif (je me suis ajouté moi-même).
      // Filet de sécurité contre la course entre l'ack `createRoom` et
      // l'event `room:player_joined` : si je suis le seul joueur du lobby
      // à cet instant, c'est que je viens de créer la salle.
      final isRoomCreator = _playersInLobby.length == 1;
      if (!isHost && !isRoomCreator) {
        final hostInfo =
            _playersInLobby.where((p) => p['id'] == _hostPlayerId).firstOrNull;
        final hostName = hostInfo?['name'] as String? ?? 'L\'hôte';
        _eventController.add(GameEvent(
            GameEventType.playerJoined, '$hostName vous a ajouté à la partie'));

        if (!inGameContext) {
          InAppNotificationService.instance.show(InAppNotificationPayload(
            type: InAppNotificationType.playerJoined,
            title: 'Invitation',
            body: '$hostName vous a ajouté au salon',
            route: '/lobby',
          ));
        }
      }
    } else {
      _eventController.add(GameEvent(
          GameEventType.playerJoined, "${player['name']} a rejoint la partie"));

      if (!inGameContext) {
        final playerName = player['name'] as String? ?? 'Un joueur';
        InAppNotificationService.instance.show(InAppNotificationPayload(
          type: InAppNotificationType.playerJoined,
          title: 'Joueur rejoint',
          body: '$playerName a rejoint le salon',
          route: '/lobby',
        ));
      }
    }
  }

  void _handlePresenceUpdate(Map<String, dynamic> data) {
    final hostId = data['hostPlayerId'];
    if (hostId is String) _hostPlayerId = hostId;

    final players = data['players'];
    if (players is List) {
      _playersInLobby = players
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList()
        ..sort((a, b) => ((a['position'] as num?)?.toInt() ?? 0)
            .compareTo((b['position'] as num?)?.toInt() ?? 0));
    }

    final byId = <String, Map<String, dynamic>>{};
    final byClient = <String, Map<String, dynamic>>{};
    for (final entry in (players is List ? players : const [])) {
      if (entry is Map) {
        final map = entry.cast<String, dynamic>();
        if (map['id'] is String) byId[map['id']] = map;
        if (map['clientId'] is String) byClient[map['clientId']] = map;
      }
    }
    _presenceById = byId;
    _presenceByClientId = byClient;

    // Detect if we've been removed from the room
    final myPid = playerId;
    final myCid = clientId;
    final stillInRoom = _playersInLobby.any((p) =>
        (myPid != null && p['id'] == myPid) ||
        (myCid != null && p['clientId'] == myCid));
    if (!stillInRoom && _roomCode != null) {
      // We're no longer in the player list — we were removed (or list is empty)
      _resetRoomState();
      return;
    }

    if (data['gameMode'] is int) {
      final modeIndex = data['gameMode'] as int;
      if (modeIndex >= 0 && modeIndex < GameMode.values.length) {
        _roomGameMode = GameMode.values[modeIndex];
      }
    }

    // Detect room status transitions
    final newStatus = data['status'] as String?;
    if (newStatus != null) {
      _roomStatus = newStatus;
    }

    if (data['cumulativeScores'] is List) {
      _cumulativeScores = (data['cumulativeScores'] as List)
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();

      // Trier les joueurs dans le lobby en fonction du score
      _playersInLobby.sort((a, b) {
        final scoreA = _getScoreForPlayer(a['clientId']);
        final scoreB = _getScoreForPlayer(b['clientId']);
        return scoreB.compareTo(scoreA); // Descendant
      });
    }
    notifyListeners();
  }

  int _getScoreForPlayer(String? clientId) {
    if (clientId == null || _cumulativeScores.isEmpty) return 0;
    for (final entry in _cumulativeScores) {
      if (entry['clientId'] == clientId) {
        return entry['score'] as int? ?? 0;
      }
    }
    return 0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ROOM MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> createRoom(
      {required GameSettings settings, required String playerName}) async {
    try {
      _connectionManager.setConnecting(true);
      _notificationManager.clearError();
      _timerManager.setReactionTimeMs(settings.reactionTimeMs);

      _roomCode = await _multiplayerService.createRoom(
          settings: settings, playerName: playerName);

      if (_roomCode != null) {
        _hostPlayerId = _multiplayerService.playerId;
        _isInLobby = true;
        _roomSettings = settings;
        _playersInLobby = [
          {
            'id': playerId,
            'clientId': clientId,
            'name': playerName,
            'isHuman': true,
            'ready': false
          }
        ];
        _multiplayerService.setFocused(true);
        WebSessionStorage.saveSession(_roomCode!);
      }
      _connectionManager.setConnecting(false);
    } catch (e) {
      _notificationManager.setError(e.toString());
      _connectionManager.setConnecting(false);
      rethrow;
    }
  }

  Future<void> createPublicRoom(
      {String playerName = 'Joueur', String? roomName}) async {
    await createRoom(
      settings: GameSettings(
          gameMode: GameMode.quick,
          numberOfPlayers: 4,
          isPublic: true,
          minPlayers: 2,
          maxPlayers: 6,
          roomName: roomName),
      playerName: playerName,
    );
  }

  Future<void> searchAndJoinPublicRoom({String playerName = 'Joueur'}) async {
    try {
      _connectionManager.setConnecting(true);
      _notificationManager.clearError();

      final publicRooms = await _multiplayerService.getPublicRooms();
      if (publicRooms != null && publicRooms.isNotEmpty) {
        await joinRoom(
            roomCode: publicRooms.first['code'] as String,
            playerName: playerName);
      } else {
        throw Exception('Aucune partie publique disponible');
      }
      _connectionManager.setConnecting(false);
    } catch (e) {
      _notificationManager.setError(e.toString());
      _connectionManager.setConnecting(false);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>?> getPublicRooms() async {
    try {
      return await _multiplayerService.getPublicRooms();
    } catch (_) {
      return null;
    }
  }

  Future<void> joinRoom(
      {required String roomCode, required String playerName}) async {
    try {
      _connectionManager.setConnecting(true);
      _notificationManager.clearError();
      _lastPlayerName = playerName;

      final room = await _multiplayerService.joinRoom(
          roomCode: roomCode, playerName: playerName);

      _roomCode = roomCode;
      _isInLobby = true;
      if (room != null && room['players'] is List) {
        _playersInLobby = (room['players'] as List)
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        if (room['hostPlayerId'] is String) {
          _hostPlayerId = room['hostPlayerId'];
        }
        if (room['settings'] is Map<String, dynamic>) {
          _roomSettings = GameSettings.fromJson(room['settings']);
        }
      } else {
        _playersInLobby = [
          {
            'id': playerId,
            'clientId': clientId,
            'name': playerName,
            'isHuman': true,
            'ready': false
          }
        ];
      }
      _multiplayerService.setFocused(true);
      WebSessionStorage.saveSession(roomCode);
      _connectionManager.setConnecting(false);
    } catch (e) {
      _notificationManager.setError(e.toString());
      _connectionManager.setConnecting(false);
      rethrow;
    }
  }

  Future<void> startGame(
      {bool fillBots = false,
      int? numberOfBots,
      bool? useSBMM,
      int? botDifficulty}) async {
    if (!isHost) {
      _notificationManager.setError("Seul l'hôte peut démarrer");
      return;
    }
    if (!isReady) {
      _notificationManager.setError("Vous devez être prêt");
      return;
    }
    final minPlayers = _roomSettings?.minPlayers ?? 2;
    if (readyHumanCount < minPlayers) {
      _notificationManager.setError("Minimum $minPlayers joueurs prêts requis");
      return;
    }

    try {
      _notificationManager.clearError();
      final success = await _multiplayerService.startGame(
          fillBots: fillBots,
          numberOfBots: numberOfBots,
          useSBMM: useSBMM,
          botDifficulty: botDifficulty);
      if (!success) _notificationManager.setError("Erreur lors du démarrage");
    } catch (e) {
      _notificationManager.setError(e.toString());
    }
  }

  Future<void> leaveRoom() async {
    if (isHost) {
      await closeRoom();
    } else {
      _multiplayerService.leaveRoom();
    }
    _resetRoomState();
  }

  void triggerPowerTimeoutKick() {
    final isForeground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _multiplayerService.sendPresenceTimeoutKick(isForeground);
  }

  Future<bool> closeRoom() async {
    if (!isHost) return false;
    final success = await _multiplayerService.closeRoom();
    if (success) _resetRoomState();
    return success;
  }

  Future<bool> becomeHost() async {
    if (_notificationManager.closedRoomCode == null) return false;
    final success = await _multiplayerService
        .becomeHost(_notificationManager.closedRoomCode!);
    if (success) {
      _roomCode = _notificationManager.closedRoomCode;
      _hostPlayerId = playerId; // Set so computed isHost returns true
      _isInLobby = true;
      _notificationManager.clearRoomClosedAfterBecomeHost();
      notifyListeners();
    }
    return success;
  }

  /// En tournoi, n'importe quel survivant peut lancer la manche suivante.
  /// En partie rapide, seul l'hôte peut relancer.
  Future<bool> restartGame() async =>
      (roomGameMode == GameMode.tournament || isHost)
          ? await _multiplayerService.restartGame()
          : false;

  /// Retour indépendant au salon depuis l'écran de résultats (tout joueur)
  void returnToLobbyFromResults() {
    _multiplayerService.backToLobby();
    _gameState = null;
    _isPlaying = false;
    _isInLobby = true;
    _isPaused = false;
    _pausedByName = null;
    _pausedByPlayerId = null;
    _pauseDeadlineMs = 0;
    _preloadedDeckCard = null;
    _pendingValetPlayer1 = null;
    _pendingValetCard1 = null;
    _pendingValetPlayer2 = null;
    _pendingValetCard2 = null;
    _powerTargetPlayerIndices = {};
    _isProcessingAction = false;
    _lastSpiedCard = null;
    _spiedTargetName = null;
    _showSpiedCardDialog = false;
    _afkPlayerIds.clear();
    _timerManager.reset();
    for (final player in _playersInLobby) {
      player['ready'] = false;
    }
    notifyListeners();
  }

  /// Clean return to lobby for non-host players from the results screen.
  /// Leaves the room and resets state so the player navigates to /multiplayer.
  void leaveAfterResults() {
    _multiplayerService.leaveRoom();
    _resetRoomState();
  }

  Future<bool> kickPlayer(String clientId) async =>
      isHost ? await _multiplayerService.kickPlayer(clientId) : false;
  Future<bool> banPlayer(String clientId) async =>
      isHost ? await _multiplayerService.banPlayer(clientId) : false;

  Future<bool> setGameMode(GameMode mode) async {
    if (!isHost) return false;
    final success = await _multiplayerService.setGameMode(mode.index);
    if (success && _roomSettings != null) {
      _roomSettings = GameSettings(
          gameMode: mode,
          botDifficulty: _roomSettings!.botDifficulty,
          luckDifficulty: _roomSettings!.luckDifficulty,
          reactionTimeMs: _roomSettings!.reactionTimeMs,
          minPlayers: _roomSettings!.minPlayers,
          maxPlayers: _roomSettings!.maxPlayers);
      notifyListeners();
    }
    return success;
  }

  Future<bool> updateRoomSettings(
      {Difficulty? botDifficulty, Difficulty? luckDifficulty}) async {
    if (!isHost) return false;
    final success = await _multiplayerService.updateRoomSettings(
        botDifficulty: botDifficulty?.index,
        luckDifficulty: luckDifficulty?.index);
    if (success && _roomSettings != null) {
      _roomSettings = GameSettings(
          gameMode: _roomSettings!.gameMode,
          botDifficulty: botDifficulty ?? _roomSettings!.botDifficulty,
          luckDifficulty: luckDifficulty ?? _roomSettings!.luckDifficulty,
          reactionTimeMs: _roomSettings!.reactionTimeMs,
          minPlayers: _roomSettings!.minPlayers,
          maxPlayers: _roomSettings!.maxPlayers);
      notifyListeners();
    }
    return success;
  }

  void requestFullState() => _multiplayerService.requestFullState();

  // ═══════════════════════════════════════════════════════════════════════════
  // GAME ACTIONS (IGameController)
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void drawCard() {
    if (_gameState == null) return;

    _hapticService.cardTap();

    // Optimisation: Utiliser la carte préchargée pour affichage instantané
    // Le serveur confirmera la vraie carte mais l'affichage est immédiat
    if (_preloadedDeckCard != null && _gameState!.drawnCard == null) {
      _gameState!.drawnCard = _preloadedDeckCard;
      _hasOptimisticDrawnCard = true;
      _preloadedDeckCard = null; // Consommer la carte préchargée
      notifyListeners(); // Afficher immédiatement
    }

    _trackActionAck('Pioche', _multiplayerService.drawCard());
  }

  void _trackActionAck(String actionLabel, Future<bool> actionResult) {
    unawaited(_handleActionAck(actionLabel, actionResult));
  }

  Future<void> _handleActionAck(
      String actionLabel, Future<bool> actionResult) async {
    final success = await actionResult;
    if (_isDisposed) return;
    if (success) return;

    if (actionLabel == 'Pioche' && _hasOptimisticDrawnCard) {
      _gameState?.drawnCard = null;
      _hasOptimisticDrawnCard = false;
      notifyListeners();
    }

    _hapticService.error();
    _notificationManager.setError(
      '$actionLabel non confirmé par le serveur. Resynchronisation en cours.',
    );
    _multiplayerService.requestFullState();
  }

  @override
  void replaceCard(int cardIndex) {
    if (_gameState != null) {
      _hapticService.cardTap();
      _trackActionAck(
        'Remplacement',
        _multiplayerService.replaceCard(cardIndex),
      );
    }
  }

  @override
  void discardDrawnCard() {
    if (_gameState != null) {
      _hapticService.cardTap();
      _trackActionAck('Défausse', _multiplayerService.discardDrawnCard());
    }
  }

  @override
  void callDutch() {
    if (_gameState != null) {
      _hapticService.importantAction();
      _trackActionAck('Dutch', _multiplayerService.callDutch());
    }
  }

  @override
  void attemptMatch(int cardIndex) async {
    if (_gameState == null || _gameState!.phase != GamePhase.reaction) return;

    final pid = playerId;
    if (pid == null) return;

    final me = _gameState!.players.where((p) => p.id == pid).firstOrNull;
    if (me == null) return;
    if (cardIndex < 0 || cardIndex >= me.hand.length) return;

    // Vérification locale pour le feedback visuel (shake si match raté)
    final playerCard = me.hand[cardIndex];
    final topDiscard = _gameState!.discardPile.isNotEmpty
        ? _gameState!.discardPile.last
        : null;
    final willSucceed = topDiscard != null && playerCard.matches(topDiscard);

    // Envoyer au serveur (source de vérité)
    _trackActionAck('Match', _multiplayerService.attemptMatch(cardIndex));

    // Feedback visuel local immédiat
    if (!willSucceed) {
      _hapticService.error();
      shakingCardIndices.add(cardIndex);
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 500));
      if (_isDisposed) return;
      shakingCardIndices.remove(cardIndex);
      notifyListeners();
    } else {
      _hapticService.cardTap();
    }
  }

  @override
  void skipSpecialPower() => _executeWithProcessingLock(() {
        _hapticService.buttonTap();
        _trackActionAck(
            'Pouvoir ignoré', _multiplayerService.skipSpecialPower());
      });

  @override
  void handleCardTap(int cardIndex) {
    if (_gameState == null) return;
    final pid = playerId;
    if (pid == null) return;
    Player? me;
    try {
      me = _gameState!.players.firstWhere((p) => p.id == pid);
    } catch (_) {
      return;
    }
    if (me.isSpectator) return;
    final isLocalTurn = _gameState!.currentPlayer.id == pid;

    if (_gameState!.phase == GamePhase.reaction) {
      attemptMatch(cardIndex);
    } else if (_gameState!.phase == GamePhase.playing &&
        isLocalTurn &&
        _gameState!.drawnCard != null) {
      replaceCard(cardIndex);
    }
  }

  void usePower7LookOwnCard(int cardIndex) => _executeWithProcessingLock(() {
        _hapticService.cardTap();
        _trackActionAck(
          'Pouvoir 7',
          _multiplayerService.usePower7LookOwnCard(cardIndex),
        );
      });
  void usePower10SpyOpponent(int targetPlayerIndex, int targetCardIndex) =>
      _executeWithProcessingLock(() {
        _hapticService.cardTap();
        _trackActionAck(
          'Pouvoir 10',
          _multiplayerService.usePower10SpyOpponent(
              targetPlayerIndex, targetCardIndex),
        );
      });
  void usePowerValetSwap(int p1, int c1, int p2, int c2) =>
      _executeWithProcessingLock(() {
        _hapticService.importantAction();
        _trackActionAck(
          'Pouvoir Valet',
          _multiplayerService.usePowerValetSwap(p1, c1, p2, c2),
        );
      });
  void usePowerJokerShuffle(int targetPlayerIndex) =>
      _executeWithProcessingLock(() {
        _hapticService.importantAction();
        _trackActionAck(
          'Pouvoir Joker',
          _multiplayerService.usePowerJokerShuffle(targetPlayerIndex),
        );
      });

  void sendSpecialPowerTargetSelection(int? p1, int? c1, int? p2, int? c2) =>
      _multiplayerService.sendSpecialPowerTargetSelection(p1, c1, p2, c2);

  void _executeWithProcessingLock(void Function() action) {
    if (_gameState == null || _isProcessingAction) return;
    _isProcessingAction = true;
    notifyListeners();
    action();
    Future.delayed(const Duration(seconds: 2), () {
      if (_isProcessingAction) {
        _isProcessingAction = false;
        notifyListeners();
      }
    });
  }

  void pauseGame() =>
      _multiplayerService.socket?.emit('game:pause', {'roomCode': _roomCode});
  void resumeGame() =>
      _multiplayerService.socket?.emit('game:resume', {'roomCode': _roomCode});

  // ═══════════════════════════════════════════════════════════════════════════
  // NOTIFICATIONS & DIALOGS
  // ═══════════════════════════════════════════════════════════════════════════

  void clearSwapNotification() => _notificationManager.clearSwapNotification();
  void clearJokerNotification() =>
      _notificationManager.clearJokerNotification();
  void clearSpyNotification() => _notificationManager.clearSpyNotification();
  void acknowledgeRoomClosed() {
    _notificationManager.acknowledgeRoomClosed();
    _resetRoomState();
  }

  void acknowledgeKicked() {
    _notificationManager.acknowledgeKicked();
    _resetRoomState();
  }

  void acknowledgeBanned() {
    _notificationManager.acknowledgeBanned();
    _resetRoomState();
  }

  void clearError() {
    _notificationManager.clearError();
    _connectionManager.clearError();
  }

  void closeSpiedCardDialog() {
    _showSpiedCardDialog = false;
    _lastSpiedCard = null;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRESENCE & READY
  // ═══════════════════════════════════════════════════════════════════════════

  void confirmPresence() {
    _multiplayerService.confirmPresence();
    _presenceCheckActive = false;
    _presenceCheckReason = null;
    _presenceCheckDeadlineMs = 0;
    notifyListeners();
  }

  void setReady(bool ready) {
    _multiplayerService.setReady(ready);
    final cid = clientId;
    final pid = playerId;
    for (final player in _playersInLobby) {
      if ((cid != null && player['clientId'] == cid) ||
          (pid != null && player['id'] == pid)) {
        player['ready'] = ready;
      }
    }
    notifyListeners();
  }

  void markReady() => _multiplayerService.markReady();

  /// Appelé par les écrans (lobby, game) pour signaler l'entrée/sortie de l'écran.
  /// Distinct du lifecycle handler qui gère le passage app → arrière-plan OS.
  void setScreenFocused(bool focused) {
    if (!isConnected || _roomCode == null) return;
    _multiplayerService.setFocused(focused);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHAT & EMOTES
  // ═══════════════════════════════════════════════════════════════════════════

  void sendChatMessage(String message) =>
      _multiplayerService.sendChatMessage(message);

  void sendEmote(String emoji) {
    final playerName = _playersInLobby.firstWhere((p) => p['id'] == playerId,
            orElse: () => {'name': 'Joueur'})['name'] as String? ??
        'Joueur';
    _multiplayerService.socket?.emit('game:emote',
        {'roomCode': _roomCode, 'emoji': emoji, 'playerName': playerName});
    _chatManager.addLocalEmote(emoji, playerName, playerId ?? '');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONNECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> reconnect() => _connectionManager.reconnect(
      _roomCode, _playersInLobby, playerId, (inLobby) => _isInLobby = inLobby);
  Future<bool> checkServerReachable() =>
      _connectionManager.checkServerReachable();

  // ═══════════════════════════════════════════════════════════════════════════
  // MISC
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> forfeitGame() async {
    _multiplayerService.cancelGame();
    // Don't set _isInLobby = true here!
    // The player stays as spectator in the game view.
    // When the game ends (GAME_ENDED), they'll see the results screen
    // and can return to lobby from there.
    notifyListeners();
  }

  void watchGame() {
    if (_gameState != null) {
      _isPlaying = true;
      _isInLobby = false;
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>?> getMyActiveRooms() =>
      _multiplayerService.getMyActiveRooms(clientId: clientId);
  Future<void> removeRoom(String roomCode) =>
      _multiplayerService.removeSavedRoom(roomCode);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final focused = state == AppLifecycleState.resumed;
    // Focus global : met à jour la pastille en ligne pour les amis, même hors room
    if (isConnected) {
      _multiplayerService.setUserFocused(focused);
    }
    // Focus room : met à jour la présence dans la partie en cours
    if (isConnected && _roomCode != null) {
      _multiplayerService.setFocused(focused);
    }
  }

  /// Vérifie si l'utilisateur est déjà dans un écran lié au salon
  /// (lobby, partie, rejoin...) — dans ce cas, pas besoin de notif in-app.
  static bool _isInRoomScreen() {
    final loc = AppRouter.currentLocation;
    if (loc == null) return false;
    return loc.startsWith('/lobby') ||
        loc.startsWith('/multiplayer/game') ||
        loc.startsWith('/multiplayer/memorization') ||
        loc.startsWith('/multiplayer/results') ||
        loc.startsWith('/multiplayer/dutch-reveal') ||
        loc.startsWith('/room/');
  }

  void _resetRoomState() {
    WebSessionStorage.clearSession();
    _roomCode = null;
    _hostPlayerId = null;
    _gameState = null;
    _isInLobby = false;
    _isPlaying = false;
    _playersInLobby = [];
    _roomSettings = null;
    _cumulativeScores = [];
    _roomGameMode = GameMode.quick;
    _roomStatus = 'waiting';
    _presenceById = {};
    _presenceByClientId = {};
    _presenceCheckActive = false;
    _presenceCheckReason = null;
    _presenceCheckDeadlineMs = 0;
    _afkPlayerIds.clear();
    _lastWizzSentAt = null;
    _showWizzAnimation = false;
    _wizzFromName = null;
    _chatManager.reset();
    _timerManager.reset();
    _notificationManager.reset();
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;

    // Nettoyer tous les callbacks pour éviter les leaks
    _multiplayerService.onGameStateUpdate = null;
    _multiplayerService.onPreloadedDeckCardUpdate = null;
    _multiplayerService.onTimerUpdate = null;
    _multiplayerService.onGameAllReady = null;
    _multiplayerService.onPlayerJoined = null;
    _multiplayerService.onGameStarted = null;
    _multiplayerService.onReactionTimeConfig = null;
    _multiplayerService.onPresenceUpdate = null;
    _multiplayerService.onPresenceCheck = null;
    _multiplayerService.onChatMessage = null;
    _multiplayerService.onError = null;
    _multiplayerService.onSocketConnectionStateChanged = null;
    _multiplayerService.onRoomClosed = null;
    _multiplayerService.onRoomRestarted = null;
    _multiplayerService.onKicked = null;
    _multiplayerService.onBanned = null;
    _multiplayerService.onPlayerLeft = null;
    _multiplayerService.onPlayerAfk = null;
    _multiplayerService.onSpecialPowerTargeted = null;
    _multiplayerService.onSpiedCard = null;
    _multiplayerService.onSwapNotification = null;
    _multiplayerService.onJokerNotification = null;
    _multiplayerService.onSpyNotification = null;
    _multiplayerService.onGamePaused = null;
    _multiplayerService.onGameResumed = null;
    _multiplayerService.onEmoteReceived = null;
    _multiplayerService.onTournamentEliminated = null;
    _multiplayerService.onTournamentEnded = null;
    _multiplayerService.onDuplicateLoginAttempt = null;
    _multiplayerService.onRoomInviteReceived = null;
    _multiplayerService.onFriendRequestReceived = null;
    _multiplayerService.onFriendAccepted = null;
    _multiplayerService.onPrivateMessage = null;
    _multiplayerService.onWizzReceived = null;

    _eventController.close();
    _connectionManager.dispose();
    _timerManager.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _multiplayerService.disconnect();
    super.dispose();
  }
}
