import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/card.dart';
import 'package:dutch_game/models/game_settings.dart';

void main() {
  group('Player', () {
    group('constructor', () {
      test('creates player with required fields', () {
        final player = Player(
          id: 'p1',
          name: 'Test Player',
          isHuman: true,
        );

        expect(player.id, 'p1');
        expect(player.name, 'Test Player');
        expect(player.isHuman, true);
        expect(player.hand, isEmpty);
        expect(player.knownCards, isEmpty);
        expect(player.isSpectator, false);
      });

      test('creates bot with behavior and skill level', () {
        final bot = Player(
          id: 'bot1',
          name: 'Bot',
          isHuman: false,
          botBehavior: BotBehavior.aggressive,
          botSkillLevel: BotSkillLevel.gold,
        );

        expect(bot.isHuman, false);
        expect(bot.botBehavior, BotBehavior.aggressive);
        expect(bot.botSkillLevel, BotSkillLevel.gold);
      });
    });

    group('clone', () {
      test('creates a copy with same values', () {
        final original = Player(
          id: 'p1',
          name: 'Original',
          isHuman: true,
          hand: [PlayingCard.create('hearts', '5')],
          knownCards: [true],
        );

        final clone = Player.clone(original);

        expect(clone.id, original.id);
        expect(clone.name, original.name);
        expect(clone.hand.length, original.hand.length);
        expect(clone.knownCards.length, original.knownCards.length);
      });

      test('clone has separate lists', () {
        final original = Player(
          id: 'p1',
          name: 'Original',
          isHuman: true,
          hand: [PlayingCard.create('hearts', '5')],
        );

        final clone = Player.clone(original);
        clone.hand.add(PlayingCard.create('spades', '6'));

        expect(original.hand.length, 1);
        expect(clone.hand.length, 2);
      });
    });

    group('calculateScore', () {
      test('returns sum of card points', () {
        final player = Player(
          id: 'p1',
          name: 'Test',
          isHuman: true,
          hand: [
            PlayingCard.create('hearts', '5'), // 5
            PlayingCard.create('spades', '3'), // 3
            PlayingCard.create('clubs', 'A'), // 1
          ],
        );

        expect(player.calculateScore(), 9);
      });

      test('returns 0 for empty hand', () {
        final player = Player(
          id: 'p1',
          name: 'Test',
          isHuman: true,
        );

        expect(player.calculateScore(), 0);
      });

      test('handles special cards correctly', () {
        final player = Player(
          id: 'p1',
          name: 'Test',
          isHuman: true,
          hand: [
            PlayingCard.create('hearts', 'R'), // 0 (red king)
            PlayingCard.create('joker', 'JOKER'), // 0
            PlayingCard.create('spades', 'R'), // 13 (black king)
          ],
        );

        expect(player.calculateScore(), 13);
      });
    });

    group('getEstimatedScore', () {
      test('returns actual score for human player', () {
        final player = Player(
          id: 'p1',
          name: 'Human',
          isHuman: true,
          hand: [
            PlayingCard.create('hearts', '5'),
            PlayingCard.create('spades', '3'),
          ],
        );

        expect(player.getEstimatedScore(), player.calculateScore());
      });

      test('estimates unknown cards for bot', () {
        final bot = Player(
          id: 'bot1',
          name: 'Bot',
          isHuman: false,
          hand: [
            PlayingCard.create('hearts', '5'),
            PlayingCard.create('spades', '3'),
            PlayingCard.create('clubs', '7'),
            PlayingCard.create('diamonds', '2'),
          ],
          mentalMap: [
            PlayingCard.create('hearts', '5'),
            PlayingCard.create('spades', '3'),
            null,
            null,
          ],
        );

        // Known: 5 + 3 = 8
        // Unknown: 2 cards estimated at ~5 each (average of known cards clamped)
        final estimate = bot.getEstimatedScore();
        expect(estimate, greaterThanOrEqualTo(8));
      });
    });

    group('initializeBotMemory', () {
      test('does nothing for human player', () {
        final human = Player(
          id: 'p1',
          name: 'Human',
          isHuman: true,
          hand: [
            PlayingCard.create('hearts', '5'),
            PlayingCard.create('spades', '3'),
            PlayingCard.create('clubs', '7'),
            PlayingCard.create('diamonds', '2'),
          ],
        );

        human.initializeBotMemory();
        expect(human.mentalMap, isEmpty);
      });

      test('initializes first 2 cards for bot', () {
        final bot = Player(
          id: 'bot1',
          name: 'Bot',
          isHuman: false,
          hand: [
            PlayingCard.create('hearts', '5'),
            PlayingCard.create('spades', '3'),
            PlayingCard.create('clubs', '7'),
            PlayingCard.create('diamonds', '2'),
          ],
        );

        bot.initializeBotMemory();

        expect(bot.mentalMap.length, 4);
        expect(bot.mentalMap[0], isNotNull);
        expect(bot.mentalMap[1], isNotNull);
        expect(bot.mentalMap[2], isNull);
        expect(bot.mentalMap[3], isNull);

        expect(bot.knownCards[0], true);
        expect(bot.knownCards[1], true);
        expect(bot.knownCards[2], false);
        expect(bot.knownCards[3], false);
      });
    });

    group('updateMentalMap', () {
      test('updates card at index', () {
        final bot = Player(
          id: 'bot1',
          name: 'Bot',
          isHuman: false,
          hand: List.filled(4, PlayingCard.create('hearts', 'A')),
          mentalMap: List.filled(4, null),
          knownCards: List.filled(4, false),
        );

        final newCard = PlayingCard.create('spades', 'K');
        bot.updateMentalMap(2, newCard);

        expect(bot.mentalMap[2], newCard);
        expect(bot.knownCards[2], true);
      });

      test('expands mentalMap if needed', () {
        final bot = Player(
          id: 'bot1',
          name: 'Bot',
          isHuman: false,
        );

        bot.updateMentalMap(3, PlayingCard.create('hearts', '5'));

        expect(bot.mentalMap.length, 4);
      });
    });

    group('resetMentalMap', () {
      test('clears all memory', () {
        final bot = Player(
          id: 'bot1',
          name: 'Bot',
          isHuman: false,
          hand: List.filled(4, PlayingCard.create('hearts', 'A')),
          mentalMap: [
            PlayingCard.create('hearts', '5'),
            PlayingCard.create('spades', '3'),
            null,
            null,
          ],
          knownCards: [true, true, false, false],
        );

        bot.resetMentalMap();

        expect(bot.mentalMap.every((e) => e == null), true);
        expect(bot.knownCards.every((e) => e == false), true);
      });
    });

    group('forgetCard', () {
      test('clears specific card memory', () {
        final bot = Player(
          id: 'bot1',
          name: 'Bot',
          isHuman: false,
          mentalMap: [
            PlayingCard.create('hearts', '5'),
            PlayingCard.create('spades', '3'),
          ],
          knownCards: [true, true],
        );

        bot.forgetCard(0);

        expect(bot.mentalMap[0], isNull);
        expect(bot.knownCards[0], false);
        expect(bot.mentalMap[1], isNotNull);
        expect(bot.knownCards[1], true);
      });
    });

    group('knownCardCount', () {
      test('counts known cards', () {
        final bot = Player(
          id: 'bot1',
          name: 'Bot',
          isHuman: false,
          hand: List.filled(4, PlayingCard.create('hearts', 'A')),
          mentalMap: [
            PlayingCard.create('hearts', '5'),
            PlayingCard.create('spades', '3'),
            null,
            null,
          ],
        );

        expect(bot.knownCardCount, 2);
      });
    });

    group('displayAvatar', () {
      test('returns bot emoji for non-human', () {
        final bot = Player(
          id: 'bot1',
          name: 'Bot',
          isHuman: false,
        );

        expect(bot.displayAvatar, '🤖');
      });

      test('returns behavior-specific emoji', () {
        final fastBot = Player(
          id: 'bot1',
          name: 'Fast Bot',
          isHuman: false,
          botBehavior: BotBehavior.fast,
        );
        final aggressiveBot = Player(
          id: 'bot2',
          name: 'Aggressive Bot',
          isHuman: false,
          botBehavior: BotBehavior.aggressive,
        );
        final balancedBot = Player(
          id: 'bot3',
          name: 'Balanced Bot',
          isHuman: false,
          botBehavior: BotBehavior.balanced,
        );

        expect(fastBot.displayAvatar, '🏃');
        expect(aggressiveBot.displayAvatar, '⚔️');
        expect(balancedBot.displayAvatar, '🧠');
      });

      test('returns consistent avatar for human based on id', () {
        final player1 = Player(id: 'p1', name: 'Player 1', isHuman: true);
        final player2 = Player(id: 'p1', name: 'Player 1', isHuman: true);

        expect(player1.displayAvatar, player2.displayAvatar);
      });
    });

    group('JSON serialization', () {
      test('serializes and deserializes player', () {
        final original = Player(
          id: 'p1',
          name: 'Test Player',
          isHuman: true,
          position: 2,
          isSpectator: false,
          hand: [PlayingCard.create('hearts', '5')],
          knownCards: [true],
        );

        final json = original.toJson();
        final restored = Player.fromJson(json);

        expect(restored.id, original.id);
        expect(restored.name, original.name);
        expect(restored.isHuman, original.isHuman);
        expect(restored.position, original.position);
        expect(restored.isSpectator, original.isSpectator);
        expect(restored.hand.length, original.hand.length);
      });

      test('serializes bot with behavior', () {
        final bot = Player(
          id: 'bot1',
          name: 'Bot',
          isHuman: false,
          botBehavior: BotBehavior.aggressive,
          botSkillLevel: BotSkillLevel.gold,
        );

        final json = bot.toJson();
        final restored = Player.fromJson(json);

        expect(restored.botBehavior, BotBehavior.aggressive);
        expect(restored.botSkillLevel, BotSkillLevel.gold);
      });
    });
  });

  group('DutchAttempt', () {
    test('calculates accuracy correctly', () {
      final accurate = DutchAttempt(
        estimatedScore: 5,
        actualScore: 4,
        won: true,
        opponentsCount: 3,
      );
      expect(accurate.accuracy, 1.0);

      final inaccurate = DutchAttempt(
        estimatedScore: 5,
        actualScore: 10,
        won: false,
        opponentsCount: 3,
      );
      expect(inaccurate.accuracy, 0.5);
    });
  });
}
