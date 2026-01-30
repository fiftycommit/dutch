import 'dart:convert';

class PlayerAction {
  final String actionType;
  final int turnNumber;
  final DateTime timestamp;
  final Map<String, dynamic> gameState;
  final Map<String, dynamic> actionDetails;
  final Map<String, dynamic> result;

  PlayerAction({
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

  factory PlayerAction.fromJson(Map<String, dynamic> json) => PlayerAction(
        actionType: json['actionType'],
        turnNumber: json['turnNumber'],
        timestamp: DateTime.parse(json['timestamp']),
        gameState: Map<String, dynamic>.from(json['gameState'] ?? {}),
        actionDetails: Map<String, dynamic>.from(json['actionDetails'] ?? {}),
        result: Map<String, dynamic>.from(json['result'] ?? {}),
      );
}

class PlayerProfile {
  final String profileId;
  final DateTime createdAt;
  final DateTime lastUpdatedAt;
  final int gamesAnalyzed;
  final Map<String, dynamic> learnedParameters;

  PlayerProfile({
    required this.profileId,
    required this.createdAt,
    required this.lastUpdatedAt,
    required this.gamesAnalyzed,
    required this.learnedParameters,
  });

  static PlayerProfile defaultProfile({required String profileId}) {
    return PlayerProfile(
      profileId: profileId,
      createdAt: DateTime.now(),
      lastUpdatedAt: DateTime.now(),
      gamesAnalyzed: 0,
      learnedParameters: {
        'aggressiveness': 0.5,
        'caution': 0.5,
        'dutchThreshold': 15.0,
        'powerUsageRate': 0.5,
        'memoryAccuracy': 0.7,
        'riskTolerance': 0.5,
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'profileId': profileId,
        'createdAt': createdAt.toIso8601String(),
        'lastUpdatedAt': lastUpdatedAt.toIso8601String(),
        'gamesAnalyzed': gamesAnalyzed,
        'learnedParameters': learnedParameters,
      };

  factory PlayerProfile.fromJson(Map<String, dynamic> json) {
    return PlayerProfile(
      profileId: json['profileId'] ?? 'local',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      lastUpdatedAt:
          DateTime.tryParse(json['lastUpdatedAt'] ?? '') ?? DateTime.now(),
      gamesAnalyzed: json['gamesAnalyzed'] ?? 0,
      learnedParameters:
          Map<String, dynamic>.from(json['learnedParameters'] ?? {}),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory PlayerProfile.fromJsonString(String raw) {
    return PlayerProfile.fromJson(jsonDecode(raw));
  }
}

class PlayerGameRecord {
  final String gameId;
  final DateTime startTime;
  final DateTime endTime;
  final bool usedSBMM;
  final int numberOfPlayers;
  final int finalRank;
  final int finalScore;
  final bool calledDutch;
  final bool wonDutch;
  final List<PlayerAction> actions;

  PlayerGameRecord({
    required this.gameId,
    required this.startTime,
    required this.endTime,
    required this.usedSBMM,
    required this.numberOfPlayers,
    required this.finalRank,
    required this.finalScore,
    required this.calledDutch,
    required this.wonDutch,
    required this.actions,
  });

  Map<String, dynamic> toJson() => {
        'gameId': gameId,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'usedSBMM': usedSBMM,
        'numberOfPlayers': numberOfPlayers,
        'finalRank': finalRank,
        'finalScore': finalScore,
        'calledDutch': calledDutch,
        'wonDutch': wonDutch,
        'actions': actions.map((a) => a.toJson()).toList(),
      };

  factory PlayerGameRecord.fromJson(Map<String, dynamic> json) {
    return PlayerGameRecord(
      gameId: json['gameId'],
      startTime: DateTime.parse(json['startTime']),
      endTime: DateTime.parse(json['endTime']),
      usedSBMM: json['usedSBMM'] ?? false,
      numberOfPlayers: json['numberOfPlayers'] ?? 4,
      finalRank: json['finalRank'] ?? 0,
      finalScore: json['finalScore'] ?? 0,
      calledDutch: json['calledDutch'] ?? false,
      wonDutch: json['wonDutch'] ?? false,
      actions: (json['actions'] as List? ?? [])
          .map((a) => PlayerAction.fromJson(Map<String, dynamic>.from(a)))
          .toList(),
    );
  }
}
