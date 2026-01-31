import '../../models/game_state.dart';
import '../../models/player.dart';
import '../../core/interfaces/i_validation_service.dart';

/// Service de validation de la cohérence de l'état du jeu
/// Principe GRASP: Pure Fabrication - Service technique de validation
/// Principe SOLID: SRP - Responsabilité unique de validation
/// Principe SOLID: DIP - Implémente l'interface IValidationService
class GameStateValidator implements IValidationService {
  @override
  ValidationResult validate(GameState gameState) {
    final errors = <String>[];

    // Vérifier que le joueur courant existe
    if (gameState.currentPlayerIndex < 0 || 
        gameState.currentPlayerIndex >= gameState.players.length) {
      errors.add('Index du joueur courant invalide: ${gameState.currentPlayerIndex}');
    }

    // Vérifier que tous les joueurs ont des mains valides
    for (var player in gameState.players) {
      if (player.hand.isEmpty && gameState.phase != GamePhase.ended) {
        errors.add('${player.name} a une main vide en cours de partie');
      }
      
      if (player.hand.length != player.knownCards.length) {
        errors.add('${player.name}: taille main (${player.hand.length}) != knownCards (${player.knownCards.length})');
      }
    }

    // Vérifier que la pioche + défausse + mains = deck complet
    final totalCards = gameState.deck.length + 
                      gameState.discardPile.length + 
                      gameState.players.fold<int>(0, (sum, p) => sum + p.hand.length);
    
    // Note: Le nombre de cartes dépend du nombre de jokers configurés
    // On vérifie juste qu'il y a au moins 52 cartes
    if (totalCards < 52 && gameState.phase != GamePhase.ended) {
      errors.add('Nombre total de cartes trop faible: $totalCards (minimum: 52)');
    }

    // Vérifier que Dutch n'est pas appelé plusieurs fois
    if (gameState.dutchCallerId != null) {
      final dutchCallers = gameState.players.where((p) => p.id == gameState.dutchCallerId).length;
      if (dutchCallers != 1) {
        errors.add('Dutch caller invalide: $dutchCallers joueurs trouvés');
      }
    }

    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
    );
  }

  @override
  bool canPerformAction(GameState gameState, String actionType) {
    switch (actionType) {
      case 'draw':
        return gameState.phase == GamePhase.playing && 
               gameState.drawnCard == null;
      
      case 'replace':
      case 'discard':
        return gameState.phase == GamePhase.playing && 
               gameState.drawnCard != null;
      
      case 'match':
        return gameState.phase == GamePhase.reaction && 
               gameState.discardPile.isNotEmpty;
      
      case 'dutch':
        return gameState.dutchCallerId == null;
      
      default:
        return false;
    }
  }

  @override
  bool canUsePower(GameState gameState, Player player) {
    return gameState.isWaitingForSpecialPower && 
           gameState.specialCardToActivate != null &&
           gameState.currentPlayer.id == player.id;
  }
}

/// Résultat de validation
class ValidationResult {
  final bool isValid;
  final List<String> errors;

  ValidationResult({
    required this.isValid,
    required this.errors,
  });

  @override
  String toString() {
    if (isValid) return 'État valide';
    return 'État invalide:\n${errors.join('\n')}';
  }
}
