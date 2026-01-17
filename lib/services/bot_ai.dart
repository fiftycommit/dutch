import 'dart:math';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/card.dart';
import '../models/game_settings.dart';
import 'game_logic.dart';
import 'bot_difficulty.dart';
import 'package:flutter/foundation.dart';

class BotAI {
  static final Random _random = Random();

  static Future<void> playBotTurn(GameState gameState, {int? playerMMR}) async {
    debugPrint("🤖 [playBotTurn] DÉBUT - Bot: ${gameState.currentPlayer.name}");
  
    Player bot = gameState.currentPlayer;
    if (bot.isHuman) {
      debugPrint("❌ [playBotTurn] Ce n'est pas un bot!");
      return;
    }

    // 🎯 Déterminer la difficulté du bot (SBMM ou manuel)
    BotDifficulty difficulty = playerMMR != null 
        ? BotDifficulty.fromMMR(playerMMR)
        : _getDifficultyFromPersonality(bot.botPersonality);
    
    debugPrint("🎯 [playBotTurn] Difficulté: ${difficulty.name}");

    // 🧠 Appliquer le decay mémoriel (oubli)
    _applyMemoryDecay(bot, difficulty);
    debugPrint("🧠 [playBotTurn] Mémoire décayée");

    int thinkingTime = _getThinkingTime(bot.botPersonality);
    debugPrint("⏳ [playBotTurn] Temps de réflexion: ${thinkingTime}ms");
    await Future.delayed(Duration(milliseconds: thinkingTime));

    // 🎯 Décision Dutch basée sur le SCORE ESTIMÉ
    if (_shouldCallDutch(gameState, bot, difficulty)) {
      debugPrint("📢 [playBotTurn] Le bot appelle DUTCH!");
      GameLogic.callDutch(gameState);
      return;
    }

    debugPrint("🎴 [playBotTurn] Le bot pioche...");
    GameLogic.drawCard(gameState);
    debugPrint("✅ [playBotTurn] Carte piochée: ${gameState.drawnCard?.value}");
  
    await Future.delayed(const Duration(milliseconds: 1000));
  
    debugPrint("🤔 [playBotTurn] Décision de l'action...");
    await _decideCardAction(gameState, bot, difficulty);
    debugPrint("✅ [playBotTurn] Action décidée et exécutée");
    
    debugPrint("🏁 [playBotTurn] FIN");
  }

  static Future<void> useBotSpecialPower(GameState gameState, {int? playerMMR}) async {
    if (!gameState.isWaitingForSpecialPower || gameState.specialCardToActivate == null) return;
    
    Player bot = gameState.currentPlayer;
    PlayingCard card = gameState.specialCardToActivate!;
    
    BotDifficulty difficulty = playerMMR != null 
        ? BotDifficulty.fromMMR(playerMMR)
        : _getDifficultyFromPersonality(bot.botPersonality);
    
    await Future.delayed(const Duration(milliseconds: 1000));
    
    String val = card.value;
    
    if (val == '7') {
      // Carte 7 : Regarder UNE de ses cartes
      int idx = _chooseUnknownCard(bot);
      GameLogic.lookAtCard(gameState, bot, idx);
      
      // 🧠 NOUVEAU : Mettre à jour la carte mentale
      bot.updateMentalMap(idx, bot.hand[idx]);
      debugPrint("👁️ Bot regarde sa carte #$idx et l'enregistre");

    } else if (val == '10') {
      // Carte 10 : Regarder carte adverse
      Player? target = _findTargetPlayer(gameState, bot);
      if (target != null) {
          int idx = _random.nextInt(target.hand.length);
          GameLogic.lookAtCard(gameState, target, idx);
          debugPrint("🔍 Bot regarde la carte #$idx de ${target.name}");
      }

    } else if (val == 'V') {
      // Valet : Échange
      Player? target = _findTargetPlayer(gameState, bot);
      if (target != null && target.hand.isNotEmpty) {
        int myBadCardIdx = _chooseBadCard(bot);
        int targetIdx = _random.nextInt(target.hand.length);
        
        // 🧠 NOUVEAU : Confusion possible selon difficulté
        bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
        
        if (confused) {
          debugPrint("😵 Bot confus ! Il garde l'ancienne valeur en mémoire");
          // Le bot ne met PAS à jour sa carte mentale
        } else {
          // Le bot oublie sa carte (ne sait pas ce qu'il a reçu)
          bot.forgetCard(myBadCardIdx);
        }
        
        GameLogic.swapCards(gameState, bot, myBadCardIdx, target, targetIdx);
        debugPrint("🔄 Bot échange sa carte #$myBadCardIdx avec la carte #$targetIdx de ${target.name}");
      }

    } else if (val == 'JOKER') {
      // Joker : Mélanger la main d'un adversaire
      Player? target = gameState.players.firstWhere((p) => p.isHuman, orElse: () => bot);
      GameLogic.jokerEffect(gameState, target);
      
      // 🧠 NOUVEAU : Si le bot se mélange lui-même, il oublie tout
      if (target.id == bot.id) {
        bot.resetMentalMap();
        debugPrint("🌀 Bot mélange ses propres cartes et oublie tout!");
      }
      
      debugPrint("🃏 Bot mélange les cartes de ${target.name}");
    }

    gameState.isWaitingForSpecialPower = false;
    gameState.specialCardToActivate = null;
    gameState.addToHistory("${bot.name} a utilisé son pouvoir.");
  }
  
  /// 🧠 MODIFIÉ : Applique l'oubli selon la difficulté
  static void _applyMemoryDecay(Player bot, BotDifficulty difficulty) {
    if (bot.knownCards.isEmpty || bot.mentalMap.isEmpty) return;
    
    for (int i = 0; i < bot.knownCards.length; i++) {
      if (bot.knownCards[i] && _random.nextDouble() < difficulty.forgetChancePerTurn) {
        bot.forgetCard(i);
        debugPrint("💭 Bot oublie sa carte #$i");
      }
    }
  }

  static int _getThinkingTime(BotPersonality? p) {
    return 1000;
  }

  /// 🎯 MODIFIÉ : Dutch basé sur le SCORE ESTIMÉ (carte mentale)
  static bool _shouldCallDutch(GameState gs, Player bot, BotDifficulty difficulty) {
    int estimatedScore = bot.getEstimatedScore();
    
    debugPrint("🎯 Score estimé du bot: $estimatedScore (seuil Dutch: ${difficulty.dutchThreshold})");
    
    return estimatedScore <= difficulty.dutchThreshold;
  }

  /// 🎯 MODIFIÉ : Décision basée sur la carte mentale
  static Future<void> _decideCardAction(GameState gs, Player bot, BotDifficulty difficulty) async {
    debugPrint("🤔 [_decideCardAction] DÉBUT");
    
    PlayingCard? drawn = gs.drawnCard;
    if (drawn == null) {
      debugPrint("❌ [_decideCardAction] Pas de carte piochée");
      return;
    }

    debugPrint("🎴 [_decideCardAction] Carte piochée: ${drawn.value} (${drawn.points} pts)");

    int drawnVal = drawn.points;
    int replaceIdx = -1;

    // Chercher une carte connue plus haute (dans la carte mentale)
    for (int i = 0; i < bot.mentalMap.length; i++) {
      if (bot.mentalMap[i] != null) {
        int mentalCardValue = bot.mentalMap[i]!.points;
        
        if (mentalCardValue > drawnVal) {
          replaceIdx = i;
          debugPrint("🔄 [_decideCardAction] Carte mentale plus haute trouvée: index $i (${mentalCardValue} pts)");
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
      
      // 🧠 NOUVEAU : Confusion possible
      bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
      
      if (confused) {
        debugPrint("😵 Bot confus ! Il croit toujours avoir l'ancienne carte");
        // Le bot garde l'ancienne valeur dans sa carte mentale
      } else {
        // Mise à jour normale : le bot connaît sa nouvelle carte
        bot.updateMentalMap(replaceIdx, drawn);
      }
      
      GameLogic.replaceCard(gs, replaceIdx);
    } else {
      debugPrint("🗑️ [_decideCardAction] DÉCISION: DÉFAUSSER");
      GameLogic.discardDrawnCard(gs);
    }
  
    debugPrint("🏁 [_decideCardAction] FIN");
  }

  static int _chooseUnknownCard(Player bot) {
    List<int> unknownIndices = [];
    for (int i = 0; i < bot.hand.length; i++) {
      if (i >= bot.mentalMap.length || bot.mentalMap[i] == null) {
        unknownIndices.add(i);
      }
    }
    if (unknownIndices.isNotEmpty) {
      return unknownIndices[_random.nextInt(unknownIndices.length)];
    }
    return 0;
  }
  
  static int _chooseBadCard(Player bot) {
    // Chercher dans la carte mentale
    for (int i = 0; i < bot.mentalMap.length; i++) {
      if (bot.mentalMap[i] != null && bot.mentalMap[i]!.points > 9) {
        return i;
      }
    }
    return _random.nextInt(bot.hand.length);
  }

  static Player? _findTargetPlayer(GameState gameState, Player me) {
    try {
       return gameState.players.firstWhere(
         (p) => p.isHuman && p.id != me.id, 
         orElse: () => gameState.players.firstWhere((p) => p.id != me.id)
       );
    } catch (e) {
       return null;
    }
  }

  /// 🎯 NOUVEAU : Conversion BotPersonality → BotDifficulty (mode manuel)
  static BotDifficulty _getDifficultyFromPersonality(BotPersonality? personality) {
    if (personality == null) return BotDifficulty.silver;
    
    switch (personality) {
      case BotPersonality.beginner:
      case BotPersonality.novice:
        return BotDifficulty.bronze;
      
      case BotPersonality.balanced:
      case BotPersonality.cautious:
        return BotDifficulty.silver;
      
      case BotPersonality.aggressive:
      case BotPersonality.legend:
        return BotDifficulty.gold;
    }
  }
}