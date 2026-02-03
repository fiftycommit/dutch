import 'package:flutter_test/flutter_test.dart';
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

    group('Game Actions', () {
      test('drawCard émet payload exact', () {
        emitter.drawCard();

        expect(mockSocket.lastEvent, 'game:draw_card');
        expect(mockSocket.lastPayload, {'roomCode': testRoomCode});
      });

      test('replaceCard émet payload avec cardIndex', () {
        emitter.replaceCard(2);

        expect(mockSocket.lastEvent, 'game:replace_card');
        expect(mockSocket.lastPayload, {
          'roomCode': testRoomCode,
          'cardIndex': 2,
        });
      });

      test('discardDrawnCard émet payload exact', () {
        emitter.discardDrawnCard();

        expect(mockSocket.lastEvent, 'game:discard_card');
        expect(mockSocket.lastPayload, {'roomCode': testRoomCode});
      });

      test('takeFromDiscard émet payload exact', () {
        emitter.takeFromDiscard();

        expect(mockSocket.lastEvent, 'game:take_from_discard');
        expect(mockSocket.lastPayload, {'roomCode': testRoomCode});
      });

      test('callDutch émet payload exact', () {
        emitter.callDutch();

        expect(mockSocket.lastEvent, 'game:call_dutch');
        expect(mockSocket.lastPayload, {'roomCode': testRoomCode});
      });

      test('attemptMatch émet payload avec cardIndex', () {
        emitter.attemptMatch(1);

        expect(mockSocket.lastEvent, 'game:attempt_match');
        expect(mockSocket.lastPayload, {
          'roomCode': testRoomCode,
          'cardIndex': 1,
        });
      });
    });

    group('Special Powers', () {
      test('power7 émet payload avec cardIndex seulement', () {
        emitter.usePower7LookOwnCard(0);

        expect(mockSocket.lastEvent, 'game:use_special_power');
        expect(mockSocket.lastPayload, {
          'roomCode': testRoomCode,
          'cardIndex': 0,
        });
      });

      test('power10 émet payload avec targetPlayerIndex et targetCardIndex', () {
        emitter.usePower10SpyOpponent(1, 2);

        expect(mockSocket.lastEvent, 'game:use_special_power');
        expect(mockSocket.lastPayload, {
          'roomCode': testRoomCode,
          'targetPlayerIndex': 1,
          'targetCardIndex': 2,
        });
      });

      test('powerValet émet payload avec 4 indices', () {
        emitter.usePowerValetSwap(0, 1, 2, 3);

        expect(mockSocket.lastEvent, 'game:use_special_power');
        expect(mockSocket.lastPayload, {
          'roomCode': testRoomCode,
          'player1Index': 0,
          'card1Index': 1,
          'player2Index': 2,
          'card2Index': 3,
        });
      });

      test('powerJoker émet payload avec targetPlayerIndex', () {
        emitter.usePowerJokerShuffle(1);

        expect(mockSocket.lastEvent, 'game:use_special_power');
        expect(mockSocket.lastPayload, {
          'roomCode': testRoomCode,
          'targetPlayerIndex': 1,
        });
      });

      test('skipSpecialPower émet payload exact', () {
        emitter.skipSpecialPower();

        expect(mockSocket.lastEvent, 'game:skip_special_power');
        expect(mockSocket.lastPayload, {'roomCode': testRoomCode});
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

      test('émission sans socket ne crash pas', () {
        final emitterNoSocket = GameActionsEmitter(
          getSocket: () => null,
          getRoomCode: () => testRoomCode,
        );

        expect(() => emitterNoSocket.drawCard(), returnsNormally);
      });

      test('cardIndex négatif est transmis tel quel', () {
        emitter.replaceCard(-1);

        expect(mockSocket.lastPayload!['cardIndex'], -1);
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

  @override
  void emit(String event, [dynamic data]) {
    lastEvent = event;
    lastPayload = data as Map<String, dynamic>?;
  }

  @override
  void emitWithAck(String event, dynamic data, {Function? ack, bool binary = false}) {
    lastEventWithAck = event;
    lastPayloadWithAck = data as Map<String, dynamic>?;
    ack?.call(null);
  }

  // Le getter connected doit être implémenté explicitement car il retourne un bool
  @override
  bool get connected => true;

  // Stubs pour les autres méthodes de io.Socket
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
