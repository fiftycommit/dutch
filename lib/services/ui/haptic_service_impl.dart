import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/interfaces/i_haptic_service.dart';
import 'haptic_service.dart';

/// Implémentation concrète du service de feedback haptique (plateformes natives)
/// Principe SOLID: DIP - Implémente l'interface IHapticService
class HapticServiceImpl implements IHapticService {
  bool _isEnabled = true;

  @override
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  @override
  bool get isEnabled => _isEnabled;

  /// Déclenche un feedback haptique selon l'intensité demandée
  Future<void> trigger(HapticIntensity intensity) async {
    if (!_isEnabled) return;

    try {
      switch (intensity) {
        case HapticIntensity.light:
          await HapticFeedback.mediumImpact();
          break;

        case HapticIntensity.medium:
          await HapticFeedback.heavyImpact();
          break;

        case HapticIntensity.heavy:
          await HapticFeedback.heavyImpact();
          await Future.delayed(const Duration(milliseconds: 80));
          await HapticFeedback.heavyImpact();
          break;

        case HapticIntensity.error:
          await HapticFeedback.heavyImpact();
          await Future.delayed(const Duration(milliseconds: 100));
          await HapticFeedback.heavyImpact();
          await Future.delayed(const Duration(milliseconds: 100));
          await HapticFeedback.heavyImpact();
          break;

        case HapticIntensity.success:
          await HapticFeedback.mediumImpact();
          await Future.delayed(const Duration(milliseconds: 60));
          await HapticFeedback.mediumImpact();
          await Future.delayed(const Duration(milliseconds: 60));
          await HapticFeedback.mediumImpact();
          break;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Haptic non supporté: $e');
    }
  }

  @override
  Future<void> cardTap() => trigger(HapticIntensity.light);

  @override
  Future<void> buttonTap() => trigger(HapticIntensity.medium);

  @override
  Future<void> importantAction() => trigger(HapticIntensity.heavy);

  @override
  Future<void> error() => trigger(HapticIntensity.error);

  @override
  Future<void> success() => trigger(HapticIntensity.success);
}
