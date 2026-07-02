import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/multiplayer/game_actions_emitter.dart';

void main() {
  group('GameActionsEmitter', () {
    group('Constructor', () {
      test('can be created with getters', () {
        final emitter = GameActionsEmitter(
          getSocket: () => null,
          getRoomCode: () => 'ROOM',
        );
        expect(emitter, isNotNull);
      });

      test('accepts null roomCode getter', () {
        final emitter = GameActionsEmitter(
          getSocket: () => null,
          getRoomCode: () => null,
        );
        expect(emitter, isNotNull);
      });
    });

    group('Null Socket Safety - Basic Actions', () {
      late GameActionsEmitter emitter;

      setUp(() {
        emitter = GameActionsEmitter(
          getSocket: () => null,
          getRoomCode: () => 'TEST_ROOM',
        );
      });

      test('drawCard does not crash with null socket', () {
        // Should not throw
        emitter.drawCard();
      });

      test('replaceCard does not crash with null socket', () {
        emitter.replaceCard(0);
        emitter.replaceCard(3);
      });

      test('discardDrawnCard does not crash with null socket', () {
        emitter.discardDrawnCard();
      });

      test('callDutch does not crash with null socket', () {
        emitter.callDutch();
      });

      test('attemptMatch does not crash with null socket', () {
        emitter.attemptMatch(0);
        emitter.attemptMatch(3);
      });
    });

    group('Null Socket Safety - Special Powers', () {
      late GameActionsEmitter emitter;

      setUp(() {
        emitter = GameActionsEmitter(
          getSocket: () => null,
          getRoomCode: () => 'TEST_ROOM',
        );
      });

      test('usePower7LookOwnCard does not crash', () {
        emitter.usePower7LookOwnCard(0);
        emitter.usePower7LookOwnCard(3);
      });

      test('usePower10SpyOpponent does not crash', () {
        emitter.usePower10SpyOpponent(1, 0);
        emitter.usePower10SpyOpponent(2, 3);
      });

      test('usePowerValetSwap does not crash', () {
        emitter.usePowerValetSwap(0, 0, 1, 1);
        emitter.usePowerValetSwap(0, 2, 2, 3);
      });

      test('usePowerJokerShuffle does not crash', () {
        emitter.usePowerJokerShuffle(0);
        emitter.usePowerJokerShuffle(2);
      });

      test('skipSpecialPower does not crash', () {
        emitter.skipSpecialPower();
      });
    });

    group('Null RoomCode Safety', () {
      late GameActionsEmitter emitter;

      setUp(() {
        emitter = GameActionsEmitter(
          getSocket: () => null,
          getRoomCode: () => null,
        );
      });

      test('all actions work with null roomCode', () {
        // None of these should throw
        emitter.drawCard();
        emitter.replaceCard(0);
        emitter.discardDrawnCard();
        emitter.callDutch();
        emitter.attemptMatch(0);
        emitter.usePower7LookOwnCard(0);
        emitter.usePower10SpyOpponent(1, 0);
        emitter.usePowerValetSwap(0, 0, 1, 1);
        emitter.usePowerJokerShuffle(0);
        emitter.skipSpecialPower();
      });
    });

    group('Multiple Actions', () {
      late GameActionsEmitter emitter;

      setUp(() {
        emitter = GameActionsEmitter(
          getSocket: () => null,
          getRoomCode: () => 'TEST_ROOM',
        );
      });

      test('can call multiple actions in sequence', () {
        emitter.drawCard();
        emitter.replaceCard(0);
        emitter.callDutch();
        // No exception = pass
      });

      test('can call same action multiple times', () {
        emitter.drawCard();
        emitter.drawCard();
        emitter.drawCard();
      });
    });
  });
}
