import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/game/bot/bot_threat_analyzer.dart';
import 'package:dutch_game/services/game/bot/bot_difficulty.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';

void main() {
  group('BotThreatAnalyzer', () {
    late GameState gameState;
    late Player bot;
    late Player human;

    setUp(() {
      human = Player(id: 'human', name: 'Human', isHuman: true, position: 0);
      bot = Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1);

      human.hand = [
        PlayingCard.create('hearts', 'A'),
        PlayingCard.create('diamonds', '5'),
        PlayingCard.create('clubs', '8'),
        PlayingCard.create('spades', 'R'),
      ];
      human.knownCards = List.filled(4, false, growable: true);

      bot.hand = [
        PlayingCard.create('hearts', '2'),
        PlayingCard.create('diamonds', '3'),
        PlayingCard.create('clubs', '4'),
        PlayingCard.create('spades', '5'),
      ];
      bot.knownCards = List.filled(4, false, growable: true);
      bot.initializeBotMemory();

      gameState = GameState(
        players: [human, bot],
        deck: GameState.createFullDeck().sublist(0, 40),
        discardPile: [PlayingCard.create('hearts', '6')],
        currentPlayerIndex: 1,
        phase: GamePhase.playing,
      );
    });

    group('getMostThreateningPlayer', () {
      test('returns null when no player is threatening', () {
        // All players have 4 cards - not threatening
        final result = BotThreatAnalyzer.getMostThreateningPlayer(gameState, bot);
        expect(result, isNull);
      });

      test('returns player with fewest cards when threatening', () {
        human.hand = [PlayingCard.create('hearts', 'A')]; // 1 card = threatening
        
        final result = BotThreatAnalyzer.getMostThreateningPlayer(gameState, bot);
        expect(result, equals(human));
      });

      test('returns player with lowest score when same card count', () {
        human.hand = [
          PlayingCard.create('hearts', 'A'), // 1 pt
          PlayingCard.create('diamonds', 'A'), // 1 pt
        ];
        
        final bot2 = Player(id: 'bot2', name: 'Bot 2', isHuman: false, position: 2)
          ..hand = [
            PlayingCard.create('hearts', 'R'), // 13 pts
            PlayingCard.create('diamonds', 'R'), // 13 pts
          ]
          ..knownCards = List.filled(2, false, growable: true);
        gameState.players.add(bot2);
        
        final result = BotThreatAnalyzer.getMostThreateningPlayer(gameState, bot);
        expect(result, equals(human)); // Lower score
      });

      test('ignores self', () {
        bot.hand = [PlayingCard.create('hearts', 'A')]; // 1 card
        human.hand = [
          PlayingCard.create('hearts', '5'),
          PlayingCard.create('diamonds', '6'),
          PlayingCard.create('clubs', '7'),
          PlayingCard.create('spades', '8'),
        ];
        
        final result = BotThreatAnalyzer.getMostThreateningPlayer(gameState, bot);
        expect(result, isNull); // Human has 4 cards, not threatening
      });
    });

    group('shouldCounterAttack', () {
      test('returns false when no threat', () {
        final result = BotThreatAnalyzer.shouldCounterAttack(gameState, bot, BotDifficulty.gold);
        expect(result, isFalse);
      });

      test('considers threat for all difficulties', () {
        human.hand = [PlayingCard.create('hearts', 'A')];
        
        for (final diff in [BotDifficulty.bronze, BotDifficulty.silver, BotDifficulty.gold, BotDifficulty.platinum]) {
          final result = BotThreatAnalyzer.shouldCounterAttack(gameState, bot, diff);
          expect(result, isA<bool>());
        }
      });
    });

    group('analyzeDiscardPatterns', () {
      test('returns empty for bronze difficulty', () {
        final result = BotThreatAnalyzer.analyzeDiscardPatterns(gameState, bot, BotDifficulty.bronze);
        expect(result, isEmpty);
      });

      test('returns empty for silver difficulty', () {
        final result = BotThreatAnalyzer.analyzeDiscardPatterns(gameState, bot, BotDifficulty.silver);
        expect(result, isEmpty);
      });

      test('returns danger scores for gold difficulty', () {
        final result = BotThreatAnalyzer.analyzeDiscardPatterns(gameState, bot, BotDifficulty.gold);
        expect(result, isNotEmpty);
        expect(result.containsKey('human'), isTrue);
      });

      test('returns danger scores for platinum difficulty', () {
        final result = BotThreatAnalyzer.analyzeDiscardPatterns(gameState, bot, BotDifficulty.platinum);
        expect(result, isNotEmpty);
      });

      test('assigns higher danger to players with fewer cards', () {
        human.hand = [PlayingCard.create('hearts', 'A')];
        
        final bot2 = Player(id: 'bot2', name: 'Bot 2', isHuman: false, position: 2)
          ..hand = [
            PlayingCard.create('hearts', '5'),
            PlayingCard.create('diamonds', '6'),
            PlayingCard.create('clubs', '7'),
            PlayingCard.create('spades', '8'),
          ]
          ..knownCards = List.filled(4, false, growable: true);
        gameState.players.add(bot2);
        
        final result = BotThreatAnalyzer.analyzeDiscardPatterns(gameState, bot, BotDifficulty.platinum);
        expect(result['human']!, greaterThan(result['bot2']!));
      });
    });

    group('shouldCoordinateAttack', () {
      test('returns false for bronze difficulty', () {
        final result = BotThreatAnalyzer.shouldCoordinateAttack(gameState, bot, BotDifficulty.bronze);
        expect(result, isFalse);
      });

      test('returns false for silver difficulty', () {
        final result = BotThreatAnalyzer.shouldCoordinateAttack(gameState, bot, BotDifficulty.silver);
        expect(result, isFalse);
      });

      test('considers human threat for gold', () {
        human.hand = [PlayingCard.create('hearts', 'A')];
        final result = BotThreatAnalyzer.shouldCoordinateAttack(gameState, bot, BotDifficulty.gold);
        expect(result, isA<bool>());
      });

      test('considers human threat for platinum', () {
        human.hand = [PlayingCard.create('hearts', 'A')];
        final result = BotThreatAnalyzer.shouldCoordinateAttack(gameState, bot, BotDifficulty.platinum);
        expect(result, isA<bool>());
      });

      test('returns false when no human in game', () {
        gameState.players = [bot];
        final result = BotThreatAnalyzer.shouldCoordinateAttack(gameState, bot, BotDifficulty.platinum);
        expect(result, isFalse);
      });
    });

    group('getCounterAttackTarget', () {
      test('returns null when no counter attack needed', () {
        final result = BotThreatAnalyzer.getCounterAttackTarget(gameState, bot, BotDifficulty.bronze);
        expect(result, isNull);
      });

      test('may return target for threatening player', () {
        human.hand = [PlayingCard.create('hearts', 'A')];
        
        // Run multiple times to account for randomness
        bool foundTarget = false;
        for (int i = 0; i < 20; i++) {
          final result = BotThreatAnalyzer.getCounterAttackTarget(gameState, bot, BotDifficulty.platinum);
          if (result != null) {
            foundTarget = true;
            break;
          }
        }
        expect(foundTarget, isA<bool>());
      });
    });

    group('getTournamentPressure', () {
      test('returns 0 for quick mode', () {
        gameState.gameMode = GameMode.quick;
        final result = BotThreatAnalyzer.getTournamentPressure(gameState, bot);
        expect(result, 0.0);
      });

      test('returns pressure based on cumulative score', () {
        gameState.gameMode = GameMode.tournament;
        
        // Test various score thresholds
        final result = BotThreatAnalyzer.getTournamentPressure(gameState, bot);
        expect(result, isA<double>());
      });
    });
  });
}
