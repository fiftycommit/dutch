class DuelTuning {
  static final double platinumDuelMatchBonus = _doubleFromEnv(
    const String.fromEnvironment('DUEL_PLAT_MATCH_BONUS', defaultValue: ''),
    0.38,
  );
  static final double platinumDuelMatchEndgameBonus = _doubleFromEnv(
    const String.fromEnvironment('DUEL_PLAT_MATCH_ENDGAME_BONUS',
        defaultValue: ''),
    0.12,
  );

  static final int duelIntelStrongCapThreshold = _intFromEnv(
    const String.fromEnvironment('DUEL_INTEL_STRONG_CAP', defaultValue: ''),
    4,
  ).clamp(2, 8);
  static final int duelAntiHumanLikeThresholdDrop = _intFromEnv(
    const String.fromEnvironment('DUEL_ANTI_HUMAN_DROP', defaultValue: ''),
    1,
  ).clamp(0, 2);

  static final double duelHumanLikeSabotageGainFloor = _doubleFromEnv(
    const String.fromEnvironment('DUEL_HUMAN_SABOTAGE_FLOOR', defaultValue: ''),
    -0.05,
  );
  static final double duelHumanLikeUnknownGainFloor = _doubleFromEnv(
    const String.fromEnvironment('DUEL_HUMAN_UNKNOWN_FLOOR', defaultValue: ''),
    0.35,
  );

  static final int moiDuelDutchAllowance = _intFromEnv(
    const String.fromEnvironment('DUEL_MOI_DUTCH_ALLOW', defaultValue: ''),
    2,
  ).clamp(0, 4);
  static final int moiDuelDutchScoreCap = _intFromEnv(
    const String.fromEnvironment('DUEL_MOI_DUTCH_CAP', defaultValue: ''),
    6,
  ).clamp(2, 10);

  static final double humanLikeThreatBonusLowCards = _doubleFromEnv(
    const String.fromEnvironment('DUEL_HUMAN_THREAT_LOW', defaultValue: ''),
    6.0,
  );
  static final double humanLikeThreatBonusNormalCards = _doubleFromEnv(
    const String.fromEnvironment('DUEL_HUMAN_THREAT_NORMAL', defaultValue: ''),
    3.0,
  );

  static int _intFromEnv(String raw, int fallback) {
    if (raw.isEmpty) return fallback;
    return int.tryParse(raw) ?? fallback;
  }

  static double _doubleFromEnv(String raw, double fallback) {
    if (raw.isEmpty) return fallback;
    return double.tryParse(raw) ?? fallback;
  }
}
