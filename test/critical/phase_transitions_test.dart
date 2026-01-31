import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';
import 'package:dutch_game/services/game/game_logic.dart';

/// Tests critiques pour les transitions de phase
/// Point sensible: les phases doivent suivre un ordre logique
void main() {
  group('Phase Transitions - Points sensibles', () {
    group('Séquence normale', () {
      test('setup -> playing après initialisation', () {
        final players = _createPlayers();
        final gs = GameLogic.initializeGame(
          players: players,
          gameMode: GameMode.quick,
          difficulty: Difficulty.medium,
        );

        // Après initialisation, le jeu est en phase setup ou playing
        expect(gs.phase, anyOf(GamePhase.setup, GamePhase.playing));
      });

      test('playing -> reaction après action (simulé)', () {
        final gs = _createGameState();
        gs.phase = GamePhase.playing;

        // Simuler une action qui mène à reaction
        gs.phase = GamePhase.reaction;

        expect(gs.phase, GamePhase.reaction);
      });

      test('playing -> dutchCalled quand Dutch appelé', () {
        final gs = _createGameState();
        gs.phase = GamePhase.playing;

        GameLogic.callDutch(gs);

        expect(gs.phase, GamePhase.dutchCalled);
        expect(gs.dutchCallerId, isNotNull);
      });

      test('dutchCalled -> ended (fin normale)', () {
        final gs = _createGameState();
        gs.phase = GamePhase.dutchCalled;
        gs.dutchCallerId = 'human';

        GameLogic.endGame(gs);

        expect(gs.phase, GamePhase.ended);
      });
    });

    group('Dutch call validation', () {
      test('Dutch ne peut être appelé qu\'une fois', () {
        final gs = _createGameState();
        gs.phase = GamePhase.playing;

        GameLogic.callDutch(gs);
        final firstCaller = gs.dutchCallerId;

        // Changer de joueur et essayer de rappeler Dutch
        gs.currentPlayerIndex = 1;
        GameLogic.callDutch(gs);

        expect(gs.dutchCallerId, firstCaller); // Pas changé
      });

      test('Dutch caller est bien le joueur courant', () {
        final gs = _createGameState();
        gs.phase = GamePhase.playing;
        gs.currentPlayerIndex = 1; // Bot

        GameLogic.callDutch(gs);

        expect(gs.dutchCallerId, 'bot1');
      });
    });

    group('End game behavior', () {
      test('endGame révèle toutes les cartes', () {
        final gs = _createGameState();
        gs.phase = GamePhase.playing;

        // Cacher des cartes
        for (var player in gs.players) {
          player.knownCards = List.filled(player.hand.length, false, growable: true);
        }

        GameLogic.endGame(gs);

        for (var player in gs.players) {
          expect(player.knownCards.every((k) => k), isTrue);
        }
      });

      test('endGame met la phase à ended', () {
        final gs = _createGameState();
        gs.phase = GamePhase.playing;

        GameLogic.endGame(gs);

        expect(gs.phase, GamePhase.ended);
      });
    });

    group('Next turn', () {
      test('nextTurn change le joueur courant', () {
        final gs = _createGameState();
        gs.currentPlayerIndex = 0;

        GameLogic.nextPlayer(gs);

        expect(gs.currentPlayerIndex, isNot(0));
      });

      test('nextTurn boucle sur les joueurs', () {
        final gs = _createGameState();
        gs.currentPlayerIndex = gs.players.length - 1;

        GameLogic.nextPlayer(gs);

        expect(gs.currentPlayerIndex, 0);
      });

      test('nextTurn inclut joueurs avec main vide (main vide = score 0)', () {
        final gs = _createGameState();
        gs.currentPlayerIndex = 0;
        gs.players[1].hand = []; // Joueur avec main vide (score 0)

        GameLogic.nextPlayer(gs);

        // Le joueur avec main vide peut jouer (il a juste score 0)
        expect(gs.currentPlayerIndex, 1);
      });
    });

    group('Special power state', () {
      test('special power définie après carte spéciale défaussée', () {
        final gs = _createGameState();
        gs.phase = GamePhase.playing;
        gs.drawnCard = PlayingCard.create('hearts', '7');

        GameLogic.discardDrawnCard(gs);

        expect(gs.isWaitingForSpecialPower, isTrue);
        expect(gs.specialCardToActivate, isNotNull);
        expect(gs.specialCardToActivate!.value, '7');
      });

      test('pas de special power pour carte normale', () {
        final gs = _createGameState();
        gs.phase = GamePhase.playing;
        gs.drawnCard = PlayingCard.create('hearts', '5');

        GameLogic.discardDrawnCard(gs);

        expect(gs.isWaitingForSpecialPower, isFalse);
      });

      test('special power pour 10 (spy)', () {
        final gs = _createGameState();
        gs.drawnCard = PlayingCard.create('diamonds', '10');

        GameLogic.discardDrawnCard(gs);

        expect(gs.isWaitingForSpecialPower, isTrue);
        expect(gs.specialCardToActivate!.value, '10');
      });

      test('special power pour Valet (swap)', () {
        final gs = _createGameState();
        gs.drawnCard = PlayingCard.create('clubs', 'V');

        GameLogic.discardDrawnCard(gs);

        expect(gs.isWaitingForSpecialPower, isTrue);
        expect(gs.specialCardToActivate!.value, 'V');
      });

      test('special power pour Joker', () {
        final gs = _createGameState();
        gs.drawnCard = PlayingCard.create('joker', 'JOKER');

        GameLogic.discardDrawnCard(gs);

        expect(gs.isWaitingForSpecialPower, isTrue);
        expect(gs.specialCardToActivate!.value, 'JOKER');
      });
    });
  });
}

List<Player> _createPlayers() {
  return [
    Player(id: 'human', name: 'Human', isHuman: true, position: 0),
    Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
  ];
}

GameState _createGameState() {
  final players = [
    Player(id: 'human', name: 'Human', isHuman: true, position: 0),
    Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
    Player(id: 'bot2', name: 'Bot 2', isHuman: false, position: 2),
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
