import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/providers/game_provider.dart';
import '../mocks/mock_services.dart';
import '../mocks/mock_tracking_provider.dart';
import '../helpers/test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockHapticService mockHaptic;
  late MockStatsService mockStats;
  late MockBotAIService mockBotAI;
  late MockGameTrackingProvider mockTracking;
  late GameProvider provider;

  setUp(() {
    mockHaptic = MockHapticService();
    mockStats = MockStatsService();
    mockBotAI = MockBotAIService();
    mockTracking = MockGameTrackingProvider();

    provider = GameProvider(
      hapticService: mockHaptic,
      statsService: mockStats,
      botAIService: mockBotAI,
      trackingProvider: mockTracking,
    );
  });

  group('GameProvider - Game Creation', () {
    test('createNewGame initializes game state', () {
      final players = createStandardPlayers(botCount: 2);

      provider.createNewGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
        reactionTimeMs: 3000,
      );

      expect(provider.hasActiveGame, true);
      expect(provider.gameState, isNotNull);
      expect(provider.gameState!.players.length, 3);
    });

    test('createNewGame in tournament mode initializes tournament', () {
      final players = createStandardPlayers(botCount: 2);

      provider.createNewGame(
        players: players,
        gameMode: GameMode.tournament,
        difficulty: Difficulty.medium,
        reactionTimeMs: 3000,
        tournamentRound: 1,
      );

      expect(provider.gameState!.gameMode, GameMode.tournament);
      expect(provider.gameState!.tournamentRound, 1);
    });

    test('createNewGame resets processing state', () {
      provider.isProcessing = true;

      final players = createStandardPlayers(botCount: 2);
      provider.createNewGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
        reactionTimeMs: 3000,
      );

      expect(provider.isProcessing, false);
    });

    test('createNewGame clears shaking indices', () {
      provider.shakingCardIndices.add(0);
      provider.shakingCardIndices.add(1);

      final players = createStandardPlayers(botCount: 2);
      provider.createNewGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
        reactionTimeMs: 3000,
      );

      expect(provider.shakingCardIndices, isEmpty);
    });

    test('createNewGame initializes tracking', () {
      final players = createStandardPlayers(botCount: 2);

      provider.createNewGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
        reactionTimeMs: 3000,
      );

      expect(mockTracking.initTrackingCount, 1);
    });
  });

  group('GameProvider - Draw Card', () {
    test('drawCard when valid sets drawnCard', () {
      _setupGameWithHumanTurn(provider);

      provider.drawCard();

      expect(provider.gameState!.drawnCard, isNotNull);
    });

    test('drawCard does nothing when not playing phase', () {
      _setupGameWithHumanTurn(provider);
      provider.gameState!.phase = GamePhase.reaction;

      provider.drawCard();

      expect(provider.gameState!.drawnCard, isNull);
    });

    test('drawCard does nothing when not human turn', () {
      _setupGameWithBotTurn(provider);

      provider.drawCard();

      expect(provider.gameState!.drawnCard, isNull);
    });

    test('drawCard does nothing when already have drawn card', () {
      _setupGameWithHumanTurn(provider);
      provider.drawCard();
      final firstDrawn = provider.gameState!.drawnCard;

      provider.drawCard();

      expect(provider.gameState!.drawnCard, firstDrawn);
    });

    test('drawCard records tracking action', () {
      _setupGameWithHumanTurn(provider);
      mockTracking.recordedActions.clear();

      provider.drawCard();

      expect(mockTracking.recordedActions.any((a) => a['actionType'] == 'draw'),
          true);
    });
  });

  group('GameProvider - Replace Card', () {
    test('replaceCard swaps drawn card with hand card', () {
      _setupGameWithHumanTurn(provider);
      provider.drawCard();
      final drawnCard = provider.gameState!.drawnCard!;
      final human = provider.gameState!.humanPlayer;
      final originalCard = human.hand[0];

      provider.replaceCard(0);

      expect(human.hand[0], drawnCard);
      expect(provider.gameState!.discardPile.last, originalCard);
      expect(provider.gameState!.drawnCard, isNull);
    });

    test('replaceCard does nothing without drawn card', () {
      _setupGameWithHumanTurn(provider);
      final human = provider.gameState!.humanPlayer;
      final originalHand = List.from(human.hand);

      provider.replaceCard(0);

      expect(human.hand, originalHand);
    });

    test('replaceCard triggers haptic feedback', () {
      _setupGameWithHumanTurn(provider);
      provider.drawCard();
      mockHaptic.reset();

      provider.replaceCard(0);

      expect(mockHaptic.cardTapCount, 1);
    });

    test('replaceCard records tracking action', () {
      _setupGameWithHumanTurn(provider);
      provider.drawCard();
      mockTracking.recordedActions.clear();

      provider.replaceCard(0);

      expect(
          mockTracking.recordedActions.any((a) => a['actionType'] == 'replace'),
          true);
    });
  });

  group('GameProvider - Discard Drawn Card', () {
    test('discardDrawnCard moves card to discard pile', () {
      _setupGameWithHumanTurn(provider);
      provider.drawCard();
      final drawnCard = provider.gameState!.drawnCard!;

      provider.discardDrawnCard();

      expect(provider.gameState!.drawnCard, isNull);
      expect(provider.gameState!.discardPile.last, drawnCard);
    });

    test('discardDrawnCard does nothing without drawn card', () {
      _setupGameWithHumanTurn(provider);
      final discardSize = provider.gameState!.discardPile.length;

      provider.discardDrawnCard();

      expect(provider.gameState!.discardPile.length, discardSize);
    });

    test('discardDrawnCard triggers haptic feedback', () {
      _setupGameWithHumanTurn(provider);
      provider.drawCard();
      final beforeDiscard = mockHaptic.cardTapCount;

      provider.discardDrawnCard();

      expect(mockHaptic.cardTapCount, beforeDiscard + 1);
    });
  });

  group('GameProvider - Attempt Match', () {
    test('attemptMatch succeeds when cards match', () {
      _setupGameWithHumanTurn(provider);
      provider.gameState!.phase = GamePhase.reaction;
      final human = provider.gameState!.humanPlayer;

      // Setup matching cards
      final matchCard = createCard('hearts', '5');
      human.hand[0] = matchCard;
      provider.gameState!.discardPile.add(createCard('diamonds', '5'));
      final handSizeBefore = human.hand.length;

      provider.attemptMatch(0);

      expect(human.hand.length, handSizeBefore - 1);
    });

    test('attemptMatch fails and applies penalty when cards differ', () async {
      _setupGameWithHumanTurn(provider);
      provider.gameState!.phase = GamePhase.reaction;
      final human = provider.gameState!.humanPlayer;

      // Setup non-matching cards
      human.hand[0] = createCard('hearts', 'A');
      provider.gameState!.discardPile.add(createCard('diamonds', '9'));
      final handSizeBefore = human.hand.length;

      provider.attemptMatch(0);
      // Wait for the penalty animation
      await Future.delayed(const Duration(milliseconds: 700));

      expect(human.hand.length, handSizeBefore + 1); // Penalty card added
    });

    test('attemptMatch does nothing when not in reaction phase', () {
      _setupGameWithHumanTurn(provider);
      provider.gameState!.phase = GamePhase.playing;
      final human = provider.gameState!.humanPlayer;
      final handSizeBefore = human.hand.length;

      provider.attemptMatch(0);

      expect(human.hand.length, handSizeBefore);
    });

    test('attemptMatch triggers haptic on success', () async {
      _setupGameWithHumanTurn(provider);
      provider.gameState!.phase = GamePhase.reaction;
      final human = provider.gameState!.humanPlayer;

      human.hand[0] = createCard('hearts', '5');
      provider.gameState!.discardPile.add(createCard('diamonds', '5'));

      provider.attemptMatch(0);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(mockHaptic.cardTapCount, 1);
    });

    test('attemptMatch triggers error haptic on failure', () async {
      _setupGameWithHumanTurn(provider);
      provider.gameState!.phase = GamePhase.reaction;
      final human = provider.gameState!.humanPlayer;

      human.hand[0] = createCard('hearts', 'A');
      provider.gameState!.discardPile.add(createCard('diamonds', '9'));

      provider.attemptMatch(0);
      await Future.delayed(const Duration(milliseconds: 700));

      expect(mockHaptic.errorCount, 1);
    });

    test('attemptMatch adds to shaking indices on failure', () async {
      _setupGameWithHumanTurn(provider);
      provider.gameState!.phase = GamePhase.reaction;
      final human = provider.gameState!.humanPlayer;

      human.hand[0] = createCard('hearts', 'A');
      provider.gameState!.discardPile.add(createCard('diamonds', '9'));

      // Don't await - check immediately
      provider.attemptMatch(0);

      expect(provider.shakingCardIndices.contains(0), true);
    });
  });

  group('GameProvider - Call Dutch', () {
    test('callDutch sets dutch caller and ends game', () {
      _setupGameWithHumanTurn(provider);
      final human = provider.gameState!.humanPlayer;

      provider.callDutch();

      expect(provider.gameState!.dutchCallerId, human.id);
      expect(provider.gameState!.phase, GamePhase.ended);
    });

    test('callDutch does nothing when not playing', () {
      _setupGameWithHumanTurn(provider);
      provider.gameState!.phase = GamePhase.reaction;

      provider.callDutch();

      expect(provider.gameState!.dutchCallerId, isNull);
    });

    test('callDutch does nothing when not human turn', () {
      _setupGameWithBotTurn(provider);

      provider.callDutch();

      expect(provider.gameState!.dutchCallerId, isNull);
    });

    test('callDutch does nothing when have drawn card', () {
      _setupGameWithHumanTurn(provider);
      provider.drawCard();

      provider.callDutch();

      expect(provider.gameState!.dutchCallerId, isNull);
    });

    test('callDutch records tracking action', () {
      _setupGameWithHumanTurn(provider);
      mockTracking.recordedActions.clear();

      provider.callDutch();

      expect(
          mockTracking.recordedActions.any((a) => a['actionType'] == 'dutch'),
          true);
    });
  });

  group('GameProvider - Handle Card Tap', () {
    test('handleCardTap routes to attemptMatch in reaction phase', () async {
      _setupGameWithHumanTurn(provider);
      provider.gameState!.phase = GamePhase.reaction;
      final human = provider.gameState!.humanPlayer;

      human.hand[0] = createCard('hearts', '5');
      provider.gameState!.discardPile.add(createCard('diamonds', '5'));
      final handSizeBefore = human.hand.length;

      provider.handleCardTap(0);
      await Future.delayed(const Duration(milliseconds: 600));

      expect(human.hand.length, handSizeBefore - 1);
    });

    test('handleCardTap routes to replaceCard in playing phase with drawn card',
        () {
      _setupGameWithHumanTurn(provider);
      provider.drawCard();
      final drawnCard = provider.gameState!.drawnCard!;
      final human = provider.gameState!.humanPlayer;

      provider.handleCardTap(0);

      expect(human.hand[0], drawnCard);
    });

    test('handleCardTap does nothing when isProcessing', () {
      _setupGameWithHumanTurn(provider);
      provider.drawCard();
      provider.isProcessing = true;
      final human = provider.gameState!.humanPlayer;
      final originalCard = human.hand[0];

      provider.handleCardTap(0);

      expect(human.hand[0], originalCard);
    });

    test('handleCardTap does nothing when no game state', () {
      // No game created
      provider.handleCardTap(0);
      // Should not throw
    });

    test('handleCardTap does nothing in playing phase without drawn card', () {
      _setupGameWithHumanTurn(provider);
      final human = provider.gameState!.humanPlayer;
      final originalHand = List.from(human.hand);

      provider.handleCardTap(0);

      expect(human.hand, originalHand);
    });
  });

  group('GameProvider - Pause/Resume', () {
    test('pauseGame sets isPaused to true', () {
      _setupGameWithHumanTurn(provider);

      provider.pauseGame();

      expect(provider.isPaused, true);
    });

    test('pauseGame resets isProcessing', () {
      _setupGameWithHumanTurn(provider);
      provider.isProcessing = true;

      provider.pauseGame();

      expect(provider.isProcessing, false);
    });

    test('resumeGame sets isPaused to false', () {
      _setupGameWithHumanTurn(provider);
      provider.pauseGame();

      provider.resumeGame();

      expect(provider.isPaused, false);
    });
  });

  group('GameProvider - End Game', () {
    test('endGame sets phase to ended', () {
      _setupGameWithHumanTurn(provider);

      provider.endGame();

      expect(provider.gameState!.phase, GamePhase.ended);
    });

    test('endGame reveals all cards', () {
      _setupGameWithHumanTurn(provider);
      final human = provider.gameState!.humanPlayer;
      human.knownCards = [false, false, false, false];

      provider.endGame();

      expect(human.knownCards, everyElement(true));
    });

    test('endGame finalizes bot recordings', () {
      _setupGameWithHumanTurn(provider);

      provider.endGame();

      expect(mockTracking.finalizeBotRecordingsCount, 1);
    });
  });

  group('GameProvider - Local Player Properties', () {
    test('localPlayer returns human player', () {
      _setupGameWithHumanTurn(provider);

      expect(provider.localPlayer, isNotNull);
      expect(provider.localPlayer!.isHuman, true);
    });

    test('isLocalPlayerTurn returns true when human turn', () {
      _setupGameWithHumanTurn(provider);

      expect(provider.isLocalPlayerTurn, true);
    });

    test('isLocalPlayerTurn returns false when bot turn', () {
      _setupGameWithBotTurn(provider);

      expect(provider.isLocalPlayerTurn, false);
    });

    test('canLocalPlayerAct returns true when valid', () {
      _setupGameWithHumanTurn(provider);

      expect(provider.canLocalPlayerAct, true);
    });

    test('canLocalPlayerAct returns false when not playing', () {
      _setupGameWithHumanTurn(provider);
      provider.gameState!.phase = GamePhase.reaction;

      expect(provider.canLocalPlayerAct, false);
    });

    test('canLocalPlayerAct returns false when bot turn', () {
      _setupGameWithBotTurn(provider);

      expect(provider.canLocalPlayerAct, false);
    });
  });

  group('GameProvider - Anti-Double Action', () {
    test('isProcessing blocks actions', () {
      _setupGameWithHumanTurn(provider);
      provider.isProcessing = true;

      provider.handleCardTap(0);
      // Should not throw or modify state
    });
  });

  group('GameProvider - Special Powers', () {
    test('skipSpecialPower clears power state', () {
      _setupGameWithHumanTurn(provider);
      provider.gameState!.isWaitingForSpecialPower = true;
      provider.gameState!.specialCardToActivate = createCard('hearts', '7');

      provider.skipSpecialPower();

      expect(provider.gameState!.isWaitingForSpecialPower, false);
      expect(provider.gameState!.specialCardToActivate, isNull);
    });
  });
}

/// Helper to setup game with human turn
void _setupGameWithHumanTurn(GameProvider provider) {
  final players = createStandardPlayers(botCount: 2);
  provider.createNewGame(
    players: players,
    gameMode: GameMode.quick,
    difficulty: Difficulty.medium,
    reactionTimeMs: 3000,
  );

  // Ensure human is current player
  final humanIndex = provider.gameState!.players.indexWhere((p) => p.isHuman);
  provider.gameState!.currentPlayerIndex = humanIndex;
  provider.gameState!.phase = GamePhase.playing;
}

/// Helper to setup game with bot turn
void _setupGameWithBotTurn(GameProvider provider) {
  final players = createStandardPlayers(botCount: 2);
  provider.createNewGame(
    players: players,
    gameMode: GameMode.quick,
    difficulty: Difficulty.medium,
    reactionTimeMs: 3000,
  );

  // Ensure bot is current player
  final botIndex = provider.gameState!.players.indexWhere((p) => !p.isHuman);
  provider.gameState!.currentPlayerIndex = botIndex;
  provider.gameState!.phase = GamePhase.playing;
}
