import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/widgets/game/player_hand.dart';
import 'package:dutch_game/widgets/game/card_widget.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';

void main() {
  group('HandMetrics', () {
    test('can be instantiated with all required values', () {
      const metrics = HandMetrics(
        cardWidth: 50.0,
        cardHeight: 70.0,
        overlap: 15.0,
        totalWidth: 155.0,
      );

      expect(metrics.cardWidth, 50.0);
      expect(metrics.cardHeight, 70.0);
      expect(metrics.overlap, 15.0);
      expect(metrics.totalWidth, 155.0);
    });

    test('is immutable', () {
      const metrics = HandMetrics(
        cardWidth: 50.0,
        cardHeight: 70.0,
        overlap: 15.0,
        totalWidth: 155.0,
      );

      // Values cannot be changed after construction
      expect(metrics.cardWidth, 50.0);
    });
  });

  group('PlayerHandWidget.overlapFactor', () {
    test('returns correct factor for tiny cards', () {
      expect(PlayerHandWidget.overlapFactor(CardSize.tiny), 0.3);
    });

    test('returns correct factor for small cards', () {
      expect(PlayerHandWidget.overlapFactor(CardSize.small), 0.28);
    });

    test('returns correct factor for medium cards', () {
      expect(PlayerHandWidget.overlapFactor(CardSize.medium), 0.26);
    });

    test('returns correct factor for large cards', () {
      expect(PlayerHandWidget.overlapFactor(CardSize.large), 0.24);
    });

    test('returns correct factor for drawn cards', () {
      expect(PlayerHandWidget.overlapFactor(CardSize.drawn), 0.26);
    });

    test('smaller cards have larger overlap factor', () {
      // Tiny cards overlap more (relatively) than large cards
      expect(
        PlayerHandWidget.overlapFactor(CardSize.tiny),
        greaterThan(PlayerHandWidget.overlapFactor(CardSize.large)),
      );
    });

    test('overlap factors are between 0 and 1', () {
      for (final size in CardSize.values) {
        final factor = PlayerHandWidget.overlapFactor(size);
        expect(factor, greaterThan(0));
        expect(factor, lessThan(1));
      }
    });
  });

  group('PlayerHandWidget', () {
    late Player humanPlayer;
    late Player botPlayer;

    setUp(() {
      humanPlayer = Player(
        id: 'human',
        name: 'Human',
        isHuman: true,
        position: 0,
      );
      humanPlayer.hand = [
        PlayingCard.create('hearts', 'A'),
        PlayingCard.create('diamonds', '2'),
        PlayingCard.create('clubs', '3'),
        PlayingCard.create('spades', '4'),
      ];
      humanPlayer.knownCards = [true, true, false, false];

      botPlayer = Player(
        id: 'bot_1',
        name: 'Bot 1',
        isHuman: false,
        position: 1,
      );
      botPlayer.hand = [
        PlayingCard.create('hearts', '5'),
        PlayingCard.create('diamonds', '6'),
        PlayingCard.create('clubs', '7'),
        PlayingCard.create('spades', '8'),
      ];
      botPlayer.knownCards = [false, false, false, false];
    });

    test('can be instantiated with required parameters', () {
      final widget = PlayerHandWidget(
        player: humanPlayer,
        isHuman: true,
        isActive: true,
      );

      expect(widget.player, humanPlayer);
      expect(widget.isHuman, true);
      expect(widget.isActive, true);
      expect(widget.onCardTap, isNull);
      expect(widget.selectedIndices, isNull);
      expect(widget.cardSize, CardSize.medium); // default
      expect(widget.overlapCards, true); // default
    });

    test('can be instantiated with all optional parameters', () {
      final widget = PlayerHandWidget(
        player: humanPlayer,
        isHuman: true,
        isActive: true,
        onCardTap: (index) {},
        selectedIndices: [0, 2],
        cardSize: CardSize.large,
        overlapCards: false,
      );

      expect(widget.onCardTap, isNotNull);
      expect(widget.selectedIndices, [0, 2]);
      expect(widget.cardSize, CardSize.large);
      expect(widget.overlapCards, false);
    });

    test('bot player has isHuman false', () {
      final widget = PlayerHandWidget(
        player: botPlayer,
        isHuman: false,
        isActive: false,
      );

      expect(widget.isHuman, false);
    });

    test('isActive affects interactivity', () {
      final activeWidget = PlayerHandWidget(
        player: humanPlayer,
        isHuman: true,
        isActive: true,
      );

      final inactiveWidget = PlayerHandWidget(
        player: humanPlayer,
        isHuman: true,
        isActive: false,
      );

      expect(activeWidget.isActive, true);
      expect(inactiveWidget.isActive, false);
    });

    test('selectedIndices can be empty', () {
      final widget = PlayerHandWidget(
        player: humanPlayer,
        isHuman: true,
        isActive: true,
        selectedIndices: [],
      );

      expect(widget.selectedIndices, isEmpty);
    });

    test('works with different card sizes', () {
      for (final size in CardSize.values) {
        final widget = PlayerHandWidget(
          player: humanPlayer,
          isHuman: true,
          isActive: true,
          cardSize: size,
        );

        expect(widget.cardSize, size);
      }
    });

    test('works with empty hand', () {
      final emptyPlayer = Player(
        id: 'empty',
        name: 'Empty',
        isHuman: true,
        position: 0,
      );
      emptyPlayer.hand = [];
      emptyPlayer.knownCards = [];

      final widget = PlayerHandWidget(
        player: emptyPlayer,
        isHuman: true,
        isActive: true,
      );

      expect(widget.player.hand, isEmpty);
    });

    test('works with single card hand', () {
      final singleCardPlayer = Player(
        id: 'single',
        name: 'Single',
        isHuman: true,
        position: 0,
      );
      singleCardPlayer.hand = [PlayingCard.create('hearts', 'A')];
      singleCardPlayer.knownCards = [true];

      final widget = PlayerHandWidget(
        player: singleCardPlayer,
        isHuman: true,
        isActive: true,
      );

      expect(widget.player.hand.length, 1);
    });

    test('works with many cards', () {
      final manyCardsPlayer = Player(
        id: 'many',
        name: 'Many',
        isHuman: true,
        position: 0,
      );
      manyCardsPlayer.hand = List.generate(
        10,
        (i) => PlayingCard.create('hearts', '${i + 1}'),
      );
      manyCardsPlayer.knownCards = List.filled(10, false);

      final widget = PlayerHandWidget(
        player: manyCardsPlayer,
        isHuman: true,
        isActive: true,
      );

      expect(widget.player.hand.length, 10);
    });
  });
}
