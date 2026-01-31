import '../../models/player.dart';
import '../../models/game_state.dart';
import '../../models/player_learning_data.dart';

/// Interface abstraite pour les services d'apprentissage
/// Principe SOLID: DIP - Les modules de haut niveau ne dépendent pas des modules de bas niveau
/// Les deux dépendent d'abstractions
abstract class ILearningService {
  /// Démarrer l'enregistrement d'une partie
  void startGameRecording({
    required String gameId,
    required Player player,
    required GameState gameState,
    required bool usedSBMM,
  });

  /// Incrémenter le compteur de tours
  void incrementTurn(String playerId);

  /// Enregistrer une défausse
  void recordDiscard(String playerId);

  /// Démarrer un nouveau round
  void startNewRound(String playerId);

  /// Terminer l'enregistrement d'une partie
  Future<void> endGameRecording({
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

/// Interface pour le service d'apprentissage des joueurs
abstract class IPlayerLearningService {
  /// Démarrer une partie
  void startGame({required String gameId});

  /// Enregistrer une action du joueur
  void recordAction({
    required String gameId,
    required String actionType,
    required int turnNumber,
    required GameState gameState,
    required Player human,
    required Map<String, dynamic> actionDetails,
  });

  /// Mettre à jour le résultat de la dernière action
  void updateLastActionResult({
    required String gameId,
    required Map<String, dynamic> result,
  });

  /// Terminer une partie
  Future<PlayerProfile> endGame({
    required String gameId,
    required int slotId,
    required bool usedSBMM,
    required GameState gameState,
    required Player human,
    required int finalScore,
    required int finalRank,
    required bool calledDutch,
    required bool wonDutch,
  });
}
