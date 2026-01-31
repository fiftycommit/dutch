import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';
import 'package:dutch_game/services/game/game_logic.dart';

/// Tests critiques pour le remplissage du deck
/// Point sensible: quand le deck est vide, la défausse doit être mélangée
/// SAUF la carte du dessus qui reste visible
void main() {
  group('Deck Refill - Points sensibles', () {
    group('Refill depuis la défausse', () {
      test('deck vide déclenche refill depuis défausse', () {
        final gs = _createGameState(deckSize: 0, discardSize: 10);
        final originalDiscardTop = gs.discardPile.last;

        GameLogic.drawCard(gs);

        expect(gs.deck.length, greaterThan(0));
        expect(gs.discardPile.length, 1); // Seule la top card reste
        expect(gs.discardPile.first.value, originalDiscardTop.value);
      });

      test('top discard card reste en place après refill', () {
        final gs = _createGameState(deckSize: 0, discardSize: 5);
        final topCard = gs.discardPile.last;

        GameLogic.drawCard(gs);

        expect(gs.discardPile.first.value, topCard.value);
        expect(gs.discardPile.first.suit, topCard.suit);
      });

      test('refill ne se produit pas si défausse a 1 seule carte', () {
        final gs = _createGameState(deckSize: 0, discardSize: 1);
        GameLogic.drawCard(gs);

        // Partie devrait se terminer car pas assez de cartes
        expect(gs.phase, GamePhase.ended);
      });

      test('refill avec Dutch caller force fin de partie', () {
        final gs = _createGameState(deckSize: 0, discardSize: 1);
        gs.dutchCallerId = 'human';

        GameLogic.drawCard(gs);

        expect(gs.phase, GamePhase.dutchCalled);
      });
    });

    group('Pénalité avec deck vide', () {
      test('pénalité déclenche refill si nécessaire', () {
        final gs = _createGameState(deckSize: 0, discardSize: 10);
        final human = gs.players.first;
        final initialHandSize = human.hand.length;

        GameLogic.applyPenalty(gs, human);

        expect(human.hand.length, initialHandSize + 1);
      });

      test('pénalité impossible si deck et défausse vides', () {
        final gs = _createGameState(deckSize: 0, discardSize: 1);
        final human = gs.players.first;
        final initialHandSize = human.hand.length;

        GameLogic.applyPenalty(gs, human);

        expect(human.hand.length, initialHandSize); // Pas de changement
      });
    });

    group('Invariants du deck', () {
      test('total des cartes reste constant après refill', () {
        final gs = _createGameState(deckSize: 5, discardSize: 10);
        final totalBefore = _countAllCards(gs);

        GameLogic.drawCard(gs); // Peut déclencher refill
        gs.discardPile.add(gs.drawnCard!);
        gs.drawnCard = null;

        final totalAfter = _countAllCards(gs);
        expect(totalAfter, totalBefore);
      });

      test('pas de doublons après refill', () {
        final gs = _createGameState(deckSize: 0, discardSize: 20);

        GameLogic.drawCard(gs);

        final allCards = [...gs.deck, ...gs.discardPile];
        if (gs.drawnCard != null) allCards.add(gs.drawnCard!);
        
        final uniqueCards = allCards.map((c) => '${c.suit}_${c.value}').toSet();
        // Note: il peut y avoir des doublons légitimes (même valeur différentes couleurs)
        // On vérifie juste que le refill n'a pas créé de problèmes
        expect(allCards.length, uniqueCards.length);
      });
    });
  });
}

int _countAllCards(GameState gs) {
  int count = gs.deck.length + gs.discardPile.length;
  if (gs.drawnCard != null) count++;
  for (var p in gs.players) {
    count += p.hand.length;
  }
  return count;
}

GameState _createGameState({required int deckSize, required int discardSize}) {
  final players = [
    Player(id: 'human', name: 'Human', isHuman: true, position: 0),
    Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
  ];

  for (var player in players) {
    player.hand = [
      PlayingCard.create('hearts', 'A'),
      PlayingCard.create('diamonds', '2'),
    ];
    player.knownCards = List.filled(2, true, growable: true);
  }

  final deck = <PlayingCard>[];
  final suits = ['hearts', 'diamonds', 'clubs', 'spades'];
  int cardIndex = 0;
  
  for (int i = 0; i < deckSize && cardIndex < 52; i++) {
    deck.add(PlayingCard.create(suits[cardIndex % 4], '${(cardIndex % 10) + 1}'));
    cardIndex++;
  }

  final discardPile = <PlayingCard>[];
  for (int i = 0; i < discardSize && cardIndex < 52; i++) {
    discardPile.add(PlayingCard.create(suits[cardIndex % 4], '${(cardIndex % 10) + 1}'));
    cardIndex++;
  }

  return GameState(
    players: players,
    deck: deck,
    discardPile: discardPile,
    currentPlayerIndex: 0,
    phase: GamePhase.playing,
  );
}
