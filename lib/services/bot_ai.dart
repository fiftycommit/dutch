import 'dart:math';
import 'package:flutter/material.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/card.dart';
import '../models/game_settings.dart';
import 'game_logic.dart';
import 'bot_difficulty.dart';
import '../widgets/special_power_dialogs.dart';
import '../main.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';

enum BotGamePhase {
  exploration,  // DÃÂ©couvrir ses cartes
  optimization, // Optimiser son score
  endgame,      // Rush vers Dutch
}

// enum BotBehavior {
// }

class BotAI {
  static final Random _random = Random();

  static BuildContext? get _context {
    return navigatorKey.currentContext;
  }

  static BotGamePhase _getBotPhase(Player bot, GameState gameState) {
    int knownCount = bot.knownCardCount;
    int totalCards = bot.hand.length;
    int estimatedScore = bot.getEstimatedScore();
    
    bool someoneClose = gameState.players.any((p) => p.hand.length <= 2);
    if (estimatedScore <= 8 || someoneClose) {
      return BotGamePhase.endgame;
    }
    
    if (knownCount < totalCards) {
      return BotGamePhase.exploration;
    }
    
    return BotGamePhase.optimization;
  }

  static Future<void> playBotTurn(GameState gameState, {int? playerMMR}) async {

    Player bot = gameState.currentPlayer;
    if (bot.isHuman) {
      return;
    }

    BotDifficulty difficulty = playerMMR != null
        ? BotDifficulty.fromMMR(playerMMR)
        : _getSkillDifficulty(bot.botSkillLevel);

    BotGamePhase phase = _getBotPhase(bot, gameState);

    _applyMemoryDecay(bot, difficulty);

    int thinkingTime = _getThinkingTime(bot.botBehavior, difficulty, gameState);
    await Future.delayed(Duration(milliseconds: thinkingTime));

    if (_shouldCallDutch(gameState, bot, difficulty, phase)) {
      GameLogic.callDutch(gameState);
      return;
    }
    GameLogic.drawCard(gameState);

    await Future.delayed(const Duration(milliseconds: 1000));
    await _decideCardAction(gameState, bot, difficulty, phase);

  }

  static bool _shouldCallDutch(GameState gs, Player bot, BotDifficulty difficulty, BotGamePhase phase) {
    int estimatedScore = bot.getEstimatedScore();
    BotBehavior? behavior = bot.botBehavior;

    if (phase == BotGamePhase.exploration) {
      return false;
    }

    double audacityBonus = _calculateAudacity(gs, bot, difficulty);

    double confidence = _calculateDutchConfidence(bot);

    int threshold;

    if (phase == BotGamePhase.endgame) {
      // En endgame, plus agressif
      switch (behavior) {
        case BotBehavior.fast:
          threshold = difficulty.name == "Bronze" ? 9 :
                     difficulty.name == "Argent" ? 6 : 
                     difficulty.name == "Or" ? 5 : 4;
          break;

        case BotBehavior.aggressive:
          threshold = difficulty.name == "Bronze" ? 7 :
                     difficulty.name == "Argent" ? 5 : 
                     difficulty.name == "Or" ? 4 : 3;
          
          if (_isHumanThreatening(gs)) {
            threshold += 1;
          }
          break;

        case BotBehavior.balanced:
          if (difficulty.name == "Bronze") {
            threshold = 7;
          } else if (difficulty.name == "Argent") {
            threshold = 5;
          } else if (difficulty.name == "Or") {
            threshold = 4;
            if (_random.nextDouble() < 0.50) {
              for (var p in gs.players) {
                if (p.id != bot.id) {
                  int opponentScore = p.getEstimatedScore();
                  if (opponentScore <= estimatedScore + 1) {
                    return false;
                  }
                }
              }
            }
          } else {
            threshold = 3;
            if (_random.nextDouble() < 0.70) {
              for (var p in gs.players) {
                if (p.id != bot.id) {
                  int opponentScore = p.getEstimatedScore();
                  if (opponentScore <= estimatedScore + 1) {
                    return false;
                  }
                }
              }
            }
          }
          break;

        default:
          threshold = difficulty.dutchThreshold + 1;
      }
    } else {
      // En optimization, plus conservateur
      switch (behavior) {
        case BotBehavior.fast:
          threshold = difficulty.name == "Bronze" ? 7 :
                     difficulty.name == "Argent" ? 4 : 
                     difficulty.name == "Or" ? 3 : 2;
          break;

        case BotBehavior.aggressive:
          threshold = difficulty.name == "Bronze" ? 5 :
                     difficulty.name == "Argent" ? 3 : 
                     difficulty.name == "Or" ? 2 : 1;
          break;

        case BotBehavior.balanced:
          threshold = difficulty.name == "Bronze" ? 6 :  // Moyenne de 7 (FAST) et 5 (AGGRESSIVE)
                     difficulty.name == "Argent" ? 4 :   // Moyenne de 4 et 3 = 3.5 Ã¢â â 4
                     difficulty.name == "Or" ? 2 :       // Moyenne de 3 et 2 = 2.5 Ã¢â â 2
                                               2;        // Moyenne de 2 et 1 = 1.5 Ã¢â â 2
          break;

        default:
          threshold = difficulty.dutchThreshold;
      }
    }
    
    double adjustedThreshold = threshold + audacityBonus + (confidence * 2);
    
    bool shouldDutch = estimatedScore <= adjustedThreshold.round();
    
    if (shouldDutch) {
    }
    
    return shouldDutch;
  }
  
  static double _calculateAudacity(GameState gs, Player bot, BotDifficulty difficulty) {
    double audacity = 0.0;
    
    int cardCount = bot.hand.length;
    if (cardCount == 1) {
      audacity += 3.0; // TrÃÂ¨s audacieux
    } else if (cardCount == 2) {
      audacity += 2.0;
    } else if (cardCount == 3) {
      audacity += 1.0;
    }
    
    if (bot.consecutiveBadDraws >= 3) {
      double badDrawBonus = (bot.consecutiveBadDraws - 2) * 0.5;
      audacity += badDrawBonus;
    }
    
    int dangerousOpponents = 0;
    for (var p in gs.players) {
      if (p.id != bot.id && p.hand.length <= 2) {
        dangerousOpponents++;
      }
    }
    if (dangerousOpponents > 0) {
      double cautionPenalty = dangerousOpponents * 0.5;
      audacity -= cautionPenalty;
    }
    
    if (bot.botBehavior == BotBehavior.aggressive) {
      audacity += 1.0;
    } else if (bot.botBehavior == BotBehavior.balanced) {
      audacity -= 1.0;
    }
    
    if (difficulty.name == "Bronze") {
      audacity *= 0.5;
    } else if (difficulty.name == "Platine") {
      audacity *= 1.2;
    }
    
    return audacity.clamp(-3.0, 5.0); // Limiter entre -3 et +5
  }
  
  static double _calculateDutchConfidence(Player bot) {
    if (bot.dutchHistory.isEmpty) {
      return 0.0; // Neutre si pas d'historique
    }
    
    List<DutchAttempt> recentAttempts = bot.dutchHistory.length > 5 
        ? bot.dutchHistory.sublist(bot.dutchHistory.length - 5) 
        : bot.dutchHistory;
    
    int wins = recentAttempts.where((a) => a.won).length;
    double winRate = wins / recentAttempts.length;
    
    double avgAccuracy = recentAttempts.map((a) => a.accuracy).reduce((a, b) => a + b) / recentAttempts.length;
    
    double confidence = (winRate * 0.7 + avgAccuracy * 0.3) - 0.5; // CentrÃÂ© sur 0
    
    return confidence.clamp(-1.0, 1.0); // Entre -1 et +1
  }

  static Future<void> _decideCardAction(
      GameState gs, Player bot, BotDifficulty difficulty, BotGamePhase phase) async {

    PlayingCard? drawn = gs.drawnCard;
    if (drawn == null) {
      return;
    }

    int drawnVal = drawn.points;
    int replaceIdx = -1;
    
    bool isBadDraw = false;

    if (phase == BotGamePhase.exploration) {
      
      List<int> unknownIndices = [];
      for (int i = 0; i < bot.hand.length; i++) {
        if (i >= bot.mentalMap.length || bot.mentalMap[i] == null) {
          unknownIndices.add(i);
        }
      }

      if (unknownIndices.isNotEmpty) {
        replaceIdx = unknownIndices[_random.nextInt(unknownIndices.length)];
        
        bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
        if (!confused) {
          bot.updateMentalMap(replaceIdx, drawn);
        }
        
        GameLogic.replaceCard(gs, replaceIdx);
        return;
      } else {
        // Tomber sur la logique d'optimization
      }
    }

    
    int keepThreshold = difficulty.keepCardThreshold;
    
    // Ajuster selon le comportement
    BotBehavior? behavior = bot.botBehavior;
    switch (behavior) {
      case BotBehavior.fast:
        keepThreshold = 5;
        break;
      case BotBehavior.aggressive:
        keepThreshold += 1;
        break;
      case BotBehavior.balanced:
        if (phase == BotGamePhase.endgame) {
          keepThreshold = (5 + difficulty.keepCardThreshold) ~/ 2; // Moyenne FAST + base
        } else {
          keepThreshold = difficulty.keepCardThreshold; // Base
        }
        break;
      default:
        break;
    }

    if (phase == BotGamePhase.endgame && 
        behavior != BotBehavior.fast && 
        behavior != BotBehavior.balanced) {
      keepThreshold -= 1;
    }

    // Chercher la pire carte connue
    int worstKnownValue = -1;
    for (int i = 0; i < bot.mentalMap.length; i++) {
      if (bot.mentalMap[i] != null) {
        int cardValue = bot.mentalMap[i]!.points;
        if (cardValue > worstKnownValue && cardValue > drawnVal) {
          worstKnownValue = cardValue;
          replaceIdx = i;
        }
      }
    }

    if (replaceIdx != -1 && drawnVal <= keepThreshold) {

      bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
      if (!confused) {
        bot.updateMentalMap(replaceIdx, drawn);
      }

      GameLogic.replaceCard(gs, replaceIdx);
      
      bot.consecutiveBadDraws = 0;
    } else if (replaceIdx != -1 && worstKnownValue > drawnVal + 3) {
      
      bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
      if (!confused) {
        bot.updateMentalMap(replaceIdx, drawn);
      }
      
      GameLogic.replaceCard(gs, replaceIdx);
      
      bot.consecutiveBadDraws = 0;
    } else {
      GameLogic.discardDrawnCard(gs);
      
      isBadDraw = true;
    }
    
    if (isBadDraw) {
      bot.consecutiveBadDraws++;
    }
  }

  static Future<bool> tryReactionMatch(GameState gameState, Player bot, {int? playerMMR}) async {
    if (gameState.phase != GamePhase.reaction) return false;
    if (bot.isHuman) return false;
    if (gameState.discardPile.isEmpty) return false;

    BotDifficulty difficulty = playerMMR != null
        ? BotDifficulty.fromMMR(playerMMR)
        : _getSkillDifficulty(bot.botSkillLevel);

    BotGamePhase phase = _getBotPhase(bot, gameState);
    double matchChance = difficulty.reactionMatchChance;
    
    if (bot.botBehavior == BotBehavior.fast && phase == BotGamePhase.endgame) {
      matchChance = 1.0; // 100% de chance en endgame
    }
    else if (bot.botBehavior == BotBehavior.balanced && phase == BotGamePhase.endgame) {
      matchChance = (matchChance + 1.0) / 2; // Moyenne entre base et 100%
    }

    if (_random.nextDouble() > matchChance) {
      return false;
    }

    PlayingCard topDiscard = gameState.discardPile.last;
    
    // Chercher une carte qui match dans la main du bot
    for (int i = 0; i < bot.hand.length; i++) {
      if (i < bot.mentalMap.length && bot.mentalMap[i] != null) {
        PlayingCard knownCard = bot.mentalMap[i]!;
        
        if (knownCard.matches(topDiscard)) {
          if (_random.nextDouble() < difficulty.matchAccuracy) {
            
            int reactionDelay = (500 * (1 - difficulty.reactionSpeed)).round() + 200;
            await Future.delayed(Duration(milliseconds: reactionDelay));
            
            bool success = GameLogic.matchCard(gameState, bot, i);
            
            if (success) {
              if (i < bot.mentalMap.length) {
                bot.mentalMap.removeAt(i);
              }
              return true;
            } else {
              return false;
            }
          } else {
          }
        }
      }
    }

    if (difficulty.name == "Or" || difficulty.name == "Platine") {
      if (_random.nextDouble() < 0.30) {
        List<int> unknownIndices = [];
        for (int i = 0; i < bot.hand.length; i++) {
          if (i >= bot.mentalMap.length || bot.mentalMap[i] == null) {
            unknownIndices.add(i);
          }
        }
        
        if (unknownIndices.isNotEmpty) {
          int blindIndex = unknownIndices[_random.nextInt(unknownIndices.length)];
          PlayingCard blindCard = bot.hand[blindIndex];
          
          if (blindCard.matches(topDiscard)) {
            
            int reactionDelay = (400 * (1 - difficulty.reactionSpeed)).round() + 150;
            await Future.delayed(Duration(milliseconds: reactionDelay));
            
            bool success = GameLogic.matchCard(gameState, bot, blindIndex);
            return success;
          }
        }
      }
    }

    return false;
  }

  
  static Future<void> useBotSpecialPower(GameState gameState, {int? playerMMR}) async {
    if (!gameState.isWaitingForSpecialPower || gameState.specialCardToActivate == null) return;

    Player bot = gameState.currentPlayer;
    PlayingCard card = gameState.specialCardToActivate!;

    BotDifficulty difficulty = playerMMR != null
        ? BotDifficulty.fromMMR(playerMMR)
        : _getSkillDifficulty(bot.botSkillLevel);

    await Future.delayed(const Duration(milliseconds: 1000));

    String val = card.value;

    if (val == '7') {
      int idx = _chooseCardToLook(bot, difficulty);
      GameLogic.lookAtCard(gameState, bot, idx);
      bot.updateMentalMap(idx, bot.hand[idx]);
    } else if (val == '10') {
      Player? target = _chooseSpyTarget(gameState, bot, difficulty);
      if (target != null && target.hand.isNotEmpty) {
        int idx;
        if ((difficulty.name == "Or" || difficulty.name == "Platine") && _random.nextDouble() < 0.7) {
          idx = _random.nextBool() ? 0 : target.hand.length - 1;
        } else {
          idx = _random.nextInt(target.hand.length);
        }
        GameLogic.lookAtCard(gameState, target, idx);
      }
    } else if (val == 'V') {
      await _executeValetStrategy(gameState, bot, difficulty);
    } else if (val == 'JOKER') {
      await _executeJokerStrategy(gameState, bot, difficulty);
    }

    gameState.isWaitingForSpecialPower = false;
    gameState.specialCardToActivate = null;
    gameState.addToHistory("${bot.name} a utilisÃÂ© son pouvoir.");
  }

  static void _applyMemoryDecay(Player bot, BotDifficulty difficulty) {
    if (bot.knownCards.isEmpty || bot.mentalMap.isEmpty) return;

    for (int i = 0; i < bot.knownCards.length; i++) {
      if (bot.knownCards[i] && _random.nextDouble() < difficulty.forgetChancePerTurn) {
        bot.forgetCard(i);
      }
    }
  }

  static int _getThinkingTime(BotBehavior? behavior, BotDifficulty difficulty, GameState gameState) {
    if (behavior == null) return 800;

    if (behavior == BotBehavior.balanced) {
      bool criticalMoment = gameState.players.any((p) => p.hand.length <= 2);
      
      switch (difficulty.name) {
        case "Bronze":
          return criticalMoment ? 1000 : 800;
        case "Argent":
          return criticalMoment ? 1400 : 1000;
        case "Or":
          return criticalMoment ? 1800 : 1200;
        case "Platine":
          return criticalMoment ? 2000 : 1400;
        default:
          return 1000;
      }
    }

    if (behavior == BotBehavior.aggressive) {
      return difficulty.name == "Or" || difficulty.name == "Platine" ? 600 : 500;
    }

    return 900;
  }

  static int _chooseCardToLook(Player bot, BotDifficulty difficulty) {
    List<int> unknown = [];
    for (int i = 0; i < bot.hand.length; i++) {
      if (i >= bot.mentalMap.length || bot.mentalMap[i] == null) {
        unknown.add(i);
      }
    }
    
    if (unknown.isNotEmpty) {
      return unknown[_random.nextInt(unknown.length)];
    }

    if (bot.botBehavior == BotBehavior.balanced && 
        (difficulty.name == "Or" || difficulty.name == "Platine")) {
      int worstIdx = 0;
      int worstVal = -1;
      for (int i = 0; i < bot.mentalMap.length; i++) {
        if (bot.mentalMap[i] != null && bot.mentalMap[i]!.points > worstVal) {
          worstVal = bot.mentalMap[i]!.points;
          worstIdx = i;
        }
      }
      return worstIdx;
    }

    return _random.nextInt(bot.hand.length);
  }

  static Player? _chooseSpyTarget(GameState gs, Player bot, BotDifficulty difficulty) {
    List<Player> opponents = gs.players.where((p) => p.id != bot.id && p.hand.isNotEmpty).toList();
    if (opponents.isEmpty) return null;

    BotBehavior? behavior = bot.botBehavior;

    if ((difficulty.name == "Or" || difficulty.name == "Platine") ||
        behavior == BotBehavior.balanced) {
      opponents.sort((a, b) => a.getEstimatedScore().compareTo(b.getEstimatedScore()));
      
      if (_random.nextDouble() < 0.80) {
        return opponents.first;
      }
    }

    return opponents[_random.nextInt(opponents.length)];
  }

  static Future<void> _executeValetStrategy(GameState gs, Player bot, BotDifficulty difficulty) async {
    BotBehavior? behavior = bot.botBehavior;
    
    Player? target = _chooseValetTarget(gs, bot, difficulty);
    if (target == null || target.hand.isEmpty) return;

    int myCardIdx = _chooseBadCard(bot);
    int targetIdx;

    if ((difficulty.name == "Or" || difficulty.name == "Platine") && 
        behavior == BotBehavior.balanced) {
      targetIdx = 0;
    } else if (difficulty.name != "Bronze" && _random.nextDouble() < 0.6) {
      if (target.hand.length > 1) {
        targetIdx = _random.nextInt(target.hand.length - 1);
      } else {
        targetIdx = 0;
      }
    } else {
      targetIdx = _random.nextInt(target.hand.length);
    }

    bool confused = _random.nextDouble() < difficulty.confusionOnSwap;

    if (confused) {
    } else {
      bot.forgetCard(myCardIdx);
    }

    GameLogic.swapCards(gs, bot, myCardIdx, target, targetIdx);

    if (target.isHuman && _context != null) {
      final gameProvider = Provider.of<GameProvider>(_context!, listen: false);
      gameProvider.pauseReactionTimerForNotification();

      SpecialPowerDialogs.showBotSwapNotification(_context!, bot, target.name, targetIdx);
      await Future.delayed(const Duration(milliseconds: 2000));

      gameProvider.resumeReactionTimerAfterNotification();
    }
  }

  static Player? _chooseValetTarget(GameState gs, Player bot, BotDifficulty difficulty) {
    List<Player> opponents = gs.players.where((p) => p.id != bot.id && p.hand.isNotEmpty).toList();
    if (opponents.isEmpty) return null;

    BotBehavior? behavior = bot.botBehavior;

    // Bronze : random
    if (difficulty.name == "Bronze") {
      return opponents[_random.nextInt(opponents.length)];
    }

    if (behavior == BotBehavior.fast) {
      opponents.sort((a, b) => b.hand.length.compareTo(a.hand.length));
      return opponents.first;
    }

    if (behavior == BotBehavior.aggressive) {
      if (difficulty.name == "Or" || difficulty.name == "Platine") {
        Player? human = opponents.where((p) => p.isHuman).firstOrNull;
        if (human != null && _random.nextDouble() < 0.65) {
          return human;
        }
      }
      
      List<Player> lowCardTargets = opponents.where((p) => p.hand.length <= 3).toList();
      if (lowCardTargets.isNotEmpty && _random.nextDouble() < 0.75) {
        return lowCardTargets[_random.nextInt(lowCardTargets.length)];
      }
      return opponents[_random.nextInt(opponents.length)];
    }

    if (behavior == BotBehavior.balanced) {
      // Bronze/Argent : simple weighted
      if (difficulty.name == "Bronze" || difficulty.name == "Argent") {
        if (_random.nextDouble() < 0.70) {
          return _selectValetTargetWeighted(opponents, difficulty);
        }
        return opponents[_random.nextInt(opponents.length)];
      }
      
      // Or/Platine : HYBRIDE intelligent
      if (_random.nextDouble() < 0.50) {
        opponents.sort((a, b) => b.hand.length.compareTo(a.hand.length));
        return opponents.first;
      } else {
        Player? human = opponents.where((p) => p.isHuman).firstOrNull;
        if (human != null && _random.nextDouble() < 0.50) {
          return human;
        }
        // Ou cible weighted
        return _selectValetTargetWeighted(opponents, difficulty);
      }
    }

    // Fallback
    return opponents[_random.nextInt(opponents.length)];
  }

  static Player _selectValetTargetWeighted(List<Player> opponents, BotDifficulty difficulty) {
    Map<Player, double> threatScores = {};
    
    for (var player in opponents) {
      double score = 0.0;
      
      if (player.isHuman) {
        score += 25.0;
      }
      
      int cardCount = player.hand.length;
      if (cardCount == 1) {
        score += 120.0;
      } else if (cardCount == 2) {
        score += 80.0;
      } else if (cardCount == 3) {
        score += 45.0;
      } else if (cardCount == 4) {
        score += 20.0;
      } else {
        score += 8.0;
      }
      
      int estimatedScore = player.getEstimatedScore();
      if (estimatedScore <= 5) {
        score += 30.0;
      } else if (estimatedScore <= 10) {
        score += 18.0;
      } else if (estimatedScore <= 15) {
        score += 10.0;
      }
      
      double randomBonus = _random.nextDouble() * 30.0;
      
      if (difficulty.name == "Or" || difficulty.name == "Platine") {
        score += randomBonus * 0.3;
      } else {
        score += randomBonus * 1.0;
      }
      
      threatScores[player] = score;
    }
    
    Player selectedTarget = opponents.first;
    double maxScore = 0.0;
    
    threatScores.forEach((player, score) {
      if (score > maxScore) {
        maxScore = score;
        selectedTarget = player;
      }
    });
    
    return selectedTarget;
  }

  static Future<void> _executeJokerStrategy(GameState gs, Player bot, BotDifficulty difficulty) async {
    BotBehavior? behavior = bot.botBehavior;
    
    List<Player> possibleTargets = gs.players.where((p) => p.id != bot.id).toList();
    
    if (possibleTargets.isEmpty) {
      possibleTargets = [bot];
    }

    Player? target;

    if (behavior == BotBehavior.fast) {
      possibleTargets.sort((a, b) => a.getEstimatedScore().compareTo(b.getEstimatedScore()));
      target = possibleTargets.first; // Le joueur avec le meilleur score
    }
    else if (behavior == BotBehavior.aggressive) {
      Player? human = possibleTargets.where((p) => p.isHuman).firstOrNull;
      
      if (human != null && (difficulty.name == "Or" || difficulty.name == "Platine")) {
        if (_random.nextDouble() < 0.70) {
          target = human;
        }
      }
      
      if (target == null) {
        if ((difficulty.name == "Or" || difficulty.name == "Platine") && _random.nextDouble() < 0.6) {
          target = _selectJokerTargetWeighted(possibleTargets, difficulty);
        } else {
          target = possibleTargets[_random.nextInt(possibleTargets.length)];
        }
      }
    }
    else if (behavior == BotBehavior.balanced) {
      // Bronze/Argent : simple weighted
      if (difficulty.name == "Bronze" || difficulty.name == "Argent") {
        if (difficulty.name != "Bronze") {
          target = _selectJokerTargetWeighted(possibleTargets, difficulty);
        } else {
          target = possibleTargets[_random.nextInt(possibleTargets.length)];
        }
      }
      // Or/Platine : HYBRIDE intelligent
      else {
        if (_random.nextDouble() < 0.50) {
          possibleTargets.sort((a, b) => a.getEstimatedScore().compareTo(b.getEstimatedScore()));
          target = possibleTargets.first;
        } else {
          Player? human = possibleTargets.where((p) => p.isHuman).firstOrNull;
          if (human != null && _random.nextDouble() < 0.60) {
            target = human;
          } else {
            target = _selectJokerTargetWeighted(possibleTargets, difficulty);
          }
        }
      }
    }
    // Fallback
    else {
      if (difficulty.name != "Bronze" && _random.nextDouble() < 0.3) {
        target = _selectJokerTargetWeighted(possibleTargets, difficulty);
      } else {
        target = possibleTargets[_random.nextInt(possibleTargets.length)];
      }
    }

    GameLogic.jokerEffect(gs, target);

    if (target.id == bot.id) {
      bot.resetMentalMap();
    }

    if (target.isHuman && _context != null) {
      final gameProvider = Provider.of<GameProvider>(_context!, listen: false);
      gameProvider.pauseReactionTimerForNotification();

      SpecialPowerDialogs.showBotJokerNotification(_context!, bot, target.name);
      await Future.delayed(const Duration(milliseconds: 3000));

      gameProvider.resumeReactionTimerAfterNotification();
    }
  }

  static Player _selectJokerTargetWeighted(List<Player> targets, BotDifficulty difficulty) {
    Map<Player, double> threatScores = {};
    
    for (var player in targets) {
      double score = 0.0;
      
      if (player.isHuman) {
        score += 30.0;
      }
      
      int cardCount = player.hand.length;
      if (cardCount <= 2) {
        score += 50.0;
      } else if (cardCount == 3) {
        score += 30.0;
      } else if (cardCount == 4) {
        score += 15.0;
      }
      
      int estimatedScore = player.getEstimatedScore();
      if (estimatedScore <= 5) {
        score += 20.0;
      } else if (estimatedScore <= 10) {
        score += 10.0;
      } else if (estimatedScore <= 15) {
        score += 5.0;
      }
      
      double randomFactor = _random.nextDouble() * 20.0;
      
      if (difficulty.name == "Or" || difficulty.name == "Platine") {
        score += randomFactor * 0.3;
      } else if (difficulty.name == "Argent") {
        score += randomFactor * 1.0;
      } else {
        score += randomFactor * 2.0;
      }
      
      threatScores[player] = score;
    }
    
    Player selectedTarget = targets.first;
    double maxScore = 0.0;
    
    threatScores.forEach((player, score) {
      if (score > maxScore) {
        maxScore = score;
        selectedTarget = player;
      }
    });
    
    return selectedTarget;
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
    int worstIdx = 0;
    int worstValue = -1;

    for (int i = 0; i < bot.mentalMap.length; i++) {
      if (bot.mentalMap[i] != null && bot.mentalMap[i]!.points > worstValue) {
        worstValue = bot.mentalMap[i]!.points;
        worstIdx = i;
      }
    }

    if (worstValue == -1) {
      return _chooseUnknownCard(bot);
    }

    return worstIdx;
  }

  static BotDifficulty _getSkillDifficulty(BotSkillLevel? level) {
    if (level == null) return BotDifficulty.silver;
    
    switch (level) {
      case BotSkillLevel.bronze:
        return BotDifficulty.bronze;
      case BotSkillLevel.silver:
        return BotDifficulty.silver;
      case BotSkillLevel.gold:
        return BotDifficulty.gold;
    }
  }

  static bool _isHumanThreatening(GameState gs) {
    try {
      Player human = gs.players.firstWhere((p) => p.isHuman);
      return human.hand.length <= 3;
    } catch (e) {
      return false;
    }
  }
}