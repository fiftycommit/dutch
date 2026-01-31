import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/providers/managers/solo/special_power_handler.dart';
import 'package:dutch_game/providers/game_tracking_provider.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';

/// Mock GameTrackingProvider for testing
class MockGameTrackingProvider extends GameTrackingProvider {
  final List<Map<String, dynamic>> recordedActions = [];
  Map<String, dynamic>? lastUpdateResult;

  @override
  void recordPlayerAction({
    required String actionType,
    required GameState gameState,
    Map<String, dynamic>? actionDetails,
    String? powerType,
    String? targetStrategy,
  }) {
    recordedActions.add({
      'actionType': actionType,
      'actionDetails': actionDetails,
      'powerType': powerType,
      'targetStrategy': targetStrategy,
    });
  }

  @override
  void updateLastActionResult({required Map<String, dynamic> result}) {
    lastUpdateResult = result;
  }
}

void main() {
  group('SpecialPowerHandler', () {
    late SpecialPowerHandler handler;
    late MockGameTrackingProvider mockTrackingProvider;
    late GameState gameState;
    late Player human;
    late Player bot;

    setUp(() {
      mockTrackingProvider = MockGameTrackingProvider();
      handler = SpecialPowerHandler(trackingProvider: mockTrackingProvider);

      human = Player(id: 'human', name: 'Human', isHuman: true, position: 0);
      bot = Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1);

      human.hand = [
        PlayingCard.create('hearts', 'A'),
        PlayingCard.create('diamonds', '5'),
        PlayingCard.create('clubs', '8'),
        PlayingCard.create('spades', 'R'),
      ];
      human.knownCards = [true, false, false, false];

      bot.hand = [
        PlayingCard.create('hearts', '2'),
        PlayingCard.create('diamonds', '3'),
        PlayingCard.create('clubs', '4'),
        PlayingCard.create('spades', '5'),
      ];
      bot.knownCards = List.filled(4, false, growable: true);

      gameState = GameState(
        players: [human, bot],
        deck: GameState.createFullDeck().sublist(0, 40),
        discardPile: [PlayingCard.create('hearts', '6')],
        currentPlayerIndex: 0,
        phase: GamePhase.playing,
      );
    });

    group('skipPower', () {
      test('clears special power state', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        handler.skipPower(gameState);

        expect(gameState.isWaitingForSpecialPower, isFalse);
        expect(gameState.specialCardToActivate, isNull);
      });

      test('adds to history', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');
        final historyBefore = gameState.actionHistory.length;

        handler.skipPower(gameState);

        expect(gameState.actionHistory.length, greaterThan(historyBefore));
      });

      test('records action for human player', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        handler.skipPower(gameState);

        expect(mockTrackingProvider.recordedActions, isNotEmpty);
        expect(mockTrackingProvider.recordedActions.last['actionType'], 'power_skip');
      });

      test('does not record for bot player', () {
        gameState.currentPlayerIndex = 1; // Bot
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        handler.skipPower(gameState);

        expect(mockTrackingProvider.recordedActions, isEmpty);
      });
    });

    group('usePower - Power 7/8 (look at own card)', () {
      test('marks card as known', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');
        human.knownCards[2] = false;

        handler.usePower(gameState, 0, 2);

        expect(human.knownCards[2], isTrue);
      });

      test('clears special power state', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        handler.usePower(gameState, 0, 0);

        expect(gameState.isWaitingForSpecialPower, isFalse);
        expect(gameState.specialCardToActivate, isNull);
      });

      test('adds to history', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '8');
        final historyBefore = gameState.actionHistory.length;

        handler.usePower(gameState, 0, 1);

        expect(gameState.actionHistory.length, greaterThan(historyBefore));
      });

      test('records action', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        handler.usePower(gameState, 0, 0);

        expect(mockTrackingProvider.recordedActions, isNotEmpty);
        expect(mockTrackingProvider.recordedActions.last['powerType'], '7');
      });
    });

    group('usePower - Power 9/10 (spy on opponent)', () {
      test('sets lastSpiedCard', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '10');

        handler.usePower(gameState, 1, 0); // Spy on bot, card 0

        expect(gameState.lastSpiedCard, isNotNull);
        expect(gameState.lastSpiedCard, equals(bot.hand[0]));
      });

      test('adds to history', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '9');
        final historyBefore = gameState.actionHistory.length;

        handler.usePower(gameState, 1, 0);

        expect(gameState.actionHistory.length, greaterThan(historyBefore));
      });

      test('clears special power state', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '10');

        handler.usePower(gameState, 1, 0);

        expect(gameState.isWaitingForSpecialPower, isFalse);
      });
    });

    group('usePower - Power V (Jack - swap)', () {
      test('sets pendingSwap and does not clear power state', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');

        handler.usePower(gameState, 1, 0);

        expect(gameState.pendingSwap, isNotNull);
        expect(gameState.pendingSwap!['targetPlayer'], 1);
        expect(gameState.pendingSwap!['targetCard'], 0);
        // Power state should NOT be cleared yet (waiting for own card selection)
        expect(gameState.isWaitingForSpecialPower, isTrue);
      });
    });

    group('completeSwap', () {
      test('swaps cards between players', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');
        gameState.pendingSwap = {
          'targetPlayer': 1,
          'targetCard': 0,
          'ownCard': null,
        };

        final humanCard = human.hand[0];
        final botCard = bot.hand[0];

        handler.completeSwap(gameState, 0);

        expect(human.hand[0], equals(botCard));
        expect(bot.hand[0], equals(humanCard));
      });

      test('marks swapped cards as unknown', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');
        gameState.pendingSwap = {
          'targetPlayer': 1,
          'targetCard': 0,
          'ownCard': null,
        };
        human.knownCards[0] = true;

        handler.completeSwap(gameState, 0);

        expect(human.knownCards[0], isFalse);
        expect(bot.knownCards[0], isFalse);
      });

      test('clears pendingSwap and special power state', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');
        gameState.pendingSwap = {
          'targetPlayer': 1,
          'targetCard': 0,
          'ownCard': null,
        };

        handler.completeSwap(gameState, 0);

        expect(gameState.pendingSwap, isNull);
        expect(gameState.isWaitingForSpecialPower, isFalse);
        expect(gameState.specialCardToActivate, isNull);
      });

      test('does nothing when pendingSwap is null', () {
        gameState.pendingSwap = null;
        final handBefore = List<PlayingCard>.from(human.hand);

        handler.completeSwap(gameState, 0);

        expect(human.hand, equals(handBefore));
      });

      test('adds to history', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');
        gameState.pendingSwap = {
          'targetPlayer': 1,
          'targetCard': 0,
          'ownCard': null,
        };
        final historyBefore = gameState.actionHistory.length;

        handler.completeSwap(gameState, 0);

        expect(gameState.actionHistory.length, greaterThan(historyBefore));
      });
    });

    group('executeLookAtCard', () {
      test('sets lastSpiedCard', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        handler.executeLookAtCard(gameState, human, 0);

        expect(gameState.lastSpiedCard, isNotNull);
      });

      test('marks human card as known', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');
        human.knownCards[1] = false;

        handler.executeLookAtCard(gameState, human, 1);

        expect(human.knownCards[1], isTrue);
      });

      test('does not mark bot card as known', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '10');

        handler.executeLookAtCard(gameState, bot, 0);

        expect(bot.knownCards[0], isFalse);
      });

      test('clears special power state', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        handler.executeLookAtCard(gameState, human, 0);

        expect(gameState.isWaitingForSpecialPower, isFalse);
        expect(gameState.specialCardToActivate, isNull);
      });

      test('handles invalid card index gracefully', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        // Should not throw
        handler.executeLookAtCard(gameState, human, 100);

        expect(gameState.isWaitingForSpecialPower, isFalse);
      });
    });

    group('executeJokerEffect', () {
      test('shuffles target hand', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('joker', 'JOKER');

        handler.executeJokerEffect(gameState, bot);

        // Hand should still have same length
        expect(bot.hand.length, 4);
      });

      test('resets human knownCards', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('joker', 'JOKER');
        human.knownCards = [true, true, true, true];

        handler.executeJokerEffect(gameState, human);

        expect(human.knownCards, everyElement(isFalse));
      });

      test('clears special power state', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('joker', 'JOKER');

        handler.executeJokerEffect(gameState, bot);

        expect(gameState.isWaitingForSpecialPower, isFalse);
        expect(gameState.specialCardToActivate, isNull);
      });

      test('records action for human', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('joker', 'JOKER');

        handler.executeJokerEffect(gameState, bot);

        expect(mockTrackingProvider.recordedActions, isNotEmpty);
      });
    });

    group('usePower returns early when no special card', () {
      test('does nothing when specialCardToActivate is null', () {
        gameState.specialCardToActivate = null;
        final handBefore = List<PlayingCard>.from(human.hand);

        handler.usePower(gameState, 0, 0);

        expect(human.hand, equals(handBefore));
      });
    });

    group('tracking integration', () {
      test('records score change after power use', () {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        handler.usePower(gameState, 0, 0);

        expect(mockTrackingProvider.lastUpdateResult, isNotNull);
        expect(mockTrackingProvider.lastUpdateResult!.containsKey('scoreChange'), isTrue);
      });
    });
  });
}
