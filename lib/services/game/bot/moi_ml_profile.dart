import 'dart:math' as math;

/// Profil ML leger du comportement `moi`.
///
/// Ce fichier est mis a jour par `tool/train_moi_model_from_logs.dart`.
class MoiMlProfile {
  const MoiMlProfile._();

  static const bool enabled = true;

  static const int logsUsed = 51;
  static const int samplesUsed = 262;
  static const String trainedAtIso = '2026-02-21T01:11:29.295162Z';

  static const double _wBias = 0.5429235515;
  static const double _wDrawnPoints = -2.0653499614;
  static const double _wImprovement = 2.5677037133;
  static const double _wPreTurnScore = 1.7760716752;
  static const double _wStartHandScore = -0.2498906747;
  static const double _wHandSize = 1.4244716032;
  static const double _wTurnIndex = -1.3635279558;
  static const double _wPowersUsed = -0.2090563621;
  static const double _wPowerCard = -1.4953610654;

  static final double keepThreshold = _doubleFromEnv(
    const String.fromEnvironment('MOI_ML_KEEP_THRESHOLD', defaultValue: ''),
    0.7700000000,
  );
  static final double forceDiscardThreshold = _doubleFromEnv(
    const String.fromEnvironment('MOI_ML_FORCE_DISCARD_THRESHOLD',
        defaultValue: ''),
    0.4900000000,
  );
  static final int maxSoftWorsen = _intFromEnv(
    const String.fromEnvironment('MOI_ML_MAX_SOFT_WORSEN', defaultValue: ''),
    2,
  ).clamp(0, 4);

  static bool isPowerCardValue(String value) {
    return value == '7' || value == '10' || value == 'V' || value == 'JOKER';
  }

  static double predictKeepProbability({
    required int drawnPoints,
    required int improvement,
    required int preTurnScore,
    required int startHandScore,
    required int handSize,
    required int turnIndex,
    required int powersUsed,
    required bool isPowerCard,
  }) {
    final xDrawn = _normalize(drawnPoints.toDouble(), 0, 13);
    final xImprovement = _normalize(improvement.toDouble(), -13, 13);
    final xPreTurnScore = _normalize(preTurnScore.toDouble(), 0, 45);
    final xStartHandScore = _normalize(startHandScore.toDouble(), 0, 45);
    final xHandSize = _normalize(handSize.toDouble(), 1, 6);
    final xTurn = _normalize(turnIndex.toDouble(), 0, 15);
    final xPowers = _normalize(powersUsed.toDouble(), 0, 8);
    final xPowerCard = isPowerCard ? 1.0 : 0.0;

    final z = _wBias +
        (_wDrawnPoints * xDrawn) +
        (_wImprovement * xImprovement) +
        (_wPreTurnScore * xPreTurnScore) +
        (_wStartHandScore * xStartHandScore) +
        (_wHandSize * xHandSize) +
        (_wTurnIndex * xTurn) +
        (_wPowersUsed * xPowers) +
        (_wPowerCard * xPowerCard);
    return _sigmoid(z);
  }

  static int softWorsenTolerance({
    required int startHandScore,
    required int powersUsed,
    required bool isPowerCard,
  }) {
    int tolerance = 0;
    if (startHandScore >= 28) tolerance += 1;
    if (powersUsed >= 2) tolerance += 1;
    if (isPowerCard) tolerance += 1;
    if (tolerance > maxSoftWorsen) return maxSoftWorsen;
    return tolerance;
  }

  static double _normalize(double value, double minValue, double maxValue) {
    if (maxValue <= minValue) return 0.0;
    final clamped = value.clamp(minValue, maxValue);
    return ((clamped - minValue) / (maxValue - minValue)).toDouble();
  }

  static double _sigmoid(double x) {
    return 1.0 / (1.0 + math.exp(-x));
  }

  static int _intFromEnv(String raw, int fallback) {
    if (raw.isEmpty) return fallback;
    return int.tryParse(raw) ?? fallback;
  }

  static double _doubleFromEnv(String raw, double fallback) {
    if (raw.isEmpty) return fallback;
    return double.tryParse(raw) ?? fallback;
  }
}
