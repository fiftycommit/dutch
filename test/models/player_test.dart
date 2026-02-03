import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';
import 'package:dutch_game/models/game_settings.dart';

void main() {
  group('Player - Creation', () {
    test('human player created correctly', () {
      final player = Player(id: 'p1', name: 'Test', isHuman: true);
      
      expect(player.id, 'p1');
      expect(player.name, 'Test');
      expect(player.isHuman, true);
      expect(player.hand, isEmpty);
      expect(player.knownCards, isEmpty);
    });

    test('bot player created correctly', () {
      final player = Player(
        id: 'bot1',
        name: 'Bot',
        isHuman: false,
        botBehavior: BotBehavior.aggressive,
        botSkillLevel: BotSkillLevel.gold,
      );
      
      expect(player.isHuman, false);
      expect(player.botBehavior, BotBehavior.aggressive);
      expect(player.botSkillLevel, BotSkillLevel.gold);
    });

    test('clone creates independent copy', () {
      final original = Player(id: 'p1', name: 'Test', isHuman: true);
      original.hand = [PlayingCard.create('hearts', 'A')];
      original.knownCards = [true];
      
      final clone = Player.clone(original);
      clone.hand.add(PlayingCard.create('diamonds', '2'));
      
      expect(original.hand.length, 1);
      expect(clone.hand.length, 2);
    });
  });

  group('Player - Score Calculation', () {
    test('calculateScore sums card points', () {
      final player = Player(id: 'p1', name: 'Test', isHuman: true);
      player.hand = [
        PlayingCard.create('hearts', 'A'),   // 1
        PlayingCard.create('diamonds', '5'), // 5
        PlayingCard.create('clubs', '10'),   // 10
      ];
      
      expect(player.calculateScore(), 16);
    });

    test('calculateScore with empty hand is 0', () {
      final player = Player(id: 'p1', name: 'Test', isHuman: true);
      
      expect(player.calculateScore(), 0);
    });

    test('calculateScore includes red King as 0', () {
      final player = Player(id: 'p1', name: 'Test', isHuman: true);
      player.hand = [
        PlayingCard.create('hearts', 'R'),  // 0 (red king)
        PlayingCard.create('hearts', '5'),  // 5
      ];
      
      expect(player.calculateScore(), 5);
    });

    test('calculateScore includes black King as 13', () {
      final player = Player(id: 'p1', name: 'Test', isHuman: true);
      player.hand = [
        PlayingCard.create('spades', 'R'),  // 13 (black king)
        PlayingCard.create('hearts', '2'),  // 2
      ];
      
      expect(player.calculateScore(), 15);
    });
  });

  group('Player - Estimated Score (Bot)', () {
    test('human getEstimatedScore returns actual score', () {
      final player = Player(id: 'p1', name: 'Test', isHuman: true);
      player.hand = [
        PlayingCard.create('hearts', 'A'),
        PlayingCard.create('diamonds', '5'),
      ];
      
      expect(player.getEstimatedScore(), player.calculateScore());
    });

    test('bot getEstimatedScore uses mental map', () {
      final bot = Player(id: 'bot1', name: 'Bot', isHuman: false);
      bot.hand = [
        PlayingCard.create('hearts', 'A'),   // 1 - known
        PlayingCard.create('diamonds', '5'), // 5 - known
        PlayingCard.create('clubs', '10'),   // 10 - unknown
        PlayingCard.create('spades', 'R'),   // 13 - unknown
      ];
      bot.mentalMap = [
        PlayingCard.create('hearts', 'A'),
        PlayingCard.create('diamonds', '5'),
        null,
        null,
      ];
      
      final estimated = bot.getEstimatedScore();
      // Connu seulement: 1 + 5 = 6 (aucune estimation sur les inconnues)
      expect(estimated, equals(6));
    });

    test('bot with all known cards has accurate estimate', () {
      final bot = Player(id: 'bot1', name: 'Bot', isHuman: false);
      final cards = [
        PlayingCard.create('hearts', 'A'),
        PlayingCard.create('diamonds', '2'),
      ];
      bot.hand = cards;
      bot.mentalMap = List.from(cards);
      
      expect(bot.getEstimatedScore(), bot.calculateScore());
    });
  });

  group('Player - Bot Memory', () {
    test('initializeBotMemory sets up mental map', () {
      final bot = Player(id: 'bot1', name: 'Bot', isHuman: false);
      bot.hand = [
        PlayingCard.create('hearts', 'A'),
        PlayingCard.create('diamonds', '2'),
        PlayingCard.create('clubs', '3'),
        PlayingCard.create('spades', '4'),
      ];
      bot.knownCards = [false, false, false, false];
      
      bot.initializeBotMemory();
      
      expect(bot.mentalMap.length, 4);
      expect(bot.mentalMap[0], isNotNull); // First 2 cards known
      expect(bot.mentalMap[1], isNotNull);
      expect(bot.mentalMap[2], isNull);
      expect(bot.mentalMap[3], isNull);
    });

    test('initializeBotMemory does nothing for human', () {
      final human = Player(id: 'p1', name: 'Test', isHuman: true);
      human.hand = [PlayingCard.create('hearts', 'A')];
      
      human.initializeBotMemory();
      
      expect(human.mentalMap, isEmpty);
    });

    test('updateMentalMap sets card at index', () {
      final bot = Player(id: 'bot1', name: 'Bot', isHuman: false);
      bot.hand = [PlayingCard.create('hearts', 'A')];
      bot.mentalMap = [null];
      bot.knownCards = [false];
      
      final newCard = PlayingCard.create('diamonds', '5');
      bot.updateMentalMap(0, newCard);
      
      expect(bot.mentalMap[0], newCard);
      expect(bot.knownCards[0], true);
    });

    test('updateMentalMap extends list if needed', () {
      final bot = Player(id: 'bot1', name: 'Bot', isHuman: false);
      bot.mentalMap = [];
      bot.knownCards = [false, false, false];
      
      final card = PlayingCard.create('hearts', 'A');
      bot.updateMentalMap(2, card);
      
      expect(bot.mentalMap.length, 3);
      expect(bot.mentalMap[2], card);
    });

    test('resetMentalMap clears all memory', () {
      final bot = Player(id: 'bot1', name: 'Bot', isHuman: false);
      bot.hand = [
        PlayingCard.create('hearts', 'A'),
        PlayingCard.create('diamonds', '2'),
      ];
      bot.mentalMap = [bot.hand[0], bot.hand[1]];
      bot.knownCards = [true, true];
      
      bot.resetMentalMap();
      
      expect(bot.mentalMap, everyElement(isNull));
      expect(bot.knownCards, everyElement(false));
    });

    test('forgetCard clears specific card memory', () {
      final bot = Player(id: 'bot1', name: 'Bot', isHuman: false);
      bot.mentalMap = [
        PlayingCard.create('hearts', 'A'),
        PlayingCard.create('diamonds', '2'),
      ];
      bot.knownCards = [true, true];
      
      bot.forgetCard(0);
      
      expect(bot.mentalMap[0], isNull);
      expect(bot.knownCards[0], false);
      expect(bot.mentalMap[1], isNotNull);
      expect(bot.knownCards[1], true);
    });
  });

  group('Player - Known Card Counts', () {
    test('knownCardCount returns correct count', () {
      final bot = Player(id: 'bot1', name: 'Bot', isHuman: false);
      bot.hand = [
        PlayingCard.create('hearts', 'A'),
        PlayingCard.create('diamonds', '2'),
        PlayingCard.create('clubs', '3'),
      ];
      bot.mentalMap = [
        PlayingCard.create('hearts', 'A'),
        null,
        PlayingCard.create('clubs', '3'),
      ];
      
      expect(bot.knownCardCount, 2);
    });

    test('knownCardsScore sums known cards only', () {
      final bot = Player(id: 'bot1', name: 'Bot', isHuman: false);
      bot.hand = [
        PlayingCard.create('hearts', 'A'),   // 1 - known
        PlayingCard.create('diamonds', '5'), // 5 - unknown
        PlayingCard.create('clubs', '3'),    // 3 - known
      ];
      bot.mentalMap = [
        PlayingCard.create('hearts', 'A'),
        null,
        PlayingCard.create('clubs', '3'),
      ];
      
      expect(bot.knownCardsScore, 4); // 1 + 3
    });
  });

  group('Player - Dutch History', () {
    test('dutchHistory tracks attempts', () {
      final player = Player(id: 'p1', name: 'Test', isHuman: true);
      
      player.dutchHistory.add(DutchAttempt(
        estimatedScore: 5,
        actualScore: 6,
        won: true,
        opponentsCount: 3,
      ));
      
      expect(player.dutchHistory.length, 1);
      expect(player.dutchHistory[0].won, true);
    });

    test('DutchAttempt accuracy calculation', () {
      final accurate = DutchAttempt(
        estimatedScore: 5,
        actualScore: 6, // Within 2
        won: true,
        opponentsCount: 3,
      );
      
      final inaccurate = DutchAttempt(
        estimatedScore: 5,
        actualScore: 10, // More than 2 away
        won: false,
        opponentsCount: 3,
      );
      
      expect(accurate.accuracy, 1.0);
      expect(inaccurate.accuracy, 0.5);
    });
  });

  group('Player - Display', () {
    test('displayName returns name', () {
      final player = Player(id: 'p1', name: 'TestPlayer', isHuman: true);
      
      expect(player.displayName, 'TestPlayer');
    });

    test('displayAvatar for bots shows behavior emoji', () {
      final fastBot = Player(
        id: 'bot1',
        name: 'Fast',
        isHuman: false,
        botBehavior: BotBehavior.fast,
      );
      final aggressiveBot = Player(
        id: 'bot2',
        name: 'Aggressive',
        isHuman: false,
        botBehavior: BotBehavior.aggressive,
      );
      final balancedBot = Player(
        id: 'bot3',
        name: 'Balanced',
        isHuman: false,
        botBehavior: BotBehavior.balanced,
      );
      
      expect(fastBot.displayAvatar, '🏃');
      expect(aggressiveBot.displayAvatar, '⚔️');
      expect(balancedBot.displayAvatar, '🧠');
    });

    test('displayAvatar for humans is consistent', () {
      final player = Player(id: 'p1', name: 'Test', isHuman: true);
      
      // Same ID should give same avatar
      final avatar1 = player.displayAvatar;
      final avatar2 = player.displayAvatar;
      
      expect(avatar1, avatar2);
    });

    test('getPositionDisplay for bots', () {
      final bot = Player(id: 'bot1', name: 'Bot', isHuman: false);
      
      expect(bot.getPositionDisplay(1), contains('Gauche'));
      expect(bot.getPositionDisplay(2), contains('Haut'));
      expect(bot.getPositionDisplay(3), contains('Droite'));
    });
  });

  group('Player - Serialization', () {
    test('toJson includes all properties', () {
      final player = Player(
        id: 'p1',
        name: 'Test',
        isHuman: true,
        position: 2,
      );
      player.hand = [PlayingCard.create('hearts', 'A')];
      player.knownCards = [true];
      
      final json = player.toJson();
      
      expect(json['id'], 'p1');
      expect(json['name'], 'Test');
      expect(json['isHuman'], true);
      expect(json['position'], 2);
      expect(json['hand'], isNotEmpty);
      expect(json['knownCards'], [true]);
    });

    test('fromJson restores player correctly', () {
      final original = Player(
        id: 'p1',
        name: 'Test',
        isHuman: true,
        position: 1,
      );
      original.hand = [PlayingCard.create('hearts', 'A')];
      original.knownCards = [true];
      
      final json = original.toJson();
      final restored = Player.fromJson(json);
      
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.isHuman, original.isHuman);
      expect(restored.position, original.position);
      expect(restored.hand.length, original.hand.length);
    });

    test('fromJson handles bot properties', () {
      final json = {
        'id': 'bot1',
        'name': 'Bot',
        'isHuman': false,
        'botBehavior': BotBehavior.aggressive.index,
        'botSkillLevel': BotSkillLevel.gold.index,
        'position': 1,
        'hand': <Map<String, dynamic>>[],
        'knownCards': <bool>[],
      };
      
      final bot = Player.fromJson(json);
      
      expect(bot.botBehavior, BotBehavior.aggressive);
      expect(bot.botSkillLevel, BotSkillLevel.gold);
    });

    test('fromJson handles spectator', () {
      final json = {
        'id': 'spec1',
        'name': 'Spectator',
        'isHuman': true,
        'isSpectator': true,
        'hand': <Map<String, dynamic>>[],
        'knownCards': <bool>[],
      };
      
      final spectator = Player.fromJson(json);
      
      expect(spectator.isSpectator, true);
    });
  });

  group('Player - Consecutive Bad Draws', () {
    test('consecutiveBadDraws defaults to 0', () {
      final player = Player(id: 'p1', name: 'Test', isHuman: true);
      
      expect(player.consecutiveBadDraws, 0);
    });

    test('consecutiveBadDraws can be updated', () {
      final player = Player(id: 'p1', name: 'Test', isHuman: true);
      
      player.consecutiveBadDraws = 3;
      
      expect(player.consecutiveBadDraws, 3);
    });
  });
}
