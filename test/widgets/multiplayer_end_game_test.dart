import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/providers/settings_provider.dart';
import 'package:dutch_game/screens/multiplayer_lobby_screen.dart';
import 'package:dutch_game/screens/multiplayer_game_screen.dart';
import 'package:dutch_game/screens/multiplayer_dutch_reveal_screen.dart';
import 'package:dutch_game/screens/multiplayer_results_screen.dart';
import 'package:dutch_game/screens/multiplayer_memorization_screen.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/card.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/services/multiplayer_service.dart';

class MockMultiplayerService extends MultiplayerService {
  final List<String> calls = [];

  // Callbacks pour les tests
  Function(GameState)? gameStateUpdateCallback;
  Function(Map<String, dynamic>)? gameAllReadyCallback;
  Function(Map<String, dynamic>)? roomRestartedCallback;

  @override
  String get playerId => 'p1';
  @override
  String get clientId => 'c1';
  @override
  bool get isConnected => true;
  @override
  int get latencyMs => 0;
  @override
  int get serverNowMs => DateTime.now().millisecondsSinceEpoch;

  @override
  Future<bool> restartGame() async {
    calls.add('restartGame');
    return true;
  }

  void emitGameState(GameState state) {
    onGameStateUpdate?.call(state);
  }

  void emitGameAllReady(Map<String, dynamic> data) {
    onGameAllReady?.call(data);
  }

  void emitRoomRestarted(Map<String, dynamic> data) {
    onRoomRestarted?.call(data);
  }

  @override
  Future<void> connect() async {}
  @override
  Future<String?> createRoom(
      {required GameSettings settings, required String playerName}) async {
    return 'ROOM1';
  }

  @override
  Future<Map<String, dynamic>?> joinRoom(
      {required String roomCode, required String playerName}) async {
    return {
      'success': true,
      'room': {'hostPlayerId': 'p2', 'players': []}
    };
  }

  @override
  void leaveRoom() => calls.add('leaveRoom');
  @override
  void setFocused(bool focused) {}

  // Necessary overrides
  @override
  void drawCard() {}
  @override
  void replaceCard(int cardIndex) {}
  @override
  void discardDrawnCard() {}
  @override
  void takeFromDiscard() {}
  @override
  void callDutch() {}
  @override
  void attemptMatch(int cardIndex) {}
  @override
  void setReady(bool ready) {}
  @override
  void markReady() {}
  @override
  void confirmPresence() {}
  @override
  void sendChatMessage(String message) {}
  @override
  Future<bool> closeRoom() async => true;
  @override
  Future<bool> kickPlayer(String clientId) async => true;
  @override
  Future<bool> setGameMode(int mode) async => true;
  @override
  void requestFullState() {}
  @override
  Future<void> cleanupInactiveRooms() async {}
}

Widget createTestApp(MultiplayerGameProvider provider) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ChangeNotifierProvider.value(value: provider),
    ],
    child: const MaterialApp(
      home: MultiplayerLobbyScreen(),
    ),
  );
}

void main() {
  late MockMultiplayerService mockService;
  late MultiplayerGameProvider provider;

  setUp(() {
    mockService = MockMultiplayerService();
    provider = MultiplayerGameProvider(multiplayerService: mockService);
  });

  tearDown(() {
    provider.dispose();
  });

  PlayingCard makeCard(String s, String v, int p) =>
      PlayingCard(suit: s, value: v, points: p, isSpecial: false, id: '$s$v');

  GameState createPlayingState() {
    final p1 = Player(id: 'p1', name: 'Me', isHuman: true, position: 0)
      ..hand = [makeCard('hearts', '2', 2)];
    final p2 = Player(id: 'p2', name: 'Opponent', isHuman: false, position: 1)
      ..hand = [makeCard('diamonds', '3', 3)];

    return GameState(
      players: [p1, p2],
      deck: [],
      discardPile: [],
      currentPlayerIndex: 0,
      phase: GamePhase.playing,
    );
  }

  GameState createEndedState({required bool withDutch}) {
    final p1 = Player(id: 'p1', name: 'Me', isHuman: true, position: 0)
      ..hand = [makeCard('hearts', 'A', 1)];
    final p2 = Player(id: 'p2', name: 'Opponent', isHuman: false, position: 1)
      ..hand = [makeCard('diamonds', '3', 3)];

    return GameState(
      players: [p1, p2],
      deck: [],
      discardPile: [],
      currentPlayerIndex: 0,
      phase: GamePhase.ended,
      dutchCallerId: withDutch ? 'p1' : null,
    );
  }

  Future<void> manualPump(WidgetTester tester, {int iterations = 20}) async {
    for (int i = 0; i < iterations; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Multiplayer End-game Sequence Widget Tests', () {
    testWidgets('Full sequence: Game -> Reveal -> Results -> Rematch (Host)',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      await manualPump(tester);

      // 0. Become Host
      await provider.createRoom(settings: GameSettings(), playerName: 'Me');

      // 1. Enter Game via emissions
      mockService.emitGameState(createPlayingState());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await manualPump(tester);
      expect(find.byType(MultiplayerMemorizationScreen), findsOneWidget);

      mockService.emitGameAllReady({'message': 'Go'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await manualPump(tester);
      expect(find.byType(MultiplayerGameScreen), findsOneWidget);

      // 2. End Game
      mockService.emitGameState(createEndedState(withDutch: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await manualPump(tester);

      expect(find.byType(MultiplayerDutchRevealScreen), findsOneWidget);

      // 3. Wait for Reveal Screen to finish and transition to Results
      await manualPump(tester, iterations: 60); // 6 seconds

      expect(find.byType(MultiplayerResultsScreen), findsOneWidget);

      // 4. Rematch (Host)
      final rematchBtn = find.text('Retour au Lobby (Host)');
      expect(rematchBtn, findsOneWidget);
      await tester.tap(rematchBtn);
      await manualPump(tester);

      expect(mockService.calls, contains('restartGame'));
    });

    testWidgets('Direct transition to Results and return to Lobby (Non-Host)',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      await manualPump(tester);

      // 0. Join Room (Non-Host)
      await provider.joinRoom(roomCode: 'ROOM1', playerName: 'Me');

      // 1. Enter Game via emissions
      mockService.emitGameState(createPlayingState());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await manualPump(tester);

      mockService.emitGameAllReady({'message': 'Go'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await manualPump(tester);
      expect(find.byType(MultiplayerGameScreen), findsOneWidget);

      // 2. End Game (No Dutch)
      mockService.emitGameState(createEndedState(withDutch: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await manualPump(tester);

      expect(find.byType(MultiplayerResultsScreen), findsOneWidget);

      // 3. Return to Lobby (Non-Host)
      // Simulate host restarting the room (clears isPlaying)
      mockService.emitRoomRestarted({'roomCode': 'ROOM1'});
      await tester.pump();

      final lobbyBtn = find.text('Retour au Lobby');
      expect(lobbyBtn, findsOneWidget);
      await tester.tap(lobbyBtn);
      await manualPump(tester, iterations: 30);

      expect(find.byType(MultiplayerLobbyScreen), findsOneWidget);
    });

    testWidgets('Quitting from Results leaves room',
        (WidgetTester tester) async {
      final endedState = createEndedState(withDutch: false);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider.value(value: provider),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              return Center(
                child: SizedBox(
                  width: 100,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MultiplayerResultsScreen(
                          gameState: endedState,
                          localPlayerId: 'p1',
                        ),
                      ),
                    ),
                    child: const Text('Go'),
                  ),
                ),
              );
            }),
          ),
        ),
      ));

      await tester.tap(find.text('Go'));
      await manualPump(tester);

      expect(find.byType(MultiplayerResultsScreen), findsOneWidget);

      final quitBtn = find.text('Quitter');
      expect(quitBtn, findsOneWidget);
      await tester.tap(quitBtn);
      await manualPump(tester);

      expect(mockService.calls, contains('leaveRoom'));
    });
  });
}
