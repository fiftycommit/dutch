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
      'A',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '10',
      'V',
      'D',
      'R'
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

  // 🔥 SYSTÈME DE MÉLANGE AMÉLIORÉ V2
  void smartShuffle() {
    Random rnd = Random();
    if (difficulty == Difficulty.easy) {
      // ✅ MODE DÉTENDU : Mélange 100% aléatoire pur
      deck.shuffle();
      addToHistory("🎲 Mélange aléatoire pur (Mode Détendu)");
    } else if (difficulty == Difficulty.medium) {
      // ✅ MODE TACTIQUE : Distribution équilibrée avec paquets aléatoires

      // 1️⃣ Catégoriser les cartes
      List<PlayingCard> excellent =
          []; // 0-3 points (A, 2, 3, Rois rouges, Jokers)
      List<PlayingCard> good = []; // 4-6 points
      List<PlayingCard> medium = []; // 7-9 points
      List<PlayingCard> bad = []; // 10-13 points

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

      // 2️⃣ Mélanger chaque catégorie individuellement
      excellent.shuffle();
      good.shuffle();
      medium.shuffle();
      bad.shuffle();

      // 3️⃣ Reconstruction en "paquets" (plus naturel qu'une lasagne régulière)
      deck.clear();

      // Distribution en paquets de 2-4 cartes
      while (excellent.isNotEmpty ||
          good.isNotEmpty ||
          medium.isNotEmpty ||
          bad.isNotEmpty) {
        List<List<PlayingCard>> cats = [excellent, good, medium, bad];
        cats.shuffle(); // Ordre aléatoire des catégories

        // Prendre un mini-paquet (2-4 cartes) d'une catégorie aléatoire

        int packetSize = 2 + rnd.nextInt(3); // 2 à 4 cartes
        for (int i = 0; i < packetSize; i++) {
          for (var cat in cats) {
            if (cat.isNotEmpty) {
              deck.add(cat.removeLast());
              break;
            }
          }
        }
      }

      // 4️⃣ Mélange partiel (20%) pour éviter la prévisibilité
      _partialShuffle(deck, 0.20);
      addToHistory("⚖️ Mélange équilibré (Mode Tactique)");
    } else {
      // ✅ MODE CHALLENGER : Gradient progressif (bon → moyen → difficile)

      List<PlayingCard> heaven = []; // 0-4 points
      List<PlayingCard> earth = []; // 5-8 points
      List<PlayingCard> hell = []; // 9-13 points

      for (var card in deck) {
        int val = card.points;

        if (val <= 4) {
          heaven.add(card);
        } else if (val <= 8) {
          earth.add(card);
        } else {
          hell.add(card);
        }
      }

      heaven.shuffle();
      earth.shuffle();
      hell.shuffle();

      deck.clear();

      // ✅ AMÉLIORATION : Gradient 30% bon / 40% moyen / 30% difficile
      int totalCards = heaven.length + earth.length + hell.length;
      int phase1 = (totalCards * 0.30).round(); // 30% : Majoritairement bonnes
      int phase2 = (totalCards * 0.40).round(); // 40% : Mélange équilibré
      // phase3 : le reste (30%) : Majoritairement difficiles

      // Phase 1 : Bonnes cartes prédominantes (50% excellent, 30% good, 20% bad)
      for (int i = 0; i < phase1; i++) {
        double roll = rnd.nextDouble();
        if (roll < 0.50 && heaven.isNotEmpty) {
          deck.add(heaven.removeLast());
        } else if (roll < 0.80 && earth.isNotEmpty) {
          deck.add(earth.removeLast());
        } else if (hell.isNotEmpty) {
          deck.add(hell.removeLast());
        } else if (heaven.isNotEmpty) {
          deck.add(heaven.removeLast());
        } else if (earth.isNotEmpty) {
          deck.add(earth.removeLast());
        }
      }

      // Phase 2 : Équilibre (distribution égale)
      for (int i = 0; i < phase2; i++) {
        List<List<PlayingCard>> cats = [heaven, earth, hell];
        cats.shuffle(rnd);
        for (var cat in cats) {
          if (cat.isNotEmpty) {
            deck.add(cat.removeLast());
            break;
          }
        }
      }

      // Phase 3 : Mauvaises cartes prédominantes (60% hell, 30% earth, 10% heaven)
      while (hell.isNotEmpty || earth.isNotEmpty || heaven.isNotEmpty) {
        double roll = rnd.nextDouble();
        if (roll < 0.60 && hell.isNotEmpty) {
          deck.add(hell.removeLast());
        } else if (roll < 0.90 && earth.isNotEmpty) {
          deck.add(earth.removeLast());
        } else if (heaven.isNotEmpty) {
          deck.add(heaven.removeLast());
        } else if (hell.isNotEmpty) {
          deck.add(hell.removeLast());
        } else if (earth.isNotEmpty) {
          deck.add(earth.removeLast());
        }
      }

      // Mélange partiel très léger (10%) pour éviter les patterns
      _partialShuffle(deck, 0.10);
      addToHistory("🔥 Mélange exigeant (Mode Challenger)");
    }
  }

  // 🔥 NOUVELLE MÉTHODE : Mélange partiel pour éviter la prédictibilité
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

  // 🔥 DISTRIBUTION AMÉLIORÉE : Sans Jokers ni cartes spéciales au début
  void dealCards() {
    Random rnd = Random();

    // 1️⃣ Séparer les cartes "normales" des cartes "spéciales"
    List<PlayingCard> normalCards = [];
    List<PlayingCard> specialCards = [];

    for (var card in deck) {
      // Carte spéciale = Joker OU pouvoir spécial (7, 10, V uniquement)
      if (card.value == 'JOKER' || ['7', '10', 'V'].contains(card.value)) {
        specialCards.add(card);
      } else {
        normalCards.add(card);
      }
    }

    // 2️⃣ Mélanger les cartes normales
    normalCards.shuffle(rnd);

    // 3️⃣ Distribuer UNIQUEMENT des cartes normales
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

    // 4️⃣ Reconstituer le deck : cartes normales restantes + cartes spéciales
    deck.clear();
    deck.addAll(normalCards);
    deck.addAll(specialCards);

    // 5️⃣ Mélanger le deck final
    deck.shuffle(rnd);

    // 📊 Debug : Vérifier la composition
    int jokers = deck.where((c) => c.value == 'JOKER').length;
    int specials = deck.where((c) => ['7', '10', 'V'].contains(c.value)).length;
    addToHistory(
        "🎴 Deck recomposé : $jokers Jokers, $specials cartes spéciales");
  }

  int _getCardValue(PlayingCard card) {
    if (card.value == 'K' && (card.suit == 'hearts' || card.suit == 'diamonds'))
      return 0;
    if (card.value == 'JOKER') return -1;
    switch (card.value) {
      case 'A':
        return 1;
      case 'V':
      case 'J':
        return 11;
      case 'D':
      case 'Q':
        return 12;
      case 'K':
      case 'R':
        return 13;
      default:
        return int.tryParse(card.value) ?? 7;
    }
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
