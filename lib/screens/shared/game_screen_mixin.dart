import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/services/ui/web_orientation_service.dart';

// Re-export des classes de layout pour compatibilité
export 'package:dutch_game/widgets/game/game_layout_mixin.dart';

/// Mixin partagé entre GameScreen (solo) et MultiplayerGameScreen
/// Contient la logique écran (navigation, orientation)
/// Les screens doivent aussi mixer GameLayoutMixin pour les helpers layout
mixin GameScreenMixin<T extends StatefulWidget> on State<T> {
  
  // ============================================================
  // END GAME NAVIGATION
  // ============================================================

  bool _hasNavigatedToEndMixin = false;

  /// Remet le flag de navigation à false (utile si on revient sur l'écran)
  void resetEndGameNavigation() {
    _hasNavigatedToEndMixin = false;
  }

  /// Navigue vers l'écran de fin de partie si les conditions sont remplies
  /// Retourne true si la navigation a été effectuée
  bool maybeNavigateToEnd({
    required GameState gameState,
    String? routeLocation,
    Widget? destination,
  }) {
    assert(routeLocation != null || destination != null,
        'routeLocation or destination must be provided');
    if (_hasNavigatedToEndMixin) return false;
    if (gameState.phase != GamePhase.ended) return false;
    if (ModalRoute.of(context)?.isCurrent != true || !mounted) return false;

    _hasNavigatedToEndMixin = true;
    if (routeLocation != null) {
      context.go(routeLocation);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => destination!),
      );
    }
    return true;
  }

  // ============================================================
  // ORIENTATION HANDLING
  // ============================================================

  void lockLandscapeOrientation() {
    if (kIsWeb) {
      WebOrientationService.lockLandscape();
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void unlockOrientation() {
    if (kIsWeb) {
      WebOrientationService.unlock();
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  bool shouldShowRotateOverlay(BuildContext context) {
    if (!kIsWeb) return false;
    final size = MediaQuery.of(context).size;
    return size.height > size.width;
  }
}
