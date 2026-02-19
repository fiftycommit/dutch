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

    group('silver contextual behavior', () {
      test('replaces first unknown card when drawing non-7', () async {
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '9'),
          PlayingCard.create('clubs', '10'),
          PlayingCard.create('spades', 'R'),
        ];
        bot.knownCards = [true, false, false, true];
        bot.mentalMap = [
          bot.hand[0],
          null,
          null,
          bot.hand[3],
        ];

        gameState.drawnCard = PlayingCard.create('hearts', '2');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.silver,
          BotGamePhase.optimization,
        );

        expect(bot.hand[1].value, equals('2'));
      });

      test('discards 7 when no known card is above 7', () async {
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '4'),
          PlayingCard.create('clubs', '6'),
          PlayingCard.create('spades', '7'),
        ];
        bot.knownCards = List.filled(4, true, growable: true);
        bot.mentalMap = List<PlayingCard?>.from(bot.hand);
        gameState.drawnCard = PlayingCard.create('diamonds', '7');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.silver,
          BotGamePhase.optimization,
        );

        expect(gameState.drawnCard, isNull);
        expect(gameState.discardPile.last.value, equals('7'));
        expect(gameState.isWaitingForSpecialPower, isTrue);
        expect(gameState.specialCardToActivate?.value, equals('7'));
      });
    });

    group('difficulty ladder behavior', () {
      test('bronze keeps slight immediate gain by replacing higher known card',
          () async {
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

        // Bronze contextuel: remplace la carte supérieure connue.
        expect(bot.hand.any((c) => c.value == '10' && c.suit == 'spades'),
            isFalse);
        expect(
            bot.hand.any((c) => c.value == '9' && c.suit == 'hearts'), isTrue);

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

    group('gold seven behavior', () {
      test('discards 7 when an unknown card exists', () async {
        // Main partiellement inconnue (setup par défaut: 2 connues, 2 inconnues)
        gameState.drawnCard = PlayingCard.create('hearts', '7');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.gold,
          BotGamePhase.exploration,
        );

        expect(gameState.drawnCard, isNull);
        expect(gameState.discardPile.last.value, equals('7'));
      });

      test('keeps 7 only to replace a known card strictly above 7', () async {
        bot.hand = [
          PlayingCard.create('hearts', 'A'), // 1
          PlayingCard.create('diamonds', '5'), // 5
          PlayingCard.create('clubs', '8'), // 8
          PlayingCard.create('spades', 'R'), // 13 (pire)
        ];
        bot.knownCards = List.filled(4, true, growable: true);
        bot.mentalMap = List<PlayingCard?>.from(bot.hand);
        gameState.drawnCard = PlayingCard.create('hearts', '7');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.gold,
          BotGamePhase.optimization,
        );

        expect(gameState.drawnCard, isNull);
        expect(
            bot.hand.any((c) => c.value == '7' && c.suit == 'hearts'), isTrue);
        expect(
            bot.hand.any((c) => c.value == 'R' && c.suit == 'spades'), isFalse);
      });

      test('discards 7 when all known cards are 7 or lower', () async {
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '3'),
          PlayingCard.create('clubs', '5'),
          PlayingCard.create('spades', '7'),
        ];
        bot.knownCards = List.filled(4, true, growable: true);
        bot.mentalMap = List<PlayingCard?>.from(bot.hand);
        gameState.drawnCard = PlayingCard.create('diamonds', '7');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.gold,
          BotGamePhase.endgame,
        );

        expect(gameState.drawnCard, isNull);
        expect(gameState.discardPile.last.value, equals('7'));
        expect(bot.hand.any((c) => c.value == '7' && c.suit == 'diamonds'),
            isFalse);
      });
    });

    group('silver reaction behavior', () {
      test('retries once on confusion when a known match exists', () async {
        gameState.phase = GamePhase.reaction;
        gameState.discardPile = [PlayingCard.create('hearts', '3')];
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '3'),
          PlayingCard.create('clubs', '5'),
        ];
        bot.knownCards = [true, true, true];
        bot.mentalMap = List<PlayingCard?>.from(bot.hand);

        const forcedConfusionSilver = BotDifficulty(
          name: 'Argent',
          forgetChancePerTurn: 0.24,
          confusionOnSwap: 1.0,
          reactionSpeed: 1.0,
          matchAccuracy: 1.0,
          reactionMatchChance: 1.0,
        );

        final matched = await BotCardStrategy.tryReactionMatch(
          gameState,
          bot,
          forcedConfusionSilver,
          BotGamePhase.endgame,
        );

        expect(matched, isTrue);
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

      test('does not preserve unknown card only because hint is positive',
          () async {
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

        gameState.drawnCard = PlayingCard.create('clubs', '6');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.platinum,
          BotGamePhase.optimization,
        );

        expect(gameState.drawnCard, isNull);
        expect(bot.hand[3].value, equals('6'));
        expect(gameState.discardPile.last.value, equals('R'));
      });

      test('stable table: prioritizes unknown resolution over tempo self-match',
          () async {
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '5'),
          PlayingCard.create('clubs', '8'),
          PlayingCard.create('spades', 'R'),
        ];
        bot.knownCards = [true, true, false, false];
        bot.mentalMap = [
          bot.hand[0],
          bot.hand[1],
          null,
          null,
        ];
        gameState.drawnCard = PlayingCard.create('hearts', '5');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.platinum,
          BotGamePhase.optimization,
        );

        expect(gameState.drawnCard, isNull);
        expect(bot.hand.length, equals(4));
        expect(bot.hand.where((c) => c.value == '5').length, equals(2));
      });

      test('under pressure but behind on cards: prioritizes unknown resolution',
          () async {
        // Table sous pression: adversaire à 2 cartes -> tempo prioritaire autorisé.
        gameState.players[0].hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '2'),
        ];

        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '5'),
          PlayingCard.create('clubs', '8'),
          PlayingCard.create('spades', 'R'),
        ];
        bot.knownCards = [true, true, false, false];
        bot.mentalMap = [
          bot.hand[0],
          bot.hand[1],
          null,
          null,
        ];
        gameState.drawnCard = PlayingCard.create('hearts', '5');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.platinum,
          BotGamePhase.endgame,
        );

        expect(gameState.drawnCard, isNull);
        expect(bot.hand.length, equals(4));
        expect(bot.hand.where((c) => c.value == '5').length, equals(2));
      });

      test('under pressure and not behind: allows tempo self-match', () async {
        gameState.players[0].hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '2'),
        ];

        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '5'),
          PlayingCard.create('spades', 'R'),
        ];
        bot.knownCards = [true, true, false];
        bot.mentalMap = [
          bot.hand[0],
          bot.hand[1],
          null,
        ];
        gameState.drawnCard = PlayingCard.create('hearts', '5');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.platinum,
          BotGamePhase.endgame,
        );

        expect(gameState.drawnCard, isNull);
        expect(bot.hand.length, equals(2));
        expect(bot.hand.where((c) => c.value == '5').length, equals(0));
      });
    });

    group('gold contextual unknown swaps', () {
      test('does not keep a high draw instead of resolving an unknown',
          () async {
        bot.hand = [
          PlayingCard.create('hearts', 'A'),
          PlayingCard.create('diamonds', '5'),
          PlayingCard.create('clubs', '8'),
          PlayingCard.create('spades', 'R'),
        ];
        bot.knownCards = [true, true, false, false];
        bot.mentalMap = [
          bot.hand[0],
          bot.hand[1],
          null,
          null,
        ];
        gameState.drawnCard = PlayingCard.create('hearts', '10');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.gold,
          BotGamePhase.exploration,
        );

        expect(gameState.drawnCard, isNull);
        expect(bot.hand[3].value, equals('10'));
      });
    });

    group('bronze blackout behavior', () {
      test('bronze does not enter blackout automatically', () async {
        gameState.turnCount = 3;
        gameState.actionCount = 20;
        gameState.drawnCard = PlayingCard.create('hearts', '6');

        await BotCardStrategy.decideCardAction(
          gameState,
          bot,
          BotDifficulty.bronze,
          BotGamePhase.optimization,
        );

        expect(bot.bronzeBlackoutActive, isFalse);
      });
    });
  });
}
