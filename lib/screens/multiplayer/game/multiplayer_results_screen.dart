import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../models/game_state.dart';
import '../../../models/player.dart';
import '../../../providers/multiplayer_game_provider.dart';
import '../../../services/game/rp_result_helper.dart';
import '../../../services/multiplayer/competitive_service.dart';
import '../../../utils/tournament_labels.dart';
import '../../../utils/ui_constants.dart';
import '../../shared/unified_results_screen.dart' as shared;

/// Écran de résultats pour le mode multiplayer
/// Utilise la version unifiée avec configuration spécifique
class MultiplayerResultsScreen extends StatefulWidget {
  final GameState gameState;
  final String? localPlayerId;

  const MultiplayerResultsScreen({
    super.key,
    required this.gameState,
    this.localPlayerId,
  });

  @override
  State<MultiplayerResultsScreen> createState() =>
      _MultiplayerResultsScreenState();
}

class _MultiplayerResultsScreenState extends State<MultiplayerResultsScreen> {
  int? _localMMR;
  int _localWinStreak = 0;

  @override
  void initState() {
    super.initState();
    _loadLocalCompetitiveStats();
  }

  Future<void> _loadLocalCompetitiveStats() async {
    final playerId = widget.localPlayerId;
    if (playerId == null) return;
    final stats = await CompetitiveService.getStats(playerId);
    if (!mounted) return;
    setState(() {
      _localMMR = stats.mmr;
      _localWinStreak = stats.winStreak;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MultiplayerGameProvider>();
    final gameState = widget.gameState;
    final isTournament = gameState.gameMode == GameMode.tournament;
    final totalRounds = isTournament ? provider.tournamentTotalRounds : 1;
    final isFinalRound = provider.isTournamentFinalRound;
    final isLocalEliminated =
        isTournament && provider.isLocalPlayerEliminated();
    final isTournamentOver =
        isTournament && (isFinalRound || isLocalEliminated);

    final stageLabel = isTournament
        ? tournamentStageLabel(gameState.tournamentRound,
            totalRounds: totalRounds)
        : null;

    final eliminatedIds = <String>{};
    if (isTournament) {
      eliminatedIds.addAll(provider.getEliminatedPlayerIds());
    }

    // Vérifier si le joueur local a gagné le tournoi
    final localPlayer = gameState.players
        .where((p) => p.id == widget.localPlayerId)
        .firstOrNull;
    final localRank = localPlayer != null
        ? (gameState.getFinalRanksWithTies()[localPlayer.id] ??
            (gameState
                    .getFinalRanking()
                    .indexWhere((p) => p.id == localPlayer.id) +
                1))
        : 0;
    final isTournamentWinner = isTournament && isFinalRound && localRank == 1;

    return PopScope(
      canPop: false,
      child: shared.ResultsScreen(
        config: shared.ResultsConfig(
          gameState: gameState,
          localPlayerId: widget.localPlayerId,
          title: isTournament
              ? (isTournamentOver
                  ? "FIN DU TOURNOI"
                  : "${stageLabel!.toUpperCase()} TERMINÉE")
              : "RÉSULTATS",
          subtitle: isTournamentOver ? stageLabel : null,
          alertBanner: isTournamentWinner
              ? _buildTournamentWinnerBanner()
              : (isTournament && isLocalEliminated)
                  ? _buildEliminatedBanner(stageLabel)
                  : null,
          isTournamentFinal: isFinalRound,
          eliminatedPlayerIds: eliminatedIds.isEmpty ? null : eliminatedIds,
          shouldRedirect: () {
            // Room was closed/destroyed or player was removed → exit
            if (provider.roomCode == null) {
              return true;
            }
            // Room restarted → go to lobby
            if (provider.isInLobby &&
                !provider.isPlaying &&
                provider.roomCode != null) {
              return true;
            }
            // Host closed room while we're on results
            if (provider.roomClosedByHost) {
              return true;
            }
            // Banned
            if (provider.wasBanned) {
              return true;
            }
            return false;
          },
          onRedirect: () {
            if (provider.wasBanned) {
              provider.acknowledgeBanned(); // resets room state
              context.go('/multiplayer');
            } else if (provider.roomClosedByHost) {
              provider.acknowledgeRoomClosed(); // resets room state
              context.go('/multiplayer');
            } else if (provider.roomCode == null) {
              // Room destroyed or we were removed
              context.go('/multiplayer');
            } else {
              // Room restarted → lobby
              context.go('/lobby');
            }
          },
          buildActionButtons: (ctx) => _buildMultiplayerButtons(ctx, provider,
              isTournament: isTournament, isTournamentOver: isTournamentOver),
          rpCalculator: (player, rank) => _calculateRP(player, rank, gameState),
        ),
      ),
    );
  }

  Widget _buildTournamentWinnerBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.shade700, Colors.orange.shade600],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.emoji_events, color: Colors.white, size: 24),
          SizedBox(width: 8),
          Text(
            "🏆 CHAMPION DU TOURNOI ! 🏆",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEliminatedBanner(String? stageLabel) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "💀 ÉLIMINÉ DU TOURNOI",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          if (stageLabel != null)
            Text(
              "Éliminé en $stageLabel",
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
        ],
      ),
    );
  }

  shared.PlayerRPResult? _calculateRP(Player player, int rank, GameState gs) {
    // Si les stats ne sont pas encore chargées, ne pas calculer pour éviter
    // d'afficher un rang Bronze par défaut (MMR=0) à la place du vrai rang.
    if (_localMMR == null) return null;
    final currentMMR = _localMMR!;
    final isLocalPlayer = player.id == widget.localPlayerId;
    final winStreak = isLocalPlayer && rank == 1 ? _localWinStreak + 1 : 0;

    return RPResultHelper.build(
      gameState: gs,
      player: player,
      rank: rank,
      currentMMR: currentMMR,
      winStreak: winStreak,
    );
  }

  List<Widget> _buildMultiplayerButtons(
    BuildContext context,
    MultiplayerGameProvider provider, {
    bool isTournament = false,
    bool isTournamentOver = false,
  }) {
    // Joueur kické / expulsé : bouton quitter directement
    if (provider.wasKicked) {
      return [
        shared.ResultsActionButton(
          label: "Quitter",
          backgroundColor: Colors.orange.shade700,
          onPressed: () {
            provider.acknowledgeKicked(); // resets room state
            context.go('/multiplayer');
          },
        ),
      ];
    }

    // Tous les joueurs : retour indépendant au salon
    return [
      shared.ResultsActionButton(
        label: isTournament && !isTournamentOver
            ? "MANCHE SUIVANTE >>"
            : "Retour au Salon",
        backgroundColor: isTournament && !isTournamentOver
            ? Colors.amber.shade700
            : Colors.green.shade700,
        onPressed: () {
          provider.returnToLobbyFromResults();
          context.go('/lobby');
        },
      ),

      const SizedBox(height: 12),

      shared.ResultsActionButton(
        label: "Quitter le salon",
        backgroundColor: Colors.red.shade700,
        onPressed: () {
          provider.leaveAfterResults();
          context.go('/multiplayer');
        },
      ),
    ];
  }
}
