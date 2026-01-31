import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/widgets/game/game_layout_mixin.dart';
import 'package:dutch_game/widgets/game/card_widget.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';

/// Helper class to test GameLayoutMixin methods
class TestableLayoutWidget extends StatefulWidget {
  const TestableLayoutWidget({super.key});

  @override
  State<TestableLayoutWidget> createState() => TestableLayoutWidgetState();
}

class TestableLayoutWidgetState extends State<TestableLayoutWidget>
    with GameLayoutMixin<TestableLayoutWidget> {
  @override
  Widget build(BuildContext context) => const SizedBox();

  // Expose mixin methods for testing
  Size testCardVisualSize(BuildContext ctx, CardSize size) =>
      cardVisualSize(ctx, size);

  PlayerAreaLayoutData testComputePlayerAreaLayout({
    required BuildContext ctx,
    required int handLength,
    required CardSize cardSize,
    required bool isCompactMode,
  }) =>
      computePlayerAreaLayout(
        context: ctx,
        handLength: handLength,
        cardSize: cardSize,
        isCompactMode: isCompactMode,
      );

  double testEstimateCenterMinHeight(
          BuildContext ctx, GameState gs, bool isCompactMode) =>
      estimateCenterMinHeight(ctx, gs, isCompactMode);

  bool testIsCompactMode(BuildContext ctx) => isCompactModeFor(ctx);
  bool testIsMediumMode(BuildContext ctx) => isMediumModeFor(ctx);

  ActionButtonLayout testActionButtonLayout(
          BuildContext ctx, bool isCompactMode, Size cardMetrics) =>
      actionButtonLayout(ctx, isCompactMode, cardMetrics);
}

void main() {
  group('GameTableMetrics.compute', () {
    test('computes valid metrics for standard constraints', () {
      final metrics = GameTableMetrics.compute(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        sideBandContentWidth: 80,
        outerGap: 10,
        centerGapX: 5,
        botBlockHeight: 100,
        playerAreaHeight: 120,
        centerMinHeight: 150,
        botCardHeight: 80,
        playerCardHeight: 100,
        isCompactMode: false,
        isMediumMode: false,
        isDrawnCardVisible: true,
      );

      expect(metrics.sideBandWidth, greaterThan(0));
      expect(metrics.topBandHeight, greaterThan(0));
      expect(metrics.bottomBandHeight, greaterThan(0));
      expect(metrics.centerWidth, greaterThan(0));
      expect(metrics.centerHeight, greaterThanOrEqualTo(0));
      expect(metrics.buttonMargin, 24.0); // Not compact, not medium
    });

    test('computes compact mode button margin', () {
      final metrics = GameTableMetrics.compute(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 300),
        sideBandContentWidth: 60,
        outerGap: 5,
        centerGapX: 3,
        botBlockHeight: 60,
        playerAreaHeight: 80,
        centerMinHeight: 80,
        botCardHeight: 50,
        playerCardHeight: 60,
        isCompactMode: true,
        isMediumMode: false,
        isDrawnCardVisible: false,
      );

      expect(metrics.buttonMargin, 2.0); // Compact mode
    });

    test('computes medium mode button margin', () {
      final metrics = GameTableMetrics.compute(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        sideBandContentWidth: 70,
        outerGap: 8,
        centerGapX: 4,
        botBlockHeight: 80,
        playerAreaHeight: 100,
        centerMinHeight: 120,
        botCardHeight: 70,
        playerCardHeight: 80,
        isCompactMode: false,
        isMediumMode: true,
        isDrawnCardVisible: true,
      );

      expect(metrics.buttonMargin, 12.0); // Medium mode
    });

    test('centerShiftFraction is 0 when drawnCard not visible', () {
      final metrics = GameTableMetrics.compute(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        sideBandContentWidth: 80,
        outerGap: 10,
        centerGapX: 5,
        botBlockHeight: 100,
        playerAreaHeight: 120,
        centerMinHeight: 150,
        botCardHeight: 80,
        playerCardHeight: 100,
        isCompactMode: false,
        isMediumMode: false,
        isDrawnCardVisible: false,
      );

      expect(metrics.centerShiftFraction, 0.0);
    });

    test('handles zero dimensions gracefully', () {
      final metrics = GameTableMetrics.compute(
        constraints: const BoxConstraints(maxWidth: 100, maxHeight: 100),
        sideBandContentWidth: 50,
        outerGap: 5,
        centerGapX: 5,
        botBlockHeight: 50,
        playerAreaHeight: 50,
        centerMinHeight: 50,
        botCardHeight: 30,
        playerCardHeight: 30,
        isCompactMode: true,
        isMediumMode: false,
        isDrawnCardVisible: true,
      );

      expect(metrics.centerWidth, greaterThanOrEqualTo(0));
      expect(metrics.centerHeight, greaterThanOrEqualTo(0));
    });

    test('sideBandWidth includes all gaps', () {
      final metrics = GameTableMetrics.compute(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        sideBandContentWidth: 80,
        outerGap: 10,
        centerGapX: 5,
        botBlockHeight: 100,
        playerAreaHeight: 120,
        centerMinHeight: 150,
        botCardHeight: 80,
        playerCardHeight: 100,
        isCompactMode: false,
        isMediumMode: false,
        isDrawnCardVisible: true,
      );

      // sideBandWidth = sideBandContentWidth + outerGap + centerGapX
      expect(metrics.sideBandWidth, 80 + 10 + 5);
    });

    test('centerShiftFraction is clamped between -1 and 1', () {
      final metrics = GameTableMetrics.compute(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 600),
        sideBandContentWidth: 80,
        outerGap: 10,
        centerGapX: 5,
        botBlockHeight: 100,
        playerAreaHeight: 120,
        centerMinHeight: 150,
        botCardHeight: 200, // Large difference
        playerCardHeight: 50,
        isCompactMode: false,
        isMediumMode: false,
        isDrawnCardVisible: true,
      );

      expect(metrics.centerShiftFraction, inInclusiveRange(-1.0, 1.0));
    });
  });

  group('PlayerAreaLayoutData', () {
    test('constructor stores all values', () {
      const layout = PlayerAreaLayoutData(
        sideButtonWidth: 100,
        sideGap: 10,
        actionButtonHeight: 50,
        actionButtonMargin: 8,
        handMaxWidth: 300,
        cardMetrics: Size(50, 70),
      );

      expect(layout.sideButtonWidth, 100);
      expect(layout.sideGap, 10);
      expect(layout.actionButtonHeight, 50);
      expect(layout.actionButtonMargin, 8);
      expect(layout.handMaxWidth, 300);
      expect(layout.cardMetrics, const Size(50, 70));
    });
  });

  group('ActionButtonLayout', () {
    test('computes columnHeight from height and margin', () {
      final layout = ActionButtonLayout(
        width: 100,
        height: 50,
        margin: 10,
      );

      expect(layout.width, 100);
      expect(layout.height, 50);
      expect(layout.margin, 10);
      expect(layout.columnHeight, (50 * 2) + 10); // 110
    });
  });

  group('GameLayoutMixin methods', () {
    late TestableLayoutWidgetState layoutState;

    Future<void> pumpLayout(WidgetTester tester, Size size) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: size),
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return const TestableLayoutWidget();
              },
            ),
          ),
        ),
      );
      layoutState = tester.state(find.byType(TestableLayoutWidget));
    }

    testWidgets('cardVisualSize returns valid sizes for all CardSize values',
        (tester) async {
      await pumpLayout(tester, const Size(800, 600));

      final context = tester.element(find.byType(TestableLayoutWidget));

      for (final cardSize in CardSize.values) {
        final size = layoutState.testCardVisualSize(context, cardSize);
        expect(size.width, greaterThan(0));
        expect(size.height, greaterThan(0));
        expect(size.height, greaterThan(size.width)); // Cards are taller
      }
    });

    testWidgets('cardVisualSize maintains aspect ratio', (tester) async {
      await pumpLayout(tester, const Size(800, 600));

      final context = tester.element(find.byType(TestableLayoutWidget));
      final size = layoutState.testCardVisualSize(context, CardSize.medium);

      // Aspect ratio should be approximately 7/5 = 1.4
      final ratio = size.height / size.width;
      expect(ratio, closeTo(1.4, 0.1));
    });

    testWidgets('isCompactMode returns true for small screens', (tester) async {
      await pumpLayout(tester, const Size(600, 350)); // height < 400

      final context = tester.element(find.byType(TestableLayoutWidget));
      expect(layoutState.testIsCompactMode(context), isTrue);
    });

    testWidgets('isCompactMode returns false for large screens',
        (tester) async {
      await pumpLayout(tester, const Size(1200, 800));

      final context = tester.element(find.byType(TestableLayoutWidget));
      expect(layoutState.testIsCompactMode(context), isFalse);
    });

    testWidgets('isMediumMode returns true for medium screens', (tester) async {
      await pumpLayout(tester, const Size(900, 550)); // Between compact and large

      final context = tester.element(find.byType(TestableLayoutWidget));
      expect(layoutState.testIsMediumMode(context), isTrue);
    });

    testWidgets('computePlayerAreaLayout returns valid data', (tester) async {
      await pumpLayout(tester, const Size(800, 600));

      final context = tester.element(find.byType(TestableLayoutWidget));
      final layout = layoutState.testComputePlayerAreaLayout(
        ctx: context,
        handLength: 4,
        cardSize: CardSize.medium,
        isCompactMode: false,
      );

      expect(layout.sideButtonWidth, greaterThan(0));
      expect(layout.sideGap, greaterThan(0));
      expect(layout.actionButtonHeight, greaterThan(0));
      expect(layout.handMaxWidth, greaterThan(0));
      expect(layout.cardMetrics.width, greaterThan(0));
      expect(layout.cardMetrics.height, greaterThan(0));
    });

    testWidgets('computePlayerAreaLayout compact mode has smaller buttons',
        (tester) async {
      await pumpLayout(tester, const Size(800, 600));

      final context = tester.element(find.byType(TestableLayoutWidget));

      final normalLayout = layoutState.testComputePlayerAreaLayout(
        ctx: context,
        handLength: 4,
        cardSize: CardSize.medium,
        isCompactMode: false,
      );

      final compactLayout = layoutState.testComputePlayerAreaLayout(
        ctx: context,
        handLength: 4,
        cardSize: CardSize.small,
        isCompactMode: true,
      );

      expect(compactLayout.actionButtonHeight,
          lessThanOrEqualTo(normalLayout.actionButtonHeight));
    });

    testWidgets('estimateCenterMinHeight returns positive value',
        (tester) async {
      await pumpLayout(tester, const Size(800, 600));

      final context = tester.element(find.byType(TestableLayoutWidget));
      final gs = _createTestGameState();

      final height = layoutState.testEstimateCenterMinHeight(context, gs, false);
      expect(height, greaterThan(0));

      final compactHeight =
          layoutState.testEstimateCenterMinHeight(context, gs, true);
      expect(compactHeight, greaterThan(0));
      expect(compactHeight, lessThan(height)); // Compact is smaller
    });

    testWidgets('actionButtonLayout clamps values correctly', (tester) async {
      await pumpLayout(tester, const Size(800, 600));

      final context = tester.element(find.byType(TestableLayoutWidget));

      final normalLayout = layoutState.testActionButtonLayout(
        context,
        false,
        const Size(50, 70),
      );

      expect(normalLayout.width, inInclusiveRange(110.0, 220.0));
      expect(normalLayout.height, inInclusiveRange(56.0, 92.0));

      final compactLayout = layoutState.testActionButtonLayout(
        context,
        true,
        const Size(40, 56),
      );

      expect(compactLayout.width, inInclusiveRange(72.0, 120.0));
      expect(compactLayout.height, inInclusiveRange(34.0, 52.0));
    });
  });
}

GameState _createTestGameState() {
  final players = [
    Player(id: 'human', name: 'Human', isHuman: true, position: 0),
    Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
  ];

  for (var player in players) {
    player.hand = [
      PlayingCard.create('hearts', 'A'),
      PlayingCard.create('diamonds', '2'),
    ];
    player.knownCards = List.filled(2, false, growable: true);
  }

  return GameState(
    players: players,
    deck: GameState.createFullDeck().sublist(0, 40),
    discardPile: [PlayingCard.create('hearts', '5')],
    currentPlayerIndex: 0,
    phase: GamePhase.playing,
  );
}
