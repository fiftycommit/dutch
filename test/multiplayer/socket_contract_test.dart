import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:dutch_game/services/multiplayer/game_actions_emitter.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Contract tests pour les payloads Socket.IO
/// Vérifie que les payloads émis sont EXACTS (type + ids + data)
void main() {
  group('Socket.IO Contract Tests - Emit Payloads', () {
    late MockSocket mockSocket;
    late GameActionsEmitter emitter;
    const testRoomCode = 'TEST123';

    setUp(() {
      mockSocket = MockSocket();
      emitter = GameActionsEmitter(
        getSocket: () => mockSocket,
        getRoomCode: () => testRoomCode,
      );
    });

    void expectAckPayload(String event, Map<String, dynamic> expectedFields) {
      expect(mockSocket.lastEventWithAck, event);
      expect(mockSocket.lastPayloadWithAck,
          containsPair('roomCode', testRoomCode));
      for (final entry in expectedFields.entries) {
        expect(mockSocket.lastPayloadWithAck,
            containsPair(entry.key, entry.value));
      }
      expect(mockSocket.lastPayloadWithAck!['actionId'], isA<String>());
      expect(
        mockSocket.lastPayloadWithAck!['actionId'] as String,
        startsWith('${event.replaceAll(':', '_')}-'),
      );
    }

    group('Game Actions', () {
      test('drawCard émet payload avec ACK et actionId', () async {
        final success = await emitter.drawCard();

        expect(success, isTrue);
        expectAckPayload('game:draw_card', const {});
      });

      test('drawCard retourne false quand le serveur refuse l ACK', () async {
        mockSocket.ackResponse = {'ok': false, 'error': 'invalid_phase'};

        final success = await emitter.drawCard();

        expect(success, isFalse);
        expectAckPayload('game:draw_card', const {});
      });

      test('drawCard retourne false quand l ACK expire', () {
        mockSocket.shouldAck = false;

        fakeAsync((async) {
          bool? result;
          emitter.drawCard().then((value) => result = value);

          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();

          expect(result, isFalse);
          expectAckPayload('game:draw_card', const {});
        });
      });

      test('replaceCard émet payload avec ACK et cardIndex', () async {
        final success = await emitter.replaceCard(2);

        expect(success, isTrue);
        expectAckPayload('game:replace_card', const {'cardIndex': 2});
      });

      test('discardDrawnCard émet payload avec ACK', () async {
        final success = await emitter.discardDrawnCard();

        expect(success, isTrue);
        expectAckPayload('game:discard_card', const {});
      });

      test('callDutch émet payload avec ACK', () async {
        final success = await emitter.callDutch();

        expect(success, isTrue);
        expectAckPayload('game:call_dutch', const {});
      });

      test('attemptMatch émet payload avec ACK et cardIndex', () async {
        final success = await emitter.attemptMatch(1);

        expect(success, isTrue);
        expectAckPayload('game:attempt_match', const {'cardIndex': 1});
      });
    });

    group('Special Powers', () {
      test('power7 émet payload avec ACK et cardIndex seulement', () async {
        final success = await emitter.usePower7LookOwnCard(0);

        expect(success, isTrue);
        expectAckPayload('game:use_special_power', const {'cardIndex': 0});
      });

      test('power10 émet payload avec targetPlayerIndex et targetCardIndex',
          () async {
        final success = await emitter.usePower10SpyOpponent(1, 2);

        expect(success, isTrue);
        expectAckPayload('game:use_special_power', const {
          'targetPlayerIndex': 1,
          'targetCardIndex': 2,
        });
      });

      test('powerValet émet payload avec ACK et 4 indices', () async {
        final success = await emitter.usePowerValetSwap(0, 1, 2, 3);

        expect(success, isTrue);
        expectAckPayload('game:use_special_power', const {
          'player1Index': 0,
          'card1Index': 1,
          'player2Index': 2,
          'card2Index': 3,
        });
      });

      test('powerJoker émet payload avec ACK et targetPlayerIndex', () async {
        final success = await emitter.usePowerJokerShuffle(1);

        expect(success, isTrue);
        expectAckPayload(
            'game:use_special_power', const {'targetPlayerIndex': 1});
      });

      test('skipSpecialPower émet payload avec ACK', () async {
        final success = await emitter.skipSpecialPower();

        expect(success, isTrue);
        expectAckPayload('game:skip_special_power', const {});
      });
    });

    group('Room Actions', () {
      test('setReady émet payload avec ready boolean', () {
        emitter.setReady(true);

        expect(mockSocket.lastEvent, 'room:ready');
        expect(mockSocket.lastPayload, {
          'roomCode': testRoomCode,
          'ready': true,
        });
      });

      test('setReady false émet payload correct', () {
        emitter.setReady(false);

        expect(mockSocket.lastPayload!['ready'], false);
      });
    });

    group('Edge Cases', () {
      test('émission sans roomCode ne crash pas', () {
        final emitterNoRoom = GameActionsEmitter(
          getSocket: () => mockSocket,
          getRoomCode: () => null,
        );

        expect(() => emitterNoRoom.setReady(true), returnsNormally);
        // setReady avec roomCode null ne doit rien émettre
        expect(mockSocket.lastEventWithAck, isNull);
      });

      test('émission sans socket ne crash pas', () async {
        final emitterNoSocket = GameActionsEmitter(
          getSocket: () => null,
          getRoomCode: () => testRoomCode,
        );

        expect(await emitterNoSocket.drawCard(), isFalse);
      });

      test('cardIndex négatif est transmis tel quel', () {
        emitter.replaceCard(-1);

        expect(mockSocket.lastPayloadWithAck!['cardIndex'], -1);
      });
    });
  });
}

/// Mock Socket qui capture les émissions
class MockSocket implements io.Socket {
  String? lastEvent;
  Map<String, dynamic>? lastPayload;
  String? lastEventWithAck;
  Map<String, dynamic>? lastPayloadWithAck;
  bool shouldAck = true;
  dynamic ackResponse;

  @override
  void emit(String event, [dynamic data]) {
    lastEvent = event;
    lastPayload = data as Map<String, dynamic>?;
  }

  @override
  void emitWithAck(String event, dynamic data,
      {Function? ack, bool binary = false}) {
    lastEventWithAck = event;
    lastPayloadWithAck = data as Map<String, dynamic>?;
    if (shouldAck) {
      ack?.call(ackResponse ??
          {'ok': true, 'actionId': lastPayloadWithAck?['actionId']});
    }
  }

  // Le getter connected doit être implémenté explicitement car il retourne un bool
  @override
  bool get connected => true;

  // Stubs pour les autres méthodes de io.Socket
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
