import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';
import 'package:dutch_game/services/game/bot/bot_config.dart';
import 'package:dutch_game/services/game/bot/bot_difficulty.dart';
import 'package:dutch_game/services/game/bot/bot_dutch_strategy.dart';
import 'package:dutch_game/services/game/bot/bot_fair_play_audit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BotFairPlayAudit', () {
    late GameState gameState;
    late Player bot;
    late Player human;

    setUp(() {
      human = Player(
        id: 'human',
        name: 'Human',
        isHuman: true,
        position: 0,
      )
        ..hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '5'),
          PlayingCard.create('clubs', '8'),
          PlayingCard.create('spades', 'R'),
        ]
        ..knownCards = [false, false, false, false];

      bot = Player(
        id: 'bot',
        name: 'Bot',
        isHuman: false,
        botBehavior: BotBehavior.balanced,
        botSkillLevel: BotSkillLevel.platinum,
        position: 1,
      )
        ..hand = [
          PlayingCard.create('hearts', '2'),
          PlayingCard.create('diamonds', '3'),
          PlayingCard.create('clubs', '4'),
          PlayingCard.create('spades', '5'),
        ]
        ..knownCards = [true, true, true, true]
        ..mentalMap = [
          PlayingCard.create('hearts', '2'),
          PlayingCard.create('diamonds', '3'),
          PlayingCard.create('clubs', '4'),
          PlayingCard.create('spades', '5'),
        ];

      gameState = GameState(
        players: [human, bot],
        deck: GameState.createFullDeck().sublist(0, 30),
        discardPile: [PlayingCard.create('hearts', '6')],
        currentPlayerIndex: 1,
        phase: GamePhase.playing,
      );
    });

    test('knowledge + dutch audit passes on coherent state', () {
      final difficulty = BotDifficulty.platinum;
      final phase = BotConfig.getBotPhase(bot, gameState);
      final decision = BotDutchStrategy.shouldCallDutch(
        gameState,
        bot,
        difficulty,
        phase,
      );

      expect(
        () => BotFairPlayAudit.auditKnowledgeState(
          gameState,
          bot,
          difficulty,
          stage: 'test_ok',
        ),
        returnsNormally,
      );

      expect(
        () => BotFairPlayAudit.auditDutchDecisionBlindness(
          gameState,
          bot,
          difficulty,
          phase,
          decision,
        ),
        returnsNormally,
      );
    });

    test('knowledge audit fails on impossible perfect-memory mismatch', () {
      bot.mentalMap[0] = PlayingCard.create('clubs', 'R');
      final difficulty = BotDifficulty.platinum;

      expect(
        () => BotFairPlayAudit.auditKnowledgeState(
          gameState,
          bot,
          difficulty,
          stage: 'test_mismatch',
        ),
        throwsStateError,
      );
    });
  });
}
