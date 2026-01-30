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
  final Map<String, DateTime> _lastActionTimestamp = {};

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
    String? powerType,
    String? targetStrategy,
  }) {
    final list = _pendingActions[gameId];
    if (list == null) return;

    final now = DateTime.now();
    final lastActionTime = _lastActionTimestamp[gameId];
    final decisionTimeMs = lastActionTime != null ? now.difference(lastActionTime).inMilliseconds : null;
    _lastActionTimestamp[gameId] = now;

    final currentRank = _calculateCurrentRank(gameState, human);
    final isRiskyAction = _isRiskyAction(actionType, actionDetails, gameState, human);

    list.add(PlayerAction(
      actionType: actionType,
      turnNumber: turnNumber,
      timestamp: now,
      gameState: _captureGameState(gameState, human),
      actionDetails: actionDetails,
      result: {},
      currentRank: currentRank,
      isRiskyAction: isRiskyAction,
      powerType: powerType,
      targetStrategy: targetStrategy,
      decisionTimeMs: decisionTimeMs,
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
      currentRank: last.currentRank,
      isRiskyAction: last.isRiskyAction,
      powerType: last.powerType,
      targetStrategy: last.targetStrategy,
      decisionTimeMs: last.decisionTimeMs,
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

  int _calculateCurrentRank(GameState gameState, Player human) {
    final players = List<Player>.from(gameState.players);
    players.sort((a, b) => a.getEstimatedScore().compareTo(b.getEstimatedScore()));
    return players.indexOf(human) + 1;
  }

  bool _isRiskyAction(String actionType, Map<String, dynamic> actionDetails, GameState gameState, Player human) {
    if (actionType == 'replace') {
      final cardIndex = actionDetails['cardIndex'] as int?;
      if (cardIndex != null && cardIndex < human.hand.length && cardIndex < human.knownCards.length) {
        final isKnown = human.knownCards[cardIndex];
        if (isKnown) {
          final card = human.hand[cardIndex];
          if (card.points <= 3) {
            return true;
          }
        }
      }
    }
    if (actionType == 'power' && actionDetails['powerType'] == 'joker') {
      return true;
    }
    return false;
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
    final dutchQuality = getNum('dutchQuality', 0.5);
    final powerDefensiveRate = getNum('powerDefensiveRate', 0.5);
    final powerOffensiveRate = getNum('powerOffensiveRate', 0.5);
    final memoryAccuracy = getNum('memoryAccuracy', 0.7);
    final memoryRetention = getNum('memoryRetention', 0.7);
    final adaptability = getNum('adaptability', 0.5);
    final decisionSpeed = getNum('decisionSpeed', 2000.0);
    final aggressivenessWinning = getNum('aggressiveness_winning', 0.5);
    final aggressivenessLosing = getNum('aggressiveness_losing', 0.5);
    final cautionWinning = getNum('caution_winning', 0.5);
    final cautionLosing = getNum('caution_losing', 0.5);

    final defensivePowerActions = record.actions.where((a) => 
        (a.actionType == 'power' || a.actionType == 'power_skip') && 
        (a.powerType == '7' || a.powerType == '8'));
    final offensivePowerActions = record.actions.where((a) => 
        (a.actionType == 'power' || a.actionType == 'power_skip') && 
        (a.powerType == '9' || a.powerType == '10' || a.powerType == 'jack' || a.powerType == 'joker'));
    
    final usedDefensive = defensivePowerActions.where((a) => a.actionType == 'power').length;
    final usedOffensive = offensivePowerActions.where((a) => a.actionType == 'power').length;
    final defensiveOpps = defensivePowerActions.length;
    final offensiveOpps = offensivePowerActions.length;
    
    final defensiveRateObserved = defensiveOpps == 0 ? powerDefensiveRate : usedDefensive / defensiveOpps;
    final offensiveRateObserved = offensiveOpps == 0 ? powerOffensiveRate : usedOffensive / offensiveOpps;
    
    final badPower = record.actions
        .where((a) => a.actionType == 'power')
        .where((a) => (a.result['isBadDecision'] ?? false) == true)
        .length;

    final matchActions = record.actions.where((a) => a.actionType == 'match');
    final matchAttempts = matchActions.length;
    final matchSuccess = matchActions
        .where((a) => (a.result['success'] ?? false) == true)
        .length;
    final matchAccuracyObserved =
        matchAttempts == 0 ? 0.7 : matchSuccess / matchAttempts;

    final dutchSucceeded = record.calledDutch && record.wonDutch;
    final dutchFailed = record.calledDutch && !record.wonDutch;

    final riskyActions = record.actions.where((a) => a.isRiskyAction == true).length;
    final totalActions = record.actions.length;
    final riskyRateObserved = totalActions == 0 ? 0.5 : riskyActions / totalActions;

    final targetingCounts = <String, int>{'leader': 0, 'weak': 0, 'random': 0};
    for (final action in record.actions.where((a) => a.targetStrategy != null)) {
      final strat = action.targetStrategy!;
      targetingCounts[strat] = (targetingCounts[strat] ?? 0) + 1;
    }
    final dominantStrategy = targetingCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    final winningActions = record.actions.where((a) => (a.currentRank ?? 99) <= 2);
    final losingActions = record.actions.where((a) => (a.currentRank ?? 1) >= 3);
    final winningRiskyRate = winningActions.isEmpty ? 0.5 : winningActions.where((a) => a.isRiskyAction == true).length / winningActions.length;
    final losingRiskyRate = losingActions.isEmpty ? 0.5 : losingActions.where((a) => a.isRiskyAction == true).length / losingActions.length;
    final adaptabilityObserved = (winningRiskyRate - losingRiskyRate).abs();

    final decisionTimes = record.actions.where((a) => a.decisionTimeMs != null).map((a) => a.decisionTimeMs!.toDouble()).toList();
    final avgDecisionTime = decisionTimes.isEmpty ? decisionSpeed : decisionTimes.reduce((a, b) => a + b) / decisionTimes.length;

    final seenCards = <String>{};
    int memoryTests = 0;
    int memoryCorrect = 0;
    for (final action in record.actions) {
      if (action.actionType == 'power' && action.powerType == '7') {
        final cardSeen = action.result['cardSeen'];
        if (cardSeen != null) seenCards.add('${action.actionDetails['targetPlayerId']}_${action.actionDetails['cardIndex']}');
      }
      if (action.actionType == 'power' && action.powerType == '9') {
        memoryTests++;
        if (action.result['wasOptimal'] == true) memoryCorrect++;
      }
    }
    final memoryRetentionObserved = memoryTests == 0 ? memoryRetention : memoryCorrect / memoryTests;

    double newDutchQuality = dutchQuality;
    if (record.calledDutch) {
      final estimatedScore = record.actions.lastWhere((a) => a.actionType == 'dutch', orElse: () => record.actions.last).gameState['estimatedScore'] ?? record.finalScore;
      final error = (estimatedScore - record.finalScore).abs() / 30.0;
      newDutchQuality = dutchQuality * 0.9 + (1.0 - error) * 0.1;
    }

    final lr = 0.08;
    double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

    double newAgg = aggressiveness + lr * (riskyRateObserved - aggressiveness);
    double newCaution = caution + lr * ((1.0 - riskyRateObserved) - caution);

    double newPowerDefensive = powerDefensiveRate + lr * (defensiveRateObserved - powerDefensiveRate);
    double newPowerOffensive = powerOffensiveRate + lr * (offensiveRateObserved - powerOffensiveRate);
    if (badPower > 0) {
      newPowerDefensive -= lr * 0.2 * badPower;
      newPowerOffensive -= lr * 0.2 * badPower;
    }

    double newMemory = memoryAccuracy + lr * (matchAccuracyObserved - memoryAccuracy);
    double newMemoryRetention = memoryRetention + lr * (memoryRetentionObserved - memoryRetention);

    double newAdaptability = adaptability + lr * (adaptabilityObserved - adaptability);
    double newDecisionSpeed = decisionSpeed * 0.9 + avgDecisionTime * 0.1;

    double newAggWinning = aggressivenessWinning + lr * (winningRiskyRate - aggressivenessWinning);
    double newAggLosing = aggressivenessLosing + lr * (losingRiskyRate - aggressivenessLosing);
    double newCautionWinning = cautionWinning + lr * ((1.0 - winningRiskyRate) - cautionWinning);
    double newCautionLosing = cautionLosing + lr * ((1.0 - losingRiskyRate) - cautionLosing);

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
    params['dutchThreshold'] = newDutchThreshold;
    params['dutchQuality'] = clamp01(newDutchQuality);
    params['powerDefensiveRate'] = clamp01(newPowerDefensive);
    params['powerOffensiveRate'] = clamp01(newPowerOffensive);
    params['memoryAccuracy'] = clamp01(newMemory);
    params['memoryRetention'] = clamp01(newMemoryRetention);
    params['targetingStrategy'] = dominantStrategy;
    params['adaptability'] = clamp01(newAdaptability);
    params['decisionSpeed'] = newDecisionSpeed.clamp(500.0, 10000.0);
    params['aggressiveness_winning'] = clamp01(newAggWinning);
    params['aggressiveness_losing'] = clamp01(newAggLosing);
    params['caution_winning'] = clamp01(newCautionWinning);
    params['caution_losing'] = clamp01(newCautionLosing);

    // Calcul du MMR selon le nombre de joueurs et le classement final
    final int newMMR = _calculateMMRChange(
      currentMMR: profile.mmr,
      finalRank: record.finalRank,
      numberOfPlayers: record.numberOfPlayers,
    );

    return PlayerProfile(
      profileId: profile.profileId,
      createdAt: profile.createdAt,
      lastUpdatedAt: DateTime.now(),
      gamesAnalyzed: profile.gamesAnalyzed + 1,
      mmr: newMMR,
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

  /// Calcule le changement de MMR selon le classement final et le nombre de joueurs
  /// Plus il y a de joueurs, plus les gains/pertes sont importants
  int _calculateMMRChange({
    required int currentMMR,
    required int finalRank,
    required int numberOfPlayers,
  }) {
    // Multiplicateur selon le nombre de joueurs (2-6 joueurs)
    // 2 joueurs: x1.0, 3: x1.2, 4: x1.4, 5: x1.6, 6: x1.8
    final double playerMultiplier = 1.0 + (numberOfPlayers - 2) * 0.2;
    
    // Points de base selon le classement
    // 1er: +30, 2e: +10, 3e: 0, 4e: -10, 5e: -20, 6e: -30
    final int basePoints = {
      1: 30,
      2: 10,
      3: 0,
      4: -10,
      5: -20,
      6: -30,
    }[finalRank] ?? 0;
    
    // Appliquer le multiplicateur
    final int mmrChange = (basePoints * playerMultiplier).round();
    
    // Nouveau MMR (minimum 0)
    final int newMMR = (currentMMR + mmrChange).clamp(0, 9999);
    
    return newMMR;
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
