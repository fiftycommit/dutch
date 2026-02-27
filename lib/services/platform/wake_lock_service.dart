import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Empêche la mise en veille de l'écran pendant le jeu.
/// Utilise un compteur de références pour gérer plusieurs écrans de jeu.
class WakeLockService {
  WakeLockService._();
  static final WakeLockService instance = WakeLockService._();

  int _refCount = 0;

  /// Activer le wake lock (appelé quand on entre dans un écran de jeu)
  Future<void> enable() async {
    _refCount++;
    if (_refCount == 1) {
      try {
        await WakelockPlus.enable();
        if (kDebugMode) debugPrint('[WakeLock] enabled');
      } catch (e) {
        if (kDebugMode) debugPrint('[WakeLock] enable error: $e');
      }
    }
  }

  /// Désactiver le wake lock (appelé quand on quitte un écran de jeu)
  Future<void> disable() async {
    _refCount = (_refCount - 1).clamp(0, 999);
    if (_refCount == 0) {
      try {
        await WakelockPlus.disable();
        if (kDebugMode) debugPrint('[WakeLock] disabled');
      } catch (e) {
        if (kDebugMode) debugPrint('[WakeLock] disable error: $e');
      }
    }
  }
}
