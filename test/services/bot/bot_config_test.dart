import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/game/bot/bot_config.dart';
import 'package:dutch_game/services/game/bot/bot_difficulty.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';

void main() {
  group('BotConfig', () {
    late GameState gameState;
    late Player bot;

    setUp(() {
      final human = Player(id: 'human', name: 'Human', isHuman: true, position: 0);
      bot = Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1);

      human.hand = [
        PlayingCard.create('hearts', 'A'),
        PlayingCard.create('diamonds', '5'),
        PlayingCard.create('clubs', '8'),
        PlayingCard.create('spades', 'R'),
      ];
      human.knownCards = List.filled(4, false, growable: true);

      bot.hand = [
        PlayingCard.create('hearts', '2'),
        PlayingCard.create('diamonds', '3'),
        PlayingCard.create('clubs', '4'),
        PlayingCard.create('spades', '5'),
      ];
      bot.knownCards = List.filled(4, false, growable: true);
      bot.initializeBotMemory();

      gameState = GameState(
        players: [human, bot],
        deck: GameState.createFullDeck().sublist(0, 40),
        discardPile: [PlayingCard.create('hearts', '6')],
        currentPlayerIndex: 1,
        phase: GamePhase.playing,
      );
    });

    group('getBotPhase', () {
      test('returns exploration when not all cards known', () {
        // Bot knows only 2 cards with high values (score > 8 to avoid endgame trigger)
        bot.hand = [
          PlayingCard.create('hearts', '6'),   // 6 points
          PlayingCard.create('diamonds', '7'), // 7 points
          PlayingCard.create('clubs', '4'),    // 4 points
          PlayingCard.create('spades', '5'),   // 5 points
        ];
        bot.mentalMap = [bot.hand[0], bot.hand[1], null, null]; // Score estimé = 6+7 = 13 > 8

        final phase = BotConfig.getBotPhase(bot, gameState);

        expect(phase, BotGamePhase.exploration);
      });

      test('returns optimization when all cards known and score high', () {
        // Bot knows all cards
        bot.mentalMap = List.from(bot.hand);
        // High score hand
        bot.hand = [
          PlayingCard.create('hearts', 'R'), // 13
          PlayingCard.create('diamonds', 'D'), // 12
          PlayingCard.create('clubs', 'V'), // 11
          PlayingCard.create('spades', '10'), // 10
        ];
        bot.mentalMap = List.from(bot.hand);

        final phase = BotConfig.getBotPhase(bot, gameState);

        expect(phase, BotGamePhase.optimization);
      });

      test('returns endgame when estimated score is low', () {
        // Low score hand
        bot.hand = [PlayingCard.create('hearts', 'A')]; // 1 point
        bot.knownCards = [true];
        bot.mentalMap = [bot.hand[0]];

        final phase = BotConfig.getBotPhase(bot, gameState);

        expect(phase, BotGamePhase.endgame);
      });

      test('returns endgame when someone has few cards', () {
        // Human has only 2 cards
        gameState.players[0].hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '2'),
        ];
        gameState.players[0].knownCards = [true, true];

        final phase = BotConfig.getBotPhase(bot, gameState);

        expect(phase, BotGamePhase.endgame);
      });

      test('returns endgame in tournament with high cumulative score', () {
        gameState.gameMode = GameMode.tournament;
        gameState.tournamentCumulativeScores = {'bot1': 75};

        final phase = BotConfig.getBotPhase(bot, gameState);

        expect(phase, BotGamePhase.endgame);
      });
    });

    group('getThinkingTime', () {
      test('returns default for null behavior', () {
        final time = BotConfig.getThinkingTime(null, BotDifficulty.silver, gameState);

        expect(time, 800);
      });

      test('balanced behavior varies by difficulty', () {
        final bronze = BotConfig.getThinkingTime(BotBehavior.balanced, BotDifficulty.bronze, gameState);
        final platine = BotConfig.getThinkingTime(BotBehavior.balanced, BotDifficulty.platinum, gameState);

        expect(platine, greaterThan(bronze));
      });

      test('balanced behavior takes longer in critical moments', () {
        // Normal game
        final normal = BotConfig.getThinkingTime(BotBehavior.balanced, BotDifficulty.gold, gameState);

        // Critical moment - someone has 2 cards
        gameState.players[0].hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '2'),
        ];
        final critical = BotConfig.getThinkingTime(BotBehavior.balanced, BotDifficulty.gold, gameState);

        expect(critical, greaterThan(normal));
      });

      test('aggressive behavior is fast', () {
        final aggressive = BotConfig.getThinkingTime(BotBehavior.aggressive, BotDifficulty.gold, gameState);
        final balanced = BotConfig.getThinkingTime(BotBehavior.balanced, BotDifficulty.gold, gameState);

        expect(aggressive, lessThan(balanced));
      });

      test('fast behavior returns default time', () {
        final fast = BotConfig.getThinkingTime(BotBehavior.fast, BotDifficulty.silver, gameState);

        expect(fast, 600); // Fast behavior uses default fallthrough (quick thinking)
      });
    });

    group('getSkillDifficulty', () {
      test('returns silver for null', () {
        final difficulty = BotConfig.getSkillDifficulty(null);

        expect(difficulty.name, 'Argent');
      });

      test('maps bronze correctly', () {
        final difficulty = BotConfig.getSkillDifficulty(BotSkillLevel.bronze);

        expect(difficulty.name, 'Bronze');
      });

      test('maps silver correctly', () {
        final difficulty = BotConfig.getSkillDifficulty(BotSkillLevel.silver);

        expect(difficulty.name, 'Argent');
      });

      test('maps gold correctly', () {
        final difficulty = BotConfig.getSkillDifficulty(BotSkillLevel.difficile);

        expect(difficulty.name, 'Difficile');
      });

      test('maps platinum correctly', () {
        final difficulty = BotConfig.getSkillDifficulty(BotSkillLevel.difficile);

        expect(difficulty.name, 'Difficile');
      });
    });

    group('getDifficulty', () {
      test('uses aiParameters when available', () {
        final botWithAI = Player(
          id: 'bot_ai',
          name: 'Bot AI',
          isHuman: false,
          position: 1,
          aiParameters: {
            'memoryAccuracy': 0.9,
            'riskTolerance': 0.5,
            'powerUsageRate': 0.5,
            'caution': 0.5,
            'dutchThreshold': 5.0,
          },
        );

        final difficulty = BotConfig.getDifficulty(botWithAI, null);

        expect(difficulty.name, 'SBMM');
      });

      test('uses playerMMR when no aiParameters', () {
        final difficulty = BotConfig.getDifficulty(bot, 800);

        expect(difficulty.name, 'Difficile');
      });

      test('uses botSkillLevel as fallback', () {
        final botWithSkill = Player(
          id: 'bot_skill',
          name: 'Bot Skill',
          isHuman: false,
          position: 1,
          botSkillLevel: BotSkillLevel.difficile,
        );

        final difficulty = BotConfig.getDifficulty(botWithSkill, null);

        expect(difficulty.name, 'Difficile');
      });
    });

    group('difficultyFromParameters', () {
      test('creates valid difficulty from parameters', () {
        final params = {
          'memoryAccuracy': 0.8,
          'riskTolerance': 0.6,
          'powerUsageRate': 0.7,
        };

        final difficulty = BotConfig.difficultyFromParameters(params);

        expect(difficulty.name, 'SBMM');
        expect(difficulty.reactionSpeed, greaterThan(0.5));
      });

      test('clamps values to valid range', () {
        final params = {
          'memoryAccuracy': 1.5, // > 1.0
          'riskTolerance': -0.5, // < 0.0
          'powerUsageRate': 0.5,
        };

        final difficulty = BotConfig.difficultyFromParameters(params);

        // memoryAccuracy clamped to 1.0 → forgetChancePerTurn = 0
        expect(difficulty.forgetChancePerTurn, 0.0);
      });

      test('uses defaults for missing parameters', () {
        final params = <String, double>{};

        final difficulty = BotConfig.difficultyFromParameters(params);

        expect(difficulty, isNotNull);
        expect(difficulty.reactionSpeed, greaterThan(0.5));
      });

      test('high memory accuracy reduces forget chance', () {
        final highMemory = BotConfig.difficultyFromParameters({
          'memoryAccuracy': 1.0,
        });

        final lowMemory = BotConfig.difficultyFromParameters({
          'memoryAccuracy': 0.0,
        });

        expect(highMemory.forgetChancePerTurn, lessThan(lowMemory.forgetChancePerTurn));
      });
    });

    group('BotGamePhase enum', () {
      test('has all expected values', () {
        expect(BotGamePhase.values, contains(BotGamePhase.exploration));
        expect(BotGamePhase.values, contains(BotGamePhase.optimization));
        expect(BotGamePhase.values, contains(BotGamePhase.endgame));
      });
    });
  });
}
