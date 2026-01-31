import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';

/// Tests critiques pour le classement avec Dutch
/// Ces tests vérifient les règles métier les plus importantes du jeu
void main() {
  group('Dutch Ranking - Points sensibles', () {
    group('Dutch caller gagnant', () {
      test('Dutch caller avec meilleur score est 1er', () {
        final gs = _createGameState([
          _player('dutch', score: 5, isHuman: true),
          _player('bot1', score: 10),
          _player('bot2', score: 15),
        ]);
        gs.dutchCallerId = 'dutch';

        final ranking = gs.getFinalRanking();

        expect(ranking[0].id, 'dutch');
        expect(ranking[1].id, 'bot1');
        expect(ranking[2].id, 'bot2');
      });

      test('Dutch caller avec score égal au meilleur est SEUL 1er', () {
        final gs = _createGameState([
          _player('dutch', score: 10, isHuman: true),
          _player('bot1', score: 10), // Même score
          _player('bot2', score: 15),
        ]);
        gs.dutchCallerId = 'dutch';

        final ranks = gs.getFinalRanksWithTies();

        expect(ranks['dutch'], 1); // Dutch caller est 1er
        expect(ranks['bot1'], 2); // Même score mais 2e (pas ex-aequo avec Dutch)
        expect(ranks['bot2'], 3);
      });

      test('Dutch caller gagnant avec main vide est 1er', () {
        final gs = _createGameState([
          _player('dutch', score: 0, isHuman: true),
          _player('bot1', score: 5),
          _player('bot2', score: 10),
        ]);
        gs.dutchCallerId = 'dutch';

        final ranking = gs.getFinalRanking();

        expect(ranking[0].id, 'dutch');
        expect(gs.didDutchCallerWin(), isTrue);
      });
    });

    group('Dutch caller perdant', () {
      test('Dutch caller avec score supérieur est DERNIER', () {
        final gs = _createGameState([
          _player('dutch', score: 20, isHuman: true),
          _player('bot1', score: 5),
          _player('bot2', score: 10),
        ]);
        gs.dutchCallerId = 'dutch';

        final ranking = gs.getFinalRanking();

        expect(ranking.last.id, 'dutch'); // Dutch raté = dernier
        expect(ranking[0].id, 'bot1'); // Meilleur score = 1er
      });

      test('Dutch caller perdant a le rang le plus bas', () {
        final gs = _createGameState([
          _player('dutch', score: 20, isHuman: true),
          _player('bot1', score: 5),
          _player('bot2', score: 10),
          _player('bot3', score: 15),
        ]);
        gs.dutchCallerId = 'dutch';

        final ranks = gs.getFinalRanksWithTies();

        expect(ranks['dutch'], 4); // Dernier même si pas le pire score
        expect(ranks['bot1'], 1);
      });

      test('didDutchCallerWin retourne false si pas meilleur score', () {
        final gs = _createGameState([
          _player('dutch', score: 15, isHuman: true),
          _player('bot1', score: 10), // Meilleur score
        ]);
        gs.dutchCallerId = 'dutch';

        expect(gs.didDutchCallerWin(), isFalse);
      });
    });

    group('Ex-aequo sans Dutch', () {
      test('Joueurs avec même score ont même rang', () {
        final gs = _createGameState([
          _player('p1', score: 10, isHuman: true),
          _player('p2', score: 10),
          _player('p3', score: 20),
        ]);

        final ranks = gs.getFinalRanksWithTies();

        expect(ranks['p1'], ranks['p2']); // Même rang
        expect(ranks['p3'], 3); // 3e (pas 2e car 2 ex-aequo avant)
      });

      test('Trois joueurs ex-aequo', () {
        final gs = _createGameState([
          _player('p1', score: 10, isHuman: true),
          _player('p2', score: 10),
          _player('p3', score: 10),
          _player('p4', score: 20),
        ]);

        final ranks = gs.getFinalRanksWithTies();

        expect(ranks['p1'], 1);
        expect(ranks['p2'], 1);
        expect(ranks['p3'], 1);
        expect(ranks['p4'], 4); // 4e car 3 ex-aequo avant
      });
    });

    group('Cas limites', () {
      test('Partie sans Dutch caller', () {
        final gs = _createGameState([
          _player('p1', score: 5, isHuman: true),
          _player('p2', score: 10),
        ]);
        // Pas de dutchCallerId

        final ranking = gs.getFinalRanking();

        expect(ranking[0].id, 'p1');
        expect(ranking[1].id, 'p2');
      });

      test('Tous les joueurs avec score 0', () {
        final gs = _createGameState([
          _player('p1', score: 0, isHuman: true),
          _player('p2', score: 0),
        ]);

        final ranks = gs.getFinalRanksWithTies();

        expect(ranks['p1'], 1);
        expect(ranks['p2'], 1); // Ex-aequo
      });

      test('Dutch caller avec exactement même score que tous', () {
        final gs = _createGameState([
          _player('dutch', score: 10, isHuman: true),
          _player('bot1', score: 10),
          _player('bot2', score: 10),
        ]);
        gs.dutchCallerId = 'dutch';

        final ranks = gs.getFinalRanksWithTies();

        expect(ranks['dutch'], 1); // Dutch caller seul 1er
        expect(ranks['bot1'], 2); // Autres sont 2e
        expect(ranks['bot2'], 2);
      });
    });
  });
}

Player _player(String id, {required int score, bool isHuman = false}) {
  final player = Player(
    id: id,
    name: id,
    isHuman: isHuman,
    position: 0,
  );
  
  // Créer une main avec le score exact souhaité
  player.hand = _createHandWithScore(score);
  player.knownCards = List.filled(player.hand.length, true, growable: true);
  
  return player;
}

List<PlayingCard> _createHandWithScore(int targetScore) {
  if (targetScore == 0) return [];
  
  final cards = <PlayingCard>[];
  int remaining = targetScore;
  
  // Utiliser des cartes de 10 points d'abord
  while (remaining >= 10) {
    cards.add(PlayingCard.create('hearts', '10'));
    remaining -= 10;
  }
  
  // Puis le reste avec une carte de la valeur exacte
  if (remaining > 0) {
    if (remaining == 1) {
      cards.add(PlayingCard.create('hearts', 'A'));
    } else {
      cards.add(PlayingCard.create('hearts', remaining.toString()));
    }
  }
  
  return cards;
}

GameState _createGameState(List<Player> players) {
  for (int i = 0; i < players.length; i++) {
    players[i] = Player(
      id: players[i].id,
      name: players[i].name,
      isHuman: players[i].isHuman,
      position: i,
    )..hand = players[i].hand
     ..knownCards = players[i].knownCards;
  }
  
  return GameState(
    players: players,
    deck: [],
    discardPile: [PlayingCard.create('hearts', '5')],
    currentPlayerIndex: 0,
    phase: GamePhase.ended,
  );
}
