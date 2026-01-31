import '../../../models/player.dart';

class BotPersonality {
  final double aggressiveness;
  final double caution;
  final double riskTolerance;
  final double powerUsageRate;
  final double powerDefensiveRate;
  final double powerOffensiveRate;
  final double memoryAccuracy;
  final double memoryRetention;
  final double adaptability;
  final double decisionSpeedMs;
  final double dutchThreshold;
  final double dutchQuality;
  final double aggressivenessWinning;
  final double aggressivenessLosing;
  final double cautionWinning;
  final double cautionLosing;
  final String targetingStrategy;

  const BotPersonality({
    required this.aggressiveness,
    required this.caution,
    required this.riskTolerance,
    required this.powerUsageRate,
    required this.powerDefensiveRate,
    required this.powerOffensiveRate,
    required this.memoryAccuracy,
    required this.memoryRetention,
    required this.adaptability,
    required this.decisionSpeedMs,
    required this.dutchThreshold,
    required this.dutchQuality,
    required this.aggressivenessWinning,
    required this.aggressivenessLosing,
    required this.cautionWinning,
    required this.cautionLosing,
    required this.targetingStrategy,
  });

  static BotPersonality? fromBot(Player bot) {
    final params = bot.aiParameters;
    if (params == null || params.isEmpty) return null;

    double numParam(String key, double fallback) {
      final v = params[key];
      return v ?? fallback;
    }

    double clamp01(double v) => v.clamp(0.0, 1.0);

    return BotPersonality(
      aggressiveness: clamp01(numParam('aggressiveness', 0.5)),
      caution: clamp01(numParam('caution', 0.5)),
      riskTolerance: clamp01(numParam('riskTolerance', 0.5)),
      powerUsageRate: clamp01(numParam('powerUsageRate', 0.5)),
      powerDefensiveRate: clamp01(numParam('powerDefensiveRate', 0.5)),
      powerOffensiveRate: clamp01(numParam('powerOffensiveRate', 0.5)),
      memoryAccuracy: clamp01(numParam('memoryAccuracy', 0.7)),
      memoryRetention: clamp01(numParam('memoryRetention', 0.7)),
      adaptability: clamp01(numParam('adaptability', 0.5)),
      decisionSpeedMs: numParam('decisionSpeed', 2000.0).clamp(500.0, 10000.0),
      dutchThreshold: numParam('dutchThreshold', 15.0).clamp(5.0, 30.0),
      dutchQuality: clamp01(numParam('dutchQuality', 0.5)),
      aggressivenessWinning: clamp01(numParam('aggressiveness_winning', 0.5)),
      aggressivenessLosing: clamp01(numParam('aggressiveness_losing', 0.5)),
      cautionWinning: clamp01(numParam('caution_winning', 0.5)),
      cautionLosing: clamp01(numParam('caution_losing', 0.5)),
      targetingStrategy:
          (params['targetingStrategy'] as String?)?.trim().toLowerCase() ??
              'random',
    );
  }
}
