import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/game_state.dart';
import '../../models/player.dart';
import '../../models/card.dart';
import '../../models/game_settings.dart';
import 'game_logic.dart';
import 'bot_difficulty.dart';
import '../../widgets/dialogs/special_power_dialogs.dart';
import '../../main.dart';
import 'package:provider/provider.dart';
import '../../providers/game_provider.dart';

enum BotGamePhase {
  exploration,  // DÃÂ©couvrir ses cartes
  optimization, // Optimiser son score
  endgame,      // Rush vers Dutch
}

// enum BotBehavior {
// }

class BotAI {
  static final Random _random = Random();

  static BuildContext? _currentContext;
  
  static BuildContext? get _context {
    return _currentContext ?? navigatorKey.currentContext;
  }

  static BotDifficulty _difficultyFromParameters(Map<String, double> params) {
    double numParam(String key, double fallback) {
      final v = params[key];
      if (v == null) return fallback;
      return v;
    }

    double clamp01(double v) {
      if (v < 0) return 0;
      if (v > 1) return 1;
      return v;
    }

    final memoryAccuracy = clamp01(numParam('memoryAccuracy', 0.7));
    final riskTolerance = clamp01(numParam('riskTolerance', 0.5));
    final powerUsageRate = clamp01(numParam('powerUsageRate', 0.5));
    final caution = clamp01(numParam('caution', 0.5));
    final dutchThreshold = numParam('dutchThreshold', 6.0).round().clamp(0, 30);

    // Mappings (heuristiques) -> BotDifficulty
    final forgetChancePerTurn = (1.0 - memoryAccuracy) * 0.25;
    final confusionOnSwap = (1.0 - memoryAccuracy) * 0.20;
    final reactionSpeed = (0.6 + memoryAccuracy * 0.4).clamp(0.0, 1.0);
    final matchAccuracy = (0.75 + memoryAccuracy * 0.25).clamp(0.0, 1.0);
    final reactionMatchChance = (0.35 + (riskTolerance + powerUsageRate) * 0.3).clamp(0.0, 1.0);

    // keepCardThreshold: plus le bot est prudent, plus il est exigeant
    final keepCardThreshold = (7 - (caution * 6)).round().clamp(0, 7);

    return BotDifficulty(
      name: 'SBMM',
      forgetChancePerTurn: forgetChancePerTurn,
      confusionOnSwap: confusionOnSwap,
      dutchThreshold: dutchThreshold,
      reactionSpeed: reactionSpeed,
      matchAccuracy: matchAccuracy,
      reactionMatchChance: reactionMatchChance,
      keepCardThreshold: keepCardThreshold,
    );
  }

  static BotGamePhase _getBotPhase(Player bot, GameState gameState) {
    int knownCount = bot.knownCardCount;
    int totalCards = bot.hand.length;
    int estimatedScore = bot.getEstimatedScore();
    
    // En tournoi, prendre en compte le score cumule pour passer en endgame plus tot
    if (gameState.gameMode == GameMode.tournament) {
      int cumulativeScore = gameState.getCumulativeScore(bot);
      // Si proche de l'elimination (>= 70 points), etre plus agressif
      if (cumulativeScore >= 70) {
        return BotGamePhase.endgame;
      }
    }
    
    bool someoneClose = gameState.players.any((p) => p.hand.length <= 2);
    if (estimatedScore <= 8 || someoneClose) {
      return BotGamePhase.endgame;
    }
    
    if (knownCount < totalCards) {
      return BotGamePhase.exploration;
    }
    
    return BotGamePhase.optimization;
  }

  static Future<void> playBotTurn(GameState gameState, {int? playerMMR, BuildContext? context}) async {
    _currentContext = context;

    Player bot = gameState.currentPlayer;
    if (bot.isHuman) {
      _currentContext = null;
      return;
    }

    BotDifficulty difficulty = bot.aiParameters != null
        ? _difficultyFromParameters(bot.aiParameters!)
        : (playerMMR != null
            ? BotDifficulty.fromMMR(playerMMR)
            : _getSkillDifficulty(bot.botSkillLevel));

    BotGamePhase phase = _getBotPhase(bot, gameState);

    _applyMemoryDecay(bot, difficulty);

    int thinkingTime = _getThinkingTime(bot.botBehavior, difficulty, gameState);
    await Future.delayed(Duration(milliseconds: thinkingTime));

    if (_shouldCallDutch(gameState, bot, difficulty, phase)) {
      GameLogic.callDutch(gameState);
      _currentContext = null;
      return;
    }
    GameLogic.drawCard(gameState);

    await Future.delayed(const Duration(milliseconds: 1000));
    await _decideCardAction(gameState, bot, difficulty, phase);
    
    _currentContext = null;
  }

  static bool _shouldCallDutch(GameState gs, Player bot, BotDifficulty difficulty, BotGamePhase phase) {
    int estimatedScore = bot.getEstimatedScore();
    BotBehavior? behavior = bot.botBehavior;

    if (phase == BotGamePhase.exploration) {
      return false;
    }

    double audacityBonus = _calculateAudacity(gs, bot, difficulty);

    double confidence = _calculateDutchConfidence(bot);
    
    // En tournoi, ajuster selon le score cumule
    double tournamentPressure = 0.0;
    if (gs.gameMode == GameMode.tournament) {
      int cumulativeScore = gs.getCumulativeScore(bot);
      // Si proche de l'elimination, etre plus agressif pour Dutch
      if (cumulativeScore >= 80) {
        tournamentPressure = 3.0; // Tres urgent
      } else if (cumulativeScore >= 60) {
        tournamentPressure = 2.0;
      } else if (cumulativeScore >= 40) {
        tournamentPressure = 1.0;
      } else if (cumulativeScore <= 20) {
        tournamentPressure = -1.0; // En bonne position, peut etre plus conservateur
      }
    }

    int threshold;

    // NOUVELLE LOGIQUE : Bronze=peureux, Platine=stratégique
    // Platine/Or analysent leur avantage relatif, Bronze attend d'avoir quasi rien
    
    if (difficulty.name == "Platine" || difficulty.name == "Or") {
      // STRATEGIE INTELLIGENTE : Dutch si on a l'avantage
      return _shouldSmartDutch(gs, bot, difficulty, phase, estimatedScore, audacityBonus, confidence, tournamentPressure);
    }
    
    // Bronze/Argent : logique basée sur seuils (Bronze = très peureux)
    if (phase == BotGamePhase.endgame) {
      switch (behavior) {
        case BotBehavior.fast:
          threshold = difficulty.name == "Bronze" ? 3 : 5;  // Bronze très peureux
          break;
        case BotBehavior.aggressive:
          threshold = difficulty.name == "Bronze" ? 2 : 4;
          break;
        case BotBehavior.balanced:
          threshold = difficulty.name == "Bronze" ? 2 : 4;
          break;
        default:
          threshold = difficulty.name == "Bronze" ? 2 : 4;
      }
    } else {
      // En optimization, Bronze encore plus peureux
      switch (behavior) {
        case BotBehavior.fast:
          threshold = difficulty.name == "Bronze" ? 2 : 4;
          break;
        case BotBehavior.aggressive:
          threshold = difficulty.name == "Bronze" ? 1 : 3;
          break;
        case BotBehavior.balanced:
          threshold = difficulty.name == "Bronze" ? 1 : 3;
          break;
        default:
          threshold = difficulty.name == "Bronze" ? 1 : 3;
      }
    }
    
    // Ajouter la pression du tournoi au threshold
    double adjustedThreshold = threshold + audacityBonus + (confidence * 2) + tournamentPressure;
    
    bool shouldDutch = estimatedScore <= adjustedThreshold.round();
    
    if (shouldDutch) {
    }
    
    return shouldDutch;
  }
  
  /// Stratégie intelligente de Dutch pour Or/Platine
  /// Analyse : nombre de cartes, score estimé vs adversaires, défausses récentes
  static bool _shouldSmartDutch(GameState gs, Player bot, BotDifficulty difficulty, 
      BotGamePhase phase, int estimatedScore, double audacityBonus, double confidence, double tournamentPressure) {
    
    // BLUFF : Platine peut faire semblant de ne pas vouloir Dutch
    if (_isBluffingDutch(bot, difficulty, phase)) {
      return false; // Ne Dutch pas même si c'est avantageux (bluff)
    }
    
    int myCardCount = bot.hand.length;
    
    // 1. Analyser l'avantage en nombre de cartes
    int minOpponentCards = 99;
    int maxOpponentCards = 0;
    double avgOpponentScore = 0;
    int opponentCount = 0;
    
    for (var p in gs.players) {
      if (p.id != bot.id) {
        minOpponentCards = min(minOpponentCards, p.hand.length);
        maxOpponentCards = max(maxOpponentCards, p.hand.length);
        avgOpponentScore += p.getEstimatedScore();
        opponentCount++;
      }
    }
    avgOpponentScore = opponentCount > 0 ? avgOpponentScore / opponentCount : 0;
    
    // 2. Avantage en cartes : si j'ai moins de cartes que tout le monde
    bool hasCardAdvantage = myCardCount < minOpponentCards;
    bool hasSignificantCardAdvantage = myCardCount <= minOpponentCards - 2;
    
    // 3. Avantage en score estimé
    bool hasScoreAdvantage = estimatedScore < avgOpponentScore;
    
    // 4. Platine : Dutch agressif si avantage clair
    if (difficulty.name == "Platine") {
      // Avec 1-2 cartes et un bon score, Dutch !
      if (myCardCount <= 2 && estimatedScore <= 6) {
        return true;
      }
      // Avantage significatif en cartes ET bon score
      if (hasSignificantCardAdvantage && estimatedScore <= 10) {
        return true;
      }
      // Avantage en cartes + avantage en score
      if (hasCardAdvantage && hasScoreAdvantage && estimatedScore <= 8) {
        return true;
      }
      // Score très bas, même sans avantage en cartes
      if (estimatedScore <= 4 && myCardCount <= 3) {
        return true;
      }
      // Phase endgame : plus agressif
      if (phase == BotGamePhase.endgame && estimatedScore <= 6) {
        return true;
      }
    }
    
    // 5. Or : un peu moins agressif mais toujours stratégique
    if (difficulty.name == "Or") {
      // Avec 1-2 cartes et un bon score
      if (myCardCount <= 2 && estimatedScore <= 5) {
        return true;
      }
      // Avantage significatif
      if (hasSignificantCardAdvantage && hasScoreAdvantage && estimatedScore <= 8) {
        return true;
      }
      // Score très bas
      if (estimatedScore <= 3 && myCardCount <= 3) {
        return true;
      }
      // Phase endgame
      if (phase == BotGamePhase.endgame && estimatedScore <= 5 && hasCardAdvantage) {
        return true;
      }
    }
    
    // Bonus de pression (tournoi, audace, confiance)
    double totalBonus = audacityBonus + confidence * 2 + tournamentPressure;
    if (totalBonus >= 3 && estimatedScore <= 8) {
      return true;
    }
    
    return false;
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

    // EXPLORATION : Tous les bots (surtout Or/Platine) veulent connaître toutes leurs cartes
    // Ils remplacent une carte inconnue même par une grosse carte pour la découvrir
    // Car grâce à la défausse collective, ils pourront s'en débarrasser ensuite
    List<int> unknownIndices = [];
    for (int i = 0; i < bot.hand.length; i++) {
      if (i >= bot.mentalMap.length || bot.mentalMap[i] == null) {
        unknownIndices.add(i);
      }
    }
    
    // Or/Platine : TOUJOURS remplacer une carte inconnue pour la découvrir
    // Argent : 80% de chance, Bronze : 50% de chance
    double exploreChance = difficulty.name == "Platine" ? 1.0 :
                          difficulty.name == "Or" ? 1.0 :
                          difficulty.name == "Argent" ? 0.80 : 0.50;
    
    if (unknownIndices.isNotEmpty && _random.nextDouble() < exploreChance) {
      replaceIdx = unknownIndices[_random.nextInt(unknownIndices.length)];
      
      bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
      if (!confused) {
        bot.updateMentalMap(replaceIdx, drawn);
      }
      
      GameLogic.replaceCard(gs, replaceIdx);
      return;
    }
    
    // Si on n'explore pas, continuer avec la logique d'optimization

    int keepThreshold = difficulty.keepCardThreshold;
    
    // Ajuster selon le comportement
    BotBehavior? behavior = bot.botBehavior;
    switch (behavior) {
      case BotBehavior.fast:
        keepThreshold = difficulty.name == "Platine" ? 8 :
                       difficulty.name == "Or" ? 9 :
                       difficulty.name == "Argent" ? 10 : 10;
        break;
      case BotBehavior.aggressive:
        keepThreshold += 2;
        break;
      case BotBehavior.balanced:
        if (phase == BotGamePhase.endgame) {
          keepThreshold = (5 + difficulty.keepCardThreshold) ~/ 2;
        } else {
          keepThreshold = difficulty.keepCardThreshold;
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
    
    // Augmenter la motivation a matcher si le bot a beaucoup de cartes (il veut en avoir moins)
    if (bot.hand.length >= 5) {
      matchChance += 0.15; // Plus motive a defausser
    } else if (bot.hand.length >= 4) {
      matchChance += 0.10;
    }
    
    // FAST veut toujours matcher pour réduire ses cartes
    if (bot.botBehavior == BotBehavior.fast) {
      matchChance = 1.0; // 100% de chance de tenter un match
    }
    else if (bot.botBehavior == BotBehavior.balanced && phase == BotGamePhase.endgame) {
      matchChance = (matchChance + 1.0) / 2; // Moyenne entre base et 100%
    }
    
    // En tournoi, si proche de l'elimination, etre plus agressif pour matcher
    if (gameState.gameMode == GameMode.tournament) {
      int cumulativeScore = gameState.getCumulativeScore(bot);
      if (cumulativeScore >= 70) {
        matchChance += 0.20; // Plus motive si proche de l'elimination
      }
    }
    
    matchChance = matchChance.clamp(0.0, 1.0);

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

    // Match à l'aveugle : les bots Or/Platine tentent de matcher même des cartes inconnues
    if (difficulty.name == "Or" || difficulty.name == "Platine") {
      // Or : 50% de chance de tenter, Platine : 80% de chance
      double blindMatchChance = difficulty.name == "Platine" ? 0.80 : 0.50;
      if (_random.nextDouble() < blindMatchChance) {
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
            if (success) {
              // Mise à jour de la mental map après un match réussi
              if (blindIndex < bot.mentalMap.length) {
                bot.mentalMap.removeAt(blindIndex);
              }
            }
            return success;
          }
        }
      }
    }

    return false;
  }

  
  static Future<void> useBotSpecialPower(GameState gameState, {int? playerMMR, BuildContext? context}) async {
    if (!gameState.isWaitingForSpecialPower || gameState.specialCardToActivate == null) return;
    
    _currentContext = context;

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
        
        // Notification si le bot espionne le joueur humain
        if (target.isHuman && _context != null) {
          final gameProvider = Provider.of<GameProvider>(_context!, listen: false);
          gameProvider.pauseReactionTimerForNotification();

          SpecialPowerDialogs.showBotSpyNotification(_context!, bot, target.name, idx);
          await Future.delayed(const Duration(milliseconds: 2000));

          gameProvider.resumeReactionTimerAfterNotification();
        }
      }
    } else if (val == 'V') {
      await _executeValetStrategy(gameState, bot, difficulty);
    } else if (val == 'JOKER') {
      await _executeJokerStrategy(gameState, bot, difficulty);
    }

    gameState.isWaitingForSpecialPower = false;
    gameState.specialCardToActivate = null;
    gameState.addToHistory("${bot.name} a utilisÃÂ© son pouvoir.");
    
    _currentContext = null;
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
    int targetIdx = _chooseValetTargetCardIndex(target, difficulty, behavior);

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

    // CONTRE-ATTAQUE : Si quelqu'un est proche de gagner, le cibler en priorité
    Player? counterTarget = _getCounterAttackTarget(gs, bot, difficulty);
    if (counterTarget != null) {
      return counterTarget;
    }

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

    if (behavior == BotBehavior.aggressive) {
      Player? human = opponents.where((p) => p.isHuman).firstOrNull;
      if (human != null) {
        // Ciblage stratégique mais pas systématique pour éviter la frustration
        double humanBias;
        if (difficulty.name == "Platine") {
          humanBias = 0.75; // Cible souvent l'humain mais pas toujours
        } else if (difficulty.name == "Or") {
          humanBias = 0.65;
        } else if (difficulty.name == "Argent") {
          humanBias = 0.50;
        } else {
          humanBias = 0.35;
        }
        if (_random.nextDouble() < humanBias) {
          return human;
        }
      }
      
      List<Player> lowCardTargets = opponents.where((p) => p.hand.length <= 3).toList();
      if (lowCardTargets.isNotEmpty && _random.nextDouble() < 0.70) {
        return lowCardTargets[_random.nextInt(lowCardTargets.length)];
      }
      return _selectValetTargetWeighted(opponents, difficulty, gs);
    }

    if (behavior == BotBehavior.balanced) {
      // Bronze/Argent : simple weighted
      if (difficulty.name == "Bronze" || difficulty.name == "Argent") {
        if (_random.nextDouble() < 0.80) {
          return _selectValetTargetWeighted(opponents, difficulty, gs);
        }
        return opponents[_random.nextInt(opponents.length)];
      }
      
      // Or/Platine : Ciblage stratégique de l'humain mais avec variabilité
      Player? human = opponents.where((p) => p.isHuman).firstOrNull;
      if (human != null) {
        double humanBias = difficulty.name == "Platine" ? 0.70 : 0.60;
        if (_random.nextDouble() < humanBias) {
          return human;
        }
      }
      // Sinon cible weighted (peut cibler un autre bot dangereux)
      return _selectValetTargetWeighted(opponents, difficulty, gs);
    }

    // Fallback
    return opponents[_random.nextInt(opponents.length)];
  }

  static int _chooseValetTargetCardIndex(
      Player target, BotDifficulty difficulty, BotBehavior? behavior) {
    if (target.hand.isEmpty) return 0;
    if (target.hand.length == 1) return 0;

    final indices = List<int>.generate(target.hand.length, (i) => i);
    indices.sort((a, b) => target.hand[a].points.compareTo(target.hand[b].points));

    int bestIdx = indices.first;
    int secondIdx = indices.length > 1 ? indices[1] : bestIdx;

    double smartChance;
    if (difficulty.name == "Bronze") {
      smartChance = 0.25;
    } else if (difficulty.name == "Argent") {
      smartChance = 0.50;
    } else if (difficulty.name == "Or") {
      smartChance = 0.80;
    } else {
      smartChance = 1.0;
    }

    if (behavior == BotBehavior.aggressive) {
      smartChance += 0.10;
    } else if (behavior == BotBehavior.fast) {
      smartChance -= 0.10;
    }

    if (target.isHuman) {
      smartChance += 0.10;
    }

    smartChance = smartChance.clamp(0.0, 1.0).toDouble();

    if (_random.nextDouble() < smartChance) {
      return bestIdx;
    }

    double secondChance = difficulty.name == "Bronze" ? 0.35 : 0.55;
    if (_random.nextDouble() < secondChance) {
      return secondIdx;
    }

    return _random.nextInt(target.hand.length);
  }

  static Player _selectValetTargetWeighted(List<Player> opponents, BotDifficulty difficulty, GameState? gameState) {
    Map<Player, double> threatScores = {};
    
    // ANALYSE DES DÉFAUSSES : Or/Platine utilisent l'analyse avancée
    Map<String, double> discardAnalysis = {};
    if (gameState != null && (difficulty.name == "Or" || difficulty.name == "Platine")) {
      // Créer un bot fictif pour l'analyse (on utilise le premier opponent comme référence)
      discardAnalysis = _analyzeDiscardPatterns(gameState, opponents.first, difficulty);
    }
    
    for (var player in opponents) {
      double score = 0.0;
      
      // Ajouter le score d'analyse des défausses si disponible
      if (discardAnalysis.containsKey(player.id)) {
        score += discardAnalysis[player.id]!;
      }
      
      if (player.isHuman) {
        if (difficulty.name == "Platine") {
          score += 60.0;
        } else if (difficulty.name == "Or") {
          score += 50.0;
        } else if (difficulty.name == "Argent") {
          score += 35.0;
        } else {
          score += 20.0;
        }
      }
      
      // Priorite aux joueurs avec peu de cartes (ils sont proches de Dutch)
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

      int bestPoints = _minPointsInHand(player);
      if (difficulty.name == "Platine") {
        score += (13 - bestPoints) * 4.0;
      } else if (difficulty.name == "Or") {
        score += (13 - bestPoints) * 3.0;
      } else if (difficulty.name == "Argent") {
        score += (13 - bestPoints) * 2.0;
      } else {
        score += (13 - bestPoints) * 1.0;
      }
      
      // En tournoi, cibler davantage les joueurs avec un bon score cumule
      if (gameState != null && gameState.gameMode == GameMode.tournament) {
        int cumulativeScore = gameState.getCumulativeScore(player);
        // Un joueur avec un faible score cumule est plus dangereux
        if (cumulativeScore <= 20) {
          score += 25.0; // Il est en bonne position
        } else if (cumulativeScore <= 40) {
          score += 15.0;
        } else if (cumulativeScore >= 80) {
          score -= 20.0; // Moins prioritaire, il risque l'elimination
        }
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
      
      if (human != null) {
        // Ciblage stratégique mais pas systématique
        double humanBias;
        if (difficulty.name == "Platine") {
          humanBias = 0.80; // Cible souvent l'humain mais le laisse respirer
        } else if (difficulty.name == "Or") {
          humanBias = 0.70;
        } else if (difficulty.name == "Argent") {
          humanBias = 0.55;
        } else {
          humanBias = 0.40;
        }
        if (_random.nextDouble() < humanBias) {
          target = human;
        }
      }
      
      if (target == null) {
        if (difficulty.name != "Bronze" && _random.nextDouble() < 0.75) {
          target = _selectJokerTargetWeighted(possibleTargets, difficulty, gs);
        } else {
          target = possibleTargets[_random.nextInt(possibleTargets.length)];
        }
      }
    }
    else if (behavior == BotBehavior.balanced) {
      // Bronze/Argent : simple weighted
      if (difficulty.name == "Bronze" || difficulty.name == "Argent") {
        if (difficulty.name == "Bronze") {
          if (_random.nextDouble() < 0.25) {
            target = _selectJokerTargetWeighted(possibleTargets, difficulty, gs);
          } else {
            target = possibleTargets[_random.nextInt(possibleTargets.length)];
          }
        } else {
          target = _selectJokerTargetWeighted(possibleTargets, difficulty, gs);
        }
      }
      // Or/Platine : Ciblage stratégique mais avec variabilité
      else {
        Player? human = possibleTargets.where((p) => p.isHuman).firstOrNull;
        if (human != null) {
          double humanBias = difficulty.name == "Platine" ? 0.75 : 0.65;
          if (_random.nextDouble() < humanBias) {
            target = human;
          }
        }
        target ??= _selectJokerTargetWeighted(possibleTargets, difficulty, gs);
      }
    }
    // Fallback
    else {
      if (difficulty.name != "Bronze" && _random.nextDouble() < 0.3) {
        target = _selectJokerTargetWeighted(possibleTargets, difficulty, gs);
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

  static Player _selectJokerTargetWeighted(List<Player> targets, BotDifficulty difficulty, GameState? gameState) {
    Map<Player, double> threatScores = {};
    
    for (var player in targets) {
      double score = 0.0;
      
      if (player.isHuman) {
        if (difficulty.name == "Platine") {
          score += 65.0;
        } else if (difficulty.name == "Or") {
          score += 55.0;
        } else if (difficulty.name == "Argent") {
          score += 40.0;
        } else {
          score += 25.0;
        }
      }

      int knownCount = _countKnownCards(player);
      if (knownCount >= 4) {
        score += 24.0;
      } else if (knownCount >= 2) {
        score += 16.0;
      } else if (knownCount >= 1) {
        score += 8.0;
      }
      
      // Priorite aux joueurs avec peu de cartes (Joker detruit leur memoire)
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
      
      // En tournoi, cibler davantage les joueurs avec un bon score cumule
      if (gameState != null && gameState.gameMode == GameMode.tournament) {
        int cumulativeScore = gameState.getCumulativeScore(player);
        // Un joueur avec un faible score cumule est plus dangereux
        if (cumulativeScore <= 20) {
          score += 20.0; // Il est en bonne position
        } else if (cumulativeScore <= 40) {
          score += 10.0;
        } else if (cumulativeScore >= 80) {
          score -= 15.0; // Moins prioritaire, il risque l'elimination
        }
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

  static int _minPointsInHand(Player player) {
    if (player.hand.isEmpty) return 0;
    int minPoints = player.hand.first.points;
    for (int i = 1; i < player.hand.length; i++) {
      int points = player.hand[i].points;
      if (points < minPoints) {
        minPoints = points;
      }
    }
    return minPoints;
  }

  static int _countKnownCards(Player player) {
    int count = 0;
    for (final known in player.knownCards) {
      if (known) count++;
    }
    return count;
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
      case BotSkillLevel.platinum:
        return BotDifficulty.platinum;
    }
  }

  // ========== NOUVELLES FONCTIONNALITÉS AVANCÉES ==========

  /// Détecte le joueur le plus menaçant (proche de gagner)
  static Player? _getMostThreateningPlayer(GameState gs, Player bot) {
    Player? mostThreatening;
    int lowestCards = 99;
    int lowestScore = 999;
    
    for (var p in gs.players) {
      if (p.id == bot.id) continue;
      
      // Priorité : moins de cartes = plus menaçant
      if (p.hand.length < lowestCards || 
          (p.hand.length == lowestCards && p.getEstimatedScore() < lowestScore)) {
        lowestCards = p.hand.length;
        lowestScore = p.getEstimatedScore();
        mostThreatening = p;
      }
    }
    
    // Retourner seulement si vraiment menaçant (3 cartes ou moins)
    if (mostThreatening != null && lowestCards <= 3) {
      return mostThreatening;
    }
    return null;
  }

  /// Vérifie si le bot devrait contre-attaquer (cibler le joueur menaçant)
  static bool _shouldCounterAttack(GameState gs, Player bot, BotDifficulty difficulty) {
    Player? threat = _getMostThreateningPlayer(gs, bot);
    if (threat == null) return false;
    
    // Plus le bot est intelligent, plus il contre-attaque
    double counterChance = difficulty.name == "Platine" ? 0.90 :
                          difficulty.name == "Or" ? 0.80 :
                          difficulty.name == "Argent" ? 0.60 : 0.30;
    
    // Si l'humain est menaçant, augmenter la chance
    if (threat.isHuman) {
      counterChance += 0.10;
    }
    
    return _random.nextDouble() < counterChance;
  }

  /// Analyse les défausses récentes pour estimer les mains adverses
  /// Retourne un score de "danger" pour chaque joueur
  static Map<String, double> _analyzeDiscardPatterns(GameState gs, Player bot, BotDifficulty difficulty) {
    Map<String, double> dangerScores = {};
    
    // Seulement Or/Platine font cette analyse
    if (difficulty.name != "Or" && difficulty.name != "Platine") {
      return dangerScores;
    }
    
    // Analyser les dernières cartes défaussées (si disponible dans l'historique)
    // Plus un joueur défausse des grosses cartes, plus sa main est probablement bonne
    for (var p in gs.players) {
      if (p.id == bot.id) continue;
      
      double danger = 0.0;
      
      // Moins de cartes = plus dangereux
      danger += (5 - p.hand.length) * 15.0;
      
      // Score estimé bas = dangereux
      int estimatedScore = p.getEstimatedScore();
      if (estimatedScore <= 5) {
        danger += 40.0;
      } else if (estimatedScore <= 10) {
        danger += 25.0;
      } else if (estimatedScore <= 15) {
        danger += 10.0;
      }
      
      // Humain = toujours un peu plus dangereux (imprévisible)
      if (p.isHuman) {
        danger += 20.0;
      }
      
      dangerScores[p.id] = danger;
    }
    
    return dangerScores;
  }

  /// Détermine si les bots devraient coordonner une attaque contre l'humain
  static bool _shouldCoordinateAttack(GameState gs, Player bot, BotDifficulty difficulty) {
    // Seulement Or/Platine coordonnent
    if (difficulty.name != "Or" && difficulty.name != "Platine") {
      return false;
    }
    
    // Trouver l'humain
    Player? human;
    try {
      human = gs.players.firstWhere((p) => p.isHuman);
    } catch (e) {
      return false;
    }
    
    // Si l'humain est proche de gagner, coordonner
    if (human.hand.length <= 3) {
      double coordChance = difficulty.name == "Platine" ? 0.85 : 0.70;
      return _random.nextDouble() < coordChance;
    }
    
    // Si l'humain a un bon score estimé
    if (human.getEstimatedScore() <= 8) {
      double coordChance = difficulty.name == "Platine" ? 0.70 : 0.55;
      return _random.nextDouble() < coordChance;
    }
    
    return false;
  }

  /// Simule un "bluff" : le bot fait semblant de vouloir Dutch
  /// En réduisant rapidement ses cartes puis en changeant de stratégie
  static bool _isBluffingDutch(Player bot, BotDifficulty difficulty, BotGamePhase phase) {
    // Seulement Platine bluffe, et seulement en phase optimization
    if (difficulty.name != "Platine" || phase != BotGamePhase.optimization) {
      return false;
    }
    
    // 20% de chance de bluffer si le bot a 3-4 cartes
    if (bot.hand.length >= 3 && bot.hand.length <= 4) {
      return _random.nextDouble() < 0.20;
    }
    
    return false;
  }

  /// Cible prioritaire pour contre-attaque avec Valet
  static Player? _getCounterAttackTarget(GameState gs, Player bot, BotDifficulty difficulty) {
    if (!_shouldCounterAttack(gs, bot, difficulty)) {
      return null;
    }
    
    Player? threat = _getMostThreateningPlayer(gs, bot);
    
    // Si coordination activée et l'humain n'est pas la menace principale,
    // cibler quand même l'humain parfois
    if (_shouldCoordinateAttack(gs, bot, difficulty)) {
      try {
        Player human = gs.players.firstWhere((p) => p.isHuman);
        if (threat == null || !threat.isHuman) {
          // 60% de chance de cibler l'humain même s'il n'est pas la menace principale
          if (_random.nextDouble() < 0.60) {
            return human;
          }
        }
      } catch (e) {
        // Pas d'humain
      }
    }
    
    return threat;
  }

}
