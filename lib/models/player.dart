import 'dart:math';
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
  static final Random _random = Random();

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

  /// Indice qualitatif sur les cartes inconnues reçues/estimées.
  /// -1.0 = probablement mauvaise carte, +1.0 = probablement bonne carte.
  List<double?> unknownCardQualityHints;

  /// Confiance associée à [unknownCardQualityHints] (0.0..1.0).
  List<double?> unknownCardHintConfidence;

  /// Compteur d'action de la dernière mise à jour du hint.
  List<int?> unknownCardHintActionCount;

  /// Reconstruction mémoire après un Joker subi (bots Or/Platine).
  /// Mode binaire: aucune probabilité, uniquement déduction structurelle.
  bool jokerInferenceActive;
  String? jokerInferenceMode;
  List<PlayingCard> jokerInferenceKnownPool;
  String? jokerInferenceDoublonValue;
  String? jokerInferenceUniqueValue;
  int? jokerInferenceKnownUniqueIndex;
  List<int> jokerInferenceKnownDoublonIndices;
  int jokerInferenceActionCount;

  /// Mode "blackout" des bots Bronze: ils pensent connaître leurs cartes
  /// alors que leur mémoire est fausse.
  bool bronzeBlackoutActive;

  /// Action count à partir duquel le blackout n'est plus actif.
  int bronzeBlackoutUntilActionCount;

  /// Dernière action où un blackout a été déclenché (anti-spam).
  int lastBronzeBlackoutActionCount;

  /// Dernier tour où ce joueur humain a été ciblé par un Valet Bronze/Argent.
  int lastBronzeValetTargetTurn;

  /// Dernier tour où ce joueur a été ciblé par un pouvoir offensif adverse
  /// (espionnage, échange, joker).
  int lastTargetedByPowerTurn;

  /// Index des cartes regardées pendant la phase de mémorisation initiale.
  /// Public: on connaît les emplacements observés, pas les valeurs.
  List<int> memorizedCardIndices;

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
    List<double?>? unknownCardQualityHints,
    List<double?>? unknownCardHintConfidence,
    List<int?>? unknownCardHintActionCount,
    this.jokerInferenceActive = false,
    this.jokerInferenceMode,
    List<PlayingCard>? jokerInferenceKnownPool,
    this.jokerInferenceDoublonValue,
    this.jokerInferenceUniqueValue,
    this.jokerInferenceKnownUniqueIndex,
    List<int>? jokerInferenceKnownDoublonIndices,
    this.jokerInferenceActionCount = -1,
    this.bronzeBlackoutActive = false,
    this.bronzeBlackoutUntilActionCount = -1,
    this.lastBronzeBlackoutActionCount = -999,
    this.lastBronzeValetTargetTurn = -999,
    this.lastTargetedByPowerTurn = -999,
    List<int>? memorizedCardIndices,
  })  : hand = hand ?? [],
        knownCards = knownCards ?? [],
        mentalMap = mentalMap ?? [],
        dutchHistory = dutchHistory ?? [],
        spyMemory = spyMemory ?? {},
        unknownCardQualityHints = unknownCardQualityHints ?? [],
        unknownCardHintConfidence = unknownCardHintConfidence ?? [],
        unknownCardHintActionCount = unknownCardHintActionCount ?? [],
        jokerInferenceKnownPool = jokerInferenceKnownPool ?? [],
        jokerInferenceKnownDoublonIndices =
            jokerInferenceKnownDoublonIndices ?? [],
        memorizedCardIndices = memorizedCardIndices ?? [];

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
        spyMemory = Map.from(other.spyMemory),
        unknownCardQualityHints = List.from(other.unknownCardQualityHints),
        unknownCardHintConfidence = List.from(other.unknownCardHintConfidence),
        unknownCardHintActionCount =
            List.from(other.unknownCardHintActionCount),
        jokerInferenceActive = other.jokerInferenceActive,
        jokerInferenceMode = other.jokerInferenceMode,
        jokerInferenceKnownPool = List.from(other.jokerInferenceKnownPool),
        jokerInferenceDoublonValue = other.jokerInferenceDoublonValue,
        jokerInferenceUniqueValue = other.jokerInferenceUniqueValue,
        jokerInferenceKnownUniqueIndex = other.jokerInferenceKnownUniqueIndex,
        jokerInferenceKnownDoublonIndices =
            List.from(other.jokerInferenceKnownDoublonIndices),
        jokerInferenceActionCount = other.jokerInferenceActionCount,
        bronzeBlackoutActive = other.bronzeBlackoutActive,
        bronzeBlackoutUntilActionCount = other.bronzeBlackoutUntilActionCount,
        lastBronzeBlackoutActionCount = other.lastBronzeBlackoutActionCount,
        lastBronzeValetTargetTurn = other.lastBronzeValetTargetTurn,
        lastTargetedByPowerTurn = other.lastTargetedByPowerTurn,
        memorizedCardIndices = List<int>.from(other.memorizedCardIndices);

  int calculateScore() {
    int score = 0;
    for (var card in hand) {
      score += card.points;
    }
    return score;
  }

  /// Score des cartes CONNUES uniquement (pas d'estimation pour les inconnues)
  /// Retourne la somme des points des cartes que le joueur connaît vraiment
  /// Pour un humain : score réel (il connaît toutes ses cartes)
  /// Pour un bot qui s'évalue lui-même : utilise sa mentalMap
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

  /// Score estimé de ce joueur vu par un adversaire (algorithme entonnoir)
  /// L'estimation se précise au fil de la partie via les défausses observées :
  /// - Début de partie : estimation large (nb cartes × moyenne théorique)
  /// - Au fil des défausses : si l'adversaire défausse des hautes, il garde des basses
  /// - Fin de partie : estimation précise basée sur l'historique de défausse
  /// [avgDiscardedPoints] : moyenne des points défaussés par ce joueur (null si inconnu)
  /// [discardCount] : nombre de défausses observées
  int getEstimatedScoreForOpponent({
    double? avgDiscardedPoints,
    int discardCount = 0,
  }) {
    final cardCount = hand.length;
    if (cardCount == 0) return 0;

    // Aucune observation → estimation large (moyenne théorique)
    if (discardCount == 0 || avgDiscardedPoints == null) {
      return (cardCount * 6.5).round();
    }

    // Confiance : monte progressivement avec le nombre d'observations
    // 1 défausse = 20% confiance, 5+ = 100%
    final confidence = (discardCount / 5.0).clamp(0.0, 1.0);

    // Estimation basée sur les défausses (entonnoir)
    // Principe : si un joueur défausse des cartes hautes, il garde des basses
    double estimatedAvgCard;
    if (avgDiscardedPoints >= 10) {
      estimatedAvgCard = 3.0; // Défausse très haut → garde très bas
    } else if (avgDiscardedPoints >= 8) {
      estimatedAvgCard = 4.0;
    } else if (avgDiscardedPoints >= 6) {
      estimatedAvgCard = 5.5;
    } else if (avgDiscardedPoints >= 4) {
      estimatedAvgCard = 7.0;
    } else if (avgDiscardedPoints >= 2) {
      estimatedAvgCard = 8.5;
    } else {
      estimatedAvgCard = 10.0; // Défausse très bas → garde du lourd
    }

    // Interpolation entre estimation neutre et estimation informée
    final neutralEstimate = 6.5;
    final informedEstimate = estimatedAvgCard;
    final blendedAvg =
        neutralEstimate * (1 - confidence) + informedEstimate * confidence;

    return (cardCount * blendedAvg).round();
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
    memorizedCardIndices = [];
    if (hand.length < 2) return;

    mentalMap = List<PlayingCard?>.filled(hand.length, null, growable: true);
    knownCards = List<bool>.filled(hand.length, false, growable: true);

    // Bronze distrait: il regarde 2 cartes aléatoires au début.
    // Si elles ne sont pas adjacentes, il les "oublie" immédiatement.
    if (botSkillLevel == BotSkillLevel.bronze && hand.length >= 2) {
      final first = _random.nextInt(hand.length);
      int second = _random.nextInt(hand.length);
      while (second == first) {
        second = _random.nextInt(hand.length);
      }

      mentalMap[first] = hand[first];
      mentalMap[second] = hand[second];
      knownCards[first] = true;
      knownCards[second] = true;
      memorizedCardIndices = [first, second]..sort();

      final areAdjacent = (first - second).abs() == 1;
      if (!areAdjacent) {
        mentalMap[first] = null;
        mentalMap[second] = null;
        knownCards[first] = false;
        knownCards[second] = false;
      }
    } else {
      mentalMap[0] = hand[0];
      mentalMap[1] = hand[1];
      knownCards[0] = true;
      knownCards[1] = true;
      memorizedCardIndices = [0, 1];
    }

    resetUnknownCardHints();
  }

  void updateMentalMap(int index, PlayingCard card) {
    while (mentalMap.length <= index) {
      mentalMap.add(null);
    }

    mentalMap[index] = card;

    if (index < knownCards.length) {
      knownCards[index] = true;
    }

    clearUnknownCardHint(index);
    onCardConfirmedAfterJoker(index, card);
  }

  void resetMentalMap() {
    mentalMap = List<PlayingCard?>.filled(hand.length, null, growable: true);
    knownCards = List<bool>.filled(hand.length, false, growable: true);
    resetUnknownCardHints();
    clearJokerInference();
  }

  void forgetCard(int index) {
    if (index >= 0 && index < mentalMap.length) {
      mentalMap[index] = null;
    }
    if (index >= 0 && index < knownCards.length) {
      knownCards[index] = false;
    }
    clearUnknownCardHint(index);
  }

  void clearJokerInference() {
    jokerInferenceActive = false;
    jokerInferenceMode = null;
    jokerInferenceKnownPool = [];
    jokerInferenceDoublonValue = null;
    jokerInferenceUniqueValue = null;
    jokerInferenceKnownUniqueIndex = null;
    jokerInferenceKnownDoublonIndices = [];
    jokerInferenceActionCount = -1;
  }

  void setupJokerInferenceFromKnownHand({
    required List<PlayingCard> knownHandBeforeJoker,
    required int actionCount,
  }) {
    clearJokerInference();
    if (isHuman) return;
    if (knownHandBeforeJoker.isEmpty) return;
    if (knownHandBeforeJoker.length != hand.length) return;

    jokerInferenceActionCount = actionCount;
    jokerInferenceKnownPool = List<PlayingCard>.from(knownHandBeforeJoker);

    if (knownHandBeforeJoker.length == 2) {
      final first = knownHandBeforeJoker[0];
      final second = knownHandBeforeJoker[1];

      // Cas trivial: deux cartes strictement équivalentes (même valeur + points).
      // Le Joker ne change alors rien de pertinent.
      if (first.value == second.value && first.points == second.points) {
        for (int i = 0; i < hand.length; i++) {
          if (i >= mentalMap.length) {
            mentalMap.add(null);
          }
          if (i >= knownCards.length) {
            knownCards.add(false);
          }
          mentalMap[i] = PlayingCard.create(hand[i].suit, first.value);
          knownCards[i] = true;
          clearUnknownCardHint(i);
        }
        return;
      }

      jokerInferenceActive = true;
      jokerInferenceMode = 'two_cards';
      return;
    }

    if (knownHandBeforeJoker.length == 3) {
      final counts = <String, int>{};
      for (final card in knownHandBeforeJoker) {
        counts[card.value] = (counts[card.value] ?? 0) + 1;
      }

      String? doublonValue;
      String? uniqueValue;
      for (final entry in counts.entries) {
        if (entry.value == 2) doublonValue = entry.key;
        if (entry.value == 1) uniqueValue = entry.key;
      }

      if (doublonValue != null && uniqueValue != null) {
        jokerInferenceActive = true;
        jokerInferenceMode = 'three_double';
        jokerInferenceDoublonValue = doublonValue;
        jokerInferenceUniqueValue = uniqueValue;
        return;
      }
    }
  }

  void onOwnReplacementAfterJoker({
    required int replacedIndex,
    required PlayingCard discardedCard,
  }) {
    if (!jokerInferenceActive) return;

    final mode = jokerInferenceMode;
    if (mode == 'two_cards') {
      if (hand.length != 2 || jokerInferenceKnownPool.length != 2) {
        clearJokerInference();
        return;
      }

      int removedIndex =
          jokerInferenceKnownPool.indexWhere((c) => c.id == discardedCard.id);
      if (removedIndex == -1) {
        removedIndex = jokerInferenceKnownPool.indexWhere(
          (c) =>
              c.value == discardedCard.value &&
              c.points == discardedCard.points,
        );
      }
      if (removedIndex != -1) {
        jokerInferenceKnownPool.removeAt(removedIndex);
      }

      if (jokerInferenceKnownPool.length == 1) {
        final otherIdx = replacedIndex == 0 ? 1 : 0;
        _setKnownFromInference(otherIdx, jokerInferenceKnownPool.first.value);
      }
      clearJokerInference();
      return;
    }

    if (mode == 'three_double') {
      final doublonValue = jokerInferenceDoublonValue;
      final uniqueValue = jokerInferenceUniqueValue;
      if (doublonValue == null || uniqueValue == null || hand.length != 3) {
        clearJokerInference();
        return;
      }

      if (discardedCard.value == uniqueValue) {
        for (int i = 0; i < hand.length; i++) {
          if (i == replacedIndex) continue;
          _setKnownFromInference(i, doublonValue);
        }
      } else if (discardedCard.value == doublonValue) {
        if (jokerInferenceKnownUniqueIndex != null &&
            jokerInferenceKnownUniqueIndex != replacedIndex) {
          for (int i = 0; i < hand.length; i++) {
            if (i == replacedIndex || i == jokerInferenceKnownUniqueIndex) {
              continue;
            }
            _setKnownFromInference(i, doublonValue);
          }
        }
      }

      // Le multiset a changé (carte retirée + carte piochée), donc on stoppe
      // cette reconstruction Joker et on repart sur l'état binaire courant.
      clearJokerInference();
      return;
    }

    clearJokerInference();
  }

  void onCardConfirmedAfterJoker(int index, PlayingCard knownCard) {
    if (!jokerInferenceActive) return;

    final mode = jokerInferenceMode;
    if (mode == 'two_cards') {
      if (hand.length != 2 || jokerInferenceKnownPool.length != 2) {
        clearJokerInference();
        return;
      }

      final otherIdx = index == 0 ? 1 : 0;
      if (!knownCards[otherIdx]) {
        PlayingCard? otherCard;
        if (jokerInferenceKnownPool[0].id == knownCard.id) {
          otherCard = jokerInferenceKnownPool[1];
        } else if (jokerInferenceKnownPool[1].id == knownCard.id) {
          otherCard = jokerInferenceKnownPool[0];
        } else if (jokerInferenceKnownPool[0].value == knownCard.value &&
            jokerInferenceKnownPool[0].points == knownCard.points) {
          otherCard = jokerInferenceKnownPool[1];
        } else if (jokerInferenceKnownPool[1].value == knownCard.value &&
            jokerInferenceKnownPool[1].points == knownCard.points) {
          otherCard = jokerInferenceKnownPool[0];
        }

        if (otherCard != null) {
          _setKnownFromInference(otherIdx, otherCard.value);
        }
      }

      if (knownCardCount >= hand.length) {
        clearJokerInference();
      }
      return;
    }

    if (mode == 'three_double') {
      final doublonValue = jokerInferenceDoublonValue;
      final uniqueValue = jokerInferenceUniqueValue;
      if (doublonValue == null || uniqueValue == null || hand.length != 3) {
        clearJokerInference();
        return;
      }

      if (knownCard.value == uniqueValue) {
        jokerInferenceKnownUniqueIndex = index;
        for (int i = 0; i < hand.length; i++) {
          if (i == index) continue;
          _setKnownFromInference(i, doublonValue);
          if (!jokerInferenceKnownDoublonIndices.contains(i)) {
            jokerInferenceKnownDoublonIndices.add(i);
          }
        }
      } else if (knownCard.value == doublonValue) {
        if (!jokerInferenceKnownDoublonIndices.contains(index)) {
          jokerInferenceKnownDoublonIndices.add(index);
        }

        if (jokerInferenceKnownDoublonIndices.length >= 2) {
          int? uniqueIdx;
          for (final i in const [0, 1, 2]) {
            if (!jokerInferenceKnownDoublonIndices.contains(i)) {
              uniqueIdx = i;
              break;
            }
          }
          if (uniqueIdx != null) {
            jokerInferenceKnownUniqueIndex = uniqueIdx;
            _setKnownFromInference(uniqueIdx, uniqueValue);
          }
        } else if (jokerInferenceKnownUniqueIndex != null) {
          for (int i = 0; i < hand.length; i++) {
            if (i == jokerInferenceKnownUniqueIndex) continue;
            if (i == index) continue;
            _setKnownFromInference(i, doublonValue);
          }
        }
      }

      if (knownCardCount >= hand.length) {
        clearJokerInference();
      }
      return;
    }

    clearJokerInference();
  }

  void _setKnownFromInference(int index, String value) {
    if (index < 0 || index >= hand.length) return;
    while (mentalMap.length <= index) {
      mentalMap.add(null);
    }
    while (knownCards.length <= index) {
      knownCards.add(false);
    }
    mentalMap[index] = PlayingCard.create(hand[index].suit, value);
    knownCards[index] = true;
    clearUnknownCardHint(index);
  }

  void _syncUnknownCardHints() {
    while (unknownCardQualityHints.length < hand.length) {
      unknownCardQualityHints.add(null);
    }
    while (unknownCardHintConfidence.length < hand.length) {
      unknownCardHintConfidence.add(null);
    }
    while (unknownCardHintActionCount.length < hand.length) {
      unknownCardHintActionCount.add(null);
    }

    if (unknownCardQualityHints.length > hand.length) {
      unknownCardQualityHints.removeRange(
          hand.length, unknownCardQualityHints.length);
    }
    if (unknownCardHintConfidence.length > hand.length) {
      unknownCardHintConfidence.removeRange(
          hand.length, unknownCardHintConfidence.length);
    }
    if (unknownCardHintActionCount.length > hand.length) {
      unknownCardHintActionCount.removeRange(
          hand.length, unknownCardHintActionCount.length);
    }
  }

  void resetUnknownCardHints() {
    unknownCardQualityHints =
        List<double?>.filled(hand.length, null, growable: true);
    unknownCardHintConfidence =
        List<double?>.filled(hand.length, null, growable: true);
    unknownCardHintActionCount =
        List<int?>.filled(hand.length, null, growable: true);
  }

  void setUnknownCardHint(
    int index, {
    required double quality,
    required double confidence,
    int? actionCount,
  }) {
    _syncUnknownCardHints();
    if (index < 0 || index >= hand.length) return;

    final clampedQuality =
        quality < -1.0 ? -1.0 : (quality > 1.0 ? 1.0 : quality);
    final clampedConfidence =
        confidence < 0.0 ? 0.0 : (confidence > 1.0 ? 1.0 : confidence);

    unknownCardQualityHints[index] = clampedQuality;
    unknownCardHintConfidence[index] = clampedConfidence;
    unknownCardHintActionCount[index] = actionCount;
  }

  void clearUnknownCardHint(int index) {
    _syncUnknownCardHints();
    if (index < 0 || index >= hand.length) return;
    unknownCardQualityHints[index] = null;
    unknownCardHintConfidence[index] = null;
    unknownCardHintActionCount[index] = null;
  }

  double? getUnknownCardHintQuality(int index) {
    _syncUnknownCardHints();
    if (index < 0 || index >= hand.length) return null;
    return unknownCardQualityHints[index];
  }

  double? getUnknownCardHintConfidence(int index) {
    _syncUnknownCardHints();
    if (index < 0 || index >= hand.length) return null;
    return unknownCardHintConfidence[index];
  }

  int? getUnknownCardHintAction(int index) {
    _syncUnknownCardHints();
    if (index < 0 || index >= hand.length) return null;
    return unknownCardHintActionCount[index];
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
          case BotBehavior.moi:
            return "🦈";
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

  int get avatarColorValue {
    if (!isHuman) return 0xFF2D5F3E;

    const palette = <int>[
      0xFF42A5F5,
      0xFF26A69A,
      0xFF66BB6A,
      0xFFFFCA28,
      0xFFFF7043,
      0xFFAB47BC,
      0xFF7E57C2,
      0xFFEC407A,
      0xFF29B6F6,
      0xFFFFA726,
    ];

    final hash = id.hashCode.abs();
    return palette[hash % palette.length];
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
      memorizedCardIndices: ((json['memorizedCardIndices'] as List?) ?? [])
          .map((e) => (e as num).toInt())
          .toList(),
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
      'memorizedCardIndices': memorizedCardIndices,
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
    bool? jokerInferenceActive,
    String? jokerInferenceMode,
    List<PlayingCard>? jokerInferenceKnownPool,
    String? jokerInferenceDoublonValue,
    String? jokerInferenceUniqueValue,
    int? jokerInferenceKnownUniqueIndex,
    List<int>? jokerInferenceKnownDoublonIndices,
    int? jokerInferenceActionCount,
    List<int>? memorizedCardIndices,
  }) {
    return Player(
      id: id ?? this.id,
      name: name ?? this.name,
      isHuman: isHuman ?? this.isHuman,
      botBehavior: botBehavior ?? this.botBehavior,
      botSkillLevel: botSkillLevel ?? this.botSkillLevel,
      aiParameters: aiParameters ??
          (this.aiParameters != null
              ? Map<String, double>.from(this.aiParameters!)
              : null),
      position: position ?? this.position,
      isSpectator: isSpectator ?? this.isSpectator,
      hand: List.from(hand),
      knownCards: List.from(knownCards),
      mentalMap: List.from(mentalMap),
      consecutiveBadDraws: consecutiveBadDraws,
      dutchHistory: List.from(dutchHistory),
      spyMemory: Map.from(spyMemory),
      unknownCardQualityHints: List.from(unknownCardQualityHints),
      unknownCardHintConfidence: List.from(unknownCardHintConfidence),
      unknownCardHintActionCount: List.from(unknownCardHintActionCount),
      jokerInferenceActive: jokerInferenceActive ?? this.jokerInferenceActive,
      jokerInferenceMode: jokerInferenceMode ?? this.jokerInferenceMode,
      jokerInferenceKnownPool: jokerInferenceKnownPool ??
          List<PlayingCard>.from(this.jokerInferenceKnownPool),
      jokerInferenceDoublonValue:
          jokerInferenceDoublonValue ?? this.jokerInferenceDoublonValue,
      jokerInferenceUniqueValue:
          jokerInferenceUniqueValue ?? this.jokerInferenceUniqueValue,
      jokerInferenceKnownUniqueIndex:
          jokerInferenceKnownUniqueIndex ?? this.jokerInferenceKnownUniqueIndex,
      jokerInferenceKnownDoublonIndices: jokerInferenceKnownDoublonIndices ??
          List<int>.from(this.jokerInferenceKnownDoublonIndices),
      jokerInferenceActionCount:
          jokerInferenceActionCount ?? this.jokerInferenceActionCount,
      bronzeBlackoutActive: bronzeBlackoutActive,
      bronzeBlackoutUntilActionCount: bronzeBlackoutUntilActionCount,
      lastBronzeBlackoutActionCount: lastBronzeBlackoutActionCount,
      lastBronzeValetTargetTurn: lastBronzeValetTargetTurn,
      lastTargetedByPowerTurn: lastTargetedByPowerTurn,
      memorizedCardIndices:
          memorizedCardIndices ?? List<int>.from(this.memorizedCardIndices),
    );
  }
}
