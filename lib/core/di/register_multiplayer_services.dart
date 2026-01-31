import '../service_locator.dart';

/// Enregistrement des services multiplayer (réseau, socket)
/// Ces services gèrent la communication avec le serveur
void registerMultiplayerServices(ServiceLocator locator) {
  // Service multiplayer principal
  // Note: Ce service est souvent créé à la demande par les providers
  // mais peut être pré-enregistré si nécessaire
  
  // Pour l'instant, MultiplayerService est créé directement dans
  // MultiplayerGameProvider car il a besoin d'une gestion de lifecycle
  // spécifique (connexion/déconnexion)
  
  // Si besoin d'un singleton partagé :
  // final multiplayerService = MultiplayerService();
  // locator.register<MultiplayerService>(multiplayerService);
}
