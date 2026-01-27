import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:provider/provider.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/card.dart';
import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/providers/settings_provider.dart';
import 'package:dutch_game/screens/multiplayer_lobby_screen.dart';
import 'package:dutch_game/screens/multiplayer_game_screen.dart';
import 'package:dutch_game/widgets/card_widget.dart';
import 'package:dutch_game/widgets/center_table.dart';
import 'package:dutch_game/services/multiplayer_service.dart';

// --- MOCK SERVICE ---

class MockMultiplayerService extends MultiplayerService {
  @override
  bool get isConnected => true;

  @override
  String? get playerId => 'p1';

  @override
  String? get clientId => 'c1';

  @override
  Future<void> connect() async {}

  @override
  Future<String?> createRoom({
    required GameSettings settings,
    required String playerName,
  }) async {
    return 'TEST01';
  }

  @override
  Future<bool> startGame({bool fillBots = false}) async {
    // Simulate game start event
    onGameStarted?.call("Game Started");

    // Emit initial game state
    final state = _createInitialState();
    onGameStateUpdate?.call(state);
    return true;
  }

  @override
  void drawCard() {
    // Simulate drawing a card
    final current = _createInitialState();
    current.phase = GamePhase.playing;
    // Drawn card: 5 of Hearts
    current.drawnCard = PlayingCard(
        suit: 'hearts', value: '5', points: 5, isSpecial: false, id: 'h5');
    onGameStateUpdate?.call(current);
  }

  @override
  void discardDrawnCard() {
    // Simulate discard
    final current = _createInitialState();
    current.phase = GamePhase.playing;
    current.drawnCard = null;
    current.discardPile = [
      PlayingCard(
          suit: 'hearts', value: '5', points: 5, isSpecial: false, id: 'h5')
    ];
    onGameStateUpdate?.call(current);
  }

  @override
  Future<bool> restartGame() async {
    onRoomRestarted?.call({'success': true});
    return true;
  }

  // Helper to emit presence
  void emitPresenceUpdate(List<Map<String, dynamic>> players) {
    onPresenceUpdate?.call({'players': players, 'hostPlayerId': 'p1'});
  }

  // Method to manually emit state from test
  void emitGameState(GameState state) {
    onGameStateUpdate?.call(state);
  }

  @override
  void setFocused(bool focused) {}

  // Helper to create state
  GameState _createInitialState() {
    // Helper to make a card
    PlayingCard makeCard(String s, String v, int p) =>
        PlayingCard(suit: s, value: v, points: p, isSpecial: false, id: '$s$v');

    final p1 = Player(id: 'p1', name: 'Host', isHuman: true, position: 0)
      ..hand = [makeCard('hearts', 'A', 1), makeCard('spades', 'A', 1)]
      ..knownCards = [false, false];

    final p2 = Player(id: 'p2', name: 'Guest', isHuman: false, position: 1)
      ..hand = [makeCard('diamonds', '2', 2), makeCard('clubs', '2', 2)];

    return GameState(
      players: [p1, p2],
      deck: [makeCard('spades', 'A', 1)],
      discardPile: [],
      currentPlayerIndex: 0,
      phase: GamePhase.setup, // Acts as initial phase
      reactionTimeRemaining: 0,
    );
  }
}

// --- TEST APP ---

class TestMultiplayerApp extends StatelessWidget {
  final MockMultiplayerService mockService;

  const TestMultiplayerApp({super.key, required this.mockService});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(
          create: (_) =>
              MultiplayerGameProvider(multiplayerService: mockService),
        ),
      ],
      child: MaterialApp(
        home: Builder(builder: (context) {
          return const MultiplayerLobbyScreen();
        }),
      ),
    );
  }
}

void main() {
  testWidgets('Multiplayer E2E Flow: Lobby -> Game -> Results -> Rematch',
      (tester) async {
    final mockService = MockMultiplayerService();

    // Pump widget and wait for frames
    await tester.pumpWidget(TestMultiplayerApp(mockService: mockService));
    await tester.pump(const Duration(seconds: 1)); // Wait for initial render

    // 1. Verify Lobby
    expect(find.text("Salle d'attente"), findsOneWidget);

    final context = tester.element(find.byType(MultiplayerLobbyScreen));
    final provider = context.read<MultiplayerGameProvider>();

    // Manually trigger create room to set host status
    await provider.createRoom(settings: GameSettings(), playerName: "TestHost");
    // Only pump a few frames to handle async state change
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Simulate 2 players present and READY (Host + Guest) to satisfy minPlayers=2
    mockService.emitPresenceUpdate([
      {
        'id': 'p1',
        'name': 'TestHost',
        'isHuman': true,
        'connected': true,
        'ready': true,
        'clientId': 'c1',
        'avatarIndex': 0
      },
      {
        'id': 'p2',
        'name': 'Guest',
        'isHuman': true,
        'connected': true,
        'ready': true,
        'clientId': 'c2',
        'avatarIndex': 1
      }
    ]);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Now 'Lancer' should appear
    expect(find.text("Lancer"), findsOneWidget);

    // 2. Start Game
    await tester.tap(find.text("Lancer"));
    // Trigger tap
    await tester.pump();
    // Wait for dialog or logic
    await tester.pump(const Duration(milliseconds: 500));

    // Check for "Completer la table ?" dialog and dismiss it
    if (find.text("Completer la table ?").evaluate().isNotEmpty) {
      debugPrint("Dialog found, tapping Non");
      await tester.tap(find.text("Non"));
      await tester.pump(); // Tap effect
      await tester.pump(const Duration(milliseconds: 500)); // Close animation
    }

    // Logic is async; manually advance time to cover navigation delay
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // 3. Memorization Phase
    // Verify text
    if (find.text("C'EST BON !").evaluate().isEmpty) {
      // If not found yet, maybe pump more?
      await tester.pump(const Duration(seconds: 1));
    }

    // Select cards automatically
    final cards = find.byType(CardWidget);
    if (cards.evaluate().length >= 2) {
      await tester.tap(cards.at(0));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(cards.at(1));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text("C'EST BON !"));
    }
    // Update: Wait 4 seconds for revealed cards dialog + navigation
    await tester.pump(const Duration(seconds: 4));
    // Settle navigation (safe now as old screen is gone)
    await tester.pumpAndSettle();

    // 4. Game Screen
    // Emit 'playing' phase manually
    final playingState = mockService._createInitialState();
    playingState.phase = GamePhase.playing;
    mockService.emitGameState(playingState);

    // Wait for state update to reflect
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify Game Screen
    expect(find.byType(MultiplayerGameScreen), findsOneWidget);

    // 5. Draw Card
    // Locate the deck. Deck is inside CenterTable and is a CardWidget(isRevealed: false).
    final centerTable = find.byType(CenterTable);
    final deckFinder = find.descendant(
        of: centerTable,
        matching: find.byWidgetPredicate(
            (widget) => widget is CardWidget && !widget.isRevealed));

    if (deckFinder.evaluate().isEmpty) {
      // Should not happen if deck is present
      debugPrint("DECK NOT FOUND");
    } else {
      // Tap the deck
      await tester.tap(deckFinder.first);
    }

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // mockService.drawCard() update
    await tester.pump(const Duration(milliseconds: 100));

    // Verify drawn card UI
    // It says "TAP POUR AGRANDIR" by default
    expect(find.text("TAP POUR AGRANDIR"), findsOneWidget);

    // 6. End Game
    final endedState = mockService._createInitialState();
    endedState.phase = GamePhase.ended;
    mockService.emitGameState(endedState);

    // Use pumpAndSettle to allow full navigation from Game to Results
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // 7. Results Screen
    expect(find.text("RÉSULTATS"), findsOneWidget);
    expect(find.text("Rejouer"), findsOneWidget); // Host should see this

    // 8. Rematch
    await tester.tap(find.text("Rejouer"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Test complete
  });
}
