import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../providers/game_provider.dart';
import '../utils/screen_utils.dart';
import '../widgets/player_avatar.dart';
import 'main_menu_screen.dart';
import 'memorization_screen.dart';
import 'dutch_reveal_screen.dart'; // ✅ AJOUT

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<GameProvider>(
        builder: (context, gameProvider, child) {
          if (!gameProvider.hasActiveGame) {
            return const Center(child: Text('Pas de résultats'));
          }

          final gameState = gameProvider.gameState!;

          final ranking = gameState.getFinalRanking();
          final isTournament = gameState.gameMode == GameMode.tournament;

          bool isTournamentOver =
              isTournament && gameState.tournamentRound >= 3;

          return Container(
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
                  SizedBox(height: ScreenUtils.spacing(context, 20)),

                  // Titre
                  Text(
                    isTournament
                        ? (isTournamentOver
                            ? "FIN DU TOURNOI"
                            : "MANCHE ${gameState.tournamentRound} TERMINÉE")
                        : "RÉSULTATS",
                    style: TextStyle(
                      fontFamily: 'Rye',
                      fontSize: ScreenUtils.scaleFont(context, 32),
                      color: Colors.white,
                      shadows: const [
                        Shadow(
                            color: Colors.black45,
                            blurRadius: 10,
                            offset: Offset(2, 2))
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Liste des joueurs (Classement)
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: ranking.length,
                      itemBuilder: (context, index) {
                        final player = ranking[index];
                        return _buildPlayerResult(
                            context, player, index + 1, gameState);
                      },
                    ),
                  ),

                  // Bouton d'action unique (centré)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: SizedBox(
                        width: 300,
                        child: ElevatedButton(
                          onPressed: () {
                            if (isTournament && !isTournamentOver) {
                              // TOURNOI : Manche suivante
                              debugPrint("🏆 Manche suivante déclenchée");
                              gameProvider.startNextTournamentRound();

                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                    builder: (context) =>
                                        const MemorizationScreen()),
                              );
                            } else {
                              // PARTIE RAPIDE ou FIN TOURNOI : Retour Menu
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                    builder: (context) =>
                                        const MainMenuScreen()),
                                (route) => false,
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(
                            (isTournament && !isTournamentOver)
                                ? 'MANCHE SUIVANTE >>'
                                : 'TERMINER',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlayerResult(
      BuildContext context, Player player, int rank, GameState gs) {
    bool isWinner = rank == 1;
    bool isDutchCaller = gs.dutchCallerId == player.id;
    bool isEliminated = isDutchCaller && !isWinner;
    int score = gs.getFinalScore(player);

    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    bool isSBMM = gameProvider.playerMMR != null;
    bool isTournament = gs.gameMode == GameMode.tournament;

    // ✅ NOUVEAU : Déterminer si éliminé en tournoi
    bool isTournamentEliminated =
        isTournament && rank == gs.players.length && !isWinner;

    String pointsChangeText = "";
    Color pointsColor = Colors.grey;

    if (!isSBMM) {
      pointsChangeText = "Mode Manuel";
      pointsColor = Colors.white54;
    } else {
      switch (rank) {
        case 1:
          if (isDutchCaller) {
            pointsChangeText = "+80 RP";
            pointsColor = Colors.amber;
          } else {
            pointsChangeText = "+50 RP";
            pointsColor = Colors.greenAccent;
          }
          break;
        case 2:
          pointsChangeText = "+25 RP";
          pointsColor = Colors.lightGreenAccent;
          break;
        case 3:
          pointsChangeText = "-15 RP";
          pointsColor = Colors.orange;
          break;
        case 4:
          if (isEliminated) {
            pointsChangeText = "-60 RP";
            pointsColor = Colors.red;
          } else {
            pointsChangeText = "-30 RP";
            pointsColor = Colors.redAccent;
          }
          break;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isEliminated
            ? Colors.red.withValues(alpha: 0.2)
            : (isWinner
                ? Colors.amber.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(12),
        border: isEliminated ? Border.all(color: Colors.red, width: 2) : null,
      ),
      child: Row(
        children: [
          Text(
            "#$rank",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isWinner ? Colors.amber : Colors.white54,
            ),
          ),
          const SizedBox(width: 16),
          PlayerAvatar(player: player, size: 50),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      player.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                    if (isDutchCaller) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius: BorderRadius.circular(4)),
                        child: const Text("DUTCH",
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 10)),
                      ),
                    ],
                    // ✅ NOUVEAU : Badge ÉLIMINÉ
                    if (isTournamentEliminated) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(4)),
                        child: const Text("ÉLIMINÉ",
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 10)),
                      ),
                    ],
                  ],
                ),
                if (isEliminated)
                  const Text(
                    "❌ ÉLIMINÉ (Dutch raté !)",
                    style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "$score pts",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                pointsChangeText,
                style: TextStyle(
                    color: pointsColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
