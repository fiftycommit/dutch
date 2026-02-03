import 'dart:math';
import '../../../models/game_state.dart';
import '../../../models/player.dart';
import '../../learning/ai_telemetry_service.dart';
import '../../logging/game_logger_service.dart';
import 'bot_difficulty.dart';
import 'bot_config.dart';
import 'bot_threat_analyzer.dart';
import 'bot_personality.dart';
import 'dutch_strategy_config.dart';
import 'bot_memory_manager.dart';
import 'discard_tracker.dart';

/// Stratégie de décision pour appeler Dutch
/// Principe GRASP: Information Expert - Décide quand appeler Dutch
class BotDutchStrategy {
  static final Random _random = Random();
  
  /// Tracker de défausses partagé (comptage de cartes)
  /// Utilisé par les bots Or/Platine/Hardcore pour des décisions plus intelligentes
  static final DiscardTracker discardTracker = DiscardTracker();

  // ═══════════════════════════════════════════════════════════════════════════
  // NOUVELLE LOGIQUE : DUTCH BASÉ SUR L'ÉTAT (pas sur le temps)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Vérifie si le bot PEUT Dutch (conditions nécessaires)
  /// C'est une logique "humaine" : on Dutch quand on SAIT qu'on est bien
  static bool _canDutchStateBaseed(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
  ) {
    // RÈGLE FONDAMENTALE : le bot doit connaître TOUTES ses cartes
    // Aucun humain sensé ne Dutch sans savoir ce qu'il a
    final unknownIndices = BotMemoryManager.getUnknownIndices(bot);
    if (unknownIndices.isNotEmpty) {
      return false;
    }

    // Vérifier que la mentalMap est cohérente
    final knownCount = bot.mentalMap.where((c) => c != null).length;
    final handSize = bot.hand.length;
    if (knownCount < handSize) {
      return false; // Pas assez de certitude
    }

    return true;
  }

  /// Décide si le bot DEVRAIT Dutch (conditions suffisantes)
  /// C'est la vraie intelligence : Dutch tôt si c'est logique
  ///
  /// PHILOSOPHIE SIMPLIFIÉE : Se fier uniquement aux FAITS OBSERVABLES
  /// - Nombre de cartes (visible)
  /// - Son propre score estimé (basé sur mentalMap)
  /// - Nombre de tours joués
  /// PAS d'estimation du score des adversaires (trop aléatoire)
  static bool _shouldDutchStateBased(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    BotPersonality? personality,
  ) {
    final myScore = bot.getEstimatedScore();
    final myCards = bot.hand.length;

    // Analyser la table (pour le nombre de cartes uniquement)
    final report = BotThreatAnalyzer.analyzeOpponents(gs, bot);
    
    // Nombre de fois que CE bot a joué (approximation)
    final myTurnsPlayed = gs.actionCount ~/ gs.players.length;

    // ═══════════════════════════════════════════════════════════════════════
    // RÈGLE 0 (SIMPLIFIÉE) : Ne Dutch que si on a MOINS ou ÉGAL de cartes
    // que le meilleur adversaire. Pas d'estimation de score adverse !
    // ═══════════════════════════════════════════════════════════════════════
    if (myCards > report.minOpponentCards) {
      // Un adversaire a moins de cartes = potentiellement mieux placé
      return false;
    }
    
    // Si quelqu'un a le même nombre de cartes, être plus prudent
    // (il pourrait avoir un meilleur score)
    final hasOpponentWithSameCards = report.minOpponentCards == myCards;
    
    // ═══════════════════════════════════════════════════════════════════════
    // RÈGLE 1 : Mort subite - Si quelqu'un a 1 carte, il faut être ultra-sûr
    // ═══════════════════════════════════════════════════════════════════════
    if (report.hasOpponentWithOneCard) {
      // L'adversaire peut Dutch au prochain tour
      // Il faut avoir un score très bas ET peu de cartes
      if (myScore > 2) return false;
      if (myCards > 1) return false; // On doit aussi avoir 1 carte
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RÈGLE 2 : Score maximum selon le contexte
    // Plus conservateur si on a joué beaucoup de tours
    // ═══════════════════════════════════════════════════════════════════════
    final isLateGame = myTurnsPlayed >= 7;
    
    int scoreGate;
    if (myCards == 1) {
      scoreGate = isLateGame ? 6 : 8;
    } else if (myCards == 2) {
      scoreGate = isLateGame ? 5 : 7;
    } else if (myCards == 3) {
      scoreGate = isLateGame ? 4 : 5;
    } else {
      scoreGate = isLateGame ? 3 : 4;
    }
    
    // Si adversaire a même nombre de cartes, être encore plus strict
    if (hasOpponentWithSameCards) {
      scoreGate -= 2;
    }

    if (myScore > scoreGate) {
      return false;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RÈGLE 3 : Confiance minimale basée sur la mémoire
    // C'est ICI que Bronze et Platine diffèrent naturellement !
    // Bronze oublie → mentalMap trouée → confidence basse → Dutch moins souvent
    // Platine se souvient → mentalMap complète → confidence haute → Dutch tranchant
    // ═══════════════════════════════════════════════════════════════════════
    final confidence = BotThreatAnalyzer.calculateLeadConfidence(gs, bot);

    // Seuil de confiance - plus strict en late game ou si adversaire a même nb cartes
    double confidenceThreshold = 0.45;
    if (isLateGame) confidenceThreshold += 0.10;
    if (hasOpponentWithSameCards) confidenceThreshold += 0.10;
    
    if (confidence < confidenceThreshold) {
      return false; // Pas assez sûr de sa position
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RÈGLE 4 : COMPTAGE DE CARTES (bots Or/Platine/Hardcore uniquement)
    // Analyser ce que les adversaires ont défaussé pour estimer leur main
    // ═══════════════════════════════════════════════════════════════════════
    final isSmartBot = difficulty.name == "Or" || 
                       difficulty.name == "Platine" ||
                       BotThreatAnalyzer.isHardcoreMode(difficulty);
    
    if (isSmartBot && hasOpponentWithSameCards) {
      // Utiliser le comptage de cartes pour décider
      final bestOpponentEstimate = discardTracker.estimateBestOpponentScore(gs, bot);
      
      // Si l'adversaire défausse beaucoup de cartes hautes, 
      // il a probablement un bon score → être prudent
      if (myScore > bestOpponentEstimate - 2) {
        // Trop risqué - l'adversaire semble avoir une bonne main
        return false;
      }
      
      // Bonus : si le ratio low/high est faible, moins de risque
      final ratio = discardTracker.lowToHighRatio;
      if (ratio < 0.8 && myScore <= scoreGate) {
        // Peu de bonnes cartes restantes → adversaires ont du mal à s'améliorer
        return true;
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RÈGLE 5 : HUMAIN EN DANGER = DUTCH IMMÉDIAT
    // Si l'humain a peu de cartes, il faut agir MAINTENANT (mais prudemment)
    // ═══════════════════════════════════════════════════════════════════════
    if (report.humanPlayer != null) {
      final humanCards = report.humanPlayer!.hand.length;

      // L'humain a peu de cartes : Dutch si on est bien placé
      if (humanCards <= 2 && myCards <= humanCards) {
        // Pour les bots intelligents, vérifier le comptage
        if (isSmartBot) {
          final humanEstimate = discardTracker.estimateOpponentHand(
            report.humanPlayer!.id, 
            humanCards
          );
          // Si l'humain défausse des cartes hautes, il a probablement un bon score
          if (humanEstimate.likelyLowHand && myScore > humanEstimate.estimatedScore) {
            return false; // L'humain semble mieux placé
          }
        }
        
        // On accepte un score plus haut si l'humain menace
        if (myScore <= scoreGate + 1 && confidence >= 0.50) {
          return true;
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // RÈGLE 6 : Avantages situationnels (basé sur le NOMBRE DE CARTES uniquement)
    // ═══════════════════════════════════════════════════════════════════════

    // Avantage clair : on a moins de cartes que tout le monde
    final hasCardAdvantage = myCards < report.minOpponentCards;

    // Si on a un avantage en cartes et un bon score, Dutch !
    if (hasCardAdvantage && myScore <= scoreGate) {
      return true;
    }

    // Si on a un bon score et une bonne confiance, go
    return myScore <= scoreGate && confidence >= 0.55;
  }

  /// Détermine si le bot devrait faire du "sandbagging"
  /// (retarder un Dutch gagnant pour faire croire à l'adversaire qu'il gagne)
  ///
  /// DÉSACTIVÉ par défaut : En mode mort subite, retarder un Dutch gagnant
  /// est trop risqué (un adversaire peut Dutch avant nous).
  /// Ça fait aussi "bot idiot" aux yeux des joueurs.
  static bool _shouldSandbag(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    int estimatedScore,
  ) {
    // SANDBAGGING DÉSACTIVÉ : trop risqué en mode mort subite
    // Un bot intelligent Dutch dès qu'il sait qu'il gagne
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POINT D'ENTRÉE PRINCIPAL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Détermine si le bot doit appeler Dutch
  static bool shouldCallDutch(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    BotGamePhase phase, {
    BotPersonality? personality,
  }) {
    // Phase d'exploration = jamais de Dutch
    if (phase == BotGamePhase.exploration) {
      return false;
    }

    // === CONDITION NÉCESSAIRE : le bot peut-il Dutch ? ===
    if (!_canDutchStateBaseed(gs, bot, difficulty)) {
      return false;
    }

    final estimatedScore = bot.getEstimatedScore();
    final decisionScore = _riskAdjustedScore(bot, estimatedScore);

    // === SANDBAGGING : retarder un Dutch gagnant ===
    // On vérifie d'abord si on DEVRAIT Dutch sans sandbagging
    final wouldDutchWithoutSandbag = _shouldDutchStateBased(gs, bot, difficulty, personality);
    final sandbagged = _shouldSandbag(gs, bot, difficulty, decisionScore);
    
    if (sandbagged && wouldDutchWithoutSandbag) {
      // TÉLÉMÉTRIE: le bot a volontairement retardé un Dutch gagnant
      final report = BotThreatAnalyzer.analyzeOpponents(gs, bot);
      AiTelemetryService().onSandbag(bot.id, report.leadConfidence);
      return false;
    }
    
    if (sandbagged) {
      return false;
    }

    // === CONDITION SUFFISANTE : le bot devrait-il Dutch ? ===
    if (wouldDutchWithoutSandbag) {
      // Log la décision de Dutch
      GameLoggerService.instance.logBotDecision(
        bot: bot,
        decision: 'DUTCH DÉCIDÉ',
        context: {
          'estimatedScore': estimatedScore,
          'handSize': bot.hand.length,
          'confidence': BotThreatAnalyzer.calculateLeadConfidence(gs, bot).toStringAsFixed(2),
          'reason': 'State-based logic',
        },
      );
      return true;
    }

    // === LOGIQUE LEGACY (pour personnalité avec ghost influence) ===
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

      final int humanScore = _estimateHumanScore(gs, bot);
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

      // HARDCORE FIX: Les niveaux hardcore utilisent la logique intelligente
      final isHardcoreWithPersonality = difficulty.name == "Platine" || 
                                         difficulty.name == "Or" ||
                                         difficulty.name == "Hard" ||
                                         difficulty.name == "Insane" ||
                                         difficulty.name == "Nightmare" ||
                                         difficulty.name == "Impossible";

      if (isHardcoreWithPersonality) {
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
    // HARDCORE FIX: Les niveaux hardcore utilisent aussi la logique intelligente
    final isHardcore = difficulty.name == "Platine" || 
                       difficulty.name == "Or" ||
                       difficulty.name == "Hard" ||
                       difficulty.name == "Insane" ||
                       difficulty.name == "Nightmare" ||
                       difficulty.name == "Impossible";
    
    if (isHardcore) {
      return _shouldSmartDutch(gs, bot, difficulty, phase, decisionScore, audacityBonus, confidence, tournamentPressure);
    }
    
    // Bronze/Argent : logique basée sur seuils
    final behavior = bot.botBehavior;
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
