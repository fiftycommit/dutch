import '../../models/game_state.dart';

/// Interface abstraite pour le service de tracking
/// Principe SOLID: ISP - Interface Segregation Principle
/// Les clients ne doivent pas dépendre d'interfaces qu'ils n'utilisent pas
abstract class ITrackingService {
  /// Tracker l'incrémentation des tours pour tous les bots
  void trackTurnIncrement(GameState gameState);

  /// Tracker une défausse de carte
  void trackCardDiscard(GameState gameState);

  /// Initialiser un nouveau round
  void initializeRound(GameState gameState);

  /// Démarrer le tracking pour une partie
  void startGameTracking({
    required String gameId,
    required GameState gameState,
    required bool usedSBMM,
  });

  /// Terminer le tracking pour un bot
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
  });
}
