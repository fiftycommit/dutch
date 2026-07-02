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

      test('drawCard does not crash with null socket', () async {
        // Should not throw
        expect(await emitter.drawCard(), isFalse);
      });

      test('replaceCard does not crash with null socket', () async {
        expect(await emitter.replaceCard(0), isFalse);
        expect(await emitter.replaceCard(3), isFalse);
      });

      test('discardDrawnCard does not crash with null socket', () async {
        expect(await emitter.discardDrawnCard(), isFalse);
      });

      test('callDutch does not crash with null socket', () async {
        expect(await emitter.callDutch(), isFalse);
      });

      test('attemptMatch does not crash with null socket', () async {
        expect(await emitter.attemptMatch(0), isFalse);
        expect(await emitter.attemptMatch(3), isFalse);
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

      test('usePower7LookOwnCard does not crash', () async {
        expect(await emitter.usePower7LookOwnCard(0), isFalse);
        expect(await emitter.usePower7LookOwnCard(3), isFalse);
      });

      test('usePower10SpyOpponent does not crash', () async {
        expect(await emitter.usePower10SpyOpponent(1, 0), isFalse);
        expect(await emitter.usePower10SpyOpponent(2, 3), isFalse);
      });

      test('usePowerValetSwap does not crash', () async {
        expect(await emitter.usePowerValetSwap(0, 0, 1, 1), isFalse);
        expect(await emitter.usePowerValetSwap(0, 2, 2, 3), isFalse);
      });

      test('usePowerJokerShuffle does not crash', () async {
        expect(await emitter.usePowerJokerShuffle(0), isFalse);
        expect(await emitter.usePowerJokerShuffle(2), isFalse);
      });

      test('skipSpecialPower does not crash', () async {
        expect(await emitter.skipSpecialPower(), isFalse);
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

      test('all actions work with null roomCode', () async {
        // None of these should throw
        expect(await emitter.drawCard(), isFalse);
        expect(await emitter.replaceCard(0), isFalse);
        expect(await emitter.discardDrawnCard(), isFalse);
        expect(await emitter.callDutch(), isFalse);
        expect(await emitter.attemptMatch(0), isFalse);
        expect(await emitter.usePower7LookOwnCard(0), isFalse);
        expect(await emitter.usePower10SpyOpponent(1, 0), isFalse);
        expect(await emitter.usePowerValetSwap(0, 0, 1, 1), isFalse);
        expect(await emitter.usePowerJokerShuffle(0), isFalse);
        expect(await emitter.skipSpecialPower(), isFalse);
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

      test('can call multiple actions in sequence', () async {
        expect(await emitter.drawCard(), isFalse);
        expect(await emitter.replaceCard(0), isFalse);
        expect(await emitter.callDutch(), isFalse);
        // No exception = pass
      });

      test('can call same action multiple times', () async {
        expect(await emitter.drawCard(), isFalse);
        expect(await emitter.drawCard(), isFalse);
        expect(await emitter.drawCard(), isFalse);
      });
    });
  });
}
