import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../../models/bot_learning_data.dart';
import '../../models/game_state.dart';
import '../../models/player.dart';
import '../../core/interfaces/i_learning_service.dart';
import '../network/network_probe_service.dart';

/// Service pour enregistrer et envoyer les données d'apprentissage des bots
class BotLearningService implements ILearningService {
  static const String _serverUrl = 'https://dutch-game.me/api/bot-learning';
  static const Duration _apiTimeout = Duration(seconds: 2);
  static const Duration _networkProbeTimeout = Duration(milliseconds: 700);

  // Enregistrement de la partie en cours
  final Map<String, BotGameRecord> _activeGames = {};
  final Map<String, List<BotAction>> _pendingActions = {};
  final Map<String, DateTime> _actionTimestamps = {};
  final Map<String, List<Map<String, dynamic>>> _initialDecks = {};
  final Map<String, int> _turnCounters = {};
  final Map<String, List<int>> _discardsPerRound = {};
  final Map<String, List<Map<String, dynamic>>> _triageDecisions = {};

  static void _log(String message) {
    // Keep trainer-compatible logging without Flutter dependency.
    // ignore: avoid_print
    print(message);
  }

  Future<bool> _canReachBackendQuickly() {
    return NetworkProbeService.canReachBackend(timeout: _networkProbeTimeout);
  }

  /// Démarre l'enregistrement d'une partie pour un bot
  @override
  void startGameRecording({
    required String gameId,
    required Player player,
    required GameState gameState,
    required bool usedSBMM,
  }) {
    final bot = player;
    if (bot.isHuman) return;

    final initialHandScore = _calculateHandScore(bot);
    final initialHandRank = _calculateInitialHandRank(
      gameState: gameState,
      botId: bot.id,
    );
    final initialHandRankFromWorst =
        gameState.players.length - initialHandRank + 1;

    // FIX: Normaliser behavior et skillLevel pour matcher le format serveur
    final behavior = bot.botBehavior.toString().split('.').last;
    final skill = bot.botSkillLevel.toString().split('.').last;
    final botId = '${behavior}_$skill';

    _activeGames[bot.id] = BotGameRecord(
      gameId: gameId,
      botId: botId,
      botName: bot.name,
      botBehavior: behavior,
      botSkillLevel: skill,
      startTime: DateTime.now(),
      numberOfPlayers: gameState.players.length,
      gameMode: gameState.gameMode.toString().split('.').last,
      usedSBMM: usedSBMM,
      actions: [],
      initialHandSize: bot.hand.length,
      initialHandScore: initialHandScore,
      initialHandRank: initialHandRank,
      initialHandRankFromWorst: initialHandRankFromWorst,
      finalScore: 0,
      finalRank: 0,
      calledDutch: false,
      wonDutch: false,
      cardsAtDutch: 0,
      scoreAtDutch: 0,
      totalTurns: 0,
      avgDecisionTime: 0,
      powerUsesCount: 0,
      goodDecisions: 0,
      badDecisions: 0,
      opponents: _getOpponentsInfo(gameState, bot.id),
    );

    _pendingActions[bot.id] = [];
    _initialDecks[bot.id] = _captureDeck(gameState);
    _turnCounters[bot.id] = 0;
    _discardsPerRound[bot.id] = [];
    _triageDecisions[bot.id] = [];

    _log('🤖 Démarrage enregistrement pour bot ${bot.name} (ID: $botId)');
  }

  /// Enregistre une action d'un bot
  void recordAction({
    required String botPlayerId,
    required String actionType,
    required int turnNumber,
    required GameState gameState,
    required Map<String, dynamic> actionDetails,
  }) {
    if (!_activeGames.containsKey(botPlayerId)) return;

    _actionTimestamps[botPlayerId] = DateTime.now();

    final action = BotAction(
      actionType: actionType,
      turnNumber: turnNumber,
      timestamp: DateTime.now(),
      gameState: _captureGameState(gameState, botPlayerId),
      actionDetails: actionDetails,
      result: {}, // Sera rempli après l'action
    );

    _pendingActions[botPlayerId]?.add(action);
  }

  /// Met à jour le résultat de la dernière action
  void updateLastActionResult({
    required String botPlayerId,
    required Map<String, dynamic> result,
  }) {
    if (!_pendingActions.containsKey(botPlayerId)) return;

    final actions = _pendingActions[botPlayerId]!;
    if (actions.isEmpty) return;

    final lastAction = actions.last;
    final updatedAction = BotAction(
      actionType: lastAction.actionType,
      turnNumber: lastAction.turnNumber,
      timestamp: lastAction.timestamp,
      gameState: lastAction.gameState,
      actionDetails: lastAction.actionDetails,
      result: result,
    );

    actions[actions.length - 1] = updatedAction;
  }

  /// Termine l'enregistrement d'une partie et envoie les données au serveur
  @override
  Future<void> endGameRecording({
    required String botPlayerId,
    required int finalScore,
    required int finalRank,
    required bool calledDutch,
    required bool wonDutch,
    required int cardsAtDutch,
    required int scoreAtDutch,
    required int humanFinalScore,
    required int humanFinalHandSize,
    required int botFinalHandSize,
  }) async {
    if (!_activeGames.containsKey(botPlayerId)) return;

    final record = _activeGames[botPlayerId]!;
    final actions = _pendingActions[botPlayerId] ?? [];

    // Calculer les métriques
    final decisionTimes = <int>[];
    DateTime? lastTimestamp;
    for (var action in actions) {
      if (lastTimestamp != null) {
        decisionTimes
            .add(action.timestamp.difference(lastTimestamp).inMilliseconds);
      }
      lastTimestamp = action.timestamp;
    }

    final avgDecisionTime = decisionTimes.isEmpty
        ? 0.0
        : decisionTimes.reduce((a, b) => a + b) / decisionTimes.length;

    final powerUsesCount = actions.where((a) => a.actionType == 'power').length;

    // Analyser les bonnes/mauvaises décisions
    int goodDecisions = 0;
    int badDecisions = 0;
    for (var action in actions) {
      if (action.result['scoreChange'] != null) {
        if (action.result['scoreChange'] < 0) {
          goodDecisions++;
        } else if (action.result['scoreChange'] > 0) {
          badDecisions++;
        }
      }
    }

    double sigmoid(double x) => 1.0 / (1.0 + exp(-x));

    // Heuristique simple (fin de partie): avantage score + avantage "moins de cartes"
    final scoreAdv = (humanFinalScore - finalScore).toDouble();
    final cardsAdv = (humanFinalHandSize - botFinalHandSize).toDouble();
    final raw = 0.35 * scoreAdv + 0.25 * cardsAdv;
    final pBeatHuman = sigmoid(raw).clamp(0.01, 0.99);

    final completedRecord = BotGameRecord(
      gameId: record.gameId,
      botId: record.botId,
      botName: record.botName,
      botBehavior: record.botBehavior,
      botSkillLevel: record.botSkillLevel,
      startTime: record.startTime,
      endTime: DateTime.now(),
      numberOfPlayers: record.numberOfPlayers,
      gameMode: record.gameMode,
      usedSBMM: record.usedSBMM,
      humanFinalScore: humanFinalScore,
      humanFinalHandSize: humanFinalHandSize,
      botFinalHandSize: botFinalHandSize,
      pBeatHuman: pBeatHuman,
      initialDeck: _initialDecks[botPlayerId],
      turnsBeforeDutch: calledDutch ? _turnCounters[botPlayerId] : null,
      discardsPerRound: _discardsPerRound[botPlayerId],
      triageDecisions: _triageDecisions[botPlayerId],
      actions: actions,
      initialHandSize: record.initialHandSize,
      initialHandScore: record.initialHandScore,
      initialHandRank: record.initialHandRank,
      initialHandRankFromWorst: record.initialHandRankFromWorst,
      finalScore: finalScore,
      finalRank: finalRank,
      calledDutch: calledDutch,
      wonDutch: wonDutch,
      cardsAtDutch: cardsAtDutch,
      scoreAtDutch: scoreAtDutch,
      totalTurns: actions.length,
      avgDecisionTime: avgDecisionTime,
      powerUsesCount: powerUsesCount,
      goodDecisions: goodDecisions,
      badDecisions: badDecisions,
      opponents: record.opponents,
    );

    // Envoyer au serveur
    await _sendToServer(completedRecord);

    // Nettoyer
    _activeGames.remove(botPlayerId);
    _pendingActions.remove(botPlayerId);
    _actionTimestamps.remove(botPlayerId);
    _initialDecks.remove(botPlayerId);
    _turnCounters.remove(botPlayerId);
    _discardsPerRound.remove(botPlayerId);
    _triageDecisions.remove(botPlayerId);

    _log(
        '🤖 Fin enregistrement pour bot ${record.botName} - Score: $finalScore, Rang: $finalRank');
  }

  /// Capture l'état du jeu pour analyse
  Map<String, dynamic> _captureGameState(
      GameState gameState, String botPlayerId) {
    final bot = gameState.players.firstWhere((p) => p.id == botPlayerId);

    return {
      'phase': gameState.phase.toString().split('.').last,
      'currentPlayerIndex': gameState.currentPlayerIndex,
      'deckSize': gameState.deck.length,
      'discardPileSize': gameState.discardPile.length,
      'topDiscardCard': gameState.topDiscardCard?.toJson(),
      'botHandSize': bot.hand.length,
      'botKnownCards': bot.knownCards.where((k) => k).length,
      'botEstimatedScore': bot.getEstimatedScore(),
      'opponentsHandSizes': gameState.players
          .where((p) => p.id != botPlayerId)
          .map((p) => p.hand.length)
          .toList(),
    };
  }

  int _calculateHandScore(Player player) {
    return player.hand.fold<int>(0, (sum, card) => sum + card.points);
  }

  int _calculateInitialHandRank({
    required GameState gameState,
    required String botId,
  }) {
    final scored = gameState.players
        .map((p) => (id: p.id, score: _calculateHandScore(p)))
        .toList()
      ..sort((a, b) {
        final byScore = a.score.compareTo(b.score);
        if (byScore != 0) return byScore;
        return a.id.compareTo(b.id);
      });

    final index = scored.indexWhere((entry) => entry.id == botId);
    return index >= 0 ? index + 1 : gameState.players.length;
  }

  /// Récupère les informations des adversaires
  List<Map<String, dynamic>> _getOpponentsInfo(
      GameState gameState, String botPlayerId) {
    return gameState.players
        .where((p) => p.id != botPlayerId)
        .map((p) => {
              'id': p.id,
              'name': p.name,
              'isHuman': p.isHuman,
              'behavior': p.botBehavior?.toString().split('.').last,
              'skillLevel': p.botSkillLevel?.toString().split('.').last,
            })
        .toList();
  }

  /// Capture le deck initial pour analyse
  List<Map<String, dynamic>> _captureDeck(GameState gameState) {
    final allCards = <Map<String, dynamic>>[];
    for (final player in gameState.players) {
      for (final card in player.hand) {
        allCards.add({
          'suit': card.suit,
          'value': card.value,
          'points': card.points,
          'playerId': player.id,
        });
      }
    }
    for (final card in gameState.deck) {
      allCards.add({
        'suit': card.suit,
        'value': card.value,
        'points': card.points,
        'location': 'deck',
      });
    }
    return allCards;
  }

  /// Enregistre une décision de triage (garder vs défausser)
  void recordTriageDecision({
    required String botPlayerId,
    required Map<String, dynamic> decision,
  }) {
    final decisions = _triageDecisions[botPlayerId];
    if (decisions != null) {
      decisions.add(decision);
    }
  }

  /// Incrémente le compteur de tours
  @override
  void incrementTurn(String botPlayerId) {
    final counter = _turnCounters[botPlayerId];
    if (counter != null) {
      _turnCounters[botPlayerId] = counter + 1;
    }
  }

  /// Enregistre une défausse pour le round actuel
  @override
  void recordDiscard(String botPlayerId) {
    final discards = _discardsPerRound[botPlayerId];
    if (discards != null) {
      if (discards.isEmpty) {
        discards.add(1);
      } else {
        discards[discards.length - 1]++;
      }
    }
  }

  /// Démarre un nouveau round
  @override
  void startNewRound(String botPlayerId) {
    final discards = _discardsPerRound[botPlayerId];
    if (discards != null) {
      discards.add(0);
    }
  }

  /// Envoie les données au serveur
  Future<void> _sendToServer(BotGameRecord record) async {
    try {
      final isOnline = await _canReachBackendQuickly();
      if (!isOnline) {
        _log('⚠️ Offline détecté, envoi bot ignoré');
        return;
      }

      final response = await http
          .post(
            Uri.parse('$_serverUrl/record'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(record.toJson()),
          )
          .timeout(_apiTimeout);

      if (response.statusCode == 200) {
        _log('✅ Données bot envoyées au serveur');
      } else {
        _log('❌ Erreur envoi données bot: ${response.statusCode}');
      }
    } catch (e) {
      _log('❌ Exception envoi données bot: $e');
    }
  }

  /// Récupère les meilleurs bots depuis le serveur
  Future<List<BotProfile>> fetchTopBots({
    String? behavior,
    String? skillLevel,
    int limit = 10,
  }) async {
    try {
      final isOnline = await _canReachBackendQuickly();
      if (!isOnline) return [];

      final queryParams = <String, String>{
        'limit': limit.toString(),
        if (behavior != null) 'behavior': behavior,
        if (skillLevel != null) 'skillLevel': skillLevel,
      };

      final uri = Uri.parse('$_serverUrl/top-bots')
          .replace(queryParameters: queryParams);
      final response = await http.get(uri).timeout(_apiTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => BotProfile.fromJson(json)).toList();
      }
    } catch (e) {
      _log('❌ Erreur récupération top bots: $e');
    }

    return [];
  }

  /// Récupère les paramètres appris d'un bot spécifique
  Future<Map<String, dynamic>?> fetchBotParameters({
    required String behavior,
    required String skillLevel,
  }) async {
    try {
      final isOnline = await _canReachBackendQuickly();
      if (!isOnline) return null;

      final uri = Uri.parse('$_serverUrl/parameters/$behavior/$skillLevel');
      final response = await http.get(uri).timeout(_apiTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      _log('❌ Erreur récupération paramètres bot: $e');
    }

    return null;
  }
}
