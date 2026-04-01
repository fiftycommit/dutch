import 'dart:math';
import '../../../models/game_state.dart';
import '../../../models/game_settings.dart';
import '../../../models/player.dart';
import '../../../models/player_learning_data.dart';
import 'bot_difficulty.dart';
import 'bot_memory_manager.dart';
import 'bot_personality.dart';
import 'hardcore_bot_config.dart';

export '../../../models/game_settings.dart' show BotBehavior, BotSkillLevel;
export 'hardcore_bot_config.dart'
    show HardcoreLevel, HardcoreBotConfig, PlayerSkillEstimator;

/// Phases de jeu du bot
enum BotGamePhase {
  exploration, // Découvrir ses cartes
  optimization, // Optimiser son score
  endgame, // Rush vers Dutch
}

/// Configuration et utilitaires pour les bots
/// Principe GRASP: Information Expert - Connaît les règles de configuration
class BotConfig {
  static final Random random = Random();

  /// Détermine la phase de jeu du bot
  /// Logique basée sur la CERTITUDE, pas sur des estimations de score
  static BotGamePhase getBotPhase(Player bot, GameState gameState) {
    // Niveau fort unique : les anciens bots Or utilisent désormais
    // la logique contextuelle du palier Platine.
    if (bot.botSkillLevel == BotSkillLevel.gold ||
        bot.botSkillLevel == BotSkillLevel.platinum) {
      return _getPlatinumContextualPhase(bot, gameState);
    }

    final knowsAll = bot.knowsAllCards;
    final knownScore = bot.getKnownScore();

    // En tournoi, prendre en compte le score cumulé pour passer en endgame plus tôt
    if (gameState.gameMode == GameMode.tournament) {
      int cumulativeScore = gameState.getCumulativeScore(bot);
      if (cumulativeScore >= 70) {
        return BotGamePhase.endgame;
      }
    }

    // URGENCE : quelqu'un a ≤2 cartes → endgame (même si on ne connaît pas tout)
    final someoneClose = gameState.players.any((p) => p.hand.length <= 2);
    if (someoneClose) {
      return BotGamePhase.endgame;
    }

    // Si on ne connaît pas toutes ses cartes → exploration (priorité découverte)
    if (!knowsAll) {
      return BotGamePhase.exploration;
    }

    // On connaît TOUT : décider entre optimization et endgame
    // Endgame si score connu est bon (on peut se permettre de Dutch)
    if (knownScore <= 8) {
      return BotGamePhase.endgame;
    }

    return BotGamePhase.optimization;
  }

  /// Phase contextuelle pour le palier fort : jamais d'exploration passive
  static BotGamePhase _getPlatinumContextualPhase(Player bot, GameState gs) {
    final knownScore = bot.getKnownScore();
    final unknownCount = BotMemoryManager.getUnknownIndices(bot).length;
    final minOpponentCards = gs.players
        .where((p) => p.id != bot.id)
        .map((p) => p.hand.length)
        .fold(99, (int a, int b) => a < b ? a : b);

    // Tournoi : endgame si score cumulé élevé
    if (gs.gameMode == GameMode.tournament) {
      int cumulativeScore = gs.getCumulativeScore(bot);
      if (cumulativeScore >= 70) {
        return BotGamePhase.endgame;
      }
    }

    if (minOpponentCards <= 2) return BotGamePhase.endgame;
    if (unknownCount == 0 && knownScore <= 5) return BotGamePhase.endgame;
    if (knownScore <= 3 && unknownCount <= 1) return BotGamePhase.endgame;
    return BotGamePhase.optimization; // jamais exploration passive
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
      } else if (behavior == BotBehavior.moi) {
        behaviorFactor = 0.80;
      }

      double difficultyFactor = 1.0;
      if (difficulty.name == "Difficile") {
        difficultyFactor = 1.05;
      } else if (difficulty.name == "Bronze") {
        difficultyFactor = 0.95;
      }

      final base = (personality.decisionSpeedMs *
              behaviorFactor *
              difficultyFactor *
              0.6)
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
        case "Difficile":
          return criticalMoment ? 1300 : 800;
        default:
          return 600;
      }
    }

    if (behavior == BotBehavior.aggressive) {
      return difficulty.name == "Difficile"
          ? 550
          : 450;
    }

    if (behavior == BotBehavior.moi) {
      final criticalMoment = gameState.players.any((p) => p.hand.length <= 2);
      return criticalMoment ? 700 : 520;
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

    final forgetChancePerTurn = (1.0 - memoryAccuracy) * 0.25;
    final confusionOnSwap = (1.0 - memoryAccuracy) * 0.20;
    final reactionSpeed = (0.6 + memoryAccuracy * 0.4).clamp(0.0, 1.0);
    final matchAccuracy = (0.75 + memoryAccuracy * 0.25).clamp(0.0, 1.0);
    final reactionMatchChance =
        (0.35 + (riskTolerance + powerUsageRate) * 0.3).clamp(0.0, 1.0);

    return BotDifficulty(
      name: 'SBMM',
      forgetChancePerTurn: forgetChancePerTurn,
      confusionOnSwap: confusionOnSwap,
      reactionSpeed: reactionSpeed,
      matchAccuracy: matchAccuracy,
      reactionMatchChance: reactionMatchChance,
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
      case BotSkillLevel.platinum:
        return BotDifficulty.difficult;
    }
  }

  /// Obtient la difficulté appropriée pour un bot
  ///
  /// HARDCORE FIX: Si playerMMR est null, on utilise le skill level du bot
  /// au lieu de forcer Argent (qui rendait tous les bots trop faciles)
  static BotDifficulty getDifficulty(
    Player bot,
    int? playerMMR, {
    HardcoreLevel? hardcoreLevel,
    int? playerSkillEstimate,
  }) {
    // Mode hardcore: utilise la config hardcore
    if (hardcoreLevel != null) {
      return HardcoreBotConfig.getHardcoreDifficulty(
        level: hardcoreLevel,
        playerSkillEstimate: playerSkillEstimate ?? playerMMR ?? 0,
      );
    }

    // Si on a des paramètres AI explicites, les utiliser
    if (bot.aiParameters != null) {
      return difficultyFromParameters(bot.aiParameters!);
    }

    // Si on a un MMR joueur, l'utiliser pour adapter la difficulté
    if (playerMMR != null) {
      return BotDifficulty.fromMMR(playerMMR);
    }

    // HARDCORE FIX: Au lieu de retourner Argent par défaut,
    // utiliser le skill level configuré du bot
    return getSkillDifficulty(bot.botSkillLevel);
  }

  /// Vrai SBMM : copie les paramètres du joueur avec petite variance
  ///
  /// Au lieu de scaler les params via un multiplicateur basé sur des seuils MMR,
  /// on copie directement les learnedParameters du joueur avec une variance
  /// aléatoire par paramètre. Chaque bot est un "miroir" du joueur,
  /// légèrement différent pour la diversité.
  static List<Map<String, double>> generateMatchmakingBotParams({
    required PlayerProfile playerProfile,
    required int botCount,
    bool forceChallenge = false,
  }) {
    final base = playerProfile.learnedParameters;
    final result = <Map<String, double>>[];

    double getNum(String key, double fallback) {
      final v = base[key];
      if (v is num) return v.toDouble();
      return fallback;
    }

    for (int i = 0; i < botCount; i++) {
      final botParams = <String, double>{};

      // Copier chaque paramètre du joueur avec variance aléatoire
      for (final entry in _sbmmParamConfig.entries) {
        final playerValue = getNum(entry.key, entry.value[0]);
        final variance = entry.value[1];
        final minVal = entry.value[2];
        final maxVal = entry.value[3];

        final noise = (random.nextDouble() - 0.5) * 2 * variance;
        botParams[entry.key] = (playerValue + noise).clamp(minVal, maxVal);
      }

      // Paramètres dérivés (calculés, pas trackés directement)
      botParams['riskTolerance'] =
          ((botParams['aggressiveness']! + (1.0 - botParams['caution']!)) / 2)
              .clamp(0.0, 1.0);
      botParams['powerUsageRate'] = ((botParams['powerDefensiveRate']! +
                  botParams['powerOffensiveRate']!) /
              2)
          .clamp(0.0, 1.0);
      botParams['scoreGapWeight'] = 0.7;
      botParams['rankPenalty'] = 0.0;
      botParams['ghostInfluence'] = 0.0;
      botParams['ghostDutchThreshold'] = botParams['dutchThreshold']!;

      // Ciblage : copier la stratégie du joueur (catégoriel)
      final targetStrat = base['targetingStrategy'];
      if (targetStrat == 'leader') {
        botParams['targetingStrategy'] = 0.0;
      } else if (targetStrat == 'weak') {
        botParams['targetingStrategy'] = 1.0;
      } else {
        botParams['targetingStrategy'] = 2.0; // random/balanced
      }

      result.add(botParams);
    }

    return result;
  }

  // Config SBMM : [default, variance, min, max] par paramètre
  // Variance = bruit aléatoire ± autour de la valeur du joueur
  static const Map<String, List<double>> _sbmmParamConfig = {
    'aggressiveness': [0.5, 0.08, 0.0, 1.0],
    'caution': [0.5, 0.08, 0.0, 1.0],
    'dutchThreshold': [15.0, 2.5, 5.0, 30.0],
    'dutchQuality': [0.5, 0.08, 0.0, 1.0],
    'powerDefensiveRate': [0.5, 0.08, 0.0, 1.0],
    'powerOffensiveRate': [0.5, 0.08, 0.0, 1.0],
    'memoryAccuracy': [0.7, 0.06, 0.3, 1.0],
    'memoryRetention': [0.7, 0.05, 0.3, 1.0],
    'adaptability': [0.5, 0.08, 0.0, 1.0],
    'decisionSpeed': [2000, 300, 500, 10000],
    'aggressiveness_winning': [0.5, 0.08, 0.0, 1.0],
    'aggressiveness_losing': [0.5, 0.08, 0.0, 1.0],
    'caution_winning': [0.5, 0.08, 0.0, 1.0],
    'caution_losing': [0.5, 0.08, 0.0, 1.0],
  };
}
