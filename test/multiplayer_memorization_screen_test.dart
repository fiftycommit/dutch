import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dutch_game/screens/multiplayer_memorization_screen.dart';
import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/card.dart'; // Import PlayingCard
import 'package:dutch_game/services/multiplayer_service.dart';

// Mock Provider
class MockMultiplayerGameProvider extends ChangeNotifier
    implements MultiplayerGameProvider {
  @override
  GameState? gameState;

  @override
  String? playerId;

  @override
  Stream<GameEvent> get events => const Stream.empty();

  @override
  void markReady() {}

  // Missing overrides to satisfy interface (returning dummies)
  @override
  get roomCode => "TEST";
  @override
  SocketConnectionState get connectionState => SocketConnectionState.connected;
  @override
  var roomClosedByHost = false;
  @override
  var wasKicked = false;
  @override
  get kickedMessage => null;
  @override
  get playerLeftNotification => false;
  @override
  get lastPlayerLeftName => null;
  @override
  get specialPowerNotification => false;
  @override
  get specialPowerByName => null;
  @override
  get specialPowerType => null;
  @override
  get pendingSwapNotification => null;
  @override
  get pendingJokerNotification => null;
  @override
  get pendingSpyNotification => null;
  @override
  get hostPlayerId => "p1";
  @override
  get isHost => true;
  @override
  get isProcessing => false;
  @override
  get playersInLobby => [];
  @override
  get roomSettings => null;
  @override
  get cumulativeScores => [];
  @override
  get roomGameMode => GameMode.quick;
  @override
  get roomStatus => 'playing';
  @override
  get chatMessages => [];
  @override
  get presenceById => {};
  @override
  get presenceByClientId => {};
  @override
  get presenceCheckActive => false;
  @override
  get presenceCheckReason => null;
  @override
  get presenceCheckDeadlineMs => 0;
  @override
  get errorMessage => null;
  @override
  get isConnecting => false;
  @override
  get isInLobby => false;
  @override
  get isPlaying => true;
  @override
  var shakingCardIndices = <int>{};
  @override
  get currentReactionTimeMs => 3000;
  @override
  get isPaused => false;
  @override
  get pausedByName => null;
  @override
  get lastSpiedCard => null;
  @override
  get spiedTargetName => null;
  @override
  get showSpiedCardDialog => false;
  @override
  get reactionTimeMs => 3000;
  @override
  get clientId => "c1";
  @override
  get isConnected => true;
  @override
  get isReady => false;
  @override
  get serverTimeOffsetMs => 0;
  @override
  get afkPlayerIds => {};
  @override
  isPlayerAfk(String id) => false;
  @override
  get readyHumanCount => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Spectator sees spectator screen', (WidgetTester tester) async {
    // Setup
    final provider = MockMultiplayerGameProvider();
    provider.playerId = 'spectator1';

    // Create GameState where 'spectator1' is a spectator
    provider.gameState = GameState(
      players: [
        Player(
            id: 'p1',
            name: 'Player 1',
            isHuman: true,
            position: 0,
            hand: [],
            knownCards: []),
        Player(
            id: 'spectator1',
            name: 'Spectator',
            isHuman: true,
            position: 1,
            hand: [],
            knownCards: [],
            isSpectator: true // Set via constructor
            ),
      ],
      deck: [],
      discardPile: [],
      currentPlayerIndex: 0,
      phase: GamePhase.setup,
      gameMode: GameMode.quick,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<MultiplayerGameProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: MultiplayerMemorizationScreen(),
        ),
      ),
    );

    // Assert
    expect(find.text('VOUS ÊTES SPECTATEUR'), findsOneWidget);
    expect(find.text('MÉMORISATION'), findsNothing);
  });

  testWidgets('Active player sees memorization screen',
      (WidgetTester tester) async {
    // Setup
    final provider = MockMultiplayerGameProvider();
    provider.playerId = 'p1';

    // Create GameState where 'p1' is active
    // Must give cards to hand to avoid range errors in rendering
    final card = PlayingCard(
        suit: 'hearts', value: 'A', points: 1, isSpecial: false, id: 'hA');

    provider.gameState = GameState(
      players: [
        Player(id: 'p1', name: 'Player 1', isHuman: true, position: 0)
          ..hand = [card, card] // 2 cards
          ..knownCards = [false, false],
      ],
      deck: [],
      discardPile: [],
      currentPlayerIndex: 0,
      phase: GamePhase.setup,
      gameMode: GameMode.quick,
    );

    // Set screen size to ensure layout works
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ChangeNotifierProvider<MultiplayerGameProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: MultiplayerMemorizationScreen(),
        ),
      ),
    );

    // Assert
    expect(find.text('MÉMORISATION'), findsOneWidget);
    expect(find.text('VOUS ÊTES SPECTATEUR'), findsNothing);
  });
}
