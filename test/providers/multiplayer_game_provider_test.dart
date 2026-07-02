import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';
import 'package:dutch_game/services/multiplayer/multiplayer_service.dart';
import '../mocks/mock_multiplayer_service.dart';
import '../mocks/mock_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMultiplayerService mockService;
  late MultiplayerGameProvider provider;

  setUp(() {
    mockService = MockMultiplayerService();
    provider = MultiplayerGameProvider(
      multiplayerService: mockService,
      hapticService: MockHapticService(),
    );
  });

  tearDown(() {
    provider.dispose();
  });

  group('MultiplayerGameProvider - Initialization', () {
    test('initial state is not connected to room', () {
      expect(provider.isInLobby, false);
      expect(provider.isPlaying, false);
      expect(provider.hasActiveGame, false);
    });

    test('initial state has no game state', () {
      expect(provider.gameState, isNull);
      expect(provider.roomCode, isNull);
    });

    test('playerId comes from service', () {
      expect(provider.playerId, 'test_player');
    });

    test('clientId comes from service', () {
      expect(provider.clientId, 'test_client');
    });

    test('isConnected delegates to service', () {
      expect(provider.isConnected, true);
      mockService.setConnected(false);
      expect(provider.isConnected, false);
    });
  });

  group('MultiplayerGameProvider - Room Creation', () {
    test('createRoom calls service and sets host state', () async {
      await provider.createRoom(
        playerName: 'TestPlayer',
        settings: GameSettings(gameMode: GameMode.quick),
      );

      expect(mockService.createRoomCount, 1);
      expect(provider.isHost, true);
      expect(provider.isInLobby, true);
    });

    test('createRoom stores room code', () async {
      mockService.mockRoomCode = 'ABCD12';

      await provider.createRoom(
        playerName: 'TestPlayer',
        settings: GameSettings(gameMode: GameMode.quick),
      );

      expect(provider.roomCode, 'ABCD12');
    });

    test('createRoom handles failure gracefully', () async {
      mockService.mockRoomCode = null;

      await provider.createRoom(
        playerName: 'TestPlayer',
        settings: GameSettings(gameMode: GameMode.quick),
      );

      // Should not throw, but room code will be null
      expect(mockService.createRoomCount, 1);
    });
  });

  group('MultiplayerGameProvider - Join Room', () {
    test('joinRoom calls service', () async {
      await provider.joinRoom(
        roomCode: 'TEST123',
        playerName: 'Joiner',
      );

      expect(mockService.joinRoomCount, 1);
      expect(provider.isInLobby, true);
      expect(provider.isHost, false);
    });

    test('joinRoom stores room code', () async {
      await provider.joinRoom(
        roomCode: 'ROOM456',
        playerName: 'Joiner',
      );

      expect(provider.roomCode, 'ROOM456');
    });

    test('joinRoom populates players list', () async {
      await provider.joinRoom(
        roomCode: 'TEST123',
        playerName: 'Joiner',
      );

      expect(provider.playersInLobby.length, greaterThan(0));
    });
  });

  group('MultiplayerGameProvider - Game Actions', () {
    setUp(() async {
      // Setup a game state for action tests
      final gameState = _createTestGameState(mockService.playerId!);
      mockService.simulateGameStateUpdate(gameState);
      // Wait for state to propagate
      await Future.delayed(const Duration(milliseconds: 50));
    });

    test('drawCard calls service when game state exists', () {
      provider.drawCard();
      expect(mockService.drawCardCount, 1);
    });

    test('replaceCard calls service', () {
      provider.replaceCard(0);
      expect(mockService.replaceCardCount, 1);
    });

    test('discardDrawnCard calls service', () {
      provider.discardDrawnCard();
      expect(mockService.discardDrawnCardCount, 1);
    });

    test('callDutch calls service', () {
      provider.callDutch();
      expect(mockService.callDutchCount, 1);
    });

    test('attemptMatch calls service', () {
      provider.gameState!.phase = GamePhase.reaction;
      provider.attemptMatch(0);
      expect(mockService.attemptMatchCount, 1);
    });

    test('skipSpecialPower calls service', () {
      provider.skipSpecialPower();
      expect(mockService.skipSpecialPowerCount, 1);
    });
  });

  group('MultiplayerGameProvider - handleCardTap', () {
    test('handleCardTap does nothing without game state', () {
      provider.handleCardTap(0);
      // Should not throw
      expect(mockService.attemptMatchCount, 0);
      expect(mockService.replaceCardCount, 0);
    });

    test('handleCardTap calls attemptMatch in reaction phase', () async {
      final gameState = _createTestGameState(mockService.playerId!);
      gameState.phase = GamePhase.reaction;
      mockService.simulateGameStateUpdate(gameState);
      await Future.delayed(const Duration(milliseconds: 50));

      provider.handleCardTap(0);
      expect(mockService.attemptMatchCount, 1);
    });

    test('handleCardTap calls replaceCard in playing phase with drawn card',
        () async {
      final gameState = _createTestGameState(mockService.playerId!);
      gameState.phase = GamePhase.playing;
      gameState.drawnCard = PlayingCard.create('hearts', 'A');
      // Make sure local player is current
      final localIndex =
          gameState.players.indexWhere((p) => p.id == mockService.playerId);
      gameState.currentPlayerIndex = localIndex;
      mockService.simulateGameStateUpdate(gameState);
      await Future.delayed(const Duration(milliseconds: 50));

      provider.handleCardTap(0);
      expect(mockService.replaceCardCount, 1);
    });
  });

  group('MultiplayerGameProvider - Local Player', () {
    test('localPlayer returns player matching playerId', () async {
      final gameState = _createTestGameState(mockService.playerId!);
      mockService.simulateGameStateUpdate(gameState);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(provider.localPlayer, isNotNull);
      expect(provider.localPlayer!.id, mockService.playerId);
    });

    test('isLocalPlayerTurn returns true when local player is current',
        () async {
      final gameState = _createTestGameState(mockService.playerId!);
      final localIndex =
          gameState.players.indexWhere((p) => p.id == mockService.playerId);
      gameState.currentPlayerIndex = localIndex;
      mockService.simulateGameStateUpdate(gameState);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(provider.isLocalPlayerTurn, true);
    });

    test('isLocalPlayerTurn returns false when other player is current',
        () async {
      final gameState = _createTestGameState(mockService.playerId!);
      // Set to another player
      gameState.currentPlayerIndex = 1;
      mockService.simulateGameStateUpdate(gameState);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(provider.isLocalPlayerTurn, false);
    });

    test('canLocalPlayerAct requires playing phase and local turn', () async {
      final gameState = _createTestGameState(mockService.playerId!);
      final localIndex =
          gameState.players.indexWhere((p) => p.id == mockService.playerId);
      gameState.currentPlayerIndex = localIndex;
      gameState.phase = GamePhase.playing;
      mockService.simulateGameStateUpdate(gameState);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(provider.canLocalPlayerAct, true);
    });

    test('canLocalPlayerAct false in reaction phase', () async {
      final gameState = _createTestGameState(mockService.playerId!);
      final localIndex =
          gameState.players.indexWhere((p) => p.id == mockService.playerId);
      gameState.currentPlayerIndex = localIndex;
      gameState.phase = GamePhase.reaction;
      mockService.simulateGameStateUpdate(gameState);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(provider.canLocalPlayerAct, false);
    });
  });

  group('MultiplayerGameProvider - Host Actions', () {
    test('startGame requires host', () async {
      provider.setReady(true);
      await provider.startGame();

      // Not host, should show error
      expect(provider.errorMessage, contains("hôte"));
    });

    test('closeRoom requires host', () async {
      final result = await provider.closeRoom();
      expect(result, false);
    });

    test('kickPlayer requires host', () async {
      final result = await provider.kickPlayer('some_client');
      expect(result, false);
    });

    test('setGameMode requires host', () async {
      final result = await provider.setGameMode(GameMode.tournament);
      expect(result, false);
    });
  });

  group('MultiplayerGameProvider - Ready State', () {
    test('setReady calls service', () {
      provider.setReady(true);
      expect(mockService.setReadyCount, 1);
    });

    test('setReady can be called multiple times', () {
      provider.setReady(true);
      provider.setReady(false);
      expect(mockService.setReadyCount, 2);
    });
  });

  group('MultiplayerGameProvider - Connection Events', () {
    test('handles connection state changes', () {
      mockService
          .simulateConnectionStateChange(SocketConnectionState.disconnected);
      expect(provider.connectionState, SocketConnectionState.disconnected);
    });

    test('handles reconnecting state', () {
      mockService
          .simulateConnectionStateChange(SocketConnectionState.reconnecting);
      expect(provider.connectionState, SocketConnectionState.reconnecting);
    });
  });

  group('MultiplayerGameProvider - Error Handling', () {
    test('error from service is accessible', () {
      mockService.simulateError('Test error message');
      // Error is handled by notification manager
      expect(provider.errorMessage, isNotNull);
    });
  });

  group('MultiplayerGameProvider - Leave Room', () {
    test('leaveRoom resets state', () async {
      await provider.joinRoom(roomCode: 'TEST123', playerName: 'Test');
      expect(provider.isInLobby, true);

      await provider.leaveRoom();

      expect(provider.isInLobby, false);
      expect(provider.roomCode, isNull);
    });
  });

  group('MultiplayerGameProvider - AFK Players', () {
    test('isPlayerAfk returns false for non-AFK player', () {
      expect(provider.isPlayerAfk('some_player'), false);
    });
  });
}

/// Create a test game state with the given player as participant
GameState _createTestGameState(String localPlayerId) {
  final players = [
    Player(id: localPlayerId, name: 'Local', isHuman: true, position: 0),
    Player(id: 'opponent_1', name: 'Opponent', isHuman: true, position: 1),
  ];

  // Give players cards
  for (var player in players) {
    player.hand = [
      PlayingCard.create('hearts', 'A'),
      PlayingCard.create('diamonds', '2'),
      PlayingCard.create('clubs', '3'),
      PlayingCard.create('spades', '4'),
    ];
    player.knownCards = List.filled(4, false, growable: true);
  }

  return GameState(
    players: players,
    deck: GameState.createFullDeck().sublist(0, 40),
    discardPile: [PlayingCard.create('hearts', '5')],
    currentPlayerIndex: 0,
    phase: GamePhase.playing,
  );
}
