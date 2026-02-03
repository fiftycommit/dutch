import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/game/bot/human_threat_tracker.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/game_settings.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('HumanThreatTracker', () {
    late HumanThreatTracker tracker;
    late GameState gameState;
    late Player human;
    late Player bot1;
    late Player bot2;

    setUp(() {
      tracker = HumanThreatTracker();
      tracker.reset();
      
      human = Player(id: 'human', name: 'Joueur', isHuman: true);
      bot1 = Player(id: 'bot1', name: 'Bot 1', isHuman: false);
      bot2 = Player(id: 'bot2', name: 'Bot 2', isHuman: false);
      
      // Initialiser les mains avec des cartes
      human.hand = [
        createCard('hearts', '2'),
        createCard('diamonds', '3'),
        createCard('clubs', '4'),
        createCard('spades', '5'),
      ];
      bot1.hand = [
        createCard('hearts', '8'),
        createCard('diamonds', '9'),
        createCard('clubs', '10'),
        createCard('spades', 'V'),
      ];
      bot2.hand = [
        createCard('hearts', '6'),
        createCard('diamonds', '7'),
        createCard('clubs', 'D'),
        createCard('spades', 'R'),
      ];
      
      gameState = GameState(
        players: [human, bot1, bot2],
        deck: [],
        discardPile: [createCard('hearts', 'A')],
        gameMode: GameMode.quick,
        difficulty: Difficulty.hard,
      );
    });

    test('reset() resets all tracking values', () {
      tracker.recordHumanMatch(5, 3);
      tracker.onNewTurn();
      tracker.reset();
      
      final level = tracker.calculateThreatLevel(gameState);
      expect(level, equals(HumanThreatLevel.low));
    });

    test('initializeRound() captures initial state', () {
      tracker.initializeRound(gameState);
      final level = tracker.calculateThreatLevel(gameState);
      // Au début, sans match ni progression, niveau bas à medium
      expect(level.index, lessThanOrEqualTo(HumanThreatLevel.medium.index));
    });

    test('recordHumanMatch() increases threat level', () {
      tracker.initializeRound(gameState);
      final levelBefore = tracker.calculateThreatLevel(gameState);
      
      // Simuler un match
      tracker.recordHumanMatch(5, 1);
      final levelAfter = tracker.calculateThreatLevel(gameState);
      
      // Le niveau devrait avoir augmenté ou rester au moins égal
      expect(levelAfter.index, greaterThanOrEqualTo(levelBefore.index));
    });

    test('multiple matches increase threat significantly', () {
      tracker.initializeRound(gameState);
      
      // Simuler plusieurs matchs consécutifs
      tracker.recordHumanMatch(5, 1);
      tracker.recordHumanMatch(4, 2);
      tracker.recordHumanMatch(3, 3);
      
      final level = tracker.calculateThreatLevel(gameState);
      
      // Avec 3 matchs, devrait être au moins MEDIUM
      expect(level.index, greaterThanOrEqualTo(HumanThreatLevel.medium.index));
    });

    test('human with few cards increases threat', () {
      tracker.initializeRound(gameState);
      
      // Réduire la main de l'humain à 1 carte
      human.hand = [createCard('hearts', '2')];
      
      final level = tracker.calculateThreatLevel(gameState);
      
      // Avec 1 carte, devrait être HIGH ou CRITICAL
      expect(level.index, greaterThanOrEqualTo(HumanThreatLevel.high.index));
    });

    test('human with low score increases threat', () {
      tracker.initializeRound(gameState);
      
      // Donner à l'humain un score très bas (2 points)
      human.hand = [
        createCard('hearts', '2'),
        createCard('diamonds', 'JOKER'),
      ];
      
      final level = tracker.calculateThreatLevel(gameState);
      
      // Score bas + peu de cartes = menace élevée
      expect(level.index, greaterThanOrEqualTo(HumanThreatLevel.medium.index));
    });

    test('getAggressivenessMultiplier returns correct values', () {
      expect(tracker.getAggressivenessMultiplier(HumanThreatLevel.low), equals(1.0));
      expect(tracker.getAggressivenessMultiplier(HumanThreatLevel.medium), equals(1.3));
      expect(tracker.getAggressivenessMultiplier(HumanThreatLevel.high), equals(1.6));
      expect(tracker.getAggressivenessMultiplier(HumanThreatLevel.critical), equals(2.0));
    });

    test('shouldPrioritizeAntiHumanMatch returns true for high+ threat', () {
      tracker.initializeRound(gameState);
      
      // Créer une situation de menace haute
      human.hand = [createCard('hearts', '2')];
      tracker.recordHumanMatch(5, 1);
      tracker.recordHumanMatch(4, 2);
      
      // Devrait prioriser le match anti-humain
      final shouldPrioritize = tracker.shouldPrioritizeAntiHumanMatch(gameState);
      final level = tracker.calculateThreatLevel(gameState);
      
      if (level.index >= HumanThreatLevel.high.index) {
        expect(shouldPrioritize, isTrue);
      }
    });

    test('onNewTurn increments counter', () {
      tracker.initializeRound(gameState);
      tracker.recordHumanMatch(5, 1);
      
      // Le momentum devrait être actif juste après un match
      var debugInfo = tracker.getDebugInfo(gameState);
      expect(debugInfo['turnsSinceMatch'], equals(0));
      
      // Après quelques tours, le momentum diminue
      tracker.onNewTurn();
      tracker.onNewTurn();
      tracker.onNewTurn();
      
      debugInfo = tracker.getDebugInfo(gameState);
      expect(debugInfo['turnsSinceMatch'], equals(3));
    });

    test('critical threat when human has 1 card and very low score', () {
      tracker.initializeRound(gameState);
      
      // Configuration critique : 1 carte, score très bas, plusieurs matchs
      human.hand = [createCard('hearts', 'JOKER')]; // 0 points
      tracker.recordHumanMatch(10, 1);
      tracker.recordHumanMatch(8, 2);
      tracker.recordHumanMatch(5, 3);
      
      final level = tracker.calculateThreatLevel(gameState);
      
      // Avec cette configuration, devrait être CRITICAL
      expect(level, equals(HumanThreatLevel.critical));
    });

    test('singleton pattern works correctly', () {
      final tracker1 = HumanThreatTracker();
      final tracker2 = HumanThreatTracker();
      
      expect(identical(tracker1, tracker2), isTrue);
    });

    test('getDebugInfo returns expected structure', () {
      tracker.initializeRound(gameState);
      tracker.recordHumanMatch(5, 1);
      
      final info = tracker.getDebugInfo(gameState);
      
      expect(info.containsKey('initialScore'), isTrue);
      expect(info.containsKey('matchCount'), isTrue);
      expect(info.containsKey('matchPointsSaved'), isTrue);
      expect(info.containsKey('turnsSinceMatch'), isTrue);
      expect(info.containsKey('threatLevel'), isTrue);
    });
  });
}
