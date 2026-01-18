import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/card.dart';
import '../providers/game_provider.dart';
import '../widgets/card_widget.dart';
import 'results_screen.dart';

class DutchRevealScreen extends StatefulWidget {
  const DutchRevealScreen({super.key});

  @override
  State<DutchRevealScreen> createState() => _DutchRevealScreenState();
}

class _DutchRevealScreenState extends State<DutchRevealScreen>
    with TickerProviderStateMixin {
  int currentCardIndex = 0; // Quelle carte on révèle (0 à max)
  Map<String, int> currentScores = {}; // Scores progressifs
  late AnimationController _flipController;
  late AnimationController _scoreController;
  String? winnerId; // ID du gagnant
  bool revealComplete = false;

  @override
  void initState() {
    super.initState();

    _flipController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scoreController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Initialiser les scores à 0
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final players = gameProvider.gameState!.players;
    for (var player in players) {
      currentScores[player.id] = 0;
    }

    // Démarrer la révélation après un court délai
    Future.delayed(const Duration(milliseconds: 1000), () {
      _revealNextCard();
    });
  }

  @override
  void dispose() {
    _flipController.dispose();
    _scoreController.dispose();
    super.dispose();
  }

  void _revealNextCard() async {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final players = gameProvider.gameState!.players;

    // Trouver le nombre max de cartes
    int maxCards = players.map((p) => p.hand.length).reduce(math.max);

    if (currentCardIndex >= maxCards) {
      // Toutes les cartes révélées, trouver le gagnant
      await Future.delayed(const Duration(milliseconds: 500));
      _highlightWinner();
      return;
    }

    // Animation de flip
    await _flipController.forward();

    setState(() {
      // Mettre à jour les scores
      for (var player in players) {
        if (currentCardIndex < player.hand.length) {
          currentScores[player.id] =
              currentScores[player.id]! + player.hand[currentCardIndex].points;
        }
      }
    });

    // Animation de score
    await _scoreController.forward();
    await _scoreController.reverse();

    // Reset flip pour la prochaine carte
    await _flipController.reverse();

    setState(() {
      currentCardIndex++;
    });

    // Petit délai avant la prochaine carte
    await Future.delayed(const Duration(milliseconds: 300));

    if (mounted) {
      _revealNextCard();
    }
  }

  void _highlightWinner() async {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final gameState = gameProvider.gameState!;
    
    // Trouver le joueur avec le plus petit score
    String? minId;
    int minScore = 999;
    
    for (var entry in currentScores.entries) {
      if (entry.value < minScore) {
        minScore = entry.value;
        minId = entry.key;
      }
    }
    
    setState(() {
      winnerId = minId;
      revealComplete = true;
    });
    
    // Attendre 2 secondes avant de passer aux résultats
    await Future.delayed(const Duration(milliseconds: 2000));
    
    // ✅ IMPORTANT : Remettre dutchCallerId à null pour éviter la boucle
    if (mounted && gameState.dutchCallerId != null) {
      debugPrint("🔄 [DutchRevealScreen] Reset dutchCallerId pour éviter la boucle");
      gameState.dutchCallerId = null; // ⚠️ On efface le flag Dutch
      
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ResultsScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<GameProvider>(
        builder: (context, gameProvider, child) {
          if (!gameProvider.hasActiveGame) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.amber));
          }

          final gameState = gameProvider.gameState!;
          final players = _orderPlayers(gameState.players);

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
                        Shadow(
                            color: Colors.black45,
                            blurRadius: 10,
                            offset: Offset(2, 2))
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

                  // Colonnes des joueurs
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: players.map((player) {
                        return _buildPlayerColumn(player, gameState);
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Ordonner les joueurs : Haut, Droite, Bas (humain), Gauche
  List<Player> _orderPlayers(List<Player> allPlayers) {
    Player human = allPlayers.firstWhere((p) => p.isHuman);
    List<Player> bots = allPlayers.where((p) => !p.isHuman).toList();

    // Si 4 joueurs : Haut (bot0), Droite (bot1), Bas (humain), Gauche (bot2)
    // Si 3 joueurs : Haut (bot0), Bas (humain), Droite (bot1)
    // Si 2 joueurs : Bas (humain), Haut (bot0)

    List<Player> ordered = [];

    if (bots.length >= 1) ordered.add(bots[0]); // Haut
    if (bots.length >= 2) ordered.add(bots[1]); // Droite
    ordered.add(human); // Bas (toujours)
    if (bots.length >= 3) ordered.add(bots[2]); // Gauche

    return ordered;
  }

  Widget _buildPlayerColumn(Player player, GameState gameState) {
    bool isWinner = winnerId == player.id;
    int displayScore = currentScores[player.id] ?? 0;
    bool isDutchCaller = gameState.dutchCallerId == player.id;

    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isWinner
              ? Colors.amber.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isWinner
                ? Colors.amber
                : (isDutchCaller
                    ? Colors.amber.withValues(alpha: 0.5)
                    : Colors.white24),
            width: isWinner ? 3 : (isDutchCaller ? 2 : 1),
          ),
          boxShadow: isWinner
              ? [
                  BoxShadow(
                    color: Colors.amber.withValues(alpha: 0.6),
                    blurRadius: 20,
                    spreadRadius: 5,
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // Avatar
            Text(
              player.displayAvatar,
              style: const TextStyle(fontSize: 40),
            ),
            const SizedBox(height: 8),

            // Nom
            Text(
              player.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            // Badge Dutch
            if (isDutchCaller) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  "DUTCH",
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Cartes
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: List.generate(player.hand.length, (index) {
                    bool isRevealed = index < currentCardIndex;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _FlipCard(
                        card: player.hand[index],
                        isRevealed: isRevealed,
                        animationValue: isRevealed
                            ? (index == currentCardIndex - 1
                                ? _flipController.value
                                : 1.0)
                            : 0.0,
                      ),
                    );
                  }),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Score
            AnimatedScale(
              scale: _scoreController.isAnimating && currentCardIndex > 0
                  ? 1.2
                  : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isWinner
                      ? Colors.amber
                      : Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "$displayScore",
                  style: TextStyle(
                    color: isWinner ? Colors.black : Colors.amber,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            if (isWinner && revealComplete) ...[
              const SizedBox(height: 8),
              const Icon(
                Icons.emoji_events,
                color: Colors.amber,
                size: 32,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Widget pour l'animation de flip
class _FlipCard extends StatelessWidget {
  final PlayingCard card;
  final bool isRevealed;
  final double animationValue;

  const _FlipCard({
    required this.card,
    required this.isRevealed,
    required this.animationValue,
  });

  @override
  Widget build(BuildContext context) {
    // Animation de rotation 3D
    final angle = animationValue * math.pi;
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.001) // Perspective
      ..rotateY(angle);

    // Déterminer quelle face montrer
    bool showFront = animationValue > 0.5;

    return Transform(
      transform: transform,
      alignment: Alignment.center,
      child: showFront && isRevealed
          ? Transform(
              transform: Matrix4.rotationY(math.pi), // Flip la face avant
              alignment: Alignment.center,
              child: CardWidget(
                card: card,
                size: CardSize.small,
                isRevealed: true,
              ),
            )
          : CardWidget(
              card: null, // Dos de carte
              size: CardSize.small,
              isRevealed: false,
            ),
    );
  }
}
