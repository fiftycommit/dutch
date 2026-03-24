import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playing_card.dart';
import '../models/player.dart';
import '../models/game_state.dart';
import '../models/game_sub_states.dart';
import '../models/game_settings.dart';
import '../utils/action_history_messages.dart';
import '../models/player_learning_data.dart';
import '../services/game/game_logic.dart';
import '../core/interfaces/i_haptic_service.dart';
import '../core/interfaces/i_stats_service.dart';
import '../services/ui/stats_service.dart';
import '../core/interfaces/i_bot_ai_service.dart';
import '../core/interfaces/i_game_controller.dart';
import '../services/game/bot/hardcore_bot_config.dart';
import '../services/game/bot/human_threat_tracker.dart';
import '../services/learning/bot_learning_service.dart';
import '../services/learning/ai_telemetry_service.dart';
import '../services/matchmaking/sbmm_client_service.dart';
import '../services/logging/game_logger_service.dart';
import '../services/network/network_probe_service.dart';
import 'game_tracking_provider.dart';
import 'managers/solo/tournament_manager.dart';
import 'managers/solo/reaction_timer_manager.dart';
import 'managers/solo/special_power_handler.dart';
import 'managers/solo/bot_orchestrator.dart';
import '../services/game/rp_calculator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

export 'managers/solo/tournament_manager.dart' show TournamentResult;
export '../services/game/bot/hardcore_bot_config.dart' show HardcoreLevel;

// Clé SharedPreferences pour détecter les abandons par fermeture d'app
const String _kActiveGameKey = 'active_tournament_game';

/// GameProvider refactoré - ~400 lignes au lieu de 1200
/// Principe SOLID: SRP - Coordination uniquement, logique déléguée aux managers
/// Principe GRASP: Controller - Point d'entrée pour les actions du jeu
/// Implements IGameController pour permettre l'UI unifiée
class GameProvider with ChangeNotifier implements IGameController {
  // État du jeu
  GameState? _gameState;
  @override
  GameState? get gameState => _gameState;
  @override
  bool get hasActiveGame => _gameState != null;

  BuildContext? _currentContext;
  @override
  bool isProcessing = false;
  String? statusMessage;
  @override
  Set<int> shakingCardIndices = {};

  bool _isPaused = false;
  @override
  bool get isPaused => _isPaused;

  @override
  Player? get localPlayer =>
      _gameState?.players.where((p) => p.isHuman).firstOrNull;

  @override
  bool get isLocalPlayerTurn => _gameState?.currentPlayer.isHuman ?? false;

  @override
  bool get canLocalPlayerAct =>
      _gameState != null &&
      isLocalPlayerTurn &&
      _gameState!.phase == GamePhase.playing;

  int _currentReactionTimeMs = 3000;
  @override
  int get currentReactionTimeMs => _currentReactionTimeMs;
  int _currentActionTextDisplayMs = 1500;
  int _currentSlotId = 1;
  bool _useSBMM = false;
  bool get useSBMM => _useSBMM;

  int? _playerMMR;
  int? get playerMMR => _playerMMR;
  int _playerWinStreak = 0;
  int get playerWinStreak => _playerWinStreak;
  RPResult? _lastMatchRpResult;
  RPResult? get lastMatchRpResult => _lastMatchRpResult;

  // Mode Hardcore
  HardcoreLevel? _hardcoreLevel;
  HardcoreLevel? get hardcoreLevel => _hardcoreLevel;
  final PlayerSkillEstimator _skillEstimator = PlayerSkillEstimator();
  int get playerSkillEstimate => _skillEstimator.estimatedSkill;

  // Flag ML hydration - bloque les bots jusqu'à ce que les params soient chargés
  bool _botsHydrated =
      true; // true par défaut (pas de bots = pas besoin d'attendre)

  // Services injectés (Principe SOLID: DIP)
  final IHapticService _hapticService;
  final IStatsService _statsService;
  final IBotAIService _botAIService;
  final GameTrackingProvider _trackingProvider;

  // Managers (Principe GRASP: Pure Fabrication)
  late final TournamentManager _tournamentManager;
  late final ReactionTimerManager _timerManager;
  late final SpecialPowerHandler _powerHandler;
  late final BotOrchestrator _botOrchestrator;

  // Délégation au TournamentManager
  List<TournamentResult>? get tournamentFinalRanking =>
      _tournamentManager.finalRanking;
  int get tournamentTotalRounds {
    if (_gameState == null) return 1;
    return _tournamentManager.getTotalRounds(_gameState!);
  }

  ValueNotifier<int> get reactionTimeRemaining =>
      _timerManager.reactionTimeRemaining;

  GameProvider({
    required IHapticService hapticService,
    required IStatsService statsService,
    required IBotAIService botAIService,
    required GameTrackingProvider trackingProvider,
  })  : _hapticService = hapticService,
        _statsService = statsService,
        _botAIService = botAIService,
        _trackingProvider = trackingProvider {
    _tournamentManager = TournamentManager();
    _timerManager = ReactionTimerManager(
      onTimerEnd: _endReactionPhase,
      onTimerUpdate: notifyListeners,
    );
    _powerHandler = SpecialPowerHandler(trackingProvider: _trackingProvider);
    _botOrchestrator = BotOrchestrator(botAIService: _botAIService);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CRÉATION ET GESTION DU JEU
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> createNewGame({
    required List<Player> players,
    required GameMode gameMode,
    required Difficulty difficulty,
    required int reactionTimeMs,
    int actionTextDisplayMs = 1500,
    int tournamentRound = 1,
    int saveSlot = 1,
    bool useSBMM = false,
    HardcoreLevel? hardcoreLevel,
  }) async {
    // Initialiser le tournoi via le manager
    if (gameMode == GameMode.tournament) {
      _tournamentManager.initializeTournament(tournamentRound,
          playerCount: players.length);
    } else {
      _tournamentManager.resetTournament();
    }

    _gameState = GameLogic.initializeGame(
        players: players,
        gameMode: gameMode,
        difficulty: difficulty,
        tournamentRound: tournamentRound);
    _gameState!.tournamentCumulativeScores =
        Map.from(_tournamentManager.cumulativeScores);

    _currentReactionTimeMs = reactionTimeMs;
    _currentActionTextDisplayMs = actionTextDisplayMs;
    _currentSlotId = saveSlot;
    _useSBMM = useSBMM;
    _lastMatchRpResult = null;

    // Mode hardcore
    _hardcoreLevel = hardcoreLevel;

    if (useSBMM || hardcoreLevel != null) {
      final stats = await _statsService.getStats(slotId: saveSlot);
      _playerMMR = stats['mmr'] ?? 0;
      _playerWinStreak = stats['winStreak'] ?? 0;

      // Initialiser l'estimateur de skill avec le MMR actuel
      _skillEstimator.reset(initialMMR: _playerMMR);
    } else {
      _playerMMR = null;
      _playerWinStreak = 0;
      _skillEstimator.reset(initialMMR: 1000);
    }

    for (var player in _gameState!.players.where((p) => !p.isHuman)) {
      player.initializeBotMemory();
    }

    // Hydrater les bots avec les paramètres ML appris
    // Le flag _botsHydrated bloque checkIfBotShouldPlay() jusqu'à completion
    _botsHydrated = false;
    _hydrateBotsWithLearnedParams();

    // Initialiser le tracking
    _trackingProvider.initTracking(_gameState!, useSBMM);

    // 🎯 HUMAN THREAT TRACKER : Réinitialiser pour cette nouvelle manche
    HumanThreatTracker().initializeRound(_gameState!);

    // ═══════════════════════════════════════════════════════════════════════
    // TÉLÉMÉTRIE AI : Démarrer la collecte
    // ═══════════════════════════════════════════════════════════════════════
    AiTelemetryService().startGame(playerCount: players.length);

    // ═══════════════════════════════════════════════════════════════════════
    // LOGGING : Démarrer l'enregistrement de la partie
    // ═══════════════════════════════════════════════════════════════════════
    if (tournamentRound <= 1) {
      GameLoggerService.instance.reset();
    }
    GameLoggerService.instance.startNewGame(
      players: players,
      targetScore: 100,
    );
    GameLoggerService.instance.logRoundStart(
      roundNumber: tournamentRound,
      players: players,
    );

    shakingCardIndices.clear();
    isProcessing = false;

    // Persister un flag "partie en cours" pour détecter les abandons par fermeture d'app
    _setActiveGameFlag(
      slotId: saveSlot,
      tournamentRound: tournamentRound,
      totalRounds: gameMode == GameMode.tournament ? tournamentTotalRounds : 1,
      totalPlayers: players.length,
      tournamentId: _tournamentManager.activeTournamentId,
      useSBMM: useSBMM,
      isTournament: gameMode == GameMode.tournament,
    );

    notifyListeners();
  }

  /// Récupère les paramètres appris du serveur ML et les injecte dans les bots.
  /// Cette opération est asynchrone et non-bloquante pour ne pas retarder le démarrage.
  Future<void> _hydrateBotsWithLearnedParams() async {
    if (_gameState == null) return;

    final bots = _gameState!.players.where((p) => !p.isHuman).toList();
    final botsToHydrate = bots
        .where((b) => (b.aiParameters == null || b.aiParameters!.isEmpty))
        .where((b) => b.botBehavior != null && b.botSkillLevel != null)
        .toList();

    if (botsToHydrate.isEmpty) {
      _botsHydrated = true;
      notifyListeners();
      checkIfBotShouldPlay();
      return;
    }

    // Offline-first: ACK + timeout court avant les requêtes ML
    final canReachBackend = await NetworkProbeService.canReachBackend(
      timeout: const Duration(milliseconds: 700),
    );
    if (!canReachBackend) {
      if (kDebugMode) {
        debugPrint(
            '⚠️ Offline détecté: hydratation ML ignorée (fallback local)');
      }
      _botsHydrated = true;
      notifyListeners();
      checkIfBotShouldPlay();
      return;
    }

    final botLearningService = BotLearningService();
    final uniqueKeys = <String>{};
    for (final bot in botsToHydrate) {
      final behavior = bot.botBehavior.toString().split('.').last;
      final skillLevel = bot.botSkillLevel.toString().split('.').last;
      uniqueKeys.add('$behavior|$skillLevel');
    }

    final paramTasks = <String, Future<Map<String, dynamic>?>>{};
    for (final key in uniqueKeys) {
      final parts = key.split('|');
      final behavior = parts[0];
      final skillLevel = parts[1];
      paramTasks[key] = botLearningService.fetchBotParameters(
        behavior: behavior,
        skillLevel: skillLevel,
      );
    }

    final hydratedParams = <String, Map<String, double>>{};
    await Future.wait(paramTasks.entries.map((entry) async {
      final key = entry.key;
      final params = await entry.value;
      if (params == null || params.isEmpty) return;

      final aiParams = <String, double>{};
      params.forEach((name, value) {
        if (value is num) {
          aiParams[name] = value.toDouble();
        }
      });
      if (aiParams.isNotEmpty) {
        hydratedParams[key] = aiParams;
      }
    }));

    if (_gameState == null) {
      _botsHydrated = true;
      return;
    }

    int hydratedCount = 0;
    for (final bot in botsToHydrate) {
      final behavior = bot.botBehavior.toString().split('.').last;
      final skillLevel = bot.botSkillLevel.toString().split('.').last;
      final key = '$behavior|$skillLevel';
      final aiParams = hydratedParams[key];
      if (aiParams == null || aiParams.isEmpty) continue;

      final botIndex = _gameState!.players.indexOf(bot);
      if (botIndex < 0) continue;

      _gameState!.players[botIndex] = bot.copyWith(aiParameters: aiParams);
      hydratedCount++;
      if (kDebugMode) {
        debugPrint(
            '✅ Bot $behavior/$skillLevel hydraté avec ${aiParams.length} paramètres ML');
      }
    }

    if (kDebugMode) {
      debugPrint(
          '🤖 Hydratation ML terminée: $hydratedCount/${botsToHydrate.length}');
    }

    _botsHydrated = true;
    notifyListeners();
    checkIfBotShouldPlay();
  }

  void setContext(BuildContext context) => _currentContext = context;

  void checkIfBotShouldPlay() {
    // Bloquer tant que les bots ne sont pas hydratés avec les params ML
    if (!_botsHydrated) return;

    if (_botOrchestrator.shouldBotPlay(_gameState, isProcessing, _isPaused)) {
      _checkAndPlayBotTurn();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS DU JOUEUR (IGameController)
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void drawCard() {
    if (_gameState == null || _gameState!.phase != GamePhase.playing) return;
    if (!_gameState!.currentPlayer.isHuman || _gameState!.drawnCard != null) {
      return;
    }

    // LOG : État de l'humain au début de son tour
    GameLoggerService.instance.logTurnStart(
      player: _gameState!.currentPlayer,
      turnNumber: _gameState!.turnCount,
      allPlayers: _gameState!.players,
      gameState: _gameState,
    );

    shakingCardIndices.clear();
    final human = _gameState!.currentPlayer;
    final beforeScore = human.getEstimatedScore();

    GameLogic.drawCard(_gameState!);

    _hapticService.cardTap();
    _trackingProvider.recordPlayerActionWithResult(
      actionType: 'draw',
      gameState: _gameState!,
      actionDetails: {
        'source': 'deck',
        'drawnCard': _gameState!.drawnCard?.toJson()
      },
      result: {'scoreChange': human.getEstimatedScore() - beforeScore},
    );
    notifyListeners();
  }

  @override
  void replaceCard(int cardIndex) {
    if (_gameState == null ||
        !_gameState!.currentPlayer.isHuman ||
        _gameState!.drawnCard == null) {
      return;
    }

    final human = _gameState!.currentPlayer;
    final beforeScore = human.getEstimatedScore();
    final drawnCard = _gameState!.drawnCard;

    GameLogic.replaceCard(_gameState!, cardIndex);
    _trackingProvider.recordBotDiscards(_gameState!);

    _trackingProvider.recordPlayerActionWithResult(
      actionType: 'replace',
      gameState: _gameState!,
      actionDetails: {'cardIndex': cardIndex, 'drawnCard': drawnCard?.toJson()},
      result: {'scoreChange': human.getEstimatedScore() - beforeScore},
    );

    _hapticService.cardTap();
    notifyListeners();

    if (_checkInstantEnd()) return;
    _handlePostAction();
  }

  @override
  void discardDrawnCard() {
    if (_gameState == null ||
        !_gameState!.currentPlayer.isHuman ||
        _gameState!.drawnCard == null) {
      return;
    }

    final human = _gameState!.currentPlayer;
    final beforeScore = human.getEstimatedScore();
    final drawnCard = _gameState!.drawnCard;

    GameLogic.discardDrawnCard(_gameState!);
    _trackingProvider.recordBotDiscards(_gameState!);

    _trackingProvider.recordPlayerActionWithResult(
      actionType: 'discard',
      gameState: _gameState!,
      actionDetails: {'source': 'drawn', 'card': drawnCard?.toJson()},
      result: {'scoreChange': human.getEstimatedScore() - beforeScore},
    );

    _hapticService.cardTap();
    notifyListeners();

    if (_checkInstantEnd()) return;
    _handlePostAction();
  }

  @override
  void attemptMatch(int cardIndex, {Player? forcedPlayer}) async {
    if (_gameState == null || _gameState!.phase != GamePhase.reaction) return;

    Player player =
        forcedPlayer ?? _gameState!.players.firstWhere((p) => p.isHuman);
    if (cardIndex < 0 || cardIndex >= player.hand.length) return;

    // 🎯 Capturer la valeur de la carte AVANT le match pour tracker les points économisés
    final cardValue = player.hand[cardIndex].points;

    bool success = GameLogic.matchCard(_gameState!, player, cardIndex);

    if (player.isHuman) {
      _trackingProvider.recordPlayerActionWithResult(
        actionType: 'match',
        gameState: _gameState!,
        actionDetails: {'cardIndex': cardIndex},
        result: {'success': success, 'scoreChange': 0},
      );
      success ? _hapticService.cardTap() : _hapticService.error();

      // 🎯 HUMAN THREAT TRACKER : Enregistrer les matchs réussis de l'humain
      if (success) {
        HumanThreatTracker()
            .recordHumanMatch(cardValue, _gameState!.actionCount);
      }
    }

    if (!success) {
      shakingCardIndices.add(cardIndex);
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 500));
      shakingCardIndices.remove(cardIndex);
    }
    notifyListeners();
  }

  @override
  void takeFromDiscard() {
    if (_gameState == null || _gameState!.phase != GamePhase.playing) return;
    if (!_gameState!.currentPlayer.isHuman || _gameState!.drawnCard != null) {
      return;
    }
    if (_gameState!.discardPile.isEmpty) return;

    final human = _gameState!.currentPlayer;
    final beforeScore = human.getEstimatedScore();
    _gameState!.drawnCard = _gameState!.discardPile.removeLast();
    _hapticService.cardTap();
    _gameState!.addToHistory(ActionHistoryMessages.takeFromDiscard(
        human.name, _gameState!.drawnCard!));

    _trackingProvider.recordPlayerActionWithResult(
      actionType: 'draw',
      gameState: _gameState!,
      actionDetails: {
        'source': 'discard',
        'drawnCard': _gameState!.drawnCard?.toJson()
      },
      result: {'scoreChange': human.getEstimatedScore() - beforeScore},
    );
    notifyListeners();
  }

  @override
  void callDutch() {
    if (_gameState == null || _gameState!.phase != GamePhase.playing) return;
    if (!_gameState!.currentPlayer.isHuman || _gameState!.drawnCard != null) {
      return;
    }

    final human = _gameState!.currentPlayer;
    _trackingProvider.recordPlayerAction(
        actionType: 'dutch', gameState: _gameState!, actionDetails: {});

    _gameState!.phase = GamePhase.dutchCalled;
    _gameState!.dutchCallerId = human.id;
    _hapticService.importantAction();
    _gameState!.addToHistory(ActionHistoryMessages.dutch(human.name));
    endGame();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POUVOIRS SPÉCIAUX (délégués au SpecialPowerHandler)
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void skipSpecialPower() {
    if (_gameState == null) return;
    final wasMatchPower = _gameState!.specialPowerPlayerId != null;
    _hapticService.buttonTap();
    _powerHandler.skipPower(_gameState!);
    _gameState!.specialPowerPlayerId = null;
    notifyListeners();

    if (wasMatchPower) {
      // Pouvoir issu d'un match : vérifier s'il reste des pouvoirs en attente
      _activateNextPendingPower();
    } else {
      _timerManager.resumeTimer(_gameState!, _isPaused);
      if (_gameState!.phase == GamePhase.playing) startReactionPhase();
    }
  }

  @override
  void handleCardTap(int cardIndex) {
    if (_gameState == null || isProcessing) return;
    final human = _gameState!.players.firstWhere((p) => p.isHuman);
    final isLocalTurn = _gameState!.currentPlayer.isHuman;

    if (_gameState!.phase == GamePhase.reaction) {
      attemptMatch(cardIndex, forcedPlayer: human);
    } else if (_gameState!.phase == GamePhase.playing &&
        isLocalTurn &&
        _gameState!.drawnCard != null) {
      replaceCard(cardIndex);
    }
  }

  void useSpecialPower(int targetPlayerIndex, int targetCardIndex) {
    if (_gameState == null) return;
    _hapticService.importantAction();
    final wasMatchPower = _gameState!.specialPowerPlayerId != null;
    _powerHandler.usePower(_gameState!, targetPlayerIndex, targetCardIndex);
    _gameState!.specialPowerPlayerId = null;
    notifyListeners();
    if (_gameState!.pendingSwap != null) return; // Attendre completeSwap
    _afterPowerResolved(wasMatchPower);
  }

  void completeSwap(int ownCardIndex) {
    if (_gameState == null) return;
    _hapticService.cardTap();
    final wasMatchPower = _gameState!.specialPowerPlayerId != null;
    _powerHandler.completeSwap(_gameState!, ownCardIndex);
    _gameState!.specialPowerPlayerId = null;
    notifyListeners();
    _afterPowerResolved(wasMatchPower);
  }

  void executeLookAtCard(Player target, int cardIndex) {
    if (_gameState == null) return;
    _hapticService.cardTap();
    final wasMatchPower = _gameState!.specialPowerPlayerId != null;
    _powerHandler.executeLookAtCard(_gameState!, target, cardIndex);
    _gameState!.specialPowerPlayerId = null;
    notifyListeners();
    _afterPowerResolved(wasMatchPower);
  }

  void executeJokerEffect(Player target) {
    if (_gameState == null) return;
    _hapticService.importantAction();
    final wasMatchPower = _gameState!.specialPowerPlayerId != null;
    _powerHandler.executeJokerEffect(_gameState!, target);
    _gameState!.specialPowerPlayerId = null;
    notifyListeners();
    _afterPowerResolved(wasMatchPower);
  }

  /// Après la résolution d'un pouvoir, soit passer au prochain pouvoir en attente,
  /// soit lancer la phase de réaction normalement.
  void _afterPowerResolved(bool wasMatchPower) {
    if (_gameState == null) return;
    if (wasMatchPower) {
      _activateNextPendingPower();
    } else {
      _timerManager.resumeTimer(_gameState!, _isPaused);
      if (_gameState!.phase == GamePhase.playing) startReactionPhase();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TIMER DE RÉACTION (délégué au ReactionTimerManager)
  // ═══════════════════════════════════════════════════════════════════════════

  void pauseReactionTimerForNotification() =>
      _timerManager.pauseTimer(_gameState);
  void resumeReactionTimerAfterNotification() =>
      _timerManager.resumeTimer(_gameState!, _isPaused);

  void startReactionPhase() {
    if (_gameState == null || _isPaused) return;

    if (_gameState!.specialPowerStartTime != null) {
      _gameState!.specialPowerStartTime = null; // consume it
    }

    _timerManager.startReactionPhase(
        _gameState!, _currentReactionTimeMs, _isPaused);
    _simulateBotReaction();
  }

  void _endReactionPhase() {
    if (_gameState == null || _isPaused) return;
    _timerManager.cancelTimer();
    _gameState!.lastSpiedCard = null;

    // S'il y a des pouvoirs en attente (matchs de cartes pouvoir pendant la réaction),
    // les résoudre avant de passer au tour suivant
    if (_gameState!.pendingMatchPowers.isNotEmpty) {
      _processPendingMatchPowers();
      return;
    }

    _advanceToNextTurn();
  }

  /// Avance au tour suivant (appelé après réaction ou après résolution des pouvoirs match)
  void _advanceToNextTurn() {
    if (_gameState == null) return;
    _gameState!.phase = GamePhase.playing;
    GameLogic.nextPlayer(_gameState!);
    _trackingProvider.incrementBotTurns(_gameState!);

    // 🎯 HUMAN THREAT TRACKER : Notifier le changement de tour
    HumanThreatTracker().onNewTurn();

    notifyListeners();
    if (!_gameState!.currentPlayer.isHuman && !_isPaused) {
      _checkAndPlayBotTurn();
    }
  }

  /// Résout les pouvoirs en attente suite à des matchs pendant la réaction.
  /// Attribution aléatoire d'un numéro d'ordre, puis résolution séquentielle.
  bool _showPowerLottery = false;
  bool get showPowerLottery => _showPowerLottery;

  void _processPendingMatchPowers() {
    if (_gameState == null) return;
    final pending = _gameState!.pendingMatchPowers;
    if (pending.isEmpty) {
      _advanceToNextTurn();
      return;
    }

    // Séparer les pouvoirs passifs (7, 10) des pouvoirs actifs (Valet, Joker).
    // Les passifs ne modifient pas l'état du jeu → pas besoin de tirage d'ordre,
    // ils peuvent être résolus simultanément / en premier sans loterie.
    final passivePowers = pending
        .where((p) => p.card.value == '7' || p.card.value == '10')
        .toList();
    final activePowers = pending
        .where((p) => p.card.value != '7' && p.card.value != '10')
        .toList();

    // Réorganiser : passifs d'abord (numéro auto), puis actifs
    pending.clear();
    int order = 1;
    for (final p in passivePowers) {
      p.drawNumber = order++;
    }
    pending.addAll(passivePowers);

    if (activePowers.isEmpty) {
      // Que des pouvoirs passifs → résoudre directement, pas de loterie
      _activateNextPendingPower();
      return;
    }

    if (activePowers.length == 1) {
      // Un seul pouvoir actif → pas besoin de loterie
      activePowers[0].drawNumber = order;
      pending.addAll(activePowers);
      if (passivePowers.isEmpty) {
        _activateNextPendingPower();
      }
      // Si on a déjà lancé les passifs, ils s'enchaîneront via _activateNextPendingPower
      if (passivePowers.isNotEmpty) {
        _activateNextPendingPower();
      }
      return;
    }

    // Plusieurs pouvoirs actifs → loterie pour l'ordre entre eux uniquement
    final numbers = List.generate(activePowers.length, (i) => i + 1)..shuffle();
    for (int i = 0; i < activePowers.length; i++) {
      activePowers[i].drawNumber = order + numbers[i] - 1;
    }
    pending.addAll(activePowers);

    // Trier par drawNumber
    pending.sort((a, b) => (a.drawNumber ?? 0).compareTo(b.drawNumber ?? 0));

    // Signaler à l'UI d'afficher le dialog de loterie (seulement pour les actifs)
    _showPowerLottery = true;
    notifyListeners();
  }

  /// Appelé par le dialog de loterie quand il se ferme
  void onPowerLotteryComplete() {
    _showPowerLottery = false;
    if (_gameState == null) return;
    // Trier par numéro (plus petit en premier)
    final pending = _gameState!.pendingMatchPowers;
    pending.sort((a, b) => (a.drawNumber ?? 0).compareTo(b.drawNumber ?? 0));
    _activateNextPendingPower();
  }

  /// Active le prochain pouvoir en attente dans la queue
  void _activateNextPendingPower() {
    if (_gameState == null) return;
    final pending = _gameState!.pendingMatchPowers;

    if (pending.isEmpty) {
      // Plus de pouvoirs en attente → tour suivant
      _advanceToNextTurn();
      return;
    }

    // Prendre le premier pouvoir et l'activer
    final power = pending.removeAt(0);
    _gameState!.phase = GamePhase.specialPower;
    _gameState!.isWaitingForSpecialPower = true;
    _gameState!.specialCardToActivate = power.card;
    _gameState!.specialPowerPlayerId = power.playerId;
    _gameState!.specialPowerStartTime =
        DateTime.now().millisecondsSinceEpoch;
    _gameState!.turnStartTime = DateTime.now().millisecondsSinceEpoch;
    _gameState!.turnTimeoutMs = 60000;

    notifyListeners();

    // Si c'est un bot, auto-résoudre le pouvoir
    final player = _gameState!.players
        .where((p) => p.id == power.playerId)
        .firstOrNull;
    if (player != null && !player.isHuman) {
      _autoBotMatchPower(player, power);
    }
  }

  /// Auto-résout le pouvoir d'un bot (match power)
  Future<void> _autoBotMatchPower(Player bot, PendingMatchPower power) async {
    if (_gameState == null) return;
    await Future.delayed(const Duration(milliseconds: 800));
    if (_gameState == null || _gameState!.phase != GamePhase.specialPower) {
      return;
    }
    // Le bot skip le pouvoir pour simplifier (les bots utilisent rarement
    // les pouvoirs de match de manière stratégique)
    skipSpecialPower();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOTS (délégué au BotOrchestrator)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _simulateBotReaction() async {
    if (_gameState == null || _isPaused) return;
    await _botOrchestrator.simulateBotReaction(
      _gameState!,
      _playerMMR,
      _isPaused,
      hardcoreLevel: _hardcoreLevel,
      playerSkillEstimate: _skillEstimator.estimatedSkill,
    );
    notifyListeners();
  }

  Future<void> _checkAndPlayBotTurn() async {
    // Protection contre les appels concurrents (race condition)
    // On vérifie ET on set isProcessing de façon atomique
    if (isProcessing) return;
    if (!_botOrchestrator.shouldBotPlay(_gameState, false, _isPaused)) return;
    if (_checkInstantEnd()) return;

    isProcessing = true;
    notifyListeners();

    await _botOrchestrator.playBotTurn(
      _gameState!,
      _playerMMR,
      _isPaused,
      _currentContext,
      () async => _checkInstantEnd(),
      hardcoreLevel: _hardcoreLevel,
      playerSkillEstimate: _skillEstimator.estimatedSkill,
      onStateChanged: () {
        if (_gameState == null) return;
        notifyListeners();
      },
    );

    if (_gameState?.phase == GamePhase.dutchCalled) {
      endGame();
      return;
    }

    isProcessing = false;
    notifyListeners();
    if (_gameState?.phase == GamePhase.playing) {
      if (_currentActionTextDisplayMs > 0) {
        await Future.delayed(
            Duration(milliseconds: _currentActionTextDisplayMs));
        if (_gameState == null || _isPaused) return;
        if (_gameState!.phase != GamePhase.playing) return;
      }
      startReactionPhase();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAUSE / REPRISE
  // ═══════════════════════════════════════════════════════════════════════════

  void pauseGame() {
    _isPaused = true;
    _timerManager.pauseTimer(_gameState);
    isProcessing = false;
    notifyListeners();
  }

  void resumeGame() {
    _isPaused = false;
    if (_gameState?.phase == GamePhase.reaction) {
      _timerManager.resumeTimer(_gameState!, _isPaused);
    }
    notifyListeners();
    if (_gameState != null &&
        !_gameState!.currentPlayer.isHuman &&
        _gameState!.phase == GamePhase.playing) {
      _checkAndPlayBotTurn();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FIN DE PARTIE
  // ═══════════════════════════════════════════════════════════════════════════

  void endGame() {
    if (_gameState == null) return;
    _hapticService.success();
    _clearActiveGameFlag();
    _gameState!.phase = GamePhase.ended;

    for (var p in _gameState!.players) {
      for (int i = 0; i < p.knownCards.length; i++) {
        p.knownCards[i] = true;
      }
    }

    _trackingProvider.finalizeBotRecordings(_gameState!);

    List<Player> ranking = _gameState!.getFinalRanking();
    Player human = _gameState!.players.firstWhere((p) => p.isHuman);
    int playerRank = ranking.indexWhere((p) => p.id == human.id) + 1;
    bool calledDutch = _gameState!.dutchCallerId == human.id;
    bool wonDutch = calledDutch && playerRank == 1;
    _lastMatchRpResult = null;
    if (_useSBMM && _playerMMR != null) {
      final winStreak = playerRank == 1 ? _playerWinStreak + 1 : 0;
      _lastMatchRpResult = RPCalculator.calculateRP(
        playerRank: playerRank,
        currentMMR: _playerMMR!,
        calledDutch: calledDutch,
        hasEmptyHand: human.hand.isEmpty,
        isEliminated: calledDutch && playerRank != 1,
        totalPlayers: _gameState!.players.length,
        isTournament: _gameState!.gameMode == GameMode.tournament,
        tournamentRound: _gameState!.gameMode == GameMode.tournament
            ? _gameState!.tournamentRound
            : 1,
        winStreak: winStreak,
      );
    }

    _trackingProvider.endPlayerRecording(
      slotId: _currentSlotId,
      usedSBMM: _useSBMM,
      gameState: _gameState!,
      finalScore: _gameState!.getFinalScore(human),
      finalRank: playerRank,
      calledDutch: calledDutch,
      wonDutch: wonDutch,
    );

    _addDutchHistory();
    _logFinalRanking(ranking);

    // ═══════════════════════════════════════════════════════════════════════
    // TÉLÉMÉTRIE AI : Générer le résumé et stocker
    // ═══════════════════════════════════════════════════════════════════════
    final aiSummary = AiTelemetryService().summarize(
      playerWon: playerRank == 1,
      winnerId: ranking.first.id,
    );

    // Stocker le résumé pour analyse SBMM
    _statsService.recordAiTelemetry(aiSummary.toJson(), slotId: _currentSlotId);

    if (kDebugMode) debugPrint(aiSummary.toString());

    // ═══════════════════════════════════════════════════════════════════════
    // LOGGING : Enregistrer la fin de partie
    // ═══════════════════════════════════════════════════════════════════════
    final dutchCaller = _gameState!.players.firstWhere(
      (p) => p.id == _gameState!.dutchCallerId,
      orElse: () => human,
    );
    GameLoggerService.instance.logRoundEnd(
      players: _gameState!.players,
      dutchCaller: dutchCaller,
      dutchSuccess: ranking.first.id == _gameState!.dutchCallerId,
    );

    final totalScores = <String, int>{};
    for (final p in _gameState!.players) {
      totalScores[p.name] = _gameState!.getFinalScore(p);
    }
    GameLoggerService.instance.logGameEnd(
      players: _gameState!.players,
      totalScores: totalScores,
      winner: ranking.first,
    );

    // IMPORTANT: sauvegarder les stats APRES logRoundEnd/logGameEnd,
    // sinon le gameLog exporté depuis Statistiques est tronqué.
    _statsService.saveGameResult(
      playerRank: playerRank,
      score: _gameState!.getFinalScore(human),
      calledDutch: calledDutch,
      wonDutch: wonDutch,
      hasEmptyHand: human.hand.isEmpty,
      slotId: _currentSlotId,
      isSBMM: _useSBMM,
      totalPlayers: _gameState!.players.length,
      isTournament: _gameState!.gameMode == GameMode.tournament,
      tournamentRound: _gameState!.gameMode == GameMode.tournament
          ? _gameState!.tournamentRound
          : 1,
      tournamentId: _tournamentManager.activeTournamentId,
      actionHistory: List<String>.from(_gameState!.actionHistory),
      gameLog: GameLoggerService.instance.getLogForCurrentRound(),
    );

    // ═══════════════════════════════════════════════════════════════════════
    // BOT MATCHUP : Sauvegarder les stats joueur vs bots
    // ═══════════════════════════════════════════════════════════════════════
    _saveBotMatchup(
      ranking: ranking,
      human: human,
      playerRank: playerRank,
    );

    // ═══════════════════════════════════════════════════════════════════════
    // SBMM : Enregistrer le résultat sur le serveur (fire-and-forget)
    // ═══════════════════════════════════════════════════════════════════════
    if (_useSBMM) {
      _recordSBMMGame(
        ranking: ranking,
        human: human,
        playerRank: playerRank,
        calledDutch: calledDutch,
        wonDutch: wonDutch,
      );
    }

    notifyListeners();
  }

  /// Sauvegarde les stats de matchup joueur vs bots (fire-and-forget).
  void _saveBotMatchup({
    required List<Player> ranking,
    required Player human,
    required int playerRank,
  }) {
    // Fire-and-forget pour ne pas bloquer notifyListeners
    _saveBotMatchupAsync(
        ranking: ranking, human: human, playerRank: playerRank);
  }

  Future<void> _saveBotMatchupAsync({
    required List<Player> ranking,
    required Player human,
    required int playerRank,
  }) async {
    try {
      final bots = _gameState!.players.where((p) => !p.isHuman).toList();
      if (bots.isEmpty) return;

      final difficultyName = _gameState!.difficulty.toString().split('.').last;

      final botEntries = <BotMatchupEntry>[];
      for (final bot in bots) {
        final params = bot.aiParameters ?? <String, double>{};
        final botRank = ranking.indexWhere((p) => p.id == bot.id) + 1;
        final keyParams = <String, double>{};
        for (final key in [
          'memoryAccuracy',
          'memoryRetention',
          'dutchThreshold',
          'dutchQuality',
          'aggressiveness',
          'decisionSpeed'
        ]) {
          final v = params[key];
          if (v != null) keyParams[key] = v;
        }

        botEntries.add(BotMatchupEntry(
          botId: bot.botBehavior?.toString().split('.').last ?? 'unknown',
          botMMR: (params['serverMMR'] as num?)?.toInt() ?? 0,
          botWinRateVsHuman:
              (params['serverWinRateVsHuman'] as num?)?.toDouble() ?? 0.0,
          botScore: _gameState!.getFinalScore(bot),
          botRank: botRank,
          botParams: keyParams,
        ));
      }

      final hasBoosted =
          bots.any((b) => (b.aiParameters?['isBoostedSBMM'] ?? 0) == 1.0);

      final record = BotMatchupRecord(
        gameId: '${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now(),
        playerMMR: _playerMMR ?? 0,
        playerRank: playerRank,
        playerScore: _gameState!.getFinalScore(human),
        numberOfPlayers: _gameState!.players.length,
        difficulty: difficultyName,
        wasBoostedSBMM: hasBoosted,
        bots: botEntries,
      );

      final prefs = await SharedPreferences.getInstance();
      final key = 'bot_matchup_history_slot_$_currentSlotId';
      final rawList = prefs.getStringList(key) ?? [];
      rawList.insert(0, jsonEncode(record.toJson()));
      // Garder max 20 entrées
      if (rawList.length > 20) rawList.removeRange(20, rawList.length);
      await prefs.setStringList(key, rawList);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Erreur sauvegarde bot matchup: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SBMM RECORD-GAME (fire-and-forget)
  // ═══════════════════════════════════════════════════════════════════════════

  void _recordSBMMGame({
    required List<Player> ranking,
    required Player human,
    required int playerRank,
    required bool calledDutch,
    required bool wonDutch,
  }) {
    _recordSBMMGameAsync(
      ranking: ranking,
      human: human,
      playerRank: playerRank,
      calledDutch: calledDutch,
      wonDutch: wonDutch,
    );
  }

  Future<void> _recordSBMMGameAsync({
    required List<Player> ranking,
    required Player human,
    required int playerRank,
    required bool calledDutch,
    required bool wonDutch,
  }) async {
    try {
      final bots = _gameState!.players.where((p) => !p.isHuman).toList();
      if (bots.isEmpty) return;

      final botResults = bots.map((bot) {
        final botRank = ranking.indexWhere((p) => p.id == bot.id) + 1;
        final botDutchCalled = _gameState!.dutchCallerId == bot.id;
        final botDutchWon = botDutchCalled && botRank == 1;
        return SBMMBotResult(
          level: bot.botSkillLevel?.name ?? 'silver',
          rank: botRank,
          score: _gameState!.getFinalScore(bot),
          dutchCalled: botDutchCalled,
          dutchWon: botDutchWon,
        );
      }).toList();

      await SBMMClientService.recordGame(
        gameId: '${DateTime.now().millisecondsSinceEpoch}',
        rank: playerRank,
        score: _gameState!.getFinalScore(human),
        botResults: botResults,
        totalPlayers: _gameState!.players.length,
        dutchCalled: calledDutch,
        dutchWon: wonDutch,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ SBMM record-game error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TOURNOI (délégué au TournamentManager)
  // ═══════════════════════════════════════════════════════════════════════════

  bool isHumanEliminatedInTournament() {
    if (_gameState == null) return false;
    return _tournamentManager.isHumanEliminated(_gameState!);
  }

  Set<String> getTournamentEliminatedIds() {
    if (_gameState == null) return {};
    return _tournamentManager.getEliminatedPlayerIds(_gameState!);
  }

  void finishTournamentForHuman() {
    if (_gameState == null) return;
    _tournamentManager.finishTournamentForHuman(_gameState!);
    notifyListeners();
  }

  int getTournamentRP(int finalPosition) =>
      _tournamentManager.calculateRP(finalPosition);

  Future<void> startNextTournamentRound() async {
    if (_gameState == null) return;
    _gameState!.updateCumulativeScores();
    _tournamentManager.updateCumulativeScores(_gameState!);

    if (_gameState!.gameMode == GameMode.tournament &&
        _gameState!.tournamentRound >= tournamentTotalRounds) {
      return;
    }

    List<Player> survivors =
        _tournamentManager.prepareSurvivorsForNextRound(_gameState!);
    if (survivors.length < 2) return;

    await createNewGame(
      players: survivors,
      gameMode: GameMode.tournament,
      difficulty: _gameState!.difficulty,
      reactionTimeMs: _currentReactionTimeMs,
      actionTextDisplayMs: _currentActionTextDisplayMs,
      tournamentRound: _gameState!.tournamentRound + 1,
      saveSlot: _currentSlotId,
      useSBMM: _playerMMR != null,
    );
  }

  /// Annule la partie en cours **sans** enregistrer de résultat dans les stats.
  /// Utilisé quand le joueur quitte avant d'avoir réellement joué (ex. phase
  /// de mémorisation avant la révélation des cartes).
  void cancelGame() {
    _clearActiveGameFlag();
    _gameState = null;
    _isPaused = false;
    isProcessing = false;
    shakingCardIndices.clear();
    _timerManager.cancelTimer();
    _playerMMR = null;
    _tournamentManager.resetTournament();
    notifyListeners();
  }

  void quitGame() {
    _clearActiveGameFlag();
    if (_gameState != null) {
      // Calcul du score d'abandon : 52pts (4 Rois) par manche restante
      final bool isTournament = _gameState!.gameMode == GameMode.tournament;
      const int penaltyPerRound = 13 * 4; // 52 = pire main possible
      final int quitScore;
      final String detail;
      if (isTournament) {
        final int remainingRounds =
            tournamentTotalRounds - _gameState!.tournamentRound + 1;
        quitScore = penaltyPerRound * remainingRounds;
        detail =
            'Abandon : $penaltyPerRound pts x $remainingRounds manche(s) restante(s) = $quitScore pts';
      } else {
        quitScore = penaltyPerRound;
        detail = 'Abandon : $penaltyPerRound pts (pire main possible)';
      }
      _statsService.saveGameResult(
        score: quitScore,
        playerRank: _gameState!.players.length,
        calledDutch: false,
        wonDutch: false,
        hasEmptyHand: false,
        isSBMM: _playerMMR != null,
        slotId: _currentSlotId,
        totalPlayers: _gameState!.players.length,
        isTournament: isTournament,
        tournamentRound: _gameState!.tournamentRound,
        tournamentId: _tournamentManager.activeTournamentId,
        actionHistory: List<String>.from(_gameState!.actionHistory),
        gameLog: GameLoggerService.instance.getLogForCurrentRound(),
        scoreDetail: detail,
      );
    }
    _gameState = null;
    _isPaused = false;
    isProcessing = false;
    shakingCardIndices.clear();
    _timerManager.cancelTimer();
    _playerMMR = null;
    _tournamentManager.resetTournament();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MÉTHODES UTILITAIRES PRIVÉES
  // ═══════════════════════════════════════════════════════════════════════════

  void _handlePostAction() {
    if (_gameState!.phase == GamePhase.specialPower) {
      _timerManager.pauseTimer(_gameState);
      Future.delayed(const Duration(milliseconds: 1300)).then((_) {
        if (_gameState?.phase == GamePhase.specialPower) notifyListeners();
      });
    } else {
      startReactionPhase();
    }
  }

  bool _checkInstantEnd() {
    if (_gameState == null) return false;
    if (_gameState!.deck.isEmpty) {
      _refillDeckFromDiscard();
      if (_gameState!.deck.isEmpty) {
        endGame();
        return true;
      }
    }
    return false;
  }

  void _refillDeckFromDiscard() {
    if (_gameState == null || _gameState!.discardPile.length <= 1) return;
    PlayingCard topCard = _gameState!.discardPile.removeLast();
    _gameState!.deck.addAll(_gameState!.discardPile);
    _gameState!.discardPile.clear();
    _gameState!.discardPile.add(topCard);
    _gameState!.smartShuffle();
    _gameState!.addToHistory(
        ActionHistoryMessages.deckRefilled(_gameState!.deck.length));
    notifyListeners();
  }

  void _addDutchHistory() {
    if (_gameState!.dutchCallerId == null) return;
    Player dutchCaller = _gameState!.players
        .firstWhere((p) => p.id == _gameState!.dutchCallerId);
    if (dutchCaller.isHuman) return;

    List<Player> ranking = _gameState!.getFinalRanking();
    int dutchCallerRank = ranking.indexWhere((p) => p.id == dutchCaller.id) + 1;
    dutchCaller.dutchHistory.add(DutchAttempt(
      estimatedScore: dutchCaller.getEstimatedScore(),
      actualScore: _gameState!.getFinalScore(dutchCaller),
      won: dutchCallerRank == 1,
      opponentsCount: _gameState!.players.length - 1,
    ));
    if (dutchCaller.dutchHistory.length > 10) {
      dutchCaller.dutchHistory.removeAt(0);
    }
  }

  void _logFinalRanking(List<Player> ranking) {
    final ranksWithTies = _gameState!.getFinalRanksWithTies();
    _gameState!.addToHistory("🏁 Classement final");
    String rankEmoji(int rank) => rank == 1
        ? "🥇"
        : rank == 2
            ? "🥈"
            : rank == 3
                ? "🥉"
                : "";
    for (int i = 0; i < ranking.length; i++) {
      final player = ranking[i];
      final rank = ranksWithTies[player.id] ?? (i + 1);
      final score = _gameState!.getFinalScore(player);
      final badge = rankEmoji(rank);
      final dutchTag = player.id == _gameState!.dutchCallerId ? " (DUTCH)" : "";
      _gameState!.addToHistory(
          "${badge.isEmpty ? "" : "$badge "}#$rank ${player.name}$dutchTag — $score pts");
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FLAG "PARTIE EN COURS" — détection abandon par fermeture d'app
  // ═══════════════════════════════════════════════════════════════════════════

  void _setActiveGameFlag({
    required int slotId,
    required int tournamentRound,
    required int totalRounds,
    required int totalPlayers,
    required String? tournamentId,
    required bool useSBMM,
    required bool isTournament,
  }) {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(
          _kActiveGameKey,
          jsonEncode({
            'slotId': slotId,
            'tournamentRound': tournamentRound,
            'totalRounds': totalRounds,
            'totalPlayers': totalPlayers,
            'tournamentId': tournamentId,
            'useSBMM': useSBMM,
            'isTournament': isTournament,
            'timestamp': DateTime.now().toIso8601String(),
          }));
    });
  }

  void _clearActiveGameFlag() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove(_kActiveGameKey);
    });
  }

  /// Appelé au lancement de l'app (main menu) pour détecter un abandon
  /// par fermeture d'app/page lors d'un tournoi.
  static Future<void> checkForAbandonedGame() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kActiveGameKey);
    if (raw == null) return;

    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final slotId = data['slotId'] as int;
      final tournamentRound = data['tournamentRound'] as int? ?? 1;
      final totalRounds = data['totalRounds'] as int? ?? 1;
      final totalPlayers = data['totalPlayers'] as int;
      final tournamentId = data['tournamentId'] as String?;
      final useSBMM = data['useSBMM'] as bool? ?? false;
      final isTournament = data['isTournament'] as bool? ?? false;

      const penaltyPerRound = 13 * 4; // 52
      final int quitScore;
      final String detail;

      if (isTournament) {
        final remainingRounds = totalRounds - tournamentRound + 1;
        quitScore = penaltyPerRound * remainingRounds;
        detail =
            'Abandon (app fermée) : $penaltyPerRound pts x $remainingRounds manche(s) = $quitScore pts';
      } else {
        quitScore = penaltyPerRound;
        detail =
            'Abandon (app fermée) : $penaltyPerRound pts (pire main possible)';
      }

      await StatsService.saveGameResult(
        score: quitScore,
        playerRank: totalPlayers,
        calledDutch: false,
        wonDutch: false,
        hasEmptyHand: false,
        isSBMM: useSBMM,
        slotId: slotId,
        totalPlayers: totalPlayers,
        isTournament: isTournament,
        tournamentRound: tournamentRound,
        tournamentId: tournamentId,
        scoreDetail: detail,
      );

      if (kDebugMode) {
        debugPrint(
            'Abandon détecté : ${isTournament ? "tournoi round $tournamentRound" : "partie rapide"}, score=$quitScore');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Erreur checkForAbandonedGame: $e');
    } finally {
      await prefs.remove(_kActiveGameKey);
    }
  }

  @override
  void dispose() {
    _timerManager.dispose();
    super.dispose();
  }
}
