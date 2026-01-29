import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/card.dart';

void main() {
  group('PlayingCard', () {
    group('create factory', () {
      test('creates numeric card with correct points', () {
        final card = PlayingCard.create('hearts', '5');
        expect(card.suit, 'hearts');
        expect(card.value, '5');
        expect(card.points, 5);
        expect(card.isSpecial, false);
        expect(card.id, '5_hearts');
      });

      test('creates Ace with 1 point', () {
        final card = PlayingCard.create('spades', 'A');
        expect(card.points, 1);
        expect(card.isSpecial, false);
      });

      test('creates Jack (Valet) with 11 points and isSpecial=true', () {
        final card = PlayingCard.create('clubs', 'V');
        expect(card.points, 11);
        expect(card.isSpecial, true);
      });

      test('creates Queen (Dame) with 12 points', () {
        final card = PlayingCard.create('diamonds', 'D');
        expect(card.points, 12);
        expect(card.isSpecial, false);
      });

      test('creates red King with 0 points', () {
        final cardHearts = PlayingCard.create('hearts', 'R');
        final cardDiamonds = PlayingCard.create('diamonds', 'R');
        expect(cardHearts.points, 0);
        expect(cardDiamonds.points, 0);
      });

      test('creates black King with 13 points', () {
        final cardSpades = PlayingCard.create('spades', 'R');
        final cardClubs = PlayingCard.create('clubs', 'R');
        expect(cardSpades.points, 13);
        expect(cardClubs.points, 13);
      });

      test('creates Joker with 0 points and isSpecial=true', () {
        final card = PlayingCard.create('joker', 'JOKER');
        expect(card.points, 0);
        expect(card.isSpecial, true);
      });

      test('creates 7 card as special', () {
        final card = PlayingCard.create('hearts', '7');
        expect(card.points, 7);
        expect(card.isSpecial, true);
      });

      test('creates 10 card as special', () {
        final card = PlayingCard.create('spades', '10');
        expect(card.points, 10);
        expect(card.isSpecial, true);
      });
    });

    group('hidden factory', () {
      test('creates hidden card', () {
        final card = PlayingCard.hidden();
        expect(card.isHidden, true);
        expect(card.suit, 'hidden');
        expect(card.value, 'hidden');
        expect(card.points, 0);
      });
    });

    group('matchValue', () {
      test('returns value for regular cards', () {
        final card = PlayingCard.create('hearts', '5');
        expect(card.matchValue, '5');
      });

      test('returns R for all Kings', () {
        final redKing = PlayingCard.create('hearts', 'R');
        final blackKing = PlayingCard.create('spades', 'R');
        expect(redKing.matchValue, 'R');
        expect(blackKing.matchValue, 'R');
      });

      test('returns JOKER for jokers', () {
        final joker = PlayingCard.create('joker', 'JOKER');
        expect(joker.matchValue, 'JOKER');
      });
    });

    group('matches', () {
      test('returns true for same value cards', () {
        final card1 = PlayingCard.create('hearts', '5');
        final card2 = PlayingCard.create('spades', '5');
        expect(card1.matches(card2), true);
      });

      test('returns false for different value cards', () {
        final card1 = PlayingCard.create('hearts', '5');
        final card2 = PlayingCard.create('hearts', '6');
        expect(card1.matches(card2), false);
      });

      test('matches Kings regardless of color', () {
        final redKing = PlayingCard.create('hearts', 'R');
        final blackKing = PlayingCard.create('spades', 'R');
        expect(redKing.matches(blackKing), true);
      });

      test('matches Jokers', () {
        final joker1 = PlayingCard.create('joker', 'JOKER');
        final joker2 = PlayingCard.create('joker', 'JOKER');
        expect(joker1.matches(joker2), true);
      });
    });

    group('imagePath', () {
      test('returns back image for hidden card', () {
        final card = PlayingCard.hidden();
        expect(card.imagePath, 'assets/images/cards/back.svg');
      });

      test('returns correct path for numeric card', () {
        final card = PlayingCard.create('hearts', '5');
        expect(card.imagePath, 'assets/images/cards/05-coeur.svg');
      });

      test('returns correct path for Ace', () {
        final card = PlayingCard.create('spades', 'A');
        expect(card.imagePath, 'assets/images/cards/01-pique.svg');
      });

      test('returns correct path for face cards', () {
        final jack = PlayingCard.create('clubs', 'V');
        final queen = PlayingCard.create('diamonds', 'D');
        final king = PlayingCard.create('hearts', 'R');

        expect(jack.imagePath, 'assets/images/cards/V-trefle.svg');
        expect(queen.imagePath, 'assets/images/cards/D-carreau.svg');
        expect(king.imagePath, 'assets/images/cards/R-coeur.svg');
      });

      test('returns correct path for joker', () {
        final redJoker = PlayingCard.create('hearts', 'JOKER');
        final blackJoker = PlayingCard.create('spades', 'JOKER');

        expect(redJoker.imagePath, 'assets/images/cards/joker-rouge.svg');
        expect(blackJoker.imagePath, 'assets/images/cards/joker-noir.svg');
      });
    });

    group('displayName', () {
      test('returns correct name for red King', () {
        final card = PlayingCard.create('hearts', 'R');
        expect(card.displayName.trim(), 'Roi Rouge');
      });

      test('returns correct name for black King', () {
        final card = PlayingCard.create('spades', 'R');
        expect(card.displayName.trim(), 'Roi Noir');
      });

      test('returns correct name for Joker', () {
        final card = PlayingCard.create('joker', 'JOKER');
        expect(card.displayName.trim(), 'Joker');
      });
    });

    group('JSON serialization', () {
      test('serializes and deserializes regular card', () {
        final original = PlayingCard.create('hearts', '7');
        final json = original.toJson();
        final restored = PlayingCard.fromJson(json);

        expect(restored.suit, original.suit);
        expect(restored.value, original.value);
        expect(restored.points, original.points);
        expect(restored.isSpecial, original.isSpecial);
        expect(restored.id, original.id);
      });

      test('serializes hidden card', () {
        final hidden = PlayingCard.hidden();
        final json = hidden.toJson();

        expect(json['hidden'], true);
      });

      test('deserializes hidden card', () {
        final json = {'hidden': true};
        final card = PlayingCard.fromJson(json);

        expect(card.isHidden, true);
      });
    });
  });
}
