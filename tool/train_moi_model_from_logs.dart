import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

void main(List<String> args) {
  final config = _CliConfig.fromArgs(args);
  if (config.showHelp) {
    _printHelp();
    return;
  }

  final files = _discoverLogFiles(config.logDir);
  if (files.isEmpty) {
    stderr.writeln('Aucun fichier log trouve dans: ${config.logDir}');
    exitCode = 2;
    return;
  }

  final dataset = <_Sample>[];
  int parsedLogs = 0;
  for (final file in files) {
    final parsed = _parseLogFile(file);
    if (parsed.isNotEmpty) {
      parsedLogs++;
      dataset.addAll(parsed);
    }
  }

  if (dataset.length < 50) {
    stderr.writeln(
      'Dataset trop petit: ${dataset.length} echantillons '
      '(logs parsables: $parsedLogs/${files.length}).',
    );
    exitCode = 3;
    return;
  }

  final trained = _trainModel(dataset);

  final modelJson = <String, dynamic>{
    'logsFound': files.length,
    'logsParsed': parsedLogs,
    'samples': dataset.length,
    'trainedAtIso': DateTime.now().toUtc().toIso8601String(),
    'weights': trained.weights.toJson(),
    'thresholds': {
      'keepThreshold': trained.keepThreshold,
      'forceDiscardThreshold': trained.forceDiscardThreshold,
      'maxSoftWorsen': trained.maxSoftWorsen,
    },
    'metrics': trained.metrics.toJson(),
  };

  File(config.outJsonPath)
    ..createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(modelJson));

  final dartSource = _renderDartProfile(
    trained: trained,
    logsUsed: parsedLogs,
    samplesUsed: dataset.length,
    trainedAtIso: modelJson['trainedAtIso'] as String,
  );
  File(config.outDartPath)
    ..createSync(recursive: true)
    ..writeAsStringSync(dartSource);

  stdout.writeln('=== MOI MODEL TRAINER ===');
  stdout.writeln('logs: $parsedLogs/${files.length}');
  stdout.writeln('samples: ${dataset.length}');
  stdout.writeln(
    'train acc=${(trained.metrics.trainAccuracy * 100).toStringAsFixed(1)}% '
    'test acc=${(trained.metrics.testAccuracy * 100).toStringAsFixed(1)}%',
  );
  stdout.writeln(
    'keepThreshold=${trained.keepThreshold.toStringAsFixed(3)} '
    'forceDiscardThreshold=${trained.forceDiscardThreshold.toStringAsFixed(3)} '
    'maxSoftWorsen=${trained.maxSoftWorsen}',
  );
  stdout.writeln('wrote: ${config.outJsonPath}');
  stdout.writeln('wrote: ${config.outDartPath}');
}

class _CliConfig {
  final String logDir;
  final String outJsonPath;
  final String outDartPath;
  final bool showHelp;

  const _CliConfig({
    required this.logDir,
    required this.outJsonPath,
    required this.outDartPath,
    required this.showHelp,
  });

  static _CliConfig fromArgs(List<String> args) {
    String readArg(String name, String fallback) {
      final prefix = '$name=';
      for (final arg in args) {
        if (arg.startsWith(prefix)) {
          return arg.substring(prefix.length);
        }
      }
      return fallback;
    }

    final showHelp = args.contains('-h') || args.contains('--help');
    return _CliConfig(
      logDir: readArg('--log-dir', '/Users/maxmbey/Downloads'),
      outJsonPath: readArg('--out-json', 'tmp/moi_ml_profile.json'),
      outDartPath: readArg(
        '--out-dart',
        'lib/services/game/bot/moi_ml_profile.dart',
      ),
      showHelp: showHelp,
    );
  }
}

void _printHelp() {
  stdout.writeln('''
Usage:
  dart run tool/train_moi_model_from_logs.dart \\
    [--log-dir=/Users/maxmbey/Downloads] \\
    [--out-json=tmp/moi_ml_profile.json] \\
    [--out-dart=lib/services/game/bot/moi_ml_profile.dart]
''');
}

List<File> _discoverLogFiles(String logDir) {
  final dir = Directory(logDir);
  if (!dir.existsSync()) return const <File>[];
  final files = dir
      .listSync(followLinks: false)
      .whereType<File>()
      .where((f) => f.path.contains('/game_') && f.path.endsWith('.log'))
      .toList(growable: false);
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

class _TurnContext {
  final int turnIndex;
  final int preTurnScore;
  final int handSize;
  final int worstCardPoints;

  const _TurnContext({
    required this.turnIndex,
    required this.preTurnScore,
    required this.handSize,
    required this.worstCardPoints,
  });
}

class _PendingDecision {
  final int turnIndex;
  final int preTurnScore;
  final int startHandScore;
  final int handSize;
  final int worstCardPoints;
  final int drawnPoints;
  final bool isPowerCard;
  final int powersUsedBefore;

  const _PendingDecision({
    required this.turnIndex,
    required this.preTurnScore,
    required this.startHandScore,
    required this.handSize,
    required this.worstCardPoints,
    required this.drawnPoints,
    required this.isPowerCard,
    required this.powersUsedBefore,
  });
}

class _Sample {
  final int drawnPoints;
  final int improvement;
  final int preTurnScore;
  final int startHandScore;
  final int handSize;
  final int turnIndex;
  final int powersUsed;
  final bool isPowerCard;
  final int labelKeep;

  const _Sample({
    required this.drawnPoints,
    required this.improvement,
    required this.preTurnScore,
    required this.startHandScore,
    required this.handSize,
    required this.turnIndex,
    required this.powersUsed,
    required this.isPowerCard,
    required this.labelKeep,
  });
}

List<_Sample> _parseLogFile(File file) {
  final lines = file.readAsLinesSync();
  final samples = <_Sample>[];

  bool inInitialHands = false;
  int? startHandScore;
  int powersUsed = 0;

  _TurnContext? currentTurn;
  _PendingDecision? pending;

  final turnRegExp = RegExp(r'^\s*┌─── Tour (\d+): Vous ───┐');
  final mainRegExp =
      RegExp(r'^\s*│ Main réelle:\s*\[(.*)\]\s*=\s*(-?\d+)\s*pts');
  final drawRegExp =
      RegExp(r'^\s*→ Vous pioche ([^\s(]+)\((-?\d+)\)\s+\(PIOCHE\)');
  final exchangeRegExp = RegExp(
    r'^\s*→ Vous ÉCHANGE position (\d+): .*gain:\s*(-?\d+)\s*pts\)',
  );
  final discardRegExp = RegExp(r'^\s*→ Vous défausse ');
  final initialYouRegExp = RegExp(r'^\s*Vous:\s*\[.*\]\s*=\s*(-?\d+)\s*pts');

  for (final rawLine in lines) {
    final line = rawLine.trimRight();

    if (line.contains('Mains initiales:')) {
      inInitialHands = true;
      continue;
    }
    if (inInitialHands) {
      if (line.trim().isEmpty) {
        inInitialHands = false;
      } else if (startHandScore == null) {
        final m = initialYouRegExp.firstMatch(line);
        if (m != null) {
          startHandScore = int.parse(m.group(1)!);
        }
      }
    }

    if (line.startsWith('  ⚡ Vous ')) {
      powersUsed++;
      continue;
    }

    final turnMatch = turnRegExp.firstMatch(line);
    if (turnMatch != null) {
      pending = null;
      final turnIdx = int.parse(turnMatch.group(1)!);
      currentTurn = _TurnContext(
        turnIndex: turnIdx,
        preTurnScore: 0,
        handSize: 0,
        worstCardPoints: 0,
      );
      continue;
    }

    if (currentTurn != null) {
      final mainMatch = mainRegExp.firstMatch(line);
      if (mainMatch != null) {
        final handRaw = mainMatch.group(1)!;
        final preTurnScore = int.parse(mainMatch.group(2)!);
        final points = RegExp(r'\((-?\d+)\)')
            .allMatches(handRaw)
            .map((m) => int.parse(m.group(1)!))
            .toList(growable: false);
        final handSize = points.length;
        final worst =
            points.isEmpty ? 0 : points.reduce((a, b) => a > b ? a : b);

        currentTurn = _TurnContext(
          turnIndex: currentTurn.turnIndex,
          preTurnScore: preTurnScore,
          handSize: handSize,
          worstCardPoints: worst,
        );
        continue;
      }
    }

    final drawMatch = drawRegExp.firstMatch(line);
    if (drawMatch != null && currentTurn != null && currentTurn.handSize > 0) {
      final cardToken = drawMatch.group(1)!;
      final drawnPoints = int.parse(drawMatch.group(2)!);
      final value = _extractCardValue(cardToken);
      pending = _PendingDecision(
        turnIndex: currentTurn.turnIndex,
        preTurnScore: currentTurn.preTurnScore,
        startHandScore: startHandScore ?? currentTurn.preTurnScore,
        handSize: currentTurn.handSize,
        worstCardPoints: currentTurn.worstCardPoints,
        drawnPoints: drawnPoints,
        isPowerCard: _isPowerCardValue(value),
        powersUsedBefore: powersUsed,
      );
      continue;
    }

    if (pending != null) {
      final exchangeMatch = exchangeRegExp.firstMatch(line);
      if (exchangeMatch != null) {
        final improvement = pending.worstCardPoints - pending.drawnPoints;
        samples.add(
          _Sample(
            drawnPoints: pending.drawnPoints,
            improvement: improvement,
            preTurnScore: pending.preTurnScore,
            startHandScore: pending.startHandScore,
            handSize: pending.handSize,
            turnIndex: pending.turnIndex,
            powersUsed: pending.powersUsedBefore,
            isPowerCard: pending.isPowerCard,
            labelKeep: 1,
          ),
        );
        pending = null;
        continue;
      }
      if (discardRegExp.hasMatch(line)) {
        final improvement = pending.worstCardPoints - pending.drawnPoints;
        samples.add(
          _Sample(
            drawnPoints: pending.drawnPoints,
            improvement: improvement,
            preTurnScore: pending.preTurnScore,
            startHandScore: pending.startHandScore,
            handSize: pending.handSize,
            turnIndex: pending.turnIndex,
            powersUsed: pending.powersUsedBefore,
            isPowerCard: pending.isPowerCard,
            labelKeep: 0,
          ),
        );
        pending = null;
        continue;
      }
    }
  }

  return samples;
}

String _extractCardValue(String token) {
  const suits = ['hearts', 'diamonds', 'spades', 'clubs'];
  for (final suit in suits) {
    if (token.endsWith(suit)) {
      return token.substring(0, token.length - suit.length);
    }
  }
  return token;
}

bool _isPowerCardValue(String value) {
  return value == '7' || value == '10' || value == 'V' || value == 'JOKER';
}

class _TrainedModel {
  final _Weights weights;
  final double keepThreshold;
  final double forceDiscardThreshold;
  final int maxSoftWorsen;
  final _Metrics metrics;

  const _TrainedModel({
    required this.weights,
    required this.keepThreshold,
    required this.forceDiscardThreshold,
    required this.maxSoftWorsen,
    required this.metrics,
  });
}

class _Weights {
  final double bias;
  final double wDrawnPoints;
  final double wImprovement;
  final double wPreTurnScore;
  final double wStartHandScore;
  final double wHandSize;
  final double wTurnIndex;
  final double wPowersUsed;
  final double wPowerCard;

  const _Weights({
    required this.bias,
    required this.wDrawnPoints,
    required this.wImprovement,
    required this.wPreTurnScore,
    required this.wStartHandScore,
    required this.wHandSize,
    required this.wTurnIndex,
    required this.wPowersUsed,
    required this.wPowerCard,
  });

  Map<String, dynamic> toJson() => {
        'bias': bias,
        'wDrawnPoints': wDrawnPoints,
        'wImprovement': wImprovement,
        'wPreTurnScore': wPreTurnScore,
        'wStartHandScore': wStartHandScore,
        'wHandSize': wHandSize,
        'wTurnIndex': wTurnIndex,
        'wPowersUsed': wPowersUsed,
        'wPowerCard': wPowerCard,
      };
}

class _Metrics {
  final double trainAccuracy;
  final double testAccuracy;
  final int trainCount;
  final int testCount;

  const _Metrics({
    required this.trainAccuracy,
    required this.testAccuracy,
    required this.trainCount,
    required this.testCount,
  });

  Map<String, dynamic> toJson() => {
        'trainAccuracy': trainAccuracy,
        'testAccuracy': testAccuracy,
        'trainCount': trainCount,
        'testCount': testCount,
      };
}

_TrainedModel _trainModel(List<_Sample> all) {
  final shuffled = List<_Sample>.from(all);
  shuffled.shuffle(math.Random(42));

  final split = (shuffled.length * 0.8).round().clamp(1, shuffled.length - 1);
  final train = shuffled.sublist(0, split);
  final test = shuffled.sublist(split);

  double bias = 0;
  double wDrawn = 0;
  double wImprove = 0;
  double wPre = 0;
  double wStart = 0;
  double wHand = 0;
  double wTurn = 0;
  double wPowers = 0;
  double wPowerCard = 0;

  double lr = 0.12;
  const l2 = 0.0008;
  for (int epoch = 0; epoch < 1800; epoch++) {
    double gBias = 0;
    double gDrawn = 0;
    double gImprove = 0;
    double gPre = 0;
    double gStart = 0;
    double gHand = 0;
    double gTurn = 0;
    double gPowers = 0;
    double gPowerCard = 0;

    for (final s in train) {
      final x = _features(s);
      final z = bias +
          (wDrawn * x[0]) +
          (wImprove * x[1]) +
          (wPre * x[2]) +
          (wStart * x[3]) +
          (wHand * x[4]) +
          (wTurn * x[5]) +
          (wPowers * x[6]) +
          (wPowerCard * x[7]);
      final p = _sigmoid(z);
      final err = p - s.labelKeep;

      gBias += err;
      gDrawn += err * x[0];
      gImprove += err * x[1];
      gPre += err * x[2];
      gStart += err * x[3];
      gHand += err * x[4];
      gTurn += err * x[5];
      gPowers += err * x[6];
      gPowerCard += err * x[7];
    }

    final n = train.length.toDouble();
    bias -= lr * (gBias / n);
    wDrawn -= lr * ((gDrawn / n) + (l2 * wDrawn));
    wImprove -= lr * ((gImprove / n) + (l2 * wImprove));
    wPre -= lr * ((gPre / n) + (l2 * wPre));
    wStart -= lr * ((gStart / n) + (l2 * wStart));
    wHand -= lr * ((gHand / n) + (l2 * wHand));
    wTurn -= lr * ((gTurn / n) + (l2 * wTurn));
    wPowers -= lr * ((gPowers / n) + (l2 * wPowers));
    wPowerCard -= lr * ((gPowerCard / n) + (l2 * wPowerCard));

    if ((epoch + 1) % 300 == 0) {
      lr *= 0.86;
    }
  }

  final weights = _Weights(
    bias: bias,
    wDrawnPoints: wDrawn,
    wImprovement: wImprove,
    wPreTurnScore: wPre,
    wStartHandScore: wStart,
    wHandSize: wHand,
    wTurnIndex: wTurn,
    wPowersUsed: wPowers,
    wPowerCard: wPowerCard,
  );

  final trainThreshold = _bestThreshold(train, weights);
  final trainAcc = _accuracy(train, weights, trainThreshold);
  final testAcc = _accuracy(test, weights, trainThreshold);

  final keepNegativeImprovements = all
      .where((s) => s.labelKeep == 1 && s.improvement < 0)
      .map((s) => -s.improvement)
      .toList(growable: false);
  int maxSoftWorsen = 0;
  if (keepNegativeImprovements.isNotEmpty) {
    keepNegativeImprovements.sort();
    final idx = (keepNegativeImprovements.length * 0.7).floor().clamp(
          0,
          keepNegativeImprovements.length - 1,
        );
    maxSoftWorsen = keepNegativeImprovements[idx].clamp(0, 2);
  }

  final forceDiscardThreshold = math.max(0.12, trainThreshold - 0.28);
  return _TrainedModel(
    weights: weights,
    keepThreshold: trainThreshold,
    forceDiscardThreshold: forceDiscardThreshold,
    maxSoftWorsen: maxSoftWorsen,
    metrics: _Metrics(
      trainAccuracy: trainAcc,
      testAccuracy: testAcc,
      trainCount: train.length,
      testCount: test.length,
    ),
  );
}

List<double> _features(_Sample s) {
  final xDrawn = _normalize(s.drawnPoints.toDouble(), 0, 13);
  final xImprove = _normalize(s.improvement.toDouble(), -13, 13);
  final xPre = _normalize(s.preTurnScore.toDouble(), 0, 45);
  final xStart = _normalize(s.startHandScore.toDouble(), 0, 45);
  final xHand = _normalize(s.handSize.toDouble(), 1, 6);
  final xTurn = _normalize(s.turnIndex.toDouble(), 0, 15);
  final xPowerUses = _normalize(s.powersUsed.toDouble(), 0, 8);
  final xPowerCard = s.isPowerCard ? 1.0 : 0.0;
  return [xDrawn, xImprove, xPre, xStart, xHand, xTurn, xPowerUses, xPowerCard];
}

double _predict(_Sample s, _Weights w) {
  final x = _features(s);
  final z = w.bias +
      (w.wDrawnPoints * x[0]) +
      (w.wImprovement * x[1]) +
      (w.wPreTurnScore * x[2]) +
      (w.wStartHandScore * x[3]) +
      (w.wHandSize * x[4]) +
      (w.wTurnIndex * x[5]) +
      (w.wPowersUsed * x[6]) +
      (w.wPowerCard * x[7]);
  return _sigmoid(z);
}

double _bestThreshold(List<_Sample> train, _Weights w) {
  double bestThreshold = 0.5;
  double bestScore = -1;
  for (double t = 0.30; t <= 0.80; t += 0.01) {
    int tp = 0, tn = 0, fp = 0, fn = 0;
    for (final s in train) {
      final p = _predict(s, w);
      final pred = p >= t ? 1 : 0;
      if (pred == 1 && s.labelKeep == 1) tp++;
      if (pred == 0 && s.labelKeep == 0) tn++;
      if (pred == 1 && s.labelKeep == 0) fp++;
      if (pred == 0 && s.labelKeep == 1) fn++;
    }
    final tpr = tp + fn == 0 ? 0.0 : tp / (tp + fn);
    final tnr = tn + fp == 0 ? 0.0 : tn / (tn + fp);
    final balanced = (tpr + tnr) / 2.0;
    if (balanced > bestScore) {
      bestScore = balanced;
      bestThreshold = t;
    }
  }
  return bestThreshold;
}

double _accuracy(List<_Sample> samples, _Weights w, double threshold) {
  if (samples.isEmpty) return 0.0;
  int ok = 0;
  for (final s in samples) {
    final p = _predict(s, w);
    final pred = p >= threshold ? 1 : 0;
    if (pred == s.labelKeep) ok++;
  }
  return ok / samples.length;
}

double _normalize(double value, double minValue, double maxValue) {
  if (maxValue <= minValue) return 0;
  final v = value.clamp(minValue, maxValue);
  return ((v - minValue) / (maxValue - minValue)).toDouble();
}

double _sigmoid(double x) {
  return 1.0 / (1.0 + math.exp(-x));
}

String _renderDartProfile({
  required _TrainedModel trained,
  required int logsUsed,
  required int samplesUsed,
  required String trainedAtIso,
}) {
  String d(double v) => v.toStringAsFixed(10);

  return '''
import 'dart:math' as math;

/// Profil ML leger du comportement `moi`.
///
/// Ce fichier est mis a jour par `tool/train_moi_model_from_logs.dart`.
class MoiMlProfile {
  const MoiMlProfile._();

  static const bool enabled = true;

  static const int logsUsed = $logsUsed;
  static const int samplesUsed = $samplesUsed;
  static const String trainedAtIso = '$trainedAtIso';

  static const double _wBias = ${d(trained.weights.bias)};
  static const double _wDrawnPoints = ${d(trained.weights.wDrawnPoints)};
  static const double _wImprovement = ${d(trained.weights.wImprovement)};
  static const double _wPreTurnScore = ${d(trained.weights.wPreTurnScore)};
  static const double _wStartHandScore = ${d(trained.weights.wStartHandScore)};
  static const double _wHandSize = ${d(trained.weights.wHandSize)};
  static const double _wTurnIndex = ${d(trained.weights.wTurnIndex)};
  static const double _wPowersUsed = ${d(trained.weights.wPowersUsed)};
  static const double _wPowerCard = ${d(trained.weights.wPowerCard)};

  static final double keepThreshold = _doubleFromEnv(
    const String.fromEnvironment('MOI_ML_KEEP_THRESHOLD', defaultValue: ''),
    ${d(trained.keepThreshold)},
  );
  static final double forceDiscardThreshold = _doubleFromEnv(
    const String.fromEnvironment('MOI_ML_FORCE_DISCARD_THRESHOLD', defaultValue: ''),
    ${d(trained.forceDiscardThreshold)},
  );
  static final int maxSoftWorsen = _intFromEnv(
    const String.fromEnvironment('MOI_ML_MAX_SOFT_WORSEN', defaultValue: ''),
    ${trained.maxSoftWorsen},
  ).clamp(0, 4);

  static bool isPowerCardValue(String value) {
    return value == '7' || value == '10' || value == 'V' || value == 'JOKER';
  }

  static double predictKeepProbability({
    required int drawnPoints,
    required int improvement,
    required int preTurnScore,
    required int startHandScore,
    required int handSize,
    required int turnIndex,
    required int powersUsed,
    required bool isPowerCard,
  }) {
    final xDrawn = _normalize(drawnPoints.toDouble(), 0, 13);
    final xImprovement = _normalize(improvement.toDouble(), -13, 13);
    final xPreTurnScore = _normalize(preTurnScore.toDouble(), 0, 45);
    final xStartHandScore = _normalize(startHandScore.toDouble(), 0, 45);
    final xHandSize = _normalize(handSize.toDouble(), 1, 6);
    final xTurn = _normalize(turnIndex.toDouble(), 0, 15);
    final xPowers = _normalize(powersUsed.toDouble(), 0, 8);
    final xPowerCard = isPowerCard ? 1.0 : 0.0;

    final z = _wBias +
        (_wDrawnPoints * xDrawn) +
        (_wImprovement * xImprovement) +
        (_wPreTurnScore * xPreTurnScore) +
        (_wStartHandScore * xStartHandScore) +
        (_wHandSize * xHandSize) +
        (_wTurnIndex * xTurn) +
        (_wPowersUsed * xPowers) +
        (_wPowerCard * xPowerCard);
    return _sigmoid(z);
  }

  static int softWorsenTolerance({
    required int startHandScore,
    required int powersUsed,
    required bool isPowerCard,
  }) {
    int tolerance = 0;
    if (startHandScore >= 28) tolerance += 1;
    if (powersUsed >= 2) tolerance += 1;
    if (isPowerCard) tolerance += 1;
    if (tolerance > maxSoftWorsen) return maxSoftWorsen;
    return tolerance;
  }

  static double _normalize(double value, double minValue, double maxValue) {
    if (maxValue <= minValue) return 0.0;
    final clamped = value.clamp(minValue, maxValue);
    return ((clamped - minValue) / (maxValue - minValue)).toDouble();
  }

  static double _sigmoid(double x) {
    return 1.0 / (1.0 + math.exp(-x));
  }

  static int _intFromEnv(String raw, int fallback) {
    if (raw.isEmpty) return fallback;
    return int.tryParse(raw) ?? fallback;
  }

  static double _doubleFromEnv(String raw, double fallback) {
    if (raw.isEmpty) return fallback;
    return double.tryParse(raw) ?? fallback;
  }
}
''';
}
