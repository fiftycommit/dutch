import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/game/bot/bot_power_handler.dart';
import 'package:dutch_game/services/game/bot/bot_difficulty.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';

void main() {
  group('BotPowerHandler', () {
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

    group('useBotSpecialPower', () {
      test('returns early when not waiting for special power', () async {
        gameState.isWaitingForSpecialPower = false;
        gameState.specialCardToActivate = null;

        // Should complete without error
        await BotPowerHandler.useBotSpecialPower(
            gameState, BotDifficulty.gold, null);

        expect(gameState.isWaitingForSpecialPower, isFalse);
      });

      test('returns early when special card is null', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = null;

        await BotPowerHandler.useBotSpecialPower(
            gameState, BotDifficulty.gold, null);

        // Should not change state
        expect(gameState.isWaitingForSpecialPower, isTrue);
      });

      test('handles power 7 - look at own card', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        await BotPowerHandler.useBotSpecialPower(
            gameState, BotDifficulty.gold, null);

        expect(gameState.isWaitingForSpecialPower, isFalse);
        expect(gameState.specialCardToActivate, isNull);
      });

      test('handles power 10 - spy on opponent (no context)', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '10');

        await BotPowerHandler.useBotSpecialPower(
            gameState, BotDifficulty.gold, null);

        expect(gameState.isWaitingForSpecialPower, isFalse);
        expect(gameState.specialCardToActivate, isNull);
      });

      test('handles power V - swap cards (no context)', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');

        await BotPowerHandler.useBotSpecialPower(
            gameState, BotDifficulty.gold, null);

        expect(gameState.isWaitingForSpecialPower, isFalse);
        expect(gameState.specialCardToActivate, isNull);
      });

      test('handles power JOKER - shuffle hand (no context)', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'JOKER');

        await BotPowerHandler.useBotSpecialPower(
            gameState, BotDifficulty.gold, null);

        expect(gameState.isWaitingForSpecialPower, isFalse);
        expect(gameState.specialCardToActivate, isNull);
      });
    });

    group('difficulty effects on powers', () {
      test('bronze uses powers', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        await BotPowerHandler.useBotSpecialPower(
            gameState, BotDifficulty.bronze, null);

        expect(gameState.isWaitingForSpecialPower, isFalse);
      });

      test('silver uses powers', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        await BotPowerHandler.useBotSpecialPower(
            gameState, BotDifficulty.silver, null);

        expect(gameState.isWaitingForSpecialPower, isFalse);
      });

      test('gold uses powers', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        await BotPowerHandler.useBotSpecialPower(
            gameState, BotDifficulty.gold, null);

        expect(gameState.isWaitingForSpecialPower, isFalse);
      });

      test('platinum uses powers', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        await BotPowerHandler.useBotSpecialPower(
            gameState, BotDifficulty.platinum, null);

        expect(gameState.isWaitingForSpecialPower, isFalse);
      });
    });

    group('power effects on game state', () {
      test('power 7 updates bot mental map', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        // Initially bot may not know all cards
        int initialKnown = bot.mentalMap.where((c) => c != null).length;

        await BotPowerHandler.useBotSpecialPower(
            gameState, BotDifficulty.platinum, null);

        int finalKnown = bot.mentalMap.where((c) => c != null).length;
        expect(finalKnown, greaterThanOrEqualTo(initialKnown));
      });

      test('gold does not skip power 7 even with fully known hand', () async {
        bot.knownCards = List.filled(bot.hand.length, true, growable: true);
        bot.mentalMap = List<PlayingCard?>.from(bot.hand);

        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        await BotPowerHandler.useBotSpecialPower(
          gameState,
          BotDifficulty.gold,
          null,
        );

        expect(
          gameState.actionHistory
              .any((entry) => entry.contains('ignore son pouvoir')),
          isFalse,
        );
        expect(
          gameState.actionHistory
              .any((entry) => entry.contains('a utilisé son pouvoir')),
          isTrue,
        );
      });

      test('power V may swap cards', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');

        // Store original hands
        final originalBotHand = List<PlayingCard>.from(bot.hand);
        final originalHumanHand = List<PlayingCard>.from(human.hand);

        await BotPowerHandler.useBotSpecialPower(
            gameState, BotDifficulty.platinum, null);

        // Hands should still have same length
        expect(bot.hand.length, equals(originalBotHand.length));
        expect(human.hand.length, equals(originalHumanHand.length));
      });

      test('power JOKER shuffles target hand', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'JOKER');

        await BotPowerHandler.useBotSpecialPower(
            gameState, BotDifficulty.platinum, null);

        // Power should complete without error
        expect(gameState.isWaitingForSpecialPower, isFalse);
      });

      test('power 7 targets hinted unknown for platinum', () async {
        bot.mentalMap = [
          bot.hand[0],
          bot.hand[1],
          null,
          null,
        ];
        bot.knownCards = [true, true, false, false];
        bot.setUnknownCardHint(2,
            quality: -0.9, confidence: 0.8, actionCount: gameState.actionCount);
        bot.setUnknownCardHint(3,
            quality: 0.8, confidence: 0.95, actionCount: gameState.actionCount);

        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        await BotPowerHandler.useBotSpecialPower(
          gameState,
          BotDifficulty.platinum,
          null,
        );

        expect(bot.mentalMap[3], equals(bot.hand[3]));
      });

      test('power 7 prioritizes swapped unknown card for gold', () async {
        bot.mentalMap = [
          bot.hand[0],
          bot.hand[1],
          null,
          null,
        ];
        bot.knownCards = [true, true, false, false];
        bot.setUnknownCardHint(
          2,
          quality: 0.1,
          confidence: 0.8,
          actionCount: gameState.actionCount,
        );

        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        await BotPowerHandler.useBotSpecialPower(
          gameState,
          BotDifficulty.gold,
          null,
        );

        expect(bot.mentalMap[2], equals(bot.hand[2]));
      });
    });

    group('multiple opponents', () {
      test('handles game with 3 players', () async {
        final bot2 =
            Player(id: 'bot2', name: 'Bot 2', isHuman: false, position: 2)
              ..hand = [
                PlayingCard.create('hearts', '9'),
                PlayingCard.create('diamonds', '10'),
              ]
              ..knownCards = List.filled(2, false, growable: true);
        gameState.players.add(bot2);

        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');

        await BotPowerHandler.useBotSpecialPower(
            gameState, BotDifficulty.gold, null);

        expect(gameState.isWaitingForSpecialPower, isFalse);
      });

      test('handles game with 4 players', () async {
        final bot2 =
            Player(id: 'bot2', name: 'Bot 2', isHuman: false, position: 2)
              ..hand = [PlayingCard.create('hearts', '9')]
              ..knownCards = List.filled(1, false, growable: true);
        final bot3 =
            Player(id: 'bot3', name: 'Bot 3', isHuman: false, position: 3)
              ..hand = [PlayingCard.create('diamonds', 'D')]
              ..knownCards = List.filled(1, false, growable: true);
        gameState.players.addAll([bot2, bot3]);

        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '10');

        await BotPowerHandler.useBotSpecialPower(
            gameState, BotDifficulty.platinum, null);

        expect(gameState.isWaitingForSpecialPower, isFalse);
      });

      test('bronze avoids targeting human while human has more than one card',
          () async {
        final bot2 =
            Player(id: 'bot2', name: 'Bot 2', isHuman: false, position: 2)
              ..hand = [
                PlayingCard.create('hearts', '9'),
                PlayingCard.create('diamonds', '10'),
              ]
              ..knownCards = List.filled(2, false, growable: true);
        gameState.players.add(bot2);

        // Humain "ami" avec >1 carte
        human.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '5'),
          PlayingCard.create('clubs', '8'),
          PlayingCard.create('spades', 'R'),
        ];

        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '10');

        await BotPowerHandler.useBotSpecialPower(
          gameState,
          BotDifficulty.bronze,
          null,
        );

        expect(bot.spyMemory.containsKey(human.id), isFalse);
      });
    });

    group('gold/platinum valet targeting rules', () {
      List<PlayingCard> makeHand(int size) {
        final seed = <PlayingCard>[
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '3'),
          PlayingCard.create('clubs', '5'),
          PlayingCard.create('spades', '8'),
          PlayingCard.create('hearts', '10'),
        ];
        return List<PlayingCard>.from(seed.take(size));
      }

      Player makePlayer(
        String id,
        String name, {
        required bool isHuman,
        required int cards,
        BotSkillLevel? skill,
        int position = 0,
      }) {
        return Player(
          id: id,
          name: name,
          isHuman: isHuman,
          botSkillLevel: skill,
          position: position,
        )
          ..hand = makeHand(cards)
          ..knownCards = List<bool>.filled(cards, false, growable: true);
      }

      test('targets two boosted bots first (min cards, tie by ranking)',
          () async {
        final main = makePlayer(
          'main',
          'Main',
          isHuman: false,
          cards: 4,
          skill: BotSkillLevel.gold,
          position: 0,
        )..initializeBotMemory();
        final boostedA = makePlayer(
          'boosted_a',
          'Boosted A',
          isHuman: false,
          cards: 2,
          skill: BotSkillLevel.gold,
          position: 1,
        );
        final boostedB = makePlayer(
          'boosted_b',
          'Boosted B',
          isHuman: false,
          cards: 2,
          skill: BotSkillLevel.platinum,
          position: 2,
        );
        final slowBot = makePlayer(
          'slow',
          'Slow Bot',
          isHuman: false,
          cards: 4,
          skill: BotSkillLevel.bronze,
          position: 3,
        );
        final human = makePlayer(
          'human_x',
          'Human X',
          isHuman: true,
          cards: 4,
          position: 4,
        );

        final gs = GameState(
          players: [main, boostedA, boostedB, slowBot, human],
          deck: GameState.createFullDeck().sublist(0, 30),
          discardPile: [PlayingCard.create('hearts', '6')],
          currentPlayerIndex: 0,
          phase: GamePhase.playing,
        )
          ..isWaitingForSpecialPower = true
          ..specialCardToActivate = PlayingCard.create('hearts', 'V');

        await BotPowerHandler.useBotSpecialPower(gs, BotDifficulty.gold, null);

        final exchange = gs.actionHistory
            .firstWhere((e) => e.contains('Échange :'), orElse: () => '');
        expect(exchange, contains('Boosted A'));
        expect(exchange, contains('Boosted B'));
        expect(exchange.contains('Slow Bot'), isFalse);
      });

      test('with one boosted bot, pairs it with best other bot', () async {
        final main = makePlayer(
          'main',
          'Main',
          isHuman: false,
          cards: 4,
          skill: BotSkillLevel.gold,
          position: 0,
        )..initializeBotMemory();
        final boosted = makePlayer(
          'boosted',
          'Boosted',
          isHuman: false,
          cards: 2,
          skill: BotSkillLevel.silver,
          position: 1,
        );
        final topBot = makePlayer(
          'top_bot',
          'Top Bot',
          isHuman: false,
          cards: 4,
          skill: BotSkillLevel.platinum,
          position: 2,
        );
        final lowBot = makePlayer(
          'low_bot',
          'Low Bot',
          isHuman: false,
          cards: 4,
          skill: BotSkillLevel.bronze,
          position: 3,
        );
        final human = makePlayer(
          'human_x',
          'Human X',
          isHuman: true,
          cards: 3,
          position: 4,
        );

        final gs = GameState(
          players: [main, boosted, topBot, lowBot, human],
          deck: GameState.createFullDeck().sublist(0, 30),
          discardPile: [PlayingCard.create('hearts', '6')],
          currentPlayerIndex: 0,
          phase: GamePhase.playing,
        )
          ..isWaitingForSpecialPower = true
          ..specialCardToActivate = PlayingCard.create('hearts', 'V');

        await BotPowerHandler.useBotSpecialPower(gs, BotDifficulty.gold, null);

        final exchange = gs.actionHistory
            .firstWhere((e) => e.contains('Échange :'), orElse: () => '');
        expect(exchange, contains('Boosted'));
        expect(exchange, contains('Top Bot'));
        expect(exchange.contains('Human X'), isFalse);
      });

      test('when no boosted and hand known, swaps top bot with top human',
          () async {
        final main = makePlayer(
          'main',
          'Main',
          isHuman: false,
          cards: 4,
          skill: BotSkillLevel.platinum,
          position: 0,
        )
          ..knownCards = List<bool>.filled(4, true, growable: true)
          ..mentalMap = List<PlayingCard?>.from(makeHand(4));
        final topBot = makePlayer(
          'top_bot',
          'Top Bot',
          isHuman: false,
          cards: 4,
          skill: BotSkillLevel.platinum,
          position: 1,
        );
        final lowBot = makePlayer(
          'low_bot',
          'Low Bot',
          isHuman: false,
          cards: 4,
          skill: BotSkillLevel.bronze,
          position: 2,
        );
        final humanA = makePlayer(
          'human_a',
          'Human A',
          isHuman: true,
          cards: 3,
          position: 3,
        );
        final humanB = makePlayer(
          'human_b',
          'Human B',
          isHuman: true,
          cards: 4,
          position: 4,
        );

        final gs = GameState(
          players: [main, topBot, lowBot, humanA, humanB],
          deck: GameState.createFullDeck().sublist(0, 30),
          discardPile: [PlayingCard.create('hearts', '6')],
          currentPlayerIndex: 0,
          phase: GamePhase.playing,
        )
          ..isWaitingForSpecialPower = true
          ..specialCardToActivate = PlayingCard.create('hearts', 'V');

        await BotPowerHandler.useBotSpecialPower(
            gs, BotDifficulty.platinum, null);

        final exchange = gs.actionHistory
            .firstWhere((e) => e.contains('Échange :'), orElse: () => '');
        expect(exchange, contains('Top Bot'));
        expect(exchange, contains('Human A'));
      });
    });
  });
}
