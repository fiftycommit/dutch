import 'package:flutter/services.dart';

enum HapticIntensity {
  light,
  medium,
  heavy,
  error,
  success,
}

class HapticService {
  static bool _isEnabled = true;

  static void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  static bool get isEnabled => _isEnabled;

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
          await HapticFeedback.heavyImpact();
          await Future.delayed(const Duration(milliseconds: 100));
          await HapticFeedback.heavyImpact();
          break;

        case HapticIntensity.success:
          await HapticFeedback.lightImpact();
          await Future.delayed(const Duration(milliseconds: 50));
          await HapticFeedback.lightImpact();
          await Future.delayed(const Duration(milliseconds: 50));
          await HapticFeedback.lightImpact();
          break;
      }
    } catch (e) {
      // Certains appareils ne supportent pas le haptique
    }
  }

  static Future<void> cardTap() => trigger(HapticIntensity.light);
  static Future<void> buttonTap() => trigger(HapticIntensity.medium);
  static Future<void> importantAction() => trigger(HapticIntensity.heavy);
  static Future<void> error() => trigger(HapticIntensity.error);
  static Future<void> success() => trigger(HapticIntensity.success);
}
