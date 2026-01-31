import 'dart:async';
import '../models/playing_card.dart';
import '../models/player.dart';
import '../models/game_state.dart';
import '../models/game_settings.dart';
import '../services/game/game_logic.dart';
import '../core/interfaces/i_haptic_service.dart';
import '../core/interfaces/i_stats_service.dart';
import '../core/interfaces/i_bot_ai_service.dart';
import '../core/interfaces/i_game_controller.dart';
import 'game_tracking_provider.dart';
import 'managers/solo/tournament_manager.dart';
import 'managers/solo/reaction_timer_manager.dart';
import 'managers/solo/special_power_handler.dart';
import 'managers/solo/bot_orchestrator.dart';
import 'package:flutter/widgets.dart';

export 'managers/solo/tournament_manager.dart' show TournamentResult;

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
  Player? get localPlayer => _gameState?.players.where((p) => p.isHuman).firstOrNull;
  
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
  int _currentSlotId = 1;
  
  int? _playerMMR;
  int? get playerMMR => _playerMMR;
  int _playerWinStreak = 0;
  int get playerWinStreak => _playerWinStreak;

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
  List<TournamentResult>? get tournamentFinalRanking => _tournamentManager.finalRanking;
  ValueNotifier<int> get reactionTimeRemaining => _timerManager.reactionTimeRemaining;

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

  void createNewGame({
    required List<Player> players,
    required GameMode gameMode,
    required Difficulty difficulty,
    required int reactionTimeMs,
    int tournamentRound = 1,
    int saveSlot = 1,
    bool useSBMM = false,
  }) async {
    // Initialiser le tournoi via le manager
    if (gameMode == GameMode.tournament) {
      _tournamentManager.initializeTournament(tournamentRound);
    } else {
      _tournamentManager.resetTournament();
    }

    _gameState = GameLogic.initializeGame(
        players: players, gameMode: gameMode, difficulty: difficulty, tournamentRound: tournamentRound);
    _gameState!.tournamentCumulativeScores = Map.from(_tournamentManager.cumulativeScores);
    
    _currentReactionTimeMs = reactionTimeMs;
    _currentSlotId = saveSlot;

    if (useSBMM) {
      final stats = await _statsService.getStats(slotId: saveSlot);
      _playerMMR = stats['mmr'] ?? 0;
      _playerWinStreak = stats['winStreak'] ?? 0;
    } else {
      _playerMMR = null;
      _playerWinStreak = 0;
    }

    for (var player in _gameState!.players.where((p) => !p.isHuman)) {
      player.initializeBotMemory();
    }

    // Initialiser le tracking
    _trackingProvider.initTracking(_gameState!, useSBMM);

    shakingCardIndices.clear();
    isProcessing = false;
    notifyListeners();
  }

  void setContext(BuildContext context) => _currentContext = context;

  void checkIfBotShouldPlay() {
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
    if (!_gameState!.currentPlayer.isHuman || _gameState!.drawnCard != null) return;

    shakingCardIndices.clear();
    final human = _gameState!.currentPlayer;
    final beforeScore = human.getEstimatedScore();
    
    GameLogic.drawCard(_gameState!);
    
    _trackingProvider.recordPlayerActionWithResult(
      actionType: 'draw',
      gameState: _gameState!,
      actionDetails: {'source': 'deck', 'drawnCard': _gameState!.drawnCard?.toJson()},
      result: {'scoreChange': human.getEstimatedScore() - beforeScore},
    );
    notifyListeners();
  }

  @override
  void replaceCard(int cardIndex) {
    if (_gameState == null || !_gameState!.currentPlayer.isHuman || _gameState!.drawnCard == null) return;

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
    if (_gameState == null || !_gameState!.currentPlayer.isHuman || _gameState!.drawnCard == null) return;

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

    Player player = forcedPlayer ?? _gameState!.players.firstWhere((p) => p.isHuman);
    if (cardIndex < 0 || cardIndex >= player.hand.length) return;

    bool success = GameLogic.matchCard(_gameState!, player, cardIndex);

    if (player.isHuman) {
      _trackingProvider.recordPlayerActionWithResult(
        actionType: 'match',
        gameState: _gameState!,
        actionDetails: {'cardIndex': cardIndex},
        result: {'success': success, 'scoreChange': 0},
      );
      success ? _hapticService.cardTap() : _hapticService.error();
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
    if (!_gameState!.currentPlayer.isHuman || _gameState!.drawnCard != null) return;
    if (_gameState!.discardPile.isEmpty) return;

    final human = _gameState!.currentPlayer;
    final beforeScore = human.getEstimatedScore();
    _gameState!.drawnCard = _gameState!.discardPile.removeLast();
    _gameState!.addToHistory("${human.name} prend ${_gameState!.drawnCard!.displayName} de la défausse.");

    _trackingProvider.recordPlayerActionWithResult(
      actionType: 'draw',
      gameState: _gameState!,
      actionDetails: {'source': 'discard', 'drawnCard': _gameState!.drawnCard?.toJson()},
      result: {'scoreChange': human.getEstimatedScore() - beforeScore},
    );
    notifyListeners();
  }

  @override
  void callDutch() {
    if (_gameState == null || _gameState!.phase != GamePhase.playing) return;
    if (!_gameState!.currentPlayer.isHuman || _gameState!.drawnCard != null) return;

    final human = _gameState!.currentPlayer;
    _trackingProvider.recordPlayerAction(actionType: 'dutch', gameState: _gameState!, actionDetails: {});
    
    _gameState!.phase = GamePhase.dutchCalled;
    _gameState!.dutchCallerId = human.id;
    _gameState!.addToHistory("📢 ${human.name} crie DUTCH !");
    endGame();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POUVOIRS SPÉCIAUX (délégués au SpecialPowerHandler)
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void skipSpecialPower() {
    if (_gameState == null) return;
    _powerHandler.skipPower(_gameState!);
    notifyListeners();
    _timerManager.resumeTimer(_gameState!, _isPaused);
    if (_gameState!.phase == GamePhase.playing) startReactionPhase();
  }

  @override
  void handleCardTap(int cardIndex) {
    if (_gameState == null || isProcessing) return;
    final human = _gameState!.players.firstWhere((p) => p.isHuman);
    final isLocalTurn = _gameState!.currentPlayer.isHuman;
    
    if (_gameState!.phase == GamePhase.reaction) {
      attemptMatch(cardIndex, forcedPlayer: human);
    } else if (_gameState!.phase == GamePhase.playing && isLocalTurn && _gameState!.drawnCard != null) {
      replaceCard(cardIndex);
    }
  }

  void useSpecialPower(int targetPlayerIndex, int targetCardIndex) {
    if (_gameState == null) return;
    _powerHandler.usePower(_gameState!, targetPlayerIndex, targetCardIndex);
    notifyListeners();
    if (_gameState!.pendingSwap != null) return; // Attendre completeSwap
    _timerManager.resumeTimer(_gameState!, _isPaused);
    if (_gameState!.phase == GamePhase.playing) startReactionPhase();
  }

  void completeSwap(int ownCardIndex) {
    if (_gameState == null) return;
    _powerHandler.completeSwap(_gameState!, ownCardIndex);
    notifyListeners();
    _timerManager.resumeTimer(_gameState!, _isPaused);
    if (_gameState!.phase == GamePhase.playing) startReactionPhase();
  }

  void executeLookAtCard(Player target, int cardIndex) {
    if (_gameState == null) return;
    _powerHandler.executeLookAtCard(_gameState!, target, cardIndex);
    notifyListeners();
    _timerManager.resumeTimer(_gameState!, _isPaused);
    if (_gameState!.phase == GamePhase.playing) startReactionPhase();
  }

  void executeJokerEffect(Player target) {
    if (_gameState == null) return;
    _powerHandler.executeJokerEffect(_gameState!, target);
    notifyListeners();
    _timerManager.resumeTimer(_gameState!, _isPaused);
    if (_gameState!.phase == GamePhase.playing) startReactionPhase();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TIMER DE RÉACTION (délégué au ReactionTimerManager)
  // ═══════════════════════════════════════════════════════════════════════════

  void pauseReactionTimerForNotification() => _timerManager.pauseTimer(_gameState);
  void resumeReactionTimerAfterNotification() => _timerManager.resumeTimer(_gameState!, _isPaused);

  void startReactionPhase() {
    if (_gameState == null || _isPaused) return;
    _timerManager.startReactionPhase(_gameState!, _currentReactionTimeMs, _isPaused);
    _simulateBotReaction();
  }

  void _endReactionPhase() {
    if (_gameState == null || _isPaused) return;
    _timerManager.cancelTimer();
    _gameState!.phase = GamePhase.playing;
    _gameState!.lastSpiedCard = null;
    GameLogic.nextPlayer(_gameState!);
    _trackingProvider.incrementBotTurns(_gameState!);
    notifyListeners();
    if (!_gameState!.currentPlayer.isHuman && !_isPaused) _checkAndPlayBotTurn();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOTS (délégué au BotOrchestrator)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _simulateBotReaction() async {
    if (_gameState == null || _isPaused) return;
    await _botOrchestrator.simulateBotReaction(_gameState!, _playerMMR, _isPaused);
    notifyListeners();
  }

  Future<void> _checkAndPlayBotTurn() async {
    if (!_botOrchestrator.shouldBotPlay(_gameState, isProcessing, _isPaused)) return;
    if (_checkInstantEnd()) return;

    isProcessing = true;
    notifyListeners();

    await _botOrchestrator.playBotTurn(_gameState!, _playerMMR, _isPaused, _currentContext, () async => _checkInstantEnd());

    if (_gameState?.phase == GamePhase.dutchCalled) {
      endGame();
      return;
    }

    isProcessing = false;
    notifyListeners();
    if (_gameState?.phase == GamePhase.playing) startReactionPhase();
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
    if (_gameState?.phase == GamePhase.reaction) _timerManager.resumeTimer(_gameState!, _isPaused);
    notifyListeners();
    if (_gameState != null && !_gameState!.currentPlayer.isHuman && _gameState!.phase == GamePhase.playing) {
      _checkAndPlayBotTurn();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FIN DE PARTIE
  // ═══════════════════════════════════════════════════════════════════════════

  void endGame() {
    if (_gameState == null) return;
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

    _trackingProvider.endPlayerRecording(
      slotId: _currentSlotId,
      usedSBMM: _playerMMR != null,
      gameState: _gameState!,
      finalScore: _gameState!.getFinalScore(human),
      finalRank: playerRank,
      calledDutch: calledDutch,
      wonDutch: wonDutch,
    );

    _addDutchHistory();
    _logFinalRanking(ranking);

    _statsService.saveGameResult(
      playerRank: playerRank,
      score: _gameState!.getFinalScore(human),
      calledDutch: calledDutch,
      wonDutch: wonDutch,
      hasEmptyHand: human.hand.isEmpty,
      slotId: _currentSlotId,
      isSBMM: _playerMMR != null,
      totalPlayers: _gameState!.players.length,
      isTournament: _gameState!.gameMode == GameMode.tournament,
      tournamentRound: _gameState!.gameMode == GameMode.tournament ? _gameState!.tournamentRound : 1,
      tournamentId: _tournamentManager.activeTournamentId,
      actionHistory: List<String>.from(_gameState!.actionHistory),
    );

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TOURNOI (délégué au TournamentManager)
  // ═══════════════════════════════════════════════════════════════════════════

  bool isHumanEliminatedInTournament() {
    if (_gameState == null) return false;
    return _tournamentManager.isHumanEliminated(_gameState!);
  }

  void finishTournamentForHuman() {
    if (_gameState == null) return;
    _tournamentManager.finishTournamentForHuman(_gameState!);
    _gameState!.tournamentRound = 3;
    notifyListeners();
  }

  int getTournamentRP(int finalPosition) => _tournamentManager.calculateRP(finalPosition);

  void startNextTournamentRound() {
    if (_gameState == null) return;
    _gameState!.updateCumulativeScores();
    _tournamentManager.updateCumulativeScores(_gameState!);
    
    List<Player> survivors = _tournamentManager.prepareSurvivorsForNextRound(_gameState!);
    if (survivors.length < 2) return;

    createNewGame(
      players: survivors,
      gameMode: GameMode.tournament,
      difficulty: _gameState!.difficulty,
      reactionTimeMs: _currentReactionTimeMs,
      tournamentRound: _gameState!.tournamentRound + 1,
      saveSlot: _currentSlotId,
      useSBMM: _playerMMR != null,
    );
  }

  void quitGame() {
    if (_gameState != null) {
      _statsService.saveGameResult(
        score: 999, playerRank: _gameState!.players.length, calledDutch: false, wonDutch: false,
        hasEmptyHand: false, isSBMM: _playerMMR != null, slotId: _currentSlotId,
        totalPlayers: _gameState!.players.length, isTournament: _gameState!.gameMode == GameMode.tournament,
        tournamentRound: _gameState!.tournamentRound, tournamentId: _tournamentManager.activeTournamentId,
        actionHistory: List<String>.from(_gameState!.actionHistory),
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
    if (_gameState!.isWaitingForSpecialPower) {
      _timerManager.pauseTimer(_gameState);
      Future.delayed(const Duration(milliseconds: 1300)).then((_) {
        if (_gameState?.isWaitingForSpecialPower == true) notifyListeners();
      });
    } else {
      startReactionPhase();
    }
  }

  bool _checkInstantEnd() {
    if (_gameState == null) return false;
    if (_gameState!.deck.isEmpty) {
      _refillDeckFromDiscard();
      if (_gameState!.deck.isEmpty) { endGame(); return true; }
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
    _gameState!.addToHistory("🔄 Pioche vide ! Défausse mélangée (${_gameState!.deck.length} cartes)");
    notifyListeners();
  }

  void _addDutchHistory() {
    if (_gameState!.dutchCallerId == null) return;
    Player dutchCaller = _gameState!.players.firstWhere((p) => p.id == _gameState!.dutchCallerId);
    if (dutchCaller.isHuman) return;
    
    List<Player> ranking = _gameState!.getFinalRanking();
    int dutchCallerRank = ranking.indexWhere((p) => p.id == dutchCaller.id) + 1;
    dutchCaller.dutchHistory.add(DutchAttempt(
      estimatedScore: dutchCaller.getEstimatedScore(),
      actualScore: _gameState!.getFinalScore(dutchCaller),
      won: dutchCallerRank == 1,
      opponentsCount: _gameState!.players.length - 1,
    ));
    if (dutchCaller.dutchHistory.length > 10) dutchCaller.dutchHistory.removeAt(0);
  }

  void _logFinalRanking(List<Player> ranking) {
    final ranksWithTies = _gameState!.getFinalRanksWithTies();
    _gameState!.addToHistory("🏁 Classement final");
    String rankEmoji(int rank) => rank == 1 ? "🥇" : rank == 2 ? "🥈" : rank == 3 ? "🥉" : "";
    for (int i = 0; i < ranking.length; i++) {
      final player = ranking[i];
      final rank = ranksWithTies[player.id] ?? (i + 1);
      final score = _gameState!.getFinalScore(player);
      final badge = rankEmoji(rank);
      final dutchTag = player.id == _gameState!.dutchCallerId ? " (DUTCH)" : "";
      _gameState!.addToHistory("${badge.isEmpty ? "" : "$badge "}#$rank ${player.name}$dutchTag — $score pts");
    }
  }

  @override
  void dispose() {
    _timerManager.dispose();
    super.dispose();
  }
}
