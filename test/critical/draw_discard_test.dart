import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';
import 'package:dutch_game/services/game/game_logic.dart';

/// Tests critiques pour pioche et défausse
void main() {
  group('Draw & Discard - Points sensibles', () {
    group('drawCard', () {
      test('pioche une carte du deck', () {
        final gs = _createGameState();
        final deckSizeBefore = gs.deck.length;

        GameLogic.drawCard(gs);

        expect(gs.deck.length, deckSizeBefore - 1);
        expect(gs.drawnCard, isNotNull);
      });

      test('drawnCard est la dernière carte du deck', () {
        final gs = _createGameState();
        final expectedCard = gs.deck.last;

        GameLogic.drawCard(gs);

        expect(gs.drawnCard!.id, expectedCard.id);
      });

      test('deck vide déclenche refill', () {
        final gs = _createGameState();
        gs.deck.clear();
        // Ajouter des cartes à la défausse
        for (int i = 0; i < 10; i++) {
          gs.discardPile.add(PlayingCard.create('hearts', '${i + 1}'));
        }

        GameLogic.drawCard(gs);

        expect(gs.deck.length, greaterThan(0));
      });
    });

    group('discardDrawnCard', () {
      test('ajoute la carte à la défausse', () {
        final gs = _createGameState();
        gs.drawnCard = PlayingCard.create('hearts', 'A');

        final discardSizeBefore = gs.discardPile.length;
        GameLogic.discardDrawnCard(gs);

        expect(gs.discardPile.length, discardSizeBefore + 1);
        expect(gs.drawnCard, isNull);
      });

      test('carte spéciale défaussée déclenche pouvoir', () {
        final gs = _createGameState();
        gs.drawnCard = PlayingCard.create('hearts', '7');

        GameLogic.discardDrawnCard(gs);

        expect(gs.isWaitingForSpecialPower, isTrue);
      });

      test('carte normale défaussée ne déclenche pas pouvoir', () {
        final gs = _createGameState();
        gs.drawnCard = PlayingCard.create('hearts', '5');

        GameLogic.discardDrawnCard(gs);

        expect(gs.isWaitingForSpecialPower, isFalse);
      });

      test('discard sans drawnCard ne fait rien', () {
        final gs = _createGameState();
        gs.drawnCard = null;

        final discardSizeBefore = gs.discardPile.length;
        GameLogic.discardDrawnCard(gs);

        expect(gs.discardPile.length, discardSizeBefore);
      });
    });

    group('takeFromDiscard', () {
      test('topDiscardCard retourne la dernière carte', () {
        final gs = _createGameState();
        final lastCard = gs.discardPile.last;

        expect(gs.topDiscardCard!.id, lastCard.id);
      });

      test('topDiscardCard null si défausse vide', () {
        final gs = _createGameState();
        gs.discardPile.clear();

        expect(gs.topDiscardCard, isNull);
      });
    });

    group('applyPenalty', () {
      test('ajoute une carte à la main', () {
        final gs = _createGameState();
        final player = gs.players[0];
        final handSizeBefore = player.hand.length;

        GameLogic.applyPenalty(gs, player);

        expect(player.hand.length, handSizeBefore + 1);
      });

      test('carte de pénalité est inconnue', () {
        final gs = _createGameState();
        final player = gs.players[0];

        GameLogic.applyPenalty(gs, player);

        expect(player.knownCards.last, isFalse);
      });

      test('pénalité avec deck vide déclenche refill', () {
        final gs = _createGameState();
        gs.deck.clear();
        for (int i = 0; i < 10; i++) {
          gs.discardPile.add(PlayingCard.create('diamonds', '${i + 1}'));
        }

        final player = gs.players[0];
        final handSizeBefore = player.hand.length;

        GameLogic.applyPenalty(gs, player);

        expect(player.hand.length, handSizeBefore + 1);
      });

      test('bot reçoit aussi mentalMap null', () {
        final gs = _createGameState();
        final bot = gs.players[1];
        final mentalMapSizeBefore = bot.mentalMap.length;

        GameLogic.applyPenalty(gs, bot);

        expect(bot.mentalMap.length, mentalMapSizeBefore + 1);
        expect(bot.mentalMap.last, isNull);
      });
    });

    group('initialReveal', () {
      test('marque les cartes sélectionnées comme connues', () {
        final gs = _createGameState();
        final human = gs.players[0];
        human.knownCards = List.filled(4, false, growable: true);

        GameLogic.initialReveal(gs, [0, 2]);

        expect(human.knownCards[0], isTrue);
        expect(human.knownCards[1], isFalse);
        expect(human.knownCards[2], isTrue);
        expect(human.knownCards[3], isFalse);
      });

      test('index invalide est ignoré', () {
        final gs = _createGameState();
        final human = gs.players[0];
        human.knownCards = List.filled(4, false, growable: true);

        GameLogic.initialReveal(gs, [-1, 0, 100]);

        expect(human.knownCards[0], isTrue);
        // Pas de crash
      });
    });
  });
}

GameState _createGameState() {
  final players = [
    Player(id: 'human', name: 'Human', isHuman: true, position: 0),
    Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
  ];

  for (var player in players) {
    player.hand = [
      PlayingCard.create('hearts', '2'),
      PlayingCard.create('diamonds', '5'),
      PlayingCard.create('clubs', '8'),
      PlayingCard.create('spades', '10'),
    ];
    player.knownCards = List.filled(4, true, growable: true);
    if (!player.isHuman) {
      player.mentalMap = List.filled(4, null, growable: true);
    }
  }

  return GameState(
    players: players,
    deck: GameState.createFullDeck().sublist(0, 40),
    discardPile: [PlayingCard.create('hearts', '5')],
    currentPlayerIndex: 0,
    phase: GamePhase.playing,
  );
}
