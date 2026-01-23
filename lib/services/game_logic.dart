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
      p.mentalMap = []; // â Reset mentalMap aussi
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

    // â NOUVEAU: Initialiser la mémoire des bots (ils mémorisent 2 cartes comme le joueur)
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
          ? "Vous commencez"
          : "${players[randomIndex].name} commence";
      gameState.addToHistory("ð² Tirage au sort : $starterName !");
    }

    Player human = gameState.players.firstWhere((p) => p.isHuman);
    debugPrint("\nð [VAR - INIT] --------------------------------------");
    debugPrint("ð Main de DÃPART du joueur : ${human.hand.map((c) => c.value).toList()}");
    debugPrint("ð¢ IDs des cartes : ${human.hand.map((c) => c.id).toList()}");
    
    // â Debug: Afficher ce que les bots ont mémorisé
    for (var bot in players.where((p) => !p.isHuman)) {
      debugPrint("ð¤ ${bot.name} mémorise: ${bot.mentalMap.where((c) => c != null).map((c) => c!.value).toList()}");
    }
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
      gameState.addToHistory("Vous avez mémorisé vos cartes.");
    } catch (e) {
      debugPrint("Erreur initialReveal: $e");
    }
  }

  static void drawCard(GameState gameState) {
    if (gameState.deck.isEmpty) _refillDeck(gameState);

    if (gameState.deck.isNotEmpty) {
      gameState.drawnCard = gameState.deck.removeLast();
      gameState.addToHistory("${gameState.currentPlayer.name} pioche.");

      if (gameState.currentPlayer.isHuman) {
        debugPrint("\nð [VAR - DRAW] Vous avez pioché : ${gameState.drawnCard!.value} (Suite: ${gameState.drawnCard!.suit})");
      }
    } else {
      endGame(gameState);
    }
  }

  static void discardDrawnCard(GameState gameState) {
    if (gameState.drawnCard == null) return;

    debugPrint("\nð [VAR - DISCARD] Joueur rejette la carte : ${gameState.drawnCard!.value}");
    debugPrint("â Main INCHANGÃE : ${gameState.currentPlayer.hand.map((c) => c.value).toList()}");

    PlayingCard card = gameState.drawnCard!;
    gameState.discardPile.add(card);
    gameState.drawnCard = null;
    gameState.addToHistory("${gameState.currentPlayer.name} rejette la carte piochée.");

    _checkSpecialPower(gameState, card);
  }

  static void replaceCard(GameState gameState, int cardIndex) {
    if (gameState.drawnCard == null) return;

    Player player = gameState.currentPlayer;

    debugPrint("\nð [VAR - REPLACE] --------------------------------------");
    debugPrint("ð¤ Joueur : ${player.name}");
    debugPrint("â Main AVANT : ${player.hand.map((c) => c.value).toList()}");
    debugPrint("ð¯ Carte visée (Index $cardIndex) : ${player.hand[cardIndex].value} (ID: ${player.hand[cardIndex].id})");
    debugPrint("ð¥ Carte piochée Ã  insérer : ${gameState.drawnCard!.value} (ID: ${gameState.drawnCard!.id})");

    if (cardIndex < 0 || cardIndex >= player.hand.length) {
      debugPrint("Erreur critique: Tentative de remplacement hors limites ($cardIndex)");
      return;
    }

    PlayingCard newCard = gameState.drawnCard!;
    PlayingCard oldCard = player.hand[cardIndex];

    player.hand[cardIndex] = newCard;
    player.knownCards[cardIndex] = true;
    gameState.drawnCard = null;

    gameState.discardPile.add(oldCard);
    gameState.addToHistory("${player.name} échange une carte.");

    debugPrint("â Main APRÃS : ${player.hand.map((c) => c.value).toList()}");
    debugPrint("ðï¸ Défausse : ${gameState.discardPile.last.value}");
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

    if (playerCard.matches(topDiscard)) {
      gameState.discardPile.add(playerCard);

      List<PlayingCard> newHand = List.from(player.hand);
      List<bool> newKnownCards = List.from(player.knownCards);

      newHand.removeAt(cardIndex);
      newKnownCards.removeAt(cardIndex);

      player.hand = newHand;
      player.knownCards = newKnownCards;
      
      // â NOUVEAU: Mettre Ã  jour la mentalMap du bot aussi
      if (!player.isHuman && cardIndex < player.mentalMap.length) {
        player.mentalMap.removeAt(cardIndex);
      }

      gameState.addToHistory("â¡ MATCH ! ${player.name} pose ${playerCard.displayName} !");
      if (gameState.phase != GamePhase.reaction) {
        _checkSpecialPower(gameState, playerCard);
      }
      return true;
    } else {
      gameState.addToHistory("ð« ${player.name} rate son match (${playerCard.displayName} â  ${topDiscard.displayName}) ! Pénalité !");
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
    
    // â NOUVEAU: Ajouter null Ã  la mentalMap du bot
    if (!player.isHuman) {
      player.mentalMap.add(null);
    }

    gameState.addToHistory("â ï¸ ${player.name} prend une carte de pénalité.");
  }

  static void lookAtCard(GameState gameState, Player target, int cardIndex) {
    if (cardIndex >= 0 && cardIndex < target.knownCards.length) {
      gameState.addToHistory("ðï¸ ${gameState.currentPlayer.name} regarde une carte de ${target.name}.");
    }
  }

  static void swapCards(GameState gameState, Player p1, int idx1, Player p2, int idx2) {
    if (idx1 < 0 || idx1 >= p1.hand.length || idx2 < 0 || idx2 >= p2.hand.length) return;

    final c1 = p1.hand[idx1];
    final c2 = p2.hand[idx2];

    p1.hand[idx1] = c2;
    p2.hand[idx2] = c1;

    if (idx1 < p1.knownCards.length) p1.knownCards[idx1] = false;
    if (idx2 < p2.knownCards.length) p2.knownCards[idx2] = false;
    
    // â NOUVEAU: Mettre Ã  jour les mentalMaps des bots
    if (!p1.isHuman && idx1 < p1.mentalMap.length) {
      p1.mentalMap[idx1] = null; // Le bot oublie cette carte (elle a changé)
    }
    if (!p2.isHuman && idx2 < p2.mentalMap.length) {
      p2.mentalMap[idx2] = null; // Le bot oublie cette carte (elle a changé)
    }

    gameState.addToHistory("ð Ãchange : ${p1.name} carte #${idx1 + 1} â ${p2.name} carte #${idx2 + 1}.");
  }

  static void jokerEffect(GameState gameState, Player targetPlayer) {
    List<PlayingCard> shuffledHand = List.from(targetPlayer.hand);
    shuffledHand.shuffle(Random());
    targetPlayer.hand = shuffledHand;

    targetPlayer.knownCards = List.filled(targetPlayer.hand.length, false);
    
    // â NOUVEAU: Reset la mentalMap du bot ciblé
    if (!targetPlayer.isHuman) {
      targetPlayer.mentalMap = List.filled(targetPlayer.hand.length, null);
    }

    gameState.addToHistory("ð JOKER ! ${gameState.currentPlayer.name} mélange ${targetPlayer.name} !");
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
    gameState.addToHistory('ð³ï¸ ${gameState.currentPlayer.name} crie DUTCH !');
  }

  static void endGame(GameState gameState) {
    gameState.phase = GamePhase.ended;
    for (var p in gameState.players) {
      for (int i = 0; i < p.knownCards.length; i++) {
        p.knownCards[i] = true;
      }
    }
  }

  // ð NOUVELLE MÃTHODE : Passer au joueur suivant
  static void nextPlayer(GameState gameState) {
    gameState.nextTurn();
    debugPrint("â¡ï¸ Prochain joueur: ${gameState.currentPlayer.name}");
  }

  static void _refillDeck(GameState gameState) {
    if (gameState.discardPile.length > 1) {
      PlayingCard top = gameState.discardPile.removeLast();
      gameState.deck.addAll(gameState.discardPile);
      gameState.discardPile.clear();
      gameState.discardPile.add(top);
      gameState.deck.shuffle(_random);
      gameState.addToHistory("â»ï¸ La pioche est vide, on mélange la défausse !");
    } else {
      if (gameState.dutchCallerId != null) {
        gameState.phase = GamePhase.dutchCalled;
        gameState.addToHistory("ð Plus de cartes disponibles - Fin de partie");
      } else {
        endGame(gameState);
      }
    }
  }
}