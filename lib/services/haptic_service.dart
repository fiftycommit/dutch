import 'package:flutter/services.dart';

enum HapticIntensity {
  light,    // Clic léger
  medium,   // Clic moyen
  heavy,    // Clic fort
  error,    // Vibration d'erreur
  success,  // Vibration de succès
}

class HapticService {
  static bool _isEnabled = true;

  // Activer/désactiver le feedback haptique
  static void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  static bool get isEnabled => _isEnabled;

  // Feedback haptique selon l'intensité
  static Future<void> trigger(HapticIntensity intensity) async {
    if (!_isEnabled) return;

    try {
      switch (intensity) {
        case HapticIntensity.light:
          await HapticFeedback.selectionClick();
          break;

        case HapticIntensity.medium:
          await HapticFeedback.mediumImpact();
          break;

        case HapticIntensity.heavy:
          await HapticFeedback.heavyImpact();
          break;

        case HapticIntensity.error:
          // Double vibration pour erreur
          await HapticFeedback.heavyImpact();
          await Future.delayed(const Duration(milliseconds: 100));
          await HapticFeedback.heavyImpact();
          break;

        case HapticIntensity.success:
          // Triple vibration légère pour succès
          await HapticFeedback.lightImpact();
          await Future.delayed(const Duration(milliseconds: 50));
          await HapticFeedback.lightImpact();
          await Future.delayed(const Duration(milliseconds: 50));
          await HapticFeedback.lightImpact();
          break;
      }
    } catch (e) {
      // Ignorer les erreurs (certains appareils ne supportent pas le haptique)
    }
  }

  // Raccourcis pour les cas d'usage courants
  static Future<void> cardTap() => trigger(HapticIntensity.light);
  static Future<void> buttonTap() => trigger(HapticIntensity.medium);
  static Future<void> importantAction() => trigger(HapticIntensity.heavy);
  static Future<void> error() => trigger(HapticIntensity.error);
  static Future<void> success() => trigger(HapticIntensity.success);
}
