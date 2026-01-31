import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/providers/game_provider.dart';
import 'package:dutch_game/providers/game_tracking_provider.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/game_settings.dart';
import '../mocks/mock_services.dart';

void main() {
  // Ensure Flutter binding is initialized for SharedPreferences
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameProvider gameProvider;
  late MockHapticService mockHaptic;
  late MockStatsService mockStats;
  late MockBotAIService mockBotAI;
  late GameTrackingProvider trackingProvider;

  setUp(() {
    mockHaptic = MockHapticService();
    mockStats = MockStatsService();
    mockBotAI = MockBotAIService();
    trackingProvider = GameTrackingProvider();

    gameProvider = GameProvider(
      hapticService: mockHaptic,
      statsService: mockStats,
      botAIService: mockBotAI,
      trackingProvider: trackingProvider,
    );
  });

  group('GameProvider - Initialization', () {
    test('should have no active game initially', () {
      expect(gameProvider.hasActiveGame, false);
      expect(gameProvider.gameState, null);
    });

    test('should not be paused initially', () {
      expect(gameProvider.isPaused, false);
    });

    test('should have default reaction time', () {
      expect(gameProvider.currentReactionTimeMs, 3000);
    });
  });

  group('GameProvider - Game Creation', () {
    test('should create a new game with players', () async {
      final players = [
        Player(id: 'human', name: 'Player', isHuman: true, position: 0),
        Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
        Player(id: 'bot2', name: 'Bot 2', isHuman: false, position: 2),
      ];

      gameProvider.createNewGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
        reactionTimeMs: 3000,
      );

      expect(gameProvider.hasActiveGame, true);
      expect(gameProvider.gameState, isNotNull);
      expect(gameProvider.gameState!.players.length, 3);
    });

    test('should initialize game in setup phase', () async {
      final players = [
        Player(id: 'human', name: 'Player', isHuman: true, position: 0),
        Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
      ];

      gameProvider.createNewGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.easy,
        reactionTimeMs: 3000,
      );

      // Game starts in setup phase (memorization)
      expect(gameProvider.gameState!.phase, isIn([GamePhase.setup, GamePhase.playing]));
    });

    test('should load MMR when SBMM is enabled', () async {
      mockStats.mockStats['mmr'] = 750;

      final players = [
        Player(id: 'human', name: 'Player', isHuman: true, position: 0),
        Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
      ];

      gameProvider.createNewGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
        reactionTimeMs: 3000,
        useSBMM: true,
      );

      // Wait for async MMR loading
      await Future.delayed(const Duration(milliseconds: 100));

      expect(gameProvider.playerMMR, 750);
    });

    test('should not load MMR when SBMM is disabled', () async {
      mockStats.mockStats['mmr'] = 750;

      final players = [
        Player(id: 'human', name: 'Player', isHuman: true, position: 0),
        Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
      ];

      gameProvider.createNewGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
        reactionTimeMs: 3000,
        useSBMM: false,
      );

      expect(gameProvider.playerMMR, null);
    });
  });

  group('GameProvider - Player Actions', () {
    late List<Player> players;

    setUp(() async {
      players = [
        Player(id: 'human', name: 'Player', isHuman: true, position: 0),
        Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
      ];

      gameProvider.createNewGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
        reactionTimeMs: 3000,
      );

      // Move to playing phase
      gameProvider.gameState!.phase = GamePhase.playing;
      gameProvider.gameState!.currentPlayerIndex = 0; // Human's turn
    });

    test('should allow human to draw card on their turn', () {
      final deckSizeBefore = gameProvider.gameState!.deck.length;

      gameProvider.drawCard();

      expect(gameProvider.gameState!.drawnCard, isNotNull);
      expect(gameProvider.gameState!.deck.length, deckSizeBefore - 1);
    });

    test('should not allow drawing when not in playing phase', () {
      gameProvider.gameState!.phase = GamePhase.setup;
      final deckSizeBefore = gameProvider.gameState!.deck.length;

      gameProvider.drawCard();

      expect(gameProvider.gameState!.drawnCard, null);
      expect(gameProvider.gameState!.deck.length, deckSizeBefore);
    });

    test('should trigger haptic feedback on replace card', () {
      gameProvider.drawCard();
      mockHaptic.reset();

      gameProvider.replaceCard(0);

      expect(mockHaptic.cardTapCount, 1);
    });

    test('should trigger haptic feedback on discard', () {
      gameProvider.drawCard();
      mockHaptic.reset();

      gameProvider.discardDrawnCard();

      expect(mockHaptic.cardTapCount, 1);
    });
  });

  // Dutch Call tests moved to game_provider_comprehensive_test.dart

  group('GameProvider - IGameController Interface', () {
    setUp(() async {
      final players = [
        Player(id: 'human', name: 'Player', isHuman: true, position: 0),
        Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
      ];

      gameProvider.createNewGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
        reactionTimeMs: 3000,
      );
    });

    test('localPlayer should return the human player', () {
      expect(gameProvider.localPlayer, isNotNull);
      expect(gameProvider.localPlayer!.isHuman, true);
      expect(gameProvider.localPlayer!.id, 'human');
    });

    test('isLocalPlayerTurn should be true when human plays', () {
      gameProvider.gameState!.phase = GamePhase.playing;
      gameProvider.gameState!.currentPlayerIndex = 0;

      expect(gameProvider.isLocalPlayerTurn, true);
    });

    test('isLocalPlayerTurn should be false when bot plays', () {
      gameProvider.gameState!.phase = GamePhase.playing;
      gameProvider.gameState!.currentPlayerIndex = 1;

      expect(gameProvider.isLocalPlayerTurn, false);
    });

    test('canLocalPlayerAct should consider phase and turn', () {
      gameProvider.gameState!.phase = GamePhase.playing;
      gameProvider.gameState!.currentPlayerIndex = 0;

      expect(gameProvider.canLocalPlayerAct, true);

      gameProvider.gameState!.phase = GamePhase.setup;
      expect(gameProvider.canLocalPlayerAct, false);
    });
  });

  group('GameProvider - Pause/Resume', () {
    setUp(() {
      final players = [
        Player(id: 'human', name: 'Player', isHuman: true, position: 0),
        Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
      ];

      gameProvider.createNewGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
        reactionTimeMs: 3000,
      );
      gameProvider.gameState!.phase = GamePhase.playing;
    });

    test('pauseGame sets isPaused to true', () {
      gameProvider.pauseGame();
      expect(gameProvider.isPaused, true);
    });

    test('resumeGame sets isPaused to false', () {
      gameProvider.pauseGame();
      gameProvider.resumeGame();
      expect(gameProvider.isPaused, false);
    });

    test('pause change l\'état isPaused', () {
      gameProvider.pauseGame();
      expect(gameProvider.isPaused, isTrue);
      expect(gameProvider.isProcessing, isFalse);
    });
  });

  group('GameProvider - End Game', () {
    setUp(() {
      final players = [
        Player(id: 'human', name: 'Player', isHuman: true, position: 0),
        Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
      ];

      gameProvider.createNewGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
        reactionTimeMs: 3000,
      );
      gameProvider.gameState!.phase = GamePhase.playing;
    });

    test('quitGame reset l\'état', () {
      gameProvider.quitGame();

      expect(gameProvider.gameState, isNull);
      expect(gameProvider.hasActiveGame, isFalse);
      expect(gameProvider.isPaused, isFalse);
    });
  });

  group('GameProvider - Tournament', () {
    setUp(() {
      final players = [
        Player(id: 'human', name: 'Player', isHuman: true, position: 0),
        Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
        Player(id: 'bot2', name: 'Bot 2', isHuman: false, position: 2),
        Player(id: 'bot3', name: 'Bot 3', isHuman: false, position: 3),
      ];

      gameProvider.createNewGame(
        players: players,
        gameMode: GameMode.tournament,
        difficulty: Difficulty.medium,
        reactionTimeMs: 3000,
        tournamentRound: 1,
      );
    });

    test('mode tournoi existe', () {
      expect(gameProvider.gameState!.gameMode, GameMode.tournament);
    });
  });
}
