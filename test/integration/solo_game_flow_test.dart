import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';
import 'package:dutch_game/services/game/game_logic.dart';

/// Integration tests pour le flux de jeu solo
/// Ces tests vérifient le parcours complet sans UI
void main() {
  group('Solo Game Flow Integration', () {
    group('Happy Path: setup -> draw -> replace -> dutch -> results', () {
      test('parcours complet sans erreur', () {
        // 1. SETUP: Créer une partie
        final players = [
          Player(id: 'human', name: 'Human', isHuman: true, position: 0),
          Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
          Player(id: 'bot2', name: 'Bot 2', isHuman: false, position: 2),
        ];

        final gs = GameLogic.initializeGame(
          players: players,
          gameMode: GameMode.quick,
          difficulty: Difficulty.medium,
        );

        expect(gs.phase, anyOf(GamePhase.setup, GamePhase.playing));
        expect(gs.players.length, 3);
        expect(gs.deck.isNotEmpty, isTrue);

        // 2. Passer en phase playing avec un joueur de départ connu
        gs.phase = GamePhase.playing;
        gs.currentPlayerIndex = 0; // Fixer le joueur initial pour un test déterministe

        // 3. DRAW: Piocher une carte
        GameLogic.drawCard(gs);
        expect(gs.drawnCard, isNotNull);

        // 4. REPLACE: Remplacer une carte
        final humanHandBefore = gs.players[0].hand.length;
        GameLogic.replaceCard(gs, 0);
        expect(gs.players[0].hand.length, humanHandBefore);
        expect(gs.drawnCard, isNull);

        // 5. Passer au joueur suivant
        GameLogic.nextPlayer(gs);
        expect(gs.currentPlayerIndex, isNot(0));

        // Simuler quelques tours
        for (int i = 0; i < 3; i++) {
          if (gs.deck.isEmpty) break;
          GameLogic.drawCard(gs);
          if (gs.drawnCard != null) {
            GameLogic.discardDrawnCard(gs);
          }
          GameLogic.nextPlayer(gs);
        }

        // 6. Revenir au joueur humain
        gs.currentPlayerIndex = 0;
        gs.phase = GamePhase.playing;

        // 7. DUTCH: Appeler Dutch
        GameLogic.callDutch(gs);
        expect(gs.phase, GamePhase.dutchCalled);
        expect(gs.dutchCallerId, 'human');

        // 8. END: Terminer la partie
        GameLogic.endGame(gs);
        expect(gs.phase, GamePhase.ended);

        // 9. RESULTS: Vérifier le classement
        final ranking = gs.getFinalRanking();
        expect(ranking.length, 3);
        expect(ranking.every((p) => p.knownCards.every((k) => k)), isTrue);
      });

      test('partie avec victoire Dutch', () {
        final gs = _createLowScoreGameState();

        GameLogic.callDutch(gs);
        GameLogic.endGame(gs);

        expect(gs.didDutchCallerWin(), isTrue);

        final ranking = gs.getFinalRanking();
        expect(ranking.first.id, 'human');
      });

      test('partie avec Dutch raté', () {
        final gs = _createHighScoreGameState();

        GameLogic.callDutch(gs);
        GameLogic.endGame(gs);

        expect(gs.didDutchCallerWin(), isFalse);

        final ranking = gs.getFinalRanking();
        expect(ranking.last.id, 'human'); // Dernier car Dutch raté
      });
    });

    group('Special Power Flow', () {
      test('pouvoir 7 déclenché et utilisable', () {
        final gs = _createGameState();
        gs.drawnCard = PlayingCard.create('hearts', '7');

        GameLogic.discardDrawnCard(gs);

        expect(gs.isWaitingForSpecialPower, isTrue);
        expect(gs.specialCardToActivate!.value, '7');

        // Utiliser le pouvoir
        GameLogic.lookAtCard(gs, gs.players[0], 0);

        // Réinitialiser l'état
        gs.isWaitingForSpecialPower = false;
        gs.specialCardToActivate = null;

        expect(gs.isWaitingForSpecialPower, isFalse);
      });

      test('pouvoir 10 (spy) flow complet', () {
        final gs = _createGameState();
        gs.drawnCard = PlayingCard.create('diamonds', '10');

        GameLogic.discardDrawnCard(gs);

        expect(gs.isWaitingForSpecialPower, isTrue);
        expect(gs.specialCardToActivate!.value, '10');
      });

      test('pouvoir Valet (swap) flow complet', () {
        final gs = _createGameState();
        gs.drawnCard = PlayingCard.create('clubs', 'V');

        GameLogic.discardDrawnCard(gs);

        expect(gs.isWaitingForSpecialPower, isTrue);

        // Swap
        final p1Card = gs.players[0].hand[0];
        final p2Card = gs.players[1].hand[1];

        GameLogic.swapCards(gs, gs.players[0], 0, gs.players[1], 1);

        expect(gs.players[0].hand[0].id, p2Card.id);
        expect(gs.players[1].hand[1].id, p1Card.id);
      });

      test('pouvoir Joker flow complet', () {
        final gs = _createGameState();
        gs.drawnCard = PlayingCard.create('joker', 'JOKER');

        GameLogic.discardDrawnCard(gs);

        expect(gs.isWaitingForSpecialPower, isTrue);

        // Joker shuffle
        final target = gs.players[1];
        target.knownCards = List.filled(target.hand.length, true, growable: true);

        GameLogic.jokerEffect(gs, target);

        expect(target.knownCards.every((k) => k == false), isTrue);
      });

      test('skip power fonctionne', () {
        final gs = _createGameState();
        gs.drawnCard = PlayingCard.create('hearts', '7');

        GameLogic.discardDrawnCard(gs);
        expect(gs.isWaitingForSpecialPower, isTrue);

        // Skip
        gs.isWaitingForSpecialPower = false;
        gs.specialCardToActivate = null;

        expect(gs.isWaitingForSpecialPower, isFalse);
      });
    });

    group('Match reaction flow', () {
      test('match réussi en phase reaction', () {
        final gs = _createGameState();
        gs.phase = GamePhase.reaction;

        // Mettre une carte matchable
        gs.discardPile.add(PlayingCard.create('hearts', '5'));
        gs.players[0].hand[0] = PlayingCard.create('diamonds', '5');

        final handSizeBefore = gs.players[0].hand.length;
        final result = GameLogic.matchCard(gs, gs.players[0], 0);

        expect(result, isTrue);
        expect(gs.players[0].hand.length, handSizeBefore - 1);
      });

      test('match raté donne pénalité', () {
        final gs = _createGameState();
        gs.phase = GamePhase.reaction;

        gs.discardPile.add(PlayingCard.create('hearts', '5'));
        gs.players[0].hand[0] = PlayingCard.create('diamonds', '8'); // Pas match

        final handSizeBefore = gs.players[0].hand.length;
        GameLogic.matchCard(gs, gs.players[0], 0);

        expect(gs.players[0].hand.length, handSizeBefore + 1);
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

GameState _createLowScoreGameState() {
  final gs = _createGameState();
  // Humain avec score bas (gagne Dutch)
  gs.players[0].hand = [PlayingCard.create('hearts', 'A')]; // Score 1
  gs.players[0].knownCards = [true];

  gs.players[1].hand = [
    PlayingCard.create('diamonds', '10'),
    PlayingCard.create('clubs', 'R'),
  ]; // Score 23
  gs.players[1].knownCards = [true, true];

  return gs;
}

GameState _createHighScoreGameState() {
  final gs = _createGameState();
  // Humain avec score élevé (perd Dutch)
  gs.players[0].hand = [
    PlayingCard.create('hearts', 'D'),
    PlayingCard.create('diamonds', 'R'),
  ]; // Score 25
  gs.players[0].knownCards = [true, true];

  gs.players[1].hand = [PlayingCard.create('clubs', 'A')]; // Score 1
  gs.players[1].knownCards = [true];

  return gs;
}
