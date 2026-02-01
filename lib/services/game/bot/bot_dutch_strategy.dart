import 'dart:math';
import '../../../models/game_state.dart';
import '../../../models/player.dart';
import 'bot_difficulty.dart';
import 'bot_config.dart';
import 'bot_threat_analyzer.dart';
import 'bot_personality.dart';
import 'dutch_strategy_config.dart';

/// Stratégie de décision pour appeler Dutch
/// Principe GRASP: Information Expert - Décide quand appeler Dutch
class BotDutchStrategy {
  static final Random _random = Random();

  /// Détermine si le bot doit appeler Dutch
  static bool shouldCallDutch(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    BotGamePhase phase, {
    BotPersonality? personality,
  }) {
    int estimatedScore = bot.getEstimatedScore();
    final int decisionScore = _riskAdjustedScore(bot, estimatedScore);
    final int humanScore = _estimateHumanScore(gs, bot);
    BotBehavior? behavior = bot.botBehavior;

    if (phase == BotGamePhase.exploration) {
      return false;
    }

    double audacityBonus = _calculateAudacity(gs, bot, difficulty);
    double confidence = _calculateDutchConfidence(bot);
    double tournamentPressure = BotThreatAnalyzer.getTournamentPressure(gs, bot);

    if (personality != null) {
      final double ghostInfluence = personality.ghostInfluence;
      final double baseThreshold = personality.dutchThreshold;
      final double ghostThreshold = personality.ghostDutchThreshold;
      final double effectiveThreshold =
          baseThreshold + (ghostThreshold - baseThreshold) * ghostInfluence;

      final styleBoost =
          (personality.aggressiveness - personality.caution).clamp(-1.0, 1.0) *
              DutchStrategyConfig.styleBoostMultiplier;
      double adjustedThreshold = effectiveThreshold +
          audacityBonus +
          (confidence * 2) +
          tournamentPressure +
          styleBoost;

      // Pénalité liée aux classements récents (bots en difficulté)
      adjustedThreshold -= personality.rankPenalty * DutchStrategyConfig.rankPenaltyMultiplier;

      // Pénalité liée à l'écart de score vs humain
      adjustedThreshold -= _calculateScoreGapPenalty(
        decisionScore,
        humanScore,
        personality.scoreGapWeight,
      );

      // Pénalité renforcée en cas d'échecs Dutch récents
      adjustedThreshold -= _calculateFailurePenalty(bot, personality);

      // Qualité Dutch faible => exigence plus stricte
      adjustedThreshold -= (1.0 - personality.dutchQuality) * DutchStrategyConfig.dutchQualityPenaltyMultiplier;

      final double safetyMargin = _calculateSafetyMargin(personality);
      final double safeThreshold = adjustedThreshold - safetyMargin;

      if (difficulty.name == "Platine" || difficulty.name == "Or") {
        if (_shouldSmartDutch(
          gs,
          bot,
          difficulty,
          phase,
          decisionScore,
          audacityBonus,
          confidence,
          tournamentPressure,
        ) && decisionScore <= safeThreshold.round()) {
          return true;
        }
      }

      return decisionScore <= safeThreshold.round();
    }

    // NOUVELLE LOGIQUE : Bronze=peureux, Platine=stratégique
    if (difficulty.name == "Platine" || difficulty.name == "Or") {
      return _shouldSmartDutch(gs, bot, difficulty, phase, decisionScore, audacityBonus, confidence, tournamentPressure);
    }
    
    // Bronze/Argent : logique basée sur seuils
    int threshold = _getThresholdForBehavior(behavior, difficulty, phase);
    
    double adjustedThreshold = threshold + audacityBonus + (confidence * 2) + tournamentPressure;
    return decisionScore <= adjustedThreshold.round();
  }

  static int _getThresholdForBehavior(BotBehavior? behavior, BotDifficulty difficulty, BotGamePhase phase) {
    bool isBronze = difficulty.name == "Bronze";
    final basicT = DutchStrategyConfig.basic;
    final behaviorName = behavior?.toString().split('.').last ?? 'balanced';

    if (phase == BotGamePhase.endgame) {
      return basicT.endgameThreshold(behaviorName, isBronze);
    } else {
      return basicT.normalThreshold(behaviorName, isBronze);
    }
  }

  /// Stratégie intelligente de Dutch pour Or/Platine
  static bool _shouldSmartDutch(GameState gs, Player bot, BotDifficulty difficulty,
      BotGamePhase phase, int estimatedScore, double audacityBonus, double confidence, double tournamentPressure) {

    if (_isBluffingDutch(bot, difficulty, phase)) {
      return false;
    }

    int myCardCount = bot.hand.length;

    // Analyser l'avantage
    int minOpponentCards = 99;
    double avgOpponentScore = 0;
    int opponentCount = 0;

    for (var p in gs.players) {
      if (p.id != bot.id) {
        minOpponentCards = min(minOpponentCards, p.hand.length);
        avgOpponentScore += p.getEstimatedScore();
        opponentCount++;
      }
    }
    avgOpponentScore = opponentCount > 0 ? avgOpponentScore / opponentCount : 0;

    bool hasCardAdvantage = myCardCount < minOpponentCards;
    bool hasSignificantCardAdvantage =
        myCardCount <= minOpponentCards - DutchStrategyConfig.platinum.significantCardAdvantage;
    bool hasScoreAdvantage = estimatedScore < avgOpponentScore;

    final platinumT = DutchStrategyConfig.platinum;
    final goldT = DutchStrategyConfig.gold;

    if (difficulty.name == "Platine") {
      if (myCardCount <= 2 && estimatedScore <= platinumT.twoCardsMaxScore) return true;
      if (hasSignificantCardAdvantage && estimatedScore <= platinumT.significantAdvantageMaxScore) return true;
      if (hasCardAdvantage && hasScoreAdvantage && estimatedScore <= platinumT.dualAdvantageMaxScore) return true;
      if (estimatedScore <= platinumT.lowScoreMaxScore && myCardCount <= platinumT.lowScoreMaxCards) return true;
      if (phase == BotGamePhase.endgame && estimatedScore <= platinumT.endgameMaxScore) return true;
    }

    if (difficulty.name == "Or") {
      if (myCardCount <= 2 && estimatedScore <= goldT.twoCardsMaxScore) return true;
      if (hasSignificantCardAdvantage && hasScoreAdvantage && estimatedScore <= goldT.significantAdvantageMaxScore) return true;
      if (estimatedScore <= goldT.lowScoreMaxScore && myCardCount <= goldT.lowScoreMaxCards) return true;
      if (phase == BotGamePhase.endgame && estimatedScore <= goldT.endgameMaxScore && hasCardAdvantage) return true;
    }

    double totalBonus = audacityBonus + confidence * 2 + tournamentPressure;
    if (totalBonus >= DutchStrategyConfig.opportunisticBonusThreshold &&
        estimatedScore <= DutchStrategyConfig.opportunisticMaxScore) {
      return true;
    }

    return false;
  }

  static double _calculateAudacity(GameState gs, Player bot, BotDifficulty difficulty) {
    double audacity = 0.0;

    int cardCount = bot.hand.length;
    audacity += DutchStrategyConfig.cardCountAudacityBonus[cardCount] ?? 0.0;

    if (bot.consecutiveBadDraws >= DutchStrategyConfig.badDrawsThreshold) {
      audacity += (bot.consecutiveBadDraws - (DutchStrategyConfig.badDrawsThreshold - 1)) *
          DutchStrategyConfig.badDrawsAudacityPerDraw;
    }

    int dangerousOpponents = gs.players.where((p) => p.id != bot.id && p.hand.length <= 2).length;
    audacity -= dangerousOpponents * DutchStrategyConfig.dangerousOpponentPenalty;

    if (bot.botBehavior == BotBehavior.aggressive) {
      audacity += 1.0;
    } else if (bot.botBehavior == BotBehavior.balanced) {
      audacity -= 1.0;
    }

    final difficultyMultiplier = DutchStrategyConfig.difficultyAudacityMultiplier[difficulty.name] ?? 1.0;
    audacity *= difficultyMultiplier;

    return audacity.clamp(DutchStrategyConfig.minAudacity, DutchStrategyConfig.maxAudacity);
  }
  
  static double _calculateDutchConfidence(Player bot) {
    if (bot.dutchHistory.isEmpty) return 0.0;

    final count = DutchStrategyConfig.recentAttemptsCount;
    List<DutchAttempt> recentAttempts = bot.dutchHistory.length > count
        ? bot.dutchHistory.sublist(bot.dutchHistory.length - count)
        : bot.dutchHistory;

    int wins = recentAttempts.where((a) => a.won).length;
    double winRate = wins / recentAttempts.length;
    double avgAccuracy = recentAttempts.map((a) => a.accuracy).reduce((a, b) => a + b) / recentAttempts.length;
    double confidence = (winRate * DutchStrategyConfig.winRateWeight +
            avgAccuracy * DutchStrategyConfig.accuracyWeight) -
        DutchStrategyConfig.confidenceOffset;

    return confidence.clamp(DutchStrategyConfig.minConfidence, DutchStrategyConfig.maxConfidence);
  }

  static bool _isBluffingDutch(Player bot, BotDifficulty difficulty, BotGamePhase phase) {
    if (difficulty.name != "Platine" || phase != BotGamePhase.optimization) {
      return false;
    }
    if (bot.hand.length >= DutchStrategyConfig.bluffMinCards &&
        bot.hand.length <= DutchStrategyConfig.bluffMaxCards) {
      return _random.nextDouble() < DutchStrategyConfig.bluffProbability;
    }
    return false;
  }

  static int _estimateHumanScore(GameState gs, Player bot) {
    try {
      final human = gs.players.firstWhere((p) => p.isHuman);
      return human.getEstimatedScore();
    } catch (_) {
      return bot.getEstimatedScore();
    }
  }

  static double _calculateScoreGapPenalty(
    int botScore,
    int humanScore,
    double weight,
  ) {
    final gap = (botScore - humanScore).toDouble();
    final penalty = gap * weight;
    return penalty.clamp(
      DutchStrategyConfig.minScoreGapPenalty,
      DutchStrategyConfig.maxScoreGapPenalty,
    );
  }

  static double _calculateFailurePenalty(Player bot, BotPersonality personality) {
    if (bot.dutchHistory.isEmpty) return 0.0;
    final recentAttempts = bot.dutchHistory.length > 5
        ? bot.dutchHistory.sublist(bot.dutchHistory.length - 5)
        : bot.dutchHistory;
    final wins = recentAttempts.where((a) => a.won).length;
    final winRate = wins / recentAttempts.length;
    final failureRate = 1.0 - winRate;
    final qualityPenalty = (1.0 - personality.dutchQuality) * 2.0;
    return (failureRate * 4.0) + qualityPenalty;
  }

  static double _calculateSafetyMargin(BotPersonality personality) {
    final base = DutchStrategyConfig.safetyMarginBase +
        (1.0 - personality.dutchQuality) * DutchStrategyConfig.safetyMarginQualityMultiplier;
    return base.clamp(
      DutchStrategyConfig.minSafetyMargin,
      DutchStrategyConfig.maxSafetyMargin,
    );
  }

  static int _riskAdjustedScore(Player bot, int estimatedScore) {
    final int unknownCount =
        (bot.hand.length - bot.knownCardCount).clamp(0, bot.hand.length).toInt();
    if (unknownCount == 0) return estimatedScore;

    int penaltyPerCard;
    if (bot.hand.length <= 2) {
      penaltyPerCard = 3;
    } else if (bot.hand.length <= 3) {
      penaltyPerCard = 2;
    } else {
      penaltyPerCard = 1;
    }

    return estimatedScore + (unknownCount * penaltyPerCard);
  }
}
