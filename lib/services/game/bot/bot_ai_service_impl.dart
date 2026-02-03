import 'package:flutter/widgets.dart';
import '../../../core/interfaces/i_bot_ai_service.dart';
import '../../../models/game_state.dart';
import '../../../models/player.dart';
import '../bot_ai.dart';

/// Implémentation concrète du service d'IA des bots
/// Principe SOLID: DIP - Implémente l'interface IBotAIService
/// Principe GRASP: Adapter - Adapte BotAI statique vers une interface injectable
class BotAIServiceImpl implements IBotAIService {
  @override
  Future<void> playBotTurn(
    GameState gameState, {
    int? playerMMR,
    BuildContext? context,
    HardcoreLevel? hardcoreLevel,
    int? playerSkillEstimate,
  }) async {
    await BotAI.playBotTurn(
      gameState,
      playerMMR: playerMMR,
      context: context,
      hardcoreLevel: hardcoreLevel,
      playerSkillEstimate: playerSkillEstimate,
    );
  }

  @override
  Future<bool> tryReactionMatch(
    GameState gameState,
    Player bot, {
    int? playerMMR,
    HardcoreLevel? hardcoreLevel,
    int? playerSkillEstimate,
  }) async {
    return await BotAI.tryReactionMatch(
      gameState,
      bot,
      playerMMR: playerMMR,
      hardcoreLevel: hardcoreLevel,
      playerSkillEstimate: playerSkillEstimate,
    );
  }

  @override
  Future<void> useBotSpecialPower(
    GameState gameState, {
    int? playerMMR,
    BuildContext? context,
    HardcoreLevel? hardcoreLevel,
    int? playerSkillEstimate,
  }) async {
    await BotAI.useBotSpecialPower(
      gameState,
      playerMMR: playerMMR,
      context: context,
      hardcoreLevel: hardcoreLevel,
      playerSkillEstimate: playerSkillEstimate,
    );
  }
}
