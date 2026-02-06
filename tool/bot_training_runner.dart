import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/services/game/game_logic.dart';
import 'package:dutch_game/services/game/bot/bot_card_strategy.dart';
import 'package:dutch_game/services/game/bot/bot_config.dart';
import 'package:dutch_game/services/game/bot/bot_dutch_strategy.dart';
import 'package:dutch_game/services/game/bot/bot_memory_manager.dart';
import 'package:dutch_game/services/game/bot/bot_personality.dart';
import 'package:dutch_game/services/learning/bot_learning_service.dart';
import 'package:http/http.dart' as http;

class TrainingConfig {
  final String serverBaseUrl;
  final int startHour;
  final int endHour;
  final int matchesPerBatch;
  final int sleepBetweenMatchesMs;
  final int maxTurnsPerMatch;
  final bool balancedOnly;

  const TrainingConfig({
    required this.serverBaseUrl,
    required this.startHour,
    required this.endHour,
    required this.matchesPerBatch,
    required this.sleepBetweenMatchesMs,
    required this.maxTurnsPerMatch,
    required this.balancedOnly,
  });

  factory TrainingConfig.fromEnv() {
    final env = Platform.environment;
    return TrainingConfig(
      serverBaseUrl: env['BOT_TRAIN_SERVER'] ?? 'https://dutch-game.me',
      startHour: int.tryParse(env['BOT_TRAIN_START_HOUR'] ?? '') ?? 20,
      endHour: int.tryParse(env['BOT_TRAIN_END_HOUR'] ?? '') ?? 12,
      matchesPerBatch: int.tryParse(env['BOT_TRAIN_BATCH'] ?? '') ?? 12,
      sleepBetweenMatchesMs: int.tryParse(env['BOT_TRAIN_SLEEP_MS'] ?? '') ?? 200,
      maxTurnsPerMatch: int.tryParse(env['BOT_TRAIN_MAX_TURNS'] ?? '') ?? 800,
      balancedOnly: (env['BOT_TRAIN_BALANCED_ONLY'] ?? 'false').toLowerCase() == 'true',
    );
  }
}

class GhostClone {
  final String cloneId;
  final String playerName;
  final Map<String, dynamic> pattern;

  GhostClone({
    required this.cloneId,
    required this.playerName,
    required this.pattern,
  });

  Map<String, double> toAiParams() {
    double numValue(String key, double fallback) {
      final v = pattern[key];
      if (v is num) return v.toDouble();
      return fallback;
    }

    double clamp01(double v) => v.clamp(0.0, 1.0);

    double aggressiveness = clamp01(numValue('aggressivenessScore', 0.5));
    double riskTolerance = clamp01(numValue('riskTakingScore', 0.5));
    double powerUsage = clamp01(numValue('powerUsageFrequency', 0.5));
    double decisionSpeed = numValue('avgDecisionTime', 2000.0).clamp(500.0, 10000.0);
    double dutchThreshold = numValue('dutchThresholdPattern', 15.0).clamp(5.0, 30.0);

    double caution = clamp01(1.0 - aggressiveness);
    final playStyle = pattern['playStyle']?.toString() ?? 'balanced';
    if (playStyle == 'defensive') {
      caution = caution.clamp(0.6, 1.0);
      aggressiveness = aggressiveness.clamp(0.0, 0.5);
    } else if (playStyle == 'aggressive') {
      aggressiveness = aggressiveness.clamp(0.6, 1.0);
      caution = caution.clamp(0.0, 0.4);
    } else if (playStyle == 'opportunistic') {
      riskTolerance = riskTolerance.clamp(0.6, 1.0);
    }

    return {
      'aggressiveness': aggressiveness,
      'caution': caution,
      'riskTolerance': riskTolerance,
      'powerUsageRate': powerUsage,
      'decisionSpeed': decisionSpeed,
      'dutchThreshold': dutchThreshold,
    };
  }
}

class TrainingMatchResult {
  final bool botWon;
  final int botCount;
  final int ghostRank;

  TrainingMatchResult({
    required this.botWon,
    required this.botCount,
    required this.ghostRank,
  });
}

Future<void> main(List<String> args) async {
  final config = TrainingConfig.fromEnv();
  stdout.writeln('[trainer] Server: ${config.serverBaseUrl}');
  stdout.writeln('[trainer] Window: ${config.startHour}:00 → ${config.endHour}:00');
  stdout.writeln('[trainer] Batch: ${config.matchesPerBatch} matches');

  final trainer = BotTrainer(config: config);
  await trainer.run();
}

class BotTrainer {
  BotTrainer({required this.config});

  final TrainingConfig config;
  final Random _random = Random();

  Future<void> _playBotTurnHeadless(GameState gameState) async {
    final bot = gameState.currentPlayer;
    if (bot.isHuman) return;

    final difficulty = BotConfig.getDifficulty(bot, null);
    final phase = BotConfig.getBotPhase(bot, gameState);
    final personality = BotPersonality.fromBot(bot);

    BotMemoryManager.applyMemoryDecay(
      bot,
      difficulty,
      personality: personality,
    );

    if (BotDutchStrategy.shouldCallDutch(
      gameState,
      bot,
      difficulty,
      phase,
      personality: personality,
    )) {
      GameLogic.callDutch(gameState);
      return;
    }

    GameLogic.drawCard(gameState);
    if (gameState.drawnCard == null) return;

    await BotCardStrategy.decideCardAction(
      gameState,
      bot,
      difficulty,
      phase,
      personality: personality,
    );

    if (gameState.isWaitingForSpecialPower) {
      // Trainer mode is headless: skip UI-dependent power handling.
      gameState.isWaitingForSpecialPower = false;
      gameState.specialCardToActivate = null;
    }
  }

  Future<void> _tryReactionMatchHeadless(
    GameState gameState,
    Player bot,
  ) async {
    if (bot.isHuman) return;
    final difficulty = BotConfig.getDifficulty(bot, null);
    final phase = BotConfig.getBotPhase(bot, gameState);
    final personality = BotPersonality.fromBot(bot);

    await BotCardStrategy.tryReactionMatch(
      gameState,
      bot,
      difficulty,
      phase,
      personality: personality,
    );
  }

  bool _withinWindow(DateTime now) {
    if (config.startHour == config.endHour) return true;
    if (config.startHour < config.endHour) {
      return now.hour >= config.startHour && now.hour < config.endHour;
    }
    return now.hour >= config.startHour || now.hour < config.endHour;
  }

  Duration _timeUntilNextWindow(DateTime now) {
    if (_withinWindow(now)) return Duration.zero;
    DateTime nextStart;
    if (config.startHour < config.endHour) {
      nextStart = DateTime(now.year, now.month, now.day, config.startHour);
      if (nextStart.isBefore(now)) {
        nextStart = nextStart.add(const Duration(days: 1));
      }
    } else {
      nextStart = DateTime(now.year, now.month, now.day, config.startHour);
      if (nextStart.isBefore(now)) {
        nextStart = nextStart.add(const Duration(days: 1));
      }
    }
    return nextStart.difference(now);
  }

  Future<void> run() async {
    while (true) {
      final now = DateTime.now();
      if (!_withinWindow(now)) {
        final wait = _timeUntilNextWindow(now);
        stdout.writeln('[trainer] Outside window. Sleeping for ${wait.inMinutes} min');
        await Future.delayed(wait);
        continue;
      }

      final clones = await _fetchClones();
      if (clones.isEmpty) {
        stdout.writeln('[trainer] No clones available. Retry in 5 min.');
        await Future.delayed(const Duration(minutes: 5));
        continue;
      }

      final botLearningService = BotLearningService();
      int botWins = 0;

      for (int i = 0; i < config.matchesPerBatch; i++) {
        final ghost = clones[_random.nextInt(clones.length)];
        final result = await _runMatch(botLearningService, ghost);
        if (result.botWon) botWins++;

        if (config.sleepBetweenMatchesMs > 0) {
          await Future.delayed(Duration(milliseconds: config.sleepBetweenMatchesMs));
        }
      }

      final winRate = botWins / max(1, config.matchesPerBatch);
      await _sendTrainingSummary(
        totalMatches: config.matchesPerBatch,
        botWinRate: winRate,
      );
    }
  }

  Future<List<GhostClone>> _fetchClones() async {
    try {
      final uri = Uri.parse('${config.serverBaseUrl}/api/bot-learning/clones');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];

      final decoded = jsonDecode(response.body);
      if (decoded is! List) return [];

      return decoded
          .whereType<Map<String, dynamic>>()
          .map((json) => GhostClone(
                cloneId: json['clonedBotId']?.toString() ?? '',
                playerName: json['playerName']?.toString() ?? 'Ghost',
                pattern: Map<String, dynamic>.from(json['pattern'] ?? const {}),
              ))
          .where((c) => c.cloneId.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<TrainingMatchResult> _runMatch(
    BotLearningService botLearningService,
    GhostClone ghost,
  ) async {
    final behaviorPool = config.balancedOnly
        ? [BotBehavior.balanced]
        : [BotBehavior.fast, BotBehavior.aggressive, BotBehavior.balanced];

    final skillLevel = _randomSkillLevel();
    final ghostPlayer = Player(
      id: 'ghost_${ghost.cloneId}',
      name: 'Ghost ${ghost.playerName}',
      isHuman: false,
      botBehavior: BotBehavior.balanced,
      botSkillLevel: skillLevel,
      aiParameters: ghost.toAiParams(),
      position: 0,
    );

    final bots = <Player>[];
    for (int i = 0; i < behaviorPool.length; i++) {
      final behavior = behaviorPool[i];
      final aiParams = await _fetchBotParams(
        botLearningService,
        behavior: behavior,
        skillLevel: skillLevel,
      );
      bots.add(Player(
        id: 'bot_${i}_${DateTime.now().millisecondsSinceEpoch}',
        name: '${behavior.name}_${skillLevel.name}',
        isHuman: false,
        botBehavior: behavior,
        botSkillLevel: skillLevel,
        aiParameters: aiParams,
        position: i + 1,
      ));
    }

    final players = [ghostPlayer, ...bots];
    final gameState = GameLogic.initializeGame(
      players: players,
      gameMode: GameMode.quick,
      difficulty: Difficulty.medium,
    );
    gameState.phase = GamePhase.playing;

    for (final bot in bots) {
      botLearningService.startGameRecording(
        gameId: gameState.hashCode.toString(),
        player: bot,
        gameState: gameState,
        usedSBMM: false,
      );
    }

    int guard = 0;
    while (gameState.phase != GamePhase.ended &&
        gameState.phase != GamePhase.dutchCalled &&
        guard < config.maxTurnsPerMatch) {
      guard++;

      await _playBotTurnHeadless(gameState);

      if (gameState.phase == GamePhase.dutchCalled) break;

      gameState.phase = GamePhase.reaction;
      for (final bot in gameState.players.where((p) => !p.isHuman)) {
        if (gameState.phase != GamePhase.reaction) break;
        await _tryReactionMatchHeadless(gameState, bot);
      }
      gameState.phase = GamePhase.playing;
      gameState.lastSpiedCard = null;

      if (gameState.deck.isEmpty && gameState.discardPile.length <= 1) {
        break;
      }

      GameLogic.nextPlayer(gameState);
    }

    GameLogic.endGame(gameState);
    final ranking = gameState.getFinalRanking();
    final ghostRank = ranking.indexOf(ghostPlayer) + 1;
    final botWon = ranking.first.isHuman == false && ranking.first.id != ghostPlayer.id;

    final ghostFinalScore = gameState.getFinalScore(ghostPlayer);
    final ghostFinalHandSize = ghostPlayer.hand.length;

    for (final bot in bots) {
      final rank = ranking.indexOf(bot) + 1;
      final calledDutch = gameState.dutchCallerId == bot.id;
      final wonDutch = calledDutch && rank == 1;
      await botLearningService.endGameRecording(
        botPlayerId: bot.id,
        finalScore: gameState.getFinalScore(bot),
        finalRank: rank,
        calledDutch: calledDutch,
        wonDutch: wonDutch,
        cardsAtDutch: calledDutch ? bot.hand.length : 0,
        scoreAtDutch: calledDutch ? gameState.getFinalScore(bot) : 0,
        humanFinalScore: ghostFinalScore,
        humanFinalHandSize: ghostFinalHandSize,
        botFinalHandSize: bot.hand.length,
      );
    }

    return TrainingMatchResult(
      botWon: botWon,
      botCount: bots.length,
      ghostRank: ghostRank,
    );
  }

  BotSkillLevel _randomSkillLevel() {
    final levels = BotSkillLevel.values;
    return levels[_random.nextInt(levels.length)];
  }

  Future<Map<String, double>?> _fetchBotParams(
    BotLearningService service, {
    required BotBehavior behavior,
    required BotSkillLevel skillLevel,
  }) async {
    final params = await service.fetchBotParameters(
      behavior: behavior.name,
      skillLevel: skillLevel.name,
    );
    if (params == null || params.isEmpty) return null;
    final converted = <String, double>{};
    params.forEach((key, value) {
      if (value is num) converted[key] = value.toDouble();
    });
    return converted.isEmpty ? null : converted;
  }

  Future<void> _sendTrainingSummary({
    required int totalMatches,
    required double botWinRate,
  }) async {
    try {
      final uri = Uri.parse('${config.serverBaseUrl}/api/bot-learning/training-series');
      final payload = jsonEncode({
        'timestamp': DateTime.now().toIso8601String(),
        'totalMatches': totalMatches,
        'botWinRate': botWinRate,
      });
      await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      // best-effort
    }
  }
}
