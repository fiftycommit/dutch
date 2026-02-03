import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';

/// Tests critiques pour le calcul des scores
void main() {
  group('Score Calculation - Points sensibles', () {
    group('calculateScore', () {
      test('main vide = score 0', () {
        final player = _createPlayer([]);
        expect(player.calculateScore(), 0);
      });

      test('As = 1 point', () {
        final player = _createPlayer([PlayingCard.create('hearts', 'A')]);
        expect(player.calculateScore(), 1);
      });

      test('cartes numériques = valeur faciale', () {
        final player = _createPlayer([
          PlayingCard.create('hearts', '2'),
          PlayingCard.create('diamonds', '5'),
          PlayingCard.create('clubs', '10'),
        ]);
        expect(player.calculateScore(), 2 + 5 + 10);
      });

      test('Valet = 11 points', () {
        final player = _createPlayer([PlayingCard.create('hearts', 'V')]);
        expect(player.calculateScore(), 11);
      });

      test('Dame = 12 points', () {
        final player = _createPlayer([PlayingCard.create('hearts', 'D')]);
        expect(player.calculateScore(), 12);
      });

      test('Roi noir = 13 points', () {
        final player = _createPlayer([PlayingCard.create('clubs', 'R')]);
        expect(player.calculateScore(), 13);
      });

      test('Roi rouge = 0 points (règle Dutch)', () {
        final player = _createPlayer([PlayingCard.create('hearts', 'R')]);
        expect(player.calculateScore(), 0);
      });

      test('Joker = 0 points', () {
        final player = _createPlayer([PlayingCard.create('joker', 'JOKER')]);
        expect(player.calculateScore(), 0);
      });

      test('main mixte calcule correctement', () {
        final player = _createPlayer([
          PlayingCard.create('hearts', 'A'),    // 1
          PlayingCard.create('diamonds', '5'),  // 5
          PlayingCard.create('clubs', 'R'),     // 13
          PlayingCard.create('joker', 'JOKER'), // 0
        ]);
        expect(player.calculateScore(), 1 + 5 + 13 + 0);
      });
    });

    group('getFinalScore', () {
      test('retourne le score calculé du joueur', () {
        final gs = _createGameState();
        final player = gs.players.first;
        player.hand = [
          PlayingCard.create('hearts', '5'),
          PlayingCard.create('diamonds', '10'),
        ];

        expect(gs.getFinalScore(player), 15);
      });

      test('fonctionne pour tous les joueurs', () {
        final gs = _createGameState();
        
        gs.players[0].hand = [PlayingCard.create('hearts', 'A')];
        gs.players[1].hand = [PlayingCard.create('clubs', 'R')];

        expect(gs.getFinalScore(gs.players[0]), 1);
        expect(gs.getFinalScore(gs.players[1]), 13);
      });
    });

    group('getEstimatedScore', () {
      test('humain: retourne score réel', () {
        final player = Player(id: 'human', name: 'Human', isHuman: true, position: 0);
        player.hand = [
          PlayingCard.create('hearts', '5'),
          PlayingCard.create('diamonds', '10'),
        ];
        player.knownCards = [true, true];

        expect(player.getEstimatedScore(), 15);
      });

      test('bot: estime selon cartes connues', () {
        final player = Player(id: 'bot', name: 'Bot', isHuman: false, position: 0);
        player.hand = [
          PlayingCard.create('hearts', '5'),
          PlayingCard.create('diamonds', '10'),
        ];
        player.mentalMap = [
          PlayingCard.create('hearts', '5'), // Connu
          null, // Inconnu
        ];

        final estimated = player.getEstimatedScore();
        expect(estimated, equals(5)); // Seulement les cartes connues
      });
    });

    group('PlayingCard.points', () {
      test('toutes les valeurs ont des points corrects', () {
        expect(PlayingCard.create('hearts', 'A').points, 1);
        expect(PlayingCard.create('hearts', '2').points, 2);
        expect(PlayingCard.create('hearts', '3').points, 3);
        expect(PlayingCard.create('hearts', '4').points, 4);
        expect(PlayingCard.create('hearts', '5').points, 5);
        expect(PlayingCard.create('hearts', '6').points, 6);
        expect(PlayingCard.create('hearts', '7').points, 7);
        expect(PlayingCard.create('hearts', '8').points, 8);
        expect(PlayingCard.create('hearts', '9').points, 9);
        expect(PlayingCard.create('hearts', '10').points, 10);
        expect(PlayingCard.create('hearts', 'V').points, 11);
        expect(PlayingCard.create('hearts', 'D').points, 12);
        expect(PlayingCard.create('clubs', 'R').points, 13); // Roi noir
        expect(PlayingCard.create('hearts', 'R').points, 0); // Roi rouge = 0
        expect(PlayingCard.create('joker', 'JOKER').points, 0);
      });
    });
  });
}

Player _createPlayer(List<PlayingCard> hand) {
  final player = Player(id: 'test', name: 'Test', isHuman: true, position: 0);
  player.hand = hand;
  player.knownCards = List.filled(hand.length, true, growable: true);
  return player;
}

GameState _createGameState() {
  final players = [
    Player(id: 'human', name: 'Human', isHuman: true, position: 0),
    Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
  ];

  for (var player in players) {
    player.hand = [PlayingCard.create('hearts', 'A')];
    player.knownCards = [true];
  }

  return GameState(
    players: players,
    deck: [],
    discardPile: [PlayingCard.create('hearts', '5')],
    currentPlayerIndex: 0,
    phase: GamePhase.ended,
  );
}
