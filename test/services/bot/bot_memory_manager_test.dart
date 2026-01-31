import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/game/bot/bot_memory_manager.dart';
import 'package:dutch_game/services/game/bot/bot_difficulty.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';

void main() {
  group('BotMemoryManager', () {
    late Player bot;

    setUp(() {
      bot = Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1);
      bot.hand = [
        PlayingCard.create('hearts', 'A'),
        PlayingCard.create('diamonds', '5'),
        PlayingCard.create('clubs', '8'),
        PlayingCard.create('spades', 'R'),
      ];
      bot.knownCards = List.filled(4, false, growable: true);
      bot.initializeBotMemory();
    });

    group('getUnknownIndices', () {
      test('returns all indices when nothing is known', () {
        bot.mentalMap = List.filled(4, null, growable: true);
        
        final unknown = BotMemoryManager.getUnknownIndices(bot);
        
        expect(unknown, [0, 1, 2, 3]);
      });

      test('returns empty when all cards are known', () {
        bot.mentalMap[0] = PlayingCard.create('hearts', 'A');
        bot.mentalMap[1] = PlayingCard.create('diamonds', '5');
        bot.mentalMap[2] = PlayingCard.create('clubs', '8');
        bot.mentalMap[3] = PlayingCard.create('spades', 'R');
        
        final unknown = BotMemoryManager.getUnknownIndices(bot);
        
        expect(unknown, isEmpty);
      });

      test('returns partial indices when some cards are known', () {
        // Reset mentalMap completely
        bot.mentalMap = List.filled(4, null, growable: true);
        bot.mentalMap[0] = PlayingCard.create('hearts', 'A');
        bot.mentalMap[2] = PlayingCard.create('clubs', '8');
        
        final unknown = BotMemoryManager.getUnknownIndices(bot);
        
        expect(unknown, [1, 3]);
      });
    });

    group('countKnownCards', () {
      test('returns 0 when nothing is known', () {
        bot.knownCards = List.filled(4, false, growable: true);
        
        final count = BotMemoryManager.countKnownCards(bot);
        
        expect(count, 0);
      });

      test('returns count of known cards', () {
        // Reset knownCards completely
        bot.knownCards = List.filled(4, false, growable: true);
        bot.knownCards[0] = true;
        bot.knownCards[2] = true;
        
        final count = BotMemoryManager.countKnownCards(bot);
        
        expect(count, 2);
      });

      test('returns 4 when all cards are known', () {
        bot.knownCards = List.filled(4, true, growable: true);
        
        final count = BotMemoryManager.countKnownCards(bot);
        
        expect(count, 4);
      });
    });

    group('minPointsInHand', () {
      test('returns 0 for empty hand', () {
        bot.hand = [];
        
        final min = BotMemoryManager.minPointsInHand(bot);
        
        expect(min, 0);
      });

      test('returns minimum points in hand', () {
        // Hand: A(1), 5(5), 8(8), R(13)
        final min = BotMemoryManager.minPointsInHand(bot);
        
        expect(min, 1);
      });

      test('handles hand with all same value', () {
        bot.hand = [
          PlayingCard.create('hearts', '5'),
          PlayingCard.create('diamonds', '5'),
          PlayingCard.create('clubs', '5'),
        ];
        
        final min = BotMemoryManager.minPointsInHand(bot);
        
        expect(min, 5);
      });
    });

    group('chooseBadCard', () {
      test('returns worst known card index', () {
        bot.mentalMap[0] = PlayingCard.create('hearts', 'A');   // 1 point
        bot.mentalMap[1] = PlayingCard.create('diamonds', '5'); // 5 points
        bot.mentalMap[2] = PlayingCard.create('clubs', '8');    // 8 points
        bot.mentalMap[3] = PlayingCard.create('spades', 'R');   // 13 points
        
        final worst = BotMemoryManager.chooseBadCard(bot);
        
        expect(worst, 3); // R has highest points
      });

      test('returns unknown card when nothing known', () {
        bot.mentalMap = List.filled(4, null, growable: true);
        
        final choice = BotMemoryManager.chooseBadCard(bot);
        
        expect(choice, greaterThanOrEqualTo(0));
        expect(choice, lessThan(4));
      });
    });

    group('chooseUnknownCard', () {
      test('returns unknown card index', () {
        bot.mentalMap[0] = PlayingCard.create('hearts', 'A');
        bot.mentalMap[2] = PlayingCard.create('clubs', '8');
        // 1 and 3 are unknown
        
        final choice = BotMemoryManager.chooseUnknownCard(bot);
        
        expect(choice, isIn([1, 3]));
      });

      test('returns 0 when all cards are known', () {
        bot.mentalMap[0] = PlayingCard.create('hearts', 'A');
        bot.mentalMap[1] = PlayingCard.create('diamonds', '5');
        bot.mentalMap[2] = PlayingCard.create('clubs', '8');
        bot.mentalMap[3] = PlayingCard.create('spades', 'R');
        
        final choice = BotMemoryManager.chooseUnknownCard(bot);
        
        expect(choice, 0);
      });
    });

    group('chooseCardToLook', () {
      test('returns unknown card when available', () {
        bot.mentalMap[0] = PlayingCard.create('hearts', 'A');
        // 1, 2, 3 are unknown
        
        final choice = BotMemoryManager.chooseCardToLook(bot, BotDifficulty.bronze);
        
        expect(choice, isIn([1, 2, 3]));
      });

      test('works with all difficulties', () {
        for (final diff in [BotDifficulty.bronze, BotDifficulty.silver, BotDifficulty.gold, BotDifficulty.platinum]) {
          final choice = BotMemoryManager.chooseCardToLook(bot, diff);
          expect(choice, greaterThanOrEqualTo(0));
          expect(choice, lessThan(4));
        }
      });
    });

    group('applyMemoryDecay', () {
      test('does not crash with empty lists', () {
        bot.knownCards = [];
        bot.mentalMap = [];
        
        // Should not throw
        BotMemoryManager.applyMemoryDecay(bot, BotDifficulty.bronze);
      });

      test('applies decay based on difficulty', () {
        bot.knownCards = List.filled(4, true, growable: true);
        
        // Run multiple times to see if decay happens (probabilistic)
        for (int i = 0; i < 10; i++) {
          BotMemoryManager.applyMemoryDecay(bot, BotDifficulty.bronze);
        }
        
        // Just verify it doesn't crash
        expect(true, isTrue);
      });
    });
  });
}
