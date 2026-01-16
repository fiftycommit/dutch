import 'dart:math';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/card.dart';
import '../models/game_settings.dart';
import 'game_logic.dart';
import 'package:flutter/foundation.dart';

class BotAI {
  static final Random _random = Random();

  static Future<void> playBotTurn(GameState gameState) async {
    debugPrint("🤖 [playBotTurn] DÉBUT - Bot: ${gameState.currentPlayer.name}");
  
    Player bot = gameState.currentPlayer;
    if (bot.isHuman) {
      debugPrint("❌ [playBotTurn] Ce n'est pas un bot!");
      return;
    }

    _applyMemoryDecay(bot);
    debugPrint("🧠 [playBotTurn] Mémoire décayée");

    int thinkingTime = _getThinkingTime(bot.botPersonality);
    debugPrint("⏳ [playBotTurn] Temps de réflexion: ${thinkingTime}ms");
    await Future.delayed(Duration(milliseconds: thinkingTime));

    if (_shouldCallDutch(gameState, bot)) {
      debugPrint("📢 [playBotTurn] Le bot appelle DUTCH!");
      GameLogic.callDutch(gameState);
      return;
    }

    debugPrint("🎴 [playBotTurn] Le bot pioche...");
    GameLogic.drawCard(gameState);
    debugPrint("✅ [playBotTurn] Carte piochée: ${gameState.drawnCard?.value}");
  
    await Future.delayed(const Duration(milliseconds: 1000));
  
    debugPrint("🤔 [playBotTurn] Décision de l'action...");
    await _decideCardAction(gameState, bot);
    debugPrint("✅ [playBotTurn] Action décidée et exécutée");
    
    debugPrint("🏁 [playBotTurn] FIN");
  }

  static Future<void> useBotSpecialPower(GameState gameState) async {
    if (!gameState.isWaitingForSpecialPower || gameState.specialCardToActivate == null) return;
    
    Player bot = gameState.currentPlayer;
    PlayingCard card = gameState.specialCardToActivate!;
    
    await Future.delayed(const Duration(milliseconds: 1000));
    
    String val = card.value;
    
    // ✅ CORRECTION : Seulement 7, 10, V, JOKER
    if (val == '7') {
      // Carte 7 : Regarder UNE de ses cartes
      int idx = _chooseUnknownCard(bot);
      GameLogic.lookAtCard(gameState, bot, idx);
      bot.knownCards[idx] = true;
      debugPrint("👁️ Bot regarde sa carte #$idx");

    } else if (val == '10') {
      // Carte 10 : Regarder carte adverse
      Player? target = _findTargetPlayer(gameState, bot);
      if (target != null) {
          int idx = _random.nextInt(target.hand.length);
          GameLogic.lookAtCard(gameState, target, idx);
          debugPrint("🔍 Bot regarde la carte #$idx de ${target.name}");
      }

    } else if (val == 'V') {
      // Valet : Échange (bot choisit toujours option 1 : ma mauvaise carte ↔ carte adverse)
      Player? target = _findTargetPlayer(gameState, bot);
      if (target != null && target.hand.isNotEmpty) {
        int myBadCardIdx = _chooseBadCard(bot);
        int targetIdx = _random.nextInt(target.hand.length);
        GameLogic.swapCards(gameState, bot, myBadCardIdx, target, targetIdx);
        debugPrint("🔄 Bot échange sa carte #$myBadCardIdx avec la carte #$targetIdx de ${target.name}");
      }

    } else if (val == 'JOKER') {
      // Joker : Mélanger la main d'un adversaire (de préférence l'humain)
      Player? target = gameState.players.firstWhere((p) => p.isHuman, orElse: () => bot);
      GameLogic.jokerEffect(gameState, target);
      debugPrint("🃏 Bot mélange les cartes de ${target.name}");
    }

    // ✅ FIX : Nettoyer l'état des pouvoirs spéciaux
    gameState.isWaitingForSpecialPower = false;
    gameState.specialCardToActivate = null;
    gameState.addToHistory("${bot.name} a utilisé son pouvoir.");
  }
  
  static void _applyMemoryDecay(Player bot) {
    if (bot.knownCards.isEmpty) return;
    double chanceToForget = 0.1; 
    for (int i = 0; i < bot.knownCards.length; i++) {
      if (bot.knownCards[i] && _random.nextDouble() < chanceToForget) {
        bot.knownCards[i] = false;
      }
    }
  }

  static int _getThinkingTime(BotPersonality? p) {
    return 1000;
  }

  static bool _shouldCallDutch(GameState gs, Player bot) {
    int estimatedScore = 0;
    for (var c in bot.hand) {
      estimatedScore += c.points;
    }
    return estimatedScore < 10;
  }

  static Future<void> _decideCardAction(GameState gs, Player bot) async {
    debugPrint("🤔 [_decideCardAction] DÉBUT");
    
    PlayingCard? drawn = gs.drawnCard;
    if (drawn == null) {
      debugPrint("❌ [_decideCardAction] Pas de carte piochée");
      return;
    }

    debugPrint("🎴 [_decideCardAction] Carte piochée: ${drawn.value} (${drawn.points} pts)");

    int drawnVal = _getCardValue(drawn);
    int replaceIdx = -1;

    // Chercher une carte connue plus haute
    for (int i=0; i<bot.hand.length; i++) {
      PlayingCard c = bot.hand[i];
      if (bot.knownCards[i]) {
        if (_getCardValue(c) > drawnVal) {
          replaceIdx = i;
          debugPrint("🔄 [_decideCardAction] Carte connue plus haute trouvée: index $i (${c.value})");
          break;
        }
      }
    }
  
    // Sinon prendre une carte inconnue
    if (replaceIdx == -1) {
      replaceIdx = _chooseUnknownCard(bot);
      debugPrint("❓ [_decideCardAction] Carte inconnue choisie: index $replaceIdx");
    }

    // Décision : remplacer ou défausser
    if (replaceIdx != -1 && drawnVal < 8) {
      debugPrint("✅ [_decideCardAction] DÉCISION: REMPLACER (index $replaceIdx)");
      GameLogic.replaceCard(gs, replaceIdx);
    } else {
      debugPrint("🗑️ [_decideCardAction] DÉCISION: DÉFAUSSER");
      GameLogic.discardDrawnCard(gs);
    }
  
    debugPrint("🏁 [_decideCardAction] FIN");
  }

  static int _chooseUnknownCard(Player bot) {
    List<int> unknownIndices = [];
    for (int i=0; i<bot.hand.length; i++) {
      if (!bot.knownCards[i]) unknownIndices.add(i);
    }
    if (unknownIndices.isNotEmpty) return unknownIndices[_random.nextInt(unknownIndices.length)];
    return 0;
  }
  
  static int _chooseBadCard(Player bot) {
    for (int i=0; i<bot.hand.length; i++) {
       if (bot.knownCards[i] && _getCardValue(bot.hand[i]) > 9) return i;
    }
    return _random.nextInt(bot.hand.length);
  }

  static Player? _findTargetPlayer(GameState gameState, Player me) {
    try {
       return gameState.players.firstWhere((p) => p.isHuman && p.id != me.id, orElse: () => gameState.players.firstWhere((p) => p.id != me.id));
    } catch (e) {
       return null;
    }
  }

  static int _getCardValue(PlayingCard card) {
    return card.points;
  }
}