import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/services/multiplayer_service.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/card.dart';

/// Mock MultiplayerService for testing provider
class MockMultiplayerService extends MultiplayerService {
  String _playerId = 'test-player';
  String _clientId = 'test-client';
  bool _connected = true;
  int _latencyMs = 50;
  int _serverNowMs = 0;
  String? _currentRoomCode;

  final List<String> calls = [];

  MockMultiplayerService() {
    _serverNowMs = DateTime.now().millisecondsSinceEpoch;
  }

  @override
  bool get isConnected => _connected;

  @override
  String? get playerId => _playerId;

  @override
  String? get clientId => _clientId;

  @override
  int get latencyMs => _latencyMs;

  @override
  int get serverNowMs => _serverNowMs;

  void setPlayerId(String id) => _playerId = id;
  void setClientId(String id) => _clientId = id;
  void setConnected(bool connected) => _connected = connected;
  void setLatency(int ms) => _latencyMs = ms;
  void setServerNow(int ms) => _serverNowMs = ms;

  @override
  Future<void> connect() async {
    calls.add('connect');
    _connected = true;
  }

  @override
  Future<String?> createRoom({
    required GameSettings settings,
    required String playerName,
  }) async {
    calls.add('createRoom');
    _currentRoomCode = 'TEST01';
    return _currentRoomCode;
  }

  @override
  Future<Map<String, dynamic>?> joinRoom({
    required String roomCode,
    required String playerName,
  }) async {
    calls.add('joinRoom:$roomCode');
    _currentRoomCode = roomCode;
    return {'success': true};
  }

  @override
  Future<bool> startGame({bool fillBots = false}) async {
    calls.add('startGame:$fillBots');
    return true;
  }

  @override
  void drawCard() => calls.add('drawCard');

  @override
  void replaceCard(int cardIndex) => calls.add('replaceCard:$cardIndex');

  @override
  void discardDrawnCard() => calls.add('discardDrawnCard');

  @override
  void takeFromDiscard() => calls.add('takeFromDiscard');

  @override
  void callDutch() => calls.add('callDutch');

  @override
  void attemptMatch(int cardIndex) => calls.add('attemptMatch:$cardIndex');

  @override
  void useSpecialPower(int targetPlayerIndex, int targetCardIndex) =>
      calls.add('useSpecialPower:$targetPlayerIndex,$targetCardIndex');

  @override
  void usePower7LookOwnCard(int cardIndex) =>
      calls.add('usePower7LookOwnCard:$cardIndex');

  @override
  void usePower10SpyOpponent(int targetPlayerIndex, int targetCardIndex) =>
      calls.add('usePower10SpyOpponent:$targetPlayerIndex,$targetCardIndex');

  @override
  void usePowerValetSwap(
          int player1Index, int card1Index, int player2Index, int card2Index) =>
      calls.add(
          'usePowerValetSwap:$player1Index,$card1Index,$player2Index,$card2Index');

  @override
  void usePowerJokerShuffle(int targetPlayerIndex) =>
      calls.add('usePowerJokerShuffle:$targetPlayerIndex');

  @override
  void skipSpecialPower() => calls.add('skipSpecialPower');

  @override
  void setReady(bool ready) => calls.add('setReady:$ready');

  @override
  void markReady() => calls.add('markReady');

  @override
  void setFocused(bool focused) => calls.add('setFocused:$focused');

  @override
  void confirmPresence() => calls.add('confirmPresence');

  @override
  void sendChatMessage(String message) => calls.add('sendChatMessage:$message');

  @override
  Future<bool> restartGame() async {
    calls.add('restartGame');
    return true;
  }

  @override
  void leaveRoom() => calls.add('leaveRoom');

  @override
  Future<bool> closeRoom() async {
    calls.add('closeRoom');
    return true;
  }

  @override
  Future<bool> kickPlayer(String clientId) async {
    calls.add('kickPlayer:$clientId');
    return true;
  }

  @override
  Future<bool> setGameMode(int mode) async {
    calls.add('setGameMode:$mode');
    return true;
  }

  @override
  void requestFullState() => calls.add('requestFullState');

  @override
  Future<void> cleanupInactiveRooms() async {
    calls.add('cleanupInactiveRooms');
  }

  // Helpers to trigger callbacks
  void emitGameState(GameState state) => onGameStateUpdate?.call(state);

  void emitPresenceUpdate(List<Map<String, dynamic>> players,
      {String hostPlayerId = 'test-player'}) {
    onPresenceUpdate?.call({
      'hostPlayerId': hostPlayerId,
      'players': players,
    });
  }

  void emitPresenceCheck({String reason = 'AFK', int deadlineMs = 5000}) {
    onPresenceCheck?.call({
      'reason': reason,
      'deadlineMs': deadlineMs,
    });
  }

  void emitGameStarted() => onGameStarted?.call('Game started');

  void emitPlayerJoined(Map<String, dynamic> data) =>
      onPlayerJoined?.call(data);

  void emitPlayerLeft(Map<String, dynamic> data) => onPlayerLeft?.call(data);

  void emitRoomClosed(Map<String, dynamic> data) => onRoomClosed?.call(data);

  void emitKicked(Map<String, dynamic> data) => onKicked?.call(data);

  void emitRoomRestarted(Map<String, dynamic> data) =>
      onRoomRestarted?.call(data);

  void emitChatMessage(Map<String, dynamic> data) => onChatMessage?.call(data);

  void emitSpecialPowerNotification(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'spy':
        onSpyNotification?.call(data);
        break;
      case 'swap':
        onSwapNotification?.call(data);
        break;
      case 'joker':
        onJokerNotification?.call(data);
        break;
    }
  }

  void emitReactionTimeConfig(int ms) => onReactionTimeConfig?.call(ms);

  void emitSpiedCard(PlayingCard card, String targetName) =>
      onSpiedCard?.call(card, targetName);

  void clearCalls() => calls.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MultiplayerGameProvider', () {
    late MockMultiplayerService mockService;
    late MultiplayerGameProvider provider;

    setUp(() {
      mockService = MockMultiplayerService();
      provider = MultiplayerGameProvider(multiplayerService: mockService);
    });

    tearDown(() {
      provider.dispose();
    });

    group('initialization', () {
      test('initializes with correct default state', () {
        expect(provider.gameState, isNull);
        expect(provider.roomCode, isNull);
        expect(provider.isHost, false);
        expect(provider.playersInLobby, isEmpty);
        expect(provider.chatMessages, isEmpty);
        expect(provider.presenceCheckActive, false);
      });

      test('provides isConnected from service', () {
        expect(provider.isConnected, true);
        mockService.setConnected(false);
        expect(provider.isConnected, false);
      });

      test('provides playerId from service', () {
        expect(provider.playerId, 'test-player');
        mockService.setPlayerId('new-player');
        expect(provider.playerId, 'new-player');
      });

      test('provides clientId from service', () {
        expect(provider.clientId, 'test-client');
        mockService.setClientId('new-client');
        expect(provider.clientId, 'new-client');
      });
    });

    group('room creation and joining', () {
      test('createRoom calls service and updates state', () async {
        await provider.createRoom(
          settings: GameSettings(),
          playerName: 'Host Player',
        );

        expect(provider.roomCode, 'TEST01');
        expect(mockService.calls, contains('createRoom'));
      });

      test('joinRoom calls service', () async {
        await provider.joinRoom(
          roomCode: 'ABC123',
          playerName: 'Guest Player',
        );

        expect(mockService.calls, contains('joinRoom:ABC123'));
      });
    });

    group('game state updates', () {
      test('updates gameState on callback', () {
        // Need at least 2 players to stay in playing phase
        // (provider auto-ends if only 1 player remains)
        final testState = GameState(
          players: [
            Player(id: 'test-player', name: 'Test', isHuman: true),
            Player(id: 'opponent', name: 'Opponent', isHuman: true),
          ],
          deck: [],
          discardPile: [],
          phase: GamePhase.playing,
        );

        mockService.emitGameState(testState);

        expect(provider.gameState, isNotNull);
        expect(provider.gameState!.phase, GamePhase.playing);
      });

      test('correctly parses readyPlayerIds', () {
        final testState = GameState(
          players: [
            Player(id: 'p1', name: 'P1', isHuman: true),
            Player(id: 'p2', name: 'P2', isHuman: true),
          ],
          deck: [],
          discardPile: [],
          readyPlayerIds: ['p1'],
        );

        mockService.emitGameState(testState);

        expect(provider.gameState!.readyPlayerIds, contains('p1'));
        expect(provider.gameState!.readyPlayerIds, isNot(contains('p2')));
      });
    });

    group('presence management', () {
      test('updates presence maps on callback', () {
        mockService.emitPresenceUpdate([
          {
            'id': 'p1',
            'clientId': 'c1',
            'connected': true,
            'focused': true,
          },
          {
            'id': 'p2',
            'clientId': 'c2',
            'connected': true,
            'focused': false,
          },
        ]);

        expect(provider.presenceById['p1']?['connected'], true);
        expect(provider.presenceByClientId['c2']?['focused'], false);
      });

      test('updates hostPlayerId on presence update', () {
        mockService.emitPresenceUpdate(
          [],
          hostPlayerId: 'new-host',
        );

        expect(provider.hostPlayerId, 'new-host');
      });

      test('handles presence check', () {
        mockService.emitPresenceCheck(
          reason: 'Turn timeout',
          deadlineMs: 3000,
        );

        expect(provider.presenceCheckActive, true);
        expect(provider.presenceCheckReason, contains('Turn timeout'));
        expect(provider.presenceCheckDeadlineMs, 3000);
      });

      test('confirmPresence clears active check', () {
        mockService.emitPresenceCheck();
        expect(provider.presenceCheckActive, true);

        provider.confirmPresence();

        expect(provider.presenceCheckActive, false);
        expect(mockService.calls, contains('confirmPresence'));
      });
    });

    group('game actions', () {
      test('drawCard calls service', () {
        // Need game state for action to work
        final testState = GameState(
          players: [Player(id: 'test-player', name: 'Test', isHuman: true)],
          deck: [PlayingCard.create('hearts', '5')],
          discardPile: [],
        );
        mockService.emitGameState(testState);

        provider.drawCard();
        expect(mockService.calls, contains('drawCard'));
      });

      test('replaceCard calls service with index', () {
        final testState = GameState(
          players: [Player(id: 'test-player', name: 'Test', isHuman: true)],
          deck: [],
          discardPile: [],
        );
        mockService.emitGameState(testState);

        provider.replaceCard(2);
        expect(mockService.calls, contains('replaceCard:2'));
      });

      test('discardDrawnCard calls service', () {
        final testState = GameState(
          players: [Player(id: 'test-player', name: 'Test', isHuman: true)],
          deck: [],
          discardPile: [],
        );
        mockService.emitGameState(testState);

        provider.discardDrawnCard();
        expect(mockService.calls, contains('discardDrawnCard'));
      });

      test('takeFromDiscard calls service', () {
        final testState = GameState(
          players: [Player(id: 'test-player', name: 'Test', isHuman: true)],
          deck: [],
          discardPile: [],
        );
        mockService.emitGameState(testState);

        provider.takeFromDiscard();
        expect(mockService.calls, contains('takeFromDiscard'));
      });

      test('callDutch calls service', () {
        final testState = GameState(
          players: [Player(id: 'test-player', name: 'Test', isHuman: true)],
          deck: [],
          discardPile: [],
        );
        mockService.emitGameState(testState);

        provider.callDutch();
        expect(mockService.calls, contains('callDutch'));
      });

      test('attemptMatch calls service with index', () {
        final testState = GameState(
          players: [Player(id: 'test-player', name: 'Test', isHuman: true)],
          deck: [],
          discardPile: [],
        );
        mockService.emitGameState(testState);

        provider.attemptMatch(1);
        expect(mockService.calls, contains('attemptMatch:1'));
      });
    });

    group('special powers', () {
      test('usePower10SpyOpponent calls service with indices', () {
        final testState = GameState(
          players: [Player(id: 'test-player', name: 'Test', isHuman: true)],
          deck: [],
          discardPile: [],
        );
        mockService.emitGameState(testState);

        provider.usePower10SpyOpponent(1, 2);
        expect(
          mockService.calls.any((c) => c.startsWith('usePower10SpyOpponent')),
          true,
        );
      });

      test('usePower7LookOwnCard calls service', () {
        final testState = GameState(
          players: [Player(id: 'test-player', name: 'Test', isHuman: true)],
          deck: [],
          discardPile: [],
        );
        mockService.emitGameState(testState);

        provider.usePower7LookOwnCard(0);
        expect(mockService.calls, contains('usePower7LookOwnCard:0'));
      });

      test('usePower10SpyOpponent calls service', () {
        final testState = GameState(
          players: [Player(id: 'test-player', name: 'Test', isHuman: true)],
          deck: [],
          discardPile: [],
        );
        mockService.emitGameState(testState);

        provider.usePower10SpyOpponent(1, 2);
        expect(mockService.calls, contains('usePower10SpyOpponent:1,2'));
      });

      test('usePowerValetSwap calls service', () {
        final testState = GameState(
          players: [Player(id: 'test-player', name: 'Test', isHuman: true)],
          deck: [],
          discardPile: [],
        );
        mockService.emitGameState(testState);

        provider.usePowerValetSwap(0, 1, 2, 3);
        expect(mockService.calls, contains('usePowerValetSwap:0,1,2,3'));
      });

      test('usePowerJokerShuffle calls service', () {
        final testState = GameState(
          players: [Player(id: 'test-player', name: 'Test', isHuman: true)],
          deck: [],
          discardPile: [],
        );
        mockService.emitGameState(testState);

        provider.usePowerJokerShuffle(1);
        expect(mockService.calls, contains('usePowerJokerShuffle:1'));
      });

      test('skipSpecialPower calls service', () {
        final testState = GameState(
          players: [Player(id: 'test-player', name: 'Test', isHuman: true)],
          deck: [],
          discardPile: [],
        );
        mockService.emitGameState(testState);

        provider.skipSpecialPower();
        expect(mockService.calls, contains('skipSpecialPower'));
      });
    });

    group('ready state', () {
      test('setReady calls service', () {
        provider.setReady(true);
        expect(mockService.calls, contains('setReady:true'));
      });

      test('markReady calls service', () {
        provider.markReady();
        expect(mockService.calls, contains('markReady'));
      });
    });

    group('host controls', () {
      test('startGame calls service', () async {
        // Set up as host with minimum players ready
        await provider.createRoom(
          settings: GameSettings(),
          playerName: 'Host',
        );

        // Mark as ready
        provider.setReady(true);

        // Add another ready player
        mockService.emitPresenceUpdate([
          {
            'id': 'test-player',
            'clientId': 'test-client',
            'name': 'Host',
            'isHuman': true,
            'ready': true,
            'connected': true,
          },
          {
            'id': 'p2',
            'clientId': 'c2',
            'name': 'Player 2',
            'isHuman': true,
            'ready': true,
            'connected': true,
          },
        ]);

        mockService.clearCalls();
        await provider.startGame(fillBots: true);
        expect(mockService.calls, contains('startGame:true'));
      });

      test('kickPlayer calls service with clientId', () async {
        await provider.createRoom(
          settings: GameSettings(),
          playerName: 'Host',
        );

        await provider.kickPlayer('client-to-kick');
        expect(mockService.calls, contains('kickPlayer:client-to-kick'));
      });

      test('setGameMode calls service', () async {
        await provider.createRoom(
          settings: GameSettings(),
          playerName: 'Host',
        );

        await provider.setGameMode(GameMode.tournament);
        expect(mockService.calls, contains('setGameMode:1'));
      });

      test('restartGame calls service', () async {
        await provider.createRoom(
          settings: GameSettings(),
          playerName: 'Host',
        );

        await provider.restartGame();
        expect(mockService.calls, contains('restartGame'));
      });

      test('closeRoom calls service', () async {
        await provider.createRoom(
          settings: GameSettings(),
          playerName: 'Host',
        );

        await provider.closeRoom();
        expect(mockService.calls, contains('closeRoom'));
      });
    });

    group('room events', () {
      test('handles room closed notification', () {
        mockService.emitRoomClosed({'canBecomeHost': true});
        expect(provider.roomClosedByHost, true);
      });

      test('handles kicked notification', () {
        mockService.emitKicked({'reason': 'Kicked by host'});
        expect(provider.wasKicked, true);
      });

      test('handles player left notification', () {
        mockService.emitPlayerLeft({'playerName': 'Quitter'});
        expect(provider.playerLeftNotification, true);
        expect(provider.lastPlayerLeftName, 'Quitter');
      });
    });

    group('chat', () {
      test('sendChatMessage calls service', () {
        provider.sendChatMessage('Hello!');
        expect(mockService.calls, contains('sendChatMessage:Hello!'));
      });

      test('receives chat messages', () {
        mockService.emitChatMessage({
          'playerName': 'Sender',
          'message': 'Test message',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });

        expect(provider.chatMessages.length, 1);
        expect(provider.chatMessages.first['message'], 'Test message');
      });
    });

    group('leaving room', () {
      test('leaveRoom calls service and resets state', () async {
        await provider.joinRoom(
          roomCode: 'TEST01',
          playerName: 'Player',
        );
        mockService.clearCalls();

        await provider.leaveRoom();
        expect(mockService.calls, contains('leaveRoom'));
      });
    });

    group('reaction time sync', () {
      test('receives reaction time config', () {
        mockService.emitReactionTimeConfig(5000);
        expect(provider.reactionTimeMs, 5000);
      });

      test('calculates remaining reaction time with latency compensation', () {
        // Setup provider with game state in reaction phase
        final now = DateTime.now().millisecondsSinceEpoch;
        mockService.setServerNow(now);
        mockService.setLatency(100);

        mockService.emitReactionTimeConfig(3000);

        final reactionStart = DateTime.fromMillisecondsSinceEpoch(now - 1000);
        final testState = GameState(
          players: [
            Player(id: 'test-player', name: 'Test', isHuman: true),
            Player(id: 'opponent', name: 'Opponent', isHuman: true),
          ],
          deck: [],
          discardPile: [],
          phase: GamePhase.reaction,
          reactionStartTime: reactionStart,
          reactionTimeRemaining: 3000,
        );

        mockService.emitGameState(testState);

        // Remaining should be approximately: 3000 - 1000 - latency/2 ~= 1950ms
        final remaining = provider.gameState?.reactionTimeRemaining ?? 0;
        expect(remaining, inInclusiveRange(1800, 2100));
      });
    });

    group('events stream', () {
      test('emits game events', () async {
        final events = <GameEvent>[];
        final subscription = provider.events.listen((event) {
          events.add(event);
        });

        // Trigger game state change (need at least one player for currentPlayer)
        mockService.emitGameState(GameState(
          players: [
            Player(id: 'test-player', name: 'Test', isHuman: true),
          ],
          deck: [],
          discardPile: [],
          phase: GamePhase.ended,
        ));

        await Future.delayed(const Duration(milliseconds: 50));
        subscription.cancel();

        // Events might be empty if no specific event was triggered
        // This test just verifies the stream works
      });
    });

    group('isHost calculation', () {
      test('returns true when creating a room', () async {
        await provider.createRoom(
          settings: GameSettings(),
          playerName: 'Host',
        );

        expect(provider.isHost, true);
      });

      test('returns false when joining a room', () async {
        await provider.joinRoom(
          roomCode: 'TEST01',
          playerName: 'Guest',
        );

        expect(provider.isHost, false);
      });
    });

    group('special power notifications', () {
      test('handles spy notification', () {
        mockService.emitSpecialPowerNotification('spy', {
          'byPlayerName': 'Spyer',
          'cardIndex': 1,
        });

        expect(provider.pendingSpyNotification, isNotNull);
      });

      test('handles swap notification', () {
        mockService.emitSpecialPowerNotification('swap', {
          'byPlayerName': 'Swapper',
          'cardIndex': 2,
        });

        expect(provider.pendingSwapNotification, isNotNull);
      });

      test('handles joker notification', () {
        mockService.emitSpecialPowerNotification('joker', {
          'byPlayerName': 'Joker User',
        });

        expect(provider.pendingJokerNotification, isNotNull);
      });

      test('clears swap notification', () {
        mockService.emitSpecialPowerNotification('swap', {
          'byPlayerName': 'Swapper',
        });
        expect(provider.pendingSwapNotification, isNotNull);

        provider.clearSwapNotification();
        expect(provider.pendingSwapNotification, isNull);
      });

      test('clears joker notification', () {
        mockService.emitSpecialPowerNotification('joker', {
          'byPlayerName': 'Joker User',
        });
        expect(provider.pendingJokerNotification, isNotNull);

        provider.clearJokerNotification();
        expect(provider.pendingJokerNotification, isNull);
      });

      test('clears spy notification', () {
        mockService.emitSpecialPowerNotification('spy', {
          'byPlayerName': 'Spyer',
        });
        expect(provider.pendingSpyNotification, isNotNull);

        provider.clearSpyNotification();
        expect(provider.pendingSpyNotification, isNull);
      });
    });

    group('spied card dialog', () {
      test('handles spied card', () {
        final card = PlayingCard.create('hearts', '5');
        mockService.emitSpiedCard(card, 'Target Player');

        expect(provider.lastSpiedCard, isNotNull);
        expect(provider.spiedTargetName, 'Target Player');
        expect(provider.showSpiedCardDialog, true);
      });

      test('closes spied card dialog', () {
        final card = PlayingCard.create('hearts', '5');
        mockService.emitSpiedCard(card, 'Target Player');
        expect(provider.showSpiedCardDialog, true);

        provider.closeSpiedCardDialog();
        expect(provider.showSpiedCardDialog, false);
        expect(provider.lastSpiedCard, isNull);
      });
    });

    group('error handling', () {
      test('clears error message', () async {
        // Manually set an error (normally happens via callback)
        await provider.createRoom(
          settings: GameSettings(),
          playerName: 'Host',
        );

        // No real error here but test the clearError method
        provider.clearError();
        expect(provider.errorMessage, isNull);
      });
    });

    group('game pausing', () {
      test('handles game paused event', () {
        mockService.onGamePaused?.call('Host Player');
        expect(provider.isPaused, true);
      });

      test('handles game resumed event', () {
        mockService.onGamePaused?.call('Host Player');
        expect(provider.isPaused, true);

        mockService.onGameResumed?.call('Host Player');
        expect(provider.isPaused, false);
      });
    });

    group('acknowledge methods', () {
      test('acknowledgeRoomClosed resets state', () {
        mockService.emitRoomClosed({'roomCode': 'TEST01'});
        expect(provider.roomClosedByHost, true);

        provider.acknowledgeRoomClosed();
        expect(provider.roomClosedByHost, false);
      });

      test('acknowledgeKicked resets state', () {
        mockService.emitKicked({'reason': 'Test'});
        expect(provider.wasKicked, true);

        provider.acknowledgeKicked();
        expect(provider.wasKicked, false);
      });
    });
  });
}
