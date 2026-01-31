import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';
import 'package:dutch_game/services/game/game_logic.dart';

/// Tests critiques pour les effets des pouvoirs spéciaux
void main() {
  group('Special Powers - Points sensibles', () {
    group('lookAtCard (7/8)', () {
      test('permet de regarder une carte adversaire', () {
        final gs = _createGameState();
        final target = gs.players[1];

        // Ne doit pas lever d'exception
        expect(
          () => GameLogic.lookAtCard(gs, target, 0),
          returnsNormally,
        );
      });

      test('index invalide ne crash pas', () {
        final gs = _createGameState();
        final target = gs.players[1];

        expect(
          () => GameLogic.lookAtCard(gs, target, -1),
          returnsNormally,
        );

        expect(
          () => GameLogic.lookAtCard(gs, target, 100),
          returnsNormally,
        );
      });
    });

    group('swapCards (Valet)', () {
      test('échange les cartes entre deux joueurs', () {
        final gs = _createGameState();
        final p1 = gs.players[0];
        final p2 = gs.players[1];

        final card1Before = p1.hand[0];
        final card2Before = p2.hand[1];

        GameLogic.swapCards(gs, p1, 0, p2, 1);

        expect(p1.hand[0].id, card2Before.id);
        expect(p2.hand[1].id, card1Before.id);
      });

      test('swap reset les knownCards', () {
        final gs = _createGameState();
        final p1 = gs.players[0];
        final p2 = gs.players[1];

        p1.knownCards[0] = true;
        p2.knownCards[1] = true;

        GameLogic.swapCards(gs, p1, 0, p2, 1);

        expect(p1.knownCards[0], isFalse);
        expect(p2.knownCards[1], isFalse);
      });

      test('index invalide ne fait rien', () {
        final gs = _createGameState();
        final p1 = gs.players[0];
        final p2 = gs.players[1];

        final hand1Before = List.from(p1.hand);
        final hand2Before = List.from(p2.hand);

        GameLogic.swapCards(gs, p1, -1, p2, 0);

        expect(p1.hand.length, hand1Before.length);
        expect(p2.hand.length, hand2Before.length);
      });

      test('swap avec même joueur fonctionne', () {
        final gs = _createGameState();
        final p = gs.players[0];

        final card0 = p.hand[0];
        final card1 = p.hand[1];

        GameLogic.swapCards(gs, p, 0, p, 1);

        expect(p.hand[0].id, card1.id);
        expect(p.hand[1].id, card0.id);
      });
    });

    group('jokerEffect', () {
      test('mélange la main du joueur cible', () {
        final gs = _createGameState();
        final target = gs.players[1];

        final handBefore = target.hand.map((c) => c.id).toList();

        GameLogic.jokerEffect(gs, target);

        // La main doit toujours avoir le même nombre de cartes
        expect(target.hand.length, handBefore.length);
      });

      test('reset toutes les knownCards à false', () {
        final gs = _createGameState();
        final target = gs.players[1];

        target.knownCards = List.filled(target.hand.length, true, growable: true);

        GameLogic.jokerEffect(gs, target);

        expect(target.knownCards.every((k) => k == false), isTrue);
      });

      test('reset mentalMap du bot', () {
        final gs = _createGameState();
        final target = gs.players[1]; // Bot

        target.mentalMap = List.filled(target.hand.length, null, growable: true);
        target.mentalMap[0] = target.hand[0];

        GameLogic.jokerEffect(gs, target);

        expect(target.mentalMap.every((m) => m == null), isTrue);
      });

      test('joker sur joueur avec main vide ne crash pas', () {
        final gs = _createGameState();
        final target = gs.players[1];
        target.hand = [];
        target.knownCards = [];

        expect(
          () => GameLogic.jokerEffect(gs, target),
          returnsNormally,
        );
      });
    });

    group('replaceCard', () {
      test('remplace la carte à l\'index donné', () {
        final gs = _createGameState();
        final player = gs.players[0];

        gs.drawnCard = PlayingCard.create('hearts', 'A');
        final drawnCard = gs.drawnCard!;
        final oldCard = player.hand[0];

        GameLogic.replaceCard(gs, 0);

        expect(player.hand[0].id, drawnCard.id);
        expect(gs.discardPile.last.id, oldCard.id);
        expect(gs.drawnCard, isNull);
      });

      test('replace marque la carte comme connue', () {
        final gs = _createGameState();
        final player = gs.players[0];

        player.knownCards[0] = false;
        gs.drawnCard = PlayingCard.create('hearts', 'A');

        GameLogic.replaceCard(gs, 0);

        expect(player.knownCards[0], isTrue);
      });

      test('replace avec index invalide ne fait rien', () {
        final gs = _createGameState();
        final player = gs.players[0];

        gs.drawnCard = PlayingCard.create('hearts', 'A');
        final handBefore = List.from(player.hand);

        GameLogic.replaceCard(gs, -1);

        expect(player.hand.length, handBefore.length);
        expect(gs.drawnCard, isNotNull); // Carte pas consommée
      });

      test('replace sans drawnCard ne fait rien', () {
        final gs = _createGameState();
        final player = gs.players[0];

        gs.drawnCard = null;
        final handBefore = List.from(player.hand);

        GameLogic.replaceCard(gs, 0);

        expect(player.hand.length, handBefore.length);
      });

      test('replace avec carte spéciale déclenche pouvoir', () {
        final gs = _createGameState();

        gs.drawnCard = PlayingCard.create('hearts', 'A');
        // La carte remplacée est un 7 (pouvoir)
        gs.players[0].hand[0] = PlayingCard.create('hearts', '7');

        GameLogic.replaceCard(gs, 0);

        expect(gs.isWaitingForSpecialPower, isTrue);
        expect(gs.specialCardToActivate!.value, '7');
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
    player.knownCards = List.filled(4, false, growable: true);
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
