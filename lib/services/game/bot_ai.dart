import 'package:flutter/material.dart';
import '../../models/game_state.dart';
import '../../models/player.dart';
import '../logging/game_logger_service.dart';
import 'game_logic.dart';
import 'bot/bot_config.dart';
import 'bot/bot_memory_manager.dart';
import 'bot/bot_dutch_strategy.dart';
import 'bot/bot_card_strategy.dart';
import 'bot/bot_power_handler.dart';
import 'bot/bot_personality.dart';
import 'bot/bot_fair_play_audit.dart';
import 'bot/bot_gossip_service.dart';

export 'bot/bot_config.dart'
    show
        BotGamePhase,
        BotBehavior,
        BotSkillLevel,
        HardcoreLevel,
        HardcoreBotConfig,
        PlayerSkillEstimator;
export 'bot/bot_difficulty.dart' show BotDifficulty;

/// BotAI refactoré - Orchestrateur léger (~100 lignes au lieu de 1376)
/// Principe GRASP: Controller - Point d'entrée, délègue aux modules spécialisés
/// Principe SOLID: SRP - Coordination uniquement
class BotAI {
  /// Joue le tour d'un bot
  ///
  /// [hardcoreLevel] - Si défini, utilise le mode hardcore avec ce niveau
  /// [playerSkillEstimate] - Estimation du skill joueur en temps réel (pour adaptation)
  static Future<void> playBotTurn(
    GameState gameState, {
    int? playerMMR,
    BuildContext? context,
    HardcoreLevel? hardcoreLevel,
    int? playerSkillEstimate,
  }) async {
    Player bot = gameState.currentPlayer;
    if (bot.isHuman) return;

    final difficulty = BotConfig.getDifficulty(
      bot,
      playerMMR,
      hardcoreLevel: hardcoreLevel,
      playerSkillEstimate: playerSkillEstimate,
    );
    final phase = BotConfig.getBotPhase(bot, gameState);
    final personality = BotPersonality.fromBot(bot);

    // LOG : État du bot au début de son tour (ce qu'il sait)
    GameLoggerService.instance.logTurnStart(
      player: bot,
      turnNumber: gameState.turnCount,
      allPlayers: gameState.players,
      gameState: gameState,
    );

    // Hook gossip : observations partagées + alliance + speech éventuel
    BotGossipService.instance.onBotTurn(bot, gameState);

    // Appliquer la décroissance de la mémoire
    BotMemoryManager.applyMemoryDecay(bot, difficulty,
        personality: personality);
    BotFairPlayAudit.auditKnowledgeState(
      gameState,
      bot,
      difficulty,
      stage: 'turn_start',
    );

    // Temps de réflexion (plus court en mode hardcore)
    int thinkingTime;
    if (hardcoreLevel != null) {
      thinkingTime =
          HardcoreBotConfig.getReactionTime(hardcoreLevel, BotConfig.random);
    } else {
      thinkingTime = BotConfig.getThinkingTime(
        bot.botBehavior,
        difficulty,
        gameState,
        personality: personality,
      );
    }
    await Future.delayed(Duration(milliseconds: thinkingTime));

    // Vérifier si le bot doit appeler Dutch
    final shouldCallDutch = BotDutchStrategy.shouldCallDutch(
      gameState,
      bot,
      difficulty,
      phase,
      personality: personality,
    );
    BotFairPlayAudit.auditDutchDecisionBlindness(
      gameState,
      bot,
      difficulty,
      phase,
      shouldCallDutch,
      personality: personality,
    );
    if (shouldCallDutch) {
      BotGossipService.instance.onBotCallsDutch(bot, gameState.turnCount);
      GameLogic.callDutch(gameState);
      return;
    }

    // Piocher une carte
    GameLogic.drawCard(gameState);

    // Décider quoi faire avec la carte piochée
    // En mode hardcore, réduire le délai
    final int postDrawDelay;
    if (hardcoreLevel != null) {
      postDrawDelay =
          HardcoreBotConfig.getReactionTime(hardcoreLevel, BotConfig.random) ~/
              2;
    } else if (personality != null) {
      postDrawDelay =
          (personality.decisionSpeedMs * 0.35).round().clamp(150, 900);
    } else {
      postDrawDelay = 600;
    }
    await Future.delayed(Duration(milliseconds: postDrawDelay));
    await BotCardStrategy.decideCardAction(
      gameState,
      bot,
      difficulty,
      phase,
      personality: personality,
    );
    BotFairPlayAudit.auditKnowledgeState(
      gameState,
      bot,
      difficulty,
      stage: 'after_card_action',
    );
  }

  /// Tente un match de réaction pour un bot
  static Future<bool> tryReactionMatch(
    GameState gameState,
    Player bot, {
    int? playerMMR,
    HardcoreLevel? hardcoreLevel,
    int? playerSkillEstimate,
  }) async {
    if (gameState.phase != GamePhase.reaction) return false;
    if (bot.isHuman) return false;

    final difficulty = BotConfig.getDifficulty(
      bot,
      playerMMR,
      hardcoreLevel: hardcoreLevel,
      playerSkillEstimate: playerSkillEstimate,
    );
    final phase = BotConfig.getBotPhase(bot, gameState);
    final personality = BotPersonality.fromBot(bot);

    BotFairPlayAudit.auditKnowledgeState(
      gameState,
      bot,
      difficulty,
      stage: 'reaction_pre',
    );
    final result = await BotCardStrategy.tryReactionMatch(
      gameState,
      bot,
      difficulty,
      phase,
      personality: personality,
    );
    BotFairPlayAudit.auditKnowledgeState(
      gameState,
      bot,
      difficulty,
      stage: 'reaction_post',
    );
    return result;
  }

  /// Utilise le pouvoir spécial du bot
  static Future<void> useBotSpecialPower(
    GameState gameState, {
    int? playerMMR,
    BuildContext? context,
    HardcoreLevel? hardcoreLevel,
    int? playerSkillEstimate,
  }) async {
    if (gameState.phase != GamePhase.specialPower ||
        gameState.specialCardToActivate == null) {
      return;
    }

    Player bot = gameState.currentPlayer;
    final difficulty = BotConfig.getDifficulty(
      bot,
      playerMMR,
      hardcoreLevel: hardcoreLevel,
      playerSkillEstimate: playerSkillEstimate,
    );
    final personality = BotPersonality.fromBot(bot);
    BotFairPlayAudit.auditKnowledgeState(
      gameState,
      bot,
      difficulty,
      stage: 'power_pre',
    );

    await BotPowerHandler.useBotSpecialPower(
      gameState,
      difficulty,
      context,
      personality: personality,
    );
    BotFairPlayAudit.auditKnowledgeState(
      gameState,
      bot,
      difficulty,
      stage: 'power_post',
    );
  }
}
