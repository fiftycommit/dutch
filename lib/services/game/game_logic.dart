import 'dart:math';
import '../../models/playing_card.dart';
import '../../models/player.dart';
import '../../models/game_state.dart';
import '../../models/game_sub_states.dart';
import '../../models/game_settings.dart';
import '../../utils/action_history_messages.dart';
import '../logging/game_logger_service.dart';
import 'bot/bot_dutch_strategy.dart';
import 'bot/discard_tracker.dart';

class GameLogic {
  static final Random _random = Random();

  static GameState initializeGame({
    required List<Player> players,
    required GameMode gameMode,
    required Difficulty difficulty,
    int tournamentRound = 1,
    DealMode dealMode = DealMode.roundRobin,
  }) {
    // Reset le tracker de défausses pour la nouvelle manche
    BotDutchStrategy.discardTracker.reset();

    List<PlayingCard> deck = GameState.createFullDeck();

    for (var p in players) {
      p.hand = [];
      p.knownCards = [];
      p.mentalMap = [];
      p.memorizedCardIndices = [];
      p.resetUnknownCardHints();
      p.clearJokerInference();
    }

    GameState gameState = GameState(
      players: players,
      deck: deck,
      discardPile: [],
      gameMode: gameMode,
      difficulty: difficulty,
      tournamentRound: tournamentRound,
      phase: GamePhase.setup,
    );

    gameState.dealCards(mode: dealMode);

    // Snapshot de départ pour les modèles de décision (ex: style "moi").
    for (final player in players) {
      BotDutchStrategy.discardTracker.recordRoundStartScore(
        player.id,
        player.calculateScore(),
      );
    }

    // Appliquer la méthode de mélange choisie (chance) sur le deck restant
    gameState.smartShuffle();

    for (var player in players) {
      if (!player.isHuman) {
        player.initializeBotMemory();
      }
    }

    if (gameState.deck.isNotEmpty) {
      PlayingCard firstCard = gameState.deck.removeLast();
      gameState.discardPile.add(firstCard);
    }

    if (players.isNotEmpty) {
      int randomIndex = _random.nextInt(players.length);
      gameState.currentPlayerIndex = randomIndex;
      String starterName = players[randomIndex].isHuman
          ? "Vous avez commencé"
          : "${players[randomIndex].name} a commencé";
      gameState.addToHistory("Tirage au sort : $starterName !");
    }

    BotDutchStrategy.discardTracker.recordTableSnapshot(gameState);

    return gameState;
  }

  static void initialReveal(GameState gameState, List<int> selectedIndices) {
    Player human = gameState.players.firstWhere((p) => p.isHuman);
    human.memorizedCardIndices = selectedIndices.toList()..sort();
    for (int index in selectedIndices) {
      if (index >= 0 && index < human.knownCards.length) {
        human.knownCards[index] = true;
      }
    }
    BotDutchStrategy.discardTracker.observePublicMemorizedIndices(
      human.id,
      human.memorizedCardIndices,
      human.hand.length,
    );
    gameState.addToHistory("Vous avez mémorisé vos cartes.");
  }

  static void drawCard(GameState gameState) {
    if (gameState.deck.isEmpty) _refillDeck(gameState);

    // Si _refillDeck a déjà terminé la partie, ne pas continuer
    if (gameState.phase == GamePhase.ended ||
        gameState.phase == GamePhase.dutchCalled) {
      return;
    }

    if (gameState.deck.isNotEmpty) {
      gameState.drawnCard = gameState.deck.removeLast();
      gameState.addToHistory(
          ActionHistoryMessages.draw(gameState.currentPlayer.name));

      // Log
      GameLoggerService.instance.logDraw(
        player: gameState.currentPlayer,
        card: gameState.drawnCard!,
        fromDiscard: false,
      );
    } else {
      endGame(gameState);
    }
  }

  static void discardDrawnCard(GameState gameState) {
    if (gameState.drawnCard == null) return;

    PlayingCard card = gameState.drawnCard!;
    gameState.discardPile.add(card);
    gameState.drawnCard = null;
    // Message explicite : le joueur n'a PAS gardé la carte piochée
    final currentName = gameState.currentPlayer.name;
    final isHuman = currentName == "Vous";
    // Vérifier si la carte a un pouvoir spécial (7, 10, V, JOKER)
    final powerValues = {'7', '10', 'V', 'JOKER'};
    final hasPower = powerValues.contains(card.value);

    gameState.addToHistory(ActionHistoryMessages.discardDrawn(currentName, card,
        isLocal: isHuman, hasPower: hasPower));

    // Tracker la défausse (wasExchange = false : pas d'échange)
    BotDutchStrategy.discardTracker.trackDiscard(
      card,
      discardedBy: gameState.currentPlayer.id,
      wasExchange: false,
      actionType: DiscardActionType.drawnDiscard,
    );

    // Log
    GameLoggerService.instance.logDiscard(
      player: gameState.currentPlayer,
      card: card,
    );

    _checkSpecialPower(gameState, card);
  }

  static void replaceCard(GameState gameState, int cardIndex) {
    if (gameState.drawnCard == null) return;

    Player player = gameState.currentPlayer;

    if (cardIndex < 0 || cardIndex >= player.hand.length) {
      return;
    }

    PlayingCard newCard = gameState.drawnCard!;
    PlayingCard oldCard = player.hand[cardIndex];

    player.hand[cardIndex] = newCard;
    player.knownCards[cardIndex] = true;
    gameState.drawnCard = null;

    // FIX CRITIQUE : Mettre à jour la mentalMap du bot avec la nouvelle carte
    // Sinon le bot raisonne sur l'ancienne carte → décisions incohérentes
    if (!player.isHuman) {
      // La carte remplacée est défaussée publiquement:
      // utile pour la reconstruction post-Joker.
      player.onOwnReplacementAfterJoker(
        replacedIndex: cardIndex,
        discardedCard: oldCard,
      );
      player.updateMentalMap(cardIndex, newCard);
    }
    player.clearUnknownCardHint(cardIndex);

    // FIX CRITIQUE : Invalider la SpyMemory des autres bots sur cette position
    // Quand un joueur échange, la carte à cette position change !
    for (final otherPlayer in gameState.players) {
      if (otherPlayer.id != player.id && !otherPlayer.isHuman) {
        final spyData = otherPlayer.spyMemory[player.id];
        if (spyData != null && spyData.containsKey(cardIndex)) {
          spyData.remove(cardIndex);
        }
      }
    }

    gameState.discardPile.add(oldCard);
    // Message explicite : le joueur a GARDÉ la carte piochée
    gameState.addToHistory(ActionHistoryMessages.replaceCard(
        player.name, oldCard,
        isLocal: player.isHuman));

    // Tracker la défausse (wasExchange = true : il a gardé la pioche)
    BotDutchStrategy.discardTracker.trackDiscard(
      oldCard,
      discardedBy: player.id,
      wasExchange: true,
      actionType: DiscardActionType.exchangeDiscard,
      replacedIndex: cardIndex,
    );

    // Log
    GameLoggerService.instance.logExchange(
      player: player,
      oldCard: oldCard,
      newCard: newCard,
      handIndex: cardIndex,
    );

    _checkSpecialPower(gameState, oldCard);
  }

  static bool matchCard(GameState gameState, Player player, int cardIndex) {
    if (gameState.discardPile.isEmpty) return false;

    if (cardIndex < 0 || cardIndex >= player.hand.length) {
      return false;
    }

    PlayingCard playerCard = player.hand[cardIndex];
    PlayingCard topDiscard = gameState.discardPile.last;

    if (playerCard.matches(topDiscard)) {
      gameState.discardPile.add(playerCard);

      // Tracker le match pour le comptage de cartes
      BotDutchStrategy.discardTracker.trackDiscard(
        playerCard,
        discardedBy: player.id,
        actionType: DiscardActionType.matchDiscard,
        turnCount: gameState.turnCount,
      );

      List<PlayingCard> newHand = List.from(player.hand);
      List<bool> newKnownCards = List.from(player.knownCards);

      newHand.removeAt(cardIndex);
      newKnownCards.removeAt(cardIndex);

      player.hand = newHand;
      player.knownCards = newKnownCards;

      if (!player.isHuman && cardIndex < player.mentalMap.length) {
        player.mentalMap.removeAt(cardIndex);
      }
      if (!player.isHuman) {
        player.clearJokerInference();
      }
      if (cardIndex < player.unknownCardQualityHints.length) {
        player.unknownCardQualityHints.removeAt(cardIndex);
      }
      if (cardIndex < player.unknownCardHintConfidence.length) {
        player.unknownCardHintConfidence.removeAt(cardIndex);
      }
      if (cardIndex < player.unknownCardHintActionCount.length) {
        player.unknownCardHintActionCount.removeAt(cardIndex);
      }

      _maybeBronzeForgetAfterReactionMatch(gameState, player, playerCard);

      // Le joueur a retiré une carte: les indices espionnés après cette
      // position sont décalés. On réindexe au lieu d'effacer toute l'info.
      for (final bot in gameState.players) {
        if (!bot.isHuman) {
          bot.reindexSpiedCardsAfterRemoval(
            player.id,
            removedIndex: cardIndex,
            newHandSize: player.hand.length,
          );
        }
      }

      gameState.addToHistory(ActionHistoryMessages.matchSuccess(
          player.name, playerCard,
          isLocal: player.name == "Vous"));

      // Log
      GameLoggerService.instance.logMatch(
        player: player,
        matchedCards: [playerCard],
        handIndices: [cardIndex],
        discardCard: topDiscard,
      );

      if (gameState.phase == GamePhase.reaction) {
        // Pendant la réaction, stocker le pouvoir pour résolution après
        _addPendingMatchPower(gameState, player, playerCard);
      } else {
        _checkSpecialPower(gameState, playerCard);
      }
      return true;
    } else {
      gameState.addToHistory(ActionHistoryMessages.matchFailed(
          player.name, playerCard, topDiscard));

      // Log
      GameLoggerService.instance.logCustomAction(
        player: player,
        action: 'MATCH RATÉ',
        details:
            '${playerCard.displayName} ≠ ${topDiscard.displayName} → pénalité',
      );

      applyPenalty(gameState, player);
      return false;
    }
  }

  static void applyPenalty(GameState gameState, Player player) {
    if (gameState.deck.isEmpty) _refillDeck(gameState);
    if (gameState.deck.isEmpty) return;

    PlayingCard penaltyCard = gameState.deck.removeLast();

    List<PlayingCard> newHand = List.from(player.hand);
    List<bool> newKnownCards = List.from(player.knownCards);

    newHand.add(penaltyCard);
    newKnownCards.add(false);

    player.hand = newHand;
    player.knownCards = newKnownCards;

    if (!player.isHuman) {
      player.mentalMap.add(null);
      player.clearJokerInference();
    }
    player.clearUnknownCardHint(newHand.length - 1);

    gameState.addToHistory(ActionHistoryMessages.penalty(player.name));
  }

  static void lookAtCard(GameState gameState, Player target, int cardIndex) {
    if (cardIndex >= 0 && cardIndex < target.knownCards.length) {
      BotDutchStrategy.discardTracker.recordPowerUse(
        gameState.currentPlayer.id,
        turnCount: gameState.turnCount,
      );
      gameState.addToHistory(
          "${gameState.currentPlayer.name} a regardé une carte de ${target.name}.");
    }
  }

  static void swapCards(
      GameState gameState, Player p1, int idx1, Player p2, int idx2) {
    if (idx1 < 0 ||
        idx1 >= p1.hand.length ||
        idx2 < 0 ||
        idx2 >= p2.hand.length) {
      return;
    }

    BotDutchStrategy.discardTracker.recordPowerUse(
      gameState.currentPlayer.id,
      turnCount: gameState.turnCount,
    );
    BotDutchStrategy.discardTracker.observeVisibleReplacementIndex(
      p1.id,
      replacedIndex: idx1,
    );
    BotDutchStrategy.discardTracker.observeVisibleReplacementIndex(
      p2.id,
      replacedIndex: idx2,
    );

    final c1 = p1.hand[idx1];
    final c2 = p2.hand[idx2];
    final p1KnownBeforeSwap = _knownOwnCardBeforeSwap(p1, idx1);
    final p2KnownBeforeSwap = _knownOwnCardBeforeSwap(p2, idx2);
    final p1HintQuality = p1.getUnknownCardHintQuality(idx1);
    final p1HintConfidence = p1.getUnknownCardHintConfidence(idx1);
    final p1HintAction = p1.getUnknownCardHintAction(idx1);
    final p2HintQuality = p2.getUnknownCardHintQuality(idx2);
    final p2HintConfidence = p2.getUnknownCardHintConfidence(idx2);
    final p2HintAction = p2.getUnknownCardHintAction(idx2);

    p1.hand[idx1] = c2;
    p2.hand[idx2] = c1;

    if (idx1 < p1.knownCards.length) p1.knownCards[idx1] = false;
    if (idx2 < p2.knownCards.length) p2.knownCards[idx2] = false;

    if (!p1.isHuman && idx1 < p1.mentalMap.length) {
      p1.mentalMap[idx1] = null;
    }
    if (!p2.isHuman && idx2 < p2.mentalMap.length) {
      p2.mentalMap[idx2] = null;
    }
    if (!p1.isHuman) {
      p1.clearJokerInference();
    }
    if (!p2.isHuman) {
      p2.clearJokerInference();
    }

    final p1IgnoresSwap = _shouldBronzeIgnoreSwap(p1);
    final p2IgnoresSwap = _shouldBronzeIgnoreSwap(p2);
    if (p1IgnoresSwap) {
      if (idx1 < p1.knownCards.length) {
        p1.knownCards[idx1] = true;
      }
      if (!p1.isHuman && idx1 < p1.mentalMap.length) {
        // Bronze "en déni": garde l'ancienne info en mémoire.
        p1.mentalMap[idx1] = c1;
      }
      p1.clearUnknownCardHint(idx1);
    }
    if (p2IgnoresSwap) {
      if (idx2 < p2.knownCards.length) {
        p2.knownCards[idx2] = true;
      }
      if (!p2.isHuman && idx2 < p2.mentalMap.length) {
        p2.mentalMap[idx2] = c2;
      }
      p2.clearUnknownCardHint(idx2);
    }

    _applySwapUnknownHint(
      gameState,
      receiver: p1,
      receiverIndex: idx1,
      source: p2,
      sourceHintQuality: p2HintQuality,
      sourceHintConfidence: p2HintConfidence,
      sourceHintActionCount: p2HintAction,
    );
    _applySwapUnknownHint(
      gameState,
      receiver: p2,
      receiverIndex: idx2,
      source: p1,
      sourceHintQuality: p1HintQuality,
      sourceHintConfidence: p1HintConfidence,
      sourceHintActionCount: p1HintAction,
    );

    // Le swap est visible (indices), et une connaissance exacte peut se
    // propager si elle existait déjà avant l'échange.
    for (final observer in gameState.players) {
      if (observer.isHuman) continue;

      final knownP1FromSpy = observer.getSpiedCards(p1.id)?[idx1];
      final knownP2FromSpy = observer.getSpiedCards(p2.id)?[idx2];

      final knownP1 = observer.id == p1.id
          ? (p1KnownBeforeSwap ?? knownP1FromSpy)
          : knownP1FromSpy;
      final knownP2 = observer.id == p2.id
          ? (p2KnownBeforeSwap ?? knownP2FromSpy)
          : knownP2FromSpy;

      observer.invalidateSpiedCard(p1.id, idx1);
      observer.invalidateSpiedCard(p2.id, idx2);

      if (knownP1 != null) {
        observer.rememberSpiedCard(p2.id, idx2, knownP1);
      }
      if (knownP2 != null) {
        observer.rememberSpiedCard(p1.id, idx1, knownP2);
      }

      if (observer.id == p1.id && !p1IgnoresSwap && knownP2 != null) {
        p1.updateMentalMap(idx1, knownP2);
      }
      if (observer.id == p2.id && !p2IgnoresSwap && knownP1 != null) {
        p2.updateMentalMap(idx2, knownP1);
      }
    }

    gameState.addToHistory(
        ActionHistoryMessages.powerSwapDetailed(p1.name, idx1, p2.name, idx2));

    // Log
    GameLoggerService.instance.logValetExchange(
      bot: gameState.currentPlayer,
      player1: p1,
      player2: p2,
      index1: idx1,
      index2: idx2,
      card1: c1,
      card2: c2,
    );
  }

  static PlayingCard? _knownOwnCardBeforeSwap(Player player, int index) {
    if (player.isHuman) return null;
    if (index < 0 || index >= player.hand.length) return null;
    if (index >= player.knownCards.length || !player.knownCards[index]) {
      return null;
    }
    if (index >= player.mentalMap.length) return null;
    return player.mentalMap[index];
  }

  static void _applySwapUnknownHint(
    GameState gameState, {
    required Player receiver,
    required int receiverIndex,
    required Player source,
    double? sourceHintQuality,
    double? sourceHintConfidence,
    int? sourceHintActionCount,
  }) {
    receiver.clearUnknownCardHint(receiverIndex);
    if (receiver.isHuman) return;

    // Or/Platine: modèle binaire strict (sait / sait pas).
    // On conserve uniquement un marqueur structurel "incertitude issue d'un swap"
    // via actionCount, sans qualité/confiance probabiliste.
    if (_usesBinaryUnknownModel(receiver)) {
      receiver.setUnknownCardHint(
        receiverIndex,
        quality: 0.0,
        confidence: 0.0,
        actionCount: gameState.actionCount,
      );
      return;
    }

    final estimate = BotDutchStrategy.discardTracker
        .estimateOpponentHand(source.id, source.hand.length);
    final sourceCardAverage = source.hand.isEmpty
        ? 6.5
        : estimate.estimatedScore / source.hand.length;

    // Qualité du joueur source d'après son historique public:
    // plus il semble fort, plus la carte reçue a de chances d'être bonne.
    double inferredQuality = (7.0 - sourceCardAverage) / 6.0;
    if (source.hand.length <= 2) {
      inferredQuality += 0.22;
    } else if (source.hand.length >= 5) {
      inferredQuality -= 0.12;
    }
    if (BotDutchStrategy.discardTracker.lastActionWasExchange(source.id)) {
      inferredQuality += 0.06;
    }

    double confidence = 0.20 + (estimate.confidence * 0.60);
    if (source.hand.length <= 2) {
      confidence += 0.18;
    } else if (source.hand.length >= 5) {
      confidence -= 0.05;
    }
    if (BotDutchStrategy.discardTracker.lastActionWasExchange(source.id)) {
      confidence *= 0.78;
    }

    // Contamination: si la carte source était déjà issue d'un échange
    // récent/non vérifié, on réduit fortement la confiance.
    if (sourceHintQuality != null && sourceHintConfidence != null) {
      final inheritedWeight =
          _clampDouble(sourceHintConfidence * 0.45, 0.0, 0.45);
      inferredQuality = (inferredQuality * (1 - inheritedWeight)) +
          (sourceHintQuality * inheritedWeight);

      confidence *= 0.58;
      if (sourceHintActionCount != null &&
          (gameState.actionCount - sourceHintActionCount) <= 2) {
        confidence *= 0.72;
      }
    }

    receiver.setUnknownCardHint(
      receiverIndex,
      quality: _clampDouble(inferredQuality, -1.0, 1.0),
      confidence: _clampDouble(confidence, 0.05, 0.95),
      actionCount: gameState.actionCount,
    );
  }

  static double _clampDouble(double value, double lower, double upper) {
    if (value < lower) return lower;
    if (value > upper) return upper;
    return value;
  }

  static bool _usesBinaryUnknownModel(Player player) {
    if (player.isHuman) return false;
    final skill = player.botSkillLevel;
    return skill == BotSkillLevel.gold || skill == BotSkillLevel.platinum;
  }

  static bool _usesAdvancedJokerModel(Player player) {
    if (player.isHuman) return false;
    final skill = player.botSkillLevel;
    return skill == BotSkillLevel.gold || skill == BotSkillLevel.platinum;
  }

  static bool _shouldBronzeIgnoreSwap(Player player) {
    if (player.isHuman) return false;
    if (player.botSkillLevel != BotSkillLevel.bronze) return false;
    return _random.nextDouble() < 0.62;
  }

  static void _maybeBronzeForgetAfterReactionMatch(
    GameState gameState,
    Player player,
    PlayingCard discardedCard,
  ) {
    if (gameState.phase != GamePhase.reaction) return;
    if (player.isHuman) return;
    if (player.botSkillLevel != BotSkillLevel.bronze) return;
    if (player.hand.isEmpty) return;
    if (_random.nextDouble() >= 0.45) return;

    final idx = _random.nextInt(player.hand.length);
    while (player.mentalMap.length < player.hand.length) {
      player.mentalMap.add(null);
    }
    while (player.knownCards.length < player.hand.length) {
      player.knownCards.add(false);
    }

    // Mémoire erronée: il croit encore avoir une carte du rang défaussé.
    player.mentalMap[idx] =
        PlayingCard.create(player.hand[idx].suit, discardedCard.value);
    player.knownCards[idx] = true;
    player.clearUnknownCardHint(idx);
    gameState.addToHistory(
        "😵 ${player.name} a oublié sa défausse de réaction et s'est trompé de carte.");
  }

  static void jokerEffect(GameState gameState, Player targetPlayer) {
    BotDutchStrategy.discardTracker.recordPowerUse(
      gameState.currentPlayer.id,
      turnCount: gameState.turnCount,
    );

    List<PlayingCard>? knownBeforeJoker;
    if (_usesAdvancedJokerModel(targetPlayer)) {
      final knowsAll =
          targetPlayer.mentalMap.length >= targetPlayer.hand.length &&
              targetPlayer.hand.isNotEmpty &&
              targetPlayer.mentalMap
                  .take(targetPlayer.hand.length)
                  .every((card) => card != null);
      if (knowsAll) {
        knownBeforeJoker = targetPlayer.mentalMap
            .take(targetPlayer.hand.length)
            .whereType<PlayingCard>()
            .map((card) => PlayingCard.create(card.suit, card.value))
            .toList(growable: false);
      }
    }

    List<PlayingCard> shuffledHand = List.from(targetPlayer.hand);
    shuffledHand.shuffle(Random());
    targetPlayer.hand = shuffledHand;

    targetPlayer.knownCards = List.filled(targetPlayer.hand.length, false);
    targetPlayer.resetUnknownCardHints();
    targetPlayer.clearJokerInference();

    // Invalider toute la mémoire espionnage concernant ce joueur
    // Car ses cartes ont été mélangées
    for (final player in gameState.players) {
      if (!player.isHuman) {
        player.forgetSpiedCards(targetPlayer.id);
      }
    }

    if (!targetPlayer.isHuman) {
      targetPlayer.mentalMap = List<PlayingCard?>.filled(
          targetPlayer.hand.length, null,
          growable: true);
      if (knownBeforeJoker != null && knownBeforeJoker.isNotEmpty) {
        targetPlayer.setupJokerInferenceFromKnownHand(
          knownHandBeforeJoker: knownBeforeJoker,
          actionCount: gameState.actionCount,
        );
      }
    }

    gameState.addToHistory(ActionHistoryMessages.powerJoker(
        gameState.currentPlayer.name, targetPlayer.name));

    // Log
    GameLoggerService.instance.logPowerUse(
      player: gameState.currentPlayer,
      powerValue: 0,
      powerName: 'JOKER',
      description: 'Mélange les cartes de ${targetPlayer.name}',
    );
  }

  static void _checkSpecialPower(GameState gameState, PlayingCard card) {
    List<String> powerCards = ['7', '10', 'V', 'JOKER'];
    if (powerCards.contains(card.value)) {
      gameState.phase = GamePhase.specialPower;
      gameState.isWaitingForSpecialPower = true;
      gameState.specialCardToActivate = card;
      gameState.specialPowerPlayerId = null; // currentPlayer par défaut
      gameState.specialPowerStartTime = DateTime.now().millisecondsSinceEpoch;
      gameState.turnStartTime = DateTime.now().millisecondsSinceEpoch;
      gameState.turnTimeoutMs = 60000; // 1 minute pour utiliser le pouvoir
    }
  }

  /// Ajoute un pouvoir en attente suite à un match pendant la phase de réaction
  static void _addPendingMatchPower(
      GameState gameState, Player player, PlayingCard card) {
    const powerCards = ['7', '10', 'V', 'JOKER'];
    if (powerCards.contains(card.value)) {
      gameState.pendingMatchPowers.add(PendingMatchPower(
        playerId: player.id,
        playerName: player.name,
        card: card,
      ));
    }
  }

  static void callDutch(GameState gameState, {String reason = 'Manuel'}) {
    if (gameState.dutchCallerId != null) return;
    gameState.dutchCallerId = gameState.currentPlayer.id;
    gameState.phase = GamePhase.dutchCalled;
    gameState.addToHistory(
        ActionHistoryMessages.dutch(gameState.currentPlayer.name));

    // Log
    GameLoggerService.instance.logDutch(
      player: gameState.currentPlayer,
      estimatedScore: gameState.currentPlayer.getEstimatedScore(),
      reason: reason,
    );
  }

  static void endGame(GameState gameState) {
    gameState.phase = GamePhase.ended;
    for (var p in gameState.players) {
      for (int i = 0; i < p.knownCards.length; i++) {
        p.knownCards[i] = true;
      }
    }
  }

  static void nextPlayer(GameState gameState) {
    gameState.nextTurn();
    BotDutchStrategy.discardTracker.recordTableSnapshot(gameState);
  }

  static void _refillDeck(GameState gameState) {
    if (gameState.discardPile.length > 1) {
      PlayingCard top = gameState.discardPile.removeLast();
      gameState.deck.addAll(gameState.discardPile);
      gameState.discardPile.clear();
      gameState.discardPile.add(top);
      // Utiliser smartShuffle avec le mode de mélange des paramètres
      gameState.smartShuffle();
      gameState.addToHistory(
          ActionHistoryMessages.deckRefilled(gameState.deck.length));
    } else {
      if (gameState.dutchCallerId != null) {
        gameState.phase = GamePhase.dutchCalled;
        gameState.addToHistory(ActionHistoryMessages.noCardsLeft());
      } else {
        endGame(gameState);
      }
    }
  }
}
