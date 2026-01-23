import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:js_interop' if (dart.library.io) 'dart:js_interop';

/// Service pour gérer l'orientation de l'écran sur le web
class WebOrientationService {
  /// Tente de verrouiller l'écran en mode paysage sur le web
  static void lockLandscape() {
    if (!kIsWeb) return;
    _requestLandscape();
  }
  
  /// Déverrouille l'orientation de l'écran
  static void unlock() {
    if (!kIsWeb) return;
    _unlockOrientation();
  }
}

@JS('screen.orientation.lock')
external JSPromise _lockOrientation(JSString orientation);

@JS('screen.orientation.unlock')
external void _unlockOrientationJS();

void _requestLandscape() {
  if (kIsWeb) {
    try {
      // Convertir la JSPromise et capturer l'erreur silencieusement
      _lockOrientation('landscape'.toJS).toDart.catchError((e) {
        // Ignorer silencieusement - l'API n'est pas supportée sur tous les appareils
        return null;
      });
    } catch (e) {
      // Silently fail - not all browsers support this
    }
  }
}

void _unlockOrientation() {
  if (kIsWeb) {
    try {
      _unlockOrientationJS();
    } catch (e) {
      // Silently fail
    }
  }
}
