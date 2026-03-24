import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/game/bot/bot_power_handler.dart';
import 'package:dutch_game/services/game/bot/bot_difficulty.dart';
import 'package:dutch_game/services/game/bot/bot_dutch_strategy.dart';
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
      BotDutchStrategy.discardTracker.reset();

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
        phase: GamePhase.specialPower,
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

      test('power V in duel can inject high known card into opponent',
          () async {
        bot.hand = [
          PlayingCard.create('hearts', 'D'),
          PlayingCard.create('diamonds', '3'),
          PlayingCard.create('clubs', '4'),
          PlayingCard.create('spades', '5'),
        ];
        bot.mentalMap = List<PlayingCard?>.from(bot.hand);
        bot.knownCards =
            List<bool>.filled(bot.hand.length, true, growable: true);

        human.hand = [
          PlayingCard.create('hearts', 'A'),
        ];
        human.knownCards =
            List<bool>.filled(human.hand.length, false, growable: true);

        bot.rememberSpiedCard(human.id, 0, human.hand[0]);

        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');

        await BotPowerHandler.useBotSpecialPower(
          gameState,
          BotDifficulty.platinum,
          null,
        );

        expect(human.hand[0].value, equals('D'));
        expect(
          gameState.actionHistory.any((entry) => entry.contains('Échange :')),
          isTrue,
        );
      });

      test('power V in duel no longer skips when fully known and calm',
          () async {
        bot.hand = [
          PlayingCard.create('hearts', '2'),
          PlayingCard.create('diamonds', '4'),
          PlayingCard.create('clubs', '6'),
          PlayingCard.create('spades', '8'),
        ];
        bot.knownCards =
            List<bool>.filled(bot.hand.length, true, growable: true);
        bot.mentalMap = List<PlayingCard?>.from(bot.hand);

        human.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '3'),
          PlayingCard.create('clubs', '5'),
          PlayingCard.create('spades', '7'),
        ];
        human.knownCards =
            List<bool>.filled(human.hand.length, false, growable: true);

        gameState.turnCount = 4;
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');

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
          gameState.actionHistory.any((entry) => entry.contains('Échange :')),
          isTrue,
        );
      });

      test(
          'power V in duel under pressure can swap unknown vs unknown to destabilize',
          () async {
        bot.hand = [
          PlayingCard.create('hearts', '2'),
          PlayingCard.create('diamonds', '4'),
          PlayingCard.create('clubs', '6'),
          PlayingCard.create('spades', '8'),
        ];
        bot.knownCards =
            List<bool>.filled(bot.hand.length, false, growable: true);
        bot.mentalMap =
            List<PlayingCard?>.filled(bot.hand.length, null, growable: true);

        human.hand = [
          PlayingCard.create('hearts', 'A'),
        ];
        human.knownCards =
            List<bool>.filled(human.hand.length, false, growable: true);

        gameState.turnCount = 10;
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');

        await BotPowerHandler.useBotSpecialPower(
          gameState,
          BotDifficulty.platinum,
          null,
        );

        expect(
          gameState.actionHistory.any((entry) => entry.contains('Échange :')),
          isTrue,
        );
        expect(
          gameState.actionHistory
              .any((entry) => entry.contains('ignore son pouvoir')),
          isFalse,
        );
        expect(human.hand[0].value, isNot(equals('A')));
      });

      test(
          'power V in duel opening can disrupt with unknown cards for moi style',
          () async {
        bot = bot.copyWith(
          botBehavior: BotBehavior.moi,
          botSkillLevel: BotSkillLevel.platinum,
        );
        gameState.players[1] = bot;

        bot.hand = [
          PlayingCard.create('hearts', '2'),
          PlayingCard.create('diamonds', '4'),
          PlayingCard.create('clubs', '6'),
          PlayingCard.create('spades', '8'),
        ];
        bot.knownCards =
            List<bool>.filled(bot.hand.length, false, growable: true);
        bot.mentalMap =
            List<PlayingCard?>.filled(bot.hand.length, null, growable: true);

        human.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '3'),
          PlayingCard.create('clubs', '5'),
          PlayingCard.create('spades', '7'),
        ];
        human.knownCards =
            List<bool>.filled(human.hand.length, false, growable: true);

        gameState.turnCount = 0;
        gameState.actionCount = 0;
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');

        await BotPowerHandler.useBotSpecialPower(
          gameState,
          BotDifficulty.platinum,
          null,
        );

        expect(
          gameState.actionHistory.any((entry) => entry.contains('Échange :')),
          isTrue,
        );
        expect(
          gameState.actionHistory
              .any((entry) => entry.contains('ignore son pouvoir')),
          isFalse,
        );
      });

      test(
          'power V in duel no longer skips when all known cards are good under pressure',
          () async {
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '2'),
          PlayingCard.create('clubs', '3'),
          PlayingCard.create('spades', '4'),
        ];
        bot.knownCards =
            List<bool>.filled(bot.hand.length, true, growable: true);
        bot.mentalMap = List<PlayingCard?>.from(bot.hand);

        human.hand = [
          PlayingCard.create('hearts', 'A'),
        ];
        human.knownCards =
            List<bool>.filled(human.hand.length, false, growable: true);

        gameState.turnCount = 12;
        gameState.actionCount = 30;
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');

        await BotPowerHandler.useBotSpecialPower(
          gameState,
          BotDifficulty.platinum,
          null,
        );

        expect(
          gameState.actionHistory
              .any((entry) => entry.contains('ignore son pouvoir')),
          isFalse,
        );
        expect(
          gameState.actionHistory.any((entry) => entry.contains('Échange :')),
          isTrue,
        );
      });

      test('power V in duel treats 8 as bad card in pressured endgame',
          () async {
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '2'),
          PlayingCard.create('clubs', '3'),
          PlayingCard.create('spades', '8'),
        ];
        bot.knownCards =
            List<bool>.filled(bot.hand.length, true, growable: true);
        bot.mentalMap = List<PlayingCard?>.from(bot.hand);

        human.hand = [
          PlayingCard.create('hearts', 'A'),
        ];
        human.knownCards =
            List<bool>.filled(human.hand.length, false, growable: true);

        gameState.turnCount = 12;
        gameState.actionCount = 30;
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');

        await BotPowerHandler.useBotSpecialPower(
          gameState,
          BotDifficulty.platinum,
          null,
        );

        expect(
          gameState.actionHistory.any((entry) => entry.contains('Échange :')),
          isTrue,
        );
        expect(
          gameState.actionHistory
              .any((entry) => entry.contains('ignore son pouvoir')),
          isFalse,
        );
      });

      test(
          'power V in duel adapts payload threshold when opponent rejects low instant cards',
          () async {
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '2'),
          PlayingCard.create('clubs', '3'),
          PlayingCard.create('spades', '7'),
        ];
        bot.knownCards =
            List<bool>.filled(bot.hand.length, true, growable: true);
        bot.mentalMap = List<PlayingCard?>.from(bot.hand);

        human.hand = [
          PlayingCard.create('hearts', 'A'),
        ];
        human.knownCards =
            List<bool>.filled(human.hand.length, false, growable: true);

        // L'adversaire rejette vite des petites cartes:
        // le seuil contextuel descend et 7 devient un payload valable.
        BotDutchStrategy.discardTracker.trackDiscard(
          PlayingCard.create('clubs', '3'),
          discardedBy: human.id,
          wasExchange: false,
        );
        BotDutchStrategy.discardTracker.trackDiscard(
          PlayingCard.create('spades', '2'),
          discardedBy: human.id,
          wasExchange: false,
        );
        BotDutchStrategy.discardTracker.trackDiscard(
          PlayingCard.create('diamonds', '4'),
          discardedBy: human.id,
          wasExchange: false,
        );

        gameState.turnCount = 12;
        gameState.actionCount = 30;
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');

        await BotPowerHandler.useBotSpecialPower(
          gameState,
          BotDifficulty.platinum,
          null,
        );

        expect(
          gameState.actionHistory.any((entry) => entry.contains('Échange :')),
          isTrue,
        );
      });

      test(
          'power V in duel adapts payload threshold when opponent replaces high cards often',
          () async {
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '2'),
          PlayingCard.create('clubs', '3'),
          PlayingCard.create('spades', '7'),
        ];
        bot.knownCards =
            List<bool>.filled(bot.hand.length, true, growable: true);
        bot.mentalMap = List<PlayingCard?>.from(bot.hand);

        human.hand = [
          PlayingCard.create('hearts', 'A'),
        ];
        human.knownCards =
            List<bool>.filled(human.hand.length, false, growable: true);

        // L'adversaire remplace et jette des cartes hautes:
        // signal d'optimisation, on réduit le seuil de payload.
        BotDutchStrategy.discardTracker.trackDiscard(
          PlayingCard.create('clubs', 'D'),
          discardedBy: human.id,
          wasExchange: true,
        );
        BotDutchStrategy.discardTracker.trackDiscard(
          PlayingCard.create('spades', '10'),
          discardedBy: human.id,
          wasExchange: true,
        );
        BotDutchStrategy.discardTracker.trackDiscard(
          PlayingCard.create('diamonds', 'V'),
          discardedBy: human.id,
          wasExchange: true,
        );
        BotDutchStrategy.discardTracker.trackDiscard(
          PlayingCard.create('hearts', '8'),
          discardedBy: human.id,
          wasExchange: true,
        );

        gameState.turnCount = 12;
        gameState.actionCount = 30;
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');

        await BotPowerHandler.useBotSpecialPower(
          gameState,
          BotDifficulty.platinum,
          null,
        );

        expect(
          gameState.actionHistory.any((entry) => entry.contains('Échange :')),
          isTrue,
        );
      });

      test('power JOKER shuffles target hand', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'JOKER');

        await BotPowerHandler.useBotSpecialPower(
            gameState, BotDifficulty.platinum, null);

        // Power should complete without error
        expect(gameState.isWaitingForSpecialPower, isFalse);
      });

      test('platinum never skips JOKER in calm duel', () async {
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '2'),
          PlayingCard.create('clubs', '3'),
          PlayingCard.create('spades', '4'),
        ];
        bot.knownCards =
            List<bool>.filled(bot.hand.length, true, growable: true);
        bot.mentalMap = List<PlayingCard?>.from(bot.hand);

        human.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '3'),
          PlayingCard.create('clubs', '5'),
          PlayingCard.create('spades', '7'),
        ];
        human.knownCards =
            List<bool>.filled(human.hand.length, false, growable: true);

        gameState.turnCount = 1;
        gameState.actionCount = 2;
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'JOKER');

        await BotPowerHandler.useBotSpecialPower(
          gameState,
          BotDifficulty.platinum,
          null,
        );

        expect(
          gameState.actionHistory
              .any((entry) => entry.contains('ignore son pouvoir')),
          isFalse,
        );
        expect(
          gameState.actionHistory.any((entry) => entry.contains('JOKER !')),
          isTrue,
        );
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

      test('silver power 7 checks first unknown card', () async {
        bot.mentalMap = [
          bot.hand[0],
          null,
          null,
          bot.hand[3],
        ];
        bot.knownCards = [true, false, false, true];

        gameState.actionCount = 10; // > 3 tours bot
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        await BotPowerHandler.useBotSpecialPower(
          gameState,
          BotDifficulty.silver,
          null,
        );

        expect(bot.mentalMap[1], equals(bot.hand[1]));
      });

      test('silver power 7 can be skipped when recently attacked', () async {
        bot.mentalMap = [
          bot.hand[0],
          null,
          null,
          bot.hand[3],
        ];
        bot.knownCards = [true, false, false, true];
        gameState.turnCount = 12;
        gameState.actionCount = 10;
        bot.lastTargetedByPowerTurn = 10;

        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        await BotPowerHandler.useBotSpecialPower(
          gameState,
          BotDifficulty.silver,
          null,
        );

        expect(
          gameState.isWaitingForSpecialPower,
          isFalse,
        );
        expect(
          gameState.specialCardToActivate,
          isNull,
        );
        expect(
          gameState.actionHistory
              .any((entry) => entry.contains('a utilisé son pouvoir')),
          isFalse,
        );
      });

      test('silver power 10 marks target as recently attacked', () async {
        human.hand = [PlayingCard.create('hearts', 'A')];
        human.knownCards = [false];
        gameState.turnCount = 7;
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '10');

        await BotPowerHandler.useBotSpecialPower(
          gameState,
          BotDifficulty.silver,
          null,
        );

        expect(human.lastTargetedByPowerTurn, equals(7));
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

      test(
          'bronze joker targets the player with the fewest cards above one, even human',
          () async {
        final bot2 =
            Player(id: 'bot2', name: 'Bot 2', isHuman: false, position: 2)
              ..hand = [
                PlayingCard.create('hearts', '9'),
                PlayingCard.create('diamonds', '10'),
                PlayingCard.create('clubs', 'V'),
              ]
              ..knownCards = List.filled(3, true, growable: true);
        gameState.players.add(bot2);

        human.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '5'),
        ];
        human.knownCards = List.filled(2, true, growable: true);

        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'JOKER');

        await BotPowerHandler.useBotSpecialPower(
          gameState,
          BotDifficulty.bronze,
          null,
        );

        expect(human.knownCards.every((k) => k == false), isTrue);
        expect(bot2.knownCards.every((k) => k == true), isTrue);
        expect(human.lastTargetedByPowerTurn, equals(gameState.turnCount));
      });

      test('bronze joker does not prioritize human on equal danger', () async {
        final bot2 = Player(
          id: 'bot2',
          name: 'Bot 2',
          isHuman: false,
          position: 2,
          botSkillLevel: BotSkillLevel.gold,
        )
          ..hand = [
            PlayingCard.create('hearts', '9'),
            PlayingCard.create('diamonds', '10'),
          ]
          ..knownCards = List.filled(2, true, growable: true);
        gameState.players.add(bot2);

        human.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '5'),
        ];
        human.knownCards = List.filled(2, true, growable: true);

        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'JOKER');

        await BotPowerHandler.useBotSpecialPower(
          gameState,
          BotDifficulty.bronze,
          null,
        );

        expect(bot2.knownCards.every((k) => k == false), isTrue);
        expect(human.knownCards.every((k) => k == true), isTrue);
      });

      test('bronze valet never targets the same player twice', () async {
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
          gameState,
          BotDifficulty.bronze,
          null,
        );

        final exchange = gameState.actionHistory
            .firstWhere((e) => e.contains('Échange :'), orElse: () => '');
        final match = RegExp(r'Échange : (.+) carte #\d+ ↔ (.+) carte #\d+\.')
            .firstMatch(exchange);
        expect(match, isNotNull);
        expect(match!.group(1), isNot(equals(match.group(2))));
      });

      test('bronze valet protects a recently attacked human', () async {
        final bot2 =
            Player(id: 'bot2', name: 'Bot 2', isHuman: false, position: 2)
              ..hand = [
                PlayingCard.create('hearts', '9'),
                PlayingCard.create('diamonds', '10'),
              ]
              ..knownCards = List.filled(2, false, growable: true);
        gameState.players.add(bot2);

        gameState.turnCount = 10;
        human.lastBronzeValetTargetTurn =
            7; // attaqué dans les 4 derniers tours

        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');

        await BotPowerHandler.useBotSpecialPower(
          gameState,
          BotDifficulty.bronze,
          null,
        );

        final exchange = gameState.actionHistory
            .firstWhere((e) => e.contains('Échange :'), orElse: () => '');
        expect(exchange.contains('Human'), isFalse);
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

      test('targets the two strongest players', () async {
        final main = makePlayer(
          'main',
          'Main',
          isHuman: false,
          cards: 4,
          skill: BotSkillLevel.gold,
          position: 0,
        )..initializeBotMemory();
        final strongest = makePlayer(
          's1',
          'Strongest',
          isHuman: false,
          cards: 2,
          skill: BotSkillLevel.platinum,
          position: 1,
        );
        final secondStrongest = makePlayer(
          's2',
          'Second',
          isHuman: false,
          cards: 3,
          skill: BotSkillLevel.gold,
          position: 2,
        );
        final human = makePlayer(
          'h1',
          'Human',
          isHuman: true,
          cards: 3,
          position: 3,
        );
        final weak = makePlayer(
          'w1',
          'Weak',
          isHuman: false,
          cards: 4,
          skill: BotSkillLevel.bronze,
          position: 4,
        );

        final gs = GameState(
          players: [main, strongest, secondStrongest, human, weak],
          deck: GameState.createFullDeck().sublist(0, 30),
          discardPile: [PlayingCard.create('hearts', '6')],
          currentPlayerIndex: 0,
          phase: GamePhase.specialPower,
        )
          ..isWaitingForSpecialPower = true
          ..specialCardToActivate = PlayingCard.create('hearts', 'V');

        await BotPowerHandler.useBotSpecialPower(gs, BotDifficulty.gold, null);

        final exchange = gs.actionHistory
            .firstWhere((e) => e.contains('Échange :'), orElse: () => '');
        expect(exchange, contains('Strongest'));
        expect(exchange, contains('Second'));
        expect(exchange.contains('Human'), isFalse);
      });

      test('includes a human when target choice is ambiguous', () async {
        final main = makePlayer(
          'main',
          'Main',
          isHuman: false,
          cards: 4,
          skill: BotSkillLevel.platinum,
          position: 0,
        )..initializeBotMemory();
        final strongest = makePlayer(
          's1',
          'Strongest',
          isHuman: false,
          cards: 2,
          skill: BotSkillLevel.platinum,
          position: 1,
        );
        final tieA = makePlayer(
          't1',
          'Tie A',
          isHuman: false,
          cards: 3,
          skill: BotSkillLevel.silver,
          position: 2,
        );
        final tieB = makePlayer(
          't2',
          'Tie B',
          isHuman: false,
          cards: 3,
          skill: BotSkillLevel.silver,
          position: 3,
        );
        final human = makePlayer(
          'h1',
          'Human',
          isHuman: true,
          cards: 4,
          position: 4,
        );

        final gs = GameState(
          players: [main, strongest, tieA, tieB, human],
          deck: GameState.createFullDeck().sublist(0, 30),
          discardPile: [PlayingCard.create('hearts', '6')],
          currentPlayerIndex: 0,
          phase: GamePhase.specialPower,
        )
          ..isWaitingForSpecialPower = true
          ..specialCardToActivate = PlayingCard.create('hearts', 'V');

        await BotPowerHandler.useBotSpecialPower(
            gs, BotDifficulty.platinum, null);

        final exchange = gs.actionHistory
            .firstWhere((e) => e.contains('Échange :'), orElse: () => '');
        expect(exchange, contains('Strongest'));
        expect(exchange, contains('Human'));
      });

      test('keeps strongest pair when no human is available', () async {
        final main = makePlayer(
          'main',
          'Main',
          isHuman: false,
          cards: 4,
          skill: BotSkillLevel.platinum,
          position: 0,
        )..initializeBotMemory();
        final first = makePlayer(
          'f1',
          'First',
          isHuman: false,
          cards: 2,
          skill: BotSkillLevel.gold,
          position: 1,
        );
        final second = makePlayer(
          'f2',
          'Second',
          isHuman: false,
          cards: 3,
          skill: BotSkillLevel.gold,
          position: 2,
        );
        final third = makePlayer(
          'f3',
          'Third',
          isHuman: false,
          cards: 3,
          skill: BotSkillLevel.bronze,
          position: 3,
        );

        final gs = GameState(
          players: [main, first, second, third],
          deck: GameState.createFullDeck().sublist(0, 30),
          discardPile: [PlayingCard.create('hearts', '6')],
          currentPlayerIndex: 0,
          phase: GamePhase.specialPower,
        )
          ..isWaitingForSpecialPower = true
          ..specialCardToActivate = PlayingCard.create('hearts', 'V');

        await BotPowerHandler.useBotSpecialPower(
            gs, BotDifficulty.platinum, null);

        final exchange = gs.actionHistory
            .firstWhere((e) => e.contains('Échange :'), orElse: () => '');
        expect(exchange, contains('First'));
        expect(exchange, contains('Second'));
      });

      test('human with 2 cards is always top valet threat', () async {
        final main = makePlayer(
          'main',
          'Main',
          isHuman: false,
          cards: 4,
          skill: BotSkillLevel.platinum,
          position: 0,
        )..initializeBotMemory();
        final botOneCard = makePlayer(
          'b1',
          'Bot One',
          isHuman: false,
          cards: 1,
          skill: BotSkillLevel.platinum,
          position: 1,
        );
        final botTwoCards = makePlayer(
          'b2',
          'Bot Two',
          isHuman: false,
          cards: 2,
          skill: BotSkillLevel.platinum,
          position: 2,
        );
        final humanTwoCards = makePlayer(
          'h1',
          'Human Two',
          isHuman: true,
          cards: 2,
          position: 3,
        );

        final gs = GameState(
          players: [main, botOneCard, botTwoCards, humanTwoCards],
          deck: GameState.createFullDeck().sublist(0, 30),
          discardPile: [PlayingCard.create('hearts', '6')],
          currentPlayerIndex: 0,
          phase: GamePhase.specialPower,
        )
          ..isWaitingForSpecialPower = true
          ..specialCardToActivate = PlayingCard.create('hearts', 'V');

        await BotPowerHandler.useBotSpecialPower(
            gs, BotDifficulty.platinum, null);

        final exchange = gs.actionHistory
            .firstWhere((e) => e.contains('Échange :'), orElse: () => '');
        expect(exchange, contains('Human Two'));
      });

      test(
          'platinum behind in near-duel uses known high donor card for variance sabotage',
          () async {
        final main = makePlayer(
          'main',
          'Main',
          isHuman: false,
          cards: 4,
          skill: BotSkillLevel.platinum,
          position: 0,
        )..initializeBotMemory();
        final strongest = makePlayer(
          's1',
          'Strongest',
          isHuman: false,
          cards: 2,
          skill: BotSkillLevel.platinum,
          position: 1,
        );
        final contender = makePlayer(
          'c1',
          'Contender',
          isHuman: false,
          cards: 3,
          skill: BotSkillLevel.gold,
          position: 2,
        );
        final donor = makePlayer(
          'd1',
          'Donor',
          isHuman: false,
          cards: 4,
          skill: BotSkillLevel.bronze,
          position: 3,
        );

        main.rememberSpiedCard(
          donor.id,
          0,
          PlayingCard.create('hearts', 'D'),
        );

        final gs = GameState(
          players: [main, strongest, contender, donor],
          deck: GameState.createFullDeck().sublist(0, 30),
          discardPile: [PlayingCard.create('hearts', '6')],
          currentPlayerIndex: 0,
          phase: GamePhase.specialPower,
        )
          ..isWaitingForSpecialPower = true
          ..specialCardToActivate = PlayingCard.create('hearts', 'V');

        await BotPowerHandler.useBotSpecialPower(
          gs,
          BotDifficulty.platinum,
          null,
        );

        final exchange = gs.actionHistory
            .firstWhere((e) => e.contains('Échange :'), orElse: () => '');
        expect(exchange, contains('Strongest'));
        expect(exchange, contains('Donor'));
        expect(exchange.contains('Contender'), isFalse);
      });

      test('never targets players with zero cards', () async {
        final main = makePlayer(
          'main',
          'Main',
          isHuman: false,
          cards: 4,
          skill: BotSkillLevel.gold,
          position: 0,
        )..initializeBotMemory();
        final activeA = makePlayer(
          'a1',
          'Active A',
          isHuman: false,
          cards: 2,
          skill: BotSkillLevel.gold,
          position: 1,
        );
        final activeB = makePlayer(
          'a2',
          'Active B',
          isHuman: true,
          cards: 3,
          position: 2,
        );
        final emptyPlayer = makePlayer(
          'z0',
          'Zero',
          isHuman: true,
          cards: 1,
          position: 3,
        )
          ..hand = <PlayingCard>[]
          ..knownCards = <bool>[];

        final gs = GameState(
          players: [main, activeA, activeB, emptyPlayer],
          deck: GameState.createFullDeck().sublist(0, 30),
          discardPile: [PlayingCard.create('hearts', '6')],
          currentPlayerIndex: 0,
          phase: GamePhase.specialPower,
        )
          ..isWaitingForSpecialPower = true
          ..specialCardToActivate = PlayingCard.create('hearts', 'V');

        await BotPowerHandler.useBotSpecialPower(gs, BotDifficulty.gold, null);

        final exchange = gs.actionHistory
            .firstWhere((e) => e.contains('Échange :'), orElse: () => '');
        expect(exchange.contains('Zero'), isFalse);
      });
    });
  });
}
