import '../../../models/playing_card.dart';
import '../../../models/player.dart';
import '../../../models/game_state.dart';
import '../../../utils/action_history_messages.dart';
import '../../../services/game/game_logic.dart';
import '../../../services/game/bot/bot_dutch_strategy.dart';
import '../../../services/logging/game_logger_service.dart';
import '../../game_tracking_provider.dart';

/// Handler dédié à la gestion des pouvoirs spéciaux
/// Principe GRASP: Pure Fabrication - Responsabilité unique de gestion des pouvoirs
/// Principe SOLID: SRP - Ne gère que les pouvoirs spéciaux
class SpecialPowerHandler {
  final GameTrackingProvider _trackingProvider;

  SpecialPowerHandler({
    required GameTrackingProvider trackingProvider,
  }) : _trackingProvider = trackingProvider;

  /// Ignorer le pouvoir spécial
  void skipPower(GameState gameState) {
    final human = gameState.currentPlayer;
    final specialCard = gameState.specialCardToActivate;
    final powerValue = specialCard?.value;

    if (human.isHuman && specialCard != null) {
      final powerType = _getPowerType(specialCard);
      _trackingProvider.recordPlayerAction(
        actionType: 'power_skip',
        gameState: gameState,
        actionDetails: {
          'specialCard': specialCard.toJson(),
          'powerType': powerType,
        },
        powerType: powerType,
      );
    }

    gameState.phase = GamePhase.playing;
    gameState.isWaitingForSpecialPower = false;
    gameState.specialCardToActivate = null;
    if (powerValue != null) {
      BotDutchStrategy.discardTracker.recordPowerSkip(
        human.id,
        powerValue,
        turnCount: gameState.turnCount,
      );
    }
    gameState.addToHistory(ActionHistoryMessages.powerSkipped());
  }

  /// Utiliser un pouvoir spécial
  void usePower(
    GameState gameState,
    int targetPlayerIndex,
    int targetCardIndex,
  ) {
    PlayingCard? specialCard = gameState.specialCardToActivate;
    if (specialCard == null) return;

    Player currentPlayer = gameState.currentPlayer;
    Player targetPlayer = gameState.players[targetPlayerIndex];

    final beforeScore =
        currentPlayer.isHuman ? currentPlayer.getEstimatedScore() : null;

    if (currentPlayer.isHuman) {
      final powerType = _getPowerType(specialCard);
      final targetStrategy = _getTargetStrategy(gameState, targetPlayer);
      _trackingProvider.recordPlayerAction(
        actionType: 'power',
        gameState: gameState,
        actionDetails: {
          'specialCard': specialCard.toJson(),
          'targetPlayerIndex': targetPlayerIndex,
          'targetCardIndex': targetCardIndex,
          'powerType': powerType,
          'targetPlayerId': targetPlayer.id,
        },
        powerType: powerType,
        targetStrategy: targetStrategy,
      );
    }

    if (specialCard.value == '7' || specialCard.value == '8') {
      if (targetCardIndex < currentPlayer.hand.length) {
        currentPlayer.knownCards[targetCardIndex] = true;
        gameState.addToHistory(ActionHistoryMessages.powerLookOwn(
            currentPlayer.name, targetCardIndex));
      }
    } else if (specialCard.value == '9' || specialCard.value == '10') {
      if (targetCardIndex < targetPlayer.hand.length) {
        gameState.lastSpiedCard = targetPlayer.hand[targetCardIndex];
        gameState.addToHistory(ActionHistoryMessages.powerSpy(
            currentPlayer.name, targetPlayer.name, targetCardIndex));
      }
    } else if (specialCard.value == 'V') {
      gameState.pendingSwap = {
        'targetPlayer': targetPlayerIndex,
        'targetCard': targetCardIndex,
        'ownCard': null,
      };
      return; // Ne pas terminer le pouvoir, attendre la sélection de la carte à échanger
    }

    gameState.phase = GamePhase.playing;
    gameState.isWaitingForSpecialPower = false;
    gameState.specialCardToActivate = null;

    if (currentPlayer.isHuman && beforeScore != null) {
      final afterScore = currentPlayer.getEstimatedScore();
      _trackingProvider.updateLastActionResult(
        result: {
          'scoreChange': afterScore - beforeScore,
        },
      );
    }
  }

  /// Compléter l'échange (pouvoir Valet)
  void completeSwap(
    GameState gameState,
    int ownCardIndex,
  ) {
    if (gameState.pendingSwap == null) return;

    int targetPlayerIndex = gameState.pendingSwap!['targetPlayer'];
    int targetCardIndex = gameState.pendingSwap!['targetCard'];

    Player currentPlayer = gameState.currentPlayer;
    Player targetPlayer = gameState.players[targetPlayerIndex];

    final beforeScore =
        currentPlayer.isHuman ? currentPlayer.getEstimatedScore() : null;

    if (currentPlayer.isHuman) {
      _trackingProvider.recordPlayerAction(
        actionType: 'power',
        gameState: gameState,
        actionDetails: {
          'specialCard': {'value': 'V'},
          'targetPlayerIndex': targetPlayerIndex,
          'targetCardIndex': targetCardIndex,
          'ownCardIndex': ownCardIndex,
        },
      );
    }

    PlayingCard? myCard = currentPlayer.hand[ownCardIndex];
    PlayingCard? theirCard = targetPlayer.hand[targetCardIndex];

    BotDutchStrategy.discardTracker.recordPowerUse(
      currentPlayer.id,
      turnCount: gameState.turnCount,
    );
    BotDutchStrategy.discardTracker.observeVisibleReplacementIndex(
      currentPlayer.id,
      replacedIndex: ownCardIndex,
    );
    BotDutchStrategy.discardTracker.observeVisibleReplacementIndex(
      targetPlayer.id,
      replacedIndex: targetCardIndex,
    );

    currentPlayer.hand[ownCardIndex] = theirCard;
    targetPlayer.hand[targetCardIndex] = myCard;

    currentPlayer.knownCards[ownCardIndex] = false;
    targetPlayer.knownCards[targetCardIndex] = false;

    // FIX: Invalider la mentalMap des bots après un swap
    if (!currentPlayer.isHuman &&
        ownCardIndex < currentPlayer.mentalMap.length) {
      currentPlayer.mentalMap[ownCardIndex] = null;
    }
    if (!targetPlayer.isHuman &&
        targetCardIndex < targetPlayer.mentalMap.length) {
      targetPlayer.mentalMap[targetCardIndex] = null;
    }

    // LOG : Échange Valet par l'humain
    GameLoggerService.instance.logValetExchange(
      bot: currentPlayer,
      player1: currentPlayer,
      player2: targetPlayer,
      index1: ownCardIndex,
      index2: targetCardIndex,
      card1: myCard,
      card2: theirCard,
    );

    gameState.addToHistory(
        ActionHistoryMessages.powerSwap(currentPlayer.name, targetPlayer.name));

    gameState.pendingSwap = null;
    gameState.phase = GamePhase.playing;
    gameState.isWaitingForSpecialPower = false;
    gameState.specialCardToActivate = null;

    if (currentPlayer.isHuman && beforeScore != null) {
      final afterScore = currentPlayer.getEstimatedScore();
      _trackingProvider.updateLastActionResult(
        result: {
          'scoreChange': afterScore - beforeScore,
        },
      );
    }
  }

  /// Regarder une carte (pouvoir 7/8)
  void executeLookAtCard(
    GameState gameState,
    Player target,
    int cardIndex,
  ) {
    final human = gameState.currentPlayer;
    final specialCard = gameState.specialCardToActivate;
    final beforeScore = human.isHuman ? human.getEstimatedScore() : null;

    if (human.isHuman && specialCard != null) {
      _trackingProvider.recordPlayerAction(
        actionType: 'power',
        gameState: gameState,
        actionDetails: {
          'specialCard': specialCard.toJson(),
          'targetPlayerId': target.id,
          'targetCardIndex': cardIndex,
        },
      );
    }

    if (cardIndex >= 0 && cardIndex < target.hand.length) {
      if (target.isHuman) {
        target.knownCards[cardIndex] = true;
      }
      gameState.lastSpiedCard = target.hand[cardIndex];
      GameLogic.lookAtCard(gameState, target, cardIndex);
    }

    gameState.phase = GamePhase.playing;
    gameState.isWaitingForSpecialPower = false;
    gameState.specialCardToActivate = null;

    if (human.isHuman && beforeScore != null) {
      final afterScore = human.getEstimatedScore();
      _trackingProvider.updateLastActionResult(
        result: {
          'scoreChange': afterScore - beforeScore,
        },
      );
    }
  }

  /// Exécuter l'effet Joker
  void executeJokerEffect(
    GameState gameState,
    Player target,
  ) {
    final human = gameState.currentPlayer;
    final specialCard = gameState.specialCardToActivate;
    final beforeScore = human.isHuman ? human.getEstimatedScore() : null;

    if (human.isHuman && specialCard != null) {
      _trackingProvider.recordPlayerAction(
        actionType: 'power',
        gameState: gameState,
        actionDetails: {
          'specialCard': specialCard.toJson(),
          'targetPlayerId': target.id,
        },
      );
    }

    GameLogic.jokerEffect(gameState, target);

    if (target.isHuman) {
      for (int i = 0; i < target.knownCards.length; i++) {
        target.knownCards[i] = false;
      }
    }

    gameState.phase = GamePhase.playing;
    gameState.isWaitingForSpecialPower = false;
    gameState.specialCardToActivate = null;

    if (human.isHuman && beforeScore != null) {
      final afterScore = human.getEstimatedScore();
      _trackingProvider.updateLastActionResult(
        result: {
          'scoreChange': afterScore - beforeScore,
        },
      );
    }
  }

  /// Obtenir le type de pouvoir
  String _getPowerType(PlayingCard card) {
    if (card.value == '7' || card.value == '8') return card.value;
    if (card.value == '9' || card.value == '10') return card.value;
    if (card.value == 'V') return 'jack';
    if (card.value == 'JOKER') return 'joker';
    return 'unknown';
  }

  /// Obtenir la stratégie de ciblage
  String _getTargetStrategy(GameState gameState, Player target) {
    final players = List<Player>.from(gameState.players);
    players
        .sort((a, b) => a.getEstimatedScore().compareTo(b.getEstimatedScore()));
    final targetRank = players.indexOf(target) + 1;
    if (targetRank == 1) return 'leader';
    if (targetRank == players.length) return 'weak';
    return 'balanced';
  }
}
