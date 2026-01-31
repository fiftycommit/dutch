import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/providers/managers/solo/bot_orchestrator.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';
import '../../mocks/mock_services.dart';

void main() {
  late MockBotAIService mockBotAI;
  late BotOrchestrator orchestrator;

  setUp(() {
    mockBotAI = MockBotAIService();
    orchestrator = BotOrchestrator(botAIService: mockBotAI);
  });

  group('BotOrchestrator - shouldBotPlay', () {
    test('returns false when gameState is null', () {
      expect(orchestrator.shouldBotPlay(null, false, false), false);
    });

    test('returns false when isProcessing is true', () {
      final gs = _createTestGameState();
      gs.currentPlayerIndex = 1; // Bot turn
      expect(orchestrator.shouldBotPlay(gs, true, false), false);
    });

    test('returns false when phase is not playing', () {
      final gs = _createTestGameState();
      gs.currentPlayerIndex = 1;
      gs.phase = GamePhase.reaction;
      expect(orchestrator.shouldBotPlay(gs, false, false), false);
    });

    test('returns false when current player is human', () {
      final gs = _createTestGameState();
      gs.currentPlayerIndex = 0; // Human turn
      expect(orchestrator.shouldBotPlay(gs, false, false), false);
    });

    test('returns false when isPaused is true', () {
      final gs = _createTestGameState();
      gs.currentPlayerIndex = 1;
      expect(orchestrator.shouldBotPlay(gs, false, true), false);
    });

    test('returns true when bot should play', () {
      final gs = _createTestGameState();
      gs.currentPlayerIndex = 1; // Bot turn
      gs.phase = GamePhase.playing;
      expect(orchestrator.shouldBotPlay(gs, false, false), true);
    });
  });

  group('BotOrchestrator - simulateBotReaction', () {
    test('returns false when phase is not reaction', () async {
      final gs = _createTestGameState();
      gs.phase = GamePhase.playing;

      final result = await orchestrator.simulateBotReaction(gs, null, false);
      expect(result, false);
    });

    test('returns false when isPaused', () async {
      final gs = _createTestGameState();
      gs.phase = GamePhase.reaction;

      final result = await orchestrator.simulateBotReaction(gs, null, true);
      expect(result, false);
    });

    test('returns false when no top discard card', () async {
      final gs = _createTestGameState();
      gs.phase = GamePhase.reaction;
      gs.discardPile.clear();

      final result = await orchestrator.simulateBotReaction(gs, null, false);
      expect(result, false);
    });

    test('returns true when bot matches', () async {
      final gs = _createTestGameState();
      gs.phase = GamePhase.reaction;
      mockBotAI.reactionMatchResult = true;

      final result = await orchestrator.simulateBotReaction(gs, null, false);
      expect(result, true);
      expect(mockBotAI.tryReactionMatchCount, greaterThan(0));
    });

    test('returns false when no bot matches', () async {
      final gs = _createTestGameState();
      gs.phase = GamePhase.reaction;
      mockBotAI.reactionMatchResult = false;

      final result = await orchestrator.simulateBotReaction(gs, null, false);
      expect(result, false);
    });

    test('passes playerMMR to bot AI', () async {
      final gs = _createTestGameState();
      gs.phase = GamePhase.reaction;

      await orchestrator.simulateBotReaction(gs, 750, false);
      expect(mockBotAI.tryReactionMatchCount, greaterThan(0));
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
      PlayingCard.create('clubs', '3'),
      PlayingCard.create('spades', '4'),
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
