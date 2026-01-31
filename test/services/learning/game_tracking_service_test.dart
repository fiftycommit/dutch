import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/learning/game_tracking_service.dart';
import 'package:dutch_game/core/interfaces/i_learning_service.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';

class MockLearningService implements ILearningService {
  final List<String> incrementTurnCalls = [];
  final List<String> recordDiscardCalls = [];
  final List<String> startNewRoundCalls = [];
  final List<Map<String, dynamic>> startGameRecordingCalls = [];
  final List<Map<String, dynamic>> endGameRecordingCalls = [];

  @override
  void incrementTurn(String playerId) {
    incrementTurnCalls.add(playerId);
  }

  @override
  void recordDiscard(String playerId) {
    recordDiscardCalls.add(playerId);
  }

  @override
  void startNewRound(String playerId) {
    startNewRoundCalls.add(playerId);
  }

  @override
  void startGameRecording({
    required String gameId,
    required Player player,
    required GameState gameState,
    required bool usedSBMM,
  }) {
    startGameRecordingCalls.add({
      'gameId': gameId,
      'playerId': player.id,
      'usedSBMM': usedSBMM,
    });
  }

  @override
  Future<void> endGameRecording({
    required String botPlayerId,
    required int finalScore,
    required int finalRank,
    required bool calledDutch,
    required bool wonDutch,
    required int cardsAtDutch,
    required int scoreAtDutch,
    required int humanFinalScore,
    required int humanFinalHandSize,
    required int botFinalHandSize,
  }) async {
    endGameRecordingCalls.add({
      'botPlayerId': botPlayerId,
      'finalScore': finalScore,
      'finalRank': finalRank,
      'calledDutch': calledDutch,
      'wonDutch': wonDutch,
      'cardsAtDutch': cardsAtDutch,
      'scoreAtDutch': scoreAtDutch,
      'humanFinalScore': humanFinalScore,
      'humanFinalHandSize': humanFinalHandSize,
      'botFinalHandSize': botFinalHandSize,
    });
  }
}

void main() {
  group('GameTrackingService', () {
    late GameTrackingService service;
    late MockLearningService mockLearningService;
    late GameState gameState;

    setUp(() {
      mockLearningService = MockLearningService();
      service = GameTrackingService(mockLearningService);
      gameState = _createTestGameState();
    });

    group('trackTurnIncrement', () {
      test('calls incrementTurn for each bot player', () {
        service.trackTurnIncrement(gameState);

        expect(mockLearningService.incrementTurnCalls, contains('bot1'));
        expect(mockLearningService.incrementTurnCalls, contains('bot2'));
      });

      test('does not call incrementTurn for human player', () {
        service.trackTurnIncrement(gameState);

        expect(mockLearningService.incrementTurnCalls, isNot(contains('human')));
      });

      test('calls incrementTurn correct number of times', () {
        service.trackTurnIncrement(gameState);

        expect(mockLearningService.incrementTurnCalls.length, 2); // 2 bots
      });
    });

    group('trackCardDiscard', () {
      test('calls recordDiscard for each bot player', () {
        service.trackCardDiscard(gameState);

        expect(mockLearningService.recordDiscardCalls, contains('bot1'));
        expect(mockLearningService.recordDiscardCalls, contains('bot2'));
      });

      test('does not call recordDiscard for human player', () {
        service.trackCardDiscard(gameState);

        expect(mockLearningService.recordDiscardCalls, isNot(contains('human')));
      });
    });

    group('initializeRound', () {
      test('calls startNewRound for each bot player', () {
        service.initializeRound(gameState);

        expect(mockLearningService.startNewRoundCalls, contains('bot1'));
        expect(mockLearningService.startNewRoundCalls, contains('bot2'));
      });

      test('does not call startNewRound for human player', () {
        service.initializeRound(gameState);

        expect(mockLearningService.startNewRoundCalls, isNot(contains('human')));
      });
    });

    group('startGameTracking', () {
      test('calls startGameRecording for each bot player', () {
        service.startGameTracking(
          gameId: 'game123',
          gameState: gameState,
          usedSBMM: true,
        );

        expect(mockLearningService.startGameRecordingCalls.length, 2);
        expect(
          mockLearningService.startGameRecordingCalls
              .map((c) => c['playerId'])
              .toList(),
          containsAll(['bot1', 'bot2']),
        );
      });

      test('passes correct gameId and usedSBMM', () {
        service.startGameTracking(
          gameId: 'game456',
          gameState: gameState,
          usedSBMM: false,
        );

        for (var call in mockLearningService.startGameRecordingCalls) {
          expect(call['gameId'], 'game456');
          expect(call['usedSBMM'], false);
        }
      });

      test('also calls startNewRound for each bot', () {
        service.startGameTracking(
          gameId: 'game789',
          gameState: gameState,
          usedSBMM: true,
        );

        expect(mockLearningService.startNewRoundCalls.length, 2);
      });

      test('does not track human player', () {
        service.startGameTracking(
          gameId: 'game000',
          gameState: gameState,
          usedSBMM: true,
        );

        final trackedPlayerIds = mockLearningService.startGameRecordingCalls
            .map((c) => c['playerId'])
            .toList();
        expect(trackedPlayerIds, isNot(contains('human')));
      });
    });

    group('endBotTracking', () {
      test('calls endGameRecording with all parameters', () async {
        await service.endBotTracking(
          botPlayerId: 'bot1',
          finalScore: 15,
          finalRank: 2,
          calledDutch: true,
          wonDutch: false,
          cardsAtDutch: 3,
          scoreAtDutch: 10,
          humanFinalScore: 20,
          humanFinalHandSize: 4,
          botFinalHandSize: 3,
        );

        expect(mockLearningService.endGameRecordingCalls.length, 1);

        final call = mockLearningService.endGameRecordingCalls.first;
        expect(call['botPlayerId'], 'bot1');
        expect(call['finalScore'], 15);
        expect(call['finalRank'], 2);
        expect(call['calledDutch'], true);
        expect(call['wonDutch'], false);
        expect(call['cardsAtDutch'], 3);
        expect(call['scoreAtDutch'], 10);
        expect(call['humanFinalScore'], 20);
        expect(call['humanFinalHandSize'], 4);
        expect(call['botFinalHandSize'], 3);
      });

      test('handles multiple bot endings', () async {
        await service.endBotTracking(
          botPlayerId: 'bot1',
          finalScore: 15,
          finalRank: 2,
          calledDutch: false,
          wonDutch: false,
          cardsAtDutch: 0,
          scoreAtDutch: 0,
          humanFinalScore: 10,
          humanFinalHandSize: 2,
          botFinalHandSize: 3,
        );

        await service.endBotTracking(
          botPlayerId: 'bot2',
          finalScore: 25,
          finalRank: 3,
          calledDutch: false,
          wonDutch: false,
          cardsAtDutch: 0,
          scoreAtDutch: 0,
          humanFinalScore: 10,
          humanFinalHandSize: 2,
          botFinalHandSize: 4,
        );

        expect(mockLearningService.endGameRecordingCalls.length, 2);
      });
    });

    group('edge cases', () {
      test('handles game with no bots', () {
        final humanOnlyGame = GameState(
          players: [
            Player(id: 'human1', name: 'Human 1', isHuman: true, position: 0)
              ..hand = [PlayingCard.create('hearts', 'A')]
              ..knownCards = [true],
          ],
          deck: [],
          discardPile: [],
          currentPlayerIndex: 0,
          phase: GamePhase.playing,
        );

        // Should not throw and should not call any learning service methods
        service.trackTurnIncrement(humanOnlyGame);
        service.trackCardDiscard(humanOnlyGame);
        service.initializeRound(humanOnlyGame);

        expect(mockLearningService.incrementTurnCalls, isEmpty);
        expect(mockLearningService.recordDiscardCalls, isEmpty);
        expect(mockLearningService.startNewRoundCalls, isEmpty);
      });

      test('handles game with only bots', () {
        final botsOnlyGame = GameState(
          players: [
            Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 0)
              ..hand = [PlayingCard.create('hearts', 'A')]
              ..knownCards = [false],
            Player(id: 'bot2', name: 'Bot 2', isHuman: false, position: 1)
              ..hand = [PlayingCard.create('diamonds', '2')]
              ..knownCards = [false],
          ],
          deck: [],
          discardPile: [],
          currentPlayerIndex: 0,
          phase: GamePhase.playing,
        );

        service.trackTurnIncrement(botsOnlyGame);

        expect(mockLearningService.incrementTurnCalls.length, 2);
      });
    });
  });
}

GameState _createTestGameState() {
  final players = [
    Player(id: 'human', name: 'Human', isHuman: true, position: 0),
    Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
    Player(id: 'bot2', name: 'Bot 2', isHuman: false, position: 2),
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
    phase: GamePhase.playing,
  );
}
