import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/learning/bot_learning_service.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';
import 'package:dutch_game/models/game_settings.dart';

void main() {
  group('BotLearningService', () {
    late BotLearningService service;
    late GameState gameState;
    late Player bot;

    setUp(() {
      service = BotLearningService();
      gameState = _createTestGameState();
      bot = gameState.players.firstWhere((p) => !p.isHuman);
    });

    group('startGameRecording', () {
      test('does not throw for bot player', () {
        expect(
          () => service.startGameRecording(
            gameId: 'game123',
            player: bot,
            gameState: gameState,
            usedSBMM: true,
          ),
          returnsNormally,
        );
      });

      test('does nothing for human player', () {
        final human = gameState.players.firstWhere((p) => p.isHuman);

        expect(
          () => service.startGameRecording(
            gameId: 'game123',
            player: human,
            gameState: gameState,
            usedSBMM: true,
          ),
          returnsNormally,
        );
      });

      test('can start multiple games for different bots', () {
        final bot2 = gameState.players.where((p) => !p.isHuman).skip(1).first;

        service.startGameRecording(
          gameId: 'game1',
          player: bot,
          gameState: gameState,
          usedSBMM: true,
        );

        service.startGameRecording(
          gameId: 'game2',
          player: bot2,
          gameState: gameState,
          usedSBMM: false,
        );

        // Should not throw
      });
    });

    group('recordAction', () {
      test('does nothing without active game', () {
        expect(
          () => service.recordAction(
            botPlayerId: 'unknown',
            actionType: 'draw',
            turnNumber: 1,
            gameState: gameState,
            actionDetails: {},
          ),
          returnsNormally,
        );
      });

      test('records action after game started', () {
        service.startGameRecording(
          gameId: 'game123',
          player: bot,
          gameState: gameState,
          usedSBMM: true,
        );

        expect(
          () => service.recordAction(
            botPlayerId: bot.id,
            actionType: 'draw',
            turnNumber: 1,
            gameState: gameState,
            actionDetails: {'source': 'deck'},
          ),
          returnsNormally,
        );
      });

      test('handles all action types', () {
        service.startGameRecording(
          gameId: 'game123',
          player: bot,
          gameState: gameState,
          usedSBMM: true,
        );

        final actionTypes = ['draw', 'discard', 'replace', 'match', 'power', 'dutch'];

        for (final actionType in actionTypes) {
          expect(
            () => service.recordAction(
              botPlayerId: bot.id,
              actionType: actionType,
              turnNumber: 1,
              gameState: gameState,
              actionDetails: {},
            ),
            returnsNormally,
          );
        }
      });
    });

    group('updateLastActionResult', () {
      test('does nothing without pending actions', () {
        expect(
          () => service.updateLastActionResult(
            botPlayerId: 'unknown',
            result: {'success': true},
          ),
          returnsNormally,
        );
      });

      test('updates result after action recorded', () {
        service.startGameRecording(
          gameId: 'game123',
          player: bot,
          gameState: gameState,
          usedSBMM: true,
        );

        service.recordAction(
          botPlayerId: bot.id,
          actionType: 'match',
          turnNumber: 1,
          gameState: gameState,
          actionDetails: {'cardIndex': 0},
        );

        expect(
          () => service.updateLastActionResult(
            botPlayerId: bot.id,
            result: {'success': true, 'scoreChange': -5},
          ),
          returnsNormally,
        );
      });
    });

    group('incrementTurn', () {
      test('does nothing without active game', () {
        expect(
          () => service.incrementTurn('unknown'),
          returnsNormally,
        );
      });

      test('increments after game started', () {
        service.startGameRecording(
          gameId: 'game123',
          player: bot,
          gameState: gameState,
          usedSBMM: true,
        );

        expect(
          () => service.incrementTurn(bot.id),
          returnsNormally,
        );
      });
    });

    group('recordDiscard', () {
      test('does nothing without active game', () {
        expect(
          () => service.recordDiscard('unknown'),
          returnsNormally,
        );
      });

      test('records discard after game started', () {
        service.startGameRecording(
          gameId: 'game123',
          player: bot,
          gameState: gameState,
          usedSBMM: true,
        );

        expect(
          () => service.recordDiscard(bot.id),
          returnsNormally,
        );
      });
    });

    group('startNewRound', () {
      test('does nothing without active game', () {
        expect(
          () => service.startNewRound('unknown'),
          returnsNormally,
        );
      });

      test('starts new round after game started', () {
        service.startGameRecording(
          gameId: 'game123',
          player: bot,
          gameState: gameState,
          usedSBMM: true,
        );

        expect(
          () => service.startNewRound(bot.id),
          returnsNormally,
        );
      });
    });

    group('recordTriageDecision', () {
      test('does nothing without active game', () {
        expect(
          () => service.recordTriageDecision(
            botPlayerId: 'unknown',
            decision: {'kept': true},
          ),
          returnsNormally,
        );
      });

      test('records decision after game started', () {
        service.startGameRecording(
          gameId: 'game123',
          player: bot,
          gameState: gameState,
          usedSBMM: true,
        );

        expect(
          () => service.recordTriageDecision(
            botPlayerId: bot.id,
            decision: {'kept': true, 'cardValue': 5},
          ),
          returnsNormally,
        );
      });
    });

    group('endGameRecording', () {
      test('does nothing without active game', () async {
        await expectLater(
          service.endGameRecording(
            botPlayerId: 'unknown',
            finalScore: 10,
            finalRank: 2,
            calledDutch: false,
            wonDutch: false,
            cardsAtDutch: 0,
            scoreAtDutch: 0,
            humanFinalScore: 15,
            humanFinalHandSize: 3,
            botFinalHandSize: 4,
          ),
          completes,
        );
      });

      test('completes without error for active game', () async {
        service.startGameRecording(
          gameId: 'game123',
          player: bot,
          gameState: gameState,
          usedSBMM: true,
        );

        // Record some actions
        service.recordAction(
          botPlayerId: bot.id,
          actionType: 'draw',
          turnNumber: 1,
          gameState: gameState,
          actionDetails: {},
        );

        await expectLater(
          service.endGameRecording(
            botPlayerId: bot.id,
            finalScore: 10,
            finalRank: 2,
            calledDutch: false,
            wonDutch: false,
            cardsAtDutch: 0,
            scoreAtDutch: 0,
            humanFinalScore: 15,
            humanFinalHandSize: 3,
            botFinalHandSize: 4,
          ),
          completes,
        );
      });

      test('handles dutch winner scenario', () async {
        service.startGameRecording(
          gameId: 'game123',
          player: bot,
          gameState: gameState,
          usedSBMM: true,
        );

        await expectLater(
          service.endGameRecording(
            botPlayerId: bot.id,
            finalScore: 5,
            finalRank: 1,
            calledDutch: true,
            wonDutch: true,
            cardsAtDutch: 2,
            scoreAtDutch: 5,
            humanFinalScore: 20,
            humanFinalHandSize: 4,
            botFinalHandSize: 2,
          ),
          completes,
        );
      });

      test('handles dutch loser scenario', () async {
        service.startGameRecording(
          gameId: 'game123',
          player: bot,
          gameState: gameState,
          usedSBMM: true,
        );

        await expectLater(
          service.endGameRecording(
            botPlayerId: bot.id,
            finalScore: 25,
            finalRank: 3,
            calledDutch: true,
            wonDutch: false,
            cardsAtDutch: 4,
            scoreAtDutch: 20,
            humanFinalScore: 10,
            humanFinalHandSize: 2,
            botFinalHandSize: 4,
          ),
          completes,
        );
      });

      test('cleans up after ending', () async {
        service.startGameRecording(
          gameId: 'game123',
          player: bot,
          gameState: gameState,
          usedSBMM: true,
        );

        await service.endGameRecording(
          botPlayerId: bot.id,
          finalScore: 10,
          finalRank: 2,
          calledDutch: false,
          wonDutch: false,
          cardsAtDutch: 0,
          scoreAtDutch: 0,
          humanFinalScore: 15,
          humanFinalHandSize: 3,
          botFinalHandSize: 4,
        );

        // Recording action after end should do nothing
        expect(
          () => service.recordAction(
            botPlayerId: bot.id,
            actionType: 'draw',
            turnNumber: 1,
            gameState: gameState,
            actionDetails: {},
          ),
          returnsNormally,
        );
      });
    });

    group('fetchTopBots', () {
      test('returns empty list on network error', () async {
        final result = await service.fetchTopBots();

        expect(result, isA<List>());
      });

      test('accepts filter parameters', () async {
        final result = await service.fetchTopBots(
          behavior: 'balanced',
          skillLevel: 'gold',
          limit: 5,
        );

        expect(result, isA<List>());
      });
    });

    group('fetchBotParameters', () {
      test('returns null on network error', () async {
        final result = await service.fetchBotParameters(
          behavior: 'balanced',
          skillLevel: 'gold',
        );

        expect(result, isNull);
      });
    });
  });
}

GameState _createTestGameState() {
  final players = [
    Player(
      id: 'human',
      name: 'Human',
      isHuman: true,
      position: 0,
    ),
    Player(
      id: 'bot1',
      name: 'Bot 1',
      isHuman: false,
      position: 1,
      botBehavior: BotBehavior.balanced,
      botSkillLevel: BotSkillLevel.silver,
    ),
    Player(
      id: 'bot2',
      name: 'Bot 2',
      isHuman: false,
      position: 2,
      botBehavior: BotBehavior.aggressive,
      botSkillLevel: BotSkillLevel.difficile,
    ),
  ];

  for (var player in players) {
    player.hand = [
      PlayingCard.create('hearts', 'A'),
      PlayingCard.create('diamonds', '2'),
      PlayingCard.create('clubs', '5'),
      PlayingCard.create('spades', '8'),
    ];
    player.knownCards = List.filled(4, false, growable: true);
    if (!player.isHuman) {
      player.initializeBotMemory();
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
