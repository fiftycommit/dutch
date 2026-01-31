import 'dart:math';
import '../../../models/game_state.dart';
import '../../../models/player.dart';
import '../../../models/playing_card.dart';
import 'bot_difficulty.dart';
import '../game_logic.dart';
import 'bot_config.dart';
import 'bot_memory_manager.dart';
import 'bot_personality.dart';

/// Stratégie de gestion des cartes
/// Principe GRASP: Information Expert - Décide quoi faire avec les cartes
class BotCardStrategy {
  static final Random _random = Random();

  /// Décide quoi faire avec la carte piochée
  static Future<void> decideCardAction(
    GameState gs,
    Player bot,
    BotDifficulty difficulty,
    BotGamePhase phase, {
    BotPersonality? personality,
  }) async {

    PlayingCard? drawn = gs.drawnCard;
    if (drawn == null) return;

    int drawnVal = drawn.points;
    int replaceIdx = -1;

    // EXPLORATION : Remplacer une carte inconnue pour la découvrir
    List<int> unknownIndices = BotMemoryManager.getUnknownIndices(bot);
    
    double exploreChance = difficulty.name == "Platine" ? 1.0 :
                          difficulty.name == "Or" ? 1.0 :
                          difficulty.name == "Argent" ? 0.80 : 0.50;

    if (personality != null) {
      final style = (personality.aggressiveness - personality.caution).clamp(-1.0, 1.0);
      exploreChance += style * 0.15;
      exploreChance -= (personality.memoryAccuracy - 0.7) * 0.2;
      exploreChance = exploreChance.clamp(0.2, 1.0);
    }
    
    if (unknownIndices.isNotEmpty && _random.nextDouble() < exploreChance) {
      replaceIdx = unknownIndices[_random.nextInt(unknownIndices.length)];
      
      bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
      if (!confused) {
        bot.updateMentalMap(replaceIdx, drawn);
      }
      
      GameLogic.replaceCard(gs, replaceIdx);
      return;
    }
    
    // OPTIMIZATION : Chercher à améliorer le score
    int keepThreshold = _getKeepThreshold(
      bot.botBehavior,
      difficulty,
      phase,
      personality: personality,
    );

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

    bool isBadDraw = false;
    
    if (replaceIdx != -1 && drawnVal <= keepThreshold) {
      _replaceCard(gs, bot, replaceIdx, drawn, difficulty);
      bot.consecutiveBadDraws = 0;
    } else if (replaceIdx != -1 && worstKnownValue > drawnVal + 3) {
      _replaceCard(gs, bot, replaceIdx, drawn, difficulty);
      bot.consecutiveBadDraws = 0;
    } else {
      GameLogic.discardDrawnCard(gs);
      isBadDraw = true;
    }
    
    if (isBadDraw) {
      bot.consecutiveBadDraws++;
    }
  }

  static int _getKeepThreshold(
    BotBehavior? behavior,
    BotDifficulty difficulty,
    BotGamePhase phase, {
    BotPersonality? personality,
  }) {
    int keepThreshold = difficulty.keepCardThreshold;
    
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

    if (personality != null) {
      final style = (personality.aggressiveness - personality.caution).clamp(-1.0, 1.0);
      keepThreshold += (style * 3).round();
      keepThreshold = keepThreshold.clamp(2, 12);
    }

    return keepThreshold;
  }

  static void _replaceCard(GameState gs, Player bot, int replaceIdx, PlayingCard drawn, BotDifficulty difficulty) {
    bool confused = _random.nextDouble() < difficulty.confusionOnSwap;
    if (!confused) {
      bot.updateMentalMap(replaceIdx, drawn);
    }
    GameLogic.replaceCard(gs, replaceIdx);
  }

  /// Tente un match de réaction
  static Future<bool> tryReactionMatch(
    GameState gameState,
    Player bot,
    BotDifficulty difficulty,
    BotGamePhase phase, {
    BotPersonality? personality,
  }) async {
    if (gameState.phase != GamePhase.reaction) return false;
    if (bot.isHuman) return false;
    if (gameState.discardPile.isEmpty) return false;

    double matchChance = _getMatchChance(
      bot,
      difficulty,
      phase,
      gameState,
      personality: personality,
    );

    if (_random.nextDouble() > matchChance) return false;

    PlayingCard topDiscard = gameState.discardPile.last;
    
    // Chercher une carte qui match dans la main du bot
    for (int i = 0; i < bot.hand.length; i++) {
      if (i < bot.mentalMap.length && bot.mentalMap[i] != null) {
        PlayingCard knownCard = bot.mentalMap[i]!;
        
        if (knownCard.matches(topDiscard)) {
          if (_random.nextDouble() < difficulty.matchAccuracy) {
            int reactionDelay = (380 * (1 - difficulty.reactionSpeed)).round() + 120;
            if (personality != null) {
              reactionDelay =
                  (reactionDelay * (personality.decisionSpeedMs / 2000.0))
                      .round()
                      .clamp(120, 900);
            }
            await Future.delayed(Duration(milliseconds: reactionDelay));
            
            bool success = GameLogic.matchCard(gameState, bot, i);
            
            if (success && i < bot.mentalMap.length) {
              bot.mentalMap.removeAt(i);
            }
            return success;
          }
        }
      }
    }

    // Match à l'aveugle pour Or/Platine
    if (difficulty.name == "Or" || difficulty.name == "Platine") {
      return await _tryBlindMatch(
        gameState,
        bot,
        difficulty,
        topDiscard,
        personality: personality,
      );
    }

    return false;
  }

  static double _getMatchChance(
    Player bot,
    BotDifficulty difficulty,
    BotGamePhase phase,
    GameState gameState, {
    BotPersonality? personality,
  }) {
    double matchChance = difficulty.reactionMatchChance;
    
    if (bot.hand.length >= 5) {
      matchChance += 0.15;
    } else if (bot.hand.length >= 4) {
      matchChance += 0.10;
    }
    
    if (bot.botBehavior == BotBehavior.fast) {
      matchChance = 1.0;
    } else if (bot.botBehavior == BotBehavior.balanced && phase == BotGamePhase.endgame) {
      matchChance = (matchChance + 1.0) / 2;
    }
    
    if (gameState.gameMode == GameMode.tournament) {
      int cumulativeScore = gameState.getCumulativeScore(bot);
      if (cumulativeScore >= 70) matchChance += 0.20;
    }

    if (personality != null) {
      matchChance += (personality.riskTolerance - 0.5) * 0.2;
    }
    
    return matchChance.clamp(0.0, 1.0);
  }

  static Future<bool> _tryBlindMatch(
    GameState gameState,
    Player bot,
    BotDifficulty difficulty,
    PlayingCard topDiscard, {
    BotPersonality? personality,
  }) async {
    double blindMatchChance = difficulty.name == "Platine" ? 0.80 : 0.50;
    if (personality != null) {
      blindMatchChance += (personality.riskTolerance - 0.5) * 0.25;
      blindMatchChance = blindMatchChance.clamp(0.1, 0.95);
    }
    if (_random.nextDouble() >= blindMatchChance) return false;

    List<int> unknownIndices = BotMemoryManager.getUnknownIndices(bot);
    
    if (unknownIndices.isEmpty) return false;

    int blindIndex = unknownIndices[_random.nextInt(unknownIndices.length)];
    PlayingCard blindCard = bot.hand[blindIndex];
    
    if (blindCard.matches(topDiscard)) {
      int reactionDelay = (320 * (1 - difficulty.reactionSpeed)).round() + 120;
      if (personality != null) {
        reactionDelay =
            (reactionDelay * (personality.decisionSpeedMs / 2000.0))
                .round()
                .clamp(120, 850);
      }
      await Future.delayed(Duration(milliseconds: reactionDelay));
      
      bool success = GameLogic.matchCard(gameState, bot, blindIndex);
      if (success && blindIndex < bot.mentalMap.length) {
        bot.mentalMap.removeAt(blindIndex);
      }
      return success;
    }
    
    return false;
  }
}
