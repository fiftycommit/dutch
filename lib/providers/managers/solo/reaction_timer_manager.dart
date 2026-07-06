import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../../models/game_state.dart';

/// Manager dédié à la gestion des timers de réaction
/// Principe GRASP: Pure Fabrication - Responsabilité unique de gestion des timers
/// Principe SOLID: SRP - Ne gère que les timers de réaction
class ReactionTimerManager {
  Timer? _reactionTimer;
  int? _remainingReactionTimeMs;
  int _reactionDurationMs = 0;
  int _reactionStartMs = 0;
  final ValueNotifier<int> reactionTimeRemaining = ValueNotifier<int>(0);

  /// Callback appelé quand le timer se termine
  final VoidCallback onTimerEnd;

  /// Callback appelé pour notifier les changements
  final VoidCallback onTimerUpdate;

  ReactionTimerManager({
    required this.onTimerEnd,
    required this.onTimerUpdate,
  });

  /// Démarrer la phase de réaction
  void startReactionPhase(
      GameState gameState, int reactionTimeMs, bool isPaused) {
    if (isPaused) return;

    gameState.phase = GamePhase.reaction;
    gameState.reactionTimeRemaining = reactionTimeMs;
    reactionTimeRemaining.value = reactionTimeMs;
    _remainingReactionTimeMs = null;
    _reactionDurationMs = reactionTimeMs;
    _reactionStartMs = DateTime.now().millisecondsSinceEpoch;

    _reactionTimer?.cancel();

    _reactionTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      final remaining = _calculateRemainingMs();
      gameState.reactionTimeRemaining = remaining;
      reactionTimeRemaining.value = remaining;

      if (remaining <= 0) {
        timer.cancel();
        onTimerEnd();
        return;
      }
    });

    onTimerUpdate();
  }

  /// Mettre en pause le timer de réaction
  void pauseTimer(GameState? gameState) {
    if (_reactionTimer != null && _reactionTimer!.isActive) {
      _reactionTimer!.cancel();
      final remaining = _calculateRemainingMs();
      _remainingReactionTimeMs = remaining;
      if (gameState != null) {
        gameState.reactionTimeRemaining = remaining;
      }
      reactionTimeRemaining.value = remaining;
    }
  }

  /// Reprendre le timer de réaction
  void resumeTimer(GameState gameState, bool isPaused) {
    if (_remainingReactionTimeMs != null && _remainingReactionTimeMs! > 0) {
      gameState.reactionTimeRemaining = _remainingReactionTimeMs!;
      reactionTimeRemaining.value = _remainingReactionTimeMs!;
      _reactionDurationMs = _remainingReactionTimeMs!;
      _reactionStartMs = DateTime.now().millisecondsSinceEpoch;

      _reactionTimer?.cancel();
      _reactionTimer =
          Timer.periodic(const Duration(milliseconds: 30), (timer) {
        if (isPaused) {
          timer.cancel();
          return;
        }

        final remaining = _calculateRemainingMs();
        gameState.reactionTimeRemaining = remaining;
        reactionTimeRemaining.value = remaining;

        if (remaining <= 0) {
          timer.cancel();
          onTimerEnd();
          return;
        }
      });

      _remainingReactionTimeMs = null;
      onTimerUpdate();
    }
  }

  int _calculateRemainingMs() {
    if (_reactionDurationMs <= 0) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - _reactionStartMs;
    return (_reactionDurationMs - elapsed).clamp(0, _reactionDurationMs);
  }

  /// Annuler le timer
  void cancelTimer() {
    _reactionTimer?.cancel();
  }

  /// Nettoyer les ressources
  void dispose() {
    _reactionTimer?.cancel();
    reactionTimeRemaining.dispose();
  }
}
