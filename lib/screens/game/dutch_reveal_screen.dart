import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/game_provider.dart';
import '../shared/unified_dutch_reveal_screen.dart' as shared;
import 'results_screen.dart';

/// Écran de révélation Dutch pour le mode solo
/// Utilise la version unifiée avec configuration spécifique
class DutchRevealScreen extends StatelessWidget {
  const DutchRevealScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    
    if (!gameProvider.hasActiveGame) {
      return const Scaffold(
        backgroundColor: Color(0xFF1a472a),
        body: Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    }

    return PopScope(
      canPop: false,
      child: shared.DutchRevealScreen(
        config: shared.DutchRevealConfig(
          gameState: gameProvider.gameState!,
          buildResultsScreen: (context) => const ResultsScreen(),
          navigateToResults: (context) => context.go('/solo/results'),
          orderPlayers: shared.orderPlayersForSolo,
        ),
      ),
    );
  }
}
