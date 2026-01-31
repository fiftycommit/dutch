import 'package:flutter/widgets.dart';
import '../../models/game_state.dart';
import '../../models/player.dart';

/// Interface abstraite pour le service d'IA des bots
/// Principe SOLID: DIP - Dépendance sur une abstraction
/// Principe SOLID: ISP - Interface dédiée à l'IA des bots
abstract class IBotAIService {
  /// Jouer le tour d'un bot
  Future<void> playBotTurn(
    GameState gameState, {
    int? playerMMR,
    BuildContext? context,
  });

  /// Tenter un match pendant la phase de réaction
  Future<bool> tryReactionMatch(
    GameState gameState,
    Player bot, {
    int? playerMMR,
  });

  /// Utiliser un pouvoir spécial de bot
  Future<void> useBotSpecialPower(
    GameState gameState, {
    int? playerMMR,
    BuildContext? context,
  });
}
