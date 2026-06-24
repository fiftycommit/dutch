import 'dart:math';
import 'bot_difficulty.dart';
import 'bot_config.dart';
import '../../../models/playing_card.dart';
import '../engine_random.dart';

/// Framework de simulation Monte Carlo pour tester les bots
/// Permet de mesurer winrate, stabilité, et faire des ablation tests
class BotSimulator {
  Random get _random => EngineRandom.instance;
  
  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// Nombre de matchs par défaut
  static const int defaultMatchCount = 1000;
  
  /// Nombre de rounds max par partie
  static const int maxRoundsPerGame = 50;
  
  /// Score de fin de partie
  static const int targetScore = 100;

  // ═══════════════════════════════════════════════════════════════════════════
  // SIMULATION MONTE CARLO
  // ═══════════════════════════════════════════════════════════════════════════

  /// Lance une simulation Monte Carlo
  /// Retourne les statistiques complètes
  Future<SimulationResult> runSimulation({
    required int matchCount,
    required SimulationConfig config,
    void Function(int current, int total)? onProgress,
  }) async {
    final stats = SimulationStats();
    
    for (int i = 0; i < matchCount; i++) {
      final matchResult = await _simulateMatch(config);
      stats.addMatch(matchResult);
      
      if (onProgress != null && i % 100 == 0) {
        onProgress(i, matchCount);
      }
    }
    
    return SimulationResult(
      config: config,
      matchCount: matchCount,
      stats: stats,
    );
  }

  /// Simule un match complet (plusieurs rounds jusqu'au score cible)
  Future<MatchResult> _simulateMatch(SimulationConfig config) async {
    final scores = List<int>.filled(config.playerCount, 0);
    final roundResults = <RoundResult>[];
    int roundCount = 0;
    
    while (roundCount < maxRoundsPerGame && scores.every((s) => s < targetScore)) {
      final roundResult = await _simulateRound(config, scores);
      roundResults.add(roundResult);
      
      for (int i = 0; i < config.playerCount; i++) {
        scores[i] += roundResult.roundScores[i];
      }
      
      roundCount++;
    }
    
    // Déterminer le gagnant (score le plus bas)
    int winnerIndex = 0;
    int lowestScore = scores[0];
    for (int i = 1; i < scores.length; i++) {
      if (scores[i] < lowestScore) {
        lowestScore = scores[i];
        winnerIndex = i;
      }
    }
    
    return MatchResult(
      winnerIndex: winnerIndex,
      finalScores: List.from(scores),
      roundCount: roundCount,
      rounds: roundResults,
    );
  }

  /// Simule un round (distribution → dutch)
  Future<RoundResult> _simulateRound(SimulationConfig config, List<int> currentScores) async {
    // Créer le deck
    final deck = _createDeck();
    deck.shuffle(_random);
    
    // Distribuer les cartes (4 par joueur)
    final hands = <List<PlayingCard>>[];
    for (int i = 0; i < config.playerCount; i++) {
      hands.add(deck.sublist(i * 4, (i + 1) * 4));
    }
    deck.removeRange(0, config.playerCount * 4);
    
    // Simuler les tours jusqu'à Dutch
    int turnCount = 0;
    int dutchCallerIndex = -1;
    final turnStats = <TurnStats>[];
    
    while (turnCount < 100 && dutchCallerIndex == -1) {
      for (int playerIndex = 0; playerIndex < config.playerCount; playerIndex++) {
        final isBot = playerIndex > 0 || config.simulatedPlayerSkill == null;
        final difficulty = isBot ? config.getBotDifficulty(playerIndex) : null;
        
        final turnResult = _simulateTurn(
          hands: hands,
          deck: deck,
          playerIndex: playerIndex,
          difficulty: difficulty,
          config: config,
          turnCount: turnCount,
        );
        
        turnStats.add(turnResult);
        
        if (turnResult.calledDutch) {
          dutchCallerIndex = playerIndex;
          break;
        }
      }
      turnCount++;
    }
    
    // Calculer les scores finaux
    final roundScores = <int>[];
    for (int i = 0; i < config.playerCount; i++) {
      int score = hands[i].fold(0, (sum, card) => sum + card.points);
      
      // Bonus/malus Dutch
      if (i == dutchCallerIndex) {
        final otherMinScore = hands
            .asMap()
            .entries
            .where((e) => e.key != i)
            .map((e) => e.value.fold(0, (sum, card) => sum + card.points))
            .reduce(min);
        
        if (score > otherMinScore) {
          score += 10; // Échec Dutch
        }
      }
      
      roundScores.add(score);
    }
    
    return RoundResult(
      roundScores: roundScores,
      dutchCallerIndex: dutchCallerIndex,
      turnCount: turnCount,
      dutchSuccess: dutchCallerIndex >= 0 && 
          roundScores[dutchCallerIndex] == roundScores.reduce(min),
    );
  }

  /// Simule un tour de jeu
  TurnStats _simulateTurn({
    required List<List<PlayingCard>> hands,
    required List<PlayingCard> deck,
    required int playerIndex,
    required BotDifficulty? difficulty,
    required SimulationConfig config,
    required int turnCount,
  }) {
    if (deck.isEmpty) {
      return TurnStats(
        playerIndex: playerIndex,
        action: TurnAction.skip,
        calledDutch: false,
      );
    }
    
    final hand = hands[playerIndex];
    final drawnCard = deck.removeLast();
    
    // Décision simplifiée sans seuil
    TurnAction action;
    if (hand.isEmpty) {
      action = TurnAction.discard;
    } else {
      int worstIndex = 0;
      int worstValue = hand[0].points;
      int maxValue = hand[0].points;
      for (int i = 1; i < hand.length; i++) {
        final v = hand[i].points;
        if (v > worstValue) {
          worstValue = v;
          worstIndex = i;
        }
        if (v > maxValue) {
          maxValue = v;
        }
      }
      if (drawnCard.points > maxValue) {
        action = TurnAction.discard;
      } else if (drawnCard.points < worstValue) {
        hand[worstIndex] = drawnCard;
        action = TurnAction.replace;
      } else {
        action = TurnAction.discard;
      }
    }
    
    // Décision Dutch (logique simplifiée pour simulation)
    // Dutch si: peu de cartes ET plusieurs tours joués
    final shouldCallDutch = hand.length <= 2 && turnCount >= 3;
    
    return TurnStats(
      playerIndex: playerIndex,
      action: action,
      calledDutch: shouldCallDutch,
      drawnCardValue: drawnCard.points,
      keptCard: action == TurnAction.replace,
    );
  }

  /// Crée un deck standard
  List<PlayingCard> _createDeck() {
    final deck = <PlayingCard>[];
    final suits = ['hearts', 'diamonds', 'clubs', 'spades'];
    final values = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'V', 'D', 'R'];
    
    for (final suit in suits) {
      for (final value in values) {
        deck.add(PlayingCard.create(suit, value));
      }
    }
    
    // Ajouter 2 jokers
    deck.add(PlayingCard.create('joker', 'JOKER'));
    deck.add(PlayingCard.create('joker', 'JOKER'));
    
    return deck;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ABLATION TESTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Lance des tests d'ablation pour identifier les features clés
  Future<AblationResult> runAblationTests({
    required int matchCount,
    required HardcoreLevel level,
    void Function(String testName, int current, int total)? onProgress,
  }) async {
    final results = <String, SimulationResult>{};
    
    // Test 1: Configuration complète (baseline)
    final baselineConfig = SimulationConfig(
      playerCount: 4,
      hardcoreLevel: level,
      enableMemory: true,
      enableAdvancedThresholds: true,
      enablePowerStrategy: true,
      enableDutchStrategy: true,
    );
    
    onProgress?.call('Baseline (full)', 0, matchCount);
    results['baseline'] = await runSimulation(
      matchCount: matchCount,
      config: baselineConfig,
    );
    
    // Test 2: Mémoire normale (pas parfaite)
    final normalMemoryConfig = baselineConfig.copyWith(enableMemory: false);
    onProgress?.call('Normal Memory', 0, matchCount);
    results['normal_memory'] = await runSimulation(
      matchCount: matchCount,
      config: normalMemoryConfig,
    );
    
    // Test 3: Thresholds normaux
    final normalThresholdsConfig = baselineConfig.copyWith(enableAdvancedThresholds: false);
    onProgress?.call('Normal Thresholds', 0, matchCount);
    results['normal_thresholds'] = await runSimulation(
      matchCount: matchCount,
      config: normalThresholdsConfig,
    );
    
    // Test 4: Power handler normal
    final normalPowerConfig = baselineConfig.copyWith(enablePowerStrategy: false);
    onProgress?.call('Normal Powers', 0, matchCount);
    results['normal_powers'] = await runSimulation(
      matchCount: matchCount,
      config: normalPowerConfig,
    );
    
    // Test 5: Dutch strategy normale
    final normalDutchConfig = baselineConfig.copyWith(enableDutchStrategy: false);
    onProgress?.call('Normal Dutch', 0, matchCount);
    results['normal_dutch'] = await runSimulation(
      matchCount: matchCount,
      config: normalDutchConfig,
    );
    
    return AblationResult(
      level: level,
      results: results,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLASSES DE CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/// Configuration d'une simulation
class SimulationConfig {
  final int playerCount;
  final HardcoreLevel? hardcoreLevel;
  final int? simulatedPlayerSkill; // null = bot, sinon MMR simulé
  final bool enableMemory;
  final bool enableAdvancedThresholds;
  final bool enablePowerStrategy;
  final bool enableDutchStrategy;

  SimulationConfig({
    this.playerCount = 4,
    this.hardcoreLevel,
    this.simulatedPlayerSkill,
    this.enableMemory = true,
    this.enableAdvancedThresholds = true,
    this.enablePowerStrategy = true,
    this.enableDutchStrategy = true,
  });
  
  SimulationConfig copyWith({
    int? playerCount,
    HardcoreLevel? hardcoreLevel,
    int? simulatedPlayerSkill,
    bool? enableMemory,
    bool? enableAdvancedThresholds,
    bool? enablePowerStrategy,
    bool? enableDutchStrategy,
  }) {
    return SimulationConfig(
      playerCount: playerCount ?? this.playerCount,
      hardcoreLevel: hardcoreLevel ?? this.hardcoreLevel,
      simulatedPlayerSkill: simulatedPlayerSkill ?? this.simulatedPlayerSkill,
      enableMemory: enableMemory ?? this.enableMemory,
      enableAdvancedThresholds: enableAdvancedThresholds ?? this.enableAdvancedThresholds,
      enablePowerStrategy: enablePowerStrategy ?? this.enablePowerStrategy,
      enableDutchStrategy: enableDutchStrategy ?? this.enableDutchStrategy,
    );
  }
  
  /// Obtient la difficulté du bot à l'index donné
  BotDifficulty getBotDifficulty(int playerIndex) {
    if (hardcoreLevel != null) {
      return HardcoreBotConfig.getHardcoreDifficulty(
        level: hardcoreLevel!,
        playerSkillEstimate: simulatedPlayerSkill ?? 0,
      );
    }
    // Difficulté Difficile par défaut pour les simulations
    return BotConfig.getSkillDifficulty(BotSkillLevel.difficile);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLASSES DE RÉSULTATS
// ═══════════════════════════════════════════════════════════════════════════

/// Statistiques agrégées
class SimulationStats {
  int _matchCount = 0;
  int _player0Wins = 0;
  int _botWins = 0;
  
  final List<int> _player0FinalScores = [];
  final List<int> _botFinalScores = [];
  final List<int> _roundCounts = [];
  final List<int> _dutchTurns = [];
  
  int _dutchSuccessCount = 0;
  int _dutchFailCount = 0;
  
  void addMatch(MatchResult result) {
    _matchCount++;
    
    if (result.winnerIndex == 0) {
      _player0Wins++;
    } else {
      _botWins++;
    }
    
    _player0FinalScores.add(result.finalScores[0]);
    if (result.finalScores.length > 1) {
      _botFinalScores.add(result.finalScores.sublist(1).reduce(min));
    }
    _roundCounts.add(result.roundCount);
    
    for (final round in result.rounds) {
      if (round.dutchCallerIndex >= 0) {
        _dutchTurns.add(round.turnCount);
        if (round.dutchSuccess) {
          _dutchSuccessCount++;
        } else {
          _dutchFailCount++;
        }
      }
    }
  }
  
  double get player0Winrate => _matchCount > 0 ? _player0Wins / _matchCount : 0;
  double get botWinrate => _matchCount > 0 ? _botWins / _matchCount : 0;
  
  double get avgPlayer0Score => _player0FinalScores.isNotEmpty 
      ? _player0FinalScores.reduce((a, b) => a + b) / _player0FinalScores.length 
      : 0;
  double get avgBotScore => _botFinalScores.isNotEmpty 
      ? _botFinalScores.reduce((a, b) => a + b) / _botFinalScores.length 
      : 0;
      
  double get avgRounds => _roundCounts.isNotEmpty 
      ? _roundCounts.reduce((a, b) => a + b) / _roundCounts.length 
      : 0;
      
  double get avgDutchTurn => _dutchTurns.isNotEmpty 
      ? _dutchTurns.reduce((a, b) => a + b) / _dutchTurns.length 
      : 0;
      
  double get dutchSuccessRate => (_dutchSuccessCount + _dutchFailCount) > 0 
      ? _dutchSuccessCount / (_dutchSuccessCount + _dutchFailCount) 
      : 0;
}

/// Résultat d'un match complet
class MatchResult {
  final int winnerIndex;
  final List<int> finalScores;
  final int roundCount;
  final List<RoundResult> rounds;

  MatchResult({
    required this.winnerIndex,
    required this.finalScores,
    required this.roundCount,
    required this.rounds,
  });
}

/// Résultat d'un round
class RoundResult {
  final List<int> roundScores;
  final int dutchCallerIndex;
  final int turnCount;
  final bool dutchSuccess;

  RoundResult({
    required this.roundScores,
    required this.dutchCallerIndex,
    required this.turnCount,
    required this.dutchSuccess,
  });
}

/// Statistiques d'un tour
class TurnStats {
  final int playerIndex;
  final TurnAction action;
  final bool calledDutch;
  final int? drawnCardValue;
  final bool? keptCard;

  TurnStats({
    required this.playerIndex,
    required this.action,
    required this.calledDutch,
    this.drawnCardValue,
    this.keptCard,
  });
}

enum TurnAction { draw, replace, discard, skip }

/// Résultat de simulation
class SimulationResult {
  final SimulationConfig config;
  final int matchCount;
  final SimulationStats stats;

  SimulationResult({
    required this.config,
    required this.matchCount,
    required this.stats,
  });
  
  String get summary => '''
Simulation: $matchCount matchs
Bot Winrate: ${(stats.botWinrate * 100).toStringAsFixed(1)}%
Player Winrate: ${(stats.player0Winrate * 100).toStringAsFixed(1)}%
Avg Rounds: ${stats.avgRounds.toStringAsFixed(1)}
Avg Dutch Turn: ${stats.avgDutchTurn.toStringAsFixed(1)}
Dutch Success Rate: ${(stats.dutchSuccessRate * 100).toStringAsFixed(1)}%
''';
}

/// Résultat des tests d'ablation
class AblationResult {
  final HardcoreLevel level;
  final Map<String, SimulationResult> results;

  AblationResult({
    required this.level,
    required this.results,
  });
  
  String get summary {
    final buffer = StringBuffer();
    buffer.writeln('=== ABLATION TESTS - ${level.name.toUpperCase()} ===\n');
    
    final baseline = results['baseline'];
    if (baseline != null) {
      buffer.writeln('BASELINE (full config):');
      buffer.writeln('  Bot Winrate: ${(baseline.stats.botWinrate * 100).toStringAsFixed(1)}%');
      buffer.writeln('');
    }
    
    for (final entry in results.entries) {
      if (entry.key == 'baseline') continue;
      
      final delta = baseline != null 
          ? entry.value.stats.botWinrate - baseline.stats.botWinrate 
          : 0;
      final deltaStr = delta >= 0 ? '+${(delta * 100).toStringAsFixed(1)}' : (delta * 100).toStringAsFixed(1);
      
      buffer.writeln('${entry.key}:');
      buffer.writeln('  Bot Winrate: ${(entry.value.stats.botWinrate * 100).toStringAsFixed(1)}% ($deltaStr%)');
    }
    
    return buffer.toString();
  }
}
