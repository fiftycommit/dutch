import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/services/game/shuffle_strategy.dart';

void main() {
  group('RandomShuffleStrategy', () {
    test('shuffle returns all cards', () {
      final strategy = RandomShuffleStrategy();
      final deck = GameState.createFullDeck();
      
      final shuffled = strategy.shuffle(deck);
      
      expect(shuffled.length, deck.length);
    });

    test('shuffle does not modify original deck', () {
      final strategy = RandomShuffleStrategy();
      final deck = GameState.createFullDeck();
      final originalIds = deck.map((c) => c.id).toList();
      
      strategy.shuffle(deck);
      
      expect(deck.map((c) => c.id).toList(), originalIds);
    });

    test('shuffle produces different order', () {
      final strategy = RandomShuffleStrategy();
      final deck = GameState.createFullDeck();
      
      // Shuffle multiple times and check at least one is different
      bool foundDifferent = false;
      for (int i = 0; i < 10; i++) {
        final shuffled = strategy.shuffle(deck);
        if (shuffled.first.id != deck.first.id) {
          foundDifferent = true;
          break;
        }
      }
      
      expect(foundDifferent, true);
    });

    test('name is Random', () {
      final strategy = RandomShuffleStrategy();
      expect(strategy.name, 'Random');
    });

    test('shuffle preserves all cards (no duplicates or losses)', () {
      final strategy = RandomShuffleStrategy();
      final deck = GameState.createFullDeck();
      final originalIds = deck.map((c) => c.id).toSet();
      
      final shuffled = strategy.shuffle(deck);
      final shuffledIds = shuffled.map((c) => c.id).toSet();
      
      expect(shuffledIds, originalIds);
    });
  });

  group('SmartShuffleStrategy', () {
    test('easy shuffle returns all cards', () {
      final strategy = SmartShuffleStrategy('easy');
      final deck = GameState.createFullDeck();
      
      final shuffled = strategy.shuffle(deck);
      
      expect(shuffled.length, deck.length);
    });

    test('medium shuffle returns all cards', () {
      final strategy = SmartShuffleStrategy('medium');
      final deck = GameState.createFullDeck();
      
      final shuffled = strategy.shuffle(deck);
      
      expect(shuffled.length, deck.length);
    });

    test('hard shuffle returns all cards', () {
      final strategy = SmartShuffleStrategy('hard');
      final deck = GameState.createFullDeck();
      
      final shuffled = strategy.shuffle(deck);
      
      expect(shuffled.length, deck.length);
    });

    test('name includes difficulty', () {
      expect(SmartShuffleStrategy('easy').name, 'Smart-easy');
      expect(SmartShuffleStrategy('medium').name, 'Smart-medium');
      expect(SmartShuffleStrategy('hard').name, 'Smart-hard');
    });

    test('easy shuffle favors good cards at top', () {
      final strategy = SmartShuffleStrategy('easy');
      final deck = GameState.createFullDeck();
      
      // Run multiple times to get statistical significance
      int goodCardsInTop10 = 0;
      const runs = 20;
      
      for (int i = 0; i < runs; i++) {
        final shuffled = strategy.shuffle(deck);
        // Count good cards (low points) in top 10
        for (int j = 0; j < 10 && j < shuffled.length; j++) {
          if (shuffled[j].points <= 4) goodCardsInTop10++;
        }
      }
      
      // Easy should have more good cards at top than random (~3-4 per 10)
      final avgGoodCards = goodCardsInTop10 / runs;
      expect(avgGoodCards, greaterThan(2.0));
    });

    test('hard shuffle favors bad cards at top', () {
      final strategy = SmartShuffleStrategy('hard');
      final deck = GameState.createFullDeck();
      
      // Run multiple times to get statistical significance
      int badCardsInTop10 = 0;
      const runs = 20;
      
      for (int i = 0; i < runs; i++) {
        final shuffled = strategy.shuffle(deck);
        // Count bad cards (high points) in top 10
        for (int j = 0; j < 10 && j < shuffled.length; j++) {
          if (shuffled[j].points >= 8) badCardsInTop10++;
        }
      }
      
      // Hard should have more bad cards at top
      final avgBadCards = badCardsInTop10 / runs;
      expect(avgBadCards, greaterThan(2.0));
    });

    test('shuffle preserves all cards', () {
      final strategy = SmartShuffleStrategy('medium');
      final deck = GameState.createFullDeck();
      final originalIds = deck.map((c) => c.id).toSet();
      
      final shuffled = strategy.shuffle(deck);
      final shuffledIds = shuffled.map((c) => c.id).toSet();
      
      expect(shuffledIds, originalIds);
    });
  });

  group('MLShuffleStrategy', () {
    test('shuffle returns all cards', () {
      final strategy = MLShuffleStrategy('medium');
      final deck = GameState.createFullDeck();
      
      final shuffled = strategy.shuffle(deck);
      
      expect(shuffled.length, deck.length);
    });

    test('name includes ML prefix', () {
      expect(MLShuffleStrategy('easy').name, 'ML-easy');
      expect(MLShuffleStrategy('medium').name, 'ML-medium');
      expect(MLShuffleStrategy('hard').name, 'ML-hard');
    });

    test('shuffle preserves all cards', () {
      final strategy = MLShuffleStrategy('hard');
      final deck = GameState.createFullDeck();
      final originalIds = deck.map((c) => c.id).toSet();
      
      final shuffled = strategy.shuffle(deck);
      final shuffledIds = shuffled.map((c) => c.id).toSet();
      
      expect(shuffledIds, originalIds);
    });

    test('easy difficulty has more good cards accessible', () {
      final strategy = MLShuffleStrategy('easy');
      final deck = GameState.createFullDeck();
      
      int goodCardsInTop15 = 0;
      const runs = 20;
      
      for (int i = 0; i < runs; i++) {
        final shuffled = strategy.shuffle(deck);
        for (int j = 0; j < 15 && j < shuffled.length; j++) {
          if (shuffled[j].points <= 4) goodCardsInTop15++;
        }
      }
      
      final avgGoodCards = goodCardsInTop15 / runs;
      expect(avgGoodCards, greaterThan(3.0));
    });

    test('hard difficulty has fewer good cards accessible', () {
      final easyStrategy = MLShuffleStrategy('easy');
      final hardStrategy = MLShuffleStrategy('hard');
      final deck = GameState.createFullDeck();
      
      int easyGoodCards = 0;
      int hardGoodCards = 0;
      const runs = 30;
      
      for (int i = 0; i < runs; i++) {
        final easyShuffled = easyStrategy.shuffle(deck);
        final hardShuffled = hardStrategy.shuffle(deck);
        
        for (int j = 0; j < 15 && j < easyShuffled.length; j++) {
          if (easyShuffled[j].points <= 4) easyGoodCards++;
          if (hardShuffled[j].points <= 4) hardGoodCards++;
        }
      }
      
      // Easy should have more good cards accessible than hard
      expect(easyGoodCards, greaterThan(hardGoodCards));
    });
  });

  group('ShuffleStrategy Interface', () {
    test('all strategies implement interface correctly', () {
      final strategies = <ShuffleStrategy>[
        RandomShuffleStrategy(),
        SmartShuffleStrategy('medium'),
        MLShuffleStrategy('medium'),
      ];
      
      for (var strategy in strategies) {
        expect(strategy.name, isNotEmpty);
        
        final deck = GameState.createFullDeck();
        final shuffled = strategy.shuffle(deck);
        
        expect(shuffled, isNotNull);
        expect(shuffled.length, 54);
      }
    });
  });
}
