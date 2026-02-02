import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../models/game_state.dart';
import '../../../models/player.dart';
import '../../../providers/multiplayer_game_provider.dart';
import '../../../services/game/rp_result_helper.dart';
import '../../../services/multiplayer/competitive_service.dart';
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

    return shared.ResultsScreen(
      config: shared.ResultsConfig(
        gameState: widget.gameState,
        localPlayerId: widget.localPlayerId,
        title: "RÉSULTATS",
        shouldRedirect: () => provider.isInLobby && !provider.isPlaying && provider.roomCode != null,
        onRedirect: () {
          context.go('/lobby');
        },
        buildActionButtons: (ctx) => _buildMultiplayerButtons(ctx, provider),
        rpCalculator: (player, rank) => _calculateRP(player, rank, widget.gameState),
      ),
    );
  }

  shared.PlayerRPResult? _calculateRP(Player player, int rank, GameState gs) {
    final currentMMR = _localMMR ?? 0;
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

  List<Widget> _buildMultiplayerButtons(BuildContext context, MultiplayerGameProvider provider) {
    if (provider.isHost) {
      return [
        // Bouton retour au salon (Host uniquement)
        shared.ResultsActionButton(
          label: "Retour au Salon",
          backgroundColor: Colors.green.shade700,
          onPressed: () => provider.restartGame(),
        ),

        const SizedBox(height: 12),

        // Bouton fermer la room (Host uniquement)
        shared.ResultsActionButton(
          label: "Fermer la room",
          backgroundColor: Colors.red.shade700,
          onPressed: () {
            provider.closeRoom();
            context.go('/multiplayer');
          },
        ),
      ];
    }

    // Non-host: boutons pour retourner au lobby ou quitter
    return [
      shared.ResultsActionButton(
        label: "Retour au Salon",
        backgroundColor: Colors.green.shade700,
        onPressed: () => context.go('/lobby'),
      ),

      const SizedBox(height: 12),

      shared.ResultsActionButton(
        label: "Quitter",
        backgroundColor: Colors.red.shade700,
        onPressed: () {
          provider.leaveRoom();
          context.go('/multiplayer');
        },
      ),
    ];
  }
}
