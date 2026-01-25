import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/card.dart';

void main() {
  group('Tests des Rois', () {
    
    test('Roi Rouge (Cœur) = 0 points', () {
      final kingHearts = PlayingCard.create('hearts', 'R');
      expect(kingHearts.points, equals(0));
      expect(kingHearts.matchValue, equals('R'));
    });
    
    test('Roi Rouge (Carreau) = 0 points', () {
      final kingDiamonds = PlayingCard.create('diamonds', 'R');
      expect(kingDiamonds.points, equals(0));
      expect(kingDiamonds.matchValue, equals('R'));
    });
    
    test('Roi Noir (Pique) = 13 points', () {
      final kingSpades = PlayingCard.create('spades', 'R');
      expect(kingSpades.points, equals(13));
      expect(kingSpades.matchValue, equals('R'));
    });
    
    test('Roi Noir (Trèfle) = 13 points', () {
      final kingClubs = PlayingCard.create('clubs', 'R');
      expect(kingClubs.points, equals(13));
      expect(kingClubs.matchValue, equals('R'));
    });
    
    test('Deux Rois Rouges matchent ensemble', () {
      final kingHearts = PlayingCard.create('hearts', 'R');
      final kingDiamonds = PlayingCard.create('diamonds', 'R');
      expect(kingHearts.matches(kingDiamonds), isTrue);
    });
    
    test('Deux Rois Noirs matchent ensemble', () {
      final kingSpades = PlayingCard.create('spades', 'R');
      final kingClubs = PlayingCard.create('clubs', 'R');
      expect(kingSpades.matches(kingClubs), isTrue);
    });
    
    test('Roi Rouge MATCHE Roi Noir', () {
      final kingHearts = PlayingCard.create('hearts', 'R');
      final kingSpades = PlayingCard.create('spades', 'R');
      expect(kingHearts.matches(kingSpades), isTrue);
    });
    
    test('Joker = 0 points', () {
      final joker = PlayingCard.create('joker', 'JOKER');
      expect(joker.points, equals(0));
    });
    
    test('Dame = 12 points', () {
      final dame = PlayingCard.create('hearts', 'D');
      expect(dame.points, equals(12));
    });
    
    test('Valet = 11 points', () {
      final jack = PlayingCard.create('hearts', 'V');
      expect(jack.points, equals(11));
    });
    
    test('As = 1 point', () {
      final ace = PlayingCard.create('hearts', 'A');
      expect(ace.points, equals(1));
    });
    
    test('Cartes numériques = leur valeur', () {
      final three = PlayingCard.create('hearts', '3');
      expect(three.points, equals(3));
      
      final seven = PlayingCard.create('hearts', '7');
      expect(seven.points, equals(7));
      
      final ten = PlayingCard.create('hearts', '10');
      expect(ten.points, equals(10));
    });
  });
  
  group('Tests de matching', () {
    
    test('Deux 7 matchent', () {
      final seven1 = PlayingCard.create('hearts', '7');
      final seven2 = PlayingCard.create('spades', '7');
      expect(seven1.matches(seven2), isTrue);
    });
    
    test('7 et 8 ne matchent pas', () {
      final seven = PlayingCard.create('hearts', '7');
      final eight = PlayingCard.create('hearts', '8');
      expect(seven.matches(eight), isFalse);
    });
    
    test('DisplayName pour Roi Rouge', () {
      final kingHearts = PlayingCard.create('hearts', 'R');
      expect(kingHearts.displayName, equals(' Roi Rouge'));
    });
    
    test('DisplayName pour Roi Noir', () {
      final kingSpades = PlayingCard.create('spades', 'R');
      expect(kingSpades.displayName, equals(' Roi Noir'));
    });
  });
}
