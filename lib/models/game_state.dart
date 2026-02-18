import 'playing_card.dart';
import 'player.dart';
import 'game_settings.dart';
import 'game_sub_states.dart';

enum GameMode { quick, tournament }

enum GamePhase { setup, playing, reaction, dutchCalled, ended }

class GameState {
  List<Player> players;
  GameMode gameMode;
  GamePhase phase;
  final Difficulty difficulty;

  /// Sous-objets structurés
  final DeckState deckState;
  final TurnState turnState;
  final TournamentState tournamentState;

  // === Forwarding getters/setters pour compatibilité ===
  List<PlayingCard> get deck => deckState.deck;
  set deck(List<PlayingCard> v) => deckState.deck = v;
  List<PlayingCard> get discardPile => deckState.discardPile;
  set discardPile(List<PlayingCard> v) => deckState.discardPile = v;
  PlayingCard? get drawnCard => deckState.drawnCard;
  set drawnCard(PlayingCard? v) => deckState.drawnCard = v;

  int get currentPlayerIndex => turnState.currentPlayerIndex;
  set currentPlayerIndex(int v) => turnState.currentPlayerIndex = v;
  bool get isWaitingForSpecialPower => turnState.isWaitingForSpecialPower;
  set isWaitingForSpecialPower(bool v) => turnState.isWaitingForSpecialPower = v;
  PlayingCard? get specialCardToActivate => turnState.specialCardToActivate;
  set specialCardToActivate(PlayingCard? v) => turnState.specialCardToActivate = v;
  String? get dutchCallerId => turnState.dutchCallerId;
  set dutchCallerId(String? v) => turnState.dutchCallerId = v;
  DateTime? get reactionStartTime => turnState.reactionStartTime;
  set reactionStartTime(DateTime? v) => turnState.reactionStartTime = v;
  int get reactionTimeRemaining => turnState.reactionTimeRemaining;
  set reactionTimeRemaining(int v) => turnState.reactionTimeRemaining = v;
  PlayingCard? get lastSpiedCard => turnState.lastSpiedCard;
  set lastSpiedCard(PlayingCard? v) => turnState.lastSpiedCard = v;
  Map<String, dynamic>? get pendingSwap => turnState.pendingSwap;
  set pendingSwap(Map<String, dynamic>? v) => turnState.pendingSwap = v;
  int? get turnStartTime => turnState.turnStartTime;
  set turnStartTime(int? v) => turnState.turnStartTime = v;
  int get turnTimeoutMs => turnState.turnTimeoutMs;
  set turnTimeoutMs(int v) => turnState.turnTimeoutMs = v;
  List<String> get readyPlayerIds => turnState.readyPlayerIds;
  set readyPlayerIds(List<String> v) => turnState.readyPlayerIds = v;
  int get turnCount => turnState.turnCount;
  set turnCount(int v) => turnState.turnCount = v;
  int get actionCount => turnState.actionCount;
  set actionCount(int v) => turnState.actionCount = v;
  List<String> get actionHistory => turnState.actionHistory;
  set actionHistory(List<String> v) => turnState.actionHistory = v;

  int get tournamentRound => tournamentState.tournamentRound;
  set tournamentRound(int v) => tournamentState.tournamentRound = v;
  List<String> get eliminatedPlayerIds => tournamentState.eliminatedPlayerIds;
  set eliminatedPlayerIds(List<String> v) => tournamentState.eliminatedPlayerIds = v;
  Map<String, int> get tournamentCumulativeScores => tournamentState.tournamentCumulativeScores;
  set tournamentCumulativeScores(Map<String, int> v) => tournamentState.tournamentCumulativeScores = v;

  GameState({
    required this.players,
    required List<PlayingCard> deck,
    required List<PlayingCard> discardPile,
    int currentPlayerIndex = 0,
    this.gameMode = GameMode.quick,
    this.phase = GamePhase.setup,
    int tournamentRound = 1,
    this.difficulty = Difficulty.medium,
    List<String>? eliminatedPlayerIds,
    PlayingCard? drawnCard,
    bool isWaitingForSpecialPower = false,
    PlayingCard? specialCardToActivate,
    String? dutchCallerId,
    DateTime? reactionStartTime,
    List<String>? actionHistory,
    int reactionTimeRemaining = 0,
    PlayingCard? lastSpiedCard,
    Map<String, dynamic>? pendingSwap,
    Map<String, int>? tournamentCumulativeScores,
    int? turnStartTime,
    int turnTimeoutMs = 25000,
    List<String>? readyPlayerIds,
    int turnCount = 0,
    int actionCount = 0,
  })  : deckState = DeckState(
          deck: deck,
          discardPile: discardPile,
          drawnCard: drawnCard,
        ),
        turnState = TurnState(
          currentPlayerIndex: currentPlayerIndex,
          isWaitingForSpecialPower: isWaitingForSpecialPower,
          specialCardToActivate: specialCardToActivate,
          dutchCallerId: dutchCallerId,
          reactionStartTime: reactionStartTime,
          reactionTimeRemaining: reactionTimeRemaining,
          lastSpiedCard: lastSpiedCard,
          pendingSwap: pendingSwap,
          turnStartTime: turnStartTime,
          turnTimeoutMs: turnTimeoutMs,
          readyPlayerIds: readyPlayerIds,
          turnCount: turnCount,
          actionCount: actionCount,
          actionHistory: actionHistory,
        ),
        tournamentState = TournamentState(
          tournamentRound: tournamentRound,
          eliminatedPlayerIds: eliminatedPlayerIds,
          tournamentCumulativeScores: tournamentCumulativeScores,
        );

  Player get currentPlayer => players[currentPlayerIndex];
  PlayingCard? get topDiscardCard =>
      discardPile.isNotEmpty ? discardPile.last : null;
  int get remainingDeckCards => deck.length;

  void nextTurn() {
    int oldIndex = currentPlayerIndex;
    
    // Incrémenter le compteur d'actions à chaque passage de tour
    actionCount++;
    
    do {
      currentPlayerIndex = (currentPlayerIndex + 1) % players.length;
    } while (eliminatedPlayerIds.contains(currentPlayer.id));
    
    // Incrémenter le compteur de tours quand on revient au premier joueur actif
    // (une rotation complète de la table)
    if (currentPlayerIndex <= oldIndex && players.isNotEmpty) {
      turnCount++;
    }
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
    // Jokers avec couleurs différentes pour avoir des IDs uniques
    deck.add(PlayingCard.create('hearts', 'JOKER'));    // Joker rouge
    deck.add(PlayingCard.create('spades', 'JOKER'));    // Joker noir
    return deck;
  }

  void smartShuffle() {
    deck.shuffle();
    addToHistory("🎲 Mélange aléatoire");
  }
  

  void dealCards() {
    deck.shuffle();
    for (var player in players) {
      player.hand = [];
      player.knownCards = [];
      for (int i = 0; i < 4; i++) {
        if (deck.isNotEmpty) {
          player.hand.add(deck.removeLast());
          player.knownCards.add(false);
        }
      }
    }
    _logDealResults();
  }

  void _logDealResults() {
    int jokers = deck.where((c) => c.value == 'JOKER').length;
    addToHistory("🃏 Distribution terminée ($jokers Jokers dans le deck)");
  }

  void shuffleDeckRandomly() {
    deck.shuffle();
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

  /// Retourne les rangs réels avec gestion des ex-aequo.
  /// Retourne une Map (playerId -> rang) où le rang tient compte des égalités.
  /// Cas spécial : le Dutch caller gagnant est SEUL #1, les autres avec même score sont #2.
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
      if (dutchCallerId != null &&
          !didDutchCallerWin() &&
          player.id == dutchCallerId) {
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
    sorted
        .sort((a, b) => getCumulativeScore(a).compareTo(getCumulativeScore(b)));
    return sorted;
  }

  // Sérialisation JSON pour multijoueur
  factory GameState.fromJson(Map<String, dynamic> json) {
    return GameState(
      players: (json['players'] as List)
          .map((e) => Player.fromJson(e as Map<String, dynamic>))
          .toList(),
      deck: (json['deck'] as List)
          .map((e) => PlayingCard.fromJson(e as Map<String, dynamic>))
          .toList(),
      discardPile: (json['discardPile'] as List)
          .map((e) => PlayingCard.fromJson(e as Map<String, dynamic>))
          .toList(),
      currentPlayerIndex: json['currentPlayerIndex'] as int,
      gameMode: GameMode.values[json['gameMode'] as int],
      phase: GamePhase.values[json['phase'] as int],
      difficulty: Difficulty.values[json['difficulty'] as int],
      tournamentRound: json['tournamentRound'] as int? ?? 1,
      eliminatedPlayerIds:
          (json['eliminatedPlayerIds'] as List?)?.cast<String>() ?? [],
      drawnCard: json['drawnCard'] != null
          ? PlayingCard.fromJson(json['drawnCard'] as Map<String, dynamic>)
          : null,
      isWaitingForSpecialPower:
          json['isWaitingForSpecialPower'] as bool? ?? false,
      specialCardToActivate: json['specialCardToActivate'] != null
          ? PlayingCard.fromJson(
              json['specialCardToActivate'] as Map<String, dynamic>)
          : null,
      dutchCallerId: json['dutchCallerId'] as String?,
      reactionStartTime: json['reactionStartTime'] != null
          ? DateTime.parse(json['reactionStartTime'] as String)
          : null,
      actionHistory: (json['actionHistory'] as List?)?.cast<String>() ?? [],
      reactionTimeRemaining: json['reactionTimeRemaining'] as int? ?? 0,
      lastSpiedCard: json['lastSpiedCard'] != null
          ? PlayingCard.fromJson(json['lastSpiedCard'] as Map<String, dynamic>)
          : null,
      pendingSwap: json['pendingSwap'] != null
          ? Map<String, dynamic>.from(json['pendingSwap'] as Map)
          : null,
      tournamentCumulativeScores:
          (json['tournamentCumulativeScores'] as Map?)?.cast<String, int>() ??
              {},
      turnStartTime: json['turnStartTime'] as int?,
      turnTimeoutMs: json['turnTimeoutMs'] as int? ?? 25000,
      readyPlayerIds: List<String>.from(json['readyPlayerIds'] as List? ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'players': players.map((p) => p.toJson()).toList(),
      'deck': deck.map((c) => c.toJson()).toList(),
      'discardPile': discardPile.map((c) => c.toJson()).toList(),
      'currentPlayerIndex': currentPlayerIndex,
      'gameMode': gameMode.index,
      'phase': phase.index,
      'difficulty': difficulty.index,
      'tournamentRound': tournamentRound,
      'eliminatedPlayerIds': eliminatedPlayerIds,
      'drawnCard': drawnCard?.toJson(),
      'isWaitingForSpecialPower': isWaitingForSpecialPower,
      'specialCardToActivate': specialCardToActivate?.toJson(),
      'dutchCallerId': dutchCallerId,
      'reactionStartTime': reactionStartTime?.toIso8601String(),
      'actionHistory': actionHistory,
      'reactionTimeRemaining': reactionTimeRemaining,
      'lastSpiedCard': lastSpiedCard?.toJson(),
      'pendingSwap': pendingSwap,
      'tournamentCumulativeScores': tournamentCumulativeScores,
      'turnStartTime': turnStartTime,
      'turnTimeoutMs': turnTimeoutMs,
      'readyPlayerIds': readyPlayerIds,
    };
  }
}
