import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../providers/game_provider.dart';
import '../utils/screen_utils.dart';
import '../widgets/player_avatar.dart';
import 'main_menu_screen.dart';
import 'memorization_screen.dart';
import 'dutch_reveal_screen.dart';

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

          // 🏆 Vérifier si l'humain est éliminé en tournoi
          bool isHumanEliminated = isTournament && gameProvider.isHumanEliminatedInTournament();
          
          // 🏆 Le tournoi est terminé si :
          // - On a atteint la manche 3 (finale)
          // - OU l'humain a été éliminé
          bool isTournamentOver = isTournament && 
              (gameState.tournamentRound >= 3 || isHumanEliminated);

          // 🏆 Si l'humain vient d'être éliminé et qu'on n'a pas encore simulé
          if (isHumanEliminated && gameProvider.tournamentFinalRanking == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              gameProvider.finishTournamentForHuman();
            });
          }

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

                  // 🏆 Sous-titre si l'humain est éliminé
                  if (isHumanEliminated && gameProvider.tournamentFinalRanking != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withOpacity(0.5)),
                      ),
                      child: Text(
                        "Vous avez été éliminé à la manche ${gameProvider.tournamentFinalRanking!.firstWhere((r) => r.player.isHuman).eliminatedAtRound}",
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Liste des joueurs (Classement)
                  Expanded(
                    child: _buildRankingList(context, gameProvider, gameState, isTournament, isTournamentOver),
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
                              debugPrint("🏆 Manche suivante déclenchée");
                              gameProvider.startNextTournamentRound();

                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                    builder: (context) =>
                                        const MemorizationScreen()),
                              );
                            } else {
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

  // 🏆 Construire la liste de classement selon le contexte
  Widget _buildRankingList(BuildContext context, GameProvider gameProvider, 
      GameState gameState, bool isTournament, bool isTournamentOver) {
    
    // Si on a un classement final de tournoi (humain éliminé), l'utiliser
    if (isTournament && isTournamentOver && gameProvider.tournamentFinalRanking != null) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: gameProvider.tournamentFinalRanking!.length,
        itemBuilder: (context, index) {
          final result = gameProvider.tournamentFinalRanking![index];
          return _buildTournamentFinalResult(context, result, gameProvider);
        },
      );
    }

    // Sinon, afficher le classement normal de la manche
    final ranking = gameState.getFinalRanking();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: ranking.length,
      itemBuilder: (context, index) {
        final player = ranking[index];
        return _buildPlayerResult(context, player, index + 1, gameState);
      },
    );
  }

  // 🏆 Afficher le résultat final du tournoi
  Widget _buildTournamentFinalResult(BuildContext context, TournamentResult result, GameProvider gameProvider) {
    bool isWinner = result.finalPosition == 1;
    bool isHuman = result.player.isHuman;
    bool isSBMM = gameProvider.playerMMR != null;
    bool isEliminated = result.eliminatedAtRound != null;

    int rpChange = isSBMM && isHuman ? gameProvider.getTournamentRP(result.finalPosition) : 0;
    
    String pointsChangeText = "";
    Color pointsColor = Colors.grey;

    if (isHuman) {
      if (!isSBMM) {
        pointsChangeText = "Mode Manuel";
        pointsColor = Colors.white54;
      } else {
        if (rpChange > 0) {
          pointsChangeText = "+$rpChange RP";
          pointsColor = rpChange >= 100 ? Colors.amber : Colors.greenAccent;
        } else if (rpChange < 0) {
          pointsChangeText = "$rpChange RP";
          pointsColor = Colors.redAccent;
        } else {
          pointsChangeText = "0 RP";
          pointsColor = Colors.white54;
        }
      }
    }

    // Déterminer le texte de statut
    String statusText = "";
    if (isWinner) {
      statusText = "🏆 CHAMPION";
    } else if (result.eliminatedAtRound != null) {
      statusText = "Éliminé manche ${result.eliminatedAtRound}";
    }

    // Couleurs selon le statut
    Color backgroundColor;
    Color? borderColor;
    
    if (isWinner) {
      backgroundColor = Colors.amber.withOpacity(0.2);
      borderColor = Colors.amber;
    } else if (isHuman && isEliminated) {
      // 🔴 HUMAIN ÉLIMINÉ = ROUGE
      backgroundColor = Colors.red.withOpacity(0.2);
      borderColor = Colors.red;
    } else if (isEliminated) {
      backgroundColor = Colors.white.withOpacity(0.05);
      borderColor = null;
    } else {
      backgroundColor = Colors.white.withOpacity(0.05);
      borderColor = null;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: borderColor != null ? Border.all(color: borderColor, width: 2) : null,
      ),
      child: Row(
        children: [
          // Position
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getPositionColor(result.finalPosition),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                "#${result.finalPosition}",
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          PlayerAvatar(player: result.player, size: 50),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      result.player.name,
                      style: TextStyle(
                          color: isHuman 
                              ? (isEliminated ? Colors.redAccent : Colors.lightBlueAccent) 
                              : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                    if (isHuman) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: isEliminated ? Colors.red : Colors.blue,
                            borderRadius: BorderRadius.circular(4)),
                        child: const Text("VOUS",
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 10)),
                      ),
                    ],
                    if (isWinner) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius: BorderRadius.circular(4)),
                        child: const Text("CHAMPION",
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 10)),
                      ),
                    ],
                  ],
                ),
                if (statusText.isNotEmpty)
                  Text(
                    statusText,
                    style: TextStyle(
                        color: isWinner ? Colors.amber : (isHuman ? Colors.redAccent : Colors.white54),
                        fontWeight: isWinner ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12),
                  ),
              ],
            ),
          ),
          // RP uniquement pour l'humain
          if (isHuman)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  pointsChangeText,
                  style: TextStyle(
                      color: pointsColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Color _getPositionColor(int position) {
    switch (position) {
      case 1:
        return Colors.amber.shade700;
      case 2:
        return Colors.grey.shade400;
      case 3:
        return Colors.brown.shade400;
      default:
        return Colors.red.shade700;
    }
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

    bool isTournamentEliminated =
        isTournament && rank == gs.players.length && !isWinner;

    String pointsChangeText = "";
    Color pointsColor = Colors.grey;

    if (!isSBMM) {
      pointsChangeText = "Mode Manuel";
      pointsColor = Colors.white54;
    } else if (isTournament) {
      if (gs.tournamentRound < 3 && !isTournamentEliminated) {
        pointsChangeText = "En cours...";
        pointsColor = Colors.white54;
      } else {
        int finalPosition = rank;
        if (isTournamentEliminated) {
          finalPosition = 5 - gs.tournamentRound;
        }
        int rp = gameProvider.getTournamentRP(finalPosition);
        if (rp > 0) {
          pointsChangeText = "+$rp RP";
          pointsColor = rp >= 100 ? Colors.amber : Colors.greenAccent;
        } else {
          pointsChangeText = "$rp RP";
          pointsColor = Colors.redAccent;
        }
      }
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
            ? Colors.red.withOpacity(0.2)
            : (isWinner
                ? Colors.amber.withOpacity(0.2)
                : Colors.white.withOpacity(0.05)),
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