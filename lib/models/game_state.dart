import 'dart:math';
import 'playing_card.dart';
import 'player.dart';
import 'game_settings.dart';
import 'game_sub_states.dart';
import '../services/game/engine_random.dart';

enum GameMode { quick, tournament }

enum GamePhase { setup, playing, specialPower, reaction, dutchCalled, ended }

enum DealMode {
  blockSequential,
  roundRobin,
  randomIndices,
  disjointValues,
}

class GameState {
  static Random get _dealRandom => EngineRandom.instance;

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
  set isWaitingForSpecialPower(bool v) =>
      turnState.isWaitingForSpecialPower = v;
  int? get specialPowerStartTime => turnState.specialPowerStartTime;
  set specialPowerStartTime(int? v) => turnState.specialPowerStartTime = v;
  PlayingCard? get specialCardToActivate => turnState.specialCardToActivate;
  set specialCardToActivate(PlayingCard? v) =>
      turnState.specialCardToActivate = v;
  String? get specialPowerPlayerId => turnState.specialPowerPlayerId;
  set specialPowerPlayerId(String? v) => turnState.specialPowerPlayerId = v;
  List<PendingMatchPower> get pendingMatchPowers =>
      turnState.pendingMatchPowers;
  set pendingMatchPowers(List<PendingMatchPower> v) =>
      turnState.pendingMatchPowers = v;
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
  set eliminatedPlayerIds(List<String> v) =>
      tournamentState.eliminatedPlayerIds = v;
  Map<String, int> get tournamentCumulativeScores =>
      tournamentState.tournamentCumulativeScores;
  set tournamentCumulativeScores(Map<String, int> v) =>
      tournamentState.tournamentCumulativeScores = v;

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
    int? specialPowerStartTime,
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
          specialPowerStartTime: specialPowerStartTime,
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
    deck.add(PlayingCard.create('hearts', 'JOKER')); // Joker rouge
    deck.add(PlayingCard.create('spades', 'JOKER')); // Joker noir
    return deck;
  }

  void smartShuffle() {
    deck.shuffle(EngineRandom.instance);
    addToHistory("🎲 Mélange aléatoire");
  }

  void dealCards({DealMode mode = DealMode.roundRobin}) {
    deck.shuffle(EngineRandom.instance);
    for (var player in players) {
      player.hand = [];
      player.knownCards = [];
    }

    switch (mode) {
      case DealMode.blockSequential:
        _dealBlockSequential();
        break;
      case DealMode.roundRobin:
        _dealRoundRobin();
        break;
      case DealMode.randomIndices:
        _dealRandomIndices();
        break;
      case DealMode.disjointValues:
        _dealDisjointValues();
        break;
    }

    _logDealResults(mode: mode);
  }

  void _dealBlockSequential() {
    for (var player in players) {
      for (int i = 0; i < 4; i++) {
        _dealFromTop(player);
      }
    }
  }

  void _dealRoundRobin() {
    for (int i = 0; i < 4; i++) {
      for (var player in players) {
        _dealFromTop(player);
      }
    }
  }

  void _dealRandomIndices() {
    for (var player in players) {
      for (int i = 0; i < 4; i++) {
        if (deck.isEmpty) return;
        final randomIndex = _dealRandom.nextInt(deck.length);
        final card = deck.removeAt(randomIndex);
        player.hand.add(card);
        player.knownCards.add(false);
      }
    }
  }

  void _dealDisjointValues() {
    final usedValues = <String>{};

    for (int i = 0; i < 4; i++) {
      for (var player in players) {
        if (deck.isEmpty) return;
        final safeIndex = _pickIndexAvoidingValues(usedValues);
        final card =
            safeIndex == null ? deck.removeLast() : deck.removeAt(safeIndex);
        player.hand.add(card);
        player.knownCards.add(false);
        usedValues.add(card.value);
      }
    }
  }

  void _dealFromTop(Player player) {
    if (deck.isEmpty) return;
    player.hand.add(deck.removeLast());
    player.knownCards.add(false);
  }

  int? _pickIndexAvoidingValues(Set<String> forbiddenValues) {
    final candidates = <int>[];
    for (int i = 0; i < deck.length; i++) {
      if (!forbiddenValues.contains(deck[i].value)) {
        candidates.add(i);
      }
    }
    if (candidates.isEmpty) return null;
    return candidates[_dealRandom.nextInt(candidates.length)];
  }

  int _countValueOverlapsInHands() {
    final valueCounts = <String, int>{};
    for (final player in players) {
      for (final card in player.hand) {
        valueCounts[card.value] = (valueCounts[card.value] ?? 0) + 1;
      }
    }

    int overlaps = 0;
    for (final count in valueCounts.values) {
      if (count > 1) overlaps += count - 1;
    }
    return overlaps;
  }

  void _logDealResults({required DealMode mode}) {
    int jokers = deck.where((c) => c.value == 'JOKER').length;
    final overlaps = _countValueOverlapsInHands();
    addToHistory(
      "🃏 Distribution ${mode.name} terminée "
      "($jokers Jokers dans le deck, overlaps=$overlaps)",
    );
  }

  void shuffleDeckRandomly() {
    deck.shuffle(EngineRandom.instance);
  }

  List<Player> getFinalRanking() {
    // Séparer les joueurs actifs des spectateurs (expulsés/kickés)
    List<Player> active = players.where((p) => !p.isSpectator).toList();
    List<Player> spectators = players.where((p) => p.isSpectator).toList();

    // Trier les actifs par score, mais en cas d'égalité, celui qui a Dutch est devant
    active.sort((a, b) {
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
      final failedCaller = active.cast<Player?>().firstWhere(
            (p) => p?.id == dutchCallerId,
            orElse: () => null,
          );
      if (failedCaller != null) {
        active.remove(failedCaller);
        active.add(failedCaller);
      }
    }

    // Les spectateurs (expulsés) sont toujours après les joueurs actifs
    return [...active, ...spectators];
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

      // Cas spécial : spectateurs (expulsés) et Dutch caller raté sont derniers
      if (player.isSpectator) {
        ranks[player.id] = ranking.length; // Dernier
        continue;
      }
      if (dutchCallerId != null &&
          !didDutchCallerWin() &&
          player.id == dutchCallerId) {
        // Dutch caller raté : juste avant les spectateurs ou dernier
        final spectatorCount = ranking.where((p) => p.isSpectator).length;
        ranks[player.id] =
            ranking.length - spectatorCount; // Dernier des actifs
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
    final gs = GameState(
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
      specialPowerStartTime: json['specialPowerStartTime'] as int?,
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
    // Champs additionnels non passés au constructeur
    gs.specialPowerPlayerId = json['specialPowerPlayerId'] as String?;
    if (json['pendingMatchPowers'] is List) {
      gs.pendingMatchPowers = (json['pendingMatchPowers'] as List)
          .map((e) => PendingMatchPower.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return gs;
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
      'specialPowerStartTime': specialPowerStartTime,
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
