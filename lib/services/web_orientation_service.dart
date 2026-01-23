import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:js_interop' if (dart.library.io) 'dart:js_interop';

/// Service pour gérer l'orientation de l'écran sur le web
class WebOrientationService {
  /// Tente de verrouiller l'écran en mode paysage sur le web
  static void lockLandscape() {
    if (!kIsWeb) return;
    
    try {
      _requestLandscape();
    } catch (e) {
      // L'API n'est pas supportée par ce navigateur
      debugPrint('Screen Orientation API not supported: $e');
    }
  }
  
  /// Déverrouille l'orientation de l'écran
  static void unlock() {
    if (!kIsWeb) return;
    
    try {
      _unlockOrientation();
    } catch (e) {
      debugPrint('Screen Orientation unlock failed: $e');
    }
  }
  
  static void debugPrint(String message) {
    // ignore: avoid_print
    print(message);
  }
}

@JS('screen.orientation.lock')
external JSPromise _lockOrientation(JSString orientation);

@JS('screen.orientation.unlock')
external void _unlockOrientationJS();

void _requestLandscape() {
  if (kIsWeb) {
    try {
      _lockOrientation('landscape'.toJS);
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
