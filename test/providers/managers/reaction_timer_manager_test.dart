import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/providers/managers/solo/reaction_timer_manager.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ReactionTimerManager timerManager;
  late int timerEndCount;
  late int timerUpdateCount;

  setUp(() {
    timerEndCount = 0;
    timerUpdateCount = 0;
    timerManager = ReactionTimerManager(
      onTimerEnd: () => timerEndCount++,
      onTimerUpdate: () => timerUpdateCount++,
    );
  });

  tearDown(() {
    timerManager.dispose();
  });

  group('ReactionTimerManager - startReactionPhase', () {
    test('does nothing when isPaused', () {
      final gs = _createTestGameState();
      
      timerManager.startReactionPhase(gs, 3000, true);
      
      expect(gs.phase, GamePhase.playing); // Phase not changed
    });

    test('sets phase to reaction', () {
      final gs = _createTestGameState();
      
      timerManager.startReactionPhase(gs, 3000, false);
      
      expect(gs.phase, GamePhase.reaction);
    });

    test('sets reactionTimeRemaining on gameState', () {
      final gs = _createTestGameState();
      
      timerManager.startReactionPhase(gs, 3000, false);
      
      expect(gs.reactionTimeRemaining, 3000);
    });

    test('sets reactionTimeRemaining on ValueNotifier', () {
      final gs = _createTestGameState();
      
      timerManager.startReactionPhase(gs, 3000, false);
      
      expect(timerManager.reactionTimeRemaining.value, 3000);
    });

    test('calls onTimerUpdate', () {
      final gs = _createTestGameState();
      
      timerManager.startReactionPhase(gs, 3000, false);
      
      expect(timerUpdateCount, greaterThan(0));
    });

    test('timer decrements over time', () async {
      final gs = _createTestGameState();
      
      timerManager.startReactionPhase(gs, 500, false);
      
      // Wait for a few timer ticks
      await Future.delayed(const Duration(milliseconds: 100));
      
      expect(gs.reactionTimeRemaining, lessThan(500));
    });

    test('timer ends and calls onTimerEnd', () async {
      final gs = _createTestGameState();
      
      timerManager.startReactionPhase(gs, 100, false);
      
      // Wait for timer to end
      await Future.delayed(const Duration(milliseconds: 200));
      
      expect(timerEndCount, 1);
    });
  });

  group('ReactionTimerManager - pauseTimer', () {
    test('cancels active timer', () async {
      final gs = _createTestGameState();
      timerManager.startReactionPhase(gs, 3000, false);
      
      final remainingBefore = gs.reactionTimeRemaining;
      timerManager.pauseTimer(gs);
      
      // Wait to ensure timer doesn't continue
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Timer should not have decremented much after pause
      expect(gs.reactionTimeRemaining, remainingBefore);
    });

    test('stores remaining time', () {
      final gs = _createTestGameState();
      timerManager.startReactionPhase(gs, 3000, false);
      gs.reactionTimeRemaining = 2000;
      
      timerManager.pauseTimer(gs);
      
      // Remaining time is stored internally for resume
    });
  });

  group('ReactionTimerManager - resumeTimer', () {
    test('resumes from paused state', () async {
      final gs = _createTestGameState();
      timerManager.startReactionPhase(gs, 3000, false);
      
      // Pause
      await Future.delayed(const Duration(milliseconds: 50));
      timerManager.pauseTimer(gs);
      final pausedTime = gs.reactionTimeRemaining;
      
      // Resume
      timerManager.resumeTimer(gs, false);
      
      expect(timerManager.reactionTimeRemaining.value, pausedTime);
    });
  });

  group('ReactionTimerManager - cancelTimer', () {
    test('cancels timer without storing', () async {
      final gs = _createTestGameState();
      timerManager.startReactionPhase(gs, 3000, false);
      
      timerManager.cancelTimer();
      
      final timeBefore = gs.reactionTimeRemaining;
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Time should not change after cancel
      expect(gs.reactionTimeRemaining, timeBefore);
    });
  });

  group('ReactionTimerManager - dispose', () {
    test('disposes resources without error', () {
      // Create a separate manager for this test to avoid double-dispose
      final separateManager = ReactionTimerManager(
        onTimerEnd: () {},
        onTimerUpdate: () {},
      );
      separateManager.dispose();
      // Should not throw
    });

    test('cancels active timer on dispose', () async {
      // Create a separate manager for this test
      final separateManager = ReactionTimerManager(
        onTimerEnd: () {},
        onTimerUpdate: () {},
      );
      final gs = _createTestGameState();
      separateManager.startReactionPhase(gs, 3000, false);
      
      separateManager.dispose();
      
      // Timer should be cancelled - no exception should be thrown
      await Future.delayed(const Duration(milliseconds: 100));
    });
  });
}

GameState _createTestGameState() {
  final players = [
    Player(id: 'human', name: 'Human', isHuman: true, position: 0),
    Player(id: 'bot_1', name: 'Bot 1', isHuman: false, position: 1),
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
