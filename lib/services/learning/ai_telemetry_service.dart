import 'dart:math' as math;

/// Service de télémétrie AI invisible pour calibrer le SBMM automatiquement.
/// 
/// Collecte 3 métriques clés par bot et par partie :
/// - **leadConfidence** : à quel point le bot pense gagner (0..1)
/// - **sandbagTurns** : combien de Dutch gagnants retardés volontairement
/// - **powerImpact** : impact des pouvoirs sur l'avantage de table
class AiTelemetryService {
  static final AiTelemetryService _instance = AiTelemetryService._internal();
  factory AiTelemetryService() => _instance;
  AiTelemetryService._internal();

  final Map<String, BotTelemetry> _bots = {};
  int _totalActions = 0;
  int _playerCount = 2;
  DateTime? _gameStart;

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALISATION / RESET
  // ═══════════════════════════════════════════════════════════════════════════

  /// Réinitialise la télémétrie pour une nouvelle partie
  void startGame({required int playerCount}) {
    _bots.clear();
    _totalActions = 0;
    _playerCount = playerCount;
    _gameStart = DateTime.now();
  }

  /// Récupère ou crée la télémétrie d'un bot
  BotTelemetry bot(String botId) => 
      _bots.putIfAbsent(botId, () => BotTelemetry(botId: botId));

  // ═══════════════════════════════════════════════════════════════════════════
  // HOOKS DE COLLECTE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Enregistre un échantillon de leadConfidence (appelé à chaque tour bot)
  void onLeadSample(String botId, double leadConfidence) {
    bot(botId).leadSamples.add(leadConfidence.clamp(0.0, 1.0));
  }

  /// Enregistre un sandbag (Dutch refusé volontairement)
  void onSandbag(String botId, double leadConfidence) {
    final b = bot(botId);
    b.sandbagTurns++;
    b.sandbagLeadSamples.add(leadConfidence.clamp(0.0, 1.0));
  }

  /// Enregistre l'utilisation d'un pouvoir avec son impact
  void onPowerUsed(String botId, String powerName, double impactDelta) {
    final b = bot(botId);
    b.powerUses++;
    b.powerImpactTotal += impactDelta;
    b.powerImpactByType.update(
      powerName, 
      (v) => v + impactDelta, 
      ifAbsent: () => impactDelta,
    );
  }

  /// Enregistre une action (pour le pacing)
  void onAction() {
    _totalActions++;
  }

  /// Enregistre un Dutch appelé
  void onDutchCalled(String botId, double leadConfidence, int cardsInHand) {
    final b = bot(botId);
    b.dutchCalled = true;
    b.dutchLeadConfidence = leadConfidence;
    b.dutchCardsInHand = cardsInHand;
  }

  /// Enregistre un match tenté
  void onMatchAttempt(String botId, {required bool success, required double probability}) {
    final b = bot(botId);
    b.matchAttempts++;
    if (success) b.matchSuccesses++;
    b.matchProbabilities.add(probability);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CALCULS ET RÉSUMÉ
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calcule la leadConfidence avec sigmoid
  static double calculateLeadConfidence({
    required double myExpectedScore,
    required double bestOpponentExpectedScore,
  }) {
    final margin = bestOpponentExpectedScore - myExpectedScore; // positif = bot ahead
    return _sigmoid(margin / 4.0);
  }

  /// Fonction sigmoid pour normaliser entre 0 et 1
  static double _sigmoid(double x) => 1.0 / (1.0 + math.exp(-x));

  /// Génère un résumé de la télémétrie de la partie
  AiTelemetrySummary summarize({
    required bool playerWon,
    required String? winnerId,
  }) {
    final duration = _gameStart != null 
        ? DateTime.now().difference(_gameStart!) 
        : Duration.zero;

    final botSummaries = _bots.values.map((b) => b.summarize()).toList();
    
    // Calculs agrégés
    double totalPowerImpact = 0;
    int totalPowerUses = 0;
    int totalSandbagTurns = 0;
    double avgLeadConfidence = 0;
    int leadSampleCount = 0;

    for (final bot in _bots.values) {
      totalPowerImpact += bot.powerImpactTotal;
      totalPowerUses += bot.powerUses;
      totalSandbagTurns += bot.sandbagTurns;
      avgLeadConfidence += bot.leadSamples.fold(0.0, (a, b) => a + b);
      leadSampleCount += bot.leadSamples.length;
    }

    if (leadSampleCount > 0) {
      avgLeadConfidence /= leadSampleCount;
    }

    final meanPowerImpactPerUse = totalPowerUses > 0 
        ? totalPowerImpact / totalPowerUses 
        : 0.0;

    // Target pacing : 22 + 3*(players-2)
    final targetActions = 22 + 3 * (_playerCount - 2);
    final pacingDelta = _totalActions - targetActions;

    return AiTelemetrySummary(
      playerWon: playerWon,
      winnerId: winnerId,
      totalActions: _totalActions,
      targetActions: targetActions,
      pacingDelta: pacingDelta,
      gameDuration: duration,
      playerCount: _playerCount,
      botSummaries: botSummaries,
      avgLeadConfidence: avgLeadConfidence,
      totalSandbagTurns: totalSandbagTurns,
      totalPowerUses: totalPowerUses,
      totalPowerImpact: totalPowerImpact,
      meanPowerImpactPerUse: meanPowerImpactPerUse,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS POUR DEBUG
  // ═══════════════════════════════════════════════════════════════════════════

  int get totalActions => _totalActions;
  int get playerCount => _playerCount;
  Map<String, BotTelemetry> get bots => Map.unmodifiable(_bots);
}

// ═════════════════════════════════════════════════════════════════════════════
// TÉLÉMÉTRIE PAR BOT
// ═════════════════════════════════════════════════════════════════════════════

/// Données de télémétrie collectées pour un bot pendant une partie
class BotTelemetry {
  final String botId;
  
  // Lead confidence samples
  final List<double> leadSamples = [];
  
  // Sandbagging
  int sandbagTurns = 0;
  final List<double> sandbagLeadSamples = [];
  
  // Power usage
  int powerUses = 0;
  double powerImpactTotal = 0;
  final Map<String, double> powerImpactByType = {};
  
  // Dutch info
  bool dutchCalled = false;
  double dutchLeadConfidence = 0;
  int dutchCardsInHand = 4;
  
  // Match attempts
  int matchAttempts = 0;
  int matchSuccesses = 0;
  final List<double> matchProbabilities = [];

  BotTelemetry({required this.botId});

  /// Génère un résumé pour ce bot
  BotTelemetrySummary summarize() {
    final avgLead = leadSamples.isNotEmpty 
        ? leadSamples.reduce((a, b) => a + b) / leadSamples.length 
        : 0.5;
    
    final avgSandbagLead = sandbagLeadSamples.isNotEmpty 
        ? sandbagLeadSamples.reduce((a, b) => a + b) / sandbagLeadSamples.length 
        : 0.0;

    final meanPowerImpact = powerUses > 0 
        ? powerImpactTotal / powerUses 
        : 0.0;

    final matchRate = matchAttempts > 0 
        ? matchSuccesses / matchAttempts 
        : 0.0;

    final avgMatchProb = matchProbabilities.isNotEmpty 
        ? matchProbabilities.reduce((a, b) => a + b) / matchProbabilities.length 
        : 0.0;

    return BotTelemetrySummary(
      botId: botId,
      avgLeadConfidence: avgLead,
      sandbagTurns: sandbagTurns,
      avgSandbagLeadConfidence: avgSandbagLead,
      powerUses: powerUses,
      powerImpactTotal: powerImpactTotal,
      meanPowerImpact: meanPowerImpact,
      powerImpactByType: Map.from(powerImpactByType),
      dutchCalled: dutchCalled,
      dutchLeadConfidence: dutchLeadConfidence,
      dutchCardsInHand: dutchCardsInHand,
      matchAttempts: matchAttempts,
      matchSuccesses: matchSuccesses,
      matchRate: matchRate,
      avgMatchProbability: avgMatchProb,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// RÉSUMÉS (pour export/stockage)
// ═════════════════════════════════════════════════════════════════════════════

/// Résumé de télémétrie pour un bot
class BotTelemetrySummary {
  final String botId;
  final double avgLeadConfidence;
  final int sandbagTurns;
  final double avgSandbagLeadConfidence;
  final int powerUses;
  final double powerImpactTotal;
  final double meanPowerImpact;
  final Map<String, double> powerImpactByType;
  final bool dutchCalled;
  final double dutchLeadConfidence;
  final int dutchCardsInHand;
  final int matchAttempts;
  final int matchSuccesses;
  final double matchRate;
  final double avgMatchProbability;

  const BotTelemetrySummary({
    required this.botId,
    required this.avgLeadConfidence,
    required this.sandbagTurns,
    required this.avgSandbagLeadConfidence,
    required this.powerUses,
    required this.powerImpactTotal,
    required this.meanPowerImpact,
    required this.powerImpactByType,
    required this.dutchCalled,
    required this.dutchLeadConfidence,
    required this.dutchCardsInHand,
    required this.matchAttempts,
    required this.matchSuccesses,
    required this.matchRate,
    required this.avgMatchProbability,
  });

  Map<String, dynamic> toJson() => {
    'botId': botId,
    'avgLeadConfidence': avgLeadConfidence,
    'sandbagTurns': sandbagTurns,
    'avgSandbagLeadConfidence': avgSandbagLeadConfidence,
    'powerUses': powerUses,
    'powerImpactTotal': powerImpactTotal,
    'meanPowerImpact': meanPowerImpact,
    'powerImpactByType': powerImpactByType,
    'dutchCalled': dutchCalled,
    'dutchLeadConfidence': dutchLeadConfidence,
    'dutchCardsInHand': dutchCardsInHand,
    'matchAttempts': matchAttempts,
    'matchSuccesses': matchSuccesses,
    'matchRate': matchRate,
    'avgMatchProbability': avgMatchProbability,
  };
}

/// Résumé global de télémétrie pour une partie
class AiTelemetrySummary {
  final bool playerWon;
  final String? winnerId;
  final int totalActions;
  final int targetActions;
  final int pacingDelta;
  final Duration gameDuration;
  final int playerCount;
  final List<BotTelemetrySummary> botSummaries;
  final double avgLeadConfidence;
  final int totalSandbagTurns;
  final int totalPowerUses;
  final double totalPowerImpact;
  final double meanPowerImpactPerUse;

  const AiTelemetrySummary({
    required this.playerWon,
    required this.winnerId,
    required this.totalActions,
    required this.targetActions,
    required this.pacingDelta,
    required this.gameDuration,
    required this.playerCount,
    required this.botSummaries,
    required this.avgLeadConfidence,
    required this.totalSandbagTurns,
    required this.totalPowerUses,
    required this.totalPowerImpact,
    required this.meanPowerImpactPerUse,
  });

  /// Indique si le pacing est trop rapide
  bool get isTooFast => pacingDelta < -6;

  /// Indique si le pacing est trop lent
  bool get isTooSlow => pacingDelta > 8;

  /// Indique si les pouvoirs sont bien utilisés
  bool get powersAreEffective => meanPowerImpactPerUse >= 0.05;

  /// Indique si le sandbagging est excessif
  bool get excessiveSandbagging => totalSandbagTurns > 3;

  Map<String, dynamic> toJson() => {
    'playerWon': playerWon,
    'winnerId': winnerId,
    'totalActions': totalActions,
    'targetActions': targetActions,
    'pacingDelta': pacingDelta,
    'gameDurationMs': gameDuration.inMilliseconds,
    'playerCount': playerCount,
    'botSummaries': botSummaries.map((b) => b.toJson()).toList(),
    'avgLeadConfidence': avgLeadConfidence,
    'totalSandbagTurns': totalSandbagTurns,
    'totalPowerUses': totalPowerUses,
    'totalPowerImpact': totalPowerImpact,
    'meanPowerImpactPerUse': meanPowerImpactPerUse,
    'isTooFast': isTooFast,
    'isTooSlow': isTooSlow,
    'powersAreEffective': powersAreEffective,
    'excessiveSandbagging': excessiveSandbagging,
  };

  @override
  String toString() => '''
AiTelemetrySummary:
  playerWon: $playerWon
  actions: $totalActions (target: $targetActions, delta: $pacingDelta)
  pacing: ${isTooFast ? 'TOO FAST' : isTooSlow ? 'TOO SLOW' : 'OK'}
  sandbagTurns: $totalSandbagTurns${excessiveSandbagging ? ' (EXCESSIVE)' : ''}
  powerUses: $totalPowerUses, impact: ${totalPowerImpact.toStringAsFixed(2)}
  meanPowerImpact: ${meanPowerImpactPerUse.toStringAsFixed(3)} ${powersAreEffective ? '✓' : '✗'}
''';
}
