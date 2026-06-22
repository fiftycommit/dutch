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
import '../../core/service_locator.dart';
import '../../core/interfaces/i_haptic_service.dart';

/// Écran de résultats pour le mode solo
/// Utilise la version unifiée avec configuration spécifique
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  bool _tournamentFinishTriggered = false;
  bool _startingNextRound = false;

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
    final remainingRounds =
        (totalRounds - gameState.tournamentRound).clamp(0, totalRounds).toInt();
    final isFinalRound = remainingRounds == 0 || gameState.players.length <= 2;
    final isHumanEliminated = gameProvider.isHumanEliminatedInTournament();
    if (isHumanEliminated &&
        !isFinalRound &&
        gameProvider.tournamentFinalRanking == null) {
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
            body: Center(
                child: Text('Pas de résultats',
                    style: TextStyle(color: Colors.white))),
          );
        }

        final gameState = gameProvider.gameState!;
        final isTournament = gameState.gameMode == GameMode.tournament;
        final totalRounds =
            isTournament ? gameProvider.tournamentTotalRounds : 1;
        final remainingRounds = isTournament
            ? (totalRounds - gameState.tournamentRound)
                .clamp(0, totalRounds)
                .toInt()
            : 0;
        final isFinalRound = isTournament &&
            (remainingRounds == 0 || gameState.players.length <= 2);
        final isHumanEliminated =
            isTournament && gameProvider.isHumanEliminatedInTournament();
        final isTournamentOver =
            isTournament && (isFinalRound || isHumanEliminated);
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
              (gameState
                      .getFinalRanking()
                      .indexWhere((p) => p.id == humanPlayer.id) +
                  1);
        }();
        final isTournamentWinner =
            isTournament && isFinalRound && humanRank == 1;

        final showRP = gameProvider.useSBMM && gameProvider.playerMMR != null;

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
                if (isTournament && !isTournamentOver)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      children: [
                        shared.ResultsActionButton(
                          label: _startingNextRound
                              ? 'PRÉPARATION...'
                              : 'MANCHE SUIVANTE',
                          backgroundColor: Colors.amber.shade700,
                          onPressed: () async {
                            if (_startingNextRound) return;
                            final router = GoRouter.of(ctx);
                            setState(() => _startingNextRound = true);
                            try {
                              final started =
                                  await gameProvider.startNextTournamentRound();
                              if (started) {
                                router.go('/solo/memorization');
                                return;
                              }
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Impossible de préparer la manche suivante.'),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content:
                                        Text('Erreur manche suivante : $e'),
                                  ),
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _startingNextRound = false);
                              }
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => _confirmAbandonTournament(
                            ctx,
                            gameProvider,
                            remainingRounds,
                            gameState,
                          ),
                          child: const Text(
                            'Abandonner le tournoi',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  shared.ResultsActionButton(
                    label: 'TERMINER',
                    backgroundColor: Colors.amber.shade700,
                    onPressed: () => ctx.go('/'),
                  ),
              ],
              rpCalculator: showRP
                  ? (player, rank) =>
                      _calculateRP(gameProvider, player, rank, gameState)
                  : null,
            ),
          ),
        );
      },
    );
  }

  void _confirmAbandonTournament(
    BuildContext ctx,
    GameProvider gameProvider,
    int remainingRounds,
    GameState gameState,
  ) {
    const penaltyPerRound = 13 * 4; // 52
    final penaltyScore = penaltyPerRound * remainingRounds;

    // Score cumulé des manches déjà jouées
    final human = gameState.players.firstWhere((p) => p.isHuman);
    final cumulativeScores = gameState.tournamentCumulativeScores;
    final currentCumul = cumulativeScores[human.id] ?? 0;
    final totalScore = currentCumul + penaltyScore;

    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.dialogBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Colors.red.shade400, size: 28),
            const SizedBox(width: 8),
            const Text('Abandonner le tournoi ?',
                style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Score actuel (manches jouées) : $currentCumul pts',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pénalité abandon : $penaltyPerRound pts x $remainingRounds manche(s) = $penaltyScore pts',
                    style: TextStyle(color: Colors.red.shade300, fontSize: 14),
                  ),
                  const Divider(color: Colors.white24, height: 16),
                  Text(
                    'Score total enregistré : $totalScore pts',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Vous serez classé dernier avec ce score.',
              style: TextStyle(color: Colors.red.shade200, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child:
                const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              ServiceLocator().get<IHapticService>().buttonTap();
              Navigator.pop(dialogCtx);
              gameProvider.quitGame();
              if (ctx.mounted) ctx.go('/');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Abandonner'),
          ),
        ],
      ),
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
      stageLabel =
          tournamentStageLabel(eliminatedRound, totalRounds: totalRounds);
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
