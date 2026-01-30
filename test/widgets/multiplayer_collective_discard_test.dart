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

  // Callback pour les mises à jour de l'état du jeu
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
  void attemptMatch(int cardIndex) => calls.add('attemptMatch:$cardIndex');

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

  GameState createReactionState() {
    final p1 = Player(id: 'p1', name: 'Me', isHuman: true, position: 0)
      ..hand = [makeCard('hearts', 'A', 1), makeCard('spades', '10', 10)];
    final p2 = Player(id: 'p2', name: 'Opponent', isHuman: false, position: 1)
      ..hand = [makeCard('diamonds', '3', 3)];

    return GameState(
      players: [p1, p2],
      deck: [],
      discardPile: [makeCard('clubs', 'A', 1)], // Top is Ace
      currentPlayerIndex: 1, // Opponent's turn
      phase: GamePhase.reaction,
      isWaitingForSpecialPower: false,
    );
  }

  Future<void> manualPump(WidgetTester tester, {int seconds = 1}) async {
    for (int i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Multiplayer Collective Discard Widget Tests', () {
    testWidgets('Attempt match during reaction phase',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      final state = createReactionState();
      mockService.emitGameState(state);
      await manualPump(tester);

      final humanHandFinder = find.byWidgetPredicate(
          (widget) => widget is PlayerHandWidget && widget.isHuman == true);

      final myCard = find
          .descendant(
            of: humanHandFinder,
            matching: find.byType(CardWidget),
          )
          .at(0);

      await tester.tap(myCard);
      await tester.pump();

      expect(mockService.calls, contains('attemptMatch:0'));

      // Cleanup: Stop reaction ticker
      state.phase = GamePhase.playing;
      mockService.emitGameState(state);
      await tester.pumpAndSettle();
    });

    testWidgets('Cannot match during playing phase on opponent turn',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      final state = createReactionState();
      state.phase = GamePhase.playing; // Not reaction phase
      mockService.emitGameState(state);
      await manualPump(tester);

      final humanHandFinder = find.byWidgetPredicate(
          (widget) => widget is PlayerHandWidget && widget.isHuman == true);

      final myCard = find
          .descendant(
            of: humanHandFinder,
            matching: find.byType(CardWidget),
          )
          .at(0);

      await tester.tap(myCard);
      await tester.pump();

      expect(mockService.calls, isNot(contains(startsWith('attemptMatch'))));
    });

    group('Match Result Handlers', () {
      testWidgets('Selection/Penalty UI check', (WidgetTester tester) async {
        await tester.pumpWidget(createTestApp(provider));
        final state = createReactionState();
        mockService.emitGameState(state);
        await manualPump(tester);

        // Verify that shaking indices are passed to the hand widget
        provider.shakingCardIndices = {0};
        // Use a small delay to allow any internal state to settle if needed,
        // though notifyListeners should be immediate.
        provider.notifyListeners();
        await tester.pump();

        final humanHand = tester.widget<PlayerHandWidget>(
            find.byWidgetPredicate(
                (widget) => widget is PlayerHandWidget && widget.isHuman));
        expect(humanHand.selectedIndices, contains(0));

        // Cleanup: Stop reaction ticker
        state.phase = GamePhase.playing;
        mockService.emitGameState(state);
        await tester.pumpAndSettle();
      });
    });
  });
}
