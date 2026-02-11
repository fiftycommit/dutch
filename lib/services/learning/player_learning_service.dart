import 'dart:convert';
import 'dart:math' show exp;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../../models/game_state.dart';
import '../../models/player.dart';
import '../../models/playing_card.dart';
import '../../models/player_learning_data.dart';
import '../../core/interfaces/i_learning_service.dart';
import '../multiplayer/client_id_service.dart';
import '../network/network_probe_service.dart';

class PlayerLearningService implements IPlayerLearningService {
  static const String _profileKeyPrefix = 'player_profile_slot_';
  static const String _historyKeyPrefix = 'player_action_history_slot_';
  static const String _serverUrl = 'https://dutch-game.me/api/player-learning';
  static const String _botLearningUrl =
      'https://dutch-game.me/api/bot-learning';
  static const String _cloneIdKeyPrefix = 'ghost_clone_id_slot_';
  static const Duration _apiTimeout = Duration(seconds: 6);
  static const Duration _networkProbeTimeout = Duration(milliseconds: 700);

  final Map<String, DateTime> _gameStart = {};
  final Map<String, List<PlayerAction>> _pendingActions = {};
  final Map<String, DateTime> _lastActionTimestamp = {};

  String _profileKey(int slotId) => '$_profileKeyPrefix$slotId';
  String _historyKey(int slotId) => '$_historyKeyPrefix$slotId';

  Future<bool> _canReachBackendQuickly() {
    return NetworkProbeService.canReachBackend(timeout: _networkProbeTimeout);
  }

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

  Future<void> _saveProfile(PlayerProfile profile,
      {required int slotId}) async {
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
        records
            .add(PlayerGameRecord.fromJson(Map<String, dynamic>.from(decoded)));
      } catch (_) {
        // ignore malformed history item
      }
    }

    return records;
  }

  @override
  void startGame({
    required String gameId,
  }) {
    _gameStart[gameId] = DateTime.now();
    _pendingActions[gameId] = [];
  }

  @override
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
    final decisionTimeMs = lastActionTime != null
        ? now.difference(lastActionTime).inMilliseconds
        : null;
    _lastActionTimestamp[gameId] = now;

    final currentRank = _calculateCurrentRank(gameState, human);
    final isRiskyAction =
        _isRiskyAction(actionType, actionDetails, gameState, human);

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

  @override
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

  @override
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

    // Envoyer un fantôme si le joueur termine 1er ou 2e
    if (finalRank <= 2) {
      await _submitCloneCandidate(
        slotId: slotId,
        playerName: human.name,
        record: record,
      );
    }

    if (!usedSBMM) {
      _gameStart.remove(gameId);
      _pendingActions.remove(gameId);
      _lastActionTimestamp.remove(gameId);
      return profileBefore;
    }

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

  Future<void> _submitCloneCandidate({
    required int slotId,
    required String playerName,
    required PlayerGameRecord record,
  }) async {
    try {
      final isOnline = await _canReachBackendQuickly();
      if (!isOnline) return;

      final prefs = await SharedPreferences.getInstance();
      final clientId = await ClientIdService.ensureClientId();

      final cloneKey = '$_cloneIdKeyPrefix$slotId';
      final existingCloneId = prefs.getString(cloneKey);
      final payload = {
        'games': [_mapGhostGameRecord(record)]
      };

      if (existingCloneId != null && existingCloneId.isNotEmpty) {
        final uri = Uri.parse('$_botLearningUrl/clone/$existingCloneId');
        final response = await http
            .put(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(_apiTimeout);

        if (response.statusCode == 200) return;
      }

      final createBody = jsonEncode({
        'playerId': clientId,
        'playerName': playerName,
        'games': [_mapGhostGameRecord(record)],
      });

      final uri = Uri.parse('$_botLearningUrl/clone-player');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: createBody,
          )
          .timeout(_apiTimeout);

      if (response.statusCode != 200) return;
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) return;
      final cloneId = json['clonedBotId']?.toString();
      if (cloneId != null && cloneId.isNotEmpty) {
        await prefs.setString(cloneKey, cloneId);
      }
    } catch (_) {
      // best-effort
    }
  }

  Map<String, dynamic> _mapGhostGameRecord(PlayerGameRecord record) {
    return {
      'calledDutch': record.calledDutch,
      'scoreAtDutch': record.calledDutch ? record.finalScore : 0,
      'actions': record.actions.map(_mapGhostAction).toList(),
    };
  }

  Map<String, dynamic> _mapGhostAction(PlayerAction action) {
    String actionType = action.actionType;
    if (actionType == 'draw') {
      final source = action.actionDetails['source'];
      actionType = source == 'discard' ? 'draw_from_discard' : 'draw_from_deck';
    } else if (actionType == 'replace') {
      actionType = 'replace_card';
    } else if (actionType == 'power') {
      actionType = 'use_power';
    } else if (actionType == 'power_skip') {
      actionType = 'skip_power';
    }

    final gameState = Map<String, dynamic>.from(action.gameState);
    if (!gameState.containsKey('myScore')) {
      final score = gameState['humanEstimatedScore'] ?? gameState['humanScore'];
      if (score != null) {
        gameState['myScore'] = score;
      }
    }

    return {
      'actionType': actionType,
      'actionDetails': action.actionDetails,
      'decisionTime': action.decisionTimeMs,
      'gameState': gameState,
    };
  }

  Future<void> _appendHistory(PlayerGameRecord record,
      {required int slotId}) async {
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
      final isOnline = await _canReachBackendQuickly();
      if (!isOnline) return;

      final clientId = await ClientIdService.ensureClientId();

      final history = await getHistory(slotId: slotId);

      final payload = {
        'clientId': clientId,
        'slotId': slotId,
        'profile': profile.toJson(),
        'history': history
            .map((g) => {
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
                })
            .toList(),
      };

      await http
          .post(
            Uri.parse('$_serverUrl/upload'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(_apiTimeout);
    } catch (_) {
      // best-effort
    }
  }

  int _calculateCurrentRank(GameState gameState, Player human) {
    final players = List<Player>.from(gameState.players);
    players
        .sort((a, b) => a.getEstimatedScore().compareTo(b.getEstimatedScore()));
    return players.indexOf(human) + 1;
  }

  bool _isRiskyAction(String actionType, Map<String, dynamic> actionDetails,
      GameState gameState, Player human) {
    if (actionType == 'replace') {
      final cardIndex = actionDetails['cardIndex'] as int?;
      if (cardIndex != null &&
          cardIndex < human.hand.length &&
          cardIndex < human.knownCards.length) {
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
        (a.powerType == '9' ||
            a.powerType == '10' ||
            a.powerType == 'jack' ||
            a.powerType == 'joker'));

    final usedDefensive =
        defensivePowerActions.where((a) => a.actionType == 'power').length;
    final usedOffensive =
        offensivePowerActions.where((a) => a.actionType == 'power').length;
    final defensiveOpps = defensivePowerActions.length;
    final offensiveOpps = offensivePowerActions.length;

    final defensiveRateObserved =
        defensiveOpps == 0 ? powerDefensiveRate : usedDefensive / defensiveOpps;
    final offensiveRateObserved =
        offensiveOpps == 0 ? powerOffensiveRate : usedOffensive / offensiveOpps;

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

    final riskyActions =
        record.actions.where((a) => a.isRiskyAction == true).length;
    final totalActions = record.actions.length;
    final riskyRateObserved =
        totalActions == 0 ? 0.5 : riskyActions / totalActions;

    final targetingCounts = <String, int>{'leader': 0, 'weak': 0, 'random': 0};
    for (final action
        in record.actions.where((a) => a.targetStrategy != null)) {
      final strat = action.targetStrategy!;
      targetingCounts[strat] = (targetingCounts[strat] ?? 0) + 1;
    }
    final dominantStrategy =
        targetingCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;

    final winningActions =
        record.actions.where((a) => (a.currentRank ?? 99) <= 2);
    final losingActions =
        record.actions.where((a) => (a.currentRank ?? 1) >= 3);
    final winningRiskyRate = winningActions.isEmpty
        ? 0.5
        : winningActions.where((a) => a.isRiskyAction == true).length /
            winningActions.length;
    final losingRiskyRate = losingActions.isEmpty
        ? 0.5
        : losingActions.where((a) => a.isRiskyAction == true).length /
            losingActions.length;
    final adaptabilityObserved = (winningRiskyRate - losingRiskyRate).abs();

    final decisionTimes = record.actions
        .where((a) => a.decisionTimeMs != null)
        .map((a) => a.decisionTimeMs!.toDouble())
        .toList();
    final avgDecisionTime = decisionTimes.isEmpty
        ? decisionSpeed
        : decisionTimes.reduce((a, b) => a + b) / decisionTimes.length;

    final seenCards = <String>{};
    int memoryTests = 0;
    int memoryCorrect = 0;
    for (final action in record.actions) {
      if (action.actionType == 'power' && action.powerType == '7') {
        final cardSeen = action.result['cardSeen'];
        if (cardSeen != null) {
          seenCards.add(
              '${action.actionDetails['targetPlayerId']}_${action.actionDetails['cardIndex']}');
        }
      }
      if (action.actionType == 'power' && action.powerType == '9') {
        memoryTests++;
        if (action.result['wasOptimal'] == true) memoryCorrect++;
      }
    }
    final memoryRetentionObserved =
        memoryTests == 0 ? memoryRetention : memoryCorrect / memoryTests;

    double newDutchQuality = dutchQuality;
    if (record.calledDutch && record.actions.isNotEmpty) {
      final dutchAction =
          record.actions.where((a) => a.actionType == 'dutch').lastOrNull;
      final estimatedScore =
          (dutchAction ?? record.actions.last).gameState['estimatedScore'] ??
              record.finalScore;
      final error = (estimatedScore - record.finalScore).abs() / 30.0;
      newDutchQuality = dutchQuality * 0.9 + (1.0 - error) * 0.1;
    }

    final lr = 0.08;
    double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

    double newAgg = aggressiveness + lr * (riskyRateObserved - aggressiveness);
    double newCaution = caution + lr * ((1.0 - riskyRateObserved) - caution);

    double newPowerDefensive =
        powerDefensiveRate + lr * (defensiveRateObserved - powerDefensiveRate);
    double newPowerOffensive =
        powerOffensiveRate + lr * (offensiveRateObserved - powerOffensiveRate);
    if (badPower > 0) {
      newPowerDefensive -= lr * 0.2 * badPower;
      newPowerOffensive -= lr * 0.2 * badPower;
    }

    double newMemory =
        memoryAccuracy + lr * (matchAccuracyObserved - memoryAccuracy);
    double newMemoryRetention =
        memoryRetention + lr * (memoryRetentionObserved - memoryRetention);

    double newAdaptability =
        adaptability + lr * (adaptabilityObserved - adaptability);
    double newDecisionSpeed = decisionSpeed * 0.9 + avgDecisionTime * 0.1;

    double newAggWinning =
        aggressivenessWinning + lr * (winningRiskyRate - aggressivenessWinning);
    double newAggLosing =
        aggressivenessLosing + lr * (losingRiskyRate - aggressivenessLosing);
    double newCautionWinning =
        cautionWinning + lr * ((1.0 - winningRiskyRate) - cautionWinning);
    double newCautionLosing =
        cautionLosing + lr * ((1.0 - losingRiskyRate) - cautionLosing);

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

    // Calcul du MMR adaptatif multi-facteurs
    final int newMMR = _calculateMMRChange(
      currentMMR: profile.mmr,
      gamesAnalyzed: profile.gamesAnalyzed,
      finalRank: record.finalRank,
      finalScore: record.finalScore,
      numberOfPlayers: record.numberOfPlayers,
      calledDutch: record.calledDutch,
      wonDutch: record.wonDutch,
      matchAccuracyObserved: matchAccuracyObserved,
      defensiveRateObserved: defensiveRateObserved,
      offensiveRateObserved: offensiveRateObserved,
      riskyRateObserved: riskyRateObserved,
      memoryRetentionObserved: memoryRetentionObserved,
      adaptabilityObserved: adaptabilityObserved,
      avgDecisionTime: avgDecisionTime,
      params: params,
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

  /// Algorithme adaptatif multi-facteurs pour le calcul du MMR.
  ///
  /// Architecture :
  ///   MMR_new = MMR_old + K * (placementScore + performanceBonus) * streakMultiplier + anchorPull
  ///
  /// K (facteur dynamique) varie selon :
  ///   - Le nombre de parties jouees (plus eleve pour les nouveaux)
  ///   - L'ecart entre performance et MMR actuel (auto-correction)
  ///   - Le nombre de joueurs dans la partie
  ///
  /// Le placementScore est base sur le classement normalise [-1, +1]
  /// Le performanceBonus est base sur la qualite du jeu [-0.15, +0.30]
  /// Le streakMultiplier accelere si le joueur est clairement mal place [0.85, 1.5]
  int _calculateMMRChange({
    required int currentMMR,
    required int gamesAnalyzed,
    required int finalRank,
    required int finalScore,
    required int numberOfPlayers,
    required bool calledDutch,
    required bool wonDutch,
    required double matchAccuracyObserved,
    required double defensiveRateObserved,
    required double offensiveRateObserved,
    required double riskyRateObserved,
    required double memoryRetentionObserved,
    required double adaptabilityObserved,
    required double avgDecisionTime,
    required Map<String, dynamic> params,
  }) {
    // --- Helpers ---
    double getNum(String key, double fallback) {
      final v = params[key];
      if (v is num) return v.toDouble();
      return fallback;
    }

    List<int> getIntList(String key) {
      final v = params[key];
      if (v is List) return v.whereType<int>().toList();
      return <int>[];
    }

    // ============================================================
    // STEP 1 : Mise a jour des streaks et de l'historique
    // ============================================================
    final bool isWin = finalRank == 1;
    final bool isBottomHalf = finalRank > (numberOfPlayers / 2).ceil();

    int winStreak = (params['winStreak'] as int?) ?? 0;
    int loseStreak = (params['loseStreak'] as int?) ?? 0;

    if (isWin) {
      winStreak += 1;
      loseStreak = 0;
    } else if (isBottomHalf) {
      loseStreak += 1;
      winStreak = 0;
    } else {
      // Milieu de tableau : on reset les deux
      winStreak = 0;
      loseStreak = 0;
    }
    params['winStreak'] = winStreak;
    params['loseStreak'] = loseStreak;

    // Derniers resultats (10 max)
    List<int> recentResults = getIntList('recentResults');
    recentResults.insert(0, finalRank);
    if (recentResults.length > 10) recentResults = recentResults.sublist(0, 10);
    params['recentResults'] = recentResults;

    List<int> recentScores = getIntList('recentScores');
    recentScores.insert(0, finalScore);
    if (recentScores.length > 10) recentScores = recentScores.sublist(0, 10);
    params['recentScores'] = recentScores;

    // ============================================================
    // STEP 2 : Score de placement [-1.0, +1.0] (zero-sum)
    // ============================================================
    // 1er parmi N => +1.0, dernier => -1.0
    final double placementScore =
        1.0 - 2.0 * (finalRank - 1) / (numberOfPlayers - 1).clamp(1, 5);

    // ============================================================
    // STEP 3 : Bonus de marge de score [-0.15, +0.15]
    // ============================================================
    double scoreMarginBonus = 0.0;
    if (isWin) {
      // Score bas en gagnant = domination
      scoreMarginBonus = 0.15 * (1.0 - (finalScore / 15.0)).clamp(-0.33, 1.0);
    } else if (finalRank == numberOfPlayers) {
      // Dernier avec gros score = penalite supplementaire
      scoreMarginBonus = -0.10 * ((finalScore - 20) / 30.0).clamp(0.0, 1.0);
    }

    // ============================================================
    // STEP 4 : Qualite de la performance [0.0, 1.0]
    // ============================================================
    double performanceQuality = 0.0;
    double weightSum = 0.0;

    // Precision memoire (poids 2.0)
    performanceQuality += matchAccuracyObserved.clamp(0.0, 1.0) * 2.0;
    weightSum += 2.0;

    // Retention memoire (poids 1.5)
    performanceQuality += memoryRetentionObserved.clamp(0.0, 1.0) * 1.5;
    weightSum += 1.5;

    // Intelligence d'utilisation des pouvoirs (poids 1.5)
    final powerUsageQuality =
        ((defensiveRateObserved + offensiveRateObserved) / 2.0).clamp(0.0, 1.0);
    performanceQuality += powerUsageQuality * 1.5;
    weightSum += 1.5;

    // Succes Dutch (poids 2.0, seulement si appele)
    if (calledDutch) {
      performanceQuality += (wonDutch ? 1.0 : 0.0) * 2.0;
      weightSum += 2.0;
    }

    // Vitesse de decision (poids 1.0) - 500ms=rapide(1.0), 5000ms=lent(0.0)
    final speedScore = (1.0 - (avgDecisionTime - 500) / 4500).clamp(0.0, 1.0);
    performanceQuality += speedScore * 1.0;
    weightSum += 1.0;

    // Adaptabilite positionnelle (poids 1.0)
    performanceQuality += adaptabilityObserved.clamp(0.0, 1.0) * 1.0;
    weightSum += 1.0;

    // Normaliser [0, 1]
    performanceQuality = weightSum > 0 ? performanceQuality / weightSum : 0.5;

    // Accumulateur EMA (alpha = 0.15)
    final double prevPerfAcc = getNum('performanceAccumulator', 0.5);
    params['performanceAccumulator'] =
        prevPerfAcc * 0.85 + performanceQuality * 0.15;

    // ============================================================
    // STEP 5 : Bonus de performance [-0.15, +0.30]
    // ============================================================
    final double perfDeviation = performanceQuality - 0.5;
    double performanceBonus;
    if (placementScore > 0) {
      // Gagne : bonne perf amplifie, mauvaise amortit
      performanceBonus = perfDeviation * 0.4;
    } else {
      // Perdu : bonne perf adoucit, mauvaise amplifie
      performanceBonus = perfDeviation * 0.2;
    }
    performanceBonus += scoreMarginBonus;
    performanceBonus = performanceBonus.clamp(-0.15, 0.30);

    // ============================================================
    // STEP 6 : K-factor dynamique (type Elo)
    // ============================================================
    // 6a. Newcomer : K eleve pour les nouveaux, decroit avec l'experience
    //     K_base = 25 + 35 * exp(-parties/15) → ~60 au debut, ~25 a 50+ parties
    final int totalGames = gamesAnalyzed + 1;
    final double kNewcomer = 25.0 + 35.0 * exp(-totalGames / 15.0);

    // 6b. Mismatch : boost si le joueur est clairement mal place
    double recentWinRate = 0.5;
    if (recentResults.length >= 3) {
      final topHalfCount =
          recentResults.where((r) => r <= (numberOfPlayers / 2).ceil()).length;
      recentWinRate = topHalfCount / recentResults.length;
    }
    final double mismatchDeviation = (recentWinRate - 0.5).abs();
    final double kMismatch = 1.0 + mismatchDeviation * 1.2;

    // 6c. Nombre de joueurs
    final double kPlayerCount = 1.0 + (numberOfPlayers - 2) * 0.08;

    final double kFactor = kNewcomer * kMismatch * kPlayerCount;

    // ============================================================
    // STEP 7 : Multiplicateur de streak [0.85, 1.5]
    // ============================================================
    double streakMultiplier = 1.0;
    if (winStreak >= 2) {
      streakMultiplier = (1.0 + (winStreak - 1) * 0.1).clamp(1.0, 1.5);
    } else if (loseStreak >= 2) {
      streakMultiplier = (1.0 + (loseStreak - 1) * 0.1).clamp(1.0, 1.4);
    } else if (winStreak == 0 && loseStreak == 0) {
      // Milieu de tableau : on amortit
      streakMultiplier = 0.85;
    }

    // ============================================================
    // STEP 8 : Anchor pull (auto-correction aux extremes)
    // ============================================================
    double anchorPull = 0.0;
    if (currentMMR < 200) {
      anchorPull = (200 - currentMMR) / 200.0 * 5.0;
    } else if (currentMMR > 1300) {
      anchorPull = (-(currentMMR - 1300) / 200.0 * 5.0).clamp(-8.0, 0.0);
    }

    // ============================================================
    // STEP 9 : Calcul final
    // ============================================================
    final double rawScore = placementScore + performanceBonus;
    final double mmrDelta = kFactor * rawScore * streakMultiplier + anchorPull;
    final int newMMR = (currentMMR + mmrDelta.round()).clamp(0, 9999);

    // ============================================================
    // STEP 10 : Metriques derivees
    // ============================================================
    // Dominance : EMA de la qualite de victoire
    double dominanceRaw = 0.0;
    if (isWin) {
      dominanceRaw = (1.0 - finalScore / 30.0).clamp(0.0, 1.0);
    }
    final double prevDominance = getNum('dominanceScore', 0.0);
    params['dominanceScore'] = prevDominance * 0.85 + dominanceRaw * 0.15;

    // Consistance : inverse de la variance des rangs recents
    if (recentResults.length >= 3) {
      final mean = recentResults.reduce((a, b) => a + b) / recentResults.length;
      final variance = recentResults
              .map((r) => (r - mean) * (r - mean))
              .reduce((a, b) => a + b) /
          recentResults.length;
      params['consistencyScore'] = (1.0 - variance / 4.0).clamp(0.0, 1.0);
    }

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
