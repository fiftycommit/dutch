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

  // 🆕 NOUVELLES PROPRIÉTÉS pour les pouvoirs spéciaux
  int reactionTimeRemaining = 0;        // Temps restant pour la phase réaction
  PlayingCard? lastSpiedCard;           // Dernière carte espionnée (pouvoir 9/10)
  Map<String, dynamic>? pendingSwap;    // Échange en attente (pouvoir J/Q)

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

  void smartShuffle() {
    Random rnd = Random();
    
    if (difficulty == Difficulty.easy) {
      // Mode facile : mélange aléatoire pur
      deck.shuffle();
      addToHistory("🎲 Mélange aléatoire pur (Mode Détendu)");
      
    } else if (difficulty == Difficulty.medium) {
      // Mode medium : début équilibré, légère tendance aux mauvaises cartes en milieu/fin
      List<PlayingCard> excellent = []; // 0-3 pts (A, 2, 3)
      List<PlayingCard> good = [];      // 4-6 pts (4, 5, 6)
      List<PlayingCard> medium = [];    // 7-9 pts (7, 8, 9)
      List<PlayingCard> bad = [];       // 10+ pts (10, V, D, R, Joker)

      for (var card in deck) {
        int val = card.points;
        if (val <= 3) {
          excellent.add(card);
        } else if (val <= 6) {
          good.add(card);
        } else if (val <= 9) {
          medium.add(card);
        } else {
          bad.add(card);
        }
      }

      excellent.shuffle();
      good.shuffle();
      medium.shuffle();
      bad.shuffle();

      deck.clear();
      
      // ✅ FIX: Structure le deck pour que les MAUVAISES cartes soient piochées plus tôt
      // Rappel: removeLast() pioche depuis la FIN, donc on met les mauvaises à la fin
      
      int totalCards = excellent.length + good.length + medium.length + bad.length;
      int phase1 = (totalCards * 0.25).round(); // Début de partie
      int phase2 = (totalCards * 0.35).round(); // Milieu
      int phase3 = (totalCards * 0.25).round(); // Fin milieu
      // Phase 4 = reste (~15%)                  // Fin de partie
      
      // Phase 1 (début - en bas du deck, pioché en dernier): Mix équilibré
      for (int i = 0; i < phase1; i++) {
        double roll = rnd.nextDouble();
        if (roll < 0.30 && excellent.isNotEmpty) {
          deck.add(excellent.removeLast());
        } else if (roll < 0.55 && good.isNotEmpty) {
          deck.add(good.removeLast());
        } else if (roll < 0.80 && medium.isNotEmpty) {
          deck.add(medium.removeLast());
        } else if (bad.isNotEmpty) {
          deck.add(bad.removeLast());
        } else {
          // Fallback
          for (var cat in [medium, good, excellent, bad]) {
            if (cat.isNotEmpty) { deck.add(cat.removeLast()); break; }
          }
        }
      }
      
      // Phase 2 (milieu): Tendance medium/bad
      for (int i = 0; i < phase2; i++) {
        double roll = rnd.nextDouble();
        if (roll < 0.15 && excellent.isNotEmpty) {
          deck.add(excellent.removeLast());
        } else if (roll < 0.35 && good.isNotEmpty) {
          deck.add(good.removeLast());
        } else if (roll < 0.65 && medium.isNotEmpty) {
          deck.add(medium.removeLast());
        } else if (bad.isNotEmpty) {
          deck.add(bad.removeLast());
        } else {
          for (var cat in [medium, good, bad, excellent]) {
            if (cat.isNotEmpty) { deck.add(cat.removeLast()); break; }
          }
        }
      }
      
      // Phase 3: Plus de mauvaises cartes
      for (int i = 0; i < phase3; i++) {
        double roll = rnd.nextDouble();
        if (roll < 0.10 && excellent.isNotEmpty) {
          deck.add(excellent.removeLast());
        } else if (roll < 0.25 && good.isNotEmpty) {
          deck.add(good.removeLast());
        } else if (roll < 0.50 && medium.isNotEmpty) {
          deck.add(medium.removeLast());
        } else if (bad.isNotEmpty) {
          deck.add(bad.removeLast());
        } else {
          for (var cat in [bad, medium, good, excellent]) {
            if (cat.isNotEmpty) { deck.add(cat.removeLast()); break; }
          }
        }
      }
      
      // Phase 4 (haut du deck - pioché en premier): Ce qui reste, tendance mauvaise
      while (excellent.isNotEmpty || good.isNotEmpty || medium.isNotEmpty || bad.isNotEmpty) {
        double roll = rnd.nextDouble();
        if (roll < 0.45 && bad.isNotEmpty) {
          deck.add(bad.removeLast());
        } else if (roll < 0.70 && medium.isNotEmpty) {
          deck.add(medium.removeLast());
        } else if (roll < 0.85 && good.isNotEmpty) {
          deck.add(good.removeLast());
        } else if (excellent.isNotEmpty) {
          deck.add(excellent.removeLast());
        } else {
          for (var cat in [bad, medium, good, excellent]) {
            if (cat.isNotEmpty) { deck.add(cat.removeLast()); break; }
          }
        }
      }

      _partialShuffle(deck, 0.12); // Moins de shuffle pour garder la structure
      addToHistory("⚖️ Mélange équilibré (Mode Tactique)");
      
    } else {
      // Mode HARD : Les premières pioches sont souvent mauvaises
      List<PlayingCard> heaven = []; // 0-3 pts (très bonnes)
      List<PlayingCard> earth = [];  // 4-7 pts (moyennes)
      List<PlayingCard> hell = [];   // 8+ pts (mauvaises)

      for (var card in deck) {
        int val = card.points;
        if (val <= 3) {
          heaven.add(card);
        } else if (val <= 7) {
          earth.add(card);
        } else {
          hell.add(card);
        }
      }

      heaven.shuffle();
      earth.shuffle();
      hell.shuffle();

      deck.clear();

      int totalCards = heaven.length + earth.length + hell.length;
      int phase1 = (totalCards * 0.30).round(); // Fond du deck (pioché en dernier)
      int phase2 = (totalCards * 0.35).round(); // Milieu
      // Phase 3 = reste (~35%)                  // Haut du deck (pioché en premier)

      // ✅ FIX: INVERSER LA LOGIQUE
      // Phase 1 (FOND du deck - pioché EN DERNIER): Quelques bonnes cartes
      for (int i = 0; i < phase1; i++) {
        double roll = rnd.nextDouble();
        if (roll < 0.35 && heaven.isNotEmpty) {
          deck.add(heaven.removeLast());
        } else if (roll < 0.70 && earth.isNotEmpty) {
          deck.add(earth.removeLast());
        } else if (hell.isNotEmpty) {
          deck.add(hell.removeLast());
        } else {
          for (var cat in [earth, heaven, hell]) {
            if (cat.isNotEmpty) { deck.add(cat.removeLast()); break; }
          }
        }
      }

      // Phase 2 (MILIEU): Mix avec tendance mauvaise
      for (int i = 0; i < phase2; i++) {
        double roll = rnd.nextDouble();
        if (roll < 0.15 && heaven.isNotEmpty) {
          deck.add(heaven.removeLast());
        } else if (roll < 0.45 && earth.isNotEmpty) {
          deck.add(earth.removeLast());
        } else if (hell.isNotEmpty) {
          deck.add(hell.removeLast());
        } else {
          for (var cat in [earth, hell, heaven]) {
            if (cat.isNotEmpty) { deck.add(cat.removeLast()); break; }
          }
        }
      }

      // Phase 3 (HAUT du deck - pioché EN PREMIER): Majoritairement mauvaises !
      while (hell.isNotEmpty || earth.isNotEmpty || heaven.isNotEmpty) {
        double roll = rnd.nextDouble();
        if (roll < 0.55 && hell.isNotEmpty) {
          deck.add(hell.removeLast());
        } else if (roll < 0.85 && earth.isNotEmpty) {
          deck.add(earth.removeLast());
        } else if (heaven.isNotEmpty) {
          deck.add(heaven.removeLast());
        } else {
          for (var cat in [hell, earth, heaven]) {
            if (cat.isNotEmpty) { deck.add(cat.removeLast()); break; }
          }
        }
      }

      _partialShuffle(deck, 0.08); // Très peu de shuffle pour garder la difficulté
      addToHistory("🔥 Mélange exigeant (Mode Challenger)");
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
    List<PlayingCard> normalCards = [];
    List<PlayingCard> specialCards = [];

    for (var card in deck) {
      if (card.value == 'JOKER' || ['7', '10', 'V'].contains(card.value)) {
        specialCards.add(card);
      } else {
        normalCards.add(card);
      }
    }

    normalCards.shuffle(rnd);

    for (var player in players) {
      player.hand = List<PlayingCard>.from([]);
      player.knownCards = List<bool>.from([]);
      for (int i = 0; i < 4; i++) {
        if (normalCards.isNotEmpty) {
          player.hand.add(normalCards.removeLast());
          player.knownCards.add(false);
        }
      }
    }

    deck.clear();
    deck.addAll(normalCards);
    deck.addAll(specialCards);
    deck.shuffle(rnd);

    int jokers = deck.where((c) => c.value == 'JOKER').length;
    int specials = deck.where((c) => ['7', '10', 'V'].contains(c.value)).length;
    addToHistory("🎴 Deck recomposé : $jokers Jokers, $specials cartes spéciales");
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