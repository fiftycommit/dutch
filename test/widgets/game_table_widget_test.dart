import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/widgets/game/game_table_widget.dart';
import 'package:dutch_game/widgets/game/card_widget.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';
import '../helpers/widget_test_helpers.dart';

void main() {
  group('GameTableCallbacks', () {
    test('can be created with all required callbacks', () {
      final callbacks = GameTableCallbacks(
        onDrawCard: () {},
        onDiscardDrawnCard: () {},
        onCallDutch: () {},
        onCardTap: (index) {},
        onShowDiscardPile: () {},
      );

      expect(callbacks.onDrawCard, isNotNull);
      expect(callbacks.onDiscardDrawnCard, isNotNull);
      expect(callbacks.onCallDutch, isNotNull);
      expect(callbacks.onCardTap, isNotNull);
      expect(callbacks.onShowDiscardPile, isNotNull);
    });

    test('onOpponentCardTap is optional', () {
      final callbacks = GameTableCallbacks(
        onDrawCard: () {},
        onDiscardDrawnCard: () {},
        onCallDutch: () {},
        onCardTap: (index) {},
        onShowDiscardPile: () {},
        onOpponentCardTap: null,
      );

      expect(callbacks.onOpponentCardTap, isNull);
    });

    test('callbacks are invoked correctly', () {
      int drawCount = 0;
      int discardCount = 0;
      int dutchCount = 0;
      List<int> cardTaps = [];

      final callbacks = GameTableCallbacks(
        onDrawCard: () => drawCount++,
        onDiscardDrawnCard: () => discardCount++,
        onCallDutch: () => dutchCount++,
        onCardTap: (index) => cardTaps.add(index),
        onShowDiscardPile: () {},
      );

      callbacks.onDrawCard();
      callbacks.onDiscardDrawnCard();
      callbacks.onCallDutch();
      callbacks.onCardTap(0);
      callbacks.onCardTap(2);

      expect(drawCount, 1);
      expect(discardCount, 1);
      expect(dutchCount, 1);
      expect(cardTaps, [0, 2]);
    });
  });

  group('MultiplayerConfig', () {
    test('solo config has default values', () {
      const config = MultiplayerConfig.solo;

      expect(config.playerId, isNull);
      expect(config.playerConnections, isEmpty);
      expect(config.playerAfkStatus, isEmpty);
      expect(config.turnStartTime, isNull);
      expect(config.turnDuration, isNull);
      expect(config.reactionTimeTotalMs, 0);
    });

    test('can be created with custom values', () {
      const config = MultiplayerConfig(
        playerId: 'player_123',
        playerConnections: {'player_123': true, 'player_456': false},
        playerAfkStatus: {'player_456': true},
        turnStartTime: 1000,
        turnDuration: 30000,
        reactionTimeTotalMs: 3000,
      );

      expect(config.playerId, 'player_123');
      expect(config.playerConnections['player_123'], true);
      expect(config.playerConnections['player_456'], false);
      expect(config.playerAfkStatus['player_456'], true);
      expect(config.turnStartTime, 1000);
      expect(config.turnDuration, 30000);
      expect(config.reactionTimeTotalMs, 3000);
    });
  });

  group('GameTableWidget Configuration', () {
    test('can create test game state', () {
      final gs = _createTestGameState();

      expect(gs.players.length, 2);
      expect(gs.players[0].isHuman, true);
      expect(gs.players[1].isHuman, false);
      expect(gs.deck.length, 40);
      expect(gs.discardPile.length, 1);
    });

    test('can create game state with multiple players', () {
      final gs = _createTestGameState(playerCount: 4);

      expect(gs.players.length, 4);
      expect(gs.players[0].isHuman, true);
      expect(gs.players[1].isHuman, false);
      expect(gs.players[2].isHuman, false);
      expect(gs.players[3].isHuman, false);
    });

    test('game state has proper phase', () {
      final gs = _createTestGameState();

      expect(gs.phase, GamePhase.playing);
      expect(gs.currentPlayerIndex, 0);
    });

    test('players have hands initialized', () {
      final gs = _createTestGameState();

      for (var player in gs.players) {
        expect(player.hand.length, 4);
        expect(player.knownCards.length, 4);
      }
    });
  });

  group('GameTableWidget - Layout Debug', () {
    late GameState gameState;
    late GameTableCallbacks callbacks;

    setUp(() {
      gameState = _createTestGameState();
      callbacks = GameTableCallbacks(
        onDrawCard: () {},
        onDiscardDrawnCard: () {},
        onCallDutch: () {},
        onCardTap: (index) {},
        onShowDiscardPile: () {},
      );
    });

    testWidgets('renders with minimal config - debug layout', (tester) async {
      await tester.pumpTestApp(
        GameTableWidget(
          gameState: gameState,
          callbacks: callbacks,
          isSpectator: false,
          isProcessing: false,
          multiplayerConfig: MultiplayerConfig.solo,
        ),
      );
      await tester.pump();

      expect(find.byType(GameTableWidget), findsOneWidget);
    });

    testWidgets('renders in playing phase', (tester) async {
      gameState.phase = GamePhase.playing;
      await tester.pumpTestApp(
        GameTableWidget(
          gameState: gameState,
          callbacks: callbacks,
          isSpectator: false,
          isProcessing: false,
          multiplayerConfig: MultiplayerConfig.solo,
        ),
      );
      await tester.pump();
      expect(find.byType(GameTableWidget), findsOneWidget);
    });

    testWidgets('renders as spectator', (tester) async {
      await tester.pumpTestApp(
        GameTableWidget(
          gameState: gameState,
          callbacks: callbacks,
          isSpectator: true,
          isProcessing: false,
          multiplayerConfig: MultiplayerConfig.solo,
        ),
      );
      await tester.pump();
      expect(find.byType(GameTableWidget), findsOneWidget);
    });

    testWidgets('renders when processing', (tester) async {
      await tester.pumpTestApp(
        GameTableWidget(
          gameState: gameState,
          callbacks: callbacks,
          isSpectator: false,
          isProcessing: true,
          multiplayerConfig: MultiplayerConfig.solo,
        ),
      );
      await tester.pump();
      expect(find.byType(GameTableWidget), findsOneWidget);
    });

    testWidgets('renders with drawn card', (tester) async {
      gameState.drawnCard = PlayingCard.create('hearts', 'A');
      await tester.pumpTestApp(
        GameTableWidget(
          gameState: gameState,
          callbacks: callbacks,
          isSpectator: false,
          isProcessing: false,
          multiplayerConfig: MultiplayerConfig.solo,
        ),
      );
      await tester.pump();
      expect(find.byType(GameTableWidget), findsOneWidget);
    });

    testWidgets('renders with multiplayer config', (tester) async {
      await tester.pumpTestApp(
        GameTableWidget(
          gameState: gameState,
          callbacks: callbacks,
          isSpectator: false,
          isProcessing: false,
          multiplayerConfig: const MultiplayerConfig(
            playerId: 'human',
            playerConnections: {'human': true, 'bot_1': true},
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(GameTableWidget), findsOneWidget);
    });

    testWidgets('renders in ended phase', (tester) async {
      gameState.phase = GamePhase.ended;
      await tester.pumpTestApp(
        GameTableWidget(
          gameState: gameState,
          callbacks: callbacks,
          isSpectator: false,
          isProcessing: false,
          multiplayerConfig: MultiplayerConfig.solo,
        ),
      );
      await tester.pump();
      expect(find.byType(GameTableWidget), findsOneWidget);
    });
  });

  group('CardWidget with SvgBuilder', () {
    testWidgets('renders with testSvgBuilder', (tester) async {
      await tester.pumpTestApp(
        CardWidget(
          card: PlayingCard.create('hearts', 'A'),
          size: CardSize.medium,
          isRevealed: true,
          svgBuilder: testSvgBuilder,
        ),
      );
      await tester.pump();

      expect(find.byType(CardWidget), findsOneWidget);
    });

    testWidgets('renders hidden card with testSvgBuilder', (tester) async {
      await tester.pumpTestApp(
        CardWidget(
          card: PlayingCard.create('hearts', 'A'),
          size: CardSize.medium,
          isRevealed: false,
          svgBuilder: testSvgBuilder,
        ),
      );
      await tester.pump();

      expect(find.byType(CardWidget), findsOneWidget);
    });

    testWidgets('renders null card with testSvgBuilder', (tester) async {
      await tester.pumpTestApp(
        CardWidget(
          card: null,
          size: CardSize.medium,
          isRevealed: true,
          svgBuilder: testSvgBuilder,
        ),
      );
      await tester.pump();

      expect(find.byType(CardWidget), findsOneWidget);
    });

    testWidgets('onTap callback works', (tester) async {
      int tapCount = 0;

      await tester.pumpTestApp(
        CardWidget(
          card: PlayingCard.create('hearts', 'A'),
          size: CardSize.medium,
          isRevealed: true,
          svgBuilder: testSvgBuilder,
          onTap: () => tapCount++,
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(CardWidget));
      await tester.pump();

      expect(tapCount, 1);
    });

    testWidgets('all card sizes render correctly', (tester) async {
      for (final size in CardSize.values) {
        await tester.pumpTestApp(
          CardWidget(
            card: PlayingCard.create('hearts', 'A'),
            size: size,
            isRevealed: true,
            svgBuilder: testSvgBuilder,
          ),
        );
        await tester.pump();

        expect(find.byType(CardWidget), findsOneWidget);
      }
    });
  });
}

GameState _createTestGameState({int playerCount = 2}) {
  final players = <Player>[];

  players.add(Player(id: 'human', name: 'Human', isHuman: true, position: 0));

  for (int i = 1; i < playerCount; i++) {
    players
        .add(Player(id: 'bot_$i', name: 'Bot $i', isHuman: false, position: i));
  }

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
