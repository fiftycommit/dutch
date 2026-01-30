/// Modèle de données pour l'apprentissage des bots
class BotAction {
  final String actionType; // 'draw', 'discard', 'replace', 'power', 'dutch'
  final int turnNumber;
  final DateTime timestamp;
  final Map<String, dynamic> gameState; // État du jeu au moment de l'action
  final Map<String, dynamic> actionDetails; // Détails de l'action
  final Map<String, dynamic> result; // Résultat de l'action

  BotAction({
    required this.actionType,
    required this.turnNumber,
    required this.timestamp,
    required this.gameState,
    required this.actionDetails,
    required this.result,
  });

  Map<String, dynamic> toJson() => {
        'actionType': actionType,
        'turnNumber': turnNumber,
        'timestamp': timestamp.toIso8601String(),
        'gameState': gameState,
        'actionDetails': actionDetails,
        'result': result,
      };

  factory BotAction.fromJson(Map<String, dynamic> json) => BotAction(
        actionType: json['actionType'],
        turnNumber: json['turnNumber'],
        timestamp: DateTime.parse(json['timestamp']),
        gameState: json['gameState'],
        actionDetails: json['actionDetails'],
        result: json['result'],
      );
}

class BotGameRecord {
  final String gameId;
  final String botId;
  final String botName;
  final String botBehavior; // 'fast', 'aggressive', 'balanced'
  final String botSkillLevel; // 'bronze', 'silver', 'gold'
  final DateTime startTime;
  final DateTime? endTime;
  final int numberOfPlayers;
  final String gameMode; // 'quick', 'tournament'
  final bool usedSBMM;

  // Contexte humain (pour estimer la "chance de battre l'humain")
  final int? humanFinalScore;
  final int? humanFinalHandSize;
  final int? botFinalHandSize;
  final double? pBeatHuman;
  
  // Tracking expérimental pour analyse de triage
  final List<Map<String, dynamic>>? initialDeck;
  final int? turnsBeforeDutch;
  final List<int>? discardsPerRound;
  final List<Map<String, dynamic>>? triageDecisions;
  
  // Données de la partie
  final List<BotAction> actions;
  final int initialHandSize;
  final int finalScore;
  final int finalRank; // 1 = winner, 2 = second, etc.
  final bool calledDutch;
  final bool wonDutch;
  final int cardsAtDutch;
  final int scoreAtDutch;
  
  // Métriques de performance
  final int totalTurns;
  final double avgDecisionTime; // en ms
  final int powerUsesCount;
  final int goodDecisions; // Décisions qui ont amélioré le score
  final int badDecisions; // Décisions qui ont empiré le score
  
  // Contexte des adversaires
  final List<Map<String, dynamic>> opponents;

  BotGameRecord({
    required this.gameId,
    required this.botId,
    required this.botName,
    required this.botBehavior,
    required this.botSkillLevel,
    required this.startTime,
    this.endTime,
    required this.numberOfPlayers,
    required this.gameMode,
    required this.usedSBMM,
    this.humanFinalScore,
    this.humanFinalHandSize,
    this.botFinalHandSize,
    this.pBeatHuman,
    this.initialDeck,
    this.turnsBeforeDutch,
    this.discardsPerRound,
    this.triageDecisions,
    required this.actions,
    required this.initialHandSize,
    required this.finalScore,
    required this.finalRank,
    required this.calledDutch,
    required this.wonDutch,
    required this.cardsAtDutch,
    required this.scoreAtDutch,
    required this.totalTurns,
    required this.avgDecisionTime,
    required this.powerUsesCount,
    required this.goodDecisions,
    required this.badDecisions,
    required this.opponents,
  });

  Map<String, dynamic> toJson() => {
        'gameId': gameId,
        'botId': botId,
        'botName': botName,
        'botBehavior': botBehavior,
        'botSkillLevel': botSkillLevel,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'numberOfPlayers': numberOfPlayers,
        'gameMode': gameMode,
        'usedSBMM': usedSBMM,
        'humanFinalScore': humanFinalScore,
        'humanFinalHandSize': humanFinalHandSize,
        'botFinalHandSize': botFinalHandSize,
        'pBeatHuman': pBeatHuman,
        'initialDeck': initialDeck,
        'turnsBeforeDutch': turnsBeforeDutch,
        'discardsPerRound': discardsPerRound,
        'triageDecisions': triageDecisions,
        'actions': actions.map((a) => a.toJson()).toList(),
        'initialHandSize': initialHandSize,
        'finalScore': finalScore,
        'finalRank': finalRank,
        'calledDutch': calledDutch,
        'wonDutch': wonDutch,
        'cardsAtDutch': cardsAtDutch,
        'scoreAtDutch': scoreAtDutch,
        'totalTurns': totalTurns,
        'avgDecisionTime': avgDecisionTime,
        'powerUsesCount': powerUsesCount,
        'goodDecisions': goodDecisions,
        'badDecisions': badDecisions,
        'opponents': opponents,
      };

  factory BotGameRecord.fromJson(Map<String, dynamic> json) => BotGameRecord(
        gameId: json['gameId'],
        botId: json['botId'],
        botName: json['botName'],
        botBehavior: json['botBehavior'],
        botSkillLevel: json['botSkillLevel'],
        startTime: DateTime.parse(json['startTime']),
        endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
        numberOfPlayers: json['numberOfPlayers'],
        gameMode: json['gameMode'],
        usedSBMM: json['usedSBMM'],
        humanFinalScore: json['humanFinalScore'],
        humanFinalHandSize: json['humanFinalHandSize'],
        botFinalHandSize: json['botFinalHandSize'],
        pBeatHuman: (json['pBeatHuman'] is num) ? (json['pBeatHuman'] as num).toDouble() : null,
        initialDeck: json['initialDeck'] != null ? List<Map<String, dynamic>>.from(json['initialDeck']) : null,
        turnsBeforeDutch: json['turnsBeforeDutch'],
        discardsPerRound: json['discardsPerRound'] != null ? List<int>.from(json['discardsPerRound']) : null,
        triageDecisions: json['triageDecisions'] != null ? List<Map<String, dynamic>>.from(json['triageDecisions']) : null,
        actions: (json['actions'] as List).map((a) => BotAction.fromJson(a)).toList(),
        initialHandSize: json['initialHandSize'],
        finalScore: json['finalScore'],
        finalRank: json['finalRank'],
        calledDutch: json['calledDutch'],
        wonDutch: json['wonDutch'],
        cardsAtDutch: json['cardsAtDutch'],
        scoreAtDutch: json['scoreAtDutch'],
        totalTurns: json['totalTurns'],
        avgDecisionTime: json['avgDecisionTime'],
        powerUsesCount: json['powerUsesCount'],
        goodDecisions: json['goodDecisions'],
        badDecisions: json['badDecisions'],
        opponents: List<Map<String, dynamic>>.from(json['opponents']),
      );
}

class BotProfile {
  final String botId;
  final String behavior;
  final String skillLevel;
  final DateTime createdAt;
  final DateTime lastPlayedAt;
  
  // Statistiques globales
  final int totalGames;
  final int wins;
  final int losses;
  final double winRate;
  final double avgScore;
  final double avgRank;
  final int totalDutchCalls;
  final int successfulDutchCalls;
  
  // MMR et évolution
  final int mmr;
  final List<int> mmrHistory;
  
  // Paramètres appris
  final Map<String, dynamic> learnedParameters;

  BotProfile({
    required this.botId,
    required this.behavior,
    required this.skillLevel,
    required this.createdAt,
    required this.lastPlayedAt,
    required this.totalGames,
    required this.wins,
    required this.losses,
    required this.winRate,
    required this.avgScore,
    required this.avgRank,
    required this.totalDutchCalls,
    required this.successfulDutchCalls,
    required this.mmr,
    required this.mmrHistory,
    required this.learnedParameters,
  });

  Map<String, dynamic> toJson() => {
        'botId': botId,
        'behavior': behavior,
        'skillLevel': skillLevel,
        'createdAt': createdAt.toIso8601String(),
        'lastPlayedAt': lastPlayedAt.toIso8601String(),
        'totalGames': totalGames,
        'wins': wins,
        'losses': losses,
        'winRate': winRate,
        'avgScore': avgScore,
        'avgRank': avgRank,
        'totalDutchCalls': totalDutchCalls,
        'successfulDutchCalls': successfulDutchCalls,
        'mmr': mmr,
        'mmrHistory': mmrHistory,
        'learnedParameters': learnedParameters,
      };

  factory BotProfile.fromJson(Map<String, dynamic> json) => BotProfile(
        botId: json['botId'],
        behavior: json['behavior'],
        skillLevel: json['skillLevel'],
        createdAt: DateTime.parse(json['createdAt']),
        lastPlayedAt: DateTime.parse(json['lastPlayedAt']),
        totalGames: json['totalGames'],
        wins: json['wins'],
        losses: json['losses'],
        winRate: json['winRate'],
        avgScore: json['avgScore'],
        avgRank: json['avgRank'],
        totalDutchCalls: json['totalDutchCalls'],
        successfulDutchCalls: json['successfulDutchCalls'],
        mmr: json['mmr'],
        mmrHistory: List<int>.from(json['mmrHistory']),
        learnedParameters: json['learnedParameters'],
      );
}
