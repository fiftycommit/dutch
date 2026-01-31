import 'interfaces/i_learning_service.dart';
import 'interfaces/i_tracking_service.dart';
import 'interfaces/i_validation_service.dart';
import '../services/learning/bot_learning_service.dart';
import '../services/learning/player_learning_service.dart';
import '../services/learning/game_tracking_service.dart';
import '../services/game/game_state_validator.dart';

/// Service Locator pour gérer les dépendances
/// Principe GRASP: Pure Fabrication - Service technique de gestion des dépendances
/// Principe SOLID: DIP - Inversion de dépendances via un conteneur
class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  // Registre des services
  final Map<Type, dynamic> _services = {};

  /// Enregistrer un service
  void register<T>(T service) {
    _services[T] = service;
  }

  /// Récupérer un service
  T get<T>() {
    final service = _services[T];
    if (service == null) {
      throw Exception('Service de type $T non enregistré');
    }
    return service as T;
  }

  /// Vérifier si un service est enregistré
  bool isRegistered<T>() {
    return _services.containsKey(T);
  }

  /// Réinitialiser tous les services (utile pour les tests)
  void reset() {
    _services.clear();
  }

  /// Configuration par défaut des services
  static void setupDefaultServices() {
    final locator = ServiceLocator();

    // Services d'apprentissage
    final botLearningService = BotLearningService();
    final playerLearningService = PlayerLearningService();

    // Enregistrer les services avec leurs interfaces
    locator.register<ILearningService>(botLearningService);
    locator.register<IPlayerLearningService>(playerLearningService);

    // Service de tracking (dépend de ILearningService)
    final trackingService = GameTrackingService(botLearningService);
    locator.register<ITrackingService>(trackingService);

    // Service de validation
    final validationService = GameStateValidator();
    locator.register<IValidationService>(validationService);
  }
}

/// Extension pour faciliter l'accès aux services
extension ServiceLocatorExtension on Object {
  T getService<T>() => ServiceLocator().get<T>();
}
