import 'dart:math';
import '../../../models/game_state.dart';
import '../../../models/game_settings.dart';
import '../../../models/player.dart';
import '../../../models/player_learning_data.dart';
import '../../matchmaking/matchmaking_service.dart';
import 'bot_difficulty.dart';
import 'bot_personality.dart';

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
  static int getThinkingTime(
    BotBehavior? behavior,
    BotDifficulty difficulty,
    GameState gameState, {
    BotPersonality? personality,
  }) {
    if (behavior == null) return 800;

    if (personality != null) {
      double behaviorFactor = 1.0;
      if (behavior == BotBehavior.fast) {
        behaviorFactor = 0.75;
      } else if (behavior == BotBehavior.aggressive) {
        behaviorFactor = 0.85;
      }

      double difficultyFactor = 1.0;
      if (difficulty.name == "Platine") {
        difficultyFactor = 1.05;
      } else if (difficulty.name == "Bronze") {
        difficultyFactor = 0.95;
      }

      final base = (personality.decisionSpeedMs * behaviorFactor * difficultyFactor * 0.6)
          .round()
          .clamp(200, 1600);
      return base;
    }

    if (behavior == BotBehavior.balanced) {
      bool criticalMoment = gameState.players.any((p) => p.hand.length <= 2);
      
      switch (difficulty.name) {
        case "Bronze":
          return criticalMoment ? 700 : 450;
        case "Argent":
          return criticalMoment ? 900 : 550;
        case "Or":
          return criticalMoment ? 1100 : 700;
        case "Platine":
          return criticalMoment ? 1300 : 800;
        default:
          return 600;
      }
    }

    if (behavior == BotBehavior.aggressive) {
      return difficulty.name == "Or" || difficulty.name == "Platine" ? 550 : 450;
    }

    return 600;
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

  /// Génère les configurations de bots basées sur le matchmaking adaptatif
  ///
  /// Le rang (Bronze/Argent/Or/Platine) est purement cosmétique.
  /// La vraie difficulté est calculée à partir du MMR du joueur :
  /// - Un joueur fort en Bronze aura des bots plus difficiles
  ///   qu'un joueur faible en Platine
  /// - Plus on se rapproche d'un palier de rang, plus les bots sont forts
  static List<Map<String, double>> generateMatchmakingBotParams({
    required PlayerProfile playerProfile,
    required int botCount,
    bool forceChallenge = false,
  }) {
    final profiles = MatchmakingService.generateBotProfiles(
      playerProfile: playerProfile,
      botCount: botCount,
      forceChallenge: forceChallenge,
    );

    return profiles.map((p) => p.adjustedParameters).toList();
  }

  /// Crée une BotDifficulty à partir d'un profil de matchmaking
  static BotDifficulty difficultyFromMatchmakingProfile(
    BotMatchmakingProfile profile,
  ) {
    return difficultyFromParameters(profile.adjustedParameters);
  }

  /// Retourne des informations de debug sur le matchmaking pour un joueur
  static Map<String, dynamic> getMatchmakingDebugInfo(int playerMMR) {
    return {
      'playerMMR': playerMMR,
      'cosmenticRank': MatchmakingService.getRankName(playerMMR),
      'palierProgress': MatchmakingService.getPalierProgress(playerMMR),
      'palierBoost': MatchmakingService.getPalierBoost(playerMMR),
      'nextRankMMR': MatchmakingService.getNextRankMMR(playerMMR),
      'progressPercent': MatchmakingService.getRankProgressPercent(playerMMR),
    };
  }
}
