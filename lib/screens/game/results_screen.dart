import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../models/game_state.dart';
import '../../providers/game_provider.dart';
import '../shared/unified_results_screen.dart' as shared;
import 'memorization_screen.dart';

/// Écran de résultats pour le mode solo
/// Utilise la version unifiée avec configuration spécifique
class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, gameProvider, child) {
        if (!gameProvider.hasActiveGame) {
          return const Scaffold(
            backgroundColor: Color(0xFF1a472a),
            body: Center(child: Text('Pas de résultats', style: TextStyle(color: Colors.white))),
          );
        }

        final gameState = gameProvider.gameState!;
        final isTournament = gameState.gameMode == GameMode.tournament;
        final isFinalRound = isTournament && gameState.tournamentRound >= 3;
        final isHumanEliminated = isTournament && gameProvider.isHumanEliminatedInTournament();
        final isTournamentOver = isTournament && (isFinalRound || isHumanEliminated);

        // Déclencher la simulation du classement final si nécessaire
        if (isTournament && isHumanEliminated && !isFinalRound && gameProvider.tournamentFinalRanking == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            gameProvider.finishTournamentForHuman();
          });
        }

        // Trouver le joueur humain
        final humanPlayer = gameState.players.firstWhere((p) => p.isHuman);

        return shared.ResultsScreen(
          config: shared.ResultsConfig(
            gameState: gameState,
            localPlayerId: humanPlayer.id,
            title: isTournament
                ? (isTournamentOver ? "FIN DU TOURNOI" : "MANCHE ${gameState.tournamentRound} TERMINÉE")
                : "RÉSULTATS",
            alertBanner: (isTournament && isHumanEliminated && gameProvider.tournamentFinalRanking != null)
                ? _buildEliminatedBanner(gameProvider)
                : null,
            buildActionButtons: (ctx) => [
              shared.ResultsActionButton(
                label: (isTournament && !isTournamentOver) ? 'MANCHE SUIVANTE >>' : 'TERMINER',
                backgroundColor: Colors.amber.shade700,
                onPressed: () {
                  if (isTournament && !isTournamentOver) {
                    gameProvider.startNextTournamentRound();
                    Navigator.of(ctx).pushReplacement(
                      MaterialPageRoute(builder: (_) => const MemorizationScreen()),
                    );
                  } else {
                    ctx.go('/');
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEliminatedBanner(GameProvider gameProvider) {
    final eliminatedRound = gameProvider.tournamentFinalRanking!
        .firstWhere((r) => r.player.isHuman)
        .eliminatedAtRound;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
      ),
      child: Text(
        "Vous avez été éliminé à la manche $eliminatedRound",
        style: const TextStyle(
          color: Colors.redAccent,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
