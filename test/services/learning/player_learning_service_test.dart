import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dutch_game/services/learning/player_learning_service.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';
import 'package:dutch_game/models/player_learning_data.dart';

void main() {
  group('PlayerLearningService', () {
    late PlayerLearningService service;
    late GameState gameState;
    late Player human;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = PlayerLearningService();
      gameState = _createTestGameState();
      human = gameState.players.firstWhere((p) => p.isHuman);
    });

    group('getProfile', () {
      test('returns default profile when no data exists', () async {
        final profile = await service.getProfile(slotId: 1);

        expect(profile.profileId, 'slot_1');
        expect(profile.gamesAnalyzed, 0);
        expect(profile.mmr, 0);
        expect(profile.learnedParameters, isNotEmpty);
      });

      test('returns different profiles for different slots', () async {
        final profile1 = await service.getProfile(slotId: 1);
        final profile2 = await service.getProfile(slotId: 2);

        expect(profile1.profileId, 'slot_1');
        expect(profile2.profileId, 'slot_2');
      });

      test('handles corrupted data gracefully', () async {
        SharedPreferences.setMockInitialValues({
          'player_profile_slot_1': 'not valid json',
        });
        final service2 = PlayerLearningService();

        final profile = await service2.getProfile(slotId: 1);

        expect(profile.profileId, 'slot_1');
        expect(profile.gamesAnalyzed, 0);
      });
    });

    group('getHistory', () {
      test('returns empty list when no history exists', () async {
        final history = await service.getHistory(slotId: 1);

        expect(history, isEmpty);
      });

      test('returns different histories for different slots', () async {
        final history1 = await service.getHistory(slotId: 1);
        final history2 = await service.getHistory(slotId: 2);

        expect(history1, isEmpty);
        expect(history2, isEmpty);
      });
    });

    group('startGame', () {
      test('does not throw', () {
        expect(
          () => service.startGame(gameId: 'game123'),
          returnsNormally,
        );
      });

      test('can start multiple games', () {
        service.startGame(gameId: 'game1');
        service.startGame(gameId: 'game2');
        // Should not throw
      });
    });

    group('recordAction', () {
      test('does nothing without active game', () {
        expect(
          () => service.recordAction(
            gameId: 'unknown',
            actionType: 'draw',
            turnNumber: 1,
            gameState: gameState,
            human: human,
            actionDetails: {},
          ),
          returnsNormally,
        );
      });

      test('records action after game started', () {
        service.startGame(gameId: 'game123');

        expect(
          () => service.recordAction(
            gameId: 'game123',
            actionType: 'draw',
            turnNumber: 1,
            gameState: gameState,
            human: human,
            actionDetails: {'source': 'deck'},
          ),
          returnsNormally,
        );
      });

      test('handles all action types', () {
        service.startGame(gameId: 'game123');

        final actionTypes = [
          'draw',
          'discard',
          'replace',
          'match',
          'power',
          'dutch',
          'power_skip'
        ];

        for (final actionType in actionTypes) {
          expect(
            () => service.recordAction(
              gameId: 'game123',
              actionType: actionType,
              turnNumber: 1,
              gameState: gameState,
              human: human,
              actionDetails: {},
            ),
            returnsNormally,
          );
        }
      });

      test('records power type and target strategy', () {
        service.startGame(gameId: 'game123');

        expect(
          () => service.recordAction(
            gameId: 'game123',
            actionType: 'power',
            turnNumber: 1,
            gameState: gameState,
            human: human,
            actionDetails: {'target': 'bot1'},
            powerType: '10',
            targetStrategy: 'leader',
          ),
          returnsNormally,
        );
      });
    });

    group('updateLastActionResult', () {
      test('does nothing without pending actions', () {
        expect(
          () => service.updateLastActionResult(
            gameId: 'unknown',
            result: {'success': true},
          ),
          returnsNormally,
        );
      });

      test('updates result after action recorded', () {
        service.startGame(gameId: 'game123');

        service.recordAction(
          gameId: 'game123',
          actionType: 'match',
          turnNumber: 1,
          gameState: gameState,
          human: human,
          actionDetails: {'cardIndex': 0},
        );

        expect(
          () => service.updateLastActionResult(
            gameId: 'game123',
            result: {'success': true, 'scoreChange': -5},
          ),
          returnsNormally,
        );
      });
    });

    group('endGame', () {
      test('returns updated profile', () async {
        service.startGame(gameId: 'game123');

        service.recordAction(
          gameId: 'game123',
          actionType: 'draw',
          turnNumber: 1,
          gameState: gameState,
          human: human,
          actionDetails: {},
        );

        final profile = await service.endGame(
          gameId: 'game123',
          slotId: 1,
          usedSBMM: true,
          gameState: gameState,
          human: human,
          finalRank: 1,
          finalScore: 5,
          calledDutch: false,
          wonDutch: false,
        );

        expect(profile.gamesAnalyzed, 1);
        expect(profile.mmr, greaterThan(0)); // Won the game, MMR increased
      });

      test('handles dutch win scenario', () async {
        service.startGame(gameId: 'game123');

        final profile = await service.endGame(
          gameId: 'game123',
          slotId: 1,
          usedSBMM: true,
          gameState: gameState,
          human: human,
          finalRank: 1,
          finalScore: 3,
          calledDutch: true,
          wonDutch: true,
        );

        expect(profile.gamesAnalyzed, 1);
        expect(profile.learnedParameters['dutchThreshold'], isNotNull);
      });

      test('handles dutch loss scenario', () async {
        service.startGame(gameId: 'game123');

        final profile = await service.endGame(
          gameId: 'game123',
          slotId: 1,
          usedSBMM: true,
          gameState: gameState,
          human: human,
          finalRank: 3,
          finalScore: 25,
          calledDutch: true,
          wonDutch: false,
        );

        expect(profile.gamesAnalyzed, 1);
      });

      test('saves history', () async {
        service.startGame(gameId: 'game123');

        await service.endGame(
          gameId: 'game123',
          slotId: 1,
          usedSBMM: true,
          gameState: gameState,
          human: human,
          finalRank: 2,
          finalScore: 15,
          calledDutch: false,
          wonDutch: false,
        );

        final history = await service.getHistory(slotId: 1);
        expect(history.length, 1);
        expect(history.first.finalRank, 2);
      });

      test('limits history to 10 entries', () async {
        for (int i = 0; i < 15; i++) {
          service.startGame(gameId: 'game$i');
          await service.endGame(
            gameId: 'game$i',
            slotId: 1,
            usedSBMM: true,
            gameState: gameState,
            human: human,
            finalRank: 1,
            finalScore: 5,
            calledDutch: false,
            wonDutch: false,
          );
        }

        final history = await service.getHistory(slotId: 1);
        expect(history.length, 10);
      });

      test('skips update and history when usedSBMM is false', () async {
        service.startGame(gameId: 'game_manual');

        service.recordAction(
          gameId: 'game_manual',
          actionType: 'draw',
          turnNumber: 1,
          gameState: gameState,
          human: human,
          actionDetails: {},
        );

        final profile = await service.endGame(
          gameId: 'game_manual',
          slotId: 1,
          usedSBMM: false,
          gameState: gameState,
          human: human,
          finalRank: 2,
          finalScore: 15,
          calledDutch: false,
          wonDutch: false,
        );

        expect(profile.gamesAnalyzed, 0);

        final history = await service.getHistory(slotId: 1);
        expect(history, isEmpty);
      });
    });

    group('isBadPowerDecision', () {
      test('returns true for joker on single card hand', () {
        final joker = PlayingCard.create('joker', 'JOKER');
        final target =
            Player(id: 'target', name: 'Target', isHuman: false, position: 1)
              ..hand = [PlayingCard.create('hearts', 'A')]
              ..knownCards = [false];

        expect(
          PlayerLearningService.isBadPowerDecision(
            specialCard: joker,
            target: target,
          ),
          isTrue,
        );
      });

      test('returns false for joker on multi-card hand', () {
        final joker = PlayingCard.create('joker', 'JOKER');
        final target =
            Player(id: 'target', name: 'Target', isHuman: false, position: 1)
              ..hand = [
                PlayingCard.create('hearts', 'A'),
                PlayingCard.create('diamonds', '2'),
                PlayingCard.create('clubs', '3'),
              ]
              ..knownCards = [false, false, false];

        expect(
          PlayerLearningService.isBadPowerDecision(
            specialCard: joker,
            target: target,
          ),
          isFalse,
        );
      });

      test('returns false for non-joker cards', () {
        final jack = PlayingCard.create('hearts', 'V');
        final target =
            Player(id: 'target', name: 'Target', isHuman: false, position: 1)
              ..hand = [PlayingCard.create('hearts', 'A')]
              ..knownCards = [false];

        expect(
          PlayerLearningService.isBadPowerDecision(
            specialCard: jack,
            target: target,
          ),
          isFalse,
        );
      });
    });

    group('PlayerProfile', () {
      test('defaultProfile has expected parameters', () {
        final profile = PlayerProfile.defaultProfile(profileId: 'test');

        expect(profile.profileId, 'test');
        expect(profile.gamesAnalyzed, 0);
        expect(profile.mmr, 0);
        expect(profile.learnedParameters['aggressiveness'], isNotNull);
        expect(profile.learnedParameters['caution'], isNotNull);
        expect(profile.learnedParameters['dutchThreshold'], isNotNull);
        expect(profile.learnedParameters['memoryAccuracy'], isNotNull);
      });

      test('toJsonString and fromJsonString roundtrip', () {
        final original = PlayerProfile.defaultProfile(profileId: 'test');
        final json = original.toJsonString();
        final restored = PlayerProfile.fromJsonString(json);

        expect(restored.profileId, original.profileId);
        expect(restored.gamesAnalyzed, original.gamesAnalyzed);
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
      PlayingCard.create('clubs', '5'),
      PlayingCard.create('spades', '8'),
    ];
    player.knownCards = List.filled(4, false, growable: true);
  }

  return GameState(
    players: players,
    deck: GameState.createFullDeck().sublist(0, 40),
    discardPile: [PlayingCard.create('hearts', '5')],
    currentPlayerIndex: 0,
    phase: GamePhase.playing,
  );
}
