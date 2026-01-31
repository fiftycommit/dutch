import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/game_state.dart';
import '../../../models/game_settings.dart';
import '../../../models/player.dart';
import 'bot_difficulty.dart';
import '../game_logic.dart';
import '../../../widgets/dialogs/shared/unified_power_dialogs.dart';
import '../../../providers/game_provider.dart';
import 'bot_memory_manager.dart';
import 'bot_threat_analyzer.dart';

/// Gestion des pouvoirs spéciaux des bots
/// Principe GRASP: Controller - Orchestre l'utilisation des pouvoirs
class BotPowerHandler {
  static final Random _random = Random();

  /// Utilise le pouvoir spécial du bot
  static Future<void> useBotSpecialPower(GameState gameState, BotDifficulty difficulty, BuildContext? context) async {
    if (!gameState.isWaitingForSpecialPower || gameState.specialCardToActivate == null) return;

    Player bot = gameState.currentPlayer;
    String val = gameState.specialCardToActivate!.value;

    await Future.delayed(const Duration(milliseconds: 1000));

    if (val == '7') {
      _usePower7(gameState, bot, difficulty);
    } else if (val == '10') {
      await _usePower10(gameState, bot, difficulty, context);
    } else if (val == 'V') {
      await _usePowerValet(gameState, bot, difficulty, context);
    } else if (val == 'JOKER') {
      await _usePowerJoker(gameState, bot, difficulty, context);
    }

    gameState.isWaitingForSpecialPower = false;
    gameState.specialCardToActivate = null;
    gameState.addToHistory("${bot.name} a utilisé son pouvoir.");
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POUVOIR 7 : Regarder sa propre carte
  // ═══════════════════════════════════════════════════════════════════════════

  static void _usePower7(GameState gameState, Player bot, BotDifficulty difficulty) {
    int idx = BotMemoryManager.chooseCardToLook(bot, difficulty);
    GameLogic.lookAtCard(gameState, bot, idx);
    bot.updateMentalMap(idx, bot.hand[idx]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POUVOIR 10 : Espionner une carte adverse
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> _usePower10(GameState gameState, Player bot, BotDifficulty difficulty, BuildContext? context) async {
    Player? target = _chooseSpyTarget(gameState, bot, difficulty);
    if (target == null || target.hand.isEmpty) return;

    int idx;
    if ((difficulty.name == "Or" || difficulty.name == "Platine") && _random.nextDouble() < 0.7) {
      idx = _random.nextBool() ? 0 : target.hand.length - 1;
    } else {
      idx = _random.nextInt(target.hand.length);
    }
    GameLogic.lookAtCard(gameState, target, idx);
    
    if (target.isHuman && context != null) {
      final gameProvider = Provider.of<GameProvider>(context, listen: false);
      gameProvider.pauseReactionTimerForNotification();
      UnifiedPowerDialogs.showBotSpyNotification(context, bot, target.name, idx);
      await Future.delayed(const Duration(milliseconds: 2000));
      gameProvider.resumeReactionTimerAfterNotification();
    }
  }

  static Player? _chooseSpyTarget(GameState gs, Player bot, BotDifficulty difficulty) {
    List<Player> opponents = gs.players.where((p) => p.id != bot.id && p.hand.isNotEmpty).toList();
    if (opponents.isEmpty) return null;

    if ((difficulty.name == "Or" || difficulty.name == "Platine") ||
        bot.botBehavior == BotBehavior.balanced) {
      opponents.sort((a, b) => a.getEstimatedScore().compareTo(b.getEstimatedScore()));
      if (_random.nextDouble() < 0.80) return opponents.first;
    }

    return opponents[_random.nextInt(opponents.length)];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POUVOIR VALET : Échange de cartes
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> _usePowerValet(GameState gs, Player bot, BotDifficulty difficulty, BuildContext? context) async {
    Player? target = _chooseValetTarget(gs, bot, difficulty);
    if (target == null || target.hand.isEmpty) return;

    int myCardIdx = BotMemoryManager.chooseBadCard(bot);
    int targetIdx = _chooseValetTargetCardIndex(target, difficulty, bot.botBehavior);

    bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
    if (!confused) {
      bot.forgetCard(myCardIdx);
    }

    GameLogic.swapCards(gs, bot, myCardIdx, target, targetIdx);

    if (target.isHuman && context != null) {
      final gameProvider = Provider.of<GameProvider>(context, listen: false);
      gameProvider.pauseReactionTimerForNotification();
      UnifiedPowerDialogs.showBotSwapNotification(context, bot, target.name, targetIdx);
      await Future.delayed(const Duration(milliseconds: 2000));
      gameProvider.resumeReactionTimerAfterNotification();
    }
  }

  static Player? _chooseValetTarget(GameState gs, Player bot, BotDifficulty difficulty) {
    List<Player> opponents = gs.players.where((p) => p.id != bot.id && p.hand.isNotEmpty).toList();
    if (opponents.isEmpty) return null;

    BotBehavior? behavior = bot.botBehavior;

    // CONTRE-ATTAQUE
    Player? counterTarget = BotThreatAnalyzer.getCounterAttackTarget(gs, bot, difficulty);
    if (counterTarget != null) return counterTarget;

    // Bronze : random
    if (difficulty.name == "Bronze") {
      if (_random.nextDouble() < 0.25) {
        return _selectValetTargetWeighted(opponents, difficulty, gs);
      }
      return opponents[_random.nextInt(opponents.length)];
    }

    if (behavior == BotBehavior.fast) {
      opponents.sort((a, b) => b.hand.length.compareTo(a.hand.length));
      return opponents.first;
    }

    if (behavior == BotBehavior.aggressive || behavior == BotBehavior.balanced) {
      Player? human = opponents.where((p) => p.isHuman).firstOrNull;
      if (human != null) {
        double humanBias = _getHumanBias(difficulty, behavior);
        if (_random.nextDouble() < humanBias) return human;
      }
      return _selectValetTargetWeighted(opponents, difficulty, gs);
    }

    return opponents[_random.nextInt(opponents.length)];
  }

  static double _getHumanBias(BotDifficulty difficulty, BotBehavior? behavior) {
    double bias = difficulty.name == "Platine" ? 0.75 :
                  difficulty.name == "Or" ? 0.65 :
                  difficulty.name == "Argent" ? 0.50 : 0.35;
    if (behavior == BotBehavior.balanced) {
      bias = difficulty.name == "Platine" ? 0.70 : 0.60;
    }
    return bias;
  }

  static int _chooseValetTargetCardIndex(Player target, BotDifficulty difficulty, BotBehavior? behavior) {
    if (target.hand.isEmpty) return 0;
    if (target.hand.length == 1) return 0;

    final indices = List<int>.generate(target.hand.length, (i) => i);
    indices.sort((a, b) => target.hand[a].points.compareTo(target.hand[b].points));

    int bestIdx = indices.first;
    int secondIdx = indices.length > 1 ? indices[1] : bestIdx;

    double smartChance = difficulty.name == "Bronze" ? 0.25 :
                        difficulty.name == "Argent" ? 0.50 :
                        difficulty.name == "Or" ? 0.80 : 1.0;

    if (behavior == BotBehavior.aggressive) {
      smartChance += 0.10;
    } else if (behavior == BotBehavior.fast) {
      smartChance -= 0.10;
    }
    if (target.isHuman) {
      smartChance += 0.10;
    }

    smartChance = smartChance.clamp(0.0, 1.0);

    if (_random.nextDouble() < smartChance) return bestIdx;

    double secondChance = difficulty.name == "Bronze" ? 0.35 : 0.55;
    if (_random.nextDouble() < secondChance) return secondIdx;

    return _random.nextInt(target.hand.length);
  }

  static Player _selectValetTargetWeighted(List<Player> opponents, BotDifficulty difficulty, GameState? gameState) {
    Map<Player, double> threatScores = {};
    
    Map<String, double> discardAnalysis = {};
    if (gameState != null && (difficulty.name == "Or" || difficulty.name == "Platine")) {
      discardAnalysis = BotThreatAnalyzer.analyzeDiscardPatterns(gameState, opponents.first, difficulty);
    }
    
    for (var player in opponents) {
      double score = _calculateThreatScore(player, difficulty, gameState, discardAnalysis);
      threatScores[player] = score;
    }
    
    return _selectHighestThreat(opponents, threatScores);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // POUVOIR JOKER : Mélanger la main d'un joueur
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<void> _usePowerJoker(GameState gs, Player bot, BotDifficulty difficulty, BuildContext? context) async {
    Player? target = _chooseJokerTarget(gs, bot, difficulty);
    target ??= bot;

    GameLogic.jokerEffect(gs, target);

    if (target.id == bot.id) {
      bot.resetMentalMap();
    }

    if (target.isHuman && context != null) {
      final gameProvider = Provider.of<GameProvider>(context, listen: false);
      gameProvider.pauseReactionTimerForNotification();
      UnifiedPowerDialogs.showBotJokerNotification(context, bot, target.name);
      await Future.delayed(const Duration(milliseconds: 3000));
      gameProvider.resumeReactionTimerAfterNotification();
    }
  }

  static Player? _chooseJokerTarget(GameState gs, Player bot, BotDifficulty difficulty) {
    BotBehavior? behavior = bot.botBehavior;
    List<Player> possibleTargets = gs.players.where((p) => p.id != bot.id).toList();
    
    if (possibleTargets.isEmpty) return null;

    if (behavior == BotBehavior.fast) {
      possibleTargets.sort((a, b) => a.getEstimatedScore().compareTo(b.getEstimatedScore()));
      return possibleTargets.first;
    }

    if (behavior == BotBehavior.aggressive || behavior == BotBehavior.balanced) {
      Player? human = possibleTargets.where((p) => p.isHuman).firstOrNull;
      if (human != null) {
        double humanBias = _getHumanBias(difficulty, behavior);
        if (behavior == BotBehavior.aggressive) humanBias += 0.05;
        if (_random.nextDouble() < humanBias) return human;
      }
    }

    if (difficulty.name != "Bronze" && _random.nextDouble() < 0.75) {
      return _selectJokerTargetWeighted(possibleTargets, difficulty, gs);
    }

    return possibleTargets[_random.nextInt(possibleTargets.length)];
  }

  static Player _selectJokerTargetWeighted(List<Player> targets, BotDifficulty difficulty, GameState? gameState) {
    Map<Player, double> threatScores = {};
    
    for (var player in targets) {
      double score = 0.0;
      
      if (player.isHuman) {
        score += difficulty.name == "Platine" ? 65.0 :
                difficulty.name == "Or" ? 55.0 :
                difficulty.name == "Argent" ? 40.0 : 25.0;
      }

      int knownCount = BotMemoryManager.countKnownCards(player);
      if (knownCount >= 4) {
        score += 24.0;
      } else if (knownCount >= 2) {
        score += 16.0;
      } else if (knownCount >= 1) {
        score += 8.0;
      }
      
      int cardCount = player.hand.length;
      if (cardCount <= 2) {
        score += 65.0;
      } else if (cardCount == 3) {
        score += 40.0;
      } else if (cardCount == 4) {
        score += 20.0;
      }
      
      int estimatedScore = player.getEstimatedScore();
      if (estimatedScore <= 5) {
        score += 28.0;
      } else if (estimatedScore <= 10) {
        score += 16.0;
      } else if (estimatedScore <= 15) {
        score += 8.0;
      }
      
      if (gameState != null && gameState.gameMode == GameMode.tournament) {
        int cumulativeScore = gameState.getCumulativeScore(player);
        if (cumulativeScore <= 20) {
          score += 20.0;
        } else if (cumulativeScore <= 40) {
          score += 10.0;
        } else if (cumulativeScore >= 80) {
          score -= 15.0;
        }
      }
      
      double randomFactor = _random.nextDouble() * 20.0;
      double randomWeight = difficulty.name == "Or" || difficulty.name == "Platine" ? 0.3 :
                           difficulty.name == "Argent" ? 1.0 : 2.0;
      score += randomFactor * randomWeight;
      
      threatScores[player] = score;
    }
    
    return _selectHighestThreat(targets, threatScores);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  static double _calculateThreatScore(Player player, BotDifficulty difficulty, GameState? gameState, Map<String, double> discardAnalysis) {
    double score = 0.0;
    
    if (discardAnalysis.containsKey(player.id)) {
      score += discardAnalysis[player.id]!;
    }
    
    if (player.isHuman) {
      score += difficulty.name == "Platine" ? 60.0 :
              difficulty.name == "Or" ? 50.0 :
              difficulty.name == "Argent" ? 35.0 : 20.0;
    }
    
    int cardCount = player.hand.length;
    if (cardCount == 1) {
      score += 130.0;
    } else if (cardCount == 2) {
      score += 90.0;
    } else if (cardCount == 3) {
      score += 55.0;
    } else if (cardCount == 4) {
      score += 25.0;
    } else {
      score += 10.0;
    }
    
    int estimatedScore = player.getEstimatedScore();
    if (estimatedScore <= 5) {
      score += 35.0;
    } else if (estimatedScore <= 10) {
      score += 22.0;
    } else if (estimatedScore <= 15) {
      score += 12.0;
    }

    int bestPoints = BotMemoryManager.minPointsInHand(player);
    double pointsMultiplier = difficulty.name == "Platine" ? 4.0 :
                             difficulty.name == "Or" ? 3.0 :
                             difficulty.name == "Argent" ? 2.0 : 1.0;
    score += (13 - bestPoints) * pointsMultiplier;
    
    if (gameState != null && gameState.gameMode == GameMode.tournament) {
      int cumulativeScore = gameState.getCumulativeScore(player);
      if (cumulativeScore <= 20) {
        score += 25.0;
      } else if (cumulativeScore <= 40) {
        score += 15.0;
      } else if (cumulativeScore >= 80) {
        score -= 20.0;
      }
    }
    
    double randomBonus = _random.nextDouble() * 30.0;
    double randomWeight = (difficulty.name == "Or" || difficulty.name == "Platine") ? 0.3 : 1.0;
    score += randomBonus * randomWeight;
    
    return score;
  }

  static Player _selectHighestThreat(List<Player> players, Map<Player, double> threatScores) {
    Player selectedTarget = players.first;
    double maxScore = 0.0;
    
    threatScores.forEach((player, score) {
      if (score > maxScore) {
        maxScore = score;
        selectedTarget = player;
      }
    });
    
    return selectedTarget;
  }
}
