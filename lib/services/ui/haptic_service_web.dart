import 'dart:js_interop';
import 'package:web/web.dart' as web;
import '../../core/interfaces/i_haptic_service.dart';

/// Implémentation web du service de feedback haptique
/// Utilise l'API Web Vibration (navigator.vibrate()) supportée sur Android Chrome
/// Les intensités sont simulées via PWM (Pulse-Width Modulation) :
/// des séquences vibration/pause dans des quanta de 20ms
class HapticServiceWeb implements IHapticService {
  bool _isEnabled = true;

  @override
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  @override
  bool get isEnabled => _isEnabled;

  /// Vérifie si l'API Vibration est disponible dans le navigateur
  bool get _isSupported {
    try {
      return web.window.navigator.vibrate(0.toJS);
    } catch (_) {
      return false;
    }
  }

  /// Déclenche une vibration simple (durée en ms)
  void _vibrate(int durationMs) {
    if (!_isEnabled || !_isSupported) return;
    try {
      web.window.navigator.vibrate(durationMs.toJS);
    } catch (_) {
      // API non disponible (ex: iOS Safari)
    }
  }

  /// Déclenche un pattern de vibration [vibrer, pause, vibrer, pause, ...]
  /// Enchaîne des appels simples avec des délais pour simuler un pattern
  Future<void> _vibratePattern(List<int> pattern) async {
    if (!_isEnabled || !_isSupported || pattern.isEmpty) return;
    try {
      for (int i = 0; i < pattern.length; i++) {
        if (i.isEven) {
          // Indices pairs = durée de vibration
          web.window.navigator.vibrate(pattern[i].toJS);
        }
        // Attendre la durée (vibration ou pause) avant le segment suivant
        if (i < pattern.length - 1) {
          await Future.delayed(Duration(milliseconds: pattern[i]));
        }
      }
    } catch (_) {
      // API non disponible
    }
  }

  @override
  Future<void> cardTap() async {
    // Feedback léger : vibration courte de 10ms
    _vibrate(10);
  }

  @override
  Future<void> buttonTap() async {
    // Feedback moyen : vibration de 25ms
    _vibrate(25);
  }

  @override
  Future<void> importantAction() async {
    // Feedback fort : vibration longue de 50ms
    _vibrate(50);
  }

  @override
  Future<void> error() async {
    // Double vibration forte : 50ms vibrer, 100ms pause, 50ms vibrer
    _vibratePattern([50, 100, 50]);
  }

  @override
  Future<void> success() async {
    // Triple vibration légère rapide : 10ms vibrer, 50ms pause, répété 3x
    _vibratePattern([10, 50, 10, 50, 10]);
  }
}

/// Fonction factory utilisée par l'import conditionnel
IHapticService createPlatformHapticService() => HapticServiceWeb();
