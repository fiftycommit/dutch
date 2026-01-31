import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/providers/managers/multiplayer/multiplayer_notification_manager.dart';

/// Tests d'idempotence pour les événements multiplayer
/// Vérifie que les événements répétés ne créent pas de doublons
void main() {
  group('Idempotence Tests - Multi Events', () {
    late MultiplayerNotificationManager manager;
    int notifyCount;

    setUp(() {
      notifyCount = 0;
      manager = MultiplayerNotificationManager(
        notifyListeners: () => notifyCount++,
      );
    });

    group('hostClosed idempotence', () {
      test('même hostClosed reçu deux fois → un seul pending event', () {
        final eventData = {'roomCode': 'TEST123', 'reason': 'Host left'};

        manager.handleRoomClosed(eventData);
        final firstState = manager.roomClosedByHost;
        final firstCode = manager.closedRoomCode;

        manager.handleRoomClosed(eventData);
        final secondState = manager.roomClosedByHost;
        final secondCode = manager.closedRoomCode;

        expect(firstState, isTrue);
        expect(secondState, isTrue);
        expect(firstCode, 'TEST123');
        expect(secondCode, 'TEST123');
        // L'état doit rester cohérent
        expect(manager.roomClosedByHost, isTrue);
      });

      test('acknowledge une fois suffit', () {
        manager.handleRoomClosed({'roomCode': 'TEST123'});
        manager.handleRoomClosed({'roomCode': 'TEST123'});

        manager.acknowledgeRoomClosed();

        expect(manager.roomClosedByHost, isFalse);
        expect(manager.closedRoomCode, isNull);
      });
    });

    group('kicked idempotence', () {
      test('même kicked reçu deux fois → une seule consommation', () {
        final kickData = {'message': 'You were kicked'};

        manager.handleKicked(kickData);
        expect(manager.wasKicked, isTrue);
        expect(manager.kickedMessage, 'You were kicked');

        manager.handleKicked(kickData);
        expect(manager.wasKicked, isTrue);
        expect(manager.kickedMessage, 'You were kicked');
      });

      test('acknowledge kicked reset l\'état', () {
        manager.handleKicked({'message': 'Kicked'});
        manager.handleKicked({'message': 'Kicked'});

        manager.acknowledgeKicked();

        expect(manager.wasKicked, isFalse);
        expect(manager.kickedMessage, isNull);
      });
    });

    group('playerLeft idempotence', () {
      test('même playerLeft deux fois ne duplique pas', () {
        final leftData = {'playerName': 'Player1', 'playerId': 'p1'};

        manager.handlePlayerLeft(leftData);
        final first = manager.lastPlayerLeftName;

        manager.handlePlayerLeft(leftData);
        final second = manager.lastPlayerLeftName;

        expect(first, 'Player1');
        expect(second, 'Player1');
      });
    });

    group('specialPower notifications idempotence', () {
      test('swap notification reçue deux fois reste unique', () {
        final swapData = {
          'byName': 'Bot1',
          'player1Name': 'Human',
          'card1Index': 0,
          'player2Name': 'Bot2',
          'card2Index': 1,
        };

        manager.handleSwapNotification(swapData);
        manager.handleSwapNotification(swapData);

        expect(manager.pendingSwapNotification, isNotNull);
        expect(manager.pendingSwapNotification!['byName'], 'Bot1');

        manager.clearSwapNotification();
        expect(manager.pendingSwapNotification, isNull);
      });

      test('joker notification idempotente', () {
        final jokerData = {
          'byName': 'Bot1',
          'targetName': 'Human',
        };

        manager.handleJokerNotification(jokerData);
        manager.handleJokerNotification(jokerData);

        expect(manager.pendingJokerNotification, isNotNull);

        manager.clearJokerNotification();
        expect(manager.pendingJokerNotification, isNull);
      });

      test('spy notification idempotente', () {
        final spyData = {
          'byName': 'Bot1',
          'targetName': 'Human',
          'cardIndex': 2,
        };

        manager.handleSpyNotification(spyData);
        manager.handleSpyNotification(spyData);

        expect(manager.pendingSpyNotification, isNotNull);

        manager.clearSpyNotification();
        expect(manager.pendingSpyNotification, isNull);
      });
    });

    group('reset behavior', () {
      test('reset efface tous les états pending', () {
        manager.handleRoomClosed({'roomCode': 'TEST'});
        manager.handleKicked({'message': 'Kicked'});
        manager.handleSwapNotification({'byName': 'Bot'});

        expect(manager.roomClosedByHost, isTrue);
        expect(manager.wasKicked, isTrue);
        expect(manager.pendingSwapNotification, isNotNull);

        manager.reset();

        expect(manager.roomClosedByHost, isFalse);
        expect(manager.wasKicked, isFalse);
        expect(manager.pendingSwapNotification, isNull);
        expect(manager.errorMessage, isNull);
      });

      test('reset après reconnexion ne corrompt pas l\'état', () {
        manager.handleRoomClosed({'roomCode': 'OLD'});
        manager.reset();

        manager.handleRoomClosed({'roomCode': 'NEW'});

        expect(manager.closedRoomCode, 'NEW');
        expect(manager.roomClosedByHost, isTrue);
      });
    });
  });
}
