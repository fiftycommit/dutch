import 'dart:math';
import '../../../models/game_settings.dart';
import '../../../models/game_state.dart';
import '../../../models/player.dart';
import 'bot_difficulty.dart';
import 'bot_personality.dart';
import '../engine_random.dart';

/// Gestion de la mémoire des bots
/// Principe GRASP: Information Expert - Gère la mémoire du bot
class BotMemoryManager {
  static Random get _random => EngineRandom.instance;

  /// Applique la décroissance de la mémoire du bot
  static void applyMemoryDecay(
    Player bot,
    BotDifficulty difficulty, {
    BotPersonality? personality,
  }) {
    if (bot.knownCards.isEmpty || bot.mentalMap.isEmpty) return;

    double forgetChance = difficulty.forgetChancePerTurn;

    // HARDCORE FIX: Pour les difficultés hautes, ne PAS forcer un minimum de 1%
    // Platine/Or/Nightmare/Insane/Hard/Impossible peuvent avoir une mémoire parfaite
    final isHardcore = difficulty.name == "Difficile" ||
        difficulty.name == "Platine" ||
        difficulty.name == "Or" ||
        difficulty.name == "Hard" ||
        difficulty.name == "Insane" ||
        difficulty.name == "Nightmare" ||
        difficulty.name == "Impossible";

    if (personality != null) {
      final retention = personality.memoryRetention;
      // Réduction de la chance d'oubli basée sur la rétention
      forgetChance = forgetChance * (1.0 - (retention * 0.7));

      // HARDCORE FIX: Clamp différent selon le niveau
      if (isHardcore) {
        // Les bots hardcore peuvent avoir une mémoire parfaite (0%)
        forgetChance = forgetChance.clamp(0.0, 0.5);
      } else {
        // Les bots normaux gardent un minimum d'oubli
        forgetChance = forgetChance.clamp(0.01, 1.0);
      }
    }

    for (int i = 0; i < bot.knownCards.length; i++) {
      if (bot.knownCards[i] && _random.nextDouble() < forgetChance) {
        bot.forgetCard(i);
      }
    }
  }

  /// Choisit une carte inconnue à regarder
  static int chooseCardToLook(Player bot, BotDifficulty difficulty) {
    if (bot.hand.isEmpty) return 0;

    List<int> unknown = [];
    for (int i = 0; i < bot.hand.length; i++) {
      if (i >= bot.mentalMap.length || bot.mentalMap[i] == null) {
        unknown.add(i);
      }
    }

    if (unknown.isNotEmpty) {
      return unknown[_random.nextInt(unknown.length)];
    }

    // HARDCORE FIX: Niveaux hardcore regardent la pire carte connue
    final isHardcore = difficulty.name == "Difficile" ||
        difficulty.name == "Or" ||
        difficulty.name == "Platine" ||
        difficulty.name == "Hard" ||
        difficulty.name == "Insane" ||
        difficulty.name == "Nightmare" ||
        difficulty.name == "Impossible";

    // Si toutes les cartes sont connues, regarder la pire
    if (bot.botBehavior == BotBehavior.balanced && isHardcore) {
      int worstIdx = 0;
      int worstVal = -1;
      for (int i = 0; i < bot.mentalMap.length; i++) {
        if (bot.mentalMap[i] != null && bot.mentalMap[i]!.points > worstVal) {
          worstVal = bot.mentalMap[i]!.points;
          worstIdx = i;
        }
      }
      return worstIdx;
    }

    return _random.nextInt(bot.hand.length);
  }

  /// Choisit une carte inconnue
  static int chooseUnknownCard(Player bot) {
    List<int> unknownIndices = [];
    for (int i = 0; i < bot.hand.length; i++) {
      if (i >= bot.mentalMap.length || bot.mentalMap[i] == null) {
        unknownIndices.add(i);
      }
    }
    if (unknownIndices.isNotEmpty) {
      return unknownIndices[_random.nextInt(unknownIndices.length)];
    }
    return 0;
  }

  /// Choisit la pire carte connue
  static int chooseBadCard(Player bot) {
    int worstIdx = 0;
    int worstValue = -1;

    for (int i = 0; i < bot.mentalMap.length; i++) {
      if (bot.mentalMap[i] != null && bot.mentalMap[i]!.points > worstValue) {
        worstValue = bot.mentalMap[i]!.points;
        worstIdx = i;
      }
    }

    if (worstValue == -1) {
      return chooseUnknownCard(bot);
    }

    return worstIdx;
  }

  /// Compte les cartes connues d'un joueur
  static int countKnownCards(Player player) {
    int count = 0;
    for (final known in player.knownCards) {
      if (known) count++;
    }
    return count;
  }

  /// Retourne les indices des cartes inconnues
  static List<int> getUnknownIndices(Player bot) {
    List<int> indices = [];
    for (int i = 0; i < bot.hand.length; i++) {
      if (i >= bot.mentalMap.length || bot.mentalMap[i] == null) {
        indices.add(i);
      }
    }
    return indices;
  }

  /// Détecte les doublons dans la mentalMap du bot
  /// Retourne une map: rang -> liste des indices
  static Map<String, List<int>> findDoublons(Player bot) {
    final Map<String, List<int>> cardsByRank = {};

    for (int i = 0; i < bot.mentalMap.length && i < bot.hand.length; i++) {
      final card = bot.mentalMap[i];
      if (card != null) {
        final rank = card.value; // A, 2, 3, ..., 10, V, D, R, JOKER
        cardsByRank.putIfAbsent(rank, () => []);
        cardsByRank[rank]!.add(i);
      }
    }

    // Garder seulement les doublons (2+ cartes du même rang)
    cardsByRank.removeWhere((_, indices) => indices.length < 2);
    return cardsByRank;
  }

  /// Vérifie si le bot a un doublon du rang donné
  static List<int>? getDoublonIndices(Player bot, String rank) {
    final doublons = findDoublons(bot);
    return doublons[rank];
  }

  /// Retourne le doublon avec la plus haute valeur (priorité pour échange)
  /// Logique: 2×4 = 8 pts, si on échange un 4 contre un 6, on a 4+6=10 mais on peut
  /// matcher l'autre 4 pendant la défausse collective → économie de 4 pts
  static (int, int, int)? getBestDoublonForExchange(
      Player bot, int drawnCardValue) {
    final doublons = findDoublons(bot);
    if (doublons.isEmpty) return null;

    // Chercher le meilleur doublon à échanger
    // Condition: valeur du doublon < valeur de la carte piochée
    // ET le gain est positif (on économise des points via le match)
    int bestDoublonValue = -1;
    List<int>? bestIndices;

    for (final entry in doublons.entries) {
      final indices = entry.value;
      if (indices.length >= 2) {
        final doublonValue = bot.mentalMap[indices[0]]!.points;

        // Si la carte piochée est SUPÉRIEURE au doublon, on peut faire l'échange
        // Car: doublon×2 = 2×V vs doublon + pioche = V + P, puis match doublon
        // Gain = 2V - (V + P - V) = V - P + V = 2V - P
        // Si P > V, on perd en score immédiat MAIS on gagne car on peut matcher
        // Donc on accepte si P > V (on échange le doublon contre une carte plus haute)
        // Exemple: 2×4 = 8, pioche 6 → 4+6 = 10 MAIS match 4 → score final = 6
        // >= car même à score égal (pioche == doublon), on gagne une carte en moins
        if (drawnCardValue >= doublonValue && doublonValue > bestDoublonValue) {
          bestDoublonValue = doublonValue;
          bestIndices = indices;
        }
      }
    }

    if (bestIndices != null && bestIndices.length >= 2) {
      // Retourne (indice à échanger, indice à garder pour match, valeur du doublon)
      return (bestIndices[0], bestIndices[1], bestDoublonValue);
    }

    return null;
  }

  /// Retourne la valeur maximale des cartes CONNUES du bot
  static int getMaxKnownCardValue(Player bot) {
    int maxValue = -1;
    for (int i = 0; i < bot.mentalMap.length && i < bot.hand.length; i++) {
      final card = bot.mentalMap[i];
      if (card != null && card.points > maxValue) {
        maxValue = card.points;
      }
    }
    return maxValue;
  }

  /// Vérifie si toutes les cartes connues sont inférieures à une valeur
  static bool allKnownCardsBelow(Player bot, int threshold) {
    for (int i = 0; i < bot.mentalMap.length && i < bot.hand.length; i++) {
      final card = bot.mentalMap[i];
      if (card != null && card.points >= threshold) {
        return false;
      }
    }
    return true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPTAGE DE CARTES
  // Permet au bot de savoir quels rangs sont épuisés
  // ═══════════════════════════════════════════════════════════════════════════

  /// Compte le nombre de cartes de chaque rang dans la défausse
  /// Retourne une map: rang -> nombre de cartes vues
  static Map<String, int> countDiscardedRanks(GameState gs) {
    final Map<String, int> counts = {};

    for (final card in gs.discardPile) {
      final rank = card.value;
      counts[rank] = (counts[rank] ?? 0) + 1;
    }

    return counts;
  }

  /// Vérifie si un rang est épuisé (4 cartes déjà vues)
  static bool isRankDepleted(GameState gs, String rank) {
    final counts = countDiscardedRanks(gs);
    return (counts[rank] ?? 0) >= 4;
  }

  /// Calcule la probabilité de match pour un rang donné
  /// Prend en compte les cartes déjà défaussées
  static double getMatchProbability(GameState gs, Player bot, String rank) {
    final discardCounts = countDiscardedRanks(gs);
    final discardedOfRank = discardCounts[rank] ?? 0;

    // 4 cartes par rang dans un jeu standard
    final remainingOfRank = 4 - discardedOfRank;
    if (remainingOfRank <= 0) return 0.0;

    // Compter les cartes que le bot connaît de ce rang dans sa main
    int knownInHand = 0;
    for (final card in bot.mentalMap) {
      if (card != null && card.value == rank) {
        knownInHand++;
      }
    }

    // Cartes restantes potentiellement matchables
    final matchableCards = remainingOfRank - knownInHand;
    if (matchableCards <= 0) return 0.0;

    // Estimer le nombre total de cartes inconnues
    final totalKnownCards = gs.discardPile.length + bot.knownCardCount;
    final totalUnknown = 52 - totalKnownCards;
    if (totalUnknown <= 0) return 0.0;

    return matchableCards / totalUnknown;
  }

  /// Retourne les rangs avec forte probabilité de match (>25%)
  static List<String> getHighProbabilityMatchRanks(GameState gs, Player bot) {
    final ranks = <String>[];
    final allRanks = [
      'A',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '10',
      'V',
      'D',
      'R'
    ];

    for (final rank in allRanks) {
      if (getMatchProbability(gs, bot, rank) > 0.25) {
        ranks.add(rank);
      }
    }

    return ranks;
  }

  /// Calcule le score moyen attendu des cartes restantes dans le deck
  /// Utile pour décider si une carte piochée est "bonne" ou "mauvaise"
  static double getExpectedDeckCardValue(GameState gs) {
    final discardCounts = countDiscardedRanks(gs);

    // Points par rang
    final rankPoints = {
      'A': 1,
      '2': 2,
      '3': 3,
      '4': 4,
      '5': 5,
      '6': 6,
      '7': 7,
      '8': 8,
      '9': 9,
      '10': 10,
      'V': 10,
      'D': 10,
      'R': 13,
      'JOKER': 0,
    };

    double totalPoints = 0;
    int totalCards = 0;

    for (final entry in rankPoints.entries) {
      final rank = entry.key;
      final points = entry.value;
      final discarded = discardCounts[rank] ?? 0;
      final remaining =
          (rank == 'R' ? 4 : (rank == 'JOKER' ? 2 : 4)) - discarded;

      if (remaining > 0) {
        totalPoints += points * remaining;
        totalCards += remaining;
      }
    }

    return totalCards > 0 ? totalPoints / totalCards : 6.0;
  }

  /// Valeur attendue d'une carte inconnue précise de la main du bot.
  ///
  /// Combine:
  /// - l'espérance neutre du deck,
  /// - un hint qualitatif local (si présent),
  /// - la fraîcheur temporelle du hint.
  ///
  /// Sans hint fiable, retourne simplement l'espérance du deck.
  static double getUnknownBeliefExpectedValue(
    GameState gs,
    Player bot,
    int handIndex,
  ) {
    final base = getExpectedDeckCardValue(gs);
    final quality = bot.getUnknownCardHintQuality(handIndex);
    final confidence = bot.getUnknownCardHintConfidence(handIndex);
    final hintAction = bot.getUnknownCardHintAction(handIndex);

    if (quality == null || confidence == null || confidence <= 0) {
      return base;
    }

    final age =
        hintAction == null ? 0 : (gs.actionCount - hintAction).clamp(0, 30);
    final freshness = pow(0.93, age).toDouble();
    final effectiveConfidence = (confidence * freshness).clamp(0.0, 1.0);

    // quality +1 => carte probablement très bonne (valeur attendue plus basse)
    // quality -1 => carte probablement mauvaise (valeur attendue plus haute)
    final hintedValue = (base - (quality * 3.2)).clamp(0.0, 13.0);

    final blended = (base * (1 - effectiveConfidence)) +
        (hintedValue * effectiveConfidence);
    return blended.clamp(0.0, 13.0);
  }

  /// Choisit la carte inconnue la plus probable d'être "mauvaise" (score élevé).
  static int chooseWorstUnknownByBelief(
    GameState gs,
    Player bot,
    List<int> unknownIndices,
  ) {
    if (unknownIndices.isEmpty) return 0;
    if (unknownIndices.length == 1) return unknownIndices.first;

    int bestIndex = unknownIndices.first;
    double bestExpected = -1;
    double bestConfidence = -1;

    for (final idx in unknownIndices) {
      final expected = getUnknownBeliefExpectedValue(gs, bot, idx);
      final confidence = bot.getUnknownCardHintConfidence(idx) ?? 0.0;

      if (expected > bestExpected) {
        bestExpected = expected;
        bestConfidence = confidence;
        bestIndex = idx;
        continue;
      }
      if ((expected - bestExpected).abs() <= 0.25 &&
          confidence > bestConfidence) {
        bestConfidence = confidence;
        bestIndex = idx;
      }
    }

    return bestIndex;
  }
}
