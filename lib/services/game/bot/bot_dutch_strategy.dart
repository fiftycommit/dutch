import '../../../models/game_state.dart';
import '../../../models/player.dart';
import 'bot_config.dart';
import 'bot_difficulty.dart';
import 'bot_personality.dart';
import 'bot_memory_manager.dart';
import 'discard_tracker.dart';

/// Stratégie de décision pour appeler Dutch
/// Logique multi‑paramètres (sans seuils de score fixes)
class BotDutchStrategy {
  /// Tracker de défausses partagé (comptage de cartes)
  static final DiscardTracker discardTracker = DiscardTracker();

  /// Décide si le bot doit appeler Dutch
  static bool shouldCallDutch(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    BotGamePhase phase, {
    BotPersonality? personality,
  }) {
    if (!_canDutchStateBased(gs, bot, difficulty)) return false;
    return _shouldDutchStateBased(gs, bot, difficulty, personality);
  }

  /// Vérifie si le bot PEUT Dutch (conditions nécessaires)
  static bool _canDutchStateBased(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
  ) {
    // RÈGLE FONDAMENTALE : le bot doit connaître TOUTES ses cartes
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
  ///
  /// RÈGLE DU JEU : Si tu Dutch et que tu n'as PAS le plus petit score,
  /// tu es DERNIER. C'est un risque énorme → le bot doit être CONFIANT
  /// qu'il a le plus petit score avant de Dutch.
  static bool _shouldDutchStateBased(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    BotPersonality? personality,
  ) {
    final myScore = bot.getKnownScore();

    // Score 0 (main vide ou toutes les cartes à 0 pts) = Dutch garanti gagnant
    if (myScore == 0) return true;

    // Score <= 2 et tous les adversaires ont 3+ cartes = quasi impossible qu'ils aient moins
    if (myScore <= 2) {
      final allOpponentsHaveMany = gs.players
          .where((p) => p.id != bot.id)
          .every((p) => p.hand.length >= 3);
      if (allOpponentsHaveMany) return true;
    }

    // Si je viens de rater un match ou de prendre une pénalité, ne Dutch pas
    if (_recentMatchFail(gs, bot) || _recentPenalty(gs, bot)) {
      return false;
    }

    // Estimer les scores de tous les adversaires
    // et vérifier si le bot pense avoir le plus petit score
    int lowestOpponentEstimate = 999;
    for (final opponent in gs.players) {
      if (opponent.id == bot.id) continue;
      if (opponent.hand.isEmpty) continue;

      final estimatedScore = _estimateOpponentScore(opponent);
      if (estimatedScore < lowestOpponentEstimate) {
        lowestOpponentEstimate = estimatedScore;
      }
    }

    // RÈGLE FONDAMENTALE : ne Dutch que si on pense avoir le plus petit score
    // Si même score, celui qui Dutch gagne → on autorise l'égalité
    if (myScore > lowestOpponentEstimate) {
      return false;
    }

    // OK, le bot pense avoir le plus petit score.
    // Maintenant, est-ce que l'écart est suffisant pour prendre le risque ?
    // (les estimations peuvent être fausses)
    final margin = lowestOpponentEstimate - myScore;

    // Score très bas (0-5) : Dutch si au moins 3 pts d'écart
    if (myScore <= 5 && margin >= 3) {
      return true;
    }

    // Score moyen (6-10) : Dutch si au moins 5 pts d'écart
    if (myScore <= 10 && margin >= 5) {
      return true;
    }

    // Score élevé (11+) : Dutch seulement si très gros écart (8+ pts)
    if (myScore <= 15 && margin >= 8) {
      return true;
    }

    // Score > 15 : ne Dutch jamais, trop risqué
    return false;
  }

  /// Estime le score d'un adversaire
  static int _estimateOpponentScore(Player opponent) {
    if (opponent.isHuman) {
      // Le score de l'humain est toujours réel
      return opponent.getKnownScore();
    }
    // Estimer via le discard tracker
    final estimate = discardTracker.estimateOpponentHand(
      opponent.id, opponent.hand.length,
    );
    return estimate.estimatedScore.round();
  }

  static bool _recentMatchFail(GameState gs, Player player) {
    return _recentActionContains(gs, player.name, ['rate son match']);
  }

  static bool _recentPenalty(GameState gs, Player player) {
    return _recentActionContains(gs, player.name, ['pénalité', 'penalite']);
  }

  static bool _recentActionContains(GameState gs, String playerName, List<String> keywords,
      {int limit = 12}) {
    final name = playerName.toLowerCase();
    int count = 0;
    for (final entry in gs.actionHistory) {
      if (count >= limit) break;
      count++;
      final lower = entry.toLowerCase();
      if (!lower.contains(name)) continue;
      for (final keyword in keywords) {
        if (lower.contains(keyword)) return true;
      }
    }
    return false;
  }
}
