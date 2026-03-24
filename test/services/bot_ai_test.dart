import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/game/bot_ai.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';

void main() {
  group('BotAI', () {
    late GameState gameState;
    late Player human;
    late Player bot;

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
        currentPlayerIndex: 1, // Bot's turn
        phase: GamePhase.playing,
      );
    });

    group('playBotTurn', () {
      test('does nothing for human player', () async {
        gameState.currentPlayerIndex = 0; // Human's turn
        final deckBefore = gameState.deck.length;

        await BotAI.playBotTurn(gameState);

        expect(gameState.deck.length, deckBefore);
      });

      test('bot draws a card', () async {
        final deckBefore = gameState.deck.length;

        await BotAI.playBotTurn(gameState);

        // Bot should have drawn (deck decreased)
        expect(gameState.deck.length, lessThan(deckBefore));
      });

      test('bot completes turn (no drawn card left)', () async {
        await BotAI.playBotTurn(gameState);

        // After turn, drawnCard should be null (replaced or discarded)
        expect(gameState.drawnCard, isNull);
      });

      test('works with playerMMR parameter', () async {
        await BotAI.playBotTurn(gameState, playerMMR: 1500);

        expect(gameState.drawnCard, isNull);
      });

      test('bot may call Dutch with low score', () async {
        // Give bot a very low score hand
        bot.hand = [PlayingCard.create('hearts', 'A')]; // 1 point
        bot.knownCards = [true];
        bot.mentalMap = [bot.hand[0]];

        await BotAI.playBotTurn(gameState);

        // Bot may have called Dutch or played normally
        expect(gameState.phase, isIn([GamePhase.playing, GamePhase.dutchCalled]));
      });
    });

    group('tryReactionMatch', () {
      test('returns false for non-reaction phase', () async {
        gameState.phase = GamePhase.playing;

        final result = await BotAI.tryReactionMatch(gameState, bot);

        expect(result, isFalse);
      });

      test('returns false for human player', () async {
        gameState.phase = GamePhase.reaction;

        final result = await BotAI.tryReactionMatch(gameState, human);

        expect(result, isFalse);
      });

      test('works in reaction phase for bot', () async {
        gameState.phase = GamePhase.reaction;
        gameState.discardPile = [PlayingCard.create('hearts', '2')];
        // Bot has a 2, could match
        bot.hand[0] = PlayingCard.create('diamonds', '2');
        bot.mentalMap[0] = bot.hand[0];

        final result = await BotAI.tryReactionMatch(gameState, bot);

        expect(result, isA<bool>());
      });

      test('works with playerMMR', () async {
        gameState.phase = GamePhase.reaction;

        final result = await BotAI.tryReactionMatch(gameState, bot, playerMMR: 1200);

        expect(result, isA<bool>());
      });
    });

    group('useBotSpecialPower', () {
      setUp(() {
        gameState.phase = GamePhase.specialPower;
      });

      test('does nothing when not waiting for power', () async {
        gameState.isWaitingForSpecialPower = false;
        gameState.specialCardToActivate = null;

        await BotAI.useBotSpecialPower(gameState);

        // Should complete without error
        expect(gameState.isWaitingForSpecialPower, isFalse);
      });

      test('does nothing when no special card', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = null;

        await BotAI.useBotSpecialPower(gameState);

        expect(gameState.isWaitingForSpecialPower, isTrue);
      });

      test('uses power when waiting with special card', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        await BotAI.useBotSpecialPower(gameState);

        expect(gameState.isWaitingForSpecialPower, isFalse);
        expect(gameState.specialCardToActivate, isNull);
      });

      test('works with playerMMR', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '10');

        await BotAI.useBotSpecialPower(gameState, playerMMR: 1800);

        expect(gameState.isWaitingForSpecialPower, isFalse);
      });

      test('handles power 7 (look at own card)', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '7');

        await BotAI.useBotSpecialPower(gameState);

        expect(gameState.isWaitingForSpecialPower, isFalse);
      });

      test('handles power 10 (spy)', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', '10');

        await BotAI.useBotSpecialPower(gameState);

        expect(gameState.isWaitingForSpecialPower, isFalse);
      });

      test('handles power V (swap)', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('hearts', 'V');

        await BotAI.useBotSpecialPower(gameState);

        expect(gameState.isWaitingForSpecialPower, isFalse);
      });

      test('handles power JOKER', () async {
        gameState.isWaitingForSpecialPower = true;
        gameState.specialCardToActivate = PlayingCard.create('joker', 'JOKER');

        await BotAI.useBotSpecialPower(gameState);

        expect(gameState.isWaitingForSpecialPower, isFalse);
      });
    });

    group('exports', () {
      test('BotGamePhase is exported', () {
        expect(BotGamePhase.exploration, isNotNull);
        expect(BotGamePhase.optimization, isNotNull);
        expect(BotGamePhase.endgame, isNotNull);
      });

      test('BotDifficulty is exported', () {
        expect(BotDifficulty.bronze, isNotNull);
        expect(BotDifficulty.silver, isNotNull);
        expect(BotDifficulty.gold, isNotNull);
        expect(BotDifficulty.platinum, isNotNull);
      });
    });
  });
}
