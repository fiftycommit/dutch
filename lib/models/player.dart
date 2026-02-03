import 'package:flutter/painting.dart';
import 'playing_card.dart';
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
  final Map<String, double>? aiParameters;
  final int position;
  final bool isSpectator;

  List<PlayingCard> hand;
  List<bool> knownCards;
  List<PlayingCard?> mentalMap;
  int consecutiveBadDraws;
  List<DutchAttempt> dutchHistory;

  /// Mémoire des cartes espionnées chez les adversaires
  /// Map: playerId -> Map[cardIndex, PlayingCard]
  /// Permet au bot de se souvenir des cartes qu'il a vues chez les autres
  Map<String, Map<int, PlayingCard>> spyMemory;

  Player({
    required this.id,
    required this.name,
    required this.isHuman,
    this.botBehavior,
    this.botSkillLevel,
    this.aiParameters,
    this.position = 0,
    this.isSpectator = false,
    List<PlayingCard>? hand,
    List<bool>? knownCards,
    List<PlayingCard?>? mentalMap,
    this.consecutiveBadDraws = 0,
    List<DutchAttempt>? dutchHistory,
    Map<String, Map<int, PlayingCard>>? spyMemory,
  })  : hand = hand ?? [],
        knownCards = knownCards ?? [],
        mentalMap = mentalMap ?? [],
        dutchHistory = dutchHistory ?? [],
        spyMemory = spyMemory ?? {};

  Player.clone(Player other)
      : id = other.id,
        name = other.name,
        isHuman = other.isHuman,
        botBehavior = other.botBehavior,
        botSkillLevel = other.botSkillLevel,
        aiParameters = other.aiParameters == null
            ? null
            : Map<String, double>.from(other.aiParameters!),
        position = other.position,
        isSpectator = other.isSpectator,
        hand = List.from(other.hand),
        knownCards = List.from(other.knownCards),
        mentalMap = List.from(other.mentalMap),
        consecutiveBadDraws = other.consecutiveBadDraws,
        dutchHistory = List.from(other.dutchHistory),
        spyMemory = Map.from(other.spyMemory);

  int calculateScore() {
    int score = 0;
    for (var card in hand) {
      score += card.points;
    }
    return score;
  }

  /// Score des cartes CONNUES uniquement (pas d'estimation pour les inconnues)
  /// Retourne la somme des points des cartes que le bot connaît vraiment
  int getKnownScore() {
    if (isHuman) {
      return calculateScore();
    }

    int knownScore = 0;

    for (int i = 0; i < hand.length; i++) {
      if (i < mentalMap.length && mentalMap[i] != null) {
        knownScore += mentalMap[i]!.points;
      }
    }

    return knownScore;
  }

  /// Confiance de la mémoire (0.0 = rien connu, 1.0 = tout connu)
  double getMemoryConfidence() {
    if (isHuman) return 1.0;
    if (hand.isEmpty) return 1.0;
    return knownCardCount / hand.length;
  }

  /// Nombre de cartes inconnues dans la main
  int get unknownCardCount => hand.length - knownCardCount;

  /// Vérifie si le bot connaît TOUTES ses cartes
  bool get knowsAllCards => unknownCardCount == 0;

  /// @deprecated Utilisez getKnownScore() à la place
  int getEstimatedScore() => getKnownScore();

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

  /// Mémorise une carte espionnée chez un adversaire
  void rememberSpiedCard(String opponentId, int cardIndex, PlayingCard card) {
    spyMemory.putIfAbsent(opponentId, () => {});
    spyMemory[opponentId]![cardIndex] = card;
  }

  /// Oublie les cartes espionnées d'un adversaire (après un Joker par exemple)
  void forgetSpiedCards(String opponentId) {
    spyMemory.remove(opponentId);
  }

  /// Invalide une carte espionnée (après un échange)
  void invalidateSpiedCard(String opponentId, int cardIndex) {
    if (spyMemory.containsKey(opponentId)) {
      spyMemory[opponentId]!.remove(cardIndex);
    }
  }

  /// Retourne le score estimé d'un adversaire basé sur les cartes espionnées
  int getEstimatedOpponentScore(String opponentId, int opponentHandSize) {
    if (!spyMemory.containsKey(opponentId)) {
      // Aucune info → estimer avec valeur moyenne (6)
      return opponentHandSize * 6;
    }

    final knownCards = spyMemory[opponentId]!;
    int knownScore = 0;
    int knownCount = 0;

    for (final entry in knownCards.entries) {
      if (entry.key < opponentHandSize) {
        knownScore += entry.value.points;
        knownCount++;
      }
    }

    // Cartes inconnues → estimer avec valeur moyenne (6)
    int unknownCount = opponentHandSize - knownCount;
    return knownScore + (unknownCount * 6);
  }

  /// Retourne les cartes espionnées d'un adversaire
  Map<int, PlayingCard>? getSpiedCards(String opponentId) {
    return spyMemory[opponentId];
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

  /// Retourne le nom d'affichage avec position pour les bots (solo)
  /// Utilise l'index passé pour déterminer Gauche/Haut/Droite
  String getPositionDisplay(int indexInGame) {
    if (isHuman) return name;
    
    String position;
    switch (indexInGame) {
      case 1:
        position = "Bot Gauche";
        break;
      case 2:
        position = "Bot Haut";
        break;
      case 3:
        position = "Bot Droite";
        break;
      default:
        position = name;
    }
    return "$displayAvatar $position";
  }

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

  /// Crée une copie du joueur avec des paramètres optionnellement modifiés.
  /// Utilisé principalement pour injecter les paramètres appris du ML.
  Player copyWith({
    String? id,
    String? name,
    bool? isHuman,
    BotBehavior? botBehavior,
    BotSkillLevel? botSkillLevel,
    Map<String, double>? aiParameters,
    int? position,
    bool? isSpectator,
  }) {
    return Player(
      id: id ?? this.id,
      name: name ?? this.name,
      isHuman: isHuman ?? this.isHuman,
      botBehavior: botBehavior ?? this.botBehavior,
      botSkillLevel: botSkillLevel ?? this.botSkillLevel,
      aiParameters: aiParameters ?? (this.aiParameters != null 
          ? Map<String, double>.from(this.aiParameters!)
          : null),
      position: position ?? this.position,
      isSpectator: isSpectator ?? this.isSpectator,
      hand: List.from(hand),
      knownCards: List.from(knownCards),
      mentalMap: List.from(mentalMap),
      consecutiveBadDraws: consecutiveBadDraws,
      dutchHistory: List.from(dutchHistory),
    );
  }
}
