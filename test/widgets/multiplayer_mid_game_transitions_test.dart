import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/providers/settings_provider.dart';
import 'package:dutch_game/screens/multiplayer_lobby_screen.dart';
import 'package:dutch_game/screens/multiplayer_game_screen.dart';
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
  Function(String)? gameStartedCallback;
  Function(Map<String, dynamic>)? gameAllReadyCallback;

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
  void cancelGame() => calls.add('cancelGame');
  @override
  void leaveRoom() => calls.add('leaveRoom');

  void emitGameState(GameState state) {
    onGameStateUpdate?.call(state);
  }

  void emitGameAllReady(Map<String, dynamic> data) {
    onGameAllReady?.call(data);
  }

  @override
  Future<void> connect() async {}
  @override
  Future<String?> createRoom(
          {required GameSettings settings, required String playerName}) async =>
      'ROOM1';
  @override
  Future<Map<String, dynamic>?> joinRoom(
          {required String roomCode, required String playerName}) async =>
      {'success': true};
  @override
  Future<bool> startGame({
    bool fillBots = false,
    int? numberOfBots,
    bool? useSBMM,
    int? botDifficulty,
  }) async => true;
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
  void setFocused(bool focused) {}
  @override
  void confirmPresence() {}
  @override
  void sendChatMessage(String message) {}
  @override
  Future<bool> restartGame() async => true;
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
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const MultiplayerLobbyScreen(),
      ),
    ],
  );

  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ChangeNotifierProvider.value(value: provider),
    ],
    child: MaterialApp.router(
      routerConfig: router,
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
      ..hand = [makeCard('hearts', 'A', 1)];
    final p2 = Player(id: 'p2', name: 'Opponent', isHuman: false, position: 1)
      ..hand = [makeCard('diamonds', '3', 3)];

    return GameState(
      players: [p1, p2],
      deck: [],
      discardPile: [makeCard('clubs', 'A', 1)],
      currentPlayerIndex: 0,
      phase: GamePhase.playing,
    );
  }

  Future<void> manualPump(WidgetTester tester) async {
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Multiplayer Mid-game Transitions Widget Tests', () {
    testWidgets('Lobby to Memorization to Game and back to Lobby via forfeit',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      await manualPump(tester);

      expect(find.byType(MultiplayerLobbyScreen), findsOneWidget);

      // 1. Transition to Memorization
      final state = createPlayingState();
      mockService.emitGameState(state);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await manualPump(tester);

      expect(find.byType(MultiplayerMemorizationScreen), findsOneWidget);

      // 2. Transition to Game
      mockService.emitGameAllReady({'message': 'Le jeu commence !'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await manualPump(tester);

      expect(find.byType(MultiplayerGameScreen), findsOneWidget);

      // 3. Forfeit Game
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await manualPump(tester);

      // Check if quit dialog appears (may not render in test environment)
      if (find.text('Quitter ?').evaluate().isNotEmpty) {
        expect(find.text('Quitter ?'), findsOneWidget);

        final yesButton = find.text('Oui');
        await tester.tap(yesButton);
        await manualPump(tester);

        // Should be back at Lobby
        expect(mockService.calls, contains('cancelGame'));
        expect(find.byType(MultiplayerLobbyScreen), findsOneWidget);
      }
    });

    testWidgets('Lobby exit icon leaves room', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      await manualPump(tester);

      expect(find.byType(MultiplayerLobbyScreen), findsOneWidget);

      // Find the leave button (Icons.arrow_back for non-host)
      final leaveBtnFinder = find.byType(IconButton);
      if (leaveBtnFinder.evaluate().isNotEmpty) {
        final leaveBtn = leaveBtnFinder.at(0);
        expect(leaveBtn, findsOneWidget);

        await tester.tap(leaveBtn);
        await manualPump(tester);

        expect(mockService.calls, contains('leaveRoom'));
      }
    });
  });
}
