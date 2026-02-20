import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/services/game/game_logic.dart';
import 'package:dutch_game/services/game/bot/bot_dutch_strategy.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('GameLogic - Initialization', () {
    test('initializeGame creates valid game state', () {
      final players = createStandardPlayers(botCount: 2);
      final gs = GameLogic.initializeGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
      );

      expect(gs.players.length, 3);
      expect(gs.phase, GamePhase.setup);
      expect(gs.discardPile.length, 1); // Une carte initiale dans la défausse
      expect(gs.drawnCard, isNull);
      expect(gs.dutchCallerId, isNull);
    });

    test('initializeGame distributes 4 cards to each player', () {
      final players = createStandardPlayers(botCount: 3);
      final gs = GameLogic.initializeGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
      );

      for (var player in gs.players) {
        expect(player.hand.length, 4);
        expect(player.knownCards.length, 4);
      }
    });

    test('initializeGame has no duplicate cards', () {
      final players = createStandardPlayers(botCount: 3);
      final gs = GameLogic.initializeGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
      );

      GameStateInvariants.assertNoDuplicateCards(gs);
    });

    test('initializeGame maintains total card count (54 cards)', () {
      final players = createStandardPlayers(botCount: 3);
      final gs = GameLogic.initializeGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
      );

      // 54 cartes total = 52 + 2 jokers
      expect(gs.totalCards, 54);
    });

    test('initializeGame sets random starting player', () {
      final players = createStandardPlayers(botCount: 2);
      final gs = GameLogic.initializeGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
      );

      expect(gs.currentPlayerIndex, inInclusiveRange(0, 2));
    });

    test('bot players have initialized mental map', () {
      final players = createStandardPlayers(botCount: 2);
      final gs = GameLogic.initializeGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
      );

      for (var player in gs.players.where((p) => !p.isHuman)) {
        expect(player.mentalMap.length, 4);
        // Bots connaissent leurs 2 premières cartes
        expect(player.mentalMap[0], isNotNull);
        expect(player.mentalMap[1], isNotNull);
      }
    });

    test('initializeGame supports round-robin deal mode', () {
      final players = createStandardPlayers(botCount: 3);
      final gs = GameLogic.initializeGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
        dealMode: DealMode.roundRobin,
      );

      for (var player in gs.players) {
        expect(player.hand.length, 4);
      }
      GameStateInvariants.assertNoDuplicateCards(gs);
      expect(gs.totalCards, 54);
    });

    test('disjoint deal mode avoids shared values when feasible', () {
      final players =
          createStandardPlayers(botCount: 2); // 3 joueurs => 12 cartes
      final gs = GameLogic.initializeGame(
        players: players,
        gameMode: GameMode.quick,
        difficulty: Difficulty.medium,
        dealMode: DealMode.disjointValues,
      );

      final counts = <String, int>{};
      for (final player in gs.players) {
        for (final card in player.hand) {
          counts[card.value] = (counts[card.value] ?? 0) + 1;
        }
      }
      final overlap =
          counts.values.where((c) => c > 1).fold<int>(0, (a, b) => a + (b - 1));
      expect(overlap, 0);
    });
  });

  group('GameLogic - Draw Card', () {
    test('drawCard sets drawnCard and decreases deck', () {
      final gs = createDeterministicGameState();
      final deckSizeBefore = gs.deck.length;

      GameLogic.drawCard(gs);

      expect(gs.drawnCard, isNotNull);
      expect(gs.deck.length, deckSizeBefore - 1);
    });

    test('drawCard adds to action history', () {
      final gs = createDeterministicGameState();
      final historyBefore = gs.actionHistory.length;

      GameLogic.drawCard(gs);

      expect(gs.actionHistory.length, greaterThan(historyBefore));
    });

    test('drawCard with empty deck refills from discard', () {
      final gs = createDeterministicGameState(
        deck: [],
        discardPile: [
          createCard('hearts', '5'),
          createCard('diamonds', '6'),
          createCard('clubs', '7'),
        ],
      );

      GameLogic.drawCard(gs);

      // Le deck devrait avoir été rempli depuis la défausse
      // La dernière carte de la défausse reste
      expect(gs.discardPile.length, 1);
      expect(gs.drawnCard, isNotNull);
    });

    test('drawCard ends game when no cards available', () {
      final gs = createDeterministicGameState(
        deck: [],
        discardPile: [createCard('hearts', '5')], // Seulement 1 carte
      );

      GameLogic.drawCard(gs);

      expect(gs.phase, GamePhase.ended);
    });

    test('drawCard maintains invariants', () {
      final gs = createDeterministicGameState();
      final totalBefore = gs.totalCards;

      GameLogic.drawCard(gs);

      expect(gs.totalCards, totalBefore);
      GameStateInvariants.assertNoDuplicateCards(gs);
    });
  });

  group('GameLogic - Discard Drawn Card', () {
    test('discardDrawnCard moves card to discard pile', () {
      final gs = createDeterministicGameState();
      GameLogic.drawCard(gs);
      final drawnCard = gs.drawnCard!;
      final discardSizeBefore = gs.discardPile.length;

      GameLogic.discardDrawnCard(gs);

      expect(gs.drawnCard, isNull);
      expect(gs.discardPile.length, discardSizeBefore + 1);
      expect(gs.discardPile.last, drawnCard);
    });

    test('discardDrawnCard does nothing when no drawn card', () {
      final gs = createDeterministicGameState();
      final discardSizeBefore = gs.discardPile.length;

      GameLogic.discardDrawnCard(gs);

      expect(gs.discardPile.length, discardSizeBefore);
    });

    test('discardDrawnCard triggers special power for 7, 10, V, JOKER', () {
      final gs = createDeterministicGameState(
        deck: [createCard('hearts', '7')], // Carte spéciale
      );
      GameLogic.drawCard(gs);

      GameLogic.discardDrawnCard(gs);

      expect(gs.isWaitingForSpecialPower, true);
      expect(gs.specialCardToActivate?.value, '7');
    });

    test('discardDrawnCard maintains invariants', () {
      final gs = createDeterministicGameState();
      GameLogic.drawCard(gs);
      final totalBefore = gs.totalCards;

      GameLogic.discardDrawnCard(gs);

      expect(gs.totalCards, totalBefore);
      GameStateInvariants.assertNoDuplicateCards(gs);
    });
  });

  group('GameLogic - Replace Card', () {
    test('replaceCard swaps drawn card with hand card', () {
      final gs = createDeterministicGameState();
      GameLogic.drawCard(gs);
      final drawnCard = gs.drawnCard!;
      final oldHandCard = gs.humanPlayer.hand[0];

      GameLogic.replaceCard(gs, 0);

      expect(gs.drawnCard, isNull);
      expect(gs.humanPlayer.hand[0], drawnCard);
      expect(gs.discardPile.last, oldHandCard);
    });

    test('replaceCard marks new card as known', () {
      final gs = createDeterministicGameState();
      gs.humanPlayer.knownCards[0] = false;
      GameLogic.drawCard(gs);

      GameLogic.replaceCard(gs, 0);

      expect(gs.humanPlayer.knownCards[0], true);
    });

    test('replaceCard does nothing when no drawn card', () {
      final gs = createDeterministicGameState();
      final handBefore = List.from(gs.humanPlayer.hand);

      GameLogic.replaceCard(gs, 0);

      expect(gs.humanPlayer.hand, handBefore);
    });

    test('replaceCard does nothing with invalid index', () {
      final gs = createDeterministicGameState();
      GameLogic.drawCard(gs);
      final handBefore = List.from(gs.humanPlayer.hand);

      GameLogic.replaceCard(gs, -1);
      expect(gs.humanPlayer.hand, handBefore);

      GameLogic.replaceCard(gs, 100);
      expect(gs.drawnCard, isNotNull); // Carte toujours en main
    });

    test('replaceCard triggers special power for discarded card', () {
      final gs = createDeterministicGameState(
        humanHand: [
          createCard('hearts', 'V'), // Valet = pouvoir spécial
          createCard('diamonds', '2'),
          createCard('clubs', '3'),
          createCard('spades', '4'),
        ],
      );
      GameLogic.drawCard(gs);

      GameLogic.replaceCard(gs, 0);

      expect(gs.isWaitingForSpecialPower, true);
      expect(gs.specialCardToActivate?.value, 'V');
    });

    test('replaceCard maintains invariants', () {
      final gs = createDeterministicGameState();
      GameLogic.drawCard(gs);
      final totalBefore = gs.totalCards;

      GameLogic.replaceCard(gs, 0);

      expect(gs.totalCards, totalBefore);
      GameStateInvariants.assertNoDuplicateCards(gs);
    });
  });

  group('GameLogic - Match Card', () {
    test('matchCard succeeds when cards match', () {
      final gs = createDeterministicGameState(
        humanHand: [
          createCard('hearts', '9'), // Même valeur que la défausse
          createCard('diamonds', '2'),
          createCard('clubs', '3'),
          createCard('spades', '4'),
        ],
        discardPile: [createCard('clubs', '9')],
        phase: GamePhase.reaction,
      );
      final handSizeBefore = gs.humanPlayer.hand.length;

      final success = GameLogic.matchCard(gs, gs.humanPlayer, 0);

      expect(success, true);
      expect(gs.humanPlayer.hand.length, handSizeBefore - 1);
      expect(gs.discardPile.last.value, '9');
    });

    test('matchCard fails when cards do not match', () {
      final gs = createDeterministicGameState(
        humanHand: [
          createCard('hearts', 'A'), // Différent de la défausse
          createCard('diamonds', '2'),
          createCard('clubs', '3'),
          createCard('spades', '4'),
        ],
        discardPile: [createCard('clubs', '9')],
        phase: GamePhase.reaction,
      );
      final handSizeBefore = gs.humanPlayer.hand.length;

      final success = GameLogic.matchCard(gs, gs.humanPlayer, 0);

      expect(success, false);
      expect(gs.humanPlayer.hand.length, handSizeBefore + 1); // Pénalité
    });

    test('matchCard applies penalty on failure', () {
      final gs = createDeterministicGameState(
        humanHand: [
          createCard('hearts', 'A'),
          createCard('diamonds', '2'),
          createCard('clubs', '3'),
          createCard('spades', '4'),
        ],
        discardPile: [createCard('clubs', '9')],
        phase: GamePhase.reaction,
      );

      GameLogic.matchCard(gs, gs.humanPlayer, 0);

      // Pénalité = carte supplémentaire
      expect(gs.humanPlayer.hand.length, 5);
      expect(gs.humanPlayer.knownCards.length, 5);
      expect(
          gs.humanPlayer.knownCards.last, false); // Carte pénalité non connue
    });

    test('matchCard returns false when discard pile is empty', () {
      final gs = createDeterministicGameState(
        discardPile: [],
        phase: GamePhase.reaction,
      );

      final success = GameLogic.matchCard(gs, gs.humanPlayer, 0);

      expect(success, false);
    });

    test('matchCard works with Kings (all match each other)', () {
      final gs = createDeterministicGameState(
        humanHand: [
          createCard('hearts', 'R'), // Roi rouge
          createCard('diamonds', '2'),
          createCard('clubs', '3'),
          createCard('spades', '4'),
        ],
        discardPile: [createCard('spades', 'R')], // Roi noir
        phase: GamePhase.reaction,
      );

      final success = GameLogic.matchCard(gs, gs.humanPlayer, 0);

      expect(success, true);
    });

    test('matchCard works with Jokers (all match each other)', () {
      final gs = createDeterministicGameState(
        humanHand: [
          createCard('joker', 'JOKER'),
          createCard('diamonds', '2'),
          createCard('clubs', '3'),
          createCard('spades', '4'),
        ],
        discardPile: [createCard('joker', 'JOKER')],
        phase: GamePhase.reaction,
      );

      final success = GameLogic.matchCard(gs, gs.humanPlayer, 0);

      expect(success, true);
    });

    test('matchCard maintains invariants', () {
      final gs = createDeterministicGameState(
        discardPile: [createCard('clubs', '9')],
        phase: GamePhase.reaction,
      );
      final totalBefore = gs.totalCards;

      GameLogic.matchCard(gs, gs.humanPlayer, 0);

      expect(gs.totalCards, totalBefore);
      GameStateInvariants.assertNoDuplicateCards(gs);
    });
  });

  group('GameLogic - Call Dutch', () {
    test('callDutch sets dutchCallerId and phase', () {
      final gs = createDeterministicGameState(phase: GamePhase.playing);

      GameLogic.callDutch(gs);

      expect(gs.dutchCallerId, gs.currentPlayer.id);
      expect(gs.phase, GamePhase.dutchCalled);
    });

    test('callDutch adds to history', () {
      final gs = createDeterministicGameState(phase: GamePhase.playing);
      final historyBefore = gs.actionHistory.length;

      GameLogic.callDutch(gs);

      expect(gs.actionHistory.length, greaterThan(historyBefore));
    });

    test('callDutch does nothing if already called', () {
      final gs = createDeterministicGameState(phase: GamePhase.playing);
      gs.dutchCallerId = 'someone_else';

      GameLogic.callDutch(gs);

      expect(gs.dutchCallerId, 'someone_else'); // Pas changé
    });
  });

  group('GameLogic - End Game', () {
    test('endGame sets phase to ended', () {
      final gs = createDeterministicGameState(phase: GamePhase.playing);

      GameLogic.endGame(gs);

      expect(gs.phase, GamePhase.ended);
    });

    test('endGame reveals all cards', () {
      final gs = createDeterministicGameState(phase: GamePhase.playing);
      gs.humanPlayer.knownCards = [false, false, false, false];

      GameLogic.endGame(gs);

      expect(gs.humanPlayer.knownCards, everyElement(true));
    });

    test('endGame is idempotent', () {
      final gs = createDeterministicGameState(phase: GamePhase.playing);

      GameLogic.endGame(gs);
      final stateAfterFirst = gs.phase;

      GameLogic.endGame(gs);

      expect(gs.phase, stateAfterFirst);
    });
  });

  group('GameLogic - Special Powers', () {
    test('lookAtCard adds to history', () {
      final gs = createDeterministicGameState();
      final historyBefore = gs.actionHistory.length;
      final target = gs.players[1];

      GameLogic.lookAtCard(gs, target, 0);

      expect(gs.actionHistory.length, greaterThan(historyBefore));
    });

    test('swapCards exchanges cards between players', () {
      final gs = createDeterministicGameState();
      final p1 = gs.players[0];
      final p2 = gs.players[1];
      final card1Before = p1.hand[0];
      final card2Before = p2.hand[0];

      GameLogic.swapCards(gs, p1, 0, p2, 0);

      expect(p1.hand[0], card2Before);
      expect(p2.hand[0], card1Before);
    });

    test('swapCards resets known cards', () {
      final gs = createDeterministicGameState();
      final p1 = gs.players[0];
      final p2 = gs.players[1];
      p1.knownCards[0] = true;
      p2.knownCards[0] = true;

      GameLogic.swapCards(gs, p1, 0, p2, 0);

      expect(p1.knownCards[0], false);
      expect(p2.knownCards[0], false);
    });

    test('swapCards assigns contextual hint to bot receiver', () {
      final gs = createDeterministicGameState();
      final human = gs.players[0];
      final bot = gs.players[1];

      BotDutchStrategy.discardTracker.reset();
      BotDutchStrategy.discardTracker.trackDiscard(
        createCard('spades', 'R'),
        discardedBy: human.id,
        wasExchange: true,
      );
      BotDutchStrategy.discardTracker.trackDiscard(
        createCard('clubs', 'D'),
        discardedBy: human.id,
        wasExchange: true,
      );

      GameLogic.swapCards(gs, bot, 2, human, 0);

      expect(bot.getUnknownCardHintQuality(2), isNotNull);
      expect(bot.getUnknownCardHintConfidence(2), greaterThan(0));
    });

    test('replaceCard clears hint on replaced index', () {
      final gs = createDeterministicGameState();
      final bot = gs.players[1];
      gs.currentPlayerIndex = 1;
      bot.setUnknownCardHint(2,
          quality: -0.7, confidence: 0.9, actionCount: gs.actionCount);
      gs.drawnCard = createCard('hearts', '2');

      GameLogic.replaceCard(gs, 2);

      expect(bot.getUnknownCardHintQuality(2), isNull);
      expect(bot.getUnknownCardHintConfidence(2), isNull);
    });

    test('swapCards does nothing with invalid indices', () {
      final gs = createDeterministicGameState();
      final p1 = gs.players[0];
      final p2 = gs.players[1];
      final hand1Before = List.from(p1.hand);
      final hand2Before = List.from(p2.hand);

      GameLogic.swapCards(gs, p1, -1, p2, 0);

      expect(p1.hand, hand1Before);
      expect(p2.hand, hand2Before);
    });

    test('jokerEffect shuffles target hand', () {
      final gs = createDeterministicGameState();
      final target = gs.players[1];
      target.knownCards = [true, true, true, true];

      GameLogic.jokerEffect(gs, target);

      // Toutes les cartes deviennent inconnues
      expect(target.knownCards, everyElement(false));
      // La main a toujours le même nombre de cartes
      expect(target.hand.length, 4);
    });

    test('jokerEffect resets bot mental map', () {
      final gs = createDeterministicGameState();
      final bot = gs.players[1];
      bot.mentalMap = [bot.hand[0], bot.hand[1], null, null];

      GameLogic.jokerEffect(gs, bot);

      expect(bot.mentalMap, everyElement(isNull));
    });
  });

  group('GameLogic - Next Player', () {
    test('nextPlayer advances to next player', () {
      final gs = createDeterministicGameState();
      gs.currentPlayerIndex = 0;

      GameLogic.nextPlayer(gs);

      expect(gs.currentPlayerIndex, 1);
    });

    test('nextPlayer wraps around', () {
      final gs = createDeterministicGameState();
      gs.currentPlayerIndex = gs.players.length - 1;

      GameLogic.nextPlayer(gs);

      expect(gs.currentPlayerIndex, 0);
    });

    test('nextPlayer skips eliminated players', () {
      final gs = createDeterministicGameState();
      gs.eliminatedPlayerIds.add(gs.players[1].id);
      gs.currentPlayerIndex = 0;

      GameLogic.nextPlayer(gs);

      expect(gs.currentPlayerIndex, isNot(1)); // Skip player 1
    });
  });

  group('GameLogic - Initial Reveal', () {
    test('initialReveal marks selected cards as known', () {
      final gs = createDeterministicGameState();
      gs.humanPlayer.knownCards = [false, false, false, false];

      GameLogic.initialReveal(gs, [0, 1]);

      expect(gs.humanPlayer.knownCards[0], true);
      expect(gs.humanPlayer.knownCards[1], true);
      expect(gs.humanPlayer.knownCards[2], false);
      expect(gs.humanPlayer.knownCards[3], false);
    });

    test('initialReveal handles invalid indices gracefully', () {
      final gs = createDeterministicGameState();
      gs.humanPlayer.knownCards = [false, false, false, false];

      GameLogic.initialReveal(gs, [-1, 100, 0]);

      expect(gs.humanPlayer.knownCards[0], true);
      // Invalid indices ignored
    });
  });

  group('GameLogic - Apply Penalty', () {
    test('applyPenalty adds card to player hand', () {
      final gs = createDeterministicGameState();
      final handSizeBefore = gs.humanPlayer.hand.length;

      GameLogic.applyPenalty(gs, gs.humanPlayer);

      expect(gs.humanPlayer.hand.length, handSizeBefore + 1);
    });

    test('applyPenalty marks new card as unknown', () {
      final gs = createDeterministicGameState();

      GameLogic.applyPenalty(gs, gs.humanPlayer);

      expect(gs.humanPlayer.knownCards.last, false);
    });

    test('applyPenalty extends bot mental map', () {
      final gs = createDeterministicGameState();
      final bot = gs.players[1];
      final mentalMapBefore = bot.mentalMap.length;

      GameLogic.applyPenalty(gs, bot);

      expect(bot.mentalMap.length, mentalMapBefore + 1);
      expect(bot.mentalMap.last, isNull);
    });

    test('applyPenalty maintains invariants', () {
      final gs = createDeterministicGameState();
      final totalBefore = gs.totalCards;

      GameLogic.applyPenalty(gs, gs.humanPlayer);

      expect(gs.totalCards, totalBefore);
      GameStateInvariants.assertNoDuplicateCards(gs);
    });
  });
}
