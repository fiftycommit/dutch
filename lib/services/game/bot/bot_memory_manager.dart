import 'dart:math';
import '../../../models/game_settings.dart';
import '../../../models/player.dart';
import 'bot_difficulty.dart';

/// Gestion de la mémoire des bots
/// Principe GRASP: Information Expert - Gère la mémoire du bot
class BotMemoryManager {
  static final Random _random = Random();

  /// Applique la décroissance de la mémoire du bot
  static void applyMemoryDecay(Player bot, BotDifficulty difficulty) {
    if (bot.knownCards.isEmpty || bot.mentalMap.isEmpty) return;

    for (int i = 0; i < bot.knownCards.length; i++) {
      if (bot.knownCards[i] && _random.nextDouble() < difficulty.forgetChancePerTurn) {
        bot.forgetCard(i);
      }
    }
  }

  /// Choisit une carte inconnue à regarder
  static int chooseCardToLook(Player bot, BotDifficulty difficulty) {
    List<int> unknown = [];
    for (int i = 0; i < bot.hand.length; i++) {
      if (i >= bot.mentalMap.length || bot.mentalMap[i] == null) {
        unknown.add(i);
      }
    }
    
    if (unknown.isNotEmpty) {
      return unknown[_random.nextInt(unknown.length)];
    }

    // Si toutes les cartes sont connues, regarder la pire (Or/Platine)
    if (bot.botBehavior == BotBehavior.balanced && 
        (difficulty.name == "Or" || difficulty.name == "Platine")) {
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

  /// Retourne le minimum de points dans la main d'un joueur
  static int minPointsInHand(Player player) {
    if (player.hand.isEmpty) return 0;
    int minPoints = player.hand.first.points;
    for (int i = 1; i < player.hand.length; i++) {
      int points = player.hand[i].points;
      if (points < minPoints) {
        minPoints = points;
      }
    }
    return minPoints;
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
}
