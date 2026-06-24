import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/services/game/game_logic.dart';
import 'package:dutch_game/services/game/bot/bot_card_strategy.dart';
import 'package:dutch_game/services/game/bot/bot_config.dart';
import 'package:dutch_game/services/game/bot/bot_difficulty.dart';
import 'package:dutch_game/services/game/bot/bot_dutch_strategy.dart';
import 'package:dutch_game/services/game/bot/bot_fair_play_audit.dart';
import 'package:dutch_game/services/game/bot/bot_memory_manager.dart';
import 'package:dutch_game/services/game/bot/bot_personality.dart';
import 'package:dutch_game/services/game/bot/bot_power_handler.dart';
import 'package:dutch_game/services/logging/game_logger_service.dart';

const List<BotSkillLevel> _orderedSkills = [
  BotSkillLevel.difficile,
  BotSkillLevel.silver,
  BotSkillLevel.bronze,
];

Future<void> main(List<String> args) async {
  try {
    final config = _CliConfig.fromArgs(args);

    stdout.writeln('=== BOT LADDER CLI ===');
    stdout.writeln(
      'games=${config.games} maxTurns=${config.maxTurns} '
      'showSamples=${config.showSamples} mix=${config.mixLabel} '
      'inspectLosses=${config.inspectLosses} totalPlayers=${config.totalPlayers} '
      'shuffleSeats=${config.shuffleSeats} '
      'moiVsPlatinumDuel=${config.moiVsPlatinumDuel} '
      'duelMoiBehavior=${config.duelMoiBehavior.name} '
      'duelPlatinumBehavior=${config.duelPlatinumBehavior.name} '
      'dealMode=${config.dealMode.name}',
    );

    final simulator = _LadderSimulator(config: config);
    final result = await simulator.run();

    stdout.writeln('');
    stdout.writeln(result.summary);
  } on FormatException catch (e) {
    stderr.writeln('Configuration invalide: ${e.message}');
    stderr.writeln(
      'Exemple: dart run tool/bot_ladder_cli.dart '
      '--games=120 --bronze=3 --silver=3 --gold=3 --platinum=3 --deal-mode=round\n'
      'Duel MOI vs Platine: dart run tool/bot_ladder_cli.dart '
      '--moi-vs-platinum=true --games=200 --shuffle-seats=true '
      '--duel-plat-behavior=balanced|aggressive|fast|moi',
    );
    exitCode = 64;
  }
}

class _CliConfig {
  final int games;
  final int maxTurns;
  final int showSamples;
  final int inspectLosses;
  final bool shuffleSeats;
  final bool moiVsPlatinumDuel;
  final BotBehavior duelMoiBehavior;
  final BotBehavior duelPlatinumBehavior;
  final DealMode dealMode;
  final Map<BotSkillLevel, int> skillCounts;

  const _CliConfig({
    required this.games,
    required this.maxTurns,
    required this.showSamples,
    required this.inspectLosses,
    required this.shuffleSeats,
    required this.moiVsPlatinumDuel,
    required this.duelMoiBehavior,
    required this.duelPlatinumBehavior,
    required this.dealMode,
    required this.skillCounts,
  });

  int get totalPlayers => skillCounts.values.fold(0, (a, b) => a + b);

  String get mixLabel {
    if (moiVsPlatinumDuel) {
      return 'MOI(${duelMoiBehavior.name}) vs P(${duelPlatinumBehavior.name})';
    }
    final b = skillCounts[BotSkillLevel.bronze] ?? 0;
    final s = skillCounts[BotSkillLevel.silver] ?? 0;
    final d = skillCounts[BotSkillLevel.difficile] ?? 0;
    return 'B$b S$s D$d';
  }

  factory _CliConfig.fromArgs(List<String> args) {
    int readInt(String key, int fallback) {
      final value = _readArgValue(args, key);
      if (value == null) return fallback;
      return int.tryParse(value) ?? fallback;
    }

    final moiVsPlatinumDuel = _readBoolArg(args, '--moi-vs-platinum', false);
    final duelMoiBehavior = _parseBotBehavior(
      _readArgValue(args, '--duel-moi-behavior') ?? 'moi',
      argName: '--duel-moi-behavior',
    );
    final duelPlatinumBehavior = _parseBotBehavior(
      _readArgValue(args, '--duel-plat-behavior') ?? 'balanced',
      argName: '--duel-plat-behavior',
    );

    final skillCounts = moiVsPlatinumDuel
        ? <BotSkillLevel, int>{
            BotSkillLevel.bronze: 0,
            BotSkillLevel.silver: 0,
            BotSkillLevel.difficile: 2,
          }
        : <BotSkillLevel, int>{
            BotSkillLevel.bronze: readInt('--bronze', 1).clamp(0, 20),
            BotSkillLevel.silver: readInt('--silver', 1).clamp(0, 20),
            BotSkillLevel.difficile: readInt('--difficile', 1).clamp(0, 20),
          };

    final totalPlayers = skillCounts.values.fold(0, (a, b) => a + b);
    if (totalPlayers < 2) {
      throw const FormatException('Il faut au moins 2 joueurs bots au total.');
    }

    return _CliConfig(
      games: readInt('--games', 200).clamp(1, 5000),
      maxTurns: readInt('--max-turns', 800).clamp(100, 10000),
      showSamples: readInt('--samples', 5).clamp(0, 30),
      inspectLosses: readInt('--inspect-losses', 0).clamp(0, 20),
      shuffleSeats: _readBoolArg(args, '--shuffle-seats', false),
      moiVsPlatinumDuel: moiVsPlatinumDuel,
      duelMoiBehavior: duelMoiBehavior,
      duelPlatinumBehavior: duelPlatinumBehavior,
      dealMode: _parseDealMode(_readArgValue(args, '--deal-mode') ?? 'round'),
      skillCounts: skillCounts,
    );
  }
}

String? _readArgValue(List<String> args, String key) {
  for (final arg in args) {
    if (arg.startsWith('$key=')) {
      return arg.substring(key.length + 1);
    }
  }
  return null;
}

bool _readBoolArg(List<String> args, String key, bool fallback) {
  final value = _readArgValue(args, key);
  if (value == null) return fallback;
  final lower = value.toLowerCase();
  if (lower == '1' || lower == 'true' || lower == 'yes' || lower == 'on') {
    return true;
  }
  if (lower == '0' || lower == 'false' || lower == 'no' || lower == 'off') {
    return false;
  }
  return fallback;
}

DealMode _parseDealMode(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'block':
    case 'block-sequential':
    case 'sequential':
      return DealMode.blockSequential;
    case 'round':
    case 'round-robin':
      return DealMode.roundRobin;
    case 'random':
    case 'random-indices':
      return DealMode.randomIndices;
    case 'disjoint':
    case 'disjoint-values':
    case 'no-common':
    case 'no-shared':
      return DealMode.disjointValues;
    default:
      throw FormatException(
        'deal-mode inconnu "$raw". '
        'Valeurs: block, round, random, disjoint',
      );
  }
}

BotBehavior _parseBotBehavior(
  String raw, {
  required String argName,
}) {
  switch (raw.trim().toLowerCase()) {
    case 'balanced':
      return BotBehavior.balanced;
    case 'aggressive':
      return BotBehavior.aggressive;
    case 'fast':
      return BotBehavior.fast;
    case 'moi':
      return BotBehavior.moi;
    default:
      throw FormatException(
        '$argName invalide "$raw". Valeurs: balanced, aggressive, fast, moi',
      );
  }
}

class _LadderSimulator {
  final _CliConfig config;
  int _capturedLosses = 0;

  _LadderSimulator({required this.config});

  Future<_SimulationAggregate> run() async {
    final aggregate = _SimulationAggregate(config: config);

    for (int i = 0; i < config.games; i++) {
      final gameResult = await _runSingleGame(
        gameIndex: i + 1,
        maxTurns: config.maxTurns,
      );
      aggregate.add(gameResult);

      final completed = i + 1;
      if (completed % 25 == 0 || completed == config.games) {
        stdout.writeln('progress: $completed/${config.games}');
      }
    }

    return aggregate;
  }

  Future<_SingleGameResult> _runSingleGame({
    required int gameIndex,
    required int maxTurns,
  }) async {
    final inspectThisGame = config.inspectLosses > 0;
    if (inspectThisGame) {
      GameLoggerService.instance.reset();
      GameLoggerService.instance.setEnabled(true);
    }

    final players = _createLadderPlayers(gameIndex);
    final gameState = GameLogic.initializeGame(
      players: players,
      gameMode: GameMode.quick,
      difficulty: Difficulty.medium,
      dealMode: config.dealMode,
    );
    gameState.phase = GamePhase.playing;

    int guard = 0;
    while (guard < maxTurns &&
        gameState.phase != GamePhase.dutchCalled &&
        gameState.phase != GamePhase.ended) {
      guard++;

      await _playBotTurnHeadless(gameState, traceDecisions: inspectThisGame);
      if (gameState.phase == GamePhase.dutchCalled ||
          gameState.phase == GamePhase.ended) {
        break;
      }

      await _runReactionPhase(gameState);
      if (gameState.phase == GamePhase.ended) break;

      if (gameState.deck.isEmpty && gameState.discardPile.length <= 1) {
        break;
      }

      GameLogic.nextPlayer(gameState);
    }

    GameLogic.endGame(gameState);
    final ranking = gameState.getFinalRanking();
    final outcomes = <_PlayerOutcome>[];

    for (int i = 0; i < ranking.length; i++) {
      final player = ranking[i];
      final skill = player.botSkillLevel;
      if (skill == null) continue;
      outcomes.add(_PlayerOutcome(
        playerName: player.name,
        skill: skill,
        seat: player.position,
        rank: i + 1,
        score: gameState.getFinalScore(player),
      ));
    }

    String? lossInsight;
    final winner = ranking.isNotEmpty ? ranking.first : null;
    final winnerSkill = winner?.botSkillLevel;
    if (inspectThisGame &&
        winner != null &&
        winnerSkill != BotSkillLevel.difficile &&
        _capturedLosses < config.inspectLosses) {
      final log = GameLoggerService.instance.getLogContent();
      lossInsight = _buildLossInsight(
        gameIndex: gameIndex,
        winner: winner,
        winnerScore: gameState.getFinalScore(winner),
        ranking: ranking,
        log: log,
      );
      _capturedLosses++;
    }

    return _SingleGameResult(
      playerCount: players.length,
      outcomes: outcomes,
      lossInsight: lossInsight,
    );
  }

  List<Player> _createLadderPlayers(int gameIndex) {
    if (config.moiVsPlatinumDuel) {
      final duelSlots = <_DuelSeatSlot>[
        _DuelSeatSlot(
          idSuffix: 'moi',
          name: 'MOI',
          behavior: config.duelMoiBehavior,
        ),
        _DuelSeatSlot(
          idSuffix: 'platine',
          name: 'PLATINE',
          behavior: config.duelPlatinumBehavior,
        ),
      ];

      if (config.shuffleSeats) {
        duelSlots.shuffle(Random((gameIndex * 1427) + 17));
      }

      final players = <Player>[];
      for (int position = 0; position < duelSlots.length; position++) {
        final slot = duelSlots[position];
        players.add(
          Player(
            id: 'bot_${slot.idSuffix}_g$gameIndex',
            name: slot.name,
            isHuman: false,
            botBehavior: slot.behavior,
            botSkillLevel: BotSkillLevel.difficile,
            position: position,
          ),
        );
      }
      return players;
    }

    final buildOrder = <BotSkillLevel>[
      BotSkillLevel.bronze,
      BotSkillLevel.silver,
      BotSkillLevel.difficile,
    ];

    final slots = <_PlayerSeatSlot>[];
    for (final skill in buildOrder) {
      final count = config.skillCounts[skill] ?? 0;
      for (int i = 0; i < count; i++) {
        slots.add(_PlayerSeatSlot(skill: skill, ordinal: i + 1));
      }
    }

    if (config.shuffleSeats) {
      final rng = Random((gameIndex * 9973) + slots.length * 31);
      slots.shuffle(rng);
    }

    final players = <Player>[];
    for (int position = 0; position < slots.length; position++) {
      final slot = slots[position];
      players.add(
        Player(
          id: 'bot_${slot.skill.name}_${slot.ordinal}_g$gameIndex',
          name: '${_skillShort(slot.skill)}${slot.ordinal}',
          isHuman: false,
          botBehavior: BotBehavior.balanced,
          botSkillLevel: slot.skill,
          position: position,
        ),
      );
    }

    return players;
  }

  Future<void> _playBotTurnHeadless(
    GameState gameState, {
    required bool traceDecisions,
  }) async {
    final bot = gameState.currentPlayer;
    if (bot.isHuman) return;

    final difficulty = BotConfig.getDifficulty(bot, null);
    final phase = BotConfig.getBotPhase(bot, gameState);
    final personality = BotPersonality.fromBot(bot);

    if (traceDecisions) {
      await GameLoggerService.instance.logTurnStart(
        player: bot,
        turnNumber: gameState.turnCount,
        allPlayers: gameState.players,
        gameState: gameState,
      );
    }

    BotMemoryManager.applyMemoryDecay(
      bot,
      difficulty,
      personality: personality,
    );
    BotFairPlayAudit.auditKnowledgeState(
      gameState,
      bot,
      difficulty,
      stage: 'cli_turn_start',
    );

    final shouldCallDutch = BotDutchStrategy.shouldCallDutch(
      gameState,
      bot,
      difficulty,
      phase,
      personality: personality,
    );
    BotFairPlayAudit.auditDutchDecisionBlindness(
      gameState,
      bot,
      difficulty,
      phase,
      shouldCallDutch,
      personality: personality,
    );
    if (shouldCallDutch) {
      GameLogic.callDutch(gameState, reason: 'cli_ladder');
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
    BotFairPlayAudit.auditKnowledgeState(
      gameState,
      bot,
      difficulty,
      stage: 'cli_after_card_action',
    );

    if (gameState.isWaitingForSpecialPower &&
        gameState.specialCardToActivate != null) {
      await BotPowerHandler.useBotSpecialPower(
        gameState,
        difficulty,
        null,
        personality: personality,
        skipDelay: true,
      );
      BotFairPlayAudit.auditKnowledgeState(
        gameState,
        bot,
        difficulty,
        stage: 'cli_after_power',
      );
    }
  }

  String _buildLossInsight({
    required int gameIndex,
    required Player winner,
    required int winnerScore,
    required List<Player> ranking,
    required String log,
  }) {
    int platPositiveExchange = 0;
    int platNegativeExchange = 0;
    int platDutchCalls = 0;
    int platPowerSkips = 0;
    final riskyLines = <String>[];

    final exchangeRegExp = RegExp(r'→\s*(P\d+)\s+ÉCHANGE.*gain:\s*(-?\d+)');
    final dutchCallRegExp = RegExp(r'DUTCH appelé par\s+(P\d+)');
    final powerSkipRegExp = RegExp(r'⚡\s+(P\d+)\s+SAUTE pouvoir');

    for (final line in log.split('\n')) {
      final exchange = exchangeRegExp.firstMatch(line);
      if (exchange != null) {
        final gain = int.tryParse(exchange.group(2) ?? '') ?? 0;
        if (gain < 0) {
          platNegativeExchange++;
          if (riskyLines.length < 3) {
            riskyLines.add(line.trim());
          }
        } else {
          platPositiveExchange++;
        }
      }

      if (dutchCallRegExp.hasMatch(line)) {
        platDutchCalls++;
      }
      if (powerSkipRegExp.hasMatch(line)) {
        platPowerSkips++;
      }
    }

    final top3 = ranking.take(3).map((p) {
      final skill = p.botSkillLevel?.name ?? '?';
      return '${p.name}($skill:${p.calculateScore()})';
    }).join(' > ');

    final riskSnippet = riskyLines.isEmpty ? 'none' : riskyLines.join(' || ');
    return 'G$gameIndex winner=${winner.name}($winnerScore) | '
        'top3=$top3 | '
        'P_exch(+/-)=$platPositiveExchange/$platNegativeExchange '
        'P_dutch=$platDutchCalls P_powerSkip=$platPowerSkips | '
        'risky=$riskSnippet';
  }

  Future<void> _runReactionPhase(GameState gameState) async {
    gameState.phase = GamePhase.reaction;

    final bots =
        gameState.players.where((p) => !p.isHuman).toList(growable: false);
    final difficulties = <String, BotDifficulty>{};
    for (final bot in bots) {
      difficulties[bot.id] = BotConfig.getDifficulty(bot, null);
    }

    final rng = Random();
    final initiatives = <String, double>{};
    for (final bot in bots) {
      final difficulty = difficulties[bot.id]!;
      initiatives[bot.id] = difficulty.reactionSpeed * 0.70 +
          difficulty.reactionMatchChance * 0.25 +
          difficulty.matchAccuracy * 0.05 +
          (rng.nextDouble() * 0.05);
    }

    final orderedBots = List<Player>.from(bots)
      ..sort(
          (a, b) => (initiatives[b.id] ?? 0).compareTo(initiatives[a.id] ?? 0));

    for (final bot in orderedBots) {
      if (gameState.phase != GamePhase.reaction) break;

      final difficulty = difficulties[bot.id]!;
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

    gameState.phase = GamePhase.playing;
    gameState.lastSpiedCard = null;
  }
}

class _DuelSeatSlot {
  final String idSuffix;
  final String name;
  final BotBehavior behavior;

  const _DuelSeatSlot({
    required this.idSuffix,
    required this.name,
    required this.behavior,
  });
}

class _PlayerSeatSlot {
  final BotSkillLevel skill;
  final int ordinal;

  const _PlayerSeatSlot({
    required this.skill,
    required this.ordinal,
  });
}

class _PlayerOutcome {
  final String playerName;
  final BotSkillLevel skill;
  final int seat;
  final int rank;
  final int score;

  const _PlayerOutcome({
    required this.playerName,
    required this.skill,
    required this.seat,
    required this.rank,
    required this.score,
  });
}

class _SingleGameResult {
  final int playerCount;
  final List<_PlayerOutcome> outcomes;
  final String? lossInsight;

  const _SingleGameResult({
    required this.playerCount,
    required this.outcomes,
    this.lossInsight,
  });
}

class _SkillStats {
  int appearances = 0;
  int wins = 0;
  int podiums = 0;
  int topHalf = 0;
  int lasts = 0;
  int rankSum = 0;
  int scoreSum = 0;

  void add({
    required int rank,
    required int score,
    required int playerCount,
  }) {
    appearances++;
    rankSum += rank;
    scoreSum += score;

    final topHalfLimit = (playerCount / 2).ceil();
    if (rank == 1) wins++;
    if (rank <= 3) podiums++;
    if (rank <= topHalfLimit) topHalf++;
    if (rank == playerCount) lasts++;
  }
}

class _GameSkillStats {
  double bestRankSum = 0;
  double avgRankSum = 0;
  double worstRankSum = 0;
}

class _SimulationAggregate {
  final _CliConfig config;
  final Map<BotSkillLevel, _SkillStats> _bySkill = {
    BotSkillLevel.bronze: _SkillStats(),
    BotSkillLevel.silver: _SkillStats(),
    BotSkillLevel.difficile: _SkillStats(),
  };
  final Map<BotSkillLevel, int> _gameWinsBySkill = {
    BotSkillLevel.bronze: 0,
    BotSkillLevel.silver: 0,
    BotSkillLevel.difficile: 0,
  };
  final Map<BotSkillLevel, int> _gameLastBySkill = {
    BotSkillLevel.bronze: 0,
    BotSkillLevel.silver: 0,
    BotSkillLevel.difficile: 0,
  };
  final Map<BotSkillLevel, _GameSkillStats> _gameSkillRollup = {
    BotSkillLevel.bronze: _GameSkillStats(),
    BotSkillLevel.silver: _GameSkillStats(),
    BotSkillLevel.difficile: _GameSkillStats(),
  };
  final Map<BotSkillLevel, Map<int, int>> _seatAppearancesBySkill = {
    BotSkillLevel.bronze: <int, int>{},
    BotSkillLevel.silver: <int, int>{},
    BotSkillLevel.difficile: <int, int>{},
  };
  final Map<BotSkillLevel, Map<int, int>> _seatWinsBySkill = {
    BotSkillLevel.bronze: <int, int>{},
    BotSkillLevel.silver: <int, int>{},
    BotSkillLevel.difficile: <int, int>{},
  };

  int _platWinBronzeLastGames = 0;
  int _orderedAverageRanksGames = 0;
  int _duelMoiWins = 0;
  int _duelPlatinumWins = 0;
  int _duelMoiLasts = 0;
  int _duelPlatinumLasts = 0;
  int _duelMoiScoreSum = 0;
  int _duelPlatinumScoreSum = 0;
  final Map<int, int> _duelMoiSeatAppearances = <int, int>{};
  final Map<int, int> _duelMoiSeatWins = <int, int>{};
  final Map<int, int> _duelPlatinumSeatAppearances = <int, int>{};
  final Map<int, int> _duelPlatinumSeatWins = <int, int>{};
  final List<String> _samples = [];
  final List<String> _lossInsights = [];

  _SimulationAggregate({required this.config});

  void add(_SingleGameResult result) {
    if (result.lossInsight != null) {
      _lossInsights.add(result.lossInsight!);
    }

    final ranksBySkill = <BotSkillLevel, List<int>>{};

    for (final outcome in result.outcomes) {
      _bySkill[outcome.skill]!.add(
        rank: outcome.rank,
        score: outcome.score,
        playerCount: result.playerCount,
      );
      final seatAppearances = _seatAppearancesBySkill[outcome.skill]!;
      seatAppearances[outcome.seat] = (seatAppearances[outcome.seat] ?? 0) + 1;
      if (outcome.rank == 1) {
        final seatWins = _seatWinsBySkill[outcome.skill]!;
        seatWins[outcome.seat] = (seatWins[outcome.seat] ?? 0) + 1;
      }
      ranksBySkill.putIfAbsent(outcome.skill, () => <int>[]).add(outcome.rank);
    }

    _PlayerOutcome? winner;
    _PlayerOutcome? last;
    for (final outcome in result.outcomes) {
      if (winner == null || outcome.rank < winner.rank) winner = outcome;
      if (last == null || outcome.rank > last.rank) last = outcome;
    }

    if (winner != null) {
      _gameWinsBySkill[winner.skill] =
          (_gameWinsBySkill[winner.skill] ?? 0) + 1;
    }
    if (last != null) {
      _gameLastBySkill[last.skill] = (_gameLastBySkill[last.skill] ?? 0) + 1;
    }

    if (winner?.skill == BotSkillLevel.difficile &&
        last?.skill == BotSkillLevel.bronze) {
      _platWinBronzeLastGames++;
    }

    if (config.moiVsPlatinumDuel) {
      for (final outcome in result.outcomes) {
        final isMoi = outcome.playerName == 'MOI';
        if (isMoi) {
          _duelMoiScoreSum += outcome.score;
          _duelMoiSeatAppearances[outcome.seat] =
              (_duelMoiSeatAppearances[outcome.seat] ?? 0) + 1;
          if (outcome.rank == 1) {
            _duelMoiWins++;
            _duelMoiSeatWins[outcome.seat] =
                (_duelMoiSeatWins[outcome.seat] ?? 0) + 1;
          }
          if (outcome.rank == result.playerCount) _duelMoiLasts++;
          continue;
        }

        _duelPlatinumScoreSum += outcome.score;
        _duelPlatinumSeatAppearances[outcome.seat] =
            (_duelPlatinumSeatAppearances[outcome.seat] ?? 0) + 1;
        if (outcome.rank == 1) {
          _duelPlatinumWins++;
          _duelPlatinumSeatWins[outcome.seat] =
              (_duelPlatinumSeatWins[outcome.seat] ?? 0) + 1;
        }
        if (outcome.rank == result.playerCount) _duelPlatinumLasts++;
      }
    }

    final avgRankBySkill = <BotSkillLevel, double>{};
    for (final skill in _orderedSkills) {
      final ranks = ranksBySkill[skill];
      if (ranks == null || ranks.isEmpty) continue;

      int minRank = ranks.first;
      int maxRank = ranks.first;
      int sum = 0;
      for (final rank in ranks) {
        if (rank < minRank) minRank = rank;
        if (rank > maxRank) maxRank = rank;
        sum += rank;
      }

      final avgRank = sum / ranks.length;
      avgRankBySkill[skill] = avgRank;

      final rollup = _gameSkillRollup[skill]!;
      rollup.bestRankSum += minRank;
      rollup.avgRankSum += avgRank;
      rollup.worstRankSum += maxRank;
    }

    final dAvg = avgRankBySkill[BotSkillLevel.difficile];
    final sAvg = avgRankBySkill[BotSkillLevel.silver];
    final bAvg = avgRankBySkill[BotSkillLevel.bronze];
    if (dAvg != null &&
        sAvg != null &&
        bAvg != null &&
        dAvg < sAvg &&
        sAvg < bAvg) {
      _orderedAverageRanksGames++;
    }

    if (_samples.length < config.showSamples) {
      final sorted = List<_PlayerOutcome>.from(result.outcomes)
        ..sort((a, b) => a.rank.compareTo(b.rank));

      final top = <String>[];
      final bottom = <String>[];

      final topCount = sorted.length < 3 ? sorted.length : 3;
      for (int i = 0; i < topCount; i++) {
        final o = sorted[i];
        top.add('${o.rank}:${o.playerName}(${o.score})');
      }

      for (int i = 0; i < topCount; i++) {
        final o = sorted[sorted.length - 1 - i];
        bottom.add('${o.rank}:${o.playerName}(${o.score})');
      }

      _samples.add('top ${top.join(' | ')} || bottom ${bottom.join(' | ')}');
    }
  }

  String get summary {
    String fmtPctFromCounts(int count, int total) {
      if (total <= 0) return '0.0%';
      return '${((count / total) * 100).toStringAsFixed(1)}%';
    }

    String fmtAvg(num sum, int count) {
      if (count <= 0) return '0.00';
      return (sum / count).toStringAsFixed(2);
    }

    if (config.moiVsPlatinumDuel) {
      final lines = <String>[];
      lines.add('--- Résumé duel MOI vs Platine ---');
      lines.add(
        'Games=${config.games} shuffleSeats=${config.shuffleSeats} '
        'dealMode=${config.dealMode.name}',
      );
      lines.add(
        'MOI: win=${fmtPctFromCounts(_duelMoiWins, config.games)} '
        'last=${fmtPctFromCounts(_duelMoiLasts, config.games)} '
        'avgScore=${fmtAvg(_duelMoiScoreSum, config.games)}',
      );
      lines.add(
        'PLATINE: win=${fmtPctFromCounts(_duelPlatinumWins, config.games)} '
        'last=${fmtPctFromCounts(_duelPlatinumLasts, config.games)} '
        'avgScore=${fmtAvg(_duelPlatinumScoreSum, config.games)}',
      );
      lines.add('');
      lines.add('--- Win% par seat ---');
      final seats = <int>{
        ..._duelMoiSeatAppearances.keys,
        ..._duelPlatinumSeatAppearances.keys,
      }.toList()
        ..sort();
      final moiCells = <String>[];
      final platCells = <String>[];
      for (final seat in seats) {
        final moiTotal = _duelMoiSeatAppearances[seat] ?? 0;
        final moiWins = _duelMoiSeatWins[seat] ?? 0;
        moiCells.add(
          'S${seat + 1}:${fmtPctFromCounts(moiWins, moiTotal)} ($moiWins/$moiTotal)',
        );

        final platTotal = _duelPlatinumSeatAppearances[seat] ?? 0;
        final platWins = _duelPlatinumSeatWins[seat] ?? 0;
        platCells.add(
          'S${seat + 1}:${fmtPctFromCounts(platWins, platTotal)} ($platWins/$platTotal)',
        );
      }
      lines.add('MOI      ${moiCells.join(' | ')}');
      lines.add('PLATINE  ${platCells.join(' | ')}');

      if (_samples.isNotEmpty) {
        lines.add('');
        lines.add('--- Exemples de parties ---');
        for (int i = 0; i < _samples.length; i++) {
          lines.add('#${i + 1}: ${_samples[i]}');
        }
      }
      if (_lossInsights.isNotEmpty) {
        lines.add('');
        lines.add('--- Diagnostics ---');
        for (int i = 0; i < _lossInsights.length; i++) {
          lines.add('#${i + 1}: ${_lossInsights[i]}');
        }
      }
      return lines.join('\n');
    }

    final lines = <String>[];
    lines.add('--- Résumé ladder ---');
    lines.add(
      'Mix: ${config.mixLabel} | joueurs=${config.totalPlayers} '
      '| dealMode=${config.dealMode.name}',
    );
    lines.add(
      'Platine gagnant ET Bronze dernier (partie): '
      '$_platWinBronzeLastGames/${config.games} '
      '(${fmtPctFromCounts(_platWinBronzeLastGames, config.games)})',
    );
    lines.add(
      'Ordre moyen P<G<S<B (partie): '
      '$_orderedAverageRanksGames/${config.games} '
      '(${fmtPctFromCounts(_orderedAverageRanksGames, config.games)})',
    );
    lines.add('');
    lines.add(
      'skill      n   botWin% gameWin% podium% topHalf% avgRank last%  avgScore bestRank(avg game)',
    );

    for (final skill in _orderedSkills) {
      final count = config.skillCounts[skill] ?? 0;
      if (count == 0) continue;

      final s = _bySkill[skill]!;
      final rollup = _gameSkillRollup[skill]!;
      final skillName = skill.name.padRight(9);
      final n = count.toString().padLeft(2);
      final botWin = fmtPctFromCounts(s.wins, s.appearances).padRight(7);
      final gameWin =
          fmtPctFromCounts(_gameWinsBySkill[skill] ?? 0, config.games)
              .padRight(7);
      final podium = fmtPctFromCounts(s.podiums, s.appearances).padRight(7);
      final topHalf = fmtPctFromCounts(s.topHalf, s.appearances).padRight(8);
      final avgRank = fmtAvg(s.rankSum, s.appearances).padRight(7);
      final last = fmtPctFromCounts(s.lasts, s.appearances).padRight(6);
      final avgScore = fmtAvg(s.scoreSum, s.appearances).padRight(8);
      final bestRankAvgGame = fmtAvg(rollup.bestRankSum, config.games);

      lines.add(
        '$skillName  $n   $botWin $gameWin $podium $topHalf $avgRank $last $avgScore $bestRankAvgGame',
      );
    }

    lines.add('');
    lines.add('--- Win% par seat ---');
    for (final skill in _orderedSkills.reversed) {
      final count = config.skillCounts[skill] ?? 0;
      if (count == 0) continue;
      final appearances = _seatAppearancesBySkill[skill]!;
      if (appearances.isEmpty) continue;

      final seats = appearances.keys.toList()..sort();
      final cells = <String>[];
      for (final seat in seats) {
        final total = appearances[seat] ?? 0;
        final wins = _seatWinsBySkill[skill]?[seat] ?? 0;
        cells.add(
          'S${seat + 1}:${fmtPctFromCounts(wins, total)} ($wins/$total)',
        );
      }
      lines.add('${skill.name.padRight(9)} ${cells.join(' | ')}');
    }

    if (_samples.isNotEmpty) {
      lines.add('');
      lines.add('--- Exemples de parties ---');
      for (int i = 0; i < _samples.length; i++) {
        lines.add('#${i + 1}: ${_samples[i]}');
      }
    }

    if (_lossInsights.isNotEmpty) {
      lines.add('');
      lines.add('--- Diagnostics défaites Platinum ---');
      for (int i = 0; i < _lossInsights.length; i++) {
        lines.add('#${i + 1}: ${_lossInsights[i]}');
      }
    }

    return lines.join('\n');
  }
}

String _skillShort(BotSkillLevel skill) {
  switch (skill) {
    case BotSkillLevel.bronze:
      return 'B';
    case BotSkillLevel.silver:
      return 'S';
    case BotSkillLevel.difficile:
      return 'D';
  }
}
