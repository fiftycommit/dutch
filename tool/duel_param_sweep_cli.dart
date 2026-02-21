import 'dart:io';
import 'dart:math';

class SweepOptions {
  final int stage1Configs;
  final int stage1Games;
  final int topConfigs;
  final int stage2Games;
  final int seed;
  final bool shuffleSeats;
  final String dealMode;

  const SweepOptions({
    required this.stage1Configs,
    required this.stage1Games,
    required this.topConfigs,
    required this.stage2Games,
    required this.seed,
    required this.shuffleSeats,
    required this.dealMode,
  });

  int get totalPlannedGames =>
      (stage1Configs * stage1Games) + (topConfigs * stage2Games);

  factory SweepOptions.fromArgs(List<String> args) {
    int readInt(String key, int fallback, {int min = 1, int max = 100000}) {
      final raw = _readArgValue(args, key);
      final parsed = raw == null ? fallback : (int.tryParse(raw) ?? fallback);
      return parsed.clamp(min, max);
    }

    final shuffle = _readBoolArg(args, '--shuffle-seats', true);
    final dealMode = _readArgValue(args, '--deal-mode') ?? 'round';

    return SweepOptions(
      stage1Configs: readInt('--stage1-configs', 12, min: 4, max: 60),
      stage1Games: readInt('--stage1-games', 120, min: 50, max: 2000),
      topConfigs: readInt('--top', 3, min: 1, max: 10),
      stage2Games: readInt('--stage2-games', 400, min: 100, max: 5000),
      seed: readInt('--seed', 20260221, min: 1, max: 1 << 30),
      shuffleSeats: shuffle,
      dealMode: dealMode,
    );
  }
}

class DuelParamConfig {
  final double matchBonus;
  final double endgameMatchBonus;
  final int intelCap;
  final int antiHumanDrop;
  final double sabotageFloor;
  final double unknownFloor;
  final int dutchAllow;
  final int dutchCap;
  final double threatLow;
  final double threatNormal;

  const DuelParamConfig({
    required this.matchBonus,
    required this.endgameMatchBonus,
    required this.intelCap,
    required this.antiHumanDrop,
    required this.sabotageFloor,
    required this.unknownFloor,
    required this.dutchAllow,
    required this.dutchCap,
    required this.threatLow,
    required this.threatNormal,
  });

  String get id =>
      'm${matchBonus.toStringAsFixed(2)}_e${endgameMatchBonus.toStringAsFixed(2)}_'
      'cap${intelCap}_drop${antiHumanDrop}_sf${sabotageFloor.toStringAsFixed(2)}_'
      'uf${unknownFloor.toStringAsFixed(2)}_da${dutchAllow}_dc${dutchCap}_'
      'tl${threatLow.toStringAsFixed(1)}_tn${threatNormal.toStringAsFixed(1)}';

  Map<String, String> asDefines() {
    return <String, String>{
      'DUEL_PLAT_MATCH_BONUS': matchBonus.toStringAsFixed(4),
      'DUEL_PLAT_MATCH_ENDGAME_BONUS': endgameMatchBonus.toStringAsFixed(4),
      'DUEL_INTEL_STRONG_CAP': '$intelCap',
      'DUEL_ANTI_HUMAN_DROP': '$antiHumanDrop',
      'DUEL_HUMAN_SABOTAGE_FLOOR': sabotageFloor.toStringAsFixed(4),
      'DUEL_HUMAN_UNKNOWN_FLOOR': unknownFloor.toStringAsFixed(4),
      'DUEL_MOI_DUTCH_ALLOW': '$dutchAllow',
      'DUEL_MOI_DUTCH_CAP': '$dutchCap',
      'DUEL_HUMAN_THREAT_LOW': threatLow.toStringAsFixed(4),
      'DUEL_HUMAN_THREAT_NORMAL': threatNormal.toStringAsFixed(4),
    };
  }

  String compact() {
    return 'match=${matchBonus.toStringAsFixed(2)} '
        'end=${endgameMatchBonus.toStringAsFixed(2)} '
        'cap=$intelCap drop=$antiHumanDrop '
        'sab=${sabotageFloor.toStringAsFixed(2)} '
        'unk=${unknownFloor.toStringAsFixed(2)} '
        'allow=$dutchAllow dcap=$dutchCap '
        'thrLow=${threatLow.toStringAsFixed(1)} '
        'thrNorm=${threatNormal.toStringAsFixed(1)}';
  }

  @override
  bool operator ==(Object other) {
    if (other is! DuelParamConfig) return false;
    return id == other.id;
  }

  @override
  int get hashCode => id.hashCode;
}

class EvalResult {
  final DuelParamConfig config;
  final int games;
  final double moiWinPct;
  final double platinumWinPct;
  final double platinumSeat1WinPct;
  final double platinumSeat2WinPct;
  final String rawSummary;

  const EvalResult({
    required this.config,
    required this.games,
    required this.moiWinPct,
    required this.platinumWinPct,
    required this.platinumSeat1WinPct,
    required this.platinumSeat2WinPct,
    required this.rawSummary,
  });

  double get seatGap => (platinumSeat1WinPct - platinumSeat2WinPct).abs();
  double get stabilityScore => platinumWinPct - (seatGap * 0.35);
}

Future<void> main(List<String> args) async {
  final options = SweepOptions.fromArgs(args);
  stdout.writeln('=== DUEL PARAM SWEEP CLI ===');
  stdout.writeln(
    'stage1=${options.stage1Configs}x${options.stage1Games} '
    'top=${options.topConfigs}x${options.stage2Games} '
    'seed=${options.seed} shuffleSeats=${options.shuffleSeats} '
    'dealMode=${options.dealMode}',
  );
  stdout.writeln('plannedGames=${options.totalPlannedGames}');
  if (options.totalPlannedGames < 1000 || options.totalPlannedGames > 3000) {
    stdout.writeln(
      'warning: plannedGames hors cible [1000..3000], continue quand même',
    );
  }

  final random = Random(options.seed);
  final stage1Configs = _buildStage1Configs(options.stage1Configs, random);
  stdout.writeln('configs generated: ${stage1Configs.length}');
  stdout.writeln('');

  final stage1Results = <EvalResult>[];
  for (int i = 0; i < stage1Configs.length; i++) {
    final cfg = stage1Configs[i];
    stdout.writeln(
      '[stage1 ${i + 1}/${stage1Configs.length}] ${cfg.compact()}',
    );
    final result = await _evaluateConfig(
      config: cfg,
      games: options.stage1Games,
      shuffleSeats: options.shuffleSeats,
      dealMode: options.dealMode,
    );
    stage1Results.add(result);
    stdout.writeln(
      '  -> PLAT=${result.platinumWinPct.toStringAsFixed(1)}% '
      'MOI=${result.moiWinPct.toStringAsFixed(1)}% '
      'seatGap=${result.seatGap.toStringAsFixed(1)} '
      'score=${result.stabilityScore.toStringAsFixed(2)}',
    );
  }

  stage1Results.sort((a, b) {
    final byScore = b.stabilityScore.compareTo(a.stabilityScore);
    if (byScore != 0) return byScore;
    return b.platinumWinPct.compareTo(a.platinumWinPct);
  });

  final topCount = min(options.topConfigs, stage1Results.length);
  final top = stage1Results.take(topCount).toList(growable: false);
  stdout.writeln('');
  stdout.writeln('--- Stage1 Top $topCount ---');
  for (int i = 0; i < top.length; i++) {
    final r = top[i];
    stdout.writeln(
      '#${i + 1}: score=${r.stabilityScore.toStringAsFixed(2)} '
      'PLAT=${r.platinumWinPct.toStringAsFixed(1)} '
      'seatGap=${r.seatGap.toStringAsFixed(1)} :: ${r.config.compact()}',
    );
  }

  stdout.writeln('');
  stdout.writeln('--- Stage2 Validation ---');
  final stage2Results = <EvalResult>[];
  for (int i = 0; i < top.length; i++) {
    final cfg = top[i].config;
    stdout.writeln(
      '[stage2 ${i + 1}/${top.length}] ${cfg.compact()}',
    );
    final result = await _evaluateConfig(
      config: cfg,
      games: options.stage2Games,
      shuffleSeats: options.shuffleSeats,
      dealMode: options.dealMode,
    );
    stage2Results.add(result);
    stdout.writeln(
      '  -> PLAT=${result.platinumWinPct.toStringAsFixed(1)}% '
      'MOI=${result.moiWinPct.toStringAsFixed(1)}% '
      'seatGap=${result.seatGap.toStringAsFixed(1)} '
      'score=${result.stabilityScore.toStringAsFixed(2)}',
    );
  }

  stage2Results.sort((a, b) {
    final byScore = b.stabilityScore.compareTo(a.stabilityScore);
    if (byScore != 0) return byScore;
    return b.platinumWinPct.compareTo(a.platinumWinPct);
  });

  stdout.writeln('');
  stdout.writeln('--- Final Ranking ---');
  for (int i = 0; i < stage2Results.length; i++) {
    final r = stage2Results[i];
    stdout.writeln(
      '#${i + 1}: score=${r.stabilityScore.toStringAsFixed(2)} '
      'PLAT=${r.platinumWinPct.toStringAsFixed(1)} '
      'seatGap=${r.seatGap.toStringAsFixed(1)} '
      '[S1=${r.platinumSeat1WinPct.toStringAsFixed(1)} '
      'S2=${r.platinumSeat2WinPct.toStringAsFixed(1)}] '
      ':: ${r.config.compact()}',
    );
  }

  final best = stage2Results.first;
  stdout.writeln('');
  stdout.writeln('=== BEST CONFIG ===');
  stdout.writeln(best.config.compact());
  stdout.writeln(
    'validated: PLAT=${best.platinumWinPct.toStringAsFixed(1)}% '
    'MOI=${best.moiWinPct.toStringAsFixed(1)}% '
    'seatGap=${best.seatGap.toStringAsFixed(1)}',
  );
  stdout.writeln('Use with defines:');
  stdout.writeln(_buildDefinesCommand(best.config));
}

List<DuelParamConfig> _buildStage1Configs(int count, Random random) {
  final matchBonus = <double>[0.30, 0.34, 0.38, 0.42, 0.46];
  final endBonus = <double>[0.06, 0.10, 0.14, 0.18];
  final intelCap = <int>[3, 4, 5];
  final antiDrop = <int>[0, 1, 2];
  final sabotageFloor = <double>[-0.15, -0.10, -0.05, 0.00, 0.05];
  final unknownFloor = <double>[0.20, 0.35, 0.50, 0.65];
  final dutchAllow = <int>[1, 2, 3];
  final dutchCap = <int>[5, 6, 7];
  final threatLow = <double>[4.5, 6.0, 7.5];
  final threatNormal = <double>[2.0, 3.0, 4.0];

  final selected = <DuelParamConfig>{
    const DuelParamConfig(
      matchBonus: 0.38,
      endgameMatchBonus: 0.12,
      intelCap: 4,
      antiHumanDrop: 1,
      sabotageFloor: -0.05,
      unknownFloor: 0.35,
      dutchAllow: 2,
      dutchCap: 6,
      threatLow: 6.0,
      threatNormal: 3.0,
    ),
  };

  while (selected.length < count) {
    selected.add(
      DuelParamConfig(
        matchBonus: matchBonus[random.nextInt(matchBonus.length)],
        endgameMatchBonus: endBonus[random.nextInt(endBonus.length)],
        intelCap: intelCap[random.nextInt(intelCap.length)],
        antiHumanDrop: antiDrop[random.nextInt(antiDrop.length)],
        sabotageFloor: sabotageFloor[random.nextInt(sabotageFloor.length)],
        unknownFloor: unknownFloor[random.nextInt(unknownFloor.length)],
        dutchAllow: dutchAllow[random.nextInt(dutchAllow.length)],
        dutchCap: dutchCap[random.nextInt(dutchCap.length)],
        threatLow: threatLow[random.nextInt(threatLow.length)],
        threatNormal: threatNormal[random.nextInt(threatNormal.length)],
      ),
    );
  }

  return selected.toList(growable: false);
}

Future<EvalResult> _evaluateConfig({
  required DuelParamConfig config,
  required int games,
  required bool shuffleSeats,
  required String dealMode,
}) async {
  final args = <String>[];
  final defines = config.asDefines();
  for (final entry in defines.entries) {
    args.add('-D${entry.key}=${entry.value}');
  }

  args.addAll(<String>[
    'run',
    'tool/bot_ladder_cli.dart',
    '--moi-vs-platinum=true',
    '--games=$games',
    '--shuffle-seats=${shuffleSeats ? 'true' : 'false'}',
    '--samples=0',
    '--inspect-losses=0',
    '--deal-mode=$dealMode',
  ]);

  final result = await Process.run('dart', args);
  if (result.exitCode != 0) {
    throw StateError(
      'Evaluation failed (${config.id}):\n'
      '${result.stdout}\n${result.stderr}',
    );
  }

  final out = '${result.stdout}';
  final moiWin = _extractPercent(
    out,
    RegExp(r'MOI:\s*win=([0-9]+(?:\.[0-9]+)?)%'),
  );
  final platWin = _extractPercent(
    out,
    RegExp(r'PLATINE:\s*win=([0-9]+(?:\.[0-9]+)?)%'),
  );
  final seatLine = _extractLineStartingWith(out, 'PLATINE  ');
  final platSeat1 = _extractPercent(
    seatLine,
    RegExp(r'S1:([0-9]+(?:\.[0-9]+)?)%'),
  );
  final platSeat2 = _extractPercent(
    seatLine,
    RegExp(r'S2:([0-9]+(?:\.[0-9]+)?)%'),
  );

  return EvalResult(
    config: config,
    games: games,
    moiWinPct: moiWin,
    platinumWinPct: platWin,
    platinumSeat1WinPct: platSeat1,
    platinumSeat2WinPct: platSeat2,
    rawSummary: out,
  );
}

double _extractPercent(String text, RegExp regex) {
  final match = regex.firstMatch(text);
  if (match == null) {
    throw FormatException('Cannot parse percent with regex: ${regex.pattern}');
  }
  return double.parse(match.group(1)!);
}

String _extractLineStartingWith(String text, String prefix) {
  for (final line in text.split('\n')) {
    if (line.startsWith(prefix)) return line;
  }
  throw FormatException('Cannot find line starting with "$prefix"');
}

String _buildDefinesCommand(DuelParamConfig config) {
  final defines = config.asDefines();
  final pieces = <String>[];
  for (final entry in defines.entries) {
    pieces.add('-D${entry.key}=${entry.value}');
  }
  return 'dart ${pieces.join(' ')} run tool/bot_ladder_cli.dart '
      '--moi-vs-platinum=true --games=600 --shuffle-seats=true '
      '--samples=0 --inspect-losses=0 --deal-mode=round';
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
