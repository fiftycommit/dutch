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

  /// ✅ AMÉLIORATION: Estimation de score plus réaliste pour les bots
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

    // Pour les cartes inconnues, utiliser une estimation basée sur :
    // - La moyenne des cartes connues (si on en a)
    // - Sinon, estimer 5 points (moyenne réaliste d'un deck)
    int unknownCount = hand.length - knownCount;
    
    if (unknownCount > 0) {
      int estimatePerUnknown;
      
      if (knownCount >= 2) {
        // Si on connaît au moins 2 cartes, utiliser leur moyenne
        estimatePerUnknown = (knownSum / knownCount).round();
        // Mais plafonner entre 4 et 7
        estimatePerUnknown = estimatePerUnknown.clamp(4, 7);
      } else {
        // Sinon, estimation conservatrice de 5 points
        estimatePerUnknown = 5;
      }
      
      estimatedScore += unknownCount * estimatePerUnknown;
    }

    debugPrint("📊 [getEstimatedScore] $name: $knownCount cartes connues, score estimé = $estimatedScore");
    return estimatedScore;
  }

  /// ✅ NOUVEAU: Initialiser la mentalMap avec les 2 premières cartes (comme le joueur humain)
  void initializeBotMemory() {
    if (isHuman) return;
    if (hand.length < 2) return;

    // Le bot mémorise ses 2 premières cartes (indices 0 et 1)
    // Comme le joueur humain qui choisit 2 cartes à mémoriser
    mentalMap = List.filled(hand.length, null);
    knownCards = List.filled(hand.length, false);
    
    // Mémoriser les cartes aux indices 0 et 1
    mentalMap[0] = hand[0];
    mentalMap[1] = hand[1];
    knownCards[0] = true;
    knownCards[1] = true;
    
    debugPrint("🧠 [initializeBotMemory] $name mémorise: ${hand[0].value} et ${hand[1].value}");
  }

  void updateMentalMap(int index, PlayingCard card) {
    while (mentalMap.length <= index) {
      mentalMap.add(null);
    }

    mentalMap[index] = card;

    if (index < knownCards.length) {
      knownCards[index] = true;
    }
    
    debugPrint("🧠 [updateMentalMap] $name mémorise carte #$index: ${card.value}");
  }

  void resetMentalMap() {
    mentalMap = List.filled(hand.length, null);
    knownCards = List.filled(hand.length, false);
    debugPrint("🧠 [resetMentalMap] $name oublie tout!");
  }

  void forgetCard(int index) {
    if (index >= 0 && index < mentalMap.length) {
      mentalMap[index] = null;
    }
    if (index >= 0 && index < knownCards.length) {
      knownCards[index] = false;
    }
    debugPrint("💭 [forgetCard] $name oublie carte #$index");
  }

  /// ✅ NOUVEAU: Nombre de cartes connues
  int get knownCardCount {
    int count = 0;
    for (int i = 0; i < mentalMap.length && i < hand.length; i++) {
      if (mentalMap[i] != null) count++;
    }
    return count;
  }

  /// ✅ NOUVEAU: Score des cartes connues uniquement
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