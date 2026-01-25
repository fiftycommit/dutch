import 'dart:math';
import 'card.dart';
import 'player.dart';
import 'game_settings.dart';

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
  
  /// Scores cumulés du tournoi par joueur (id -> score total)
  Map<String, int> tournamentCumulativeScores;

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
    Map<String, int>? tournamentCumulativeScores,
  })  : eliminatedPlayerIds = eliminatedPlayerIds ?? [],
        actionHistory = actionHistory ?? [],
        tournamentCumulativeScores = tournamentCumulativeScores ?? {};

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

  void smartShuffle() {
    Random rnd = Random();
    deck.shuffle();
      if (difficulty == Difficulty.easy) {
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

      _partialShuffle(deck, 0.0025);
      addToHistory("⚖️ Mélange tactique (Mode Équilibré)");
      
    } else {
      // MODE HARD (CHALLENGER): Pioche TRÈS défavorable
      // Les bonnes cartes sont enterrées au fond du paquet
      List<PlayingCard> excellent = [];  // 0-2 points (As, 2)
      List<PlayingCard> good = [];       // 3-4 points
      List<PlayingCard> medium = [];     // 5-7 points
      List<PlayingCard> bad = [];        // 8-10 points
      List<PlayingCard> terrible = [];   // Figures (V, D, R = 10+ points)

      for (var card in deck) {
        int val = card.points;
        if (val <= 2) {
          excellent.add(card);
        } else if (val <= 4) {
          good.add(card);
        } else if (val <= 7) {
          medium.add(card);
        } else if (val <= 10) {
          bad.add(card);
        } else {
          terrible.add(card);
        }
      }

      excellent.shuffle();
      good.shuffle();
      medium.shuffle();
      bad.shuffle();
      terrible.shuffle();

      deck.clear();

      // === FOND DU PAQUET (pioché en dernier) ===
      // Toutes les excellentes cartes sont cachées au fond
      while (excellent.isNotEmpty) {
        deck.add(excellent.removeLast());
      }
      
      // Puis les bonnes cartes
      while (good.isNotEmpty) {
        deck.add(good.removeLast());
      }
      
      // 20% des cartes moyennes au fond aussi
      int mediumForBottom = (medium.length * 0.2).round();
      for (int i = 0; i < mediumForBottom && medium.isNotEmpty; i++) {
        deck.add(medium.removeLast());
      }
      
      // === MILIEU DU PAQUET ===
      // Mix de mauvaises et moyennes (70% mauvaises)
      int middleCount = 12;
      for (int i = 0; i < middleCount && (bad.isNotEmpty || medium.isNotEmpty); i++) {
        double roll = rnd.nextDouble();
        if (roll < 0.70 && bad.isNotEmpty) {
          deck.add(bad.removeLast());
        } else if (medium.isNotEmpty) {
          deck.add(medium.removeLast());
        } else if (bad.isNotEmpty) {
          deck.add(bad.removeLast());
        }
      }

      // === HAUT DU PAQUET (pioché en premier) ===
      // Les figures terribles EN PREMIER, puis le reste des mauvaises
      while (terrible.isNotEmpty) {
        deck.add(terrible.removeLast());
      }
      
      // 90% de chances d'avoir une mauvaise carte en haut
      while (bad.isNotEmpty || medium.isNotEmpty) {
        double roll = rnd.nextDouble();
        if (roll < 0.90 && bad.isNotEmpty) {
          deck.add(bad.removeLast());
        } else if (medium.isNotEmpty) {
          deck.add(medium.removeLast());
        } else if (bad.isNotEmpty) {
          deck.add(bad.removeLast());
        }
      }

      // Aucun mélange final - structure 100% brutale
      // _partialShuffle(deck, 0.0);
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
    List<PlayingCard> normalCards = deck.where((c) => c.value != 'JOKER').toList();
    List<PlayingCard> jokers = deck.where((c) => c.value == 'JOKER').toList();
    
    Map<String, List<PlayingCard>> cardsByValue = {};
    for (var card in normalCards) {
      cardsByValue.putIfAbsent(card.value, () => []);
      cardsByValue[card.value]!.add(card);
    }
    for (var cards in cardsByValue.values) {
      cards.shuffle(rnd);
    }
    
    List<String> badValues = ['R', 'D', 'V', '10', '9', '8'];
    List<String> mediumValues = ['7', '6', '5'];
    List<String> goodValues = ['4', '3', '2', 'A'];
    
    _distributeWithSeparation(
      cardsByValue, badValues, mediumValues, goodValues, jokers, rnd,
      badCardsPerPlayer: 2,
      separationStrength: 0.7,
    );
  }

  void _dealCardsHard(Random rnd) {
    List<PlayingCard> normalCards = deck.where((c) => c.value != 'JOKER').toList();
    List<PlayingCard> jokers = deck.where((c) => c.value == 'JOKER').toList();
    
    Map<String, List<PlayingCard>> cardsByValue = {};
    for (var card in normalCards) {
      cardsByValue.putIfAbsent(card.value, () => []);
      cardsByValue[card.value]!.add(card);
    }
    for (var cards in cardsByValue.values) {
      cards.shuffle(rnd);
    }
    
    List<String> badValues = ['R', 'D', 'V', '10', '9', '8'];
    List<String> mediumValues = ['7', '6', '5'];
    List<String> goodValues = ['4', '3', '2', 'A'];
    

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
    
    List<String> allValues = [...badValues, ...mediumValues, ...goodValues];
    
    for (int playerIdx in playerOrder) {
      Set<String> playerValues = hands[playerIdx].map((c) => c.value).toSet();
      
      while (hands[playerIdx].length < 4) {
        bool cardAdded = false;
        
        allValues.shuffle(rnd);
        for (var value in allValues) {
          if (playerValues.contains(value)) continue;
          
          if (cardsByValue[value] != null && cardsByValue[value]!.isNotEmpty) {
            hands[playerIdx].add(cardsByValue[value]!.removeLast());
            playerValues.add(value);
            cardAdded = true;
            break;
          }
        }
        
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
    
    for (int i = 0; i < numPlayers; i++) {
      players[i].hand = hands[i];
      players[i].knownCards = List.filled(hands[i].length, false);
    }
    
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
    addToHistory("🃏 Distribution terminée ($jokers Jokers dans le deck)");
  }


  void shuffleDeckRandomly() {
    deck.shuffle(Random());
  }

  List<Player> getFinalRanking() {
    List<Player> ranking = List.from(players);
    
    // Trier par score, mais en cas d'égalité, celui qui a Dutch est devant
    ranking.sort((a, b) {
      int scoreA = getFinalScore(a);
      int scoreB = getFinalScore(b);
      
      if (scoreA != scoreB) {
        return scoreA.compareTo(scoreB);
      }
      
      // En cas d'égalité de score, celui qui a appelé Dutch gagne (il est premier)
      if (a.id == dutchCallerId) return -1;
      if (b.id == dutchCallerId) return 1;
      
      return 0; // Sinon ordre arbitraire entre ex-aequo
    });
    
    // Si le Dutch caller n'a pas gagné (quelqu'un a un score STRICTEMENT inférieur), il est mis en dernier
    if (dutchCallerId != null && !didDutchCallerWin()) {
      Player failedCaller = ranking.firstWhere((p) => p.id == dutchCallerId);
      ranking.remove(failedCaller);
      ranking.add(failedCaller);
    }
    return ranking;
  }
  
  /// Retourne les rangs réels avec gestion des ex-aequo
  /// Retourne une Map<playerId, rang> où le rang tient compte des égalités
  /// Cas spécial : le Dutch caller gagnant est SEUL #1, les autres avec même score sont #2
  Map<String, int> getFinalRanksWithTies() {
    List<Player> ranking = getFinalRanking();
    Map<String, int> ranks = {};
    
    // Vérifier si le Dutch caller a gagné
    bool dutchCallerWon = dutchCallerId != null && didDutchCallerWin();
    int? dutchCallerScore;
    if (dutchCallerWon) {
      Player caller = players.firstWhere((p) => p.id == dutchCallerId);
      dutchCallerScore = getFinalScore(caller);
    }
    
    int currentRank = 1;
    int? previousScore;
    
    for (int i = 0; i < ranking.length; i++) {
      Player player = ranking[i];
      int score = getFinalScore(player);
      
      // Cas spécial : Dutch caller raté est toujours dernier
      if (dutchCallerId != null && !didDutchCallerWin() && player.id == dutchCallerId) {
        ranks[player.id] = ranking.length; // Dernier
        continue;
      }
      
      // Le Dutch caller gagnant est TOUJOURS seul #1
      if (dutchCallerWon && player.id == dutchCallerId) {
        ranks[player.id] = 1;
        previousScore = score;
        continue;
      }
      
      // Si Dutch caller a gagné et ce joueur a le même score → #2 (pas ex-aequo avec le Dutch caller)
      if (dutchCallerWon && score == dutchCallerScore) {
        currentRank = 2;
        ranks[player.id] = currentRank;
        previousScore = score;
        continue;
      }
      
      if (previousScore == null || score != previousScore) {
        // Nouveau score = nouveau rang (on saute les rangs des ex-aequo précédents)
        currentRank = i + 1;
      }
      // Sinon même score = même rang (ex-aequo), on garde currentRank
      
      ranks[player.id] = currentRank;
      previousScore = score;
    }
    
    return ranks;
  }

  int getFinalScore(Player player) {
    return player.calculateScore();
  }

  bool didDutchCallerWin() {
    if (dutchCallerId == null) return false;
    Player caller = players.firstWhere((p) => p.id == dutchCallerId);
    int callerScore = getFinalScore(caller);
    for (var p in players) {
      // Le Dutch caller gagne s'il a le score MINIMUM ou ÉGAL au minimum
      // Donc il perd seulement si quelqu'un a un score STRICTEMENT inférieur
      if (p.id != caller.id && getFinalScore(p) < callerScore) {
        return false;
      }
    }
    return true;
  }

  /// Récupère le score cumulé d'un joueur dans le tournoi
  int getCumulativeScore(Player player) {
    return tournamentCumulativeScores[player.id] ?? 0;
  }

  /// Met à jour les scores cumulés du tournoi après une manche
  void updateCumulativeScores() {
    for (var player in players) {
      int roundScore = getFinalScore(player);
      tournamentCumulativeScores[player.id] = 
          (tournamentCumulativeScores[player.id] ?? 0) + roundScore;
    }
  }

  /// Vérifie si un joueur est proche de l'élimination (>= 80 points en mode tournoi)
  bool isPlayerNearElimination(Player player, {int threshold = 80}) {
    if (gameMode != GameMode.tournament) return false;
    return getCumulativeScore(player) >= threshold;
  }
  
  /// Récupère la liste des joueurs triés par score cumulé (meilleur en premier)
  List<Player> getPlayersByTournamentRank() {
    List<Player> sorted = List.from(players);
    sorted.sort((a, b) => getCumulativeScore(a).compareTo(getCumulativeScore(b)));
    return sorted;
  }
}