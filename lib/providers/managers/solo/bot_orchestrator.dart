import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../../../models/playing_card.dart';
import '../../../models/game_state.dart';
import '../../../models/player.dart';
import '../../../core/interfaces/i_bot_ai_service.dart';
import '../../../services/game/bot/bot_config.dart';
import '../../../services/game/bot/bot_difficulty.dart';

/// Orchestrateur dédié à la gestion des actions des bots
/// Principe GRASP: Pure Fabrication - Responsabilité unique d'orchestration des bots
/// Principe SOLID: SRP - Ne gère que les actions des bots
class BotOrchestrator {
  final IBotAIService _botAIService;

  BotOrchestrator({
    required IBotAIService botAIService,
  }) : _botAIService = botAIService;

  /// Vérifier si un bot doit jouer
  bool shouldBotPlay(GameState? gameState, bool isProcessing, bool isPaused) {
    if (gameState == null) return false;
    if (isProcessing) return false;
    if (gameState.phase != GamePhase.playing) return false;
    if (gameState.currentPlayer.isHuman) return false;
    if (isPaused) return false;
    return true;
  }

  /// Simuler la réaction des bots pendant la phase de réaction
  Future<bool> simulateBotReaction(
    GameState gameState,
    int? playerMMR,
    bool isPaused, {
    HardcoreLevel? hardcoreLevel,
    int? playerSkillEstimate,
  }) async {
    if (gameState.phase != GamePhase.reaction) return false;
    if (isPaused) return false;

    PlayingCard? topCard = gameState.topDiscardCard;
    if (topCard == null) return false;

    final reactionBots =
        gameState.players.where((p) => !p.isHuman).toList(growable: false);
    if (reactionBots.isEmpty) return false;

    final difficulties = <String, BotDifficulty>{};
    for (final bot in reactionBots) {
      difficulties[bot.id] = BotConfig.getDifficulty(
        bot,
        playerMMR,
        hardcoreLevel: hardcoreLevel,
        playerSkillEstimate: playerSkillEstimate,
      );
    }

    final rng = Random();
    final initiatives = <String, double>{};
    for (final bot in reactionBots) {
      final difficulty = difficulties[bot.id]!;
      initiatives[bot.id] = _reactionInitiative(difficulty, rng);
    }

    final orderedBots = List<Player>.from(reactionBots)
      ..sort(
          (a, b) => (initiatives[b.id] ?? 0).compareTo(initiatives[a.id] ?? 0));

    for (var bot in orderedBots) {
      if (gameState.phase != GamePhase.reaction) return false;
      if (isPaused) return false;

      final difficulty = difficulties[bot.id]!;
      final delay = _reactionDelayMs(difficulty, hardcoreLevel, rng);
      await Future.delayed(Duration(milliseconds: delay));

      if (gameState.phase != GamePhase.reaction) return false;

      bool matched = await _botAIService.tryReactionMatch(
        gameState,
        bot,
        playerMMR: playerMMR,
        hardcoreLevel: hardcoreLevel,
        playerSkillEstimate: playerSkillEstimate,
      );

      if (matched) {
        return true; // Un bot a matché
      }
    }

    return false; // Aucun bot n'a matché
  }

  double _reactionInitiative(BotDifficulty difficulty, Random rng) {
    // Combine vitesse de réaction et propension à matcher.
    // Un léger jitter évite un ordre strictement identique à chaque tour.
    return difficulty.reactionSpeed * 0.70 +
        difficulty.reactionMatchChance * 0.25 +
        difficulty.matchAccuracy * 0.05 +
        (rng.nextDouble() * 0.05);
  }

  int _reactionDelayMs(
    BotDifficulty difficulty,
    HardcoreLevel? hardcoreLevel,
    Random rng,
  ) {
    if (hardcoreLevel != null) {
      return (HardcoreBotConfig.getReactionTime(hardcoreLevel, rng) ~/ 4)
          .clamp(15, 120);
    }

    final speedPenalty = ((1 - difficulty.reactionSpeed) * 180).round();
    return 20 + speedPenalty + rng.nextInt(50);
  }

  /// Jouer le tour d'un bot (boucle complète)
  Future<void> playBotTurn(
    GameState gameState,
    int? playerMMR,
    bool isPaused,
    BuildContext? context,
    Function onCheckInstantEnd, {
    HardcoreLevel? hardcoreLevel,
    int? playerSkillEstimate,
    VoidCallback? onStateChanged,
  }) async {
    int loopCount = 0;

    while (!gameState.currentPlayer.isHuman &&
        gameState.phase == GamePhase.playing &&
        !isPaused) {
      loopCount++;

      if (loopCount > 10) break;
      if (isPaused) break;

      // Vérifier si la partie est terminée
      final shouldEnd = await onCheckInstantEnd();
      if (shouldEnd) return;

      // Attendre un peu avant que le bot joue (moins en hardcore)
      if (!isPaused) {
        final waitTime = hardcoreLevel != null ? 80 : 150;
        await Future.delayed(Duration(milliseconds: waitTime));
      }
      if (isPaused) break;

      try {
        if (isPaused) break;

        await _botAIService.playBotTurn(
          gameState,
          playerMMR: playerMMR,
          context: context,
          hardcoreLevel: hardcoreLevel,
          playerSkillEstimate: playerSkillEstimate,
        );
        onStateChanged?.call();

        if (isPaused) break;

        if (gameState.phase == GamePhase.dutchCalled) {
          return; // Le bot a appelé Dutch
        }

        if (gameState.isWaitingForSpecialPower) {
          // Attendre avant d'utiliser le pouvoir (moins en hardcore)
          if (!isPaused) {
            final powerWait = hardcoreLevel != null ? 100 : 180;
            await Future.delayed(Duration(milliseconds: powerWait));
          }
          if (isPaused) break;

          await _botAIService.useBotSpecialPower(
            gameState,
            playerMMR: playerMMR,
            context: context,
            hardcoreLevel: hardcoreLevel,
            playerSkillEstimate: playerSkillEstimate,
          );
          onStateChanged?.call();

          if (isPaused) break;

          gameState.isWaitingForSpecialPower = false;
          gameState.specialCardToActivate = null;
          onStateChanged?.call();
        }
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Bot turn error: $e');
        // En cas d'erreur, défausser la carte tirée si elle existe
        if (gameState.drawnCard != null) {
          gameState.discardPile.add(gameState.drawnCard!);
          gameState.drawnCard = null;
        }
      }

      if (isPaused) break;

      // Si on est toujours en phase playing, démarrer la phase de réaction
      if (gameState.phase == GamePhase.playing) {
        break; // Sortir de la boucle pour démarrer la phase de réaction
      } else {
        break;
      }
    }
  }
}
