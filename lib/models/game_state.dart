import 'dart:math';
import 'card.dart';
import 'player.dart';
import 'game_settings.dart';
import 'package:flutter/foundation.dart';

enum GameMode { quick, tournament }

enum GamePhase { setup, playing, reaction, dutchCalled, ended }

class GameState {
  List<Player> players;
  List<PlayingCard> deck;
  List<PlayingCard> discardPile;

  int currentPlayerIndex;
  GameMode gameMode;
  GamePhase phase;
  final Difficulty difficulty;

  int tournamentRound;
  List<String> eliminatedPlayerIds;
  PlayingCard? drawnCard;
  bool isWaitingForSpecialPower;
  PlayingCard? specialCardToActivate;
  String? dutchCallerId;
  DateTime? reactionStartTime;
  List<String> actionHistory;

  int reactionTimeRemaining = 0;
  PlayingCard? lastSpiedCard;
  Map<String, dynamic>? pendingSwap;

  GameState({
    required this.players,
    required this.deck,
    required this.discardPile,
    this.currentPlayerIndex = 0,
    this.gameMode = GameMode.quick,
    this.phase = GamePhase.setup,
    this.tournamentRound = 1,
    this.difficulty = Difficulty.medium,
    List<String>? eliminatedPlayerIds,
    this.drawnCard,
    this.isWaitingForSpecialPower = false,
    this.specialCardToActivate,
    this.dutchCallerId,
    this.reactionStartTime,
    List<String>? actionHistory,
    this.reactionTimeRemaining = 0,
    this.lastSpiedCard,
    this.pendingSwap,
  })  : eliminatedPlayerIds = eliminatedPlayerIds ?? [],
        actionHistory = actionHistory ?? [];

  Player get currentPlayer => players[currentPlayerIndex];
  PlayingCard? get topDiscardCard =>
      discardPile.isNotEmpty ? discardPile.last : null;
  int get remainingDeckCards => deck.length;

  void nextTurn() {
    do {
      currentPlayerIndex = (currentPlayerIndex + 1) % players.length;
    } while (eliminatedPlayerIds.contains(currentPlayer.id));
  }

  void addToHistory(String action) {
    String time =
        "${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}";
    actionHistory.insert(0, "[$time] $action");
    if (actionHistory.length > 50) actionHistory.removeLast();
  }

  static List<PlayingCard> createFullDeck() {
    List<PlayingCard> deck = [];
    List<String> suits = ['hearts', 'diamonds', 'clubs', 'spades'];
    List<String> values = [
      'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'V', 'D', 'R'
    ];
    for (var suit in suits) {
      for (var value in values) {
        deck.add(PlayingCard.create(suit, value));
      }
    }
    deck.add(PlayingCard.create('joker', 'JOKER'));
    deck.add(PlayingCard.create('joker', 'JOKER'));
    return deck;
  }

  // ============================================================
  // 🎴 SMART SHUFFLE
  // ============================================================
  void smartShuffle() {
    Random rnd = Random();
    
    if (difficulty == Difficulty.easy) {
      deck.shuffle();
      addToHistory("🎲 Mélange aléatoire (Mode Détendu)");
      
    } else if (difficulty == Difficulty.medium) {
      // MODE MEDIUM: 50% mauvaises au début
      List<PlayingCard> good = [];
      List<PlayingCard> medium = [];
      List<PlayingCard> bad = [];

      for (var card in deck) {
        int val = card.points;
        if (val <= 5) {
          good.add(card);
        } else if (val <= 8) {
          medium.add(card);
        } else {
          bad.add(card);
        }
      }

      good.shuffle();
      medium.shuffle();
      bad.shuffle();

      deck.clear();
      
      // Fond: bonnes cartes
      int phase1Count = 20;
      for (int i = 0; i < phase1Count; i++) {
        double roll = rnd.nextDouble();
        if (roll < 0.70 && good.isNotEmpty) {
          deck.add(good.removeLast());
        } else if (roll < 0.90 && medium.isNotEmpty) {
          deck.add(medium.removeLast());
        } else if (bad.isNotEmpty) {
          deck.add(bad.removeLast());
        } else if (good.isNotEmpty) {
          deck.add(good.removeLast());
        } else if (medium.isNotEmpty) {
          deck.add(medium.removeLast());
        }
      }
      
      // Milieu: mix
      int phase2Count = 17;
      for (int i = 0; i < phase2Count; i++) {
        double roll = rnd.nextDouble();
        if (roll < 0.40 && bad.isNotEmpty) {
          deck.add(bad.removeLast());
        } else if (roll < 0.70 && medium.isNotEmpty) {
          deck.add(medium.removeLast());
        } else if (good.isNotEmpty) {
          deck.add(good.removeLast());
        } else if (bad.isNotEmpty) {
          deck.add(bad.removeLast());
        } else if (medium.isNotEmpty) {
          deck.add(medium.removeLast());
        }
      }
      
      // Haut (pioché en premier): 50% mauvaises
      while (good.isNotEmpty || medium.isNotEmpty || bad.isNotEmpty) {
        double roll = rnd.nextDouble();
        if (roll < 0.50 && bad.isNotEmpty) {
          deck.add(bad.removeLast());
        } else if (roll < 0.80 && medium.isNotEmpty) {
          deck.add(medium.removeLast());
        } else if (good.isNotEmpty) {
          deck.add(good.removeLast());
        } else if (bad.isNotEmpty) {
          deck.add(bad.removeLast());
        } else if (medium.isNotEmpty) {
          deck.add(medium.removeLast());
        }
      }

      _partialShuffle(deck, 0.05);
      addToHistory("⚖️ Mélange tactique (Mode Équilibré)");
      
    } else {
      // MODE HARD: 80% mauvaises
      List<PlayingCard> good = [];
      List<PlayingCard> medium = [];
      List<PlayingCard> bad = [];

      for (var card in deck) {
        int val = card.points;
        if (val <= 4) {
          good.add(card);
        } else if (val <= 7) {
          medium.add(card);
        } else {
          bad.add(card);
        }
      }

      good.shuffle();
      medium.shuffle();
      bad.shuffle();

      deck.clear();

      // Enterrer les bonnes au fond
      while (good.isNotEmpty) {
        deck.add(good.removeLast());
      }
      
      int mediumForBottom = (medium.length * 0.4).round();
      for (int i = 0; i < mediumForBottom && medium.isNotEmpty; i++) {
        deck.add(medium.removeLast());
      }
      
      debugPrint("🔥 [HARD] Fond du deck: ${deck.length} cartes (bonnes enterrées)");
      
      // 80% mauvaises en haut
      while (bad.isNotEmpty || medium.isNotEmpty) {
        double roll = rnd.nextDouble();
        
        if (roll < 0.80 && bad.isNotEmpty) {
          deck.add(bad.removeLast());
        } else if (medium.isNotEmpty) {
          deck.add(medium.removeLast());
        } else if (bad.isNotEmpty) {
          deck.add(bad.removeLast());
        }
      }
      
      debugPrint("🔥 [HARD] Deck total: ${deck.length} cartes");

      _partialShuffle(deck, 0.02);
      addToHistory("🔥 Mélange BRUTAL (Mode Challenger)");
    }
  }

  void _partialShuffle(List<PlayingCard> cards, double ratio) {
    Random rnd = Random();
    int swaps = (cards.length * ratio).round();
    for (int i = 0; i < swaps; i++) {
      int a = rnd.nextInt(cards.length);
      int b = rnd.nextInt(cards.length);
      var temp = cards[a];
      cards[a] = cards[b];
      cards[b] = temp;
    }
  }

  // ============================================================
  // 🃏 DEAL CARDS - VERSION ANTI-MATCH
  // ============================================================
  void dealCards() {
    Random rnd = Random();
    
    if (difficulty == Difficulty.easy) {
      _dealCardsEasy(rnd);
    } else if (difficulty == Difficulty.medium) {
      _dealCardsMedium(rnd);
    } else {
      _dealCardsHard(rnd);
    }
  }

  void _dealCardsEasy(Random rnd) {
    // Séparer les Jokers
    List<PlayingCard> normalCards = deck.where((c) => c.value != 'JOKER').toList();
    List<PlayingCard> jokers = deck.where((c) => c.value == 'JOKER').toList();
    
    normalCards.shuffle(rnd);
    
    for (var player in players) {
      player.hand = [];
      player.knownCards = [];
      for (int i = 0; i < 4; i++) {
        if (normalCards.isNotEmpty) {
          player.hand.add(normalCards.removeLast());
          player.knownCards.add(false);
        }
      }
    }

    deck.clear();
    deck.addAll(normalCards);
    deck.addAll(jokers);
    deck.shuffle(rnd);
    
    _logDealResults();
  }

  void _dealCardsMedium(Random rnd) {
    // Séparer les Jokers
    List<PlayingCard> normalCards = deck.where((c) => c.value != 'JOKER').toList();
    List<PlayingCard> jokers = deck.where((c) => c.value == 'JOKER').toList();
    
    // Grouper par valeur
    Map<String, List<PlayingCard>> cardsByValue = {};
    for (var card in normalCards) {
      cardsByValue.putIfAbsent(card.value, () => []);
      cardsByValue[card.value]!.add(card);
    }
    for (var cards in cardsByValue.values) {
      cards.shuffle(rnd);
    }
    
    // Valeurs par catégorie
    List<String> badValues = ['R', 'D', 'V', '10', '9', '8'];
    List<String> mediumValues = ['7', '6', '5'];
    List<String> goodValues = ['4', '3', '2', 'A'];
    
    // Distribution: 50% mauvaises, avec séparation partielle
    _distributeWithSeparation(
      cardsByValue, badValues, mediumValues, goodValues, jokers, rnd,
      badCardsPerPlayer: 2,
      separationStrength: 0.7,
    );
  }

  void _dealCardsHard(Random rnd) {
    // Séparer les Jokers
    List<PlayingCard> normalCards = deck.where((c) => c.value != 'JOKER').toList();
    List<PlayingCard> jokers = deck.where((c) => c.value == 'JOKER').toList();
    
    // Grouper par valeur
    Map<String, List<PlayingCard>> cardsByValue = {};
    for (var card in normalCards) {
      cardsByValue.putIfAbsent(card.value, () => []);
      cardsByValue[card.value]!.add(card);
    }
    for (var cards in cardsByValue.values) {
      cards.shuffle(rnd);
    }
    
    // Valeurs par catégorie (inclut 7, 10, V pour plus de variété)
    List<String> badValues = ['R', 'D', 'V', '10', '9', '8'];
    List<String> mediumValues = ['7', '6', '5'];
    List<String> goodValues = ['4', '3', '2', 'A'];
    
    // 🔥 Distribution BRUTALE: ~3 mauvaises par joueur, valeurs uniques
    _distributeWithSeparation(
      cardsByValue, badValues, mediumValues, goodValues, jokers, rnd,
      badCardsPerPlayer: 3,
      separationStrength: 1.0,
    );
  }

  void _distributeWithSeparation(
    Map<String, List<PlayingCard>> cardsByValue,
    List<String> badValues,
    List<String> mediumValues,
    List<String> goodValues,
    List<PlayingCard> jokers,
    Random rnd, {
    required int badCardsPerPlayer,
    required double separationStrength,
  }) {
    int numPlayers = players.length;
    
    // Mélanger l'ordre des joueurs
    List<int> playerOrder = List.generate(numPlayers, (i) => i);
    playerOrder.shuffle(rnd);
    
    // Mélanger les valeurs
    badValues = List.from(badValues)..shuffle(rnd);
    mediumValues = List.from(mediumValues)..shuffle(rnd);
    goodValues = List.from(goodValues)..shuffle(rnd);
    
    List<List<PlayingCard>> hands = List.generate(numPlayers, (_) => []);
    Set<String> globalUsedValues = {};
    
    // PHASE 1: Donner des mauvaises cartes UNIQUES à chaque joueur
    for (int playerIdx in playerOrder) {
      int cardsGiven = 0;
      
      for (var value in badValues) {
        if (cardsGiven >= badCardsPerPlayer) break;
        
        // Séparation: éviter les valeurs déjà données
        if (rnd.nextDouble() < separationStrength && globalUsedValues.contains(value)) {
          continue;
        }
        
        if (cardsByValue[value] != null && cardsByValue[value]!.isNotEmpty) {
          hands[playerIdx].add(cardsByValue[value]!.removeLast());
          globalUsedValues.add(value);
          cardsGiven++;
        }
      }
    }
    
    // PHASE 2: Compléter avec moyennes (uniques si possible)
    List<String> remaining = [...badValues, ...mediumValues];
    remaining.shuffle(rnd);
    
    for (int playerIdx in playerOrder) {
      Set<String> playerValues = hands[playerIdx].map((c) => c.value).toSet();
      
      for (var value in remaining) {
        if (hands[playerIdx].length >= 3) break;
        
        if (playerValues.contains(value)) continue;
        
        if (rnd.nextDouble() < separationStrength && globalUsedValues.contains(value)) {
          continue;
        }
        
        if (cardsByValue[value] != null && cardsByValue[value]!.isNotEmpty) {
          hands[playerIdx].add(cardsByValue[value]!.removeLast());
          globalUsedValues.add(value);
          playerValues.add(value);
        }
      }
    }
    
    // PHASE 3: Compléter à 4 cartes (prendre ce qui reste)
    List<String> allValues = [...badValues, ...mediumValues, ...goodValues];
    
    for (int playerIdx in playerOrder) {
      Set<String> playerValues = hands[playerIdx].map((c) => c.value).toSet();
      
      while (hands[playerIdx].length < 4) {
        bool cardAdded = false;
        
        allValues.shuffle(rnd);
        for (var value in allValues) {
          // Éviter doublon dans sa propre main
          if (playerValues.contains(value)) continue;
          
          if (cardsByValue[value] != null && cardsByValue[value]!.isNotEmpty) {
            hands[playerIdx].add(cardsByValue[value]!.removeLast());
            playerValues.add(value);
            cardAdded = true;
            break;
          }
        }
        
        // Dernier recours: prendre n'importe quoi
        if (!cardAdded) {
          for (var value in allValues) {
            if (cardsByValue[value] != null && cardsByValue[value]!.isNotEmpty) {
              hands[playerIdx].add(cardsByValue[value]!.removeLast());
              cardAdded = true;
              break;
            }
          }
        }
        
        if (!cardAdded) break;
      }
    }
    
    // Assigner les mains aux joueurs
    for (int i = 0; i < numPlayers; i++) {
      players[i].hand = hands[i];
      players[i].knownCards = List.filled(hands[i].length, false);
    }
    
    // Reconstruire le deck: bonnes au fond, mauvaises en haut
    deck.clear();
    
    for (var value in goodValues) {
      if (cardsByValue[value] != null) {
        deck.addAll(cardsByValue[value]!);
      }
    }
    for (var value in mediumValues) {
      if (cardsByValue[value] != null) {
        deck.addAll(cardsByValue[value]!);
      }
    }
    for (var value in badValues) {
      if (cardsByValue[value] != null) {
        deck.addAll(cardsByValue[value]!);
      }
    }
    
    deck.addAll(jokers);
    deck.shuffle(rnd);
    
    _logDealResults();
  }

  void _logDealResults() {
    int jokers = deck.where((c) => c.value == 'JOKER').length;
    addToHistory("🎴 Distribution terminée ($jokers Jokers dans le deck)");
    
    // Debug
    Set<String> allValues = {};
    int duplicates = 0;
    
    for (var player in players) {
      int handScore = player.hand.fold(0, (sum, card) => sum + card.points);
      List<String> values = player.hand.map((c) => c.value).toList();
      
      for (var v in values) {
        if (allValues.contains(v)) duplicates++;
        allValues.add(v);
      }
      
      debugPrint("🃏 ${player.name}: $values = $handScore pts");
    }
    
    debugPrint("⚔️ Valeurs en double (matchs possibles): $duplicates");
  }

  void shuffleDeckRandomly() {
    deck.shuffle(Random());
  }

  List<Player> getFinalRanking() {
    List<Player> ranking = List.from(players);
    ranking.sort((a, b) => getFinalScore(a).compareTo(getFinalScore(b)));
    if (dutchCallerId != null && !didDutchCallerWin()) {
      Player failedCaller = ranking.firstWhere((p) => p.id == dutchCallerId);
      ranking.remove(failedCaller);
      ranking.add(failedCaller);
    }
    return ranking;
  }

  int getFinalScore(Player player) {
    return player.calculateScore();
  }

  bool didDutchCallerWin() {
    if (dutchCallerId == null) return false;
    Player caller = players.firstWhere((p) => p.id == dutchCallerId);
    int callerScore = getFinalScore(caller);
    for (var p in players) {
      if (p.id != caller.id && getFinalScore(p) <= callerScore) {
        return false;
      }
    }
    return true;
  }
}