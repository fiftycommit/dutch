import 'card.dart';
import 'game_settings.dart';

class DutchAttempt {
  final int estimatedScore;
  final int actualScore;
  final bool won;
  final int opponentsCount;

  DutchAttempt({
    required this.estimatedScore,
    required this.actualScore,
    required this.won,
    required this.opponentsCount,
  });

  double get accuracy => (estimatedScore - actualScore).abs() <= 2 ? 1.0 : 0.5;
}

class Player {
  final String id;
  final String name;
  final bool isHuman;
  final BotBehavior? botBehavior;
  final BotSkillLevel? botSkillLevel;
  final int position;

  List<PlayingCard> hand;
  List<bool> knownCards;
  List<PlayingCard?> mentalMap;
  int consecutiveBadDraws;
  List<DutchAttempt> dutchHistory;

  Player({
    required this.id,
    required this.name,
    required this.isHuman,
    this.botBehavior,
    this.botSkillLevel,
    this.position = 0,
    List<PlayingCard>? hand,
    List<bool>? knownCards,
    List<PlayingCard?>? mentalMap,
    this.consecutiveBadDraws = 0,
    List<DutchAttempt>? dutchHistory,
  })  : hand = hand ?? [],
        knownCards = knownCards ?? [],
        mentalMap = mentalMap ?? [],
        dutchHistory = dutchHistory ?? [];

  Player.clone(Player other)
      : id = other.id,
        name = other.name,
        isHuman = other.isHuman,
        botBehavior = other.botBehavior,
        botSkillLevel = other.botSkillLevel,
        position = other.position,
        hand = List.from(other.hand),
        knownCards = List.from(other.knownCards),
        mentalMap = List.from(other.mentalMap),
        consecutiveBadDraws = other.consecutiveBadDraws,
        dutchHistory = List.from(other.dutchHistory);

  int calculateScore() {
    int score = 0;
    for (var card in hand) {
      score += card.points;
    }
    return score;
  }

  int getEstimatedScore() {
    if (isHuman) {
      return calculateScore();
    }

    int estimatedScore = 0;
    int knownCount = 0;
    int knownSum = 0;

    for (int i = 0; i < hand.length; i++) {
      if (i < mentalMap.length && mentalMap[i] != null) {
        int cardPoints = mentalMap[i]!.points;
        estimatedScore += cardPoints;
        knownSum += cardPoints;
        knownCount++;
      }
    }

    int unknownCount = hand.length - knownCount;

    if (unknownCount > 0) {
      int estimatePerUnknown;

      if (knownCount >= 2) {
        estimatePerUnknown = (knownSum / knownCount).round();
        estimatePerUnknown = estimatePerUnknown.clamp(4, 7);
      } else {
        estimatePerUnknown = 5;
      }

      estimatedScore += unknownCount * estimatePerUnknown;
    }

    return estimatedScore;
  }

  void initializeBotMemory() {
    if (isHuman) return;
    if (hand.length < 2) return;

    mentalMap = List.filled(hand.length, null);
    knownCards = List.filled(hand.length, false);

    mentalMap[0] = hand[0];
    mentalMap[1] = hand[1];
    knownCards[0] = true;
    knownCards[1] = true;
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

  int get knownCardCount {
    int count = 0;
    for (int i = 0; i < mentalMap.length && i < hand.length; i++) {
      if (mentalMap[i] != null) count++;
    }
    return count;
  }

  int get knownCardsScore {
    int score = 0;
    for (int i = 0; i < mentalMap.length && i < hand.length; i++) {
      if (mentalMap[i] != null) {
        score += mentalMap[i]!.points;
      }
    }
    return score;
  }

  String get displayName => name;

  String get displayAvatar {
    if (isHuman) return "👩🏾‍💻";

    if (botBehavior != null) {
      switch (botBehavior!) {
        case BotBehavior.fast:
          return "🏃";
        case BotBehavior.aggressive:
          return "⚔️";
        case BotBehavior.balanced:
          return "🧠";
      }
    }
    return "🤖";
  }
}
