import 'dart:math';
import '../models/card.dart';
import '../models/player.dart';
import '../models/game_state.dart';
import '../models/game_settings.dart';
import 'package:flutter/foundation.dart';

class GameLogic {
  static final Random _random = Random();

  static GameState initializeGame({
    required List<Player> players,
    required GameMode gameMode,
    required Difficulty difficulty,
    int tournamentRound = 1,
  }) {
    List<PlayingCard> deck = GameState.createFullDeck();

    for (var p in players) {
      p.hand = [];
      p.knownCards = [];
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

    gameState.smartShuffle();
    gameState.dealCards();

    if (gameState.deck.isNotEmpty) {
      PlayingCard firstCard = gameState.deck.removeLast();
      gameState.discardPile.add(firstCard);
    }

    if (players.isNotEmpty) {
      int randomIndex = _random.nextInt(players.length);
      gameState.currentPlayerIndex = randomIndex;
      String starterName = players[randomIndex].isHuman
          ? "Vous commencez"
          : "${players[randomIndex].name} commence";
      gameState.addToHistory("ðŸŽ² Tirage au sort : $starterName !");
    }

    // ðŸ” VAR TACTIQUE : Distribution initiale
    Player human = gameState.players.firstWhere((p) => p.isHuman);
    debugPrint("\nðŸ” [VAR - INIT] --------------------------------------");
    debugPrint(
        "ðŸ Main de DÃ‰PART du joueur : ${human.hand.map((c) => c.value).toList()}");
    debugPrint("ðŸ†” IDs des cartes : ${human.hand.map((c) => c.id).toList()}");
    debugPrint("-------------------------------------------------------\n");

    return gameState;
  }

  static void initialReveal(GameState gameState, List<int> selectedIndices) {
    try {
      Player human = gameState.players.firstWhere((p) => p.isHuman);
      for (int index in selectedIndices) {
        if (index >= 0 && index < human.knownCards.length) {
          human.knownCards[index] = true;
        }
      }
      gameState.addToHistory("Vous avez mÃ©morisÃ© vos cartes.");
    } catch (e) {
      debugPrint("Erreur initialReveal: $e");
    }
  }

  static void drawCard(GameState gameState) {
    if (gameState.deck.isEmpty) _refillDeck(gameState);

    if (gameState.deck.isNotEmpty) {
      gameState.drawnCard = gameState.deck.removeLast();
      gameState.addToHistory("${gameState.currentPlayer.name} pioche.");

      // ðŸ” VAR TACTIQUE : Pioche
      if (gameState.currentPlayer.isHuman) {
        debugPrint(
            "\nðŸ” [VAR - DRAW] Vous avez piochÃ© : ${gameState.drawnCard!.value} (Suite: ${gameState.drawnCard!.suit})");
      }
    } else {
      endGame(gameState);
    }
  }

  static void discardDrawnCard(GameState gameState) {
    if (gameState.drawnCard == null) return;

    // ðŸ” VAR TACTIQUE - REJET
    debugPrint(
        "\nðŸ” [VAR - DISCARD] Joueur rejette la carte : ${gameState.drawnCard!.value}");
    debugPrint(
        "âœ‹ Main INCHANGÃ‰E : ${gameState.currentPlayer.hand.map((c) => c.value).toList()}");

    PlayingCard card = gameState.drawnCard!;
    gameState.discardPile.add(card);
    gameState.drawnCard = null;
    gameState.addToHistory(
        "${gameState.currentPlayer.name} rejette la carte piochÃ©e.");

    _checkSpecialPower(gameState, card);
  }

  static void replaceCard(GameState gameState, int cardIndex) {
    if (gameState.drawnCard == null) return;

    Player player = gameState.currentPlayer;

    // ðŸ” VAR TACTIQUE : Ã‰tat avant Ã©change
    debugPrint("\nðŸ” [VAR - REPLACE] --------------------------------------");
    debugPrint("ðŸ‘¤ Joueur : ${player.name}");
    debugPrint("âœ‹ Main AVANT : ${player.hand.map((c) => c.value).toList()}");
    debugPrint(
        "ðŸƒ Carte visÃ©e (Index $cardIndex) : ${player.hand[cardIndex].value} (ID: ${player.hand[cardIndex].id})");
    debugPrint(
        "ðŸ“¥ Carte piochÃ©e Ã  insÃ©rer : ${gameState.drawnCard!.value} (ID: ${gameState.drawnCard!.id})");

    if (cardIndex < 0 || cardIndex >= player.hand.length) {
      debugPrint(
          "Erreur critique: Tentative de remplacement hors limites ($cardIndex)");
      return;
    }

    PlayingCard newCard = gameState.drawnCard!;
    PlayingCard oldCard = player.hand[cardIndex];

    player.hand[cardIndex] = newCard;
    player.knownCards[cardIndex] = true;
    gameState.drawnCard = null;

    gameState.discardPile.add(oldCard);
    gameState.addToHistory("${player.name} Ã©change une carte.");

    // ðŸ” VAR TACTIQUE : Ã‰tat aprÃ¨s Ã©change
    debugPrint("âœ… Main APRÃˆS : ${player.hand.map((c) => c.value).toList()}");
    debugPrint("ðŸ—‘ï¸ DÃ©fausse : ${gameState.discardPile.last.value}");
    debugPrint("-------------------------------------------------------\n");

    _checkSpecialPower(gameState, oldCard);
  }

  static bool matchCard(GameState gameState, Player player, int cardIndex) {
    if (gameState.discardPile.isEmpty) return false;

    if (cardIndex < 0 || cardIndex >= player.hand.length) {
      debugPrint("Erreur critique: Match sur index invalide ($cardIndex)");
      return false;
    }

    PlayingCard? playerCard = player.hand[cardIndex];
    if (playerCard == null) return false;

    PlayingCard topDiscard = gameState.discardPile.last;

    // âœ… CHANGEMENT CRUCIAL : Utiliser la nouvelle mÃ©thode matches()
    // Cela prend en compte la couleur des Rois !
    if (playerCard.matches(topDiscard)) {
      gameState.discardPile.add(playerCard);

      List<PlayingCard> newHand = List.from(player.hand);
      List<bool> newKnownCards = List.from(player.knownCards);

      newHand.removeAt(cardIndex);
      newKnownCards.removeAt(cardIndex);

      player.hand = newHand;
      player.knownCards = newKnownCards;

      // âœ… Utiliser displayName pour un meilleur affichage
      gameState.addToHistory(
          "âš¡ MATCH ! ${player.name} pose ${playerCard.displayName} !");
      // ✅ FIX BUG : Les pouvoirs ne s'activent QUE pendant le tour du joueur
      // Pas pendant la défausse collective (phase réaction)
      if (gameState.phase != GamePhase.reaction) {
        _checkSpecialPower(gameState, playerCard);
      }
      return true;
    } else {
      // âœ… Message plus clair avec displayName
      gameState.addToHistory(
          "ðŸš« ${player.name} rate son match (${playerCard.displayName} â‰  ${topDiscard.displayName}) ! PÃ©nalitÃ© !");
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

    gameState.addToHistory("âš ï¸ ${player.name} prend une carte de pÃ©nalitÃ©.");
  }

  static void lookAtCard(GameState gameState, Player target, int cardIndex) {
    if (cardIndex >= 0 && cardIndex < target.knownCards.length) {
      gameState.addToHistory(
          "ðŸ‘ï¸ ${gameState.currentPlayer.name} regarde une carte de ${target.name}.");
    }
  }

  static void swapCards(
      GameState gameState, Player p1, int idx1, Player p2, int idx2) {
    if (idx1 < 0 ||
        idx1 >= p1.hand.length ||
        idx2 < 0 ||
        idx2 >= p2.hand.length) return;

    final c1 = p1.hand[idx1];
    final c2 = p2.hand[idx2];

    p1.hand[idx1] = c2;
    p2.hand[idx2] = c1;

    if (idx1 < p1.knownCards.length) p1.knownCards[idx1] = false;
    if (idx2 < p2.knownCards.length) p2.knownCards[idx2] = false;

    gameState.addToHistory(
        "ðŸ”„ Ã‰change : ${p1.name} carte #${idx1 + 1} â†” ${p2.name} carte #${idx2 + 1}.");
  }

  static void jokerEffect(GameState gameState, Player targetPlayer) {
    List<PlayingCard> shuffledHand = List.from(targetPlayer.hand);
    shuffledHand.shuffle(Random());
    targetPlayer.hand = shuffledHand;

    targetPlayer.knownCards = List.filled(targetPlayer.hand.length, false);

    gameState.addToHistory(
        "ðŸƒ JOKER ! ${gameState.currentPlayer.name} mÃ©lange ${targetPlayer.name} !");
  }

  static void _checkSpecialPower(GameState gameState, PlayingCard card) {
    List<String> powerCards = ['7', '10', 'V', 'JOKER'];
    if (powerCards.contains(card.value)) {
      gameState.isWaitingForSpecialPower = true;
      gameState.specialCardToActivate = card;
    }
  }

  static void callDutch(GameState gameState) {
    if (gameState.dutchCallerId != null) return;
    gameState.dutchCallerId = gameState.currentPlayer.id;
    gameState.phase = GamePhase.dutchCalled;
    gameState.addToHistory('ðŸŽ¯ ${gameState.currentPlayer.name} crie DUTCH !');
  }

  static void endGame(GameState gameState) {
    gameState.phase = GamePhase.ended;
    for (var p in gameState.players) {
      for (int i = 0; i < p.knownCards.length; i++) {
        p.knownCards[i] = true;
      }
    }
  }

  static void _refillDeck(GameState gameState) {
    if (gameState.discardPile.length > 1) {
      PlayingCard top = gameState.discardPile.removeLast();
      gameState.deck.addAll(gameState.discardPile);
      gameState.discardPile.clear();
      gameState.discardPile.add(top);
      gameState.deck.shuffle(_random);
      gameState.addToHistory("♻️ La pioche est vide, on mélange la défausse !");
    } else {
      // ✅ NOUVEAU : Si Dutch a été appelé, ne pas terminer immédiatement
      // Sinon, terminer la partie car plus de cartes disponibles
      if (gameState.dutchCallerId != null) {
        gameState.phase = GamePhase.dutchCalled;
        gameState.addToHistory("🏁 Plus de cartes disponibles - Fin de partie");
      } else {
        endGame(gameState);
      }
    }
  }
}