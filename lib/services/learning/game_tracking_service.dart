import '../../models/game_state.dart';
import '../../core/interfaces/i_learning_service.dart';
import '../../core/interfaces/i_tracking_service.dart';

/// Service dédié au tracking des données de jeu pour l'apprentissage ML
/// Principe GRASP: Pure Fabrication - Service technique qui n'existe pas dans le domaine métier
/// Principe SOLID: SRP - Responsabilité unique de tracking
/// Principe SOLID: DIP - Dépend de l'abstraction ILearningService, pas de l'implémentation concrète
class GameTrackingService implements ITrackingService {
  final ILearningService _learningService;

  GameTrackingService(this._learningService);

  @override
  void trackTurnIncrement(GameState gameState) {
    for (var player in gameState.players.where((p) => !p.isHuman)) {
      _learningService.incrementTurn(player.id);
    }
  }

  @override
  void trackCardDiscard(GameState gameState) {
    for (var player in gameState.players.where((p) => !p.isHuman)) {
      _learningService.recordDiscard(player.id);
    }
  }

  @override
  void initializeRound(GameState gameState) {
    for (var player in gameState.players.where((p) => !p.isHuman)) {
      _learningService.startNewRound(player.id);
    }
  }

  @override
  void startGameTracking({
    required String gameId,
    required GameState gameState,
    required bool usedSBMM,
  }) {
    for (var player in gameState.players.where((p) => !p.isHuman)) {
      _learningService.startGameRecording(
        gameId: gameId,
        player: player,
        gameState: gameState,
        usedSBMM: usedSBMM,
      );
      _learningService.startNewRound(player.id);
    }
  }

  @override
  Future<void> endBotTracking({
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
    await _learningService.endGameRecording(
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
}
