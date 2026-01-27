import 'package:flutter/painting.dart';
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
  final bool isSpectator;

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
    this.isSpectator = false,
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
        isSpectator = other.isSpectator,
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

    mentalMap = List<PlayingCard?>.filled(hand.length, null, growable: true);
    knownCards = List<bool>.filled(hand.length, false, growable: true);

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
    mentalMap = List<PlayingCard?>.filled(hand.length, null, growable: true);
    knownCards = List<bool>.filled(hand.length, false, growable: true);
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
    if (!isHuman) {
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

    // Generate consistent avatar based on ID
    final avatars = [
      "👩🏾‍💻",
      "👨‍💻",
      "🧑‍🚀",
      "🦸",
      "🦹",
      "🧙",
      "🧛",
      "🧞",
      "🧝",
      "🧟"
    ];
    final hash = id.hashCode.abs();
    return avatars[hash % avatars.length];
  }

  Color get avatarColor {
    if (!isHuman) return const Color(0xFF2d5f3e);

    // Generate consistent color based on ID
    final hash = id.hashCode.abs();
    final hue = (hash % 360).toDouble();
    return HSVColor.fromAHSV(1.0, hue, 0.7, 0.8).toColor();
  }

  // Sérialisation JSON pour multijoueur
  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as String,
      name: json['name'] as String,
      isHuman: json['isHuman'] as bool,
      botBehavior: json['botBehavior'] != null
          ? BotBehavior.values[json['botBehavior'] as int]
          : null,
      botSkillLevel: json['botSkillLevel'] != null
          ? BotSkillLevel.values[json['botSkillLevel'] as int]
          : null,
      position: json['position'] as int? ?? 0,
      isSpectator: json['isSpectator'] as bool? ?? false,
      hand: (json['hand'] as List?)
              ?.map((e) => PlayingCard.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      knownCards: (json['knownCards'] as List?)?.cast<bool>() ?? [],
      // Note: mentalMap, dutchHistory et consecutiveBadDraws ne sont pas sérialisés
      // car ils sont gérés côté serveur pour les bots
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isHuman': isHuman,
      'botBehavior': botBehavior?.index,
      'botSkillLevel': botSkillLevel?.index,
      'position': position,
      'isSpectator': isSpectator,
      'hand': hand.map((c) => c.toJson()).toList(),
      'knownCards': knownCards,
      // Note: mentalMap, dutchHistory et consecutiveBadDraws ne sont pas inclus
    };
  }
}
