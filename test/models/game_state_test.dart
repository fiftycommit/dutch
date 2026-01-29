import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/card.dart';

void main() {
  group('GameState', () {
    List<Player> createTestPlayers() {
      return [
        Player(id: 'p1', name: 'Player 1', isHuman: true, position: 0),
        Player(id: 'p2', name: 'Player 2', isHuman: true, position: 1),
        Player(id: 'bot1', name: 'Bot', isHuman: false, position: 2),
      ];
    }

    group('constructor', () {
      test('creates with required fields', () {
        final state = GameState(
          players: createTestPlayers(),
          deck: [],
          discardPile: [],
        );

        expect(state.players.length, 3);
        expect(state.currentPlayerIndex, 0);
        expect(state.phase, GamePhase.setup);
        expect(state.gameMode, GameMode.quick);
      });

      test('initializes empty lists', () {
        final state = GameState(
          players: createTestPlayers(),
          deck: [],
          discardPile: [],
        );

        expect(state.eliminatedPlayerIds, isEmpty);
        expect(state.actionHistory, isEmpty);
        expect(state.readyPlayerIds, isEmpty);
      });
    });

    group('currentPlayer', () {
      test('returns player at currentPlayerIndex', () {
        final players = createTestPlayers();
        final state = GameState(
          players: players,
          deck: [],
          discardPile: [],
          currentPlayerIndex: 1,
        );

        expect(state.currentPlayer.id, 'p2');
      });
    });

    group('topDiscardCard', () {
      test('returns last card in discard pile', () {
        final card = PlayingCard.create('hearts', '5');
        final state = GameState(
          players: createTestPlayers(),
          deck: [],
          discardPile: [
            PlayingCard.create('spades', '3'),
            card,
          ],
        );

        expect(state.topDiscardCard, card);
      });

      test('returns null for empty discard pile', () {
        final state = GameState(
          players: createTestPlayers(),
          deck: [],
          discardPile: [],
        );

        expect(state.topDiscardCard, isNull);
      });
    });

    group('nextTurn', () {
      test('advances to next player', () {
        final state = GameState(
          players: createTestPlayers(),
          deck: [],
          discardPile: [],
          currentPlayerIndex: 0,
        );

        state.nextTurn();
        expect(state.currentPlayerIndex, 1);
      });

      test('wraps around to first player', () {
        final state = GameState(
          players: createTestPlayers(),
          deck: [],
          discardPile: [],
          currentPlayerIndex: 2,
        );

        state.nextTurn();
        expect(state.currentPlayerIndex, 0);
      });

      test('skips eliminated players', () {
        final state = GameState(
          players: createTestPlayers(),
          deck: [],
          discardPile: [],
          currentPlayerIndex: 0,
          eliminatedPlayerIds: ['p2'],
        );

        state.nextTurn();
        expect(state.currentPlayerIndex, 2);
      });
    });

    group('addToHistory', () {
      test('adds action with timestamp', () {
        final state = GameState(
          players: createTestPlayers(),
          deck: [],
          discardPile: [],
        );

        state.addToHistory('Test action');

        expect(state.actionHistory.length, 1);
        expect(state.actionHistory[0], contains('Test action'));
        expect(state.actionHistory[0], contains('['));
      });

      test('prepends new actions', () {
        final state = GameState(
          players: createTestPlayers(),
          deck: [],
          discardPile: [],
        );

        state.addToHistory('First');
        state.addToHistory('Second');

        expect(state.actionHistory[0], contains('Second'));
        expect(state.actionHistory[1], contains('First'));
      });

      test('limits to 50 entries', () {
        final state = GameState(
          players: createTestPlayers(),
          deck: [],
          discardPile: [],
        );

        for (int i = 0; i < 60; i++) {
          state.addToHistory('Action $i');
        }

        expect(state.actionHistory.length, 50);
      });
    });

    group('createFullDeck', () {
      test('creates 54 cards', () {
        final deck = GameState.createFullDeck();
        expect(deck.length, 54);
      });

      test('includes 4 suits with 13 cards each', () {
        final deck = GameState.createFullDeck();
        final suits = ['hearts', 'diamonds', 'clubs', 'spades'];

        for (final suit in suits) {
          final suitCards = deck.where((c) => c.suit == suit).length;
          expect(suitCards, 13);
        }
      });

      test('includes 2 jokers', () {
        final deck = GameState.createFullDeck();
        final jokers = deck.where((c) => c.value == 'JOKER').length;
        expect(jokers, 2);
      });
    });

    group('getFinalRanking', () {
      test('sorts players by score', () {
        final players = [
          Player(id: 'p1', name: 'P1', isHuman: true, hand: [
            PlayingCard.create('hearts', '10'), // 10 pts
          ]),
          Player(id: 'p2', name: 'P2', isHuman: true, hand: [
            PlayingCard.create('hearts', '3'), // 3 pts
          ]),
          Player(id: 'p3', name: 'P3', isHuman: true, hand: [
            PlayingCard.create('hearts', '7'), // 7 pts
          ]),
        ];

        final state = GameState(
          players: players,
          deck: [],
          discardPile: [],
        );

        final ranking = state.getFinalRanking();

        expect(ranking[0].id, 'p2'); // 3 pts
        expect(ranking[1].id, 'p3'); // 7 pts
        expect(ranking[2].id, 'p1'); // 10 pts
      });

      test('Dutch caller wins with equal score', () {
        final players = [
          Player(id: 'p1', name: 'P1', isHuman: true, hand: [
            PlayingCard.create('hearts', '5'),
          ]),
          Player(id: 'p2', name: 'P2', isHuman: true, hand: [
            PlayingCard.create('spades', '5'),
          ]),
        ];

        final state = GameState(
          players: players,
          deck: [],
          discardPile: [],
          dutchCallerId: 'p1',
        );

        final ranking = state.getFinalRanking();
        expect(ranking[0].id, 'p1');
      });

      test('Failed Dutch caller is last', () {
        final players = [
          Player(id: 'p1', name: 'P1', isHuman: true, hand: [
            PlayingCard.create('hearts', '10'),
          ]),
          Player(id: 'p2', name: 'P2', isHuman: true, hand: [
            PlayingCard.create('spades', '3'),
          ]),
        ];

        final state = GameState(
          players: players,
          deck: [],
          discardPile: [],
          dutchCallerId: 'p1',
        );

        final ranking = state.getFinalRanking();
        expect(ranking.last.id, 'p1');
      });
    });

    group('didDutchCallerWin', () {
      test('returns true when caller has lowest score', () {
        final players = [
          Player(id: 'p1', name: 'P1', isHuman: true, hand: [
            PlayingCard.create('hearts', '3'),
          ]),
          Player(id: 'p2', name: 'P2', isHuman: true, hand: [
            PlayingCard.create('spades', '10'),
          ]),
        ];

        final state = GameState(
          players: players,
          deck: [],
          discardPile: [],
          dutchCallerId: 'p1',
        );

        expect(state.didDutchCallerWin(), true);
      });

      test('returns true when caller ties for lowest', () {
        final players = [
          Player(id: 'p1', name: 'P1', isHuman: true, hand: [
            PlayingCard.create('hearts', '5'),
          ]),
          Player(id: 'p2', name: 'P2', isHuman: true, hand: [
            PlayingCard.create('spades', '5'),
          ]),
        ];

        final state = GameState(
          players: players,
          deck: [],
          discardPile: [],
          dutchCallerId: 'p1',
        );

        expect(state.didDutchCallerWin(), true);
      });

      test('returns false when caller does not have lowest', () {
        final players = [
          Player(id: 'p1', name: 'P1', isHuman: true, hand: [
            PlayingCard.create('hearts', '10'),
          ]),
          Player(id: 'p2', name: 'P2', isHuman: true, hand: [
            PlayingCard.create('spades', '3'),
          ]),
        ];

        final state = GameState(
          players: players,
          deck: [],
          discardPile: [],
          dutchCallerId: 'p1',
        );

        expect(state.didDutchCallerWin(), false);
      });

      test('returns false when no Dutch caller', () {
        final state = GameState(
          players: createTestPlayers(),
          deck: [],
          discardPile: [],
        );

        expect(state.didDutchCallerWin(), false);
      });
    });

    group('tournament scores', () {
      test('getCumulativeScore returns score', () {
        final players = createTestPlayers();
        final state = GameState(
          players: players,
          deck: [],
          discardPile: [],
          tournamentCumulativeScores: {'p1': 50, 'p2': 30},
        );

        expect(state.getCumulativeScore(players[0]), 50);
        expect(state.getCumulativeScore(players[1]), 30);
      });

      test('getCumulativeScore returns 0 for unknown player', () {
        final players = createTestPlayers();
        final state = GameState(
          players: players,
          deck: [],
          discardPile: [],
        );

        expect(state.getCumulativeScore(players[2]), 0);
      });

      test('updateCumulativeScores adds round scores', () {
        final players = [
          Player(id: 'p1', name: 'P1', isHuman: true, hand: [
            PlayingCard.create('hearts', '5'),
          ]),
          Player(id: 'p2', name: 'P2', isHuman: true, hand: [
            PlayingCard.create('spades', '10'),
          ]),
        ];

        final state = GameState(
          players: players,
          deck: [],
          discardPile: [],
          tournamentCumulativeScores: {'p1': 10},
        );

        state.updateCumulativeScores();

        expect(state.tournamentCumulativeScores['p1'], 15);
        expect(state.tournamentCumulativeScores['p2'], 10);
      });

      test('isPlayerNearElimination checks threshold', () {
        final players = createTestPlayers();
        final state = GameState(
          players: players,
          deck: [],
          discardPile: [],
          gameMode: GameMode.tournament,
          tournamentCumulativeScores: {'p1': 85, 'p2': 50},
        );

        expect(state.isPlayerNearElimination(players[0]), true);
        expect(state.isPlayerNearElimination(players[1]), false);
      });

      test('isPlayerNearElimination returns false in quick mode', () {
        final players = createTestPlayers();
        final state = GameState(
          players: players,
          deck: [],
          discardPile: [],
          gameMode: GameMode.quick,
          tournamentCumulativeScores: {'p1': 100},
        );

        expect(state.isPlayerNearElimination(players[0]), false);
      });
    });

    group('JSON serialization', () {
      test('serializes and deserializes game state', () {
        final original = GameState(
          players: createTestPlayers(),
          deck: [PlayingCard.create('hearts', '5')],
          discardPile: [PlayingCard.create('spades', '3')],
          currentPlayerIndex: 1,
          gameMode: GameMode.tournament,
          phase: GamePhase.playing,
          tournamentRound: 2,
          reactionTimeRemaining: 3000,
          readyPlayerIds: ['p1'],
        );

        final json = original.toJson();
        final restored = GameState.fromJson(json);

        expect(restored.players.length, original.players.length);
        expect(restored.deck.length, original.deck.length);
        expect(restored.currentPlayerIndex, original.currentPlayerIndex);
        expect(restored.gameMode, original.gameMode);
        expect(restored.phase, original.phase);
        expect(restored.tournamentRound, original.tournamentRound);
        expect(restored.reactionTimeRemaining, original.reactionTimeRemaining);
        expect(restored.readyPlayerIds, ['p1']);
      });

      test('handles null optional fields', () {
        final json = {
          'players': [],
          'deck': [],
          'discardPile': [],
          'currentPlayerIndex': 0,
          'gameMode': 0,
          'phase': 0,
          'difficulty': 1,
        };

        final state = GameState.fromJson(json);
        expect(state.drawnCard, isNull);
        expect(state.dutchCallerId, isNull);
        expect(state.readyPlayerIds, isEmpty);
      });
    });

    group('GamePhase', () {
      test('has all phases', () {
        expect(GamePhase.values.length, 5);
        expect(GamePhase.setup.index, 0);
        expect(GamePhase.playing.index, 1);
        expect(GamePhase.reaction.index, 2);
        expect(GamePhase.dutchCalled.index, 3);
        expect(GamePhase.ended.index, 4);
      });
    });

    group('GameMode', () {
      test('has all modes', () {
        expect(GameMode.values.length, 2);
        expect(GameMode.quick.index, 0);
        expect(GameMode.tournament.index, 1);
      });
    });
  });
}
