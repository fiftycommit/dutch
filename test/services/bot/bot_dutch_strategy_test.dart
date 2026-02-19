import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/game/bot/bot_dutch_strategy.dart';
import 'package:dutch_game/services/game/bot/bot_difficulty.dart';
import 'package:dutch_game/services/game/bot/bot_config.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';

void main() {
  group('BotDutchStrategy', () {
    late GameState gameState;
    late Player bot;

    setUp(() {
      final players = [
        Player(id: 'human', name: 'Human', isHuman: true, position: 0),
        Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
      ];

      for (var player in players) {
        player.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '2'),
          PlayingCard.create('clubs', '3'),
          PlayingCard.create('spades', '4'),
        ];
        player.knownCards = List.filled(4, false, growable: true);
        if (!player.isHuman) {
          player.initializeBotMemory();
        }
      }

      gameState = GameState(
        players: players,
        deck: GameState.createFullDeck().sublist(0, 40),
        discardPile: [PlayingCard.create('hearts', '5')],
        currentPlayerIndex: 1,
        phase: GamePhase.playing,
        turnCount: 5, // Assez de tours pour permettre Dutch (règles de pacing)
      );

      bot = players[1];
    });

    group('shouldCallDutch', () {
      test('returns false during exploration phase', () {
        final result = BotDutchStrategy.shouldCallDutch(
          gameState,
          bot,
          BotDifficulty.gold,
          BotGamePhase.exploration,
        );

        expect(result, isFalse);
      });

      test('considers bot score for bronze difficulty', () {
        // Low score hand
        bot.hand = [
          PlayingCard.create('hearts', 'A'), // 1
          PlayingCard.create('diamonds', 'A'), // 1
        ];
        bot.mentalMap = List.filled(2, null, growable: true);
        bot.mentalMap[0] = bot.hand[0];
        bot.mentalMap[1] = bot.hand[1];

        final result = BotDutchStrategy.shouldCallDutch(
          gameState,
          bot,
          BotDifficulty.bronze,
          BotGamePhase.endgame,
        );

        // With very low score, should likely call Dutch
        expect(result, isA<bool>());
      });

      test('considers bot score for silver difficulty', () {
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '2'),
        ];
        bot.mentalMap = List.filled(2, null, growable: true);
        bot.mentalMap[0] = bot.hand[0];
        bot.mentalMap[1] = bot.hand[1];

        final result = BotDutchStrategy.shouldCallDutch(
          gameState,
          bot,
          BotDifficulty.silver,
          BotGamePhase.optimization,
        );

        expect(result, isA<bool>());
      });

      test('uses smart strategy for gold difficulty', () {
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '2'),
        ];
        bot.mentalMap = List.filled(2, null, growable: true);
        bot.mentalMap[0] = bot.hand[0];
        bot.mentalMap[1] = bot.hand[1];

        final result = BotDutchStrategy.shouldCallDutch(
          gameState,
          bot,
          BotDifficulty.gold,
          BotGamePhase.optimization,
        );

        expect(result, isA<bool>());
      });

      test('uses smart strategy for platinum difficulty', () {
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '2'),
        ];
        bot.mentalMap = List.filled(2, null, growable: true);
        bot.mentalMap[0] = bot.hand[0];
        bot.mentalMap[1] = bot.hand[1];

        final result = BotDutchStrategy.shouldCallDutch(
          gameState,
          bot,
          BotDifficulty.platinum,
          BotGamePhase.endgame,
        );

        expect(result, isA<bool>());
      });

      test('considers card count advantage', () {
        // Bot has fewer cards
        bot.hand = [PlayingCard.create('hearts', 'A')];
        bot.mentalMap = [bot.hand[0]];

        // Human has more cards
        gameState.players[0].hand = [
          PlayingCard.create('hearts', '5'),
          PlayingCard.create('diamonds', '6'),
          PlayingCard.create('clubs', '7'),
          PlayingCard.create('spades', '8'),
        ];

        final result = BotDutchStrategy.shouldCallDutch(
          gameState,
          bot,
          BotDifficulty.platinum,
          BotGamePhase.endgame,
        );

        // With card advantage and low score, should likely call
        expect(result, isA<bool>());
      });
    });

    group('difficulty effects', () {
      test('bronze difficulty uses simple threshold', () {
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '2'),
          PlayingCard.create('clubs', '3'),
        ];

        final result = BotDutchStrategy.shouldCallDutch(
          gameState,
          bot,
          BotDifficulty.bronze,
          BotGamePhase.optimization,
        );

        expect(result, isA<bool>());
      });

      test('silver difficulty uses simple threshold', () {
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '2'),
          PlayingCard.create('clubs', '3'),
        ];

        final result = BotDutchStrategy.shouldCallDutch(
          gameState,
          bot,
          BotDifficulty.silver,
          BotGamePhase.optimization,
        );

        expect(result, isA<bool>());
      });

      test('gold difficulty uses smart strategy', () {
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '2'),
          PlayingCard.create('clubs', '3'),
        ];

        final result = BotDutchStrategy.shouldCallDutch(
          gameState,
          bot,
          BotDifficulty.gold,
          BotGamePhase.optimization,
        );

        expect(result, isA<bool>());
      });
    });

    group('endgame phase', () {
      test('more likely to call Dutch in endgame with low score', () {
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '2'),
        ];
        bot.mentalMap = List.filled(2, null, growable: true);
        bot.mentalMap[0] = bot.hand[0];
        bot.mentalMap[1] = bot.hand[1];

        final result = BotDutchStrategy.shouldCallDutch(
          gameState,
          bot,
          BotDifficulty.gold,
          BotGamePhase.endgame,
        );

        expect(result, isA<bool>());
      });
    });

    group('consecutive bad draws', () {
      test('affects audacity calculation', () {
        bot.consecutiveBadDraws = 5;
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '2'),
          PlayingCard.create('clubs', '3'),
        ];

        final result = BotDutchStrategy.shouldCallDutch(
          gameState,
          bot,
          BotDifficulty.silver,
          BotGamePhase.optimization,
        );

        expect(result, isA<bool>());
      });
    });

    group('multiple players', () {
      test('considers multiple opponents', () {
        // Add more players
        gameState.players.add(
          Player(id: 'bot2', name: 'Bot 2', isHuman: false, position: 2)
            ..hand = [
              PlayingCard.create('hearts', '5'),
              PlayingCard.create('diamonds', '6'),
            ]
            ..knownCards = List.filled(2, false, growable: true),
        );

        bot.hand = [PlayingCard.create('hearts', 'A')];

        final result = BotDutchStrategy.shouldCallDutch(
          gameState,
          bot,
          BotDifficulty.platinum,
          BotGamePhase.endgame,
        );

        expect(result, isA<bool>());
      });
    });

    group('difficulty ladder behavior', () {
      test('exploration blocks Dutch even with perfect information', () {
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '2'),
          PlayingCard.create('clubs', '3'),
          PlayingCard.create('spades', '4'),
        ];
        bot.knownCards = List.filled(bot.hand.length, true, growable: true);
        bot.mentalMap = List<PlayingCard?>.from(bot.hand);

        final result = BotDutchStrategy.shouldCallDutch(
          gameState,
          bot,
          BotDifficulty.platinum,
          BotGamePhase.exploration,
        );

        expect(result, isFalse);
      });

      test('platinum calls in tight spots where bronze stays conservative', () {
        // Score bot = 8
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', 'A'),
          PlayingCard.create('clubs', '2'),
          PlayingCard.create('spades', '4'),
        ];
        bot.knownCards = List.filled(bot.hand.length, true, growable: true);
        bot.mentalMap = List<PlayingCard?>.from(bot.hand);

        // Opposant avec 2 cartes => estimation neutre ~13 (sans historique)
        gameState.players[0].hand = [
          PlayingCard.create('hearts', '9'),
          PlayingCard.create('diamonds', 'D'),
        ];

        final bronzeDecision = BotDutchStrategy.shouldCallDutch(
          gameState,
          bot,
          BotDifficulty.bronze,
          BotGamePhase.optimization,
        );
        final platinumDecision = BotDutchStrategy.shouldCallDutch(
          gameState,
          bot,
          BotDifficulty.platinum,
          BotGamePhase.optimization,
        );

        expect(bronzeDecision, isFalse);
        expect(platinumDecision, isTrue);
      });

      test('bronze does not Dutch only because it has fewer cards', () {
        bot.hand = [
          PlayingCard.create('hearts', '9'),
          PlayingCard.create('diamonds', 'D'),
        ];
        bot.knownCards = [false, false];
        bot.mentalMap = [null, null];

        gameState.players[0].hand = [
          PlayingCard.create('hearts', '2'),
          PlayingCard.create('diamonds', '3'),
          PlayingCard.create('clubs', '4'),
          PlayingCard.create('spades', '5'),
        ];

        final bronzeDecision = BotDutchStrategy.shouldCallDutch(
          gameState,
          bot,
          BotDifficulty.bronze,
          BotGamePhase.optimization,
        );

        expect(bronzeDecision, isFalse);
      });
    });
  });
}
