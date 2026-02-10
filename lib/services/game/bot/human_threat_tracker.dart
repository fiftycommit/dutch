import '../../../models/player.dart';
import '../../../models/game_state.dart';
import 'bot_dutch_strategy.dart';

/// Niveau de menace de l'humain
enum HumanThreatLevel {
  /// L'humain joue normalement, pas de menace particulière
  low,
  /// L'humain progresse bien, attention requise
  medium,
  /// L'humain est dangereux, les bots doivent réagir
  high,
  /// ALERTE : L'humain va gagner si on ne fait rien
  critical,
}

/// Tracker de la menace humaine
/// 
/// Analyse en temps réel les performances de l'humain pour que les bots
/// puissent ajuster leur stratégie. Un joueur qui enchaîne les matchs
/// ou qui baisse rapidement son score devient une cible prioritaire.
/// 
/// Singleton pour maintenir l'état entre les tours.
class HumanThreatTracker {
  static final HumanThreatTracker _instance = HumanThreatTracker._internal();
  factory HumanThreatTracker() => _instance;
  HumanThreatTracker._internal();

  // ═══════════════════════════════════════════════════════════════════════════
  // ÉTAT DU TRACKER
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// Score de l'humain au début de la manche
  int _initialHumanScore = 0;
  
  /// Nombre de matchs réussis par l'humain cette manche
  int _humanMatchCount = 0;
  
  /// Nombre de tours depuis le dernier match de l'humain
  int _turnsSinceLastHumanMatch = 0;
  
  /// Points économisés par matchs cette manche
  int _humanMatchPointsSaved = 0;
  
  /// Nombre de cartes initiales de l'humain (pour calcul de progression)
  // ignore: unused_field
  int _initialHumanCards = 4;
  
  /// Tour où l'humain a fait son dernier match
  int _lastMatchTurn = -1;

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALISATION
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// Réinitialise le tracker pour une nouvelle manche
  void reset() {
    _initialHumanScore = 0;
    _humanMatchCount = 0;
    _turnsSinceLastHumanMatch = 0;
    _humanMatchPointsSaved = 0;
    _initialHumanCards = 4;
    _lastMatchTurn = -1;
  }

  /// Initialise avec l'état de départ de la manche
  void initializeRound(GameState gs) {
    reset();
    final human = gs.players.where((p) => p.isHuman).firstOrNull;
    if (human != null) {
      // Estimer le score initial via l'entonnoir
      final estimate = BotDutchStrategy.discardTracker.estimateOpponentHand(human.id, human.hand.length);
      _initialHumanScore = human.getEstimatedScoreForOpponent(
        avgDiscardedPoints: estimate.avgDiscardedPoints > 0 ? estimate.avgDiscardedPoints : null,
        discardCount: BotDutchStrategy.discardTracker.getDiscardCount(human.id),
      );
      _initialHumanCards = human.hand.length;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRACKING DES ÉVÉNEMENTS
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// Enregistre un match réussi par l'humain
  void recordHumanMatch(int pointsSaved, int currentTurn) {
    _humanMatchCount++;
    _humanMatchPointsSaved += pointsSaved;
    _turnsSinceLastHumanMatch = 0;
    _lastMatchTurn = currentTurn;
  }

  /// Appelé à chaque nouveau tour pour mettre à jour les compteurs
  void onNewTurn() {
    _turnsSinceLastHumanMatch++;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CALCUL DU NIVEAU DE MENACE
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// Calcule le niveau de menace actuel de l'humain
  HumanThreatLevel calculateThreatLevel(GameState gs) {
    final human = gs.players.where((p) => p.isHuman).firstOrNull;
    if (human == null) return HumanThreatLevel.low;

    // Estimer le score de l'humain via l'entonnoir
    final humanEstimate = BotDutchStrategy.discardTracker.estimateOpponentHand(human.id, human.hand.length);
    final currentScore = human.getEstimatedScoreForOpponent(
      avgDiscardedPoints: humanEstimate.avgDiscardedPoints > 0 ? humanEstimate.avgDiscardedPoints : null,
      discardCount: BotDutchStrategy.discardTracker.getDiscardCount(human.id),
    );
    final currentCards = human.hand.length;
    
    // Score de menace (0-100)
    double threatScore = 0;

    // 1) Progression du score (25 pts max)
    // Plus le score a baissé vite, plus c'est menaçant
    final scoreReduction = _initialHumanScore - currentScore;
    if (scoreReduction >= 20) {
      threatScore += 25;
    } else if (scoreReduction >= 12) {
      threatScore += 18;
    } else if (scoreReduction >= 6) {
      threatScore += 10;
    }

    // 2) Matchs réussis (30 pts max)
    // Enchaîner les matchs = très dangereux
    if (_humanMatchCount >= 3) {
      threatScore += 30;
    } else if (_humanMatchCount >= 2) {
      threatScore += 20;
    } else if (_humanMatchCount >= 1) {
      threatScore += 10;
    }

    // 3) Nombre de cartes restantes (25 pts max)
    // Peu de cartes = proche du Dutch
    if (currentCards == 1) {
      threatScore += 25;
    } else if (currentCards == 2) {
      threatScore += 18;
    } else if (currentCards == 3) {
      threatScore += 8;
    }

    // 4) Score actuel absolu (20 pts max)
    // Un score très bas = prêt à Dutch
    if (currentScore <= 3) {
      threatScore += 20;
    } else if (currentScore <= 6) {
      threatScore += 15;
    } else if (currentScore <= 10) {
      threatScore += 8;
    }

    // 5) Momentum : matchs récents vs anciens
    // Un match il y a 1 tour = plus dangereux qu'il y a 5 tours
    if (_lastMatchTurn >= 0 && _turnsSinceLastHumanMatch <= 2) {
      threatScore += 10; // Momentum actif
    }

    // Convertir en niveau
    if (threatScore >= 70) {
      return HumanThreatLevel.critical;
    } else if (threatScore >= 45) {
      return HumanThreatLevel.high;
    } else if (threatScore >= 25) {
      return HumanThreatLevel.medium;
    }
    return HumanThreatLevel.low;
  }

  /// Retourne un multiplicateur d'agressivité basé sur le niveau de menace
  /// 1.0 = normal, 1.5 = agressif, 2.0 = très agressif
  double getAggressivenessMultiplier(HumanThreatLevel level) {
    switch (level) {
      case HumanThreatLevel.low:
        return 1.0;
      case HumanThreatLevel.medium:
        return 1.3;
      case HumanThreatLevel.high:
        return 1.6;
      case HumanThreatLevel.critical:
        return 2.0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DÉCISIONS STRATÉGIQUES ANTI-HUMAIN
  // ═══════════════════════════════════════════════════════════════════════════

  /// Le bot devrait-il prioriser un match contre l'humain même si sous-optimal ?
  /// Retourne true si l'humain est suffisamment menaçant
  bool shouldPrioritizeAntiHumanMatch(GameState gs) {
    final level = calculateThreatLevel(gs);
    return level == HumanThreatLevel.high || level == HumanThreatLevel.critical;
  }

  /// Le bot devrait-il appeler Dutch de façon préventive pour bloquer l'humain ?
  /// Retourne true si l'humain risque de Dutch avec un meilleur score
  bool shouldPreemptiveDutch(GameState gs, Player bot) {
    final human = gs.players.where((p) => p.isHuman).firstOrNull;
    if (human == null) return false;

    final level = calculateThreatLevel(gs);
    if (level != HumanThreatLevel.critical) return false;

    // L'humain a très peu de cartes et un bon score
    // Le bot devrait Dutch même avec un score "ok" pour le bloquer
    //
    // Les deux scores sont des estimations
    // Le bot ne devrait Dutch préventif que s'il connaît TOUTES ses cartes
    if (!bot.knowsAllCards) {
      return false; // Trop risqué de Dutch sans certitude
    }

    final hEstimate = BotDutchStrategy.discardTracker.estimateOpponentHand(human.id, human.hand.length);
    final humanScore = human.getEstimatedScoreForOpponent(
      avgDiscardedPoints: hEstimate.avgDiscardedPoints > 0 ? hEstimate.avgDiscardedPoints : null,
      discardCount: BotDutchStrategy.discardTracker.getDiscardCount(human.id),
    );
    final botScore = bot.getKnownScore();     // Score certain du bot

    // Si l'humain a <= 2 cartes et un meilleur score,
    // et que le bot a un score acceptable (< 15), Dutch préventif
    if (human.hand.length <= 2 && humanScore < botScore && botScore < 15) {
      return true;
    }

    return false;
  }

  /// Le bot devrait-il garder une mauvaise carte pour ne pas aider l'humain ?
  /// (ex: ne pas défausser un 10 si l'humain peut le matcher)
  bool shouldAvoidHelpingHuman(GameState gs, int cardValue) {
    final level = calculateThreatLevel(gs);
    if (level == HumanThreatLevel.low) return false;

    // En menace medium+, éviter de défausser des cartes que l'humain pourrait matcher
    // Les cartes à faible valeur (0-5) sont les plus "matchables" car communes
    // Mais aussi les 10, V, D qui ont des pouvoirs
    final riskyToDiscard = cardValue <= 5 || cardValue >= 10;
    
    return riskyToDiscard && level.index >= HumanThreatLevel.medium.index;
  }

  /// Obtient des infos de debug sur l'état actuel
  Map<String, dynamic> getDebugInfo(GameState gs) {
    return {
      'initialScore': _initialHumanScore,
      'matchCount': _humanMatchCount,
      'matchPointsSaved': _humanMatchPointsSaved,
      'turnsSinceMatch': _turnsSinceLastHumanMatch,
      'threatLevel': calculateThreatLevel(gs).name,
    };
  }
}
