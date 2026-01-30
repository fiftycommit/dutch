import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/card.dart';
import '../models/player_learning_data.dart';

class PlayerLearningService {
  static const String _profileKeyPrefix = 'player_profile_slot_';
  static const String _historyKeyPrefix = 'player_action_history_slot_';
  static const String _serverUrl = 'https://dutch-game.me/api/player-learning';

  final Map<String, DateTime> _gameStart = {};
  final Map<String, List<PlayerAction>> _pendingActions = {};

  String _profileKey(int slotId) => '$_profileKeyPrefix$slotId';
  String _historyKey(int slotId) => '$_historyKeyPrefix$slotId';

  Future<PlayerProfile> getProfile({required int slotId}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileKey(slotId));
    if (raw == null || raw.isEmpty) {
      return PlayerProfile.defaultProfile(profileId: 'slot_$slotId');
    }
    try {
      final profile = PlayerProfile.fromJsonString(raw);
      if (profile.learnedParameters.isEmpty) {
        return PlayerProfile.defaultProfile(profileId: 'slot_$slotId');
      }
      return profile;
    } catch (_) {
      return PlayerProfile.defaultProfile(profileId: 'slot_$slotId');
    }
  }

  Future<void> _saveProfile(PlayerProfile profile, {required int slotId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey(slotId), profile.toJsonString());
  }

  Future<List<PlayerGameRecord>> getHistory({required int slotId}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_historyKey(slotId)) ?? [];
    final records = <PlayerGameRecord>[];

    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        records.add(PlayerGameRecord.fromJson(Map<String, dynamic>.from(decoded)));
      } catch (_) {
        // ignore malformed history item
      }
    }

    return records;
  }

  void startGame({
    required String gameId,
  }) {
    _gameStart[gameId] = DateTime.now();
    _pendingActions[gameId] = [];
  }

  void recordAction({
    required String gameId,
    required String actionType,
    required int turnNumber,
    required GameState gameState,
    required Player human,
    required Map<String, dynamic> actionDetails,
  }) {
    final list = _pendingActions[gameId];
    if (list == null) return;

    list.add(PlayerAction(
      actionType: actionType,
      turnNumber: turnNumber,
      timestamp: DateTime.now(),
      gameState: _captureGameState(gameState, human),
      actionDetails: actionDetails,
      result: {},
    ));
  }

  void updateLastActionResult({
    required String gameId,
    required Map<String, dynamic> result,
  }) {
    final list = _pendingActions[gameId];
    if (list == null || list.isEmpty) return;

    final last = list.last;
    list[list.length - 1] = PlayerAction(
      actionType: last.actionType,
      turnNumber: last.turnNumber,
      timestamp: last.timestamp,
      gameState: last.gameState,
      actionDetails: last.actionDetails,
      result: result,
    );
  }

  Future<PlayerProfile> endGame({
    required String gameId,
    required int slotId,
    required bool usedSBMM,
    required GameState gameState,
    required Player human,
    required int finalRank,
    required int finalScore,
    required bool calledDutch,
    required bool wonDutch,
  }) async {
    final start = _gameStart[gameId] ?? DateTime.now();
    final actions = _pendingActions[gameId] ?? [];

    final profileBefore = await getProfile(slotId: slotId);

    final record = PlayerGameRecord(
      gameId: gameId,
      startTime: start,
      endTime: DateTime.now(),
      usedSBMM: usedSBMM,
      numberOfPlayers: gameState.players.length,
      finalRank: finalRank,
      finalScore: finalScore,
      calledDutch: calledDutch,
      wonDutch: wonDutch,
      actions: actions,
      profileBefore: Map<String, dynamic>.from(profileBefore.learnedParameters),
    );

    final updated = _updateProfile(profileBefore, record);
    await _saveProfile(updated, slotId: slotId);

    final recordWithAfter = PlayerGameRecord(
      gameId: record.gameId,
      startTime: record.startTime,
      endTime: record.endTime,
      usedSBMM: record.usedSBMM,
      numberOfPlayers: record.numberOfPlayers,
      finalRank: record.finalRank,
      finalScore: record.finalScore,
      calledDutch: record.calledDutch,
      wonDutch: record.wonDutch,
      actions: record.actions,
      profileBefore: record.profileBefore,
      profileAfter: Map<String, dynamic>.from(updated.learnedParameters),
    );

    await _appendHistory(recordWithAfter, slotId: slotId);

    await _uploadToServer(slotId: slotId, profile: updated);

    _gameStart.remove(gameId);
    _pendingActions.remove(gameId);

    return updated;
  }

  Future<void> _appendHistory(PlayerGameRecord record, {required int slotId}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_historyKey(slotId)) ?? [];

    final updated = [jsonEncode(record.toJson()), ...raw];
    final trimmed = updated.length > 10 ? updated.sublist(0, 10) : updated;

    await prefs.setStringList(_historyKey(slotId), trimmed);
  }

  Future<void> _uploadToServer({
    required int slotId,
    required PlayerProfile profile,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clientId = prefs.getString('multiplayer_client_id');
      if (clientId == null || clientId.isEmpty) return;

      final history = await getHistory(slotId: slotId);

      final payload = {
        'clientId': clientId,
        'slotId': slotId,
        'profile': profile.toJson(),
        'history': history.map((g) => {
              'gameId': g.gameId,
              'startTime': g.startTime.toIso8601String(),
              'endTime': g.endTime.toIso8601String(),
              'usedSBMM': g.usedSBMM,
              'numberOfPlayers': g.numberOfPlayers,
              'finalRank': g.finalRank,
              'finalScore': g.finalScore,
              'calledDutch': g.calledDutch,
              'wonDutch': g.wonDutch,
              'profileBefore': g.profileBefore,
              'profileAfter': g.profileAfter,
            }).toList(),
      };

      await http.post(
        Uri.parse('$_serverUrl/upload'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
    } catch (_) {
      // best-effort
    }
  }

  PlayerProfile _updateProfile(PlayerProfile profile, PlayerGameRecord record) {
    final params = Map<String, dynamic>.from(profile.learnedParameters);

    double getNum(String key, double fallback) {
      final v = params[key];
      if (v is num) return v.toDouble();
      return fallback;
    }

    final aggressiveness = getNum('aggressiveness', 0.5);
    final caution = getNum('caution', 0.5);
    final dutchThreshold = getNum('dutchThreshold', 15.0);
    final powerUsageRate = getNum('powerUsageRate', 0.5);
    final memoryAccuracy = getNum('memoryAccuracy', 0.7);
    final riskTolerance = getNum('riskTolerance', 0.5);

    final powerOpportunityActions =
        record.actions.where((a) => a.actionType == 'power' || a.actionType == 'power_skip');
    final usedPowers =
        powerOpportunityActions.where((a) => a.actionType == 'power').length;
    final badPower = powerOpportunityActions
        .where((a) => a.actionType == 'power')
        .where((a) => (a.result['isBadDecision'] ?? false) == true)
        .length;

    final opportunities = powerOpportunityActions.length;
    final powerRateObserved = opportunities == 0 ? powerUsageRate : usedPowers / opportunities;

    final matchActions = record.actions.where((a) => a.actionType == 'match');
    final matchAttempts = matchActions.length;
    final matchSuccess = matchActions
        .where((a) => (a.result['success'] ?? false) == true)
        .length;
    final matchAccuracyObserved =
        matchAttempts == 0 ? 0.7 : matchSuccess / matchAttempts;

    final dutchSucceeded = record.calledDutch && record.wonDutch;
    final dutchFailed = record.calledDutch && !record.wonDutch;

    final performance = record.numberOfPlayers <= 1
        ? 0.5
        : (record.numberOfPlayers - record.finalRank) /
            (record.numberOfPlayers - 1);

    final lr = 0.08;

    double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

    double newAgg = aggressiveness + lr * (performance - 0.5);
    double newCaution = caution + lr * ((0.5 - performance));

    double newPowerUsage = powerUsageRate + lr * (powerRateObserved - powerUsageRate);
    if (badPower > 0) {
      newPowerUsage -= lr * 0.4 * badPower;
    }

    double newMemory = memoryAccuracy + lr * (matchAccuracyObserved - memoryAccuracy);

    double newRisk = riskTolerance + lr * (performance - 0.5);

    double newDutchThreshold = dutchThreshold;
    if (dutchSucceeded) {
      newDutchThreshold -= 0.8;
    } else if (dutchFailed) {
      newDutchThreshold += 1.2;
    }
    if (newDutchThreshold < 5) newDutchThreshold = 5;
    if (newDutchThreshold > 30) newDutchThreshold = 30;

    params['aggressiveness'] = clamp01(newAgg);
    params['caution'] = clamp01(newCaution);
    params['powerUsageRate'] = clamp01(newPowerUsage);
    params['memoryAccuracy'] = clamp01(newMemory);
    params['riskTolerance'] = clamp01(newRisk);
    params['dutchThreshold'] = newDutchThreshold;

    return PlayerProfile(
      profileId: profile.profileId,
      createdAt: profile.createdAt,
      lastUpdatedAt: DateTime.now(),
      gamesAnalyzed: profile.gamesAnalyzed + 1,
      learnedParameters: params,
    );
  }

  Map<String, dynamic> _captureGameState(GameState gameState, Player human) {
    final topDiscard = gameState.topDiscardCard;
    final special = gameState.specialCardToActivate;

    return {
      'phase': gameState.phase.toString().split('.').last,
      'turn': gameState.currentPlayerIndex,
      'deckSize': gameState.deck.length,
      'discardPileSize': gameState.discardPile.length,
      'topDiscardCard': topDiscard?.toJson(),
      'isWaitingForSpecialPower': gameState.isWaitingForSpecialPower,
      'specialCardToActivate': special?.toJson(),
      'humanHandSize': human.hand.length,
      'humanKnownCards': human.knownCards.where((k) => k).length,
      'humanEstimatedScore': human.getEstimatedScore(),
      'opponentsHandSizes': gameState.players
          .where((p) => p.id != human.id)
          .map((p) => p.hand.length)
          .toList(),
    };
  }

  static bool isBadPowerDecision({
    required PlayingCard specialCard,
    required Player target,
  }) {
    if (specialCard.value == 'JOKER') {
      return target.hand.length <= 1;
    }
    return false;
  }
}
