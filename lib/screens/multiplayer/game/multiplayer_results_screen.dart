import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/game_state.dart';
import '../../../models/player.dart';
import '../../../providers/multiplayer_game_provider.dart';
import '../../shared/unified_results_screen.dart' as shared;
import '../lobby/multiplayer_lobby_screen.dart';

/// Écran de résultats pour le mode multiplayer
/// Utilise la version unifiée avec configuration spécifique
class MultiplayerResultsScreen extends StatelessWidget {
  final GameState gameState;
  final String? localPlayerId;

  const MultiplayerResultsScreen({
    super.key,
    required this.gameState,
    this.localPlayerId,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MultiplayerGameProvider>();

    return shared.ResultsScreen(
      config: shared.ResultsConfig(
        gameState: gameState,
        localPlayerId: localPlayerId,
        title: "RÉSULTATS",
        shouldRedirect: () => provider.isInLobby && !provider.isPlaying && provider.roomCode != null,
        onRedirect: () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MultiplayerLobbyScreen()),
          );
        },
        buildActionButtons: (ctx) => _buildMultiplayerButtons(ctx, provider),
        rpCalculator: (player, rank) => _calculateRP(player, rank, gameState),
      ),
    );
  }

  /// Calcul des RP basé sur la position (simplifié pour multiplayer)
  shared.PlayerRPResult? _calculateRP(Player player, int rank, GameState gs) {
    // En multiplayer, tout le monde est humain donc on affiche les RP pour tous
    if (player.isSpectator) return null;
    
    final totalPlayers = gs.players.where((p) => !p.isSpectator).length;
    final isDutchCaller = gs.dutchCallerId == player.id;
    final isWinner = rank == 1;
    final isEliminated = isDutchCaller && !isWinner;
    
    int rp;
    if (isEliminated) {
      // Dutch raté = grosse pénalité
      rp = -50;
    } else if (isWinner) {
      // Gagnant
      rp = isDutchCaller ? 40 : 30; // Bonus si Dutch réussi
    } else {
      // Autres positions : RP décroissant
      // 2ème: +10, 3ème: -10, 4ème: -20, etc.
      rp = 20 - (rank * 10);
      if (totalPlayers <= 2 && rank == 2) rp = -10; // 1v1
    }
    
    return shared.PlayerRPResult(rpChange: rp);
  }

  List<Widget> _buildMultiplayerButtons(BuildContext context, MultiplayerGameProvider provider) {
    return [
      // Bouton retour au salon (Host) ou retour au salon (non-host)
      if (provider.isHost)
        shared.ResultsActionButton(
          label: "Retour au Salon (Host)",
          backgroundColor: Colors.green.shade700,
          onPressed: () => provider.restartGame(),
        )
      else
        shared.ResultsActionButton(
          label: "Retour au Salon",
          backgroundColor: Colors.blue.shade700,
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const MultiplayerLobbyScreen()),
              (route) => route.isFirst,
            );
          },
        ),
      
      const SizedBox(height: 12),
      
      // Bouton quitter/fermer
      shared.ResultsActionButton(
        label: provider.isHost ? "Fermer la room" : "Quitter",
        backgroundColor: provider.isHost ? Colors.red.shade700 : Colors.amber.shade700,
        onPressed: () {
          if (provider.isHost) {
            provider.closeRoom();
          } else {
            provider.leaveRoom();
          }
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
      ),
    ];
  }
}
