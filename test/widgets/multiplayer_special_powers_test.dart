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
import 'package:dutch_game/widgets/responsive_dialog.dart';

class MockMultiplayerService extends MultiplayerService {
  final List<String> calls = [];

  @override
  Function(GameState)? onGameStateUpdate;

  @override
  String get playerId => 'p1';

  @override
  bool get isConnected => true;

  @override
  int get latencyMs => 0;

  @override
  int get serverNowMs => DateTime.now().millisecondsSinceEpoch;

  @override
  void usePower7LookOwnCard(int cardIndex) => calls.add('usePower7:$cardIndex');

  @override
  void usePower10SpyOpponent(int targetPlayerIndex, int targetCardIndex) =>
      calls.add('usePower10:$targetPlayerIndex,$targetCardIndex');

  @override
  void usePowerValetSwap(int p1, int c1, int p2, int c2) =>
      calls.add('usePowerSwap:$p1,$c1,$p2,$c2');

  @override
  void usePowerJokerShuffle(int targetPlayerIndex) =>
      calls.add('usePowerJoker:$targetPlayerIndex');

  @override
  void skipSpecialPower() => calls.add('skipPower');

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

  GameState createPowerState(String value) {
    final p1 = Player(id: 'p1', name: 'Me', isHuman: true, position: 0)
      ..hand = [makeCard('hearts', 'A', 1), makeCard('spades', '2', 2)];
    final p2 = Player(id: 'p2', name: 'Opponent', isHuman: false, position: 1)
      ..hand = [makeCard('diamonds', '3', 3), makeCard('clubs', '4', 4)];

    final trigger = makeCard('hearts', value, 0);

    return GameState(
      players: [p1, p2],
      deck: [],
      discardPile: [],
      currentPlayerIndex: 0,
      phase: GamePhase.playing,
      drawnCard: trigger,
      specialCardToActivate: trigger,
      isWaitingForSpecialPower: true,
    );
  }

  Future<void> manualPump(WidgetTester tester, {int seconds = 1}) async {
    for (int i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Multiplayer Special Powers Widget Tests', () {
    testWidgets('Power 7 Dialog: Look at own card',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      final state = createPowerState('7');
      mockService.emitGameState(state);
      await manualPump(tester, seconds: 2);

      expect(find.textContaining('7 REGARDER'), findsOneWidget);

      final detector = find
          .descendant(
            of: find.byType(ResponsiveDialog),
            matching: find.byType(GestureDetector),
          )
          .first;

      await tester.tap(detector);
      await manualPump(tester, seconds: 3);
      expect(mockService.calls, contains('usePower7:0'));
    });

    testWidgets('Power 10 Dialog: Spy opponent', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      final state = createPowerState('10');
      mockService.emitGameState(state);
      await manualPump(tester, seconds: 2);

      expect(find.textContaining('10 ESPIONNER'), findsOneWidget);

      // Select Opponent button
      final opponentBtn = find
          .descendant(
            of: find.byType(ResponsiveDialog),
            matching: find.textContaining('Opponent'),
          )
          .first;
      await tester.tap(opponentBtn);
      await manualPump(tester, seconds: 2);

      // Tapping card
      final cardDetector = find
          .descendant(
            of: find.byType(ResponsiveDialog),
            matching: find.byType(GestureDetector),
          )
          .first;

      await tester.tap(cardDetector);
      await manualPump(tester, seconds: 3);
      expect(mockService.calls, contains('usePower10:1,0'));
    });

    testWidgets('Valet (J) Dialog: Swap cards', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      final state = createPowerState('V');
      mockService.emitGameState(state);
      await manualPump(tester, seconds: 2);

      expect(find.textContaining('VALET : ECHANGE'), findsOneWidget);
      await tester.tap(find.text('CHOISIR\n2 CARTES'));
      await manualPump(tester, seconds: 2);

      // 1. Select Player A (index 0: Vous)
      final p1Btn = find
          .descendant(
            of: find.byType(Wrap).at(0),
            matching: find.byType(GestureDetector),
          )
          .at(0);
      await tester.tap(p1Btn);
      await manualPump(tester, seconds: 1);

      // 2. Select Card A (Wrap 1 appears)
      final card1Btn = find
          .descendant(
            of: find.byType(Wrap).at(1),
            matching: find.byType(GestureDetector),
          )
          .at(0);
      await tester.tap(card1Btn);
      await manualPump(tester, seconds: 1);

      // 3. Select Player B (Wrap 2 is always there, but index 0 is now Opponent because A is excluded)
      final p2Btn = find
          .descendant(
            of: find.byType(Wrap).at(2),
            matching: find.byType(GestureDetector),
          )
          .at(0);
      await tester.tap(p2Btn);
      await manualPump(tester, seconds: 1);

      // 4. Select Card B (Wrap 3 appears)
      final card2Btn = find
          .descendant(
            of: find.byType(Wrap).at(3),
            matching: find.byType(GestureDetector),
          )
          .at(0);
      await tester.tap(card2Btn);
      await manualPump(tester, seconds: 1);

      // 5. Tap ECHANGER
      await tester.tap(find.text('ECHANGER'));
      await manualPump(tester, seconds: 3);
      expect(mockService.calls, contains('usePowerSwap:0,0,1,0'));
    });

    testWidgets('Joker (K) Dialog: Shuffle', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      final state = createPowerState('JOKER');
      mockService.emitGameState(state);
      await manualPump(tester, seconds: 2);

      expect(find.textContaining('JOKER : CHAOS'), findsOneWidget);

      // Select Opponent button
      final oppTxt = find
          .descendant(
            of: find.byType(ResponsiveDialog),
            matching: find.textContaining('Opponent'),
          )
          .first;
      await tester.tap(oppTxt);
      await manualPump(tester, seconds: 2);

      expect(find.text('OK'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await manualPump(tester, seconds: 3);
      expect(mockService.calls, contains('usePowerJoker:1'));
    });

    testWidgets('Skip power functionality', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      final state = createPowerState('7');
      mockService.emitGameState(state);
      await manualPump(tester, seconds: 2);

      await tester.tap(find.text('PASSER').first);
      await manualPump(tester, seconds: 3);
      expect(mockService.calls, contains('skipPower'));
    });
  });
}
