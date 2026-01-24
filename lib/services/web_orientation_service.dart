import 'package:flutter/foundation.dart' show kIsWeb;

/// Service pour gérer l'orientation de l'écran sur le web
/// Sur les plateformes natives (iOS, Android), ces fonctions ne font rien
class WebOrientationService {
  /// Tente de verrouiller l'écran en mode paysage sur le web
  static void lockLandscape() {
    // Cette fonctionnalité n'est disponible que sur le web
    // Sur iOS/Android, l'orientation est gérée par SystemChrome
  }
  
  /// Déverrouille l'orientation de l'écran
  static void unlock() {
    // Cette fonctionnalité n'est disponible que sur le web
  }
}
