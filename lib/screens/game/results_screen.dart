import 'package:flutter/material.dart';
import '../../utils/ui_constants.dart';
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
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  bool _tournamentFinishTriggered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeTriggerTournamentFinish();
    });
  }

  void _maybeTriggerTournamentFinish() {
    if (!mounted || _tournamentFinishTriggered) return;
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    if (!gameProvider.hasActiveGame) return;
    final gameState = gameProvider.gameState!;
    final isTournament = gameState.gameMode == GameMode.tournament;
    if (!isTournament) return;
    final totalRounds = gameProvider.tournamentTotalRounds;
    final remainingRounds = (totalRounds - gameState.tournamentRound).clamp(0, totalRounds).toInt();
    final isFinalRound = remainingRounds == 0 || gameState.players.length <= 2;
    final isHumanEliminated = gameProvider.isHumanEliminatedInTournament();
    if (isHumanEliminated && !isFinalRound && gameProvider.tournamentFinalRanking == null) {
      _tournamentFinishTriggered = true;
      gameProvider.finishTournamentForHuman();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, gameProvider, child) {
        if (!gameProvider.hasActiveGame) {
          return Scaffold(
            backgroundColor: AppColors.gradientBottom,
            body: Center(child: Text('Pas de résultats', style: TextStyle(color: Colors.white))),
          );
        }

        final gameState = gameProvider.gameState!;
        final isTournament = gameState.gameMode == GameMode.tournament;
        final totalRounds = isTournament ? gameProvider.tournamentTotalRounds : 1;
        final remainingRounds = isTournament
            ? (totalRounds - gameState.tournamentRound)
                .clamp(0, totalRounds)
                .toInt()
            : 0;
        final isFinalRound = isTournament &&
            (remainingRounds == 0 || gameState.players.length <= 2);
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

        final humanPlayer = gameState.players.firstWhere((p) => p.isHuman);
        final humanRank = () {
          final ranksWithTies = gameState.getFinalRanksWithTies();
          return ranksWithTies[humanPlayer.id] ??
              (gameState.getFinalRanking().indexWhere((p) => p.id == humanPlayer.id) + 1);
        }();
        final isTournamentWinner = isTournament && isFinalRound && humanRank == 1;

        final showRP = gameProvider.playerMMR != null;

        return PopScope(
          canPop: false,
          child: shared.ResultsScreen(
          config: shared.ResultsConfig(
            gameState: gameState,
            localPlayerId: humanPlayer.id,
            title: isTournament
                ? (isTournamentOver
                    ? "FIN DU TOURNOI"
                    : "${stageLabel!.toUpperCase()} TERMINÉE")
                : "RÉSULTATS",
            subtitle: isTournamentOver ? stageLabel : null,
            alertBanner: isTournamentWinner
                ? _buildTournamentWinnerBanner()
                : (isTournament && isHumanEliminated)
                    ? _buildEliminatedBanner(
                        gameProvider,
                        totalRounds,
                        gameState.tournamentRound,
                      )
                    : null,
            isTournamentFinal: isFinalRound,
            eliminatedPlayerIds: eliminatedIds.isEmpty ? null : eliminatedIds,
            buildActionButtons: (ctx) => [
              shared.ResultsActionButton(
                label: (isTournament && !isTournamentOver) ? 'MANCHE SUIVANTE >>' : 'TERMINER',
                backgroundColor: Colors.amber.shade700,
                onPressed: () async {
                  if (isTournament && !isTournamentOver) {
                    await gameProvider.startNextTournamentRound();
                    if (ctx.mounted) ctx.go('/solo/memorization');
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

  Widget _buildEliminatedBanner(
    GameProvider gameProvider,
    int totalRounds,
    int currentRound,
  ) {
    final isFinalRound = currentRound >= totalRounds;
    final eliminatedRound = gameProvider.tournamentFinalRanking
        ?.firstWhere((r) => r.player.isHuman)
        .eliminatedAtRound;
    String? stageLabel;
    if (isFinalRound) {
      stageLabel = tournamentStageLabel(currentRound, totalRounds: totalRounds);
    } else if (eliminatedRound != null) {
      stageLabel = tournamentStageLabel(eliminatedRound, totalRounds: totalRounds);
    }
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

  Widget _buildTournamentWinnerBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
      ),
      child: const Text(
        "🏆 Vous gagnez le tournoi !",
        style: TextStyle(
          color: Colors.greenAccent,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
