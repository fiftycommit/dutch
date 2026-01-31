import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/playing_card.dart';

void main() {
  group('PlayingCard - Creation', () {
    test('create sets correct properties', () {
      final card = PlayingCard.create('hearts', 'A');
      
      expect(card.suit, 'hearts');
      expect(card.value, 'A');
      expect(card.points, 1);
      expect(card.isSpecial, false);
      expect(card.id, 'A_hearts');
    });

    test('create generates unique id', () {
      final card1 = PlayingCard.create('hearts', 'A');
      final card2 = PlayingCard.create('diamonds', 'A');
      
      expect(card1.id, isNot(card2.id));
    });

    test('hidden card has correct properties', () {
      final card = PlayingCard.hidden();
      
      expect(card.isHidden, true);
      expect(card.suit, 'hidden');
      expect(card.value, 'hidden');
    });
  });

  group('PlayingCard - Points Calculation', () {
    test('Ace is 1 point', () {
      final card = PlayingCard.create('hearts', 'A');
      expect(card.points, 1);
    });

    test('number cards have face value points', () {
      for (int i = 2; i <= 10; i++) {
        final card = PlayingCard.create('hearts', '$i');
        expect(card.points, i);
      }
    });

    test('Valet (Jack) is 11 points', () {
      final card = PlayingCard.create('hearts', 'V');
      expect(card.points, 11);
    });

    test('Dame (Queen) is 12 points', () {
      final card = PlayingCard.create('hearts', 'D');
      expect(card.points, 12);
    });

    test('Red King is 0 points', () {
      final heartsKing = PlayingCard.create('hearts', 'R');
      final diamondsKing = PlayingCard.create('diamonds', 'R');
      
      expect(heartsKing.points, 0);
      expect(diamondsKing.points, 0);
    });

    test('Black King is 13 points', () {
      final clubsKing = PlayingCard.create('clubs', 'R');
      final spadesKing = PlayingCard.create('spades', 'R');
      
      expect(clubsKing.points, 13);
      expect(spadesKing.points, 13);
    });

    test('Joker is 0 points', () {
      final joker = PlayingCard.create('joker', 'JOKER');
      expect(joker.points, 0);
    });
  });

  group('PlayingCard - Special Cards', () {
    test('7 is special', () {
      final card = PlayingCard.create('hearts', '7');
      expect(card.isSpecial, true);
    });

    test('10 is special', () {
      final card = PlayingCard.create('hearts', '10');
      expect(card.isSpecial, true);
    });

    test('Valet is special', () {
      final card = PlayingCard.create('hearts', 'V');
      expect(card.isSpecial, true);
    });

    test('Joker is special', () {
      final card = PlayingCard.create('joker', 'JOKER');
      expect(card.isSpecial, true);
    });

    test('non-special cards are not special', () {
      final nonSpecialValues = ['A', '2', '3', '4', '5', '6', '8', '9', 'D', 'R'];
      for (var value in nonSpecialValues) {
        final card = PlayingCard.create('hearts', value);
        expect(card.isSpecial, false, reason: '$value should not be special');
      }
    });
  });

  group('PlayingCard - Matching', () {
    test('same value cards match', () {
      final card1 = PlayingCard.create('hearts', '5');
      final card2 = PlayingCard.create('diamonds', '5');
      
      expect(card1.matches(card2), true);
    });

    test('different value cards do not match', () {
      final card1 = PlayingCard.create('hearts', '5');
      final card2 = PlayingCard.create('hearts', '6');
      
      expect(card1.matches(card2), false);
    });

    test('all Kings match each other', () {
      final redKing = PlayingCard.create('hearts', 'R');
      final blackKing = PlayingCard.create('spades', 'R');
      
      expect(redKing.matches(blackKing), true);
    });

    test('all Jokers match each other', () {
      final joker1 = PlayingCard.create('joker', 'JOKER');
      final joker2 = PlayingCard.create('joker', 'JOKER');
      
      expect(joker1.matches(joker2), true);
    });

    test('matchValue returns correct value', () {
      expect(PlayingCard.create('hearts', '5').matchValue, '5');
      expect(PlayingCard.create('hearts', 'R').matchValue, 'R');
      expect(PlayingCard.create('joker', 'JOKER').matchValue, 'JOKER');
    });
  });

  group('PlayingCard - Display', () {
    test('displayName for number cards', () {
      final card = PlayingCard.create('hearts', '5');
      expect(card.displayName, contains('5'));
    });

    test('displayName for Ace', () {
      final card = PlayingCard.create('hearts', 'A');
      expect(card.displayName, contains('A'));
    });

    test('displayName for face cards', () {
      expect(PlayingCard.create('hearts', 'V').displayName, contains('Valet'));
      expect(PlayingCard.create('hearts', 'D').displayName, contains('Dame'));
    });

    test('displayName for Kings shows color', () {
      final redKing = PlayingCard.create('hearts', 'R');
      final blackKing = PlayingCard.create('spades', 'R');
      
      expect(redKing.displayName, contains('Rouge'));
      expect(blackKing.displayName, contains('Noir'));
    });

    test('displayName for Joker', () {
      final joker = PlayingCard.create('joker', 'JOKER');
      expect(joker.displayName, contains('Joker'));
    });
  });

  group('PlayingCard - Image Path', () {
    test('imagePath for regular cards', () {
      final card = PlayingCard.create('hearts', '5');
      expect(card.imagePath, contains('05-coeur'));
    });

    test('imagePath for Ace', () {
      final card = PlayingCard.create('hearts', 'A');
      expect(card.imagePath, contains('01-coeur'));
    });

    test('imagePath for face cards', () {
      expect(PlayingCard.create('hearts', 'V').imagePath, contains('V-coeur'));
      expect(PlayingCard.create('hearts', 'D').imagePath, contains('D-coeur'));
      expect(PlayingCard.create('hearts', 'R').imagePath, contains('R-coeur'));
    });

    test('imagePath for different suits', () {
      expect(PlayingCard.create('hearts', '5').imagePath, contains('coeur'));
      expect(PlayingCard.create('diamonds', '5').imagePath, contains('carreau'));
      expect(PlayingCard.create('clubs', '5').imagePath, contains('trefle'));
      expect(PlayingCard.create('spades', '5').imagePath, contains('pique'));
    });

    test('imagePath for Joker', () {
      final redJoker = PlayingCard.create('hearts', 'JOKER');
      final blackJoker = PlayingCard.create('clubs', 'JOKER');
      
      expect(redJoker.imagePath, contains('joker-rouge'));
      expect(blackJoker.imagePath, contains('joker-noir'));
    });

    test('imagePath for hidden card', () {
      final card = PlayingCard.hidden();
      expect(card.imagePath, contains('back'));
    });
  });

  group('PlayingCard - Serialization', () {
    test('toJson includes all properties', () {
      final card = PlayingCard.create('hearts', 'A');
      final json = card.toJson();
      
      expect(json['suit'], 'hearts');
      expect(json['value'], 'A');
      expect(json['points'], 1);
      expect(json['isSpecial'], false);
      expect(json['id'], 'A_hearts');
    });

    test('fromJson restores card correctly', () {
      final original = PlayingCard.create('diamonds', 'V');
      final json = original.toJson();
      final restored = PlayingCard.fromJson(json);
      
      expect(restored.suit, original.suit);
      expect(restored.value, original.value);
      expect(restored.points, original.points);
      expect(restored.isSpecial, original.isSpecial);
      expect(restored.id, original.id);
    });

    test('hidden card serialization', () {
      final card = PlayingCard.hidden();
      final json = card.toJson();
      
      expect(json['hidden'], true);
    });

    test('fromJson handles hidden cards', () {
      final json = {'hidden': true};
      final card = PlayingCard.fromJson(json);
      
      expect(card.isHidden, true);
    });
  });
}
