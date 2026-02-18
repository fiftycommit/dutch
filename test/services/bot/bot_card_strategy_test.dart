import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/game/bot/bot_card_strategy.dart';
import 'package:dutch_game/services/game/bot/bot_difficulty.dart';
import 'package:dutch_game/services/game/bot/bot_config.dart';
import 'package:dutch_game/services/game/bot/human_threat_tracker.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';

void main() {
  group('BotCardStrategy', () {
    late GameState gameState;
    late Player bot;

    setUp(() {
      HumanThreatTracker().reset();

      final players = [
        Player(id: 'human', name: 'Human', isHuman: true, position: 0),
        Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
      ];

      for (var player in players) {
        player.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '5'),
          PlayingCard.create('clubs', '8'),
          PlayingCard.create('spades', 'R'),
        ];
        player.knownCards = List.filled(4, false, growable: true);
        if (!player.isHuman) {
          player.initializeBotMemory();
        }
      }

      gameState = GameState(
        players: players,
        deck: GameState.createFullDeck().sublist(0, 40),
        discardPile: [PlayingCard.create('hearts', '3')],
        currentPlayerIndex: 1,
        phase: GamePhase.playing,
      );

      bot = players[1];
    });

    group('decideCardAction', () {
      test('discards when no drawn card', () async {
        gameState.drawnCard = null;

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.bronze,
          BotGamePhase.exploration,
        );

        // Should return early without error
        expect(gameState.drawnCard, isNull);
      });

      test('processes drawn card with bronze difficulty', () async {
        gameState.drawnCard = PlayingCard.create('hearts', '2');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.bronze,
          BotGamePhase.exploration,
        );

        // Card should be processed (either replaced or discarded)
        expect(gameState.drawnCard, isNull);
      });

      test('processes drawn card with silver difficulty', () async {
        gameState.drawnCard = PlayingCard.create('hearts', '2');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.silver,
          BotGamePhase.optimization,
        );

        expect(gameState.drawnCard, isNull);
      });

      test('processes drawn card with gold difficulty', () async {
        gameState.drawnCard = PlayingCard.create('hearts', '2');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.gold,
          BotGamePhase.optimization,
        );

        expect(gameState.drawnCard, isNull);
      });

      test('processes drawn card with platinum difficulty', () async {
        gameState.drawnCard = PlayingCard.create('hearts', '2');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.platinum,
          BotGamePhase.endgame,
        );

        expect(gameState.drawnCard, isNull);
      });

      test('handles high value drawn card', () async {
        gameState.drawnCard = PlayingCard.create('spades', 'R'); // 13 points

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.gold,
          BotGamePhase.optimization,
        );

        expect(gameState.drawnCard, isNull);
      });

      test('handles low value drawn card', () async {
        gameState.drawnCard = PlayingCard.create('hearts', 'A'); // 1 point

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.gold,
          BotGamePhase.optimization,
        );

        expect(gameState.drawnCard, isNull);
      });

      test('handles Joker drawn card', () async {
        gameState.drawnCard = PlayingCard.create('hearts', 'JOKER'); // 0 points

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.gold,
          BotGamePhase.optimization,
        );

        expect(gameState.drawnCard, isNull);
      });
    });

    group('BotGamePhase effects', () {
      test('exploration phase behavior', () async {
        gameState.drawnCard = PlayingCard.create('hearts', '5');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.silver,
          BotGamePhase.exploration,
        );

        expect(gameState.drawnCard, isNull);
      });

      test('optimization phase behavior', () async {
        gameState.drawnCard = PlayingCard.create('hearts', '5');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.silver,
          BotGamePhase.optimization,
        );

        expect(gameState.drawnCard, isNull);
      });

      test('endgame phase behavior', () async {
        gameState.drawnCard = PlayingCard.create('hearts', '5');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.silver,
          BotGamePhase.endgame,
        );

        expect(gameState.drawnCard, isNull);
      });
    });

    group('Bot with known cards', () {
      test('replaces known high card with low draw', () async {
        // Bot knows all cards
        bot.mentalMap[0] = PlayingCard.create('hearts', 'A'); // 1 point
        bot.mentalMap[1] = PlayingCard.create('diamonds', '5'); // 5 points
        bot.mentalMap[2] = PlayingCard.create('clubs', '8'); // 8 points
        bot.mentalMap[3] = PlayingCard.create('spades', 'R'); // 13 points

        gameState.drawnCard = PlayingCard.create('hearts', '2'); // 2 points

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.platinum,
          BotGamePhase.optimization,
        );

        expect(gameState.drawnCard, isNull);
      });
    });

    group('difficulty ladder behavior', () {
      test('bronze discards slight gain while platinum keeps it', () async {
        // Main connue, sans doublon.
        bot.hand = [
          PlayingCard.create('hearts', 'A'), // 1
          PlayingCard.create('diamonds', '5'), // 5
          PlayingCard.create('clubs', '7'), // 7
          PlayingCard.create('spades', '10'), // 10 (pire)
        ];
        bot.knownCards = List.filled(4, true, growable: true);
        bot.mentalMap = List<PlayingCard?>.from(bot.hand);

        // Carte légèrement meilleure que la pire (gain = 1)
        gameState.drawnCard = PlayingCard.create('hearts', '9');
        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.bronze,
          BotGamePhase.optimization,
        );

        // Bronze très faible: un petit gain n'est pas jugé suffisant.
        expect(
            bot.hand.any((c) => c.value == '10' && c.suit == 'spades'), isTrue);
        expect(
            bot.hand.any((c) => c.value == '9' && c.suit == 'hearts'), isFalse);

        // Reset même scénario pour Platinum.
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '5'),
          PlayingCard.create('clubs', '7'),
          PlayingCard.create('spades', '10'),
        ];
        bot.knownCards = List.filled(4, true, growable: true);
        bot.mentalMap = List<PlayingCard?>.from(bot.hand);
        gameState.drawnCard = PlayingCard.create('hearts', '9');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.platinum,
          BotGamePhase.optimization,
        );

        // Platinum: garde l'amélioration même faible.
        expect(bot.hand.any((c) => c.value == '10' && c.suit == 'spades'),
            isFalse);
        expect(
            bot.hand.any((c) => c.value == '9' && c.suit == 'hearts'), isTrue);
      });

      test('platinum can equal-swap in tense endgame while bronze refuses',
          () async {
        // Table tendue: adversaire à 2 cartes.
        gameState.players[0].hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '2'),
        ];

        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '4'),
          PlayingCard.create('clubs', '7'),
          PlayingCard.create('clubs', '10'), // pire connue
        ];
        bot.knownCards = List.filled(4, true, growable: true);
        bot.mentalMap = List<PlayingCard?>.from(bot.hand);

        // Même valeur en pioche (10), identité différente.
        gameState.drawnCard = PlayingCard.create('hearts', '10');
        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.bronze,
          BotGamePhase.endgame,
        );

        // Bronze garde sa carte originale.
        expect(
            bot.hand.any((c) => c.value == '10' && c.suit == 'clubs'), isTrue);
        expect(bot.hand.any((c) => c.value == '10' && c.suit == 'hearts'),
            isFalse);

        // Reset pour Platinum.
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '4'),
          PlayingCard.create('clubs', '7'),
          PlayingCard.create('clubs', '10'),
        ];
        bot.knownCards = List.filled(4, true, growable: true);
        bot.mentalMap = List<PlayingCard?>.from(bot.hand);
        gameState.drawnCard = PlayingCard.create('hearts', '10');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.platinum,
          BotGamePhase.endgame,
        );

        // Platinum accepte l'échange à valeur égale pour sécuriser l'endgame.
        expect(
            bot.hand.any((c) => c.value == '10' && c.suit == 'clubs'), isFalse);
        expect(
            bot.hand.any((c) => c.value == '10' && c.suit == 'hearts'), isTrue);
      });
    });

    group('platinum contextual unknown swaps', () {
      test('targets suspicious unknown card first', () async {
        bot.mentalMap = [
          bot.hand[0],
          bot.hand[1],
          null,
          null,
        ];
        bot.knownCards = [true, true, false, false];
        bot.setUnknownCardHint(2,
            quality: 0.85,
            confidence: 0.90,
            actionCount: gameState.actionCount);
        bot.setUnknownCardHint(3,
            quality: -0.80,
            confidence: 0.95,
            actionCount: gameState.actionCount);

        gameState.drawnCard = PlayingCard.create('hearts', '6');
        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.platinum,
          BotGamePhase.exploration,
        );

        expect(gameState.drawnCard, isNull);
        expect(bot.hand[3].value, equals('6'));
        expect(bot.hand[2].value, equals('8'));
      });

      test('keeps likely good unknown when draw is only medium', () async {
        bot.mentalMap = [
          bot.hand[0],
          bot.hand[1],
          bot.hand[2],
          null,
        ];
        bot.knownCards = [true, true, true, false];
        bot.setUnknownCardHint(3,
            quality: 0.95,
            confidence: 0.95,
            actionCount: gameState.actionCount);

        final cardBefore = bot.hand[3];
        gameState.drawnCard = PlayingCard.create('clubs', '5');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.platinum,
          BotGamePhase.optimization,
        );

        expect(gameState.drawnCard, isNull);
        expect(bot.hand[3], equals(cardBefore));
        expect(gameState.discardPile.last.value, equals('5'));
      });
    });

    group('bronze blackout behavior', () {
      test('bronze can enter blackout after enough turns', () async {
        gameState.turnCount = 3;
        gameState.actionCount = 20;
        gameState.drawnCard = PlayingCard.create('hearts', '6');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.bronze,
          BotGamePhase.optimization,
        );

        expect(bot.bronzeBlackoutActive, isTrue);
      });
    });
  });
}
