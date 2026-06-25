import '../../../models/game_state.dart';
import '../../../models/player.dart';
import 'discard_tracker.dart';

/// Signal de « menace » d'un joueur, re-dérivé **headless** (pur Dart) à partir
/// de la formule de [HumanThreatTracker.calculateThreatLevel].
///
/// Pourquoi un fichier dédié plutôt que réutiliser `HumanThreatTracker` :
/// ce dernier (1) cible `players.where(isHuman)` — inexistant en self-play, et
/// (2) dépend d'un état alimenté par la couche provider Flutter
/// (`recordHumanMatch`/`onNewTurn`/`initializeRound`), jamais câblé en headless.
/// On garde donc `HumanThreatTracker` intact (couplé à l'UI/au vrai humain) et on
/// reproduit ici **la même arithmétique**, sourcée pour un joueur cible arbitraire
/// (le « proxy » dynamique du runner RL) via [DiscardTracker], déjà maintenu dans
/// la boucle moteur.
///
/// IMPORTANT : aucune nouvelle heuristique ni bonus tactique. L'arithmétique est
/// la copie littérale des lignes 116-173 de `human_threat_tracker.dart` ; seules
/// les *sources* des entrées diffèrent (DiscardTracker au lieu de l'état UI).
/// Fonction pure : aucun tirage `EngineRandom`, ne perturbe pas le déterminisme.
class HeadlessThreatSignal {
  HeadlessThreatSignal._();

  /// Menace de [target] dans l'état [gs], inputs sourcés depuis [tracker].
  /// Retourne le score brut (mêmes points/seuils que l'original ; non borné à
  /// 100 — l'original ne clampe pas non plus, il compare aux paliers 25/45/70).
  static double scoreFor(GameState gs, Player target, DiscardTracker tracker) {
    final estimate = tracker.estimateOpponentHand(target.id, target.hand.length);
    final currentScore = target.getEstimatedScoreForOpponent(
      avgDiscardedPoints:
          estimate.avgDiscardedPoints > 0 ? estimate.avgDiscardedPoints : null,
      discardCount: tracker.getDiscardCount(target.id),
    );
    final initialScore =
        tracker.getRoundStartScore(target.id, fallback: currentScore);
    final matchCount = tracker.getMatchDiscardCount(target.id);
    final recentMatch =
        tracker.getRecentMatchCountInTurns(target.id, gs.turnCount,
                windowTurns: 2) >
            0;

    return formula(
      initialScore: initialScore,
      currentScore: currentScore,
      currentCards: target.hand.length,
      matchCount: matchCount,
      recentMatch: recentMatch,
    );
  }

  /// Arithmétique pure isolée du sourcing (testable à l'identique contre
  /// l'original). Réplique `HumanThreatTracker.calculateThreatLevel` 116-173.
  static double formula({
    required int initialScore,
    required int currentScore,
    required int currentCards,
    required int matchCount,
    required bool recentMatch,
  }) {
    double threatScore = 0;

    // 1) Progression du score (25 pts max)
    final scoreReduction = initialScore - currentScore;
    if (scoreReduction >= 20) {
      threatScore += 25;
    } else if (scoreReduction >= 12) {
      threatScore += 18;
    } else if (scoreReduction >= 6) {
      threatScore += 10;
    }

    // 2) Matchs réussis (30 pts max)
    if (matchCount >= 3) {
      threatScore += 30;
    } else if (matchCount >= 2) {
      threatScore += 20;
    } else if (matchCount >= 1) {
      threatScore += 10;
    }

    // 3) Nombre de cartes restantes (25 pts max)
    if (currentCards == 1) {
      threatScore += 25;
    } else if (currentCards == 2) {
      threatScore += 18;
    } else if (currentCards == 3) {
      threatScore += 8;
    }

    // 4) Score actuel absolu (20 pts max)
    if (currentScore <= 3) {
      threatScore += 20;
    } else if (currentScore <= 6) {
      threatScore += 15;
    } else if (currentScore <= 10) {
      threatScore += 8;
    }

    // 5) Momentum : match récent (10 pts)
    if (recentMatch) {
      threatScore += 10;
    }

    return threatScore;
  }
}
