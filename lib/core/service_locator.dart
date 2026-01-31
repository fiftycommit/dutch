import 'di/register_game_services.dart';
import 'di/register_ui_services.dart';
import 'di/register_multiplayer_services.dart';

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
  /// Délègue aux fichiers di/register_*_services.dart pour plus de clarté
  static void setupDefaultServices() {
    final locator = ServiceLocator();

    // Enregistrer les services par catégorie
    registerGameServices(locator);      // Logique métier pure
    registerUIServices(locator);        // Services UI (haptics, stats)
    registerMultiplayerServices(locator); // Services réseau (si singleton)
  }
}

/// Extension pour faciliter l'accès aux services
extension ServiceLocatorExtension on Object {
  T getService<T>() => ServiceLocator().get<T>();
}
