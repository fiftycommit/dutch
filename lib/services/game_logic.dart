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
      gameState.addToHistory("🎲 Tirage au sort : $starterName !");
    }

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
    } else {
      endGame(gameState);
    }
  }

  static void discardDrawnCard(GameState gameState) {
    if (gameState.drawnCard == null) return;
    
    PlayingCard card = gameState.drawnCard!;
    gameState.discardPile.add(card);
    gameState.drawnCard = null; 
    gameState.addToHistory("${gameState.currentPlayer.name} rejette la carte piochée.");

    _checkSpecialPower(gameState, card);
  }

  static void replaceCard(GameState gameState, int cardIndex) {
    if (gameState.drawnCard == null) return;
    
    Player player = gameState.currentPlayer;
    
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

    // ✅ CHANGEMENT CRUCIAL : Utiliser la nouvelle méthode matches()
    // Cela prend en compte la couleur des Rois !
    if (playerCard.matches(topDiscard)) {
      gameState.discardPile.add(playerCard);
      
      List<PlayingCard> newHand = List.from(player.hand);
      List<bool> newKnownCards = List.from(player.knownCards);
      
      newHand.removeAt(cardIndex);
      newKnownCards.removeAt(cardIndex);
      
      player.hand = newHand;
      player.knownCards = newKnownCards;

      // ✅ Utiliser displayName pour un meilleur affichage
      gameState.addToHistory("⚡ MATCH ! ${player.name} pose ${playerCard.displayName} !");
      _checkSpecialPower(gameState, playerCard);
      return true;
    } else {
      // ✅ Message plus clair avec displayName
      gameState.addToHistory(
        "🚫 ${player.name} rate son match (${playerCard.displayName} ≠ ${topDiscard.displayName}) ! Pénalité !"
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
    
    gameState.addToHistory("⚠️ ${player.name} prend une carte de pénalité.");
  }

  static void lookAtCard(GameState gameState, Player target, int cardIndex) {
    if (cardIndex >= 0 && cardIndex < target.knownCards.length) {
      gameState.addToHistory("👁️ ${gameState.currentPlayer.name} regarde une carte de ${target.name}.");
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
    
    gameState.addToHistory("🔄 Échange : ${p1.name} carte #${idx1 + 1} ↔ ${p2.name} carte #${idx2 + 1}.");
  }

  static void jokerEffect(GameState gameState, Player targetPlayer) {
    List<PlayingCard> shuffledHand = List.from(targetPlayer.hand);
    shuffledHand.shuffle(Random());
    targetPlayer.hand = shuffledHand;
    
    targetPlayer.knownCards = List.filled(targetPlayer.hand.length, false);
    
    gameState.addToHistory("🃏 JOKER ! ${gameState.currentPlayer.name} mélange ${targetPlayer.name} !");
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
    gameState.addToHistory('🎯 ${gameState.currentPlayer.name} crie DUTCH !');
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
    }
  }
}