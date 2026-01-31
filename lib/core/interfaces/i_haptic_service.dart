/// Interface abstraite pour le service de feedback haptique
/// Principe SOLID: DIP - Dépendance sur une abstraction, pas une implémentation
/// Principe SOLID: ISP - Interface minimale et ciblée
abstract class IHapticService {
  /// Feedback léger pour un tap de carte
  Future<void> cardTap();

  /// Feedback moyen pour un bouton
  Future<void> buttonTap();

  /// Feedback fort pour une action importante
  Future<void> importantAction();

  /// Feedback d'erreur
  Future<void> error();

  /// Feedback de succès
  Future<void> success();

  /// Activer/désactiver le service
  void setEnabled(bool enabled);

  /// Vérifier si le service est activé
  bool get isEnabled;
}
