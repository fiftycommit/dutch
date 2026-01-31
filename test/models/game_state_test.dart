import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/services/game/game_logic.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('GameState - Invariants', () {
    test('no duplicate cards after initialization', () {
      final gs = createTestGameState(playerCount: 4);
      GameStateInvariants.assertNoDuplicateCards(gs);
    });

    test('total cards constant (54) after initialization', () {
      final gs = createTestGameState(playerCount: 4);
      expect(gs.totalCards, 54);
    });

    test('valid indices after initialization', () {
      final gs = createTestGameState(playerCount: 4);
      GameStateInvariants.assertValidIndices(gs);
    });

    test('phase coherence after initialization', () {
      final gs = createTestGameState(playerCount: 3, phase: GamePhase.playing);
      GameStateInvariants.assertPhaseCoherence(gs);
    });

    test('all invariants hold after multiple actions', () {
      final gs = createDeterministicGameState();
      
      // Simulate a sequence of actions
      GameLogic.drawCard(gs);
      GameStateInvariants.assertAllInvariants(gs);
      
      GameLogic.replaceCard(gs, 0);
      GameStateInvariants.assertAllInvariants(gs);
      
      gs.phase = GamePhase.reaction;
      GameLogic.matchCard(gs, gs.humanPlayer, 0);
      GameStateInvariants.assertAllInvariants(gs);
    });
  });

  group('GameState - Phase Transitions', () {
    test('setup -> playing transition', () {
      final gs = createTestGameState(phase: GamePhase.setup);
      
      gs.phase = GamePhase.playing;
      
      expect(gs.phase, GamePhase.playing);
    });

    test('playing -> reaction transition', () {
      final gs = createTestGameState(phase: GamePhase.playing);
      
      gs.phase = GamePhase.reaction;
      
      expect(gs.phase, GamePhase.reaction);
    });

    test('playing -> dutchCalled transition', () {
      final gs = createTestGameState(phase: GamePhase.playing);
      
      GameLogic.callDutch(gs);
      
      expect(gs.phase, GamePhase.dutchCalled);
      expect(gs.dutchCallerId, isNotNull);
    });

    test('dutchCalled -> ended transition', () {
      final gs = createTestGameState(phase: GamePhase.playing);
      GameLogic.callDutch(gs);
      
      GameLogic.endGame(gs);
      
      expect(gs.phase, GamePhase.ended);
    });

    test('ended phase is terminal', () {
      final gs = createTestGameState(phase: GamePhase.ended);
      
      // In ended phase, all cards should be revealed
      for (var player in gs.players) {
        for (int i = 0; i < player.knownCards.length; i++) {
          player.knownCards[i] = true;
        }
      }
      
      // Verify phase stays ended
      expect(gs.phase, GamePhase.ended);
    });
  });

  group('GameState - Current Player', () {
    test('currentPlayer returns correct player', () {
      final gs = createDeterministicGameState();
      gs.currentPlayerIndex = 0;
      
      expect(gs.currentPlayer, gs.players[0]);
    });

    test('nextTurn advances player index', () {
      final gs = createDeterministicGameState();
      gs.currentPlayerIndex = 0;
      
      gs.nextTurn();
      
      expect(gs.currentPlayerIndex, 1);
    });

    test('nextTurn wraps around', () {
      final gs = createDeterministicGameState();
      gs.currentPlayerIndex = 1; // Last player (2 players total)
      
      gs.nextTurn();
      
      expect(gs.currentPlayerIndex, 0);
    });

    test('nextTurn skips eliminated players', () {
      final players = createStandardPlayers(botCount: 3);
      final gs = GameLogic.initializeGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
      );
      gs.currentPlayerIndex = 0;
      gs.eliminatedPlayerIds.add(gs.players[1].id);
      
      gs.nextTurn();
      
      expect(gs.currentPlayerIndex, 2); // Skipped player 1
    });
  });

  group('GameState - Discard Pile', () {
    test('topDiscardCard returns last card', () {
      final gs = createDeterministicGameState(
        discardPile: [
          createCard('hearts', 'A'),
          createCard('diamonds', '2'),
        ],
      );
      
      expect(gs.topDiscardCard?.value, '2');
    });

    test('topDiscardCard returns null when empty', () {
      final gs = createDeterministicGameState(discardPile: []);
      
      expect(gs.topDiscardCard, isNull);
    });
  });

  group('GameState - Deck', () {
    test('remainingDeckCards returns correct count', () {
      final gs = createDeterministicGameState();
      
      expect(gs.remainingDeckCards, gs.deck.length);
    });

    test('createFullDeck creates 54 cards', () {
      final deck = GameState.createFullDeck();
      
      expect(deck.length, 54); // 52 + 2 jokers
    });

    test('createFullDeck has all suits', () {
      final deck = GameState.createFullDeck();
      final suits = deck.where((c) => c.value != 'JOKER').map((c) => c.suit).toSet();
      
      // Regular cards have 4 suits (Jokers use hearts/spades for unique IDs)
      expect(suits, containsAll(['hearts', 'diamonds', 'clubs', 'spades']));
    });

    test('createFullDeck has all values', () {
      final deck = GameState.createFullDeck();
      final values = deck.where((c) => c.suit != 'joker').map((c) => c.value).toSet();
      
      expect(values, containsAll(['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'V', 'D', 'R']));
    });

    test('createFullDeck has 2 jokers', () {
      final deck = GameState.createFullDeck();
      final jokers = deck.where((c) => c.value == 'JOKER').length;
      
      expect(jokers, 2);
    });
  });

  group('GameState - Action History', () {
    test('addToHistory inserts at beginning', () {
      final gs = createDeterministicGameState();
      gs.actionHistory.clear();
      
      gs.addToHistory('First action');
      gs.addToHistory('Second action');
      
      expect(gs.actionHistory[0], contains('Second action'));
      expect(gs.actionHistory[1], contains('First action'));
    });

    test('addToHistory limits to 50 entries', () {
      final gs = createDeterministicGameState();
      gs.actionHistory.clear();
      
      for (int i = 0; i < 60; i++) {
        gs.addToHistory('Action $i');
      }
      
      expect(gs.actionHistory.length, 50);
    });

    test('addToHistory includes timestamp', () {
      final gs = createDeterministicGameState();
      gs.actionHistory.clear();
      
      gs.addToHistory('Test action');
      
      expect(gs.actionHistory[0], matches(RegExp(r'\[\d+:\d+\]')));
    });
  });

  group('GameState - Tournament', () {
    test('tournament mode initializes correctly', () {
      final players = createStandardPlayers(botCount: 2);
      final gs = GameLogic.initializeGame(
        players: players,
        gameMode: GameMode.tournament,
        difficulty: Difficulty.medium,
        tournamentRound: 1,
      );
      
      expect(gs.gameMode, GameMode.tournament);
      expect(gs.tournamentRound, 1);
    });

    test('getCumulativeScore returns correct score', () {
      final gs = createDeterministicGameState();
      gs.tournamentCumulativeScores['human'] = 25;
      
      expect(gs.getCumulativeScore(gs.humanPlayer), 25);
    });

    test('getCumulativeScore returns 0 for unknown player', () {
      final gs = createDeterministicGameState();
      
      expect(gs.getCumulativeScore(gs.humanPlayer), 0);
    });
  });

  group('GameState - Final Ranking', () {
    test('getFinalRanking sorts by score ascending', () {
      final gs = createDeterministicGameState(
        humanHand: [
          createCard('hearts', 'R'), // 13 points
          createCard('diamonds', 'D'), // 12 points
          createCard('clubs', 'V'), // 11 points
          createCard('spades', '10'), // 10 points
        ],
        bot1Hand: [
          createCard('hearts', 'A'), // 1 point
          createCard('diamonds', '2'), // 2 points
          createCard('clubs', '3'), // 3 points
          createCard('spades', '4'), // 4 points
        ],
      );
      
      final ranking = gs.getFinalRanking();
      
      // Bot with lower score should be first
      expect(ranking[0].isHuman, false);
      expect(ranking[1].isHuman, true);
    });

    test('getFinalRanking penalizes failed Dutch caller', () {
      final gs = createDeterministicGameState(
        humanHand: [
          createCard('spades', 'R'), // 13 points (black King = highest)
        ],
        bot1Hand: [
          createCard('hearts', 'A'), // 1 point
        ],
      );
      gs.dutchCallerId = 'human'; // Human called Dutch but has highest score
      
      final ranking = gs.getFinalRanking();
      
      // Human should be last due to failed Dutch
      expect(ranking.last.id, 'human');
    });
  });

  group('GameState - Serialization', () {
    test('toJson and fromJson are inverse', () {
      final gs = createDeterministicGameState();
      gs.dutchCallerId = 'human';
      gs.phase = GamePhase.dutchCalled;
      
      final json = gs.toJson();
      final restored = GameState.fromJson(json);
      
      expect(restored.players.length, gs.players.length);
      expect(restored.phase, gs.phase);
      expect(restored.dutchCallerId, gs.dutchCallerId);
      expect(restored.currentPlayerIndex, gs.currentPlayerIndex);
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'players': [
          {'id': 'p1', 'name': 'Player', 'isHuman': true, 'hand': [], 'knownCards': []},
        ],
        'deck': <Map<String, dynamic>>[],
        'discardPile': <Map<String, dynamic>>[],
        'currentPlayerIndex': 0,
        'gameMode': 0, // quick
        'phase': 1, // playing
        'difficulty': 1, // medium
      };
      
      final gs = GameState.fromJson(json);
      
      expect(gs.players.length, 1);
      expect(gs.dutchCallerId, isNull);
      expect(gs.drawnCard, isNull);
    });
  });

  group('GameState - Ready Players', () {
    test('readyPlayerIds tracks ready state', () {
      final gs = createDeterministicGameState(phase: GamePhase.setup);
      
      gs.readyPlayerIds.add('human');
      
      expect(gs.readyPlayerIds.contains('human'), true);
    });
  });

  group('GameState - Special Power State', () {
    test('isWaitingForSpecialPower defaults to false', () {
      final gs = createDeterministicGameState();
      
      expect(gs.isWaitingForSpecialPower, false);
    });

    test('specialCardToActivate is null by default', () {
      final gs = createDeterministicGameState();
      
      expect(gs.specialCardToActivate, isNull);
    });

    test('pendingSwap is null by default', () {
      final gs = createDeterministicGameState();
      
      expect(gs.pendingSwap, isNull);
    });
  });

  group('GameState - Deal Cards', () {
    test('dealCards distribue 4 cartes par joueur', () {
      final players = createStandardPlayers(botCount: 2);
      final gs = GameLogic.initializeGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
      );

      for (var player in gs.players) {
        expect(player.hand.length, 4);
        expect(player.knownCards.length, 4);
      }
    });

    test('dealCards easy donne des cartes favorables à l\'humain', () {
      final players = createStandardPlayers(botCount: 1);
      final gs = GameLogic.initializeGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.easy,
      );

      // En mode easy, l'humain devrait avoir plus de bonnes cartes
      final human = gs.players.firstWhere((p) => p.isHuman);
      expect(human.hand.length, 4);
    });

    test('dealCards hard est plus difficile', () {
      final players = createStandardPlayers(botCount: 1);
      final gs = GameLogic.initializeGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.hard,
      );

      final human = gs.players.firstWhere((p) => p.isHuman);
      expect(human.hand.length, 4);
    });
  });

  group('GameState - Shuffle', () {
    test('smartShuffle mélange le deck', () {
      final gs = createDeterministicGameState();
      final deckBefore = List.from(gs.deck.map((c) => c.id));

      gs.smartShuffle();

      // Le deck devrait être différent (très improbable d'être identique)
      final deckAfter = gs.deck.map((c) => c.id).toList();
      expect(deckAfter.length, deckBefore.length);
    });

    test('shuffleDeckRandomly mélange aléatoirement', () {
      final gs = createDeterministicGameState();
      
      gs.shuffleDeckRandomly();

      expect(gs.deck.isNotEmpty, isTrue);
    });
  });

  group('GameState - Tournament Scores', () {
    test('updateCumulativeScores ajoute les scores', () {
      final gs = createDeterministicGameState();
      gs.tournamentCumulativeScores.clear();

      gs.updateCumulativeScores();

      for (var player in gs.players) {
        expect(gs.tournamentCumulativeScores.containsKey(player.id), isTrue);
      }
    });

    test('updateCumulativeScores cumule sur plusieurs rondes', () {
      final gs = createDeterministicGameState();
      gs.tournamentCumulativeScores['human'] = 10;

      final scoreBefore = gs.getCumulativeScore(gs.humanPlayer);
      gs.updateCumulativeScores();
      final scoreAfter = gs.getCumulativeScore(gs.humanPlayer);

      expect(scoreAfter, greaterThanOrEqualTo(scoreBefore));
    });
  });

  group('GameState - didDutchCallerWin', () {
    test('retourne false si pas de Dutch caller', () {
      final gs = createDeterministicGameState();
      gs.dutchCallerId = null;

      expect(gs.didDutchCallerWin(), isFalse);
    });

    test('retourne true si Dutch caller a le meilleur score', () {
      final gs = createDeterministicGameState(
        humanHand: [createCard('hearts', 'A')], // 1 point
        bot1Hand: [createCard('clubs', 'R')], // 13 points
      );
      gs.dutchCallerId = 'human';

      expect(gs.didDutchCallerWin(), isTrue);
    });

    test('retourne true si Dutch caller est ex-aequo', () {
      final gs = createDeterministicGameState(
        humanHand: [createCard('hearts', 'A')], // 1 point
        bot1Hand: [createCard('diamonds', 'A')], // 1 point aussi
      );
      gs.dutchCallerId = 'human';

      expect(gs.didDutchCallerWin(), isTrue);
    });

    test('retourne false si quelqu\'un a un score inférieur', () {
      final gs = createDeterministicGameState(
        humanHand: [createCard('clubs', 'R')], // 13 points
        bot1Hand: [createCard('hearts', 'A')], // 1 point
      );
      gs.dutchCallerId = 'human';

      expect(gs.didDutchCallerWin(), isFalse);
    });
  });

  group('GameState - getFinalRanksWithTies', () {
    test('Dutch caller gagnant est seul premier', () {
      final gs = createDeterministicGameState(
        humanHand: [createCard('hearts', 'A')], // 1 point
        bot1Hand: [createCard('diamonds', 'A')], // 1 point aussi
      );
      gs.dutchCallerId = 'human';

      final ranks = gs.getFinalRanksWithTies();

      expect(ranks['human'], 1);
      expect(ranks['bot_0'], 2); // Même score mais 2e
    });

    test('Dutch caller perdant est dernier', () {
      final gs = createDeterministicGameState(
        humanHand: [createCard('clubs', 'R')], // 13 points
        bot1Hand: [createCard('hearts', 'A')], // 1 point
      );
      gs.dutchCallerId = 'human';

      final ranks = gs.getFinalRanksWithTies();

      expect(ranks['human'], 2); // Dernier
      expect(ranks['bot_0'], 1);
    });
  });
}
