import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../../models/game_state.dart';

/// Gère le timer de réaction synchronisé avec le serveur multijoueur
/// Principe GRASP: Pure Fabrication - Responsabilité unique de gestion du timer
class MultiplayerTimerManager {
  final VoidCallback _notifyListeners;
  final int Function() _getLatencyMs;
  final int Function() _getServerNowMs;

  Timer? _reactionTick;
  int _reactionAnchorRemainingMs = 0;
  int _reactionAnchorLocalMs = 0;
  int _reactionTimeMs = 3000;

  int get reactionTimeMs => _reactionTimeMs;

  MultiplayerTimerManager({
    required VoidCallback notifyListeners,
    required int Function() getLatencyMs,
    required int Function() getServerNowMs,
  })  : _notifyListeners = notifyListeners,
        _getLatencyMs = getLatencyMs,
        _getServerNowMs = getServerNowMs;

  void setReactionTimeMs(int ms) {
    if (ms <= 0) return;
    _reactionTimeMs = ms;
  }

  /// Ajuste le temps restant en fonction de la latence réseau
  int adjustForLatency(int remaining) {
    final latency = _getLatencyMs();
    if (latency <= 0) return remaining;
    final adjusted = remaining - (latency ~/ 2);
    return adjusted < 0 ? 0 : adjusted;
  }

  /// Applique une mise à jour du timer depuis le serveur
  void applyServerUpdate(int remaining, GameState? gameState) {
    final adjusted = adjustForLatency(remaining);
    _reactionAnchorRemainingMs = adjusted;
    _reactionAnchorLocalMs = DateTime.now().millisecondsSinceEpoch;
    if (gameState != null) {
      gameState.reactionTimeRemaining = adjusted;
    }
    _startTicker(gameState);
    _notifyListeners();
  }

  /// Synchronise la phase de réaction avec l'état du jeu
  void syncReactionPhase(GameState? gameState) {
    if (gameState == null) return;

    if (gameState.phase == GamePhase.reaction) {
      final startTime = gameState.reactionStartTime;
      if (startTime != null) {
        final serverNow = _getServerNowMs();
        final elapsed = serverNow - startTime.millisecondsSinceEpoch;
        final remaining = (_reactionTimeMs - elapsed).clamp(0, 600000);
        applyServerUpdate(remaining, gameState);
        return;
      }
      applyServerUpdate(gameState.reactionTimeRemaining, gameState);
      return;
    }

    stopTicker();
    _notifyListeners();
  }

  void _startTicker(GameState? gameState) {
    if (_reactionTick != null) return;
    _reactionTick = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _tick(gameState),
    );
  }

  void stopTicker() {
    _reactionTick?.cancel();
    _reactionTick = null;
  }

  void _tick(GameState? gameState) {
    if (gameState == null || gameState.phase != GamePhase.reaction) {
      stopTicker();
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - _reactionAnchorLocalMs;
    final remaining = (_reactionAnchorRemainingMs - elapsed).clamp(0, 600000);

    if (remaining != gameState.reactionTimeRemaining) {
      gameState.reactionTimeRemaining = remaining;
      _notifyListeners();
    }
  }

  void reset() {
    stopTicker();
    _reactionTimeMs = 3000;
    _reactionAnchorRemainingMs = 0;
    _reactionAnchorLocalMs = 0;
  }

  void dispose() {
    stopTicker();
  }
}
