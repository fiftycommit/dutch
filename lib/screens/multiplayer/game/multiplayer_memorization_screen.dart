import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../providers/multiplayer_game_provider.dart';
import '../../../utils/ui_constants.dart';
import '../../shared/unified_memorization_screen.dart' as shared;
import 'multiplayer_game_screen.dart';

/// Écran de mémorisation pour le mode multiplayer
/// Utilise la version unifiée avec configuration spécifique
class MultiplayerMemorizationScreen extends StatelessWidget {
  const MultiplayerMemorizationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider =
        Provider.of<MultiplayerGameProvider>(context, listen: false);
    final gameState = provider.gameState;

    if (gameState == null) {
      return const Scaffold(
        backgroundColor: AppColors.gradientBottom,
        body: Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    }

    final localPlayer =
        gameState.players.where((p) => p.id == provider.playerId).firstOrNull;

    if (localPlayer == null) {
      return _buildSpectatorScreen();
    }

    // Créer un stream pour écouter l'événement gameStarted
    final gameStartStream = provider.events
        .where((event) => event.type == GameEventType.gameStarted)
        .map((_) {});

    return PopScope(
      canPop: false,
      child: shared.MemorizationScreen(
        config: shared.MemorizationConfig(
          localPlayer: localPlayer,
          onMemorizationComplete: (selectedIndices) async {
            // En multiplayer, pas besoin de modifier l'état local
            // Le serveur gère tout
          },
          buildGameScreen: (context) => const MultiplayerGameScreen(),
          navigateToGame: (context) => context.go('/multiplayer/game'),
          countdownSeconds: 15,
          showWaitingScreen: true,
          gameStartStream: gameStartStream,
          onMarkReady: () => provider.markReady(),
          buildReadyInfo: (context) => Consumer<MultiplayerGameProvider>(
            builder: (context, provider, child) {
              final state = provider.gameState;
              if (state == null) return const SizedBox();
              final readyCount = state.readyPlayerIds.length;
              final totalHumans = state.players
                  .where((p) => p.isHuman && !p.isSpectator)
                  .length;
              return Text(
                '$readyCount / $totalHumans prêts',
                style: const TextStyle(color: AppColors.textSecondary),
              );
            },
          ),
          noPlayerTitle: "VOUS ÊTES SPECTATEUR",
          noPlayerMessage: "La partie va commencer...",
        ),
      ),
    );
  }

  Widget _buildSpectatorScreen() {
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
                "VOUS ÊTES SPECTATEUR",
                style: TextStyle(
                  fontFamily: 'Rye',
                  fontSize: 32,
                  color: Colors.amberAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 10),
              Text(
                "La partie va commencer...",
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
