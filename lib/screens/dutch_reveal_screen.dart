import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../providers/game_provider.dart';
import '../widgets/card_widget.dart';
import '../widgets/player_avatar.dart';
import 'results_screen.dart';

/// Écran intermédiaire qui affiche toutes les cartes révélées après l'appel de Dutch
/// Avant de passer à l'écran des résultats
class DutchRevealScreen extends StatefulWidget {
  const DutchRevealScreen({super.key});

  @override
  State<DutchRevealScreen> createState() => _DutchRevealScreenState();
}

class _DutchRevealScreenState extends State<DutchRevealScreen> {
  @override
  void initState() {
    super.initState();
    // Naviguer automatiquement vers ResultsScreen après 4 secondes
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ResultsScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<GameProvider>(
        builder: (context, gameProvider, child) {
          if (!gameProvider.hasActiveGame) {
            return const Center(child: CircularProgressIndicator(color: Colors.amber));
          }

          final gameState = gameProvider.gameState!;
          final players = gameState.players;

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
                  const SizedBox(height: 20),
                  
                  // Titre
                  const Icon(Icons.campaign, size: 60, color: Colors.amber),
                  const SizedBox(height: 10),
                  const Text(
                    "DUTCH !",
                    style: TextStyle(
                      fontFamily: 'Rye',
                      fontSize: 48,
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(color: Colors.black45, blurRadius: 10, offset: Offset(2, 2))
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 10),
                  
                  Text(
                    "${gameState.players.firstWhere((p) => p.id == gameState.dutchCallerId).name} a crié Dutch !",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 18,
                    ),
                  ),
                  
                  const SizedBox(height: 30),
                  
                  // Liste des joueurs avec leurs cartes révélées
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: players.length,
                      itemBuilder: (context, index) {
                        final player = players[index];
                        final score = gameState.getFinalScore(player);
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: player.id == gameState.dutchCallerId 
                                  ? Colors.amber 
                                  : Colors.white24,
                              width: player.id == gameState.dutchCallerId ? 3 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              // Avatar et nom
                              Row(
                                children: [
                                  PlayerAvatar(player: player, size: 40),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          player.name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (player.id == gameState.dutchCallerId)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.amber,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              "DUTCH",
                                              style: TextStyle(
                                                color: Colors.black,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  // Score
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      "$score pts",
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              
                              const SizedBox(height: 16),
                              
                              // Cartes révélées
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: player.hand.map((card) {
                                  return CardWidget(
                                    card: card,
                                    size: CardSize.medium,
                                    isRevealed: true,
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  
                  // Indicateur de progression
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          "Résultats dans quelques secondes...",
                          style: TextStyle(color: Colors.white54, fontSize: 14),
                        ),
                        SizedBox(height: 10),
                        SizedBox(
                          width: 200,
                          child: LinearProgressIndicator(
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                          ),
                        ),
                      ],
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
}