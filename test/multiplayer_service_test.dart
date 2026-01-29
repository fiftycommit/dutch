import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/multiplayer_service.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';

/// Extended mock for comprehensive testing
class TestableMultiplayerService extends MultiplayerService {
  bool _mockConnected = false;
  String? _mockPlayerId;
  String? _mockClientId;
  int _mockLatencyMs = 0;
  int _mockServerNowMs = 0;

  // Tracking calls
  final List<String> methodCalls = [];
  final List<Map<String, dynamic>> emittedEvents = [];

  void setMockState({
    bool connected = false,
    String? playerId,
    String? clientId,
    int latencyMs = 0,
    int? serverNowMs,
  }) {
    _mockConnected = connected;
    _mockPlayerId = playerId;
    _mockClientId = clientId;
    _mockLatencyMs = latencyMs;
    _mockServerNowMs = serverNowMs ?? DateTime.now().millisecondsSinceEpoch;
  }

  @override
  bool get isConnected => _mockConnected;

  @override
  String? get playerId => _mockPlayerId;

  @override
  String? get clientId => _mockClientId;

  @override
  int get latencyMs => _mockLatencyMs;

  @override
  int get serverNowMs => _mockServerNowMs;

  @override
  Future<void> connect() async {
    methodCalls.add('connect');
    _mockConnected = true;
  }

  @override
  void disconnect() {
    methodCalls.add('disconnect');
    _mockConnected = false;
  }

  @override
  Future<String?> createRoom({
    required GameSettings settings,
    required String playerName,
  }) async {
    methodCalls.add('createRoom');
    emittedEvents.add({
      'event': 'room:create',
      'settings': settings,
      'playerName': playerName,
    });
    return 'ABC123';
  }

  @override
  Future<Map<String, dynamic>?> joinRoom({
    required String roomCode,
    required String playerName,
  }) async {
    methodCalls.add('joinRoom');
    emittedEvents.add({
      'event': 'room:join',
      'roomCode': roomCode,
      'playerName': playerName,
    });
    return {'success': true, 'roomCode': roomCode};
  }

  @override
  Future<bool> startGame({bool fillBots = false}) async {
    methodCalls.add('startGame');
    emittedEvents.add({'event': 'room:start_game', 'fillBots': fillBots});
    return true;
  }

  @override
  void drawCard() {
    methodCalls.add('drawCard');
    emittedEvents.add({'event': 'game:draw_card'});
  }

  @override
  void replaceCard(int cardIndex) {
    methodCalls.add('replaceCard');
    emittedEvents.add({'event': 'game:replace_card', 'cardIndex': cardIndex});
  }

  @override
  void discardDrawnCard() {
    methodCalls.add('discardDrawnCard');
    emittedEvents.add({'event': 'game:discard_card'});
  }

  @override
  void takeFromDiscard() {
    methodCalls.add('takeFromDiscard');
    emittedEvents.add({'event': 'game:take_from_discard'});
  }

  @override
  void callDutch() {
    methodCalls.add('callDutch');
    emittedEvents.add({'event': 'game:call_dutch'});
  }

  @override
  void attemptMatch(int cardIndex) {
    methodCalls.add('attemptMatch');
    emittedEvents.add({'event': 'game:attempt_match', 'cardIndex': cardIndex});
  }

  @override
  void useSpecialPower(int targetPlayerIndex, int targetCardIndex) {
    methodCalls.add('useSpecialPower');
    emittedEvents.add({
      'event': 'game:use_special_power',
      'targetPlayerIndex': targetPlayerIndex,
      'targetCardIndex': targetCardIndex,
    });
  }

  @override
  void usePower7LookOwnCard(int cardIndex) {
    methodCalls.add('usePower7LookOwnCard');
    emittedEvents
        .add({'event': 'game:use_special_power', 'cardIndex': cardIndex});
  }

  @override
  void usePower10SpyOpponent(int targetPlayerIndex, int targetCardIndex) {
    methodCalls.add('usePower10SpyOpponent');
    emittedEvents.add({
      'event': 'game:use_special_power',
      'targetPlayerIndex': targetPlayerIndex,
      'targetCardIndex': targetCardIndex,
    });
  }

  @override
  void usePowerValetSwap(
      int player1Index, int card1Index, int player2Index, int card2Index) {
    methodCalls.add('usePowerValetSwap');
    emittedEvents.add({
      'event': 'game:use_special_power',
      'player1Index': player1Index,
      'card1Index': card1Index,
      'player2Index': player2Index,
      'card2Index': card2Index,
    });
  }

  @override
  void usePowerJokerShuffle(int targetPlayerIndex) {
    methodCalls.add('usePowerJokerShuffle');
    emittedEvents.add({
      'event': 'game:use_special_power',
      'targetPlayerIndex': targetPlayerIndex,
    });
  }

  @override
  void skipSpecialPower() {
    methodCalls.add('skipSpecialPower');
    emittedEvents.add({'event': 'game:skip_special_power'});
  }

  @override
  void setReady(bool ready) {
    methodCalls.add('setReady');
    emittedEvents.add({'event': 'room:ready', 'ready': ready});
  }

  @override
  void markReady() {
    methodCalls.add('markReady');
    emittedEvents.add({'event': 'player:ready'});
  }

  @override
  void setFocused(bool focused) {
    methodCalls.add('setFocused');
    emittedEvents.add({'event': 'presence:focus', 'focused': focused});
  }

  @override
  void confirmPresence() {
    methodCalls.add('confirmPresence');
    emittedEvents.add({'event': 'presence:ack'});
  }

  @override
  void sendChatMessage(String message) {
    methodCalls.add('sendChatMessage');
    emittedEvents.add({'event': 'chat:send', 'message': message});
  }

  @override
  Future<bool> restartGame() async {
    methodCalls.add('restartGame');
    emittedEvents.add({'event': 'room:restart'});
    return true;
  }

  @override
  void leaveRoom() {
    methodCalls.add('leaveRoom');
    emittedEvents.add({'event': 'room:leave'});
  }

  @override
  Future<bool> closeRoom() async {
    methodCalls.add('closeRoom');
    emittedEvents.add({'event': 'room:close'});
    return true;
  }

  @override
  Future<bool> kickPlayer(String clientId) async {
    methodCalls.add('kickPlayer');
    emittedEvents.add({'event': 'room:kick', 'clientId': clientId});
    return true;
  }

  @override
  Future<bool> setGameMode(int mode) async {
    methodCalls.add('setGameMode');
    emittedEvents.add({'event': 'room:set_game_mode', 'mode': mode});
    return true;
  }

  @override
  void requestFullState() {
    methodCalls.add('requestFullState');
    emittedEvents.add({'event': 'game:request_state'});
  }

  // Helper methods to trigger callbacks in tests
  void triggerGameStateUpdate(GameState state) {
    onGameStateUpdate?.call(state);
  }

  void triggerPresenceUpdate(Map<String, dynamic> data) {
    onPresenceUpdate?.call(data);
  }

  void triggerPresenceCheck(Map<String, dynamic> data) {
    onPresenceCheck?.call(data);
  }

  void triggerGameStarted(String message) {
    onGameStarted?.call(message);
  }

  void triggerPlayerLeft(Map<String, dynamic> data) {
    onPlayerLeft?.call(data);
  }

  void triggerRoomClosed(Map<String, dynamic> data) {
    onRoomClosed?.call(data);
  }

  void triggerKicked(Map<String, dynamic> data) {
    onKicked?.call(data);
  }

  void clearCalls() {
    methodCalls.clear();
    emittedEvents.clear();
  }
}

void main() {
  group('MultiplayerService', () {
    late TestableMultiplayerService service;

    setUp(() {
      service = TestableMultiplayerService();
    });

    group('connection state', () {
      test('initially not connected', () {
        expect(service.isConnected, false);
        expect(service.playerId, isNull);
        expect(service.clientId, isNull);
      });

      test('connect updates state', () async {
        await service.connect();
        expect(service.isConnected, true);
        expect(service.methodCalls, contains('connect'));
      });

      test('disconnect updates state', () async {
        await service.connect();
        service.disconnect();
        expect(service.isConnected, false);
        expect(service.methodCalls, contains('disconnect'));
      });
    });

    group('room operations', () {
      test('createRoom emits event and returns room code', () async {
        final roomCode = await service.createRoom(
          settings: GameSettings(),
          playerName: 'Test Player',
        );

        expect(roomCode, 'ABC123');
        expect(service.methodCalls, contains('createRoom'));
        expect(
          service.emittedEvents.any((e) => e['event'] == 'room:create'),
          true,
        );
      });

      test('joinRoom emits event', () async {
        final result = await service.joinRoom(
          roomCode: 'XYZ789',
          playerName: 'Joiner',
        );

        expect(result?['success'], true);
        expect(service.methodCalls, contains('joinRoom'));
        expect(
          service.emittedEvents.any(
            (e) => e['event'] == 'room:join' && e['roomCode'] == 'XYZ789',
          ),
          true,
        );
      });

      test('startGame emits event', () async {
        final success = await service.startGame(fillBots: true);

        expect(success, true);
        expect(service.methodCalls, contains('startGame'));
        expect(
          service.emittedEvents.any(
            (e) => e['event'] == 'room:start_game' && e['fillBots'] == true,
          ),
          true,
        );
      });

      test('leaveRoom emits event', () {
        service.leaveRoom();
        expect(service.methodCalls, contains('leaveRoom'));
      });

      test('closeRoom emits event', () async {
        await service.closeRoom();
        expect(service.methodCalls, contains('closeRoom'));
      });

      test('kickPlayer emits event with clientId', () async {
        await service.kickPlayer('client-123');
        expect(service.methodCalls, contains('kickPlayer'));
        expect(
          service.emittedEvents.any(
            (e) => e['event'] == 'room:kick' && e['clientId'] == 'client-123',
          ),
          true,
        );
      });

      test('restartGame emits event', () async {
        final success = await service.restartGame();
        expect(success, true);
        expect(service.methodCalls, contains('restartGame'));
      });

      test('setGameMode emits event', () async {
        await service.setGameMode(1);
        expect(service.methodCalls, contains('setGameMode'));
        expect(
          service.emittedEvents.any(
            (e) => e['event'] == 'room:set_game_mode' && e['mode'] == 1,
          ),
          true,
        );
      });
    });

    group('game actions', () {
      test('drawCard emits event', () {
        service.drawCard();
        expect(service.methodCalls, contains('drawCard'));
        expect(
          service.emittedEvents.any((e) => e['event'] == 'game:draw_card'),
          true,
        );
      });

      test('replaceCard emits event with index', () {
        service.replaceCard(2);
        expect(service.methodCalls, contains('replaceCard'));
        expect(
          service.emittedEvents.any(
            (e) => e['event'] == 'game:replace_card' && e['cardIndex'] == 2,
          ),
          true,
        );
      });

      test('discardDrawnCard emits event', () {
        service.discardDrawnCard();
        expect(service.methodCalls, contains('discardDrawnCard'));
      });

      test('takeFromDiscard emits event', () {
        service.takeFromDiscard();
        expect(service.methodCalls, contains('takeFromDiscard'));
      });

      test('callDutch emits event', () {
        service.callDutch();
        expect(service.methodCalls, contains('callDutch'));
      });

      test('attemptMatch emits event with index', () {
        service.attemptMatch(1);
        expect(service.methodCalls, contains('attemptMatch'));
        expect(
          service.emittedEvents.any(
            (e) => e['event'] == 'game:attempt_match' && e['cardIndex'] == 1,
          ),
          true,
        );
      });

      test('useSpecialPower emits event with indices', () {
        service.useSpecialPower(0, 1);
        expect(service.methodCalls, contains('useSpecialPower'));
        expect(
          service.emittedEvents.any(
            (e) =>
                e['event'] == 'game:use_special_power' &&
                e['targetPlayerIndex'] == 0 &&
                e['targetCardIndex'] == 1,
          ),
          true,
        );
      });

      test('usePower7LookOwnCard emits event', () {
        service.usePower7LookOwnCard(2);
        expect(service.methodCalls, contains('usePower7LookOwnCard'));
        expect(
          service.emittedEvents.any(
            (e) =>
                e['event'] == 'game:use_special_power' && e['cardIndex'] == 2,
          ),
          true,
        );
      });

      test('usePower10SpyOpponent emits event', () {
        service.usePower10SpyOpponent(1, 3);
        expect(service.methodCalls, contains('usePower10SpyOpponent'));
        expect(
          service.emittedEvents.any(
            (e) =>
                e['event'] == 'game:use_special_power' &&
                e['targetPlayerIndex'] == 1 &&
                e['targetCardIndex'] == 3,
          ),
          true,
        );
      });

      test('usePowerValetSwap emits event', () {
        service.usePowerValetSwap(0, 1, 2, 3);
        expect(service.methodCalls, contains('usePowerValetSwap'));
        expect(
          service.emittedEvents.any(
            (e) =>
                e['event'] == 'game:use_special_power' &&
                e['player1Index'] == 0 &&
                e['card1Index'] == 1 &&
                e['player2Index'] == 2 &&
                e['card2Index'] == 3,
          ),
          true,
        );
      });

      test('usePowerJokerShuffle emits event', () {
        service.usePowerJokerShuffle(1);
        expect(service.methodCalls, contains('usePowerJokerShuffle'));
        expect(
          service.emittedEvents.any(
            (e) =>
                e['event'] == 'game:use_special_power' &&
                e['targetPlayerIndex'] == 1,
          ),
          true,
        );
      });

      test('skipSpecialPower emits event', () {
        service.skipSpecialPower();
        expect(service.methodCalls, contains('skipSpecialPower'));
      });
    });

    group('presence and ready state', () {
      test('setReady emits event', () {
        service.setReady(true);
        expect(service.methodCalls, contains('setReady'));
        expect(
          service.emittedEvents.any(
            (e) => e['event'] == 'room:ready' && e['ready'] == true,
          ),
          true,
        );
      });

      test('markReady emits event', () {
        service.markReady();
        expect(service.methodCalls, contains('markReady'));
      });

      test('setFocused emits event', () {
        service.setFocused(false);
        expect(service.methodCalls, contains('setFocused'));
        expect(
          service.emittedEvents.any(
            (e) => e['event'] == 'presence:focus' && e['focused'] == false,
          ),
          true,
        );
      });

      test('confirmPresence emits event', () {
        service.confirmPresence();
        expect(service.methodCalls, contains('confirmPresence'));
      });
    });

    group('chat', () {
      test('sendChatMessage emits event with message', () {
        service.sendChatMessage('Hello world!');
        expect(service.methodCalls, contains('sendChatMessage'));
        expect(
          service.emittedEvents.any(
            (e) => e['event'] == 'chat:send' && e['message'] == 'Hello world!',
          ),
          true,
        );
      });
    });

    group('callbacks', () {
      test('onGameStateUpdate callback is triggered', () {
        GameState? receivedState;
        service.onGameStateUpdate = (state) {
          receivedState = state;
        };

        final testState = GameState(
          players: [
            Player(id: 'p1', name: 'Player 1', isHuman: true),
          ],
          deck: [],
          discardPile: [],
        );
        service.triggerGameStateUpdate(testState);

        expect(receivedState, isNotNull);
      });

      test('onPresenceUpdate callback is triggered', () {
        Map<String, dynamic>? receivedData;
        service.onPresenceUpdate = (data) {
          receivedData = data;
        };

        service.triggerPresenceUpdate({'players': [], 'hostPlayerId': 'p1'});

        expect(receivedData, isNotNull);
        expect(receivedData!['hostPlayerId'], 'p1');
      });

      test('onPresenceCheck callback is triggered', () {
        Map<String, dynamic>? receivedData;
        service.onPresenceCheck = (data) {
          receivedData = data;
        };

        service.triggerPresenceCheck({'reason': 'AFK', 'deadlineMs': 5000});

        expect(receivedData, isNotNull);
        expect(receivedData!['reason'], 'AFK');
      });

      test('onGameStarted callback is triggered', () {
        String? receivedMessage;
        service.onGameStarted = (message) {
          receivedMessage = message;
        };

        service.triggerGameStarted('Game started!');

        expect(receivedMessage, 'Game started!');
      });

      test('onPlayerLeft callback is triggered', () {
        Map<String, dynamic>? receivedData;
        service.onPlayerLeft = (data) {
          receivedData = data;
        };

        service.triggerPlayerLeft({'playerName': 'Player 2'});

        expect(receivedData, isNotNull);
        expect(receivedData!['playerName'], 'Player 2');
      });

      test('onRoomClosed callback is triggered', () {
        Map<String, dynamic>? receivedData;
        service.onRoomClosed = (data) {
          receivedData = data;
        };

        service.triggerRoomClosed({'canBecomeHost': true});

        expect(receivedData, isNotNull);
        expect(receivedData!['canBecomeHost'], true);
      });

      test('onKicked callback is triggered', () {
        Map<String, dynamic>? receivedData;
        service.onKicked = (data) {
          receivedData = data;
        };

        service.triggerKicked({'reason': 'Host kicked you'});

        expect(receivedData, isNotNull);
        expect(receivedData!['reason'], 'Host kicked you');
      });
    });

    group('latency and time sync', () {
      test('latencyMs returns mock value', () {
        service.setMockState(latencyMs: 150);
        expect(service.latencyMs, 150);
      });

      test('serverNowMs returns mock value', () {
        final now = DateTime.now().millisecondsSinceEpoch;
        service.setMockState(serverNowMs: now);
        expect(service.serverNowMs, now);
      });
    });

    group('requestFullState', () {
      test('emits request_state event', () {
        service.requestFullState();
        expect(service.methodCalls, contains('requestFullState'));
        expect(
          service.emittedEvents.any((e) => e['event'] == 'game:request_state'),
          true,
        );
      });
    });
  });
}
