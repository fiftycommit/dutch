import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../models/game_state.dart';
import '../../models/player.dart';
import '../../providers/game_provider.dart';
import '../../services/game/rp_result_helper.dart';
import '../shared/unified_results_screen.dart' as shared;
import '../../utils/tournament_labels.dart';

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
        final totalRounds = isTournament ? gameProvider.tournamentTotalRounds : 1;
        final isFinalRound =
            isTournament && gameState.tournamentRound >= totalRounds;
        final isHumanEliminated = isTournament && gameProvider.isHumanEliminatedInTournament();
        final isTournamentOver = isTournament && (isFinalRound || isHumanEliminated);
        final stageLabel = isTournament
            ? tournamentStageLabel(
                gameState.tournamentRound,
                totalRounds: totalRounds,
              )
            : null;

        final eliminatedIds = <String>{};
        if (isTournament) {
          if (isFinalRound) {
            final ranking = gameState.getFinalRanking();
            eliminatedIds.addAll(ranking.skip(1).map((p) => p.id));
          } else {
            eliminatedIds.addAll(gameProvider.getTournamentEliminatedIds());
          }
        }

        // Déclencher la simulation du classement final si nécessaire
        if (isTournament && isHumanEliminated && !isFinalRound && gameProvider.tournamentFinalRanking == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            gameProvider.finishTournamentForHuman();
          });
        }

        // Trouver le joueur humain
        final humanPlayer = gameState.players.firstWhere((p) => p.isHuman);
        final showRP = gameProvider.playerMMR != null;

        return shared.ResultsScreen(
          config: shared.ResultsConfig(
            gameState: gameState,
            localPlayerId: humanPlayer.id,
            title: isTournament
                ? (isTournamentOver
                    ? "FIN DU TOURNOI"
                    : "${stageLabel!.toUpperCase()} TERMINÉE")
                : "RÉSULTATS",
            subtitle: isTournamentOver ? stageLabel : null,
            alertBanner: (isTournament && isHumanEliminated && gameProvider.tournamentFinalRanking != null)
                ? _buildEliminatedBanner(gameProvider, totalRounds)
                : null,
            eliminatedPlayerIds: eliminatedIds.isEmpty ? null : eliminatedIds,
            buildActionButtons: (ctx) => [
              shared.ResultsActionButton(
                label: (isTournament && !isTournamentOver) ? 'MANCHE SUIVANTE >>' : 'TERMINER',
                backgroundColor: Colors.amber.shade700,
                onPressed: () {
                  if (isTournament && !isTournamentOver) {
                    gameProvider.startNextTournamentRound();
                    ctx.go('/solo/memorization');
                  } else {
                    ctx.go('/');
                  }
                },
              ),
            ],
            rpCalculator: showRP
                ? (player, rank) => _calculateRP(gameProvider, player, rank, gameState)
                : null,
          ),
        );
      },
    );
  }

  shared.PlayerRPResult? _calculateRP(
    GameProvider provider,
    Player player,
    int rank,
    GameState gameState,
  ) {
    if (player.isHuman) {
      return RPResultHelper.build(
        gameState: gameState,
        player: player,
        rank: rank,
        currentMMR: provider.playerMMR,
        winStreak: rank == 1 ? provider.playerWinStreak + 1 : 0,
        overrideResult: provider.lastMatchRpResult,
      );
    }

    return RPResultHelper.build(
      gameState: gameState,
      player: player,
      rank: rank,
      currentMMR: provider.playerMMR,
      winStreak: 0,
    );
  }

  Widget _buildEliminatedBanner(GameProvider gameProvider, int totalRounds) {
    final eliminatedRound = gameProvider.tournamentFinalRanking!
        .firstWhere((r) => r.player.isHuman)
        .eliminatedAtRound;
    final stageLabel = eliminatedRound == null
        ? null
        : tournamentStageLabel(eliminatedRound, totalRounds: totalRounds);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
      ),
      child: Text(
        stageLabel == null
            ? "Vous avez été éliminé"
            : "Vous avez été éliminé en $stageLabel",
        style: const TextStyle(
          color: Colors.redAccent,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
