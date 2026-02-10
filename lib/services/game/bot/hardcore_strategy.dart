import 'dart:math';
import '../../../models/game_state.dart';
import '../../../models/player.dart';
import '../../../models/playing_card.dart';
import 'bot_difficulty.dart';
import 'bot_dutch_strategy.dart';
import 'hardcore_bot_config.dart';

/// Stratégies avancées pour les bots hardcore
/// Séparation des axes value/strategic, punish mistakes, endgame killer, anti-stomp
class HardcoreStrategy {
  // ═══════════════════════════════════════════════════════════════════════════
  // SEPARATION VALUE / STRATEGIC THRESHOLDS
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// Évalue si une carte devrait être gardée basé sur deux axes
  /// - valueScore: valeur pure des points
  /// - strategicScore: synergie, setup powers, deny potentiel
  static CardEvaluation evaluateCard(
    PlayingCard card,
    Player bot,
    GameState gs,
    BotDifficulty difficulty,
    HardcoreLevel? hardcoreLevel,
  ) {
    final valueScore = _calculateValueScore(card, difficulty);
    final strategicScore = _calculateStrategicScore(card, bot, gs, difficulty);
    
    return CardEvaluation(
      card: card,
      valueScore: valueScore,
      strategicScore: strategicScore,
      shouldKeep: _shouldKeepCard(valueScore, strategicScore, difficulty, hardcoreLevel),
    );
  }

  /// Score basé sur la valeur pure de la carte (0-10, plus bas = meilleur)
  static double _calculateValueScore(PlayingCard card, BotDifficulty difficulty) {
    final points = card.points;
    
    // Normalisation: 0 points → score 0, 12 points → score 10
    double score = (points / 12.0) * 10;
    
    // Bonus pour les cartes à 0 points
    if (points == 0) score = -1.0; // Toujours excellent
    
    return score;
  }

  /// Score stratégique (synergies, powers, denies)
  static double _calculateStrategicScore(
    PlayingCard card,
    Player bot,
    GameState gs,
    BotDifficulty difficulty,
  ) {
    double score = 5.0; // Neutre par défaut
    
    // Bonus pour cartes avec pouvoirs utiles
    if (_hasPowerValue(card, bot, gs)) {
      score -= 2.0; // Meilleur score = vaut la peine de garder
    }
    
    // Bonus pour cartes qui peuvent matcher avec la défausse
    if (gs.discardPile.isNotEmpty) {
      final topDiscard = gs.discardPile.last;
      if (card.matches(topDiscard)) {
        score -= 1.5; // Opportunité de match
      }
    }
    
    // Bonus pour setup de paires (si on a déjà une carte de même valeur connue)
    int sameValueCount = 0;
    for (final known in bot.mentalMap) {
      if (known != null && known.points == card.points) {
        sameValueCount++;
      }
    }
    if (sameValueCount > 0) {
      score -= sameValueCount * 1.0; // Potentiel de paire
    }
    
    // Pénalité si garder cette carte permet un deny adverse
    // (carte haute que l'adversaire pourrait nous refiler via Valet)
    if (card.points >= 8) {
      score += 1.0;
    }
    
    return score.clamp(0.0, 10.0);
  }

  /// Vérifie si la carte a une valeur de pouvoir utile
  static bool _hasPowerValue(PlayingCard card, Player bot, GameState gs) {
    final value = card.value;
    
    // 7 = regarder sa carte (utile si on a des inconnues)
    if (value == '7') {
      int unknownCount = 0;
      for (int i = 0; i < bot.hand.length; i++) {
        if (i >= bot.mentalMap.length || bot.mentalMap[i] == null) {
          unknownCount++;
        }
      }
      return unknownCount > 0;
    }
    
    // 10 = espionner (toujours utile)
    if (value == '10') return true;
    
    // Valet = swap (utile si on a une mauvaise carte connue)
    if (value == 'V') {
      int worstKnown = 0;
      for (final known in bot.mentalMap) {
        if (known != null && known.points > worstKnown) {
          worstKnown = known.points;
        }
      }
      return worstKnown >= 6;
    }
    
    // Joker = carte magique
    if (value == 'JOKER') return true;
    
    return false;
  }

  /// Décide si garder la carte basé sur les deux scores
  static bool _shouldKeepCard(
    double valueScore,
    double strategicScore,
    BotDifficulty difficulty,
    HardcoreLevel? hardcoreLevel,
  ) {
    // Combinaison pondérée des deux axes
    // Hardcore: plus de poids sur strategic
    double valueWeight = 0.7;
    double strategicWeight = 0.3;
    
    if (hardcoreLevel != null) {
      switch (hardcoreLevel) {
        case HardcoreLevel.hard:
          valueWeight = 0.65;
          strategicWeight = 0.35;
          break;
        case HardcoreLevel.insane:
          valueWeight = 0.55;
          strategicWeight = 0.45;
          break;
        case HardcoreLevel.nightmare:
        case HardcoreLevel.impossible:
          valueWeight = 0.50;
          strategicWeight = 0.50;
          break;
      }
    }
    
    final combinedScore = valueScore * valueWeight + strategicScore * strategicWeight;
    
    // Décision sans paramètre externe : garder si la qualité combinée est vraiment bonne
    return combinedScore <= 4.5;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUNISH OBVIOUS MISTAKES
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// Détecte si le joueur a fait une erreur évidente
  static MistakeAnalysis analyzeMistake(
    GameState gs,
    Player human,
    PlayingCard? drawnCard,
    int? replacedIndex,
    bool discarded,
  ) {
    if (drawnCard == null) return MistakeAnalysis.none();
    
    final drawnValue = drawnCard.points;
    
    // Erreur 1: Défausser un 0, 1 ou 2
    if (discarded && drawnValue <= 2) {
      return MistakeAnalysis(
        type: MistakeType.discardedLowCard,
        severity: MistakeSeverity.critical,
        swing: drawnValue <= 1 ? 10 : 6, // Impact estimé
      );
    }
    
    // Erreur 2: Garder une carte très haute (10+) sans raison stratégique
    if (!discarded && drawnValue >= 10 && replacedIndex != null) {
      // Vérifier si c'était pour un pouvoir
      if (!_cardHasPower(drawnCard)) {
        return MistakeAnalysis(
          type: MistakeType.keptHighCard,
          severity: MistakeSeverity.major,
          swing: drawnValue - 5,
        );
      }
    }
    
    // Erreur 3: Remplacer une bonne carte par une pire
    // (difficile à détecter sans connaître la carte remplacée)
    
    return MistakeAnalysis.none();
  }

  static bool _cardHasPower(PlayingCard card) {
    return ['7', '10', 'V', 'JOKER'].contains(card.value);
  }

  /// Applique le comportement "punish" suite à une erreur du joueur
  static BotPunishBehavior getPunishBehavior(
    MistakeAnalysis mistake,
    BotDifficulty difficulty,
    HardcoreLevel? hardcoreLevel,
  ) {
    if (mistake.type == MistakeType.none) {
      return BotPunishBehavior.normal();
    }
    
    // Seulement les bots hardcore punissent
    if (hardcoreLevel == null) {
      return BotPunishBehavior.normal();
    }
    
    switch (mistake.severity) {
      case MistakeSeverity.critical:
        return BotPunishBehavior(
          accelerateDutch: true,
          beAggressive: true,
          dutchThresholdBonus: 2,
          powerAggressionBonus: 0.3,
          duration: 3, // Tours
        );
      case MistakeSeverity.major:
        return BotPunishBehavior(
          accelerateDutch: true,
          beAggressive: false,
          dutchThresholdBonus: 1,
          powerAggressionBonus: 0.15,
          duration: 2,
        );
      case MistakeSeverity.minor:
        return BotPunishBehavior(
          accelerateDutch: false,
          beAggressive: false,
          dutchThresholdBonus: 0,
          powerAggressionBonus: 0.1,
          duration: 1,
        );
      case MistakeSeverity.none:
        return BotPunishBehavior.normal();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ENDGAME KILLER MODE
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// Vérifie si on est en phase endgame killer
  static bool isEndgameKiller(GameState gs, Player bot) {
    // Conditions d'activation:
    // 1. Peu de cartes restantes (≤ 3 en moyenne)
    // 2. Ou quelqu'un a ≤ 2 cartes
    // 3. Ou deck presque vide
    
    final avgCards = gs.players.map((p) => p.hand.length).reduce((a, b) => a + b) / gs.players.length;
    final someoneClose = gs.players.any((p) => p.hand.length <= 2);
    final deckLow = gs.deck.length <= 10;
    
    return avgCards <= 3 || someoneClose || deckLow;
  }

  /// Obtient les paramètres endgame killer
  static EndgameKillerParams getEndgameKillerParams(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    HardcoreLevel? hardcoreLevel,
  ) {
    if (!isEndgameKiller(gs, bot)) {
      return EndgameKillerParams.disabled();
    }
    
    final estimatedScore = bot.getKnownScore();
    final avgOpponentScore = _getAvgOpponentScore(gs, bot);
    final advantage = avgOpponentScore - estimatedScore;
    
    // Plus on a d'avantage, plus on peut être agressif
    int thresholdBonus = 0;
    bool callEarly = false;
    bool minimizeVariance = false;
    
    if (hardcoreLevel != null) {
      switch (hardcoreLevel) {
        case HardcoreLevel.hard:
          if (advantage >= 3) callEarly = true;
          thresholdBonus = 1;
          break;
        case HardcoreLevel.insane:
          if (advantage >= 2) callEarly = true;
          thresholdBonus = 2;
          minimizeVariance = true;
          break;
        case HardcoreLevel.nightmare:
        case HardcoreLevel.impossible:
          if (advantage >= 1) callEarly = true;
          thresholdBonus = 3;
          minimizeVariance = true;
          break;
      }
    }
    
    return EndgameKillerParams(
      enabled: true,
      dutchThresholdBonus: thresholdBonus,
      callEarly: callEarly,
      minimizeVariance: minimizeVariance,
      estimatedAdvantage: advantage,
    );
  }

  static double _getAvgOpponentScore(GameState gs, Player bot) {
    double sum = 0;
    int count = 0;
    for (final p in gs.players) {
      if (p.id != bot.id) {
        final est = BotDutchStrategy.discardTracker.estimateOpponentHand(p.id, p.hand.length);
        sum += p.getEstimatedScoreForOpponent(
          avgDiscardedPoints: est.avgDiscardedPoints > 0 ? est.avgDiscardedPoints : null,
          discardCount: BotDutchStrategy.discardTracker.getDiscardCount(p.id),
        );
        count++;
      }
    }
    return count > 0 ? sum / count : 0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANTI-STOMP PROTECTION
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// Vérifie si le bot est en position de "stomp" (domine largement)
  static bool isBotStomping(GameState gs, Player bot) {
    final botScore = bot.getKnownScore();
    final opponents = gs.players.where((p) => p.id != bot.id).toList();
    
    if (opponents.isEmpty) return false;
    
    // Stomp si:
    // - Score du bot < 50% du meilleur adversaire
    // - OU bot a beaucoup moins de cartes que tout le monde
    
    final bestOpponentScore = opponents.map((p) {
      final est = BotDutchStrategy.discardTracker.estimateOpponentHand(p.id, p.hand.length);
      return p.getEstimatedScoreForOpponent(
        avgDiscardedPoints: est.avgDiscardedPoints > 0 ? est.avgDiscardedPoints : null,
        discardCount: BotDutchStrategy.discardTracker.getDiscardCount(p.id),
      );
    }).reduce(min);
    final scoreRatio = botScore / max(1, bestOpponentScore);
    
    final botCards = bot.hand.length;
    final avgOpponentCards = opponents.map((p) => p.hand.length).reduce((a, b) => a + b) / opponents.length;
    final cardAdvantage = avgOpponentCards - botCards;
    
    return scoreRatio < 0.5 || cardAdvantage >= 2;
  }

  /// Obtient le comportement anti-stomp
  /// Le bot reste fort mais joue plus "safe" pour laisser une chance
  static AntiStompBehavior getAntiStompBehavior(
    GameState gs,
    Player bot,
    HardcoreLevel? hardcoreLevel,
  ) {
    if (!isBotStomping(gs, bot)) {
      return AntiStompBehavior.disabled();
    }
    
    // IMPORTANT: Le bot ne devient PAS plus bête
    // Il joue juste plus conservateur (pas de risques inutiles)
    
    return AntiStompBehavior(
      enabled: true,
      // Moins agressif sur les swaps risqués
      reduceRiskySwaps: true,
      riskySwapReduction: 0.3,
      // Dutch seulement si vraiment sûr
      dutchOnlyIfSafe: true,
      safetyMargin: 2,
      // Ne pas utiliser les powers de manière optimale
      suboptimalPowerChance: hardcoreLevel == HardcoreLevel.nightmare ? 0.0 : 0.15,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLASSES DE DONNÉES
// ═══════════════════════════════════════════════════════════════════════════

/// Évaluation d'une carte avec les deux axes
class CardEvaluation {
  final PlayingCard card;
  final double valueScore;      // 0-10, plus bas = meilleur
  final double strategicScore;  // 0-10, plus bas = meilleur
  final bool shouldKeep;

  CardEvaluation({
    required this.card,
    required this.valueScore,
    required this.strategicScore,
    required this.shouldKeep,
  });
  
  double get combinedScore => (valueScore + strategicScore) / 2;
}

/// Types d'erreurs détectables
enum MistakeType {
  none,
  discardedLowCard,    // Défaussé une carte 0-2
  keptHighCard,        // Gardé une carte 10+ sans raison
  badSwap,             // Swap désavantageux
  missedMatch,         // Raté un match possible
}

/// Sévérité de l'erreur
enum MistakeSeverity {
  none,
  minor,    // Légère sous-optimalité
  major,    // Erreur significative
  critical, // Grosse bourde
}

/// Analyse d'une erreur
class MistakeAnalysis {
  final MistakeType type;
  final MistakeSeverity severity;
  final int swing; // Impact en points estimé

  MistakeAnalysis({
    required this.type,
    required this.severity,
    required this.swing,
  });
  
  factory MistakeAnalysis.none() => MistakeAnalysis(
    type: MistakeType.none,
    severity: MistakeSeverity.none,
    swing: 0,
  );
}

/// Comportement de punition après erreur
class BotPunishBehavior {
  final bool accelerateDutch;
  final bool beAggressive;
  final int dutchThresholdBonus;
  final double powerAggressionBonus;
  final int duration; // Tours restants

  BotPunishBehavior({
    required this.accelerateDutch,
    required this.beAggressive,
    required this.dutchThresholdBonus,
    required this.powerAggressionBonus,
    required this.duration,
  });
  
  factory BotPunishBehavior.normal() => BotPunishBehavior(
    accelerateDutch: false,
    beAggressive: false,
    dutchThresholdBonus: 0,
    powerAggressionBonus: 0.0,
    duration: 0,
  );
  
  bool get isActive => duration > 0;
}

/// Paramètres endgame killer
class EndgameKillerParams {
  final bool enabled;
  final int dutchThresholdBonus;
  final bool callEarly;
  final bool minimizeVariance;
  final double estimatedAdvantage;

  EndgameKillerParams({
    required this.enabled,
    required this.dutchThresholdBonus,
    required this.callEarly,
    required this.minimizeVariance,
    required this.estimatedAdvantage,
  });
  
  factory EndgameKillerParams.disabled() => EndgameKillerParams(
    enabled: false,
    dutchThresholdBonus: 0,
    callEarly: false,
    minimizeVariance: false,
    estimatedAdvantage: 0,
  );
}

/// Comportement anti-stomp
class AntiStompBehavior {
  final bool enabled;
  final bool reduceRiskySwaps;
  final double riskySwapReduction;
  final bool dutchOnlyIfSafe;
  final int safetyMargin;
  final double suboptimalPowerChance;

  AntiStompBehavior({
    required this.enabled,
    required this.reduceRiskySwaps,
    required this.riskySwapReduction,
    required this.dutchOnlyIfSafe,
    required this.safetyMargin,
    required this.suboptimalPowerChance,
  });
  
  factory AntiStompBehavior.disabled() => AntiStompBehavior(
    enabled: false,
    reduceRiskySwaps: false,
    riskySwapReduction: 0.0,
    dutchOnlyIfSafe: false,
    safetyMargin: 0,
    suboptimalPowerChance: 0.0,
  );
}
