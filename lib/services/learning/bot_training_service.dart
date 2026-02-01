import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/game_settings.dart';

class BotTrainingState {
  final int poorRankStreak;
  final int ghostGamesLeft;
  final double ghostInfluence;
  final double rankPenalty;

  const BotTrainingState({
    required this.poorRankStreak,
    required this.ghostGamesLeft,
    required this.ghostInfluence,
    required this.rankPenalty,
  });

  const BotTrainingState.empty()
      : poorRankStreak = 0,
        ghostGamesLeft = 0,
        ghostInfluence = 0.0,
        rankPenalty = 0.0;

  BotTrainingState copyWith({
    int? poorRankStreak,
    int? ghostGamesLeft,
    double? ghostInfluence,
    double? rankPenalty,
  }) {
    return BotTrainingState(
      poorRankStreak: poorRankStreak ?? this.poorRankStreak,
      ghostGamesLeft: ghostGamesLeft ?? this.ghostGamesLeft,
      ghostInfluence: ghostInfluence ?? this.ghostInfluence,
      rankPenalty: rankPenalty ?? this.rankPenalty,
    );
  }

  Map<String, dynamic> toJson() => {
        'poorRankStreak': poorRankStreak,
        'ghostGamesLeft': ghostGamesLeft,
        'ghostInfluence': ghostInfluence,
        'rankPenalty': rankPenalty,
      };

  factory BotTrainingState.fromJson(Map<String, dynamic> json) {
    return BotTrainingState(
      poorRankStreak: json['poorRankStreak'] ?? 0,
      ghostGamesLeft: json['ghostGamesLeft'] ?? 0,
      ghostInfluence: (json['ghostInfluence'] is num)
          ? (json['ghostInfluence'] as num).toDouble()
          : 0.0,
      rankPenalty: (json['rankPenalty'] is num)
          ? (json['rankPenalty'] as num).toDouble()
          : 0.0,
    );
  }
}

class BotTrainingService {
  static const String _prefsKey = 'bot_training_state';
  static const int _badRankThreshold = 3;
  static const int _ghostTrainingGames = 5; // Augmenté pour une transition plus douce
  static const double _maxGhostInfluence = 0.8;
  static const double _rankPenaltySmoothing = 0.7;

  /// Calcule l'influence ghost avec une courbe smooth (ease-out)
  ///
  /// Au lieu d'une décroissance linéaire, utilise une courbe qui :
  /// - Maintient une influence forte au début
  /// - Décroît progressivement vers la fin
  ///
  /// Formule : influence = maxInfluence * (ratio^0.5) pour ease-out
  /// ou cosinus pour une courbe encore plus douce
  static double _calculateSmoothInfluence(int gamesLeft, int totalGames) {
    if (gamesLeft <= 0) return 0.0;
    if (gamesLeft >= totalGames) return _maxGhostInfluence;

    final ratio = gamesLeft / totalGames;

    // Courbe ease-out quadratique : sqrt(ratio)
    // Cela donne : 5 games left -> 100%, 4 -> 89%, 3 -> 77%, 2 -> 63%, 1 -> 45%
    // Au lieu de linéaire : 5 -> 100%, 4 -> 80%, 3 -> 60%, 2 -> 40%, 1 -> 20%
    final smoothRatio = sqrt(ratio);

    return (_maxGhostInfluence * smoothRatio).clamp(0.0, _maxGhostInfluence);
  }

  static String buildBotKey({
    required BotBehavior? behavior,
    required BotSkillLevel? skillLevel,
  }) {
    final behaviorName = behavior == null ? 'unknown' : behavior.toString().split('.').last;
    final skillName = skillLevel == null ? 'unknown' : skillLevel.toString().split('.').last;
    return '${behaviorName}_$skillName';
  }

  Future<BotTrainingState> getStateForBot(
    String botKey, {
    bool consumeTrainingGame = false,
  }) async {
    final map = await _loadMap();
    final current = map[botKey] ?? const BotTrainingState.empty();

    if (!consumeTrainingGame || current.ghostGamesLeft <= 0) {
      return current;
    }

    final nextLeft = max(0, current.ghostGamesLeft - 1);
    final nextInfluence = _calculateSmoothInfluence(nextLeft, _ghostTrainingGames);

    final updated = current.copyWith(
      ghostGamesLeft: nextLeft,
      ghostInfluence: nextInfluence,
    );

    map[botKey] = updated;
    await _saveMap(map);
    return current;
  }

  Future<void> updateWithResult({
    required String botKey,
    required int numberOfPlayers,
    required int humanFinalScore,
    required int botFinalScore,
  }) async {
    final map = await _loadMap();
    final current = map[botKey] ?? const BotTrainingState.empty();

    final double gap = max(0, botFinalScore - humanFinalScore).toDouble();
    final double gapScale = max(8.0, 10.0 + (numberOfPlayers - 2) * 2.0);
    final double normalizedGap = (gap / gapScale).clamp(0.0, 1.0);

    final bool isBadResult = normalizedGap >= 0.4;
    final int streakIncrement = normalizedGap >= 0.75 ? 2 : 1;
    final int nextStreak = isBadResult
        ? current.poorRankStreak + streakIncrement
        : max(0, current.poorRankStreak - 1);

    final double smoothedRankPenalty =
        (current.rankPenalty * _rankPenaltySmoothing) +
            (normalizedGap * (1.0 - _rankPenaltySmoothing));

    int ghostGamesLeft = current.ghostGamesLeft;
    if (nextStreak >= _badRankThreshold) {
      ghostGamesLeft = max(ghostGamesLeft, _ghostTrainingGames);
    }

    // Utiliser la courbe smooth pour l'influence initiale
    final double ghostInfluence = _calculateSmoothInfluence(
      ghostGamesLeft,
      _ghostTrainingGames,
    );

    final updated = current.copyWith(
      poorRankStreak: nextStreak >= _badRankThreshold ? 0 : nextStreak,
      ghostGamesLeft: ghostGamesLeft,
      ghostInfluence: ghostInfluence,
      rankPenalty: smoothedRankPenalty.clamp(0.0, 1.0),
    );

    map[botKey] = updated;
    await _saveMap(map);
  }

  Future<Map<String, BotTrainingState>> _loadMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      final map = <String, BotTrainingState>{};
      for (final entry in decoded.entries) {
        if (entry.value is Map<String, dynamic>) {
          map[entry.key] = BotTrainingState.fromJson(
            Map<String, dynamic>.from(entry.value),
          );
        }
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveMap(Map<String, BotTrainingState> map) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonMap = <String, dynamic>{};
    for (final entry in map.entries) {
      jsonMap[entry.key] = entry.value.toJson();
    }
    await prefs.setString(_prefsKey, jsonEncode(jsonMap));
  }
}
