import 'dart:async';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/services/multiplayer/multiplayer_service.dart';

/// Mock MultiplayerService for testing
class MockMultiplayerService extends MultiplayerService {
  // Track method calls
  int connectCount = 0;
  int disconnectCount = 0;
  int drawCardCount = 0;
  int replaceCardCount = 0;
  int discardDrawnCardCount = 0;
  int callDutchCount = 0;
  int attemptMatchCount = 0;
  int skipSpecialPowerCount = 0;
  int joinRoomCount = 0;
  int createRoomCount = 0;
  int leaveRoomCount = 0;
  int closeRoomCount = 0;
  int startGameCount = 0;
  int setReadyCount = 0;
  int setFocusedCount = 0;

  // Mock state
  String? _mockPlayerId = 'test_player';
  String? _mockClientId = 'test_client';
  bool _mockIsConnected = true;
  SocketConnectionState _mockConnectionState = SocketConnectionState.connected;
  final int _mockLatencyMs = 50;
  final int _mockServerTimeOffsetMs = 0;

  // Mock return values
  Map<String, dynamic>? mockCreateRoomResult;
  Map<String, dynamic>? mockJoinRoomResult;
  bool mockStartGameResult = true;
  bool mockCloseRoomResult = true;
  List<Map<String, dynamic>>? mockPublicRooms;

  @override
  String? get playerId => _mockPlayerId;

  @override
  String? get clientId => _mockClientId;

  @override
  bool get isConnected => _mockIsConnected;

  @override
  SocketConnectionState get connectionState => _mockConnectionState;

  @override
  int get latencyMs => _mockLatencyMs;

  @override
  int get serverTimeOffsetMs => _mockServerTimeOffsetMs;

  @override
  int get serverNowMs =>
      DateTime.now().millisecondsSinceEpoch + _mockServerTimeOffsetMs;

  void setPlayerId(String? id) => _mockPlayerId = id;
  void setClientId(String? id) => _mockClientId = id;
  void setConnected(bool connected) => _mockIsConnected = connected;
  void setConnectionState(SocketConnectionState state) =>
      _mockConnectionState = state;

  @override
  Future<void> connect() async {
    connectCount++;
    _mockIsConnected = true;
    _mockConnectionState = SocketConnectionState.connected;
  }

  @override
  void disconnect() {
    disconnectCount++;
    _mockIsConnected = false;
    _mockConnectionState = SocketConnectionState.disconnected;
  }

  String? mockRoomCode = 'TEST123';

  @override
  Future<String?> createRoom({
    required GameSettings settings,
    required String playerName,
  }) async {
    createRoomCount++;
    return mockRoomCode;
  }

  @override
  Future<Map<String, dynamic>?> joinRoom(
      {required String roomCode, required String playerName}) async {
    joinRoomCount++;
    return mockJoinRoomResult ??
        {
          'roomCode': roomCode,
          'hostPlayerId': 'host_player',
          'settings': GameSettings().toJson(),
          'players': [
            {
              'id': 'host_player',
              'clientId': 'host_client',
              'name': 'Host',
              'isHuman': true,
              'ready': true
            },
            {
              'id': _mockPlayerId,
              'clientId': _mockClientId,
              'name': playerName,
              'isHuman': true,
              'ready': false
            },
          ],
        };
  }

  @override
  void leaveRoom() {
    leaveRoomCount++;
  }

  @override
  Future<bool> closeRoom() async {
    closeRoomCount++;
    return mockCloseRoomResult;
  }

  @override
  Future<bool> startGame(
      {bool fillBots = false,
      int? numberOfBots,
      bool? useSBMM,
      int? botDifficulty}) async {
    startGameCount++;
    return mockStartGameResult;
  }

  @override
  void setReady(bool ready) {
    setReadyCount++;
  }

  @override
  void setFocused(bool focused) {
    setFocusedCount++;
  }

  @override
  Future<bool> drawCard() async {
    drawCardCount++;
    return true;
  }

  @override
  Future<bool> replaceCard(int cardIndex) async {
    replaceCardCount++;
    return true;
  }

  @override
  Future<bool> discardDrawnCard() async {
    discardDrawnCardCount++;
    return true;
  }

  @override
  Future<bool> callDutch() async {
    callDutchCount++;
    return true;
  }

  @override
  Future<bool> attemptMatch(int cardIndex) async {
    attemptMatchCount++;
    return true;
  }

  @override
  Future<bool> skipSpecialPower() async {
    skipSpecialPowerCount++;
    return true;
  }

  @override
  Future<List<Map<String, dynamic>>?> getPublicRooms() async {
    return mockPublicRooms;
  }

  @override
  Future<bool> checkServerHealth() async => true;

  void reset() {
    connectCount = 0;
    disconnectCount = 0;
    drawCardCount = 0;
    replaceCardCount = 0;
    discardDrawnCardCount = 0;
    callDutchCount = 0;
    attemptMatchCount = 0;
    skipSpecialPowerCount = 0;
    joinRoomCount = 0;
    createRoomCount = 0;
    leaveRoomCount = 0;
    closeRoomCount = 0;
    startGameCount = 0;
    setReadyCount = 0;
    setFocusedCount = 0;
  }

  /// Simulate receiving a game state update
  void simulateGameStateUpdate(GameState gameState) {
    onGameStateUpdate?.call(gameState);
  }

  /// Simulate a player joining
  void simulatePlayerJoined(Map<String, dynamic> data) {
    onPlayerJoined?.call(data);
  }

  /// Simulate an error
  void simulateError(String error) {
    onError?.call(error);
  }

  /// Simulate game started
  void simulateGameStarted(String message) {
    onGameStarted?.call(message);
  }

  /// Simulate timer update
  void simulateTimerUpdate(int remaining) {
    onTimerUpdate?.call(remaining);
  }

  /// Simulate connection state change
  void simulateConnectionStateChange(SocketConnectionState state) {
    _mockConnectionState = state;
    onSocketConnectionStateChanged?.call(state);
  }
}
