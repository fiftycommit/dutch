import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../providers/multiplayer_game_provider.dart';
import '../../shared/unified_dutch_reveal_screen.dart' as shared;
import 'multiplayer_results_screen.dart';

/// Écran de révélation Dutch pour le mode multiplayer
/// Utilise la version unifiée avec configuration spécifique
class MultiplayerDutchRevealScreen extends StatelessWidget {
  const MultiplayerDutchRevealScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<MultiplayerGameProvider>(context, listen: false);
    
    if (!provider.isPlaying || provider.gameState == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF1a472a),
        body: Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    }

    return PopScope(
      canPop: false,
      child: shared.DutchRevealScreen(
        config: shared.DutchRevealConfig(
          gameState: provider.gameState!,
          buildResultsScreen: (context) => MultiplayerResultsScreen(
            gameState: provider.gameState!,
            localPlayerId: provider.playerId,
          ),
          navigateToResults: (context) => context.go('/multiplayer/results'),
          shouldRedirectToLobby: () => 
            provider.isInLobby && !provider.isPlaying && provider.roomCode != null,
          navigateToLobbyRedirect: (context) => context.go('/lobby'),
        ),
      ),
    );
  }
}
