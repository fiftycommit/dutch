import 'dart:math';
import '../../../models/game_state.dart';
import '../../../models/game_settings.dart';
import '../../../models/player.dart';
import 'bot_difficulty.dart';
import 'bot_config.dart';
import 'bot_threat_analyzer.dart';

/// Stratégie de décision pour appeler Dutch
/// Principe GRASP: Information Expert - Décide quand appeler Dutch
class BotDutchStrategy {
  static final Random _random = Random();

  /// Détermine si le bot doit appeler Dutch
  static bool shouldCallDutch(GameState gs, Player bot, BotDifficulty difficulty, BotGamePhase phase) {
    int estimatedScore = bot.getEstimatedScore();
    BotBehavior? behavior = bot.botBehavior;

    if (phase == BotGamePhase.exploration) {
      return false;
    }

    double audacityBonus = _calculateAudacity(gs, bot, difficulty);
    double confidence = _calculateDutchConfidence(bot);
    double tournamentPressure = BotThreatAnalyzer.getTournamentPressure(gs, bot);

    // NOUVELLE LOGIQUE : Bronze=peureux, Platine=stratégique
    if (difficulty.name == "Platine" || difficulty.name == "Or") {
      return _shouldSmartDutch(gs, bot, difficulty, phase, estimatedScore, audacityBonus, confidence, tournamentPressure);
    }
    
    // Bronze/Argent : logique basée sur seuils
    int threshold = _getThresholdForBehavior(behavior, difficulty, phase);
    
    double adjustedThreshold = threshold + audacityBonus + (confidence * 2) + tournamentPressure;
    return estimatedScore <= adjustedThreshold.round();
  }

  static int _getThresholdForBehavior(BotBehavior? behavior, BotDifficulty difficulty, BotGamePhase phase) {
    bool isBronze = difficulty.name == "Bronze";
    
    if (phase == BotGamePhase.endgame) {
      switch (behavior) {
        case BotBehavior.fast:
          return isBronze ? 3 : 5;
        case BotBehavior.aggressive:
        case BotBehavior.balanced:
        default:
          return isBronze ? 2 : 4;
      }
    } else {
      switch (behavior) {
        case BotBehavior.fast:
          return isBronze ? 2 : 4;
        case BotBehavior.aggressive:
        case BotBehavior.balanced:
        default:
          return isBronze ? 1 : 3;
      }
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
    bool hasSignificantCardAdvantage = myCardCount <= minOpponentCards - 2;
    bool hasScoreAdvantage = estimatedScore < avgOpponentScore;
    
    if (difficulty.name == "Platine") {
      if (myCardCount <= 2 && estimatedScore <= 6) return true;
      if (hasSignificantCardAdvantage && estimatedScore <= 10) return true;
      if (hasCardAdvantage && hasScoreAdvantage && estimatedScore <= 8) return true;
      if (estimatedScore <= 4 && myCardCount <= 3) return true;
      if (phase == BotGamePhase.endgame && estimatedScore <= 6) return true;
    }
    
    if (difficulty.name == "Or") {
      if (myCardCount <= 2 && estimatedScore <= 5) return true;
      if (hasSignificantCardAdvantage && hasScoreAdvantage && estimatedScore <= 8) return true;
      if (estimatedScore <= 3 && myCardCount <= 3) return true;
      if (phase == BotGamePhase.endgame && estimatedScore <= 5 && hasCardAdvantage) return true;
    }
    
    double totalBonus = audacityBonus + confidence * 2 + tournamentPressure;
    if (totalBonus >= 3 && estimatedScore <= 8) return true;
    
    return false;
  }

  static double _calculateAudacity(GameState gs, Player bot, BotDifficulty difficulty) {
    double audacity = 0.0;
    
    int cardCount = bot.hand.length;
    if (cardCount == 1) audacity += 3.0;
    else if (cardCount == 2) audacity += 2.0;
    else if (cardCount == 3) audacity += 1.0;
    
    if (bot.consecutiveBadDraws >= 3) {
      audacity += (bot.consecutiveBadDraws - 2) * 0.5;
    }
    
    int dangerousOpponents = gs.players.where((p) => p.id != bot.id && p.hand.length <= 2).length;
    audacity -= dangerousOpponents * 0.5;
    
    if (bot.botBehavior == BotBehavior.aggressive) audacity += 1.0;
    else if (bot.botBehavior == BotBehavior.balanced) audacity -= 1.0;
    
    if (difficulty.name == "Bronze") audacity *= 0.5;
    else if (difficulty.name == "Platine") audacity *= 1.2;
    
    return audacity.clamp(-3.0, 5.0);
  }
  
  static double _calculateDutchConfidence(Player bot) {
    if (bot.dutchHistory.isEmpty) return 0.0;
    
    List<DutchAttempt> recentAttempts = bot.dutchHistory.length > 5 
        ? bot.dutchHistory.sublist(bot.dutchHistory.length - 5) 
        : bot.dutchHistory;
    
    int wins = recentAttempts.where((a) => a.won).length;
    double winRate = wins / recentAttempts.length;
    double avgAccuracy = recentAttempts.map((a) => a.accuracy).reduce((a, b) => a + b) / recentAttempts.length;
    double confidence = (winRate * 0.7 + avgAccuracy * 0.3) - 0.5;
    
    return confidence.clamp(-1.0, 1.0);
  }

  static bool _isBluffingDutch(Player bot, BotDifficulty difficulty, BotGamePhase phase) {
    if (difficulty.name != "Platine" || phase != BotGamePhase.optimization) {
      return false;
    }
    if (bot.hand.length >= 3 && bot.hand.length <= 4) {
      return _random.nextDouble() < 0.20;
    }
    return false;
  }
}
