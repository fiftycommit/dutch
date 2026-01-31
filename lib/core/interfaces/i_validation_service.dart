import '../../models/game_state.dart';
import '../../models/player.dart';
import '../../services/game_state_validator.dart';

/// Interface abstraite pour le service de validation
/// Principe SOLID: DIP - Dépendre d'abstractions, pas de concrétions
abstract class IValidationService {
  /// Valider l'état complet du jeu
  ValidationResult validate(GameState gameState);

  /// Vérifier si une action est possible
  bool canPerformAction(GameState gameState, String actionType);

  /// Vérifier si un pouvoir peut être utilisé
  bool canUsePower(GameState gameState, Player player);
}
