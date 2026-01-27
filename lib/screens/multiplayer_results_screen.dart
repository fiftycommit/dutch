import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../providers/multiplayer_game_provider.dart';
import '../utils/screen_utils.dart';
import '../widgets/player_avatar.dart';
import 'multiplayer_lobby_screen.dart';

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

    // Si la room a été redémarrée, naviguer vers le lobby
    if (provider.isInLobby && !provider.isPlaying && provider.roomCode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ModalRoute.of(context)?.isCurrent == true) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MultiplayerLobbyScreen()),
          );
        }
      });
    }

    final ranking = gameState.getFinalRanking();
    final ranks = gameState.getFinalRanksWithTies();
    final callerId = gameState.dutchCallerId;
    final caller = callerId != null
        ? gameState.players.firstWhere((p) => p.id == callerId)
        : null;
    final callerWon = gameState.didDutchCallerWin();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0d2818), Color(0xFF1a472a)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(height: ScreenUtils.spacing(context, 16)),
              Text(
                "RÉSULTATS",
                style: TextStyle(
                  fontFamily: 'Rye',
                  fontSize: ScreenUtils.scaleFont(context, 30),
                  color: Colors.white,
                  shadows: const [
                    Shadow(
                      color: Colors.black45,
                      blurRadius: 10,
                      offset: Offset(2, 2),
                    )
                  ],
                ),
              ),
              if (caller != null) ...[
                SizedBox(height: ScreenUtils.spacing(context, 8)),
                Container(
                  margin: EdgeInsets.symmetric(
                    horizontal: ScreenUtils.spacing(context, 16),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: ScreenUtils.spacing(context, 12),
                    vertical: ScreenUtils.spacing(context, 8),
                  ),
                  decoration: BoxDecoration(
                    color: callerWon
                        ? Colors.green.withValues(alpha: 0.2)
                        : Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: callerWon ? Colors.greenAccent : Colors.redAccent,
                    ),
                  ),
                  child: Text(
                    callerWon
                        ? "${caller.name} a crié DUTCH et gagne la manche !"
                        : "${caller.name} a crié DUTCH mais perd la manche.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              SizedBox(height: ScreenUtils.spacing(context, 12)),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.symmetric(
                    horizontal: ScreenUtils.spacing(context, 16),
                  ),
                  itemCount: ranking.length,
                  itemBuilder: (context, index) {
                    final player = ranking[index];
                    final rank = ranks[player.id] ?? (index + 1);
                    final isYou = player.id == localPlayerId;
                    final isCaller = player.id == callerId;
                    final score = gameState.getFinalScore(player);
                    return _buildResultRow(
                      context,
                      player: player,
                      rank: rank,
                      score: score,
                      isYou: isYou,
                      isCaller: isCaller,
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.all(ScreenUtils.spacing(context, 16)),
                child: SizedBox(
                  child: Column(
                    children: [
                      if (context.watch<MultiplayerGameProvider>().isHost) ...[
                        SizedBox(
                          width: 280,
                          child: ElevatedButton(
                            onPressed: () {
                              context
                                  .read<MultiplayerGameProvider>()
                                  .restartGame();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              "Rejouer",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: ScreenUtils.spacing(context, 12)),
                      ],
                      SizedBox(
                        width: 280,
                        child: ElevatedButton(
                          onPressed: () {
                            context.read<MultiplayerGameProvider>().leaveRoom();
                            Navigator.of(context)
                                .popUntil((route) => route.isFirst);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            "Retour au menu",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultRow(
    BuildContext context, {
    required Player player,
    required int rank,
    required int score,
    required bool isYou,
    required bool isCaller,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: ScreenUtils.spacing(context, 8)),
      padding: EdgeInsets.symmetric(
        horizontal: ScreenUtils.spacing(context, 12),
        vertical: ScreenUtils.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCaller ? Colors.amber : Colors.white12,
          width: isCaller ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              "#$rank",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(width: ScreenUtils.spacing(context, 10)),
          PlayerAvatar(
            player: player,
            isActive: isCaller,
            compactMode: true,
            size: 28,
          ),
          SizedBox(width: ScreenUtils.spacing(context, 10)),
          Expanded(
            child: Text(
              isYou ? "${player.name} (Vous)" : player.name,
              style: TextStyle(
                color: isYou ? Colors.amber : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: ScreenUtils.scaleFont(context, 14),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            "$score pts",
            style: TextStyle(
              color: Colors.white70,
              fontSize: ScreenUtils.scaleFont(context, 12),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
