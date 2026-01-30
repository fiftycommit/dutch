import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/providers/settings_provider.dart';
import 'package:dutch_game/screens/multiplayer_game_screen.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/card.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/services/multiplayer_service.dart';
import 'package:dutch_game/widgets/card_widget.dart';
import 'package:dutch_game/widgets/player_hand.dart';

class MockMultiplayerService extends MultiplayerService {
  final List<String> calls = [];

  // Callback pour les mises à jour
  Function(GameState)? gameStateUpdateCallback;

  @override
  String get playerId => 'p1';
  @override
  bool get isConnected => true;
  @override
  int get latencyMs => 0;
  @override
  int get serverNowMs => DateTime.now().millisecondsSinceEpoch;

  @override
  void drawCard() => calls.add('drawCard');
  @override
  void discardDrawnCard() => calls.add('discardDrawnCard');
  @override
  void takeFromDiscard() => calls.add('takeFromDiscard');
  @override
  void callDutch() => calls.add('callDutch');
  @override
  void replaceCard(int cardIndex) => calls.add('replaceCard:$cardIndex');

  void emitGameState(GameState state) {
    onGameStateUpdate?.call(state);
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
  Future<bool> startGame({bool fillBots = false}) async => true;
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
  void leaveRoom() {}
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
      home: MultiplayerGameScreen(),
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

  GameState createPlayingState({bool hasDrawn = false}) {
    final p1 = Player(id: 'p1', name: 'Me', isHuman: true, position: 0)
      ..hand = [makeCard('hearts', 'A', 1), makeCard('spades', '2', 2)];
    final p2 = Player(id: 'p2', name: 'Opponent', isHuman: false, position: 1)
      ..hand = [makeCard('diamonds', '3', 3)];

    final drawnCard = hasDrawn ? makeCard('clubs', '5', 5) : null;

    return GameState(
      players: [p1, p2],
      deck: [makeCard('spades', 'K', 13)],
      discardPile: [makeCard('hearts', 'Q', 12)],
      currentPlayerIndex: 0,
      phase: GamePhase.playing,
      drawnCard: drawnCard,
    );
  }

  Future<void> manualPump(WidgetTester tester) async {
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Multiplayer Game Buttons Widget Tests', () {
    testWidgets('Draw card button (PIOCHER)', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      mockService.emitGameState(createPlayingState(hasDrawn: false));
      await manualPump(tester);

      final drawBtn = find.text('PIOCHER');
      expect(drawBtn, findsOneWidget);
      await tester.tap(drawBtn);
      await tester.pump();

      expect(mockService.calls, contains('drawCard'));
    });

    testWidgets('Discard drawn card button (JETER)',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      mockService.emitGameState(createPlayingState(hasDrawn: true));
      await manualPump(tester);

      final discardBtn = find.text('JETER');
      expect(discardBtn, findsOneWidget);
      await tester.tap(discardBtn);
      await tester.pump();

      expect(mockService.calls, contains('discardDrawnCard'));
    });

    testWidgets('Dutch call with confirmation', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      mockService.emitGameState(createPlayingState(hasDrawn: false));
      await manualPump(tester);

      final dutchBtn = find.text('DUTCH');
      expect(dutchBtn, findsOneWidget);
      await tester.tap(dutchBtn);
      await manualPump(tester);

      expect(find.text('Crier DUTCH ?'), findsOneWidget);

      final confirmBtn = find.text('DUTCH !');
      await tester.tap(confirmBtn);
      await manualPump(tester); // Replaced pumpAndSettle

      expect(mockService.calls, contains('callDutch'));
    });

    testWidgets('Take from discard pile (Tap discard)',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      mockService.emitGameState(createPlayingState(hasDrawn: false));
      await manualPump(tester);

      final discardCard = find.byWidgetPredicate(
          (widget) => widget is CardWidget && widget.card?.id == 'heartsQ');

      expect(discardCard, findsOneWidget);

      await tester.tap(discardCard);
      await tester.pump();

      expect(mockService.calls, contains('takeFromDiscard'));
    });

    testWidgets('Replace card with drawn card', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      mockService.emitGameState(createPlayingState(hasDrawn: true));
      await manualPump(tester);

      // Unique finder for human hand
      final humanHand = find.byWidgetPredicate(
          (widget) => widget is PlayerHandWidget && widget.isHuman == true);

      final myCard = find
          .descendant(
            of: humanHand,
            matching: find.byType(CardWidget),
          )
          .at(0);

      await tester.tap(myCard);
      await tester.pump();

      expect(mockService.calls, contains('replaceCard:0'));
    });
  });
}
