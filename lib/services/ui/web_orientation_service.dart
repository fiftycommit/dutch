import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Service pour gérer l'orientation et le fullscreen sur le web
/// Utilise les API Screen Orientation et Fullscreen du navigateur
class WebOrientationService {
  /// Passe en fullscreen puis verrouille l'écran en mode paysage
  static void lockLandscape({bool requestFullscreen = true}) {
    try {
      final doc = web.document;
      final element = doc.documentElement;
      if (element == null) return;

      // Cas sans fullscreen auto: on tente juste le lock d'orientation.
      if (!requestFullscreen) {
        _lockOrientation();
        return;
      }

      // Si déjà fullscreen, verrouiller l'orientation directement
      if (doc.fullscreenElement != null) {
        _lockOrientation();
        return;
      }

      // Passer en fullscreen d'abord, puis verrouiller l'orientation
      element
          .requestFullscreen()
          .toDart
          .then((_) => _lockOrientation())
          .catchError((_) {});
    } catch (_) {
      // API non disponible sur certains navigateurs
    }
  }

  /// Verrouille l'orientation en paysage
  static void _lockOrientation() {
    try {
      web.window.screen.orientation
          .lock('landscape')
          .toDart
          .then((_) {})
          .catchError((_) {});
    } catch (_) {}
  }

  /// Déverrouille l'orientation et quitte le fullscreen
  static void unlock() {
    try {
      web.window.screen.orientation.unlock();
    } catch (_) {}

    try {
      if (web.document.fullscreenElement != null) {
        web.document.exitFullscreen().toDart.then((_) {}).catchError((_) {});
      }
    } catch (_) {
      // API non disponible sur certains navigateurs
    }
  }
}
