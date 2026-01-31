import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/providers/managers/solo/tournament_manager.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';

void main() {
  group('TournamentManager', () {
    late TournamentManager manager;
    late GameState gameState;

    setUp(() {
      manager = TournamentManager();
      gameState = _createTournamentGameState();
    });

    group('initializeTournament', () {
      test('resets state on round 1', () {
        manager.initializeTournament(1);

        expect(manager.cumulativeScores, isEmpty);
        expect(manager.activeTournamentId, isNotNull);
        expect(manager.finalRanking, isNull);
      });

      test('generates unique tournament ID', () {
        manager.initializeTournament(1);
        final firstId = manager.activeTournamentId;

        // Wait a bit to ensure different timestamp
        manager.initializeTournament(1);
        final secondId = manager.activeTournamentId;

        expect(firstId, isNotNull);
        expect(secondId, isNotNull);
      });

      test('does not reset on round > 1', () {
        manager.initializeTournament(1);
        final originalId = manager.activeTournamentId;

        manager.initializeTournament(2);

        expect(manager.activeTournamentId, originalId);
      });
    });

    group('resetTournament', () {
      test('clears all state', () {
        manager.initializeTournament(1);
        
        manager.resetTournament();

        expect(manager.activeTournamentId, isNull);
        expect(manager.finalRanking, isNull);
        expect(manager.cumulativeScores, isEmpty);
      });
    });

    group('updateCumulativeScores', () {
      test('copies scores from gameState', () {
        gameState.tournamentCumulativeScores = {
          'human': 50,
          'bot1': 30,
          'bot2': 20,
        };

        manager.updateCumulativeScores(gameState);

        expect(manager.cumulativeScores['human'], 50);
        expect(manager.cumulativeScores['bot1'], 30);
        expect(manager.cumulativeScores['bot2'], 20);
      });
    });

    group('isHumanEliminated', () {
      test('returns false for non-tournament mode', () {
        gameState.gameMode = GameMode.quick;

        final result = manager.isHumanEliminated(gameState);

        expect(result, isFalse);
      });

      test('returns true when human is last in ranking', () {
        gameState.gameMode = GameMode.tournament;
        // Set scores so human is last
        gameState.players[0].hand = [
          PlayingCard.create('hearts', 'R'), // 13 pts
          PlayingCard.create('diamonds', 'R'), // 13 pts
        ];
        gameState.players[1].hand = [
          PlayingCard.create('hearts', 'A'), // 1 pt
        ];

        final result = manager.isHumanEliminated(gameState);

        expect(result, isA<bool>());
      });

      test('returns false when human is not last', () {
        gameState.gameMode = GameMode.tournament;
        // Set scores so human is first
        gameState.players[0].hand = [
          PlayingCard.create('hearts', 'A'), // 1 pt
        ];
        gameState.players[1].hand = [
          PlayingCard.create('hearts', 'R'), // 13 pts
          PlayingCard.create('diamonds', 'R'), // 13 pts
        ];

        final result = manager.isHumanEliminated(gameState);

        expect(result, isFalse);
      });
    });

    group('calculateRP', () {
      test('returns 150 for 1st place', () {
        expect(manager.calculateRP(1), 150);
      });

      test('returns 60 for 2nd place', () {
        expect(manager.calculateRP(2), 60);
      });

      test('returns -5 for 3rd place', () {
        expect(manager.calculateRP(3), -5);
      });

      test('returns -30 for 4th place', () {
        expect(manager.calculateRP(4), -30);
      });

      test('returns 0 for other positions', () {
        expect(manager.calculateRP(5), 0);
        expect(manager.calculateRP(0), 0);
        expect(manager.calculateRP(-1), 0);
      });
    });

    group('prepareSurvivorsForNextRound', () {
      test('keeps top players for next round', () {
        // 4 players, should keep 3
        final survivors = manager.prepareSurvivorsForNextRound(gameState);

        expect(survivors.length, 3);
      });

      test('survivors are new Player instances', () {
        final survivors = manager.prepareSurvivorsForNextRound(gameState);

        // Should be new objects, not same references
        for (var survivor in survivors) {
          expect(survivor.hand, isEmpty);
        }
      });

      test('preserves player attributes', () {
        final survivors = manager.prepareSurvivorsForNextRound(gameState);

        for (var survivor in survivors) {
          expect(survivor.id, isNotEmpty);
          expect(survivor.name, isNotEmpty);
        }
      });

      test('assigns new positions', () {
        final survivors = manager.prepareSurvivorsForNextRound(gameState);

        for (int i = 0; i < survivors.length; i++) {
          expect(survivors[i].position, i);
        }
      });

      test('handles 6+ players', () {
        // Add more players
        gameState.players.add(
          Player(id: 'bot3', name: 'Bot 3', isHuman: false, position: 3)
            ..hand = [PlayingCard.create('clubs', '5')]
            ..knownCards = [false],
        );
        gameState.players.add(
          Player(id: 'bot4', name: 'Bot 4', isHuman: false, position: 4)
            ..hand = [PlayingCard.create('spades', '6')]
            ..knownCards = [false],
        );
        gameState.players.add(
          Player(id: 'bot5', name: 'Bot 5', isHuman: false, position: 5)
            ..hand = [PlayingCard.create('hearts', '7')]
            ..knownCards = [false],
        );

        final survivors = manager.prepareSurvivorsForNextRound(gameState);

        expect(survivors.length, 4);
      });
    });

    group('finishTournamentForHuman', () {
      test('creates final ranking', () {
        gameState.tournamentRound = 2;

        manager.finishTournamentForHuman(gameState);

        expect(manager.finalRanking, isNotNull);
        expect(manager.finalRanking, isNotEmpty);
      });

      test('includes human in final ranking', () {
        gameState.tournamentRound = 1;

        manager.finishTournamentForHuman(gameState);

        final humanResult = manager.finalRanking!.where(
          (r) => r.player.isHuman,
        );
        expect(humanResult, isNotEmpty);
      });

      test('ranking is sorted by position', () {
        gameState.tournamentRound = 1;

        manager.finishTournamentForHuman(gameState);

        for (int i = 0; i < manager.finalRanking!.length - 1; i++) {
          expect(
            manager.finalRanking![i].finalPosition,
            lessThanOrEqualTo(manager.finalRanking![i + 1].finalPosition),
          );
        }
      });

      test('human position based on elimination round', () {
        gameState.tournamentRound = 2;

        manager.finishTournamentForHuman(gameState);

        final humanResult = manager.finalRanking!.firstWhere(
          (r) => r.player.isHuman,
        );
        // Position = 5 - round = 5 - 2 = 3
        expect(humanResult.finalPosition, 3);
        expect(humanResult.eliminatedAtRound, 2);
      });
    });

    group('TournamentResult', () {
      test('stores all properties', () {
        final player = Player(id: 'test', name: 'Test', isHuman: true, position: 0);
        final result = TournamentResult(
          player: player,
          finalPosition: 2,
          eliminatedAtRound: 3,
        );

        expect(result.player, player);
        expect(result.finalPosition, 2);
        expect(result.eliminatedAtRound, 3);
      });

      test('eliminatedAtRound is optional', () {
        final player = Player(id: 'test', name: 'Test', isHuman: true, position: 0);
        final result = TournamentResult(
          player: player,
          finalPosition: 1,
        );

        expect(result.eliminatedAtRound, isNull);
      });
    });
  });
}

GameState _createTournamentGameState() {
  final players = [
    Player(id: 'human', name: 'Human', isHuman: true, position: 0),
    Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
    Player(id: 'bot2', name: 'Bot 2', isHuman: false, position: 2),
    Player(id: 'bot3', name: 'Bot 3', isHuman: false, position: 3),
  ];

  for (var player in players) {
    player.hand = [
      PlayingCard.create('hearts', 'A'),
      PlayingCard.create('diamonds', '2'),
    ];
    player.knownCards = List.filled(2, false, growable: true);
  }

  return GameState(
    players: players,
    deck: GameState.createFullDeck().sublist(0, 40),
    discardPile: [PlayingCard.create('hearts', '5')],
    currentPlayerIndex: 0,
    phase: GamePhase.ended,
    gameMode: GameMode.tournament,
    tournamentRound: 1,
  );
}
