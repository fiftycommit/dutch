import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/widgets/game/card_widget.dart';
import 'package:dutch_game/models/playing_card.dart';

void main() {
  group('CardSize', () {
    test('has all expected values', () {
      expect(CardSize.values, contains(CardSize.tiny));
      expect(CardSize.values, contains(CardSize.small));
      expect(CardSize.values, contains(CardSize.medium));
      expect(CardSize.values, contains(CardSize.large));
      expect(CardSize.values, contains(CardSize.drawn));
    });

    test('has 5 sizes', () {
      expect(CardSize.values.length, 5);
    });
  });

  group('CardWidget', () {
    test('can be instantiated with required parameters', () {
      final card = PlayingCard.create('hearts', 'A');
      
      final widget = CardWidget(
        card: card,
        size: CardSize.medium,
        isRevealed: true,
      );

      expect(widget.card, card);
      expect(widget.size, CardSize.medium);
      expect(widget.isRevealed, true);
      expect(widget.onTap, isNull);
    });

    test('can be instantiated with null card', () {
      final widget = CardWidget(
        card: null,
        size: CardSize.small,
        isRevealed: false,
      );

      expect(widget.card, isNull);
    });

    test('can be instantiated with onTap callback', () {
      int tapCount = 0;
      
      final widget = CardWidget(
        card: PlayingCard.create('hearts', 'A'),
        size: CardSize.medium,
        isRevealed: true,
        onTap: () => tapCount++,
      );

      expect(widget.onTap, isNotNull);
    });

    test('isRevealed affects card display logic', () {
      final card = PlayingCard.create('hearts', 'A');
      
      final revealedWidget = CardWidget(
        card: card,
        size: CardSize.medium,
        isRevealed: true,
      );

      final hiddenWidget = CardWidget(
        card: card,
        size: CardSize.medium,
        isRevealed: false,
      );

      expect(revealedWidget.isRevealed, true);
      expect(hiddenWidget.isRevealed, false);
    });

    group('Size configurations', () {
      test('tiny size is smallest', () {
        expect(CardSize.tiny.index, lessThan(CardSize.small.index));
      });

      test('large size is bigger than medium', () {
        expect(CardSize.large.index, greaterThan(CardSize.medium.index));
      });

      test('drawn size exists for drawn card display', () {
        final widget = CardWidget(
          card: PlayingCard.create('hearts', 'A'),
          size: CardSize.drawn,
          isRevealed: true,
        );

        expect(widget.size, CardSize.drawn);
      });
    });

    group('Card types', () {
      test('works with all suits', () {
        for (final suit in ['hearts', 'diamonds', 'clubs', 'spades']) {
          final card = PlayingCard.create(suit, 'A');
          final widget = CardWidget(
            card: card,
            size: CardSize.medium,
            isRevealed: true,
          );
          expect(widget.card!.suit, suit);
        }
      });

      test('works with all values', () {
        for (final value in ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'V', 'D', 'R']) {
          final card = PlayingCard.create('hearts', value);
          final widget = CardWidget(
            card: card,
            size: CardSize.medium,
            isRevealed: true,
          );
          expect(widget.card!.value, value);
        }
      });

      test('works with joker', () {
        final card = PlayingCard.create('hearts', 'JOKER');
        final widget = CardWidget(
          card: card,
          size: CardSize.medium,
          isRevealed: true,
        );
        expect(widget.card!.value, 'JOKER');
      });
    });
  });
}
