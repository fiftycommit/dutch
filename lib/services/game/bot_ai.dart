import 'package:flutter/material.dart';
import '../../models/game_state.dart';
import '../../models/player.dart';
import 'game_logic.dart';
import 'bot/bot_config.dart';
import 'bot/bot_memory_manager.dart';
import 'bot/bot_dutch_strategy.dart';
import 'bot/bot_card_strategy.dart';
import 'bot/bot_power_handler.dart';
import 'bot/bot_personality.dart';

export 'bot/bot_config.dart' show BotGamePhase, BotBehavior, BotSkillLevel;
export 'bot/bot_difficulty.dart' show BotDifficulty;

/// BotAI refactoré - Orchestrateur léger (~100 lignes au lieu de 1376)
/// Principe GRASP: Controller - Point d'entrée, délègue aux modules spécialisés
/// Principe SOLID: SRP - Coordination uniquement
class BotAI {

  /// Joue le tour d'un bot
  static Future<void> playBotTurn(GameState gameState, {int? playerMMR, BuildContext? context}) async {
    Player bot = gameState.currentPlayer;
    if (bot.isHuman) return;

    final difficulty = BotConfig.getDifficulty(bot, playerMMR);
    final phase = BotConfig.getBotPhase(bot, gameState);
    final personality = BotPersonality.fromBot(bot);

    // Appliquer la décroissance de la mémoire
    BotMemoryManager.applyMemoryDecay(bot, difficulty, personality: personality);

    // Temps de réflexion
    int thinkingTime = BotConfig.getThinkingTime(
      bot.botBehavior,
      difficulty,
      gameState,
      personality: personality,
    );
    await Future.delayed(Duration(milliseconds: thinkingTime));

    // Vérifier si le bot doit appeler Dutch
    if (BotDutchStrategy.shouldCallDutch(
      gameState,
      bot,
      difficulty,
      phase,
      personality: personality,
    )) {
      GameLogic.callDutch(gameState);
      return;
    }

    // Piocher une carte
    GameLogic.drawCard(gameState);

    // Décider quoi faire avec la carte piochée
    final postDrawDelay = personality != null
        ? (personality.decisionSpeedMs * 0.25).round().clamp(50, 300)
        : 200;
    await Future.delayed(Duration(milliseconds: postDrawDelay));
    await BotCardStrategy.decideCardAction(
      gameState,
      bot,
      difficulty,
      phase,
      personality: personality,
    );
  }

  /// Tente un match de réaction pour un bot
  static Future<bool> tryReactionMatch(GameState gameState, Player bot, {int? playerMMR}) async {
    if (gameState.phase != GamePhase.reaction) return false;
    if (bot.isHuman) return false;

    final difficulty = BotConfig.getDifficulty(bot, playerMMR);
    final phase = BotConfig.getBotPhase(bot, gameState);
    final personality = BotPersonality.fromBot(bot);

    return await BotCardStrategy.tryReactionMatch(
      gameState,
      bot,
      difficulty,
      phase,
      personality: personality,
    );
  }

  /// Utilise le pouvoir spécial du bot
  static Future<void> useBotSpecialPower(GameState gameState, {int? playerMMR, BuildContext? context}) async {
    if (!gameState.isWaitingForSpecialPower || gameState.specialCardToActivate == null) return;

    Player bot = gameState.currentPlayer;
    final difficulty = BotConfig.getDifficulty(bot, playerMMR);
    final personality = BotPersonality.fromBot(bot);

    await BotPowerHandler.useBotSpecialPower(
      gameState,
      difficulty,
      context,
      personality: personality,
    );
  }
}
