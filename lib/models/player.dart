import 'card.dart';
import 'game_settings.dart';
import 'package:flutter/foundation.dart';

class Player {
  final String id;
  final String name;
  final bool isHuman;
  final BotPersonality? botPersonality;
  final int position;

  List<PlayingCard> hand;
  List<bool> knownCards;

  List<PlayingCard?> mentalMap;

  Player({
    required this.id,
    required this.name,
    required this.isHuman,
    this.botPersonality,
    this.position = 0,
    List<PlayingCard>? hand,
    List<bool>? knownCards,
    List<PlayingCard?>? mentalMap,
  })  : hand = hand ?? [],
        knownCards = knownCards ?? [],
        mentalMap = mentalMap ?? [];

  Player.clone(Player other)
      : id = other.id,
        name = other.name,
        isHuman = other.isHuman,
        botPersonality = other.botPersonality,
        position = other.position,
        hand = List.from(other.hand),
        knownCards = List.from(other.knownCards),
        mentalMap = List.from(other.mentalMap);

  int calculateScore() {
    int score = 0;
    debugPrint("🔢 [calculateScore] Calcul pour $name:");
    for (var card in hand) {
      debugPrint("   - ${card.displayName} (${card.suit}): ${card.points} pts");
      score += card.points;
    }
    debugPrint("   📊 TOTAL: $score");
    return score;
  }

  int getEstimatedScore() {
    if (isHuman) {
      return calculateScore();
    }

    int estimatedScore = 0;

    for (int i = 0; i < hand.length; i++) {
      if (i < mentalMap.length && mentalMap[i] != null) {
        estimatedScore += mentalMap[i]!.points;
      } else {
        estimatedScore += 7;
      }
    }

    return estimatedScore;
  }

  void updateMentalMap(int index, PlayingCard card) {
    while (mentalMap.length <= index) {
      mentalMap.add(null);
    }

    mentalMap[index] = card;

    if (index < knownCards.length) {
      knownCards[index] = true;
    }
  }

  void resetMentalMap() {
    mentalMap = List.filled(hand.length, null);
    knownCards = List.filled(hand.length, false);
  }

  void forgetCard(int index) {
    if (index >= 0 && index < mentalMap.length) {
      mentalMap[index] = null;
    }
    if (index >= 0 && index < knownCards.length) {
      knownCards[index] = false;
    }
  }

  String get displayName => name;

  String get displayAvatar {
    if (isHuman) return "👩🏾‍💻";

    if (botPersonality != null) {
      switch (botPersonality!) {
        case BotPersonality.beginner:
          return "👶";
        case BotPersonality.novice:
          return "😸";
        case BotPersonality.balanced:
          return "😼";
        case BotPersonality.cautious:
          return "🛡️";
        case BotPersonality.aggressive:
          return "⚔️";
        case BotPersonality.legend:
          return "👑";
      }
    }
    return "🤖";
  }
}
