import 'playing_card.dart';

/// Pouvoir en attente suite à un match pendant la phase de réaction
class PendingMatchPower {
  final String playerId;
  final String playerName;
  final PlayingCard card;
  int? drawNumber; // numéro tiré lors de la loterie

  PendingMatchPower({
    required this.playerId,
    required this.playerName,
    required this.card,
    this.drawNumber,
  });

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'playerName': playerName,
        'card': card.toJson(),
        'drawNumber': drawNumber,
      };

  factory PendingMatchPower.fromJson(Map<String, dynamic> json) {
    return PendingMatchPower(
      playerId: json['playerId'] as String,
      playerName: json['playerName'] as String,
      card: PlayingCard.fromJson(json['card'] as Map<String, dynamic>),
      drawNumber: json['drawNumber'] as int?,
    );
  }
}

/// État du deck et de la défausse
class DeckState {
  List<PlayingCard> deck;
  List<PlayingCard> discardPile;
  PlayingCard? drawnCard;

  DeckState({
    required this.deck,
    required this.discardPile,
    this.drawnCard,
  });

  PlayingCard? get topDiscardCard =>
      discardPile.isNotEmpty ? discardPile.last : null;

  int get remainingCards => deck.length;

  factory DeckState.fromJson(Map<String, dynamic> json) {
    return DeckState(
      deck: (json['deck'] as List)
          .map((e) => PlayingCard.fromJson(e as Map<String, dynamic>))
          .toList(),
      discardPile: (json['discardPile'] as List)
          .map((e) => PlayingCard.fromJson(e as Map<String, dynamic>))
          .toList(),
      drawnCard: json['drawnCard'] != null
          ? PlayingCard.fromJson(json['drawnCard'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'deck': deck.map((c) => c.toJson()).toList(),
        'discardPile': discardPile.map((c) => c.toJson()).toList(),
        'drawnCard': drawnCard?.toJson(),
      };
}

/// État du tour en cours (phase, réaction, pouvoirs spéciaux)
class TurnState {
  int currentPlayerIndex;
  bool isWaitingForSpecialPower;
  int? specialPowerStartTime;
  PlayingCard? specialCardToActivate;
  String? specialPowerPlayerId; // joueur qui utilise le pouvoir (peut différer du currentPlayer lors d'un match)
  String? dutchCallerId;
  DateTime? reactionStartTime;
  int reactionTimeRemaining;
  PlayingCard? lastSpiedCard;
  Map<String, dynamic>? pendingSwap;
  int? turnStartTime;
  int turnTimeoutMs;
  List<String> readyPlayerIds;
  int turnCount;
  int actionCount;
  List<String> actionHistory;
  List<PendingMatchPower> pendingMatchPowers; // pouvoirs en attente après matchs pendant réaction

  TurnState({
    this.currentPlayerIndex = 0,
    this.isWaitingForSpecialPower = false,
    this.specialPowerStartTime,
    this.specialCardToActivate,
    this.specialPowerPlayerId,
    this.dutchCallerId,
    this.reactionStartTime,
    this.reactionTimeRemaining = 0,
    this.lastSpiedCard,
    this.pendingSwap,
    this.turnStartTime,
    this.turnTimeoutMs = 25000,
    List<String>? readyPlayerIds,
    this.turnCount = 0,
    this.actionCount = 0,
    List<String>? actionHistory,
    List<PendingMatchPower>? pendingMatchPowers,
  })  : readyPlayerIds = readyPlayerIds ?? [],
        actionHistory = actionHistory ?? [],
        pendingMatchPowers = pendingMatchPowers ?? [];

  void addToHistory(String action) {
    String time =
        "${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}";
    actionHistory.insert(0, "[$time] $action");
    if (actionHistory.length > 50) actionHistory.removeLast();
  }

  factory TurnState.fromJson(Map<String, dynamic> json) {
    return TurnState(
      currentPlayerIndex: json['currentPlayerIndex'] as int? ?? 0,
      isWaitingForSpecialPower:
          json['isWaitingForSpecialPower'] as bool? ?? false,
      specialPowerStartTime: json['specialPowerStartTime'] as int?,
      specialCardToActivate: json['specialCardToActivate'] != null
          ? PlayingCard.fromJson(
              json['specialCardToActivate'] as Map<String, dynamic>)
          : null,
      specialPowerPlayerId: json['specialPowerPlayerId'] as String?,
      dutchCallerId: json['dutchCallerId'] as String?,
      reactionStartTime: json['reactionStartTime'] != null
          ? DateTime.parse(json['reactionStartTime'] as String)
          : null,
      reactionTimeRemaining: json['reactionTimeRemaining'] as int? ?? 0,
      lastSpiedCard: json['lastSpiedCard'] != null
          ? PlayingCard.fromJson(json['lastSpiedCard'] as Map<String, dynamic>)
          : null,
      pendingSwap: json['pendingSwap'] != null
          ? Map<String, dynamic>.from(json['pendingSwap'] as Map)
          : null,
      turnStartTime: json['turnStartTime'] as int?,
      turnTimeoutMs: json['turnTimeoutMs'] as int? ?? 25000,
      readyPlayerIds: List<String>.from(json['readyPlayerIds'] as List? ?? []),
      turnCount: json['turnCount'] as int? ?? 0,
      actionCount: json['actionCount'] as int? ?? 0,
      actionHistory: (json['actionHistory'] as List?)?.cast<String>() ?? [],
      pendingMatchPowers: (json['pendingMatchPowers'] as List?)
              ?.map((e) =>
                  PendingMatchPower.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'currentPlayerIndex': currentPlayerIndex,
        'isWaitingForSpecialPower': isWaitingForSpecialPower,
        'specialPowerStartTime': specialPowerStartTime,
        'specialCardToActivate': specialCardToActivate?.toJson(),
        'specialPowerPlayerId': specialPowerPlayerId,
        'dutchCallerId': dutchCallerId,
        'reactionStartTime': reactionStartTime?.toIso8601String(),
        'reactionTimeRemaining': reactionTimeRemaining,
        'lastSpiedCard': lastSpiedCard?.toJson(),
        'pendingSwap': pendingSwap,
        'turnStartTime': turnStartTime,
        'turnTimeoutMs': turnTimeoutMs,
        'readyPlayerIds': readyPlayerIds,
        'turnCount': turnCount,
        'actionCount': actionCount,
        'actionHistory': actionHistory,
        'pendingMatchPowers':
            pendingMatchPowers.map((e) => e.toJson()).toList(),
      };
}

/// État du tournoi (rounds, scores cumulés, éliminations)
class TournamentState {
  int tournamentRound;
  List<String> eliminatedPlayerIds;
  Map<String, int> tournamentCumulativeScores;

  TournamentState({
    this.tournamentRound = 1,
    List<String>? eliminatedPlayerIds,
    Map<String, int>? tournamentCumulativeScores,
  })  : eliminatedPlayerIds = eliminatedPlayerIds ?? [],
        tournamentCumulativeScores = tournamentCumulativeScores ?? {};

  factory TournamentState.fromJson(Map<String, dynamic> json) {
    return TournamentState(
      tournamentRound: json['tournamentRound'] as int? ?? 1,
      eliminatedPlayerIds:
          (json['eliminatedPlayerIds'] as List?)?.cast<String>() ?? [],
      tournamentCumulativeScores:
          (json['tournamentCumulativeScores'] as Map?)?.cast<String, int>() ??
              {},
    );
  }

  Map<String, dynamic> toJson() => {
        'tournamentRound': tournamentRound,
        'eliminatedPlayerIds': eliminatedPlayerIds,
        'tournamentCumulativeScores': tournamentCumulativeScores,
      };
}
