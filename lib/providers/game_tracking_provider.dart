import '../models/index.dart';
import '../services/index.dart';
import '../services/learning/ai_telemetry_service.dart';

/// Provider dédié au tracking des données de jeu pour le ML
/// Principe GRASP: Pure Fabrication - Responsabilité unique de tracking
/// Principe SOLID: SRP - Ne gère que le tracking, pas l'état du jeu
class GameTrackingProvider {
  final BotLearningService _botLearningService;
  final PlayerLearningService _playerLearningService;
  final BotTrainingService _botTrainingService;
  
  String? _currentGameId;
  int _humanActionCounter = 0;
  
  GameTrackingProvider({
    BotLearningService? botLearningService,
    PlayerLearningService? playerLearningService,
  })  : _botLearningService = botLearningService ?? BotLearningService(),
        _playerLearningService = playerLearningService ?? PlayerLearningService(),
        _botTrainingService = BotTrainingService();

  /// Démarrer l'enregistrement d'une partie
  void startGameRecording({
    required GameState gameState,
    required int slotId,
    required bool useSBMM,
  }) {
    _currentGameId = DateTime.now().millisecondsSinceEpoch.toString();
    _humanActionCounter = 0;
    
    // Démarrer le tracking pour le joueur humain
    _playerLearningService.startGame(gameId: _currentGameId!);
    
    // Démarrer le tracking pour tous les bots
    for (var player in gameState.players) {
      if (!player.isHuman) {
        _botLearningService.startGameRecording(
          gameId: _currentGameId!,
          player: player,
          gameState: gameState,
          usedSBMM: useSBMM,
        );
        _botLearningService.startNewRound(player.id);
      }
    }
  }

  /// Enregistrer une action du joueur humain
  void recordPlayerAction({
    required String actionType,
    required GameState gameState,
    required Map<String, dynamic> actionDetails,
    String? powerType,
    String? targetStrategy,
  }) {
    if (_currentGameId == null) return;
    
    final human = gameState.players.firstWhere((p) => p.isHuman);
    
    _playerLearningService.recordAction(
      gameId: _currentGameId!,
      actionType: actionType,
      turnNumber: _humanActionCounter++,
      gameState: gameState,
      human: human,
      actionDetails: actionDetails,
      powerType: powerType,
      targetStrategy: targetStrategy,
    );
    AiTelemetryService().onAction();
  }

  /// Mettre à jour le résultat de la dernière action du joueur
  void updateLastActionResult({
    required Map<String, dynamic> result,
  }) {
    if (_currentGameId == null) return;
    
    _playerLearningService.updateLastActionResult(
      gameId: _currentGameId!,
      result: result,
    );
  }

  /// Enregistrer une action du joueur avec son résultat immédiat (méthode combinée)
  void recordPlayerActionWithResult({
    required String actionType,
    required GameState gameState,
    required Map<String, dynamic> actionDetails,
    required Map<String, dynamic> result,
    String? powerType,
    String? targetStrategy,
  }) {
    if (_currentGameId == null) return;
    
    final human = gameState.players.firstWhere((p) => p.isHuman);
    
    _playerLearningService.recordAction(
      gameId: _currentGameId!,
      actionType: actionType,
      turnNumber: _humanActionCounter++,
      gameState: gameState,
      human: human,
      actionDetails: actionDetails,
      powerType: powerType,
      targetStrategy: targetStrategy,
    );
    AiTelemetryService().onAction();
    
    _playerLearningService.updateLastActionResult(
      gameId: _currentGameId!,
      result: result,
    );
  }

  /// Incrémenter le compteur de tours pour tous les bots
  void incrementBotTurns(GameState gameState) {
    for (var player in gameState.players.where((p) => !p.isHuman)) {
      _botLearningService.incrementTurn(player.id);
    }
  }

  /// Enregistrer une défausse pour tous les bots
  void recordBotDiscards(GameState gameState) {
    for (var player in gameState.players.where((p) => !p.isHuman)) {
      _botLearningService.recordDiscard(player.id);
    }
  }

  /// Terminer l'enregistrement d'une partie pour un bot
  Future<void> endBotRecording({
    required String botPlayerId,
    required int finalScore,
    required int finalRank,
    required bool calledDutch,
    required bool wonDutch,
    required int cardsAtDutch,
    required int scoreAtDutch,
    required int humanFinalScore,
    required int humanFinalHandSize,
    required int botFinalHandSize,
  }) async {
    await _botLearningService.endGameRecording(
      botPlayerId: botPlayerId,
      finalScore: finalScore,
      finalRank: finalRank,
      calledDutch: calledDutch,
      wonDutch: wonDutch,
      cardsAtDutch: cardsAtDutch,
      scoreAtDutch: scoreAtDutch,
      humanFinalScore: humanFinalScore,
      humanFinalHandSize: humanFinalHandSize,
      botFinalHandSize: botFinalHandSize,
    );
  }

  /// Terminer l'enregistrement d'une partie pour le joueur humain
  Future<PlayerProfile> endPlayerRecording({
    required int slotId,
    required bool usedSBMM,
    required GameState gameState,
    required int finalScore,
    required int finalRank,
    required bool calledDutch,
    required bool wonDutch,
  }) async {
    if (_currentGameId == null) {
      return PlayerProfile.defaultProfile(profileId: 'slot_$slotId');
    }

    final human = gameState.players.firstWhere((p) => p.isHuman);

    return await _playerLearningService.endGame(
      gameId: _currentGameId!,
      slotId: slotId,
      usedSBMM: usedSBMM,
      gameState: gameState,
      human: human,
      finalScore: finalScore,
      finalRank: finalRank,
      calledDutch: calledDutch,
      wonDutch: wonDutch,
    );
  }

  /// Démarrer l'enregistrement (version simplifiée pour le refactoring)
  void initTracking(GameState gameState, bool useSBMM) {
    _currentGameId = DateTime.now().millisecondsSinceEpoch.toString();
    _humanActionCounter = 0;
    
    _playerLearningService.startGame(gameId: _currentGameId!);
    
    for (var player in gameState.players.where((p) => !p.isHuman)) {
      _botLearningService.startGameRecording(
        gameId: _currentGameId!,
        player: player,
        gameState: gameState,
        usedSBMM: useSBMM,
      );
      _botLearningService.startNewRound(player.id);
    }
  }

  /// Finaliser l'enregistrement de tous les bots en fin de partie
  Future<void> finalizeBotRecordings(GameState gameState) async {
    if (_currentGameId == null) return;
    
    final players = List<Player>.from(gameState.players);
    players.sort((a, b) => a.calculateScore().compareTo(b.calculateScore()));
    
    final human = gameState.players.firstWhere((p) => p.isHuman);
    final humanFinalScore = gameState.getFinalScore(human);
    final humanFinalHandSize = human.hand.length;

    for (var player in gameState.players.where((p) => !p.isHuman)) {
      final rank = players.indexOf(player) + 1;
      final calledDutch = gameState.dutchCallerId == player.id;
      final wonDutch = calledDutch && rank == 1;
      
      await _botLearningService.endGameRecording(
        botPlayerId: player.id,
        finalScore: player.calculateScore(),
        finalRank: rank,
        calledDutch: calledDutch,
        wonDutch: wonDutch,
        cardsAtDutch: calledDutch ? player.hand.length : 0,
        scoreAtDutch: calledDutch ? player.calculateScore() : 0,
        humanFinalScore: humanFinalScore,
        humanFinalHandSize: humanFinalHandSize,
        botFinalHandSize: player.hand.length,
      );

      final botKey = BotTrainingService.buildBotKey(
        behavior: player.botBehavior,
        skillLevel: player.botSkillLevel,
      );
      await _botTrainingService.updateWithResult(
        botKey: botKey,
        numberOfPlayers: players.length,
        humanFinalScore: humanFinalScore,
        botFinalScore: player.calculateScore(),
      );
    }
  }

  /// Réinitialiser le tracking
  void reset() {
    _currentGameId = null;
    _humanActionCounter = 0;
  }
}
