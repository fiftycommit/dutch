import 'dart:math';
import '../../../models/game_state.dart';
import '../../../models/game_settings.dart';
import '../../../models/player.dart';
import 'bot_difficulty.dart';

export '../../../models/game_settings.dart' show BotBehavior, BotSkillLevel;

/// Phases de jeu du bot
enum BotGamePhase {
  exploration,  // Découvrir ses cartes
  optimization, // Optimiser son score
  endgame,      // Rush vers Dutch
}

/// Configuration et utilitaires pour les bots
/// Principe GRASP: Information Expert - Connaît les règles de configuration
class BotConfig {
  static final Random random = Random();

  /// Détermine la phase de jeu du bot
  static BotGamePhase getBotPhase(Player bot, GameState gameState) {
    int knownCount = bot.knownCardCount;
    int totalCards = bot.hand.length;
    int estimatedScore = bot.getEstimatedScore();
    
    // En tournoi, prendre en compte le score cumulé pour passer en endgame plus tôt
    if (gameState.gameMode == GameMode.tournament) {
      int cumulativeScore = gameState.getCumulativeScore(bot);
      if (cumulativeScore >= 70) {
        return BotGamePhase.endgame;
      }
    }
    
    bool someoneClose = gameState.players.any((p) => p.hand.length <= 2);
    if (estimatedScore <= 8 || someoneClose) {
      return BotGamePhase.endgame;
    }
    
    if (knownCount < totalCards) {
      return BotGamePhase.exploration;
    }
    
    return BotGamePhase.optimization;
  }

  /// Calcule le temps de réflexion du bot
  static int getThinkingTime(BotBehavior? behavior, BotDifficulty difficulty, GameState gameState) {
    if (behavior == null) return 800;

    if (behavior == BotBehavior.balanced) {
      bool criticalMoment = gameState.players.any((p) => p.hand.length <= 2);
      
      switch (difficulty.name) {
        case "Bronze":
          return criticalMoment ? 1000 : 800;
        case "Argent":
          return criticalMoment ? 1400 : 1000;
        case "Or":
          return criticalMoment ? 1800 : 1200;
        case "Platine":
          return criticalMoment ? 2000 : 1400;
        default:
          return 1000;
      }
    }

    if (behavior == BotBehavior.aggressive) {
      return difficulty.name == "Or" || difficulty.name == "Platine" ? 600 : 500;
    }

    return 900;
  }

  /// Convertit les paramètres AI en BotDifficulty
  static BotDifficulty difficultyFromParameters(Map<String, double> params) {
    double numParam(String key, double fallback) {
      final v = params[key];
      return v ?? fallback;
    }

    double clamp01(double v) => v.clamp(0.0, 1.0);

    final memoryAccuracy = clamp01(numParam('memoryAccuracy', 0.7));
    final riskTolerance = clamp01(numParam('riskTolerance', 0.5));
    final powerUsageRate = clamp01(numParam('powerUsageRate', 0.5));
    final caution = clamp01(numParam('caution', 0.5));
    final dutchThreshold = numParam('dutchThreshold', 6.0).round().clamp(0, 30);

    final forgetChancePerTurn = (1.0 - memoryAccuracy) * 0.25;
    final confusionOnSwap = (1.0 - memoryAccuracy) * 0.20;
    final reactionSpeed = (0.6 + memoryAccuracy * 0.4).clamp(0.0, 1.0);
    final matchAccuracy = (0.75 + memoryAccuracy * 0.25).clamp(0.0, 1.0);
    final reactionMatchChance = (0.35 + (riskTolerance + powerUsageRate) * 0.3).clamp(0.0, 1.0);
    final keepCardThreshold = (7 - (caution * 6)).round().clamp(0, 7);

    return BotDifficulty(
      name: 'SBMM',
      forgetChancePerTurn: forgetChancePerTurn,
      confusionOnSwap: confusionOnSwap,
      dutchThreshold: dutchThreshold,
      reactionSpeed: reactionSpeed,
      matchAccuracy: matchAccuracy,
      reactionMatchChance: reactionMatchChance,
      keepCardThreshold: keepCardThreshold,
    );
  }

  /// Convertit le niveau de compétence en difficulté
  static BotDifficulty getSkillDifficulty(BotSkillLevel? level) {
    if (level == null) return BotDifficulty.silver;
    
    switch (level) {
      case BotSkillLevel.bronze:
        return BotDifficulty.bronze;
      case BotSkillLevel.silver:
        return BotDifficulty.silver;
      case BotSkillLevel.gold:
        return BotDifficulty.gold;
      case BotSkillLevel.platinum:
        return BotDifficulty.platinum;
    }
  }

  /// Obtient la difficulté appropriée pour un bot
  static BotDifficulty getDifficulty(Player bot, int? playerMMR) {
    if (bot.aiParameters != null) {
      return difficultyFromParameters(bot.aiParameters!);
    }
    if (playerMMR != null) {
      return BotDifficulty.fromMMR(playerMMR);
    }
    return getSkillDifficulty(bot.botSkillLevel);
  }
}
