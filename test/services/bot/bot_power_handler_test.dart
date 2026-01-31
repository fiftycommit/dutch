import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/game/bot/bot_power_handler.dart';
import 'package:dutch_game/services/game/bot/bot_difficulty.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';

void main() {
  group('BotPowerHandler', () {
    late GameState gameState;
    late Player bot;
    late Player human;

    setUp(() {
      human = Player(id: 'human', name: 'Human', isHuman: true, position: 0);
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

    group('useBotSpecialPower', () {
      test('returns early when not waiting for special power', () async {
        gameState.isWaitingForSpecialPower = false;
        gameState.specialCardToActivate = null;
        
        // Should complete without error
        await BotPowerHandler.useBotSpecialPower(gameState, BotDifficulty.gold, null);
        
        expect(gameState.isWaitingForSpecialPower, isFalse);
      });

      test('returns early when special card is null', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = null;
        
        await BotPowerHandler.useBotSpecialPower(gameState, BotDifficulty.gold, null);
        
        // Should not change state
        expect(gameState.isWaitingForSpecialPower, isTrue);
      });

      test('handles power 7 - look at own card', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');
        
        await BotPowerHandler.useBotSpecialPower(gameState, BotDifficulty.gold, null);
        
        expect(gameState.isWaitingForSpecialPower, isFalse);
        expect(gameState.specialCardToActivate, isNull);
      });

      test('handles power 10 - spy on opponent (no context)', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '10');
        
        await BotPowerHandler.useBotSpecialPower(gameState, BotDifficulty.gold, null);
        
        expect(gameState.isWaitingForSpecialPower, isFalse);
        expect(gameState.specialCardToActivate, isNull);
      });

      test('handles power V - swap cards (no context)', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');
        
        await BotPowerHandler.useBotSpecialPower(gameState, BotDifficulty.gold, null);
        
        expect(gameState.isWaitingForSpecialPower, isFalse);
        expect(gameState.specialCardToActivate, isNull);
      });

      test('handles power JOKER - shuffle hand (no context)', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'JOKER');
        
        await BotPowerHandler.useBotSpecialPower(gameState, BotDifficulty.gold, null);
        
        expect(gameState.isWaitingForSpecialPower, isFalse);
        expect(gameState.specialCardToActivate, isNull);
      });
    });

    group('difficulty effects on powers', () {
      test('bronze uses powers', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');
        
        await BotPowerHandler.useBotSpecialPower(gameState, BotDifficulty.bronze, null);
        
        expect(gameState.isWaitingForSpecialPower, isFalse);
      });

      test('silver uses powers', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');
        
        await BotPowerHandler.useBotSpecialPower(gameState, BotDifficulty.silver, null);
        
        expect(gameState.isWaitingForSpecialPower, isFalse);
      });

      test('gold uses powers', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');
        
        await BotPowerHandler.useBotSpecialPower(gameState, BotDifficulty.gold, null);
        
        expect(gameState.isWaitingForSpecialPower, isFalse);
      });

      test('platinum uses powers', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');
        
        await BotPowerHandler.useBotSpecialPower(gameState, BotDifficulty.platinum, null);
        
        expect(gameState.isWaitingForSpecialPower, isFalse);
      });
    });

    group('power effects on game state', () {
      test('power 7 updates bot mental map', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');
        
        // Initially bot may not know all cards
        int initialKnown = bot.mentalMap.where((c) => c != null).length;
        
        await BotPowerHandler.useBotSpecialPower(gameState, BotDifficulty.platinum, null);
        
        int finalKnown = bot.mentalMap.where((c) => c != null).length;
        expect(finalKnown, greaterThanOrEqualTo(initialKnown));
      });

      test('power V may swap cards', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');
        
        // Store original hands
        final originalBotHand = List<PlayingCard>.from(bot.hand);
        final originalHumanHand = List<PlayingCard>.from(human.hand);
        
        await BotPowerHandler.useBotSpecialPower(gameState, BotDifficulty.platinum, null);
        
        // Hands should still have same length
        expect(bot.hand.length, equals(originalBotHand.length));
        expect(human.hand.length, equals(originalHumanHand.length));
      });

      test('power JOKER shuffles target hand', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'JOKER');
        
        await BotPowerHandler.useBotSpecialPower(gameState, BotDifficulty.platinum, null);
        
        // Power should complete without error
        expect(gameState.isWaitingForSpecialPower, isFalse);
      });
    });

    group('multiple opponents', () {
      test('handles game with 3 players', () async {
        final bot2 = Player(id: 'bot2', name: 'Bot 2', isHuman: false, position: 2)
          ..hand = [
            PlayingCard.create('hearts', '9'),
            PlayingCard.create('diamonds', '10'),
          ]
          ..knownCards = List.filled(2, false, growable: true);
        gameState.players.add(bot2);
        
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');
        
        await BotPowerHandler.useBotSpecialPower(gameState, BotDifficulty.gold, null);
        
        expect(gameState.isWaitingForSpecialPower, isFalse);
      });

      test('handles game with 4 players', () async {
        final bot2 = Player(id: 'bot2', name: 'Bot 2', isHuman: false, position: 2)
          ..hand = [PlayingCard.create('hearts', '9')]
          ..knownCards = List.filled(1, false, growable: true);
        final bot3 = Player(id: 'bot3', name: 'Bot 3', isHuman: false, position: 3)
          ..hand = [PlayingCard.create('diamonds', 'D')]
          ..knownCards = List.filled(1, false, growable: true);
        gameState.players.addAll([bot2, bot3]);
        
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '10');
        
        await BotPowerHandler.useBotSpecialPower(gameState, BotDifficulty.platinum, null);
        
        expect(gameState.isWaitingForSpecialPower, isFalse);
      });
    });
  });
}
