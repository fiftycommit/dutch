import 'package:flutter/widgets.dart';

/// Interface commune pour les managers de timer (solo et multiplayer)
/// Principe SOLID: ISP - Interface segregation
abstract class ITimerManager {
  /// Temps de réaction configuré en ms
  int get reactionTimeMs;
  
  /// Démarre la phase de réaction
  void startReactionPhase();
  
  /// Met en pause le timer
  void pauseTimer();
  
  /// Reprend le timer
  void resumeTimer();
  
  /// Arrête le timer
  void stopTimer();
  
  /// Libère les ressources
  void dispose();
}

/// Classe de base avec logique commune pour les timers
/// Principe GRASP: Pure Fabrication
abstract class BaseTimerManager implements ITimerManager {
  final VoidCallback notifyListeners;
  
  int _reactionTimeMs = 3000;
  
  @override
  int get reactionTimeMs => _reactionTimeMs;
  
  BaseTimerManager({required this.notifyListeners});
  
  void setReactionTimeMs(int ms) {
    if (ms > 0) _reactionTimeMs = ms;
  }
  
  /// Calcule le temps restant interpolé localement
  int interpolateRemaining(int anchorRemaining, int anchorLocalMs) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - anchorLocalMs;
    return (anchorRemaining - elapsed).clamp(0, 600000);
  }
}
