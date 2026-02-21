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
  final String platinumBehavior;

  const SweepOptions({
    required this.stage1Configs,
    required this.stage1Games,
    required this.topConfigs,
    required this.stage2Games,
    required this.seed,
    required this.shuffleSeats,
    required this.dealMode,
    required this.platinumBehavior,
  });

  int get totalPlannedGames =>
      (stage1Configs * stage1Games) + (topConfigs * stage2Games);

  factory SweepOptions.fromArgs(List<String> args) {
    int readInt(String key, int fallback, {int min = 1, int max = 100000}) {
      final raw = _readArgValue(args, key);
      final parsed = raw == null ? fallback : (int.tryParse(raw) ?? fallback);
      return parsed.clamp(min, max);
    }

    final behavior = _readArgValue(args, '--plat-behavior') ?? 'balanced';
    if (!const {'balanced', 'aggressive', 'fast', 'moi'}.contains(behavior)) {
      throw FormatException(
        '--plat-behavior invalide "$behavior" '
        '(balanced|aggressive|fast|moi)',
      );
    }

    return SweepOptions(
      stage1Configs: readInt('--stage1-configs', 12, min: 4, max: 80),
      stage1Games: readInt('--stage1-games', 120, min: 50, max: 3000),
      topConfigs: readInt('--top', 3, min: 1, max: 12),
      stage2Games: readInt('--stage2-games', 500, min: 100, max: 5000),
      seed: readInt('--seed', 20260221, min: 1, max: 1 << 30),
      shuffleSeats: _readBoolArg(args, '--shuffle-seats', true),
      dealMode: _readArgValue(args, '--deal-mode') ?? 'round',
      platinumBehavior: behavior,
    );
  }
}

class MoiThresholdConfig {
  final double keepThreshold;
  final double forceDiscardThreshold;
  final int maxSoftWorsen;

  const MoiThresholdConfig({
    required this.keepThreshold,
    required this.forceDiscardThreshold,
    required this.maxSoftWorsen,
  });

  String get id => 'k${keepThreshold.toStringAsFixed(2)}'
      '_f${forceDiscardThreshold.toStringAsFixed(2)}'
      '_w$maxSoftWorsen';

  Map<String, String> asDefines() {
    return <String, String>{
      'MOI_ML_KEEP_THRESHOLD': keepThreshold.toStringAsFixed(4),
      'MOI_ML_FORCE_DISCARD_THRESHOLD':
          forceDiscardThreshold.toStringAsFixed(4),
      'MOI_ML_MAX_SOFT_WORSEN': '$maxSoftWorsen',
    };
  }

  String compact() {
    return 'keep=${keepThreshold.toStringAsFixed(2)} '
        'forceDiscard=${forceDiscardThreshold.toStringAsFixed(2)} '
        'worsen=$maxSoftWorsen';
  }

  @override
  bool operator ==(Object other) =>
      other is MoiThresholdConfig && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class EvalResult {
  final MoiThresholdConfig config;
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
  stdout.writeln('=== MOI THRESHOLD SWEEP CLI ===');
  stdout.writeln(
    'platBehavior=${options.platinumBehavior} '
    'stage1=${options.stage1Configs}x${options.stage1Games} '
    'top=${options.topConfigs}x${options.stage2Games} '
    'seed=${options.seed} shuffleSeats=${options.shuffleSeats} '
    'dealMode=${options.dealMode}',
  );
  stdout.writeln('plannedGames=${options.totalPlannedGames}');
  if (options.totalPlannedGames < 1000 || options.totalPlannedGames > 3000) {
    stdout.writeln(
      'warning: plannedGames hors cible [1000..3000], continue quand meme',
    );
  }
  stdout.writeln('');

  final random = Random(options.seed);
  final stage1Configs = _buildStage1Configs(options.stage1Configs, random);

  final stage1Results = <EvalResult>[];
  for (int i = 0; i < stage1Configs.length; i++) {
    final cfg = stage1Configs[i];
    stdout
        .writeln('[stage1 ${i + 1}/${stage1Configs.length}] ${cfg.compact()}');
    final result = await _evaluateConfig(
      config: cfg,
      games: options.stage1Games,
      shuffleSeats: options.shuffleSeats,
      dealMode: options.dealMode,
      platinumBehavior: options.platinumBehavior,
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
    stdout.writeln('[stage2 ${i + 1}/${top.length}] ${cfg.compact()}');
    final result = await _evaluateConfig(
      config: cfg,
      games: options.stage2Games,
      shuffleSeats: options.shuffleSeats,
      dealMode: options.dealMode,
      platinumBehavior: options.platinumBehavior,
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
  stdout.writeln(
    _buildDefinesCommand(
      config: best.config,
      platinumBehavior: options.platinumBehavior,
      dealMode: options.dealMode,
    ),
  );
}

List<MoiThresholdConfig> _buildStage1Configs(int count, Random random) {
  final keepValues = <double>[
    0.64,
    0.68,
    0.72,
    0.76,
    0.80,
    0.84,
    0.88,
    0.90,
    0.92
  ];
  final forceValues = <double>[
    0.28,
    0.34,
    0.40,
    0.46,
    0.52,
    0.58,
    0.62,
    0.66,
    0.70
  ];
  final worsenValues = <int>[0, 1, 2, 3];

  final selected = <MoiThresholdConfig>{
    const MoiThresholdConfig(
      keepThreshold: 0.77,
      forceDiscardThreshold: 0.49,
      maxSoftWorsen: 2,
    ),
  };

  while (selected.length < count) {
    final keep = keepValues[random.nextInt(keepValues.length)];
    final force = forceValues[random.nextInt(forceValues.length)];
    if (force >= keep) continue;
    selected.add(
      MoiThresholdConfig(
        keepThreshold: keep,
        forceDiscardThreshold: force,
        maxSoftWorsen: worsenValues[random.nextInt(worsenValues.length)],
      ),
    );
  }
  return selected.toList(growable: false);
}

Future<EvalResult> _evaluateConfig({
  required MoiThresholdConfig config,
  required int games,
  required bool shuffleSeats,
  required String dealMode,
  required String platinumBehavior,
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
    '--duel-moi-behavior=moi',
    '--duel-plat-behavior=$platinumBehavior',
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

String _buildDefinesCommand({
  required MoiThresholdConfig config,
  required String platinumBehavior,
  required String dealMode,
}) {
  final defines = config.asDefines();
  final pieces = <String>[];
  for (final entry in defines.entries) {
    pieces.add('-D${entry.key}=${entry.value}');
  }

  return 'dart ${pieces.join(' ')} run tool/bot_ladder_cli.dart '
      '--moi-vs-platinum=true --duel-moi-behavior=moi '
      '--duel-plat-behavior=$platinumBehavior --games=600 '
      '--shuffle-seats=true --samples=0 --inspect-losses=0 '
      '--deal-mode=$dealMode';
}

String? _readArgValue(List<String> args, String key) {
  for (final arg in args) {
    if (arg.startsWith('$key=')) return arg.substring(key.length + 1);
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
