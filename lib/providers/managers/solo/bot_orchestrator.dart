import 'dart:async';
import 'dart:math';
import 'package:flutter/widgets.dart';
import '../../../models/playing_card.dart';
import '../../../models/game_state.dart';
import '../../../core/interfaces/i_bot_ai_service.dart';

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
    bool isPaused,
  ) async {
    if (gameState.phase != GamePhase.reaction) return false;
    if (isPaused) return false;

    PlayingCard? topCard = gameState.topDiscardCard;
    if (topCard == null) return false;

    for (var bot in gameState.players.where((p) => !p.isHuman)) {
      if (gameState.phase != GamePhase.reaction) return false;
      if (isPaused) return false;

      int delay = Random().nextInt(250) + 100;
      await Future.delayed(Duration(milliseconds: delay));

      if (gameState.phase != GamePhase.reaction) return false;

      bool matched = await _botAIService.tryReactionMatch(
        gameState,
        bot,
        playerMMR: playerMMR,
      );

      if (matched) {
        return true; // Un bot a matché
      }
    }
    
    return false; // Aucun bot n'a matché
  }

  /// Jouer le tour d'un bot (boucle complète)
  Future<void> playBotTurn(
    GameState gameState,
    int? playerMMR,
    bool isPaused,
    BuildContext? context,
    Function onCheckInstantEnd,
  ) async {
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

      // Attendre un peu avant que le bot joue
      if (!isPaused) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
      if (isPaused) break;

      try {
        if (isPaused) break;
        
        await _botAIService.playBotTurn(
          gameState,
          playerMMR: playerMMR,
          context: context,
        );
        
        if (isPaused) break;

        if (gameState.phase == GamePhase.dutchCalled) {
          return; // Le bot a appelé Dutch
        }

        if (gameState.isWaitingForSpecialPower) {
          // Attendre avant d'utiliser le pouvoir
          if (!isPaused) {
            await Future.delayed(const Duration(milliseconds: 180));
          }
          if (isPaused) break;
          
          await _botAIService.useBotSpecialPower(
            gameState,
            playerMMR: playerMMR,
            context: context,
          );
          
          if (isPaused) break;

          gameState.isWaitingForSpecialPower = false;
          gameState.specialCardToActivate = null;
        }
      } catch (e) {
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
