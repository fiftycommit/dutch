import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/game_state.dart';
import '../../providers/game_provider.dart';
import '../../utils/ui_constants.dart';
import '../shared/unified_memorization_screen.dart' as shared;

/// Écran de mémorisation pour le mode solo
/// Utilise la version unifiée avec configuration spécifique
class MemorizationScreen extends StatelessWidget {
  const MemorizationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final gameState = gameProvider.gameState;

    if (gameState == null) {
      return const Scaffold(
        backgroundColor: AppColors.gradientBottom,
        body: Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    }

    final humanPlayer = gameState.players.where((p) => p.isHuman).firstOrNull;

    if (humanPlayer == null) {
      return _buildEliminatedScreen();
    }

    return PopScope(
      canPop: false,
      child: shared.MemorizationScreen(
        config: shared.MemorizationConfig(
          localPlayer: humanPlayer,
          onMemorizationComplete: (selectedIndices) async {
            humanPlayer.memorizedCardIndices = selectedIndices.toList()..sort();

            // Marquer les cartes comme connues
            for (int index in selectedIndices) {
              humanPlayer.knownCards[index] = true;
            }

            // Réinitialiser les cartes connues de tous les joueurs
            for (var p in gameState.players) {
              for (int i = 0; i < p.hand.length; i++) {
                p.knownCards[i] = false;
              }
            }

            // Démarrer la phase de jeu
            gameState.phase = GamePhase.playing;
            gameState.isWaitingForSpecialPower = false;
            gameState.specialCardToActivate = null;

            // Démarrer le tour des bots après un court délai
            Future.delayed(const Duration(milliseconds: 300), () {
              gameProvider.checkIfBotShouldPlay();
            });
          },
          navigateToGame: (context) => context.go('/solo/game'),
          onQuit: (context) {
            if (gameState.gameMode == GameMode.tournament &&
                gameState.tournamentRound > 1) {
              gameProvider.quitGame();
            }
            context.go('/');
          },
          noPlayerTitle: "VOUS ÊTES ÉLIMINÉ",
          noPlayerMessage: "Les bots continuent...",
        ),
      ),
    );
  }

  Widget _buildEliminatedScreen() {
    return Scaffold(
      backgroundColor: AppColors.gradientBottom,
      body: Container(
        color: AppColors.gradientBottom,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.visibility_off,
                  size: 60, color: AppColors.textDisabled),
              SizedBox(height: 20),
              Text(
                "VOUS ÊTES ÉLIMINÉ",
                style: TextStyle(
                  fontSize: 32,
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 10),
              Text(
                "Les bots continuent...",
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
              ),
              SizedBox(height: 30),
              CircularProgressIndicator(color: Colors.amber),
            ],
          ),
        ),
      ),
    );
  }
}
