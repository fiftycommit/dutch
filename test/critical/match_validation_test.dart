import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';
import 'package:dutch_game/services/game/game_logic.dart';

/// Tests critiques pour la validation des matchs
/// Point sensible: un match raté doit donner une pénalité
void main() {
  group('Match Validation - Points sensibles', () {
    group('Match réussi', () {
      test('carte avec même valeur match', () {
        final gs = _createGameState();
        final player = gs.players.first;
        
        // Mettre une carte 5 sur la défausse
        gs.discardPile.add(PlayingCard.create('hearts', '5'));
        // Donner au joueur une carte 5 (autre couleur)
        player.hand[0] = PlayingCard.create('diamonds', '5');
        
        final initialHandSize = player.hand.length;
        final result = GameLogic.matchCard(gs, player, 0);
        
        expect(result, isTrue);
        expect(player.hand.length, initialHandSize - 1); // Carte enlevée
      });

      test('match enlève la carte de la main', () {
        final gs = _createGameState();
        final player = gs.players.first;
        
        gs.discardPile.add(PlayingCard.create('clubs', '7'));
        player.hand[1] = PlayingCard.create('spades', '7');
        
        final matchedCard = player.hand[1];
        GameLogic.matchCard(gs, player, 1);
        
        expect(player.hand.contains(matchedCard), isFalse);
      });

      test('match ajoute la carte à la défausse', () {
        final gs = _createGameState();
        final player = gs.players.first;
        
        gs.discardPile.add(PlayingCard.create('hearts', '9'));
        player.hand[0] = PlayingCard.create('diamonds', '9');
        
        final discardSizeBefore = gs.discardPile.length;
        GameLogic.matchCard(gs, player, 0);
        
        expect(gs.discardPile.length, discardSizeBefore + 1);
      });
    });

    group('Match raté', () {
      test('carte avec valeur différente ne match pas', () {
        final gs = _createGameState();
        final player = gs.players.first;
        
        gs.discardPile.add(PlayingCard.create('hearts', '5'));
        player.hand[0] = PlayingCard.create('hearts', '8'); // Même couleur, valeur différente
        
        final result = GameLogic.matchCard(gs, player, 0);
        
        expect(result, isFalse);
      });

      test('match raté donne une pénalité', () {
        final gs = _createGameState();
        final player = gs.players.first;
        
        gs.discardPile.add(PlayingCard.create('hearts', '5'));
        player.hand[0] = PlayingCard.create('diamonds', '8');
        
        final initialHandSize = player.hand.length;
        GameLogic.matchCard(gs, player, 0);
        
        expect(player.hand.length, initialHandSize + 1); // Pénalité ajoutée
      });

      test('pénalité est une carte inconnue', () {
        final gs = _createGameState();
        final player = gs.players.first;
        
        gs.discardPile.add(PlayingCard.create('hearts', '5'));
        player.hand[0] = PlayingCard.create('diamonds', '8');
        
        GameLogic.matchCard(gs, player, 0);
        
        expect(player.knownCards.last, isFalse); // Dernière carte inconnue
      });
    });

    group('Cas limites', () {
      test('index invalide négatif retourne false', () {
        final gs = _createGameState();
        final player = gs.players.first;
        
        gs.discardPile.add(PlayingCard.create('hearts', '5'));
        
        final result = GameLogic.matchCard(gs, player, -1);
        
        expect(result, isFalse);
      });

      test('index hors limites retourne false', () {
        final gs = _createGameState();
        final player = gs.players.first;
        
        gs.discardPile.add(PlayingCard.create('hearts', '5'));
        
        final result = GameLogic.matchCard(gs, player, 100);
        
        expect(result, isFalse);
      });

      test('défausse vide retourne false', () {
        final gs = _createGameState();
        final player = gs.players.first;
        gs.discardPile.clear();
        
        final result = GameLogic.matchCard(gs, player, 0);
        
        expect(result, isFalse);
      });

      test('knownCards est mis à jour après match', () {
        final gs = _createGameState();
        final player = gs.players.first;
        
        gs.discardPile.add(PlayingCard.create('hearts', '5'));
        player.hand = [
          PlayingCard.create('diamonds', '5'),
          PlayingCard.create('clubs', 'K'),
          PlayingCard.create('spades', 'A'),
        ];
        player.knownCards = [true, false, true];
        
        GameLogic.matchCard(gs, player, 0);
        
        // knownCards[0] est supprimé, les autres décalent
        expect(player.knownCards.length, 2);
        expect(player.knownCards[0], isFalse); // Ancien knownCards[1]
        expect(player.knownCards[1], isTrue);  // Ancien knownCards[2]
      });
    });

    group('Match avec cartes spéciales', () {
      test('joker match avec joker', () {
        final gs = _createGameState();
        final player = gs.players.first;
        
        gs.discardPile.add(PlayingCard.create('joker', 'JOKER'));
        player.hand[0] = PlayingCard.create('joker', 'JOKER');
        
        final result = GameLogic.matchCard(gs, player, 0);
        
        expect(result, isTrue);
      });

      test('roi match avec roi', () {
        final gs = _createGameState();
        final player = gs.players.first;
        
        gs.discardPile.add(PlayingCard.create('hearts', 'K'));
        player.hand[0] = PlayingCard.create('spades', 'K');
        
        final result = GameLogic.matchCard(gs, player, 0);
        
        expect(result, isTrue);
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
      PlayingCard.create('hearts', 'A'),
      PlayingCard.create('diamonds', '2'),
      PlayingCard.create('clubs', '3'),
      PlayingCard.create('spades', '4'),
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
