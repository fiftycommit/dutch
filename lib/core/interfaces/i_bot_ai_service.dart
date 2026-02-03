import 'package:flutter/widgets.dart';
import '../../models/game_state.dart';
import '../../models/player.dart';
import '../../services/game/bot/hardcore_bot_config.dart';

/// Interface abstraite pour le service d'IA des bots
/// Principe SOLID: DIP - Dépendance sur une abstraction
/// Principe SOLID: ISP - Interface dédiée à l'IA des bots
abstract class IBotAIService {
  /// Jouer le tour d'un bot
  /// 
  /// [hardcoreLevel] - Si défini, utilise le mode hardcore
  /// [playerSkillEstimate] - Estimation du skill joueur pour adaptation
  Future<void> playBotTurn(
    GameState gameState, {
    int? playerMMR,
    BuildContext? context,
    HardcoreLevel? hardcoreLevel,
    int? playerSkillEstimate,
  });

  /// Tenter un match pendant la phase de réaction
  Future<bool> tryReactionMatch(
    GameState gameState,
    Player bot, {
    int? playerMMR,
    HardcoreLevel? hardcoreLevel,
    int? playerSkillEstimate,
  });

  /// Utiliser un pouvoir spécial de bot
  Future<void> useBotSpecialPower(
    GameState gameState, {
    int? playerMMR,
    BuildContext? context,
    HardcoreLevel? hardcoreLevel,
    int? playerSkillEstimate,
  });
}
