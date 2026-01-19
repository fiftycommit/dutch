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

  // ============================================================
  // 🎴 SMART SHUFFLE - VERSION BRUTALE
  // ============================================================
  void smartShuffle() {
    Random rnd = Random();
    
    if (difficulty == Difficulty.easy) {
      // Mode facile : mélange aléatoire pur
      deck.shuffle();
      addToHistory("🎲 Mélange aléatoire pur (Mode Détendu)");
      
    } else if (difficulty == Difficulty.medium) {
      // ============================================================
      // MODE MEDIUM : ~50% de mauvaises cartes au début des pioches
      // ============================================================
      List<PlayingCard> good = [];      // 0-5 pts (A, 2, 3, 4, 5)
      List<PlayingCard> medium = [];    // 6-8 pts (6, 7, 8)
      List<PlayingCard> bad = [];       // 9+ pts (9, 10, V, D, R, Joker)

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
      
      // PHASE 1 : FOND DU DECK (pioché en DERNIER) - Bonnes cartes
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
      
      // PHASE 2 : MILIEU DU DECK - Mix
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
      
      // PHASE 3 : HAUT DU DECK (pioché en PREMIER) - 50% mauvaises
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
      // ============================================================
      // MODE HARD : 80% de mauvaises cartes PARTOUT
      // Les bonnes cartes sont ENTERRÉES au fond du deck !
      // ============================================================
      List<PlayingCard> good = [];      // 0-4 pts (A, 2, 3, 4) - TRÈS RARE
      List<PlayingCard> medium = [];    // 5-7 pts (5, 6, 7)
      List<PlayingCard> bad = [];       // 8+ pts (8, 9, 10, V, D, R, Joker) - DOMINANT

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

      // PHASE 1 : FOND DU DECK (pioché en DERNIER) - ENTERRER les bonnes cartes
      while (good.isNotEmpty) {
        deck.add(good.removeLast());
      }
      
      // Quelques moyennes au fond aussi
      int mediumForBottom = (medium.length * 0.4).round();
      for (int i = 0; i < mediumForBottom && medium.isNotEmpty; i++) {
        deck.add(medium.removeLast());
      }
      
      debugPrint("🔥 [HARD] Fond du deck: ${deck.length} cartes (bonnes enterrées)");
      
      // PHASE 2 : HAUT DU DECK (pioché en PREMIER) - 80% mauvaises !
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
  // 🃏 DEAL CARDS - VERSION BRUTALE
  // En mode HARD : les joueurs reçoivent des MAUVAISES cartes !
  // ============================================================
  void dealCards() {
    Random rnd = Random();
    
    // Séparer les cartes spéciales (on ne les distribue pas en main de départ)
    List<PlayingCard> normalCards = [];
    List<PlayingCard> specialCards = [];

    for (var card in deck) {
      if (card.value == 'JOKER' || ['7', '10', 'V'].contains(card.value)) {
        specialCards.add(card);
      } else {
        normalCards.add(card);
      }
    }

    // ============================================================
    // 🔥 DISTRIBUTION SELON LA DIFFICULTÉ
    // ============================================================
    
    if (difficulty == Difficulty.easy) {
      // MODE EASY : Distribution aléatoire
      normalCards.shuffle(rnd);
      
    } else if (difficulty == Difficulty.medium) {
      // MODE MEDIUM : Mix de bonnes et mauvaises cartes
      List<PlayingCard> goodCards = normalCards.where((c) => c.points <= 5).toList();
      List<PlayingCard> mediumCards = normalCards.where((c) => c.points >= 6 && c.points <= 8).toList();
      List<PlayingCard> badCards = normalCards.where((c) => c.points >= 9).toList();
      
      goodCards.shuffle(rnd);
      mediumCards.shuffle(rnd);
      badCards.shuffle(rnd);
      
      // Réorganiser : mauvaises d'abord (seront distribuées), bonnes ensuite (resteront dans le deck)
      normalCards = [];
      
      // Pour chaque joueur : 2 mauvaises + 2 moyennes/bonnes
      int playersCount = players.length;
      int badNeeded = playersCount * 2;
      int mediumNeeded = playersCount * 1;
      int goodNeeded = playersCount * 1;
      
      // Ajouter les cartes à distribuer EN PREMIER (seront prises par removeLast)
      // Donc on les met à la FIN de normalCards
      
      // D'abord les bonnes (resteront dans le deck après distribution)
      normalCards.addAll(goodCards);
      normalCards.addAll(mediumCards.skip(mediumNeeded));
      normalCards.addAll(badCards.skip(badNeeded));
      
      // Ensuite le mix pour la distribution (sera pris en premier)
      for (int i = 0; i < playersCount * 4; i++) {
        double roll = rnd.nextDouble();
        if (roll < 0.50 && badCards.isNotEmpty && badNeeded > 0) {
          normalCards.add(badCards.removeLast());
          badNeeded--;
        } else if (roll < 0.75 && mediumCards.isNotEmpty && mediumNeeded > 0) {
          normalCards.add(mediumCards.removeLast());
          mediumNeeded--;
        } else if (goodCards.isNotEmpty && goodNeeded > 0) {
          normalCards.add(goodCards.removeLast());
          goodNeeded--;
        } else if (badCards.isNotEmpty) {
          normalCards.add(badCards.removeLast());
        } else if (mediumCards.isNotEmpty) {
          normalCards.add(mediumCards.removeLast());
        } else if (goodCards.isNotEmpty) {
          normalCards.add(goodCards.removeLast());
        }
      }
      
    } else {
      // ============================================================
      // 🔥 MODE HARD : QUE des mauvaises cartes en main de départ !
      // Minimum 8 points par carte !
      // ============================================================
      List<PlayingCard> goodCards = normalCards.where((c) => c.points <= 4).toList();
      List<PlayingCard> mediumCards = normalCards.where((c) => c.points >= 5 && c.points <= 7).toList();
      List<PlayingCard> badCards = normalCards.where((c) => c.points >= 8).toList();
      
      goodCards.shuffle(rnd);
      mediumCards.shuffle(rnd);
      badCards.shuffle(rnd);
      
      normalCards = [];
      
      // 🔥 ENTERRER les bonnes cartes au FOND (ne seront jamais distribuées)
      normalCards.addAll(goodCards);
      
      // Mettre quelques moyennes au fond aussi
      int mediumToHide = (mediumCards.length * 0.5).round();
      for (int i = 0; i < mediumToHide && mediumCards.isNotEmpty; i++) {
        normalCards.add(mediumCards.removeLast());
      }
      
      // Mélanger le reste des moyennes avec les mauvaises
      List<PlayingCard> cardsForDistribution = [];
      cardsForDistribution.addAll(mediumCards);
      cardsForDistribution.addAll(badCards);
      cardsForDistribution.shuffle(rnd);
      
      // 🔥 FORCER des mauvaises cartes (8+ pts) pour la distribution
      // On veut 4 cartes par joueur, avec au moins 3 mauvaises (8+ pts)
      int playersCount = players.length;
      int totalCardsNeeded = playersCount * 4;
      
      List<PlayingCard> distributionPile = [];
      
      // Séparer les vraies mauvaises (8+) des moyennes (5-7)
      List<PlayingCard> reallyBad = cardsForDistribution.where((c) => c.points >= 8).toList();
      List<PlayingCard> justMedium = cardsForDistribution.where((c) => c.points < 8).toList();
      
      reallyBad.shuffle(rnd);
      justMedium.shuffle(rnd);
      
      // Pour chaque joueur : 3-4 mauvaises cartes
      for (int i = 0; i < totalCardsNeeded; i++) {
        // 85% de chance de donner une mauvaise carte (8+)
        if (rnd.nextDouble() < 0.85 && reallyBad.isNotEmpty) {
          distributionPile.add(reallyBad.removeLast());
        } else if (justMedium.isNotEmpty) {
          distributionPile.add(justMedium.removeLast());
        } else if (reallyBad.isNotEmpty) {
          distributionPile.add(reallyBad.removeLast());
        }
      }
      
      // Ajouter le reste au deck (pour les pioches futures)
      normalCards.addAll(justMedium);
      normalCards.addAll(reallyBad);
      
      // Ajouter la pile de distribution à la fin (sera prise par removeLast)
      normalCards.addAll(distributionPile);
      
      debugPrint("🔥 [HARD dealCards] Distribution: ${distributionPile.length} cartes");
      debugPrint("🔥 [HARD dealCards] Cartes 8+: ${distributionPile.where((c) => c.points >= 8).length}");
    }

    // ============================================================
    // DISTRIBUTION AUX JOUEURS
    // ============================================================
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

    // Reconstruire le deck avec les cartes restantes
    deck.clear();
    deck.addAll(normalCards);
    deck.addAll(specialCards);
    deck.shuffle(rnd);

    int jokers = deck.where((c) => c.value == 'JOKER').length;
    int specials = deck.where((c) => ['7', '10', 'V'].contains(c.value)).length;
    addToHistory("🎴 Deck recomposé : $jokers Jokers, $specials cartes spéciales");
    
    // Debug des mains
    for (var player in players) {
      int handScore = player.hand.fold(0, (sum, card) => sum + card.points);
      debugPrint("🃏 ${player.name}: ${player.hand.map((c) => '${c.value}(${c.points})').toList()} = $handScore pts");
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