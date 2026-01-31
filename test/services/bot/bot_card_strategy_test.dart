import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/game/bot/bot_card_strategy.dart';
import 'package:dutch_game/services/game/bot/bot_difficulty.dart';
import 'package:dutch_game/services/game/bot/bot_config.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';

void main() {
  group('BotCardStrategy', () {
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
          gameState, bot, BotDifficulty.bronze, BotGamePhase.exploration,
        );
        
        // Should return early without error
        expect(gameState.drawnCard, isNull);
      });

      test('processes drawn card with bronze difficulty', () async {
        gameState.drawnCard = PlayingCard.create('hearts', '2');
        
        await BotCardStrategy.decideCardAction(
          gameState, bot, BotDifficulty.bronze, BotGamePhase.exploration,
        );
        
        // Card should be processed (either replaced or discarded)
        expect(gameState.drawnCard, isNull);
      });

      test('processes drawn card with silver difficulty', () async {
        gameState.drawnCard = PlayingCard.create('hearts', '2');
        
        await BotCardStrategy.decideCardAction(
          gameState, bot, BotDifficulty.silver, BotGamePhase.optimization,
        );
        
        expect(gameState.drawnCard, isNull);
      });

      test('processes drawn card with gold difficulty', () async {
        gameState.drawnCard = PlayingCard.create('hearts', '2');
        
        await BotCardStrategy.decideCardAction(
          gameState, bot, BotDifficulty.gold, BotGamePhase.optimization,
        );
        
        expect(gameState.drawnCard, isNull);
      });

      test('processes drawn card with platinum difficulty', () async {
        gameState.drawnCard = PlayingCard.create('hearts', '2');
        
        await BotCardStrategy.decideCardAction(
          gameState, bot, BotDifficulty.platinum, BotGamePhase.endgame,
        );
        
        expect(gameState.drawnCard, isNull);
      });

      test('handles high value drawn card', () async {
        gameState.drawnCard = PlayingCard.create('spades', 'R'); // 13 points
        
        await BotCardStrategy.decideCardAction(
          gameState, bot, BotDifficulty.gold, BotGamePhase.optimization,
        );
        
        expect(gameState.drawnCard, isNull);
      });

      test('handles low value drawn card', () async {
        gameState.drawnCard = PlayingCard.create('hearts', 'A'); // 1 point
        
        await BotCardStrategy.decideCardAction(
          gameState, bot, BotDifficulty.gold, BotGamePhase.optimization,
        );
        
        expect(gameState.drawnCard, isNull);
      });

      test('handles Joker drawn card', () async {
        gameState.drawnCard = PlayingCard.create('hearts', 'JOKER'); // 0 points
        
        await BotCardStrategy.decideCardAction(
          gameState, bot, BotDifficulty.gold, BotGamePhase.optimization,
        );
        
        expect(gameState.drawnCard, isNull);
      });
    });

    group('BotGamePhase effects', () {
      test('exploration phase behavior', () async {
        gameState.drawnCard = PlayingCard.create('hearts', '5');
        
        await BotCardStrategy.decideCardAction(
          gameState, bot, BotDifficulty.silver, BotGamePhase.exploration,
        );
        
        expect(gameState.drawnCard, isNull);
      });

      test('optimization phase behavior', () async {
        gameState.drawnCard = PlayingCard.create('hearts', '5');
        
        await BotCardStrategy.decideCardAction(
          gameState, bot, BotDifficulty.silver, BotGamePhase.optimization,
        );
        
        expect(gameState.drawnCard, isNull);
      });

      test('endgame phase behavior', () async {
        gameState.drawnCard = PlayingCard.create('hearts', '5');
        
        await BotCardStrategy.decideCardAction(
          gameState, bot, BotDifficulty.silver, BotGamePhase.endgame,
        );
        
        expect(gameState.drawnCard, isNull);
      });
    });

    group('Bot with known cards', () {
      test('replaces known high card with low draw', () async {
        // Bot knows all cards
        bot.mentalMap[0] = PlayingCard.create('hearts', 'A');  // 1 point
        bot.mentalMap[1] = PlayingCard.create('diamonds', '5'); // 5 points
        bot.mentalMap[2] = PlayingCard.create('clubs', '8');    // 8 points
        bot.mentalMap[3] = PlayingCard.create('spades', 'R');   // 13 points
        
        gameState.drawnCard = PlayingCard.create('hearts', '2'); // 2 points
        
        await BotCardStrategy.decideCardAction(
          gameState, bot, BotDifficulty.platinum, BotGamePhase.optimization,
        );
        
        expect(gameState.drawnCard, isNull);
      });
    });
  });
}
