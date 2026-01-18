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
  // ðŸ“ CONSTANTES DE TAILLE (Fixes pour garantir l'alignement)
  static const double CARD_HEIGHT = 64.0;
  static const double CARD_SPACING = 2.0;
  static const double SCROLL_STEP = CARD_HEIGHT + CARD_SPACING;

  int currentRevealIndex = -1; // -1 = rien rÃ©vÃ©lÃ©
  Map<String, int> currentScores = {};
  
  // ContrÃ´leurs d'animation
  late AnimationController _flipController;
  late AnimationController _scorePopController;
  
  // ContrÃ´leurs de scroll (un par joueur)
  final Map<String, ScrollController> _scrollControllers = {};

  String? winnerId;
  bool revealComplete = false;

  @override
  void initState() {
    super.initState();
    debugPrint("ðŸŽ¬ [DutchRevealScreen] INIT - Nouvelle logique synchronisÃ©e");

    _flipController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scorePopController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Initialisation des scores Ã  0 et des controllers
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    for (var player in gameProvider.gameState!.players) {
      currentScores[player.id] = 0;
      _scrollControllers[player.id] = ScrollController();
    }

    // DÃ©marrage de la sÃ©quence aprÃ¨s un court dÃ©lai
    Future.delayed(const Duration(milliseconds: 1000), _startRevealSequence);
  }

  @override
  void dispose() {
    _flipController.dispose();
    _scorePopController.dispose();
    for (var controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _startRevealSequence() async {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final players = gameProvider.gameState!.players;
    
    // Trouver le nombre max de cartes Ã  rÃ©vÃ©ler
    int maxCards = players.map((p) => p.hand.length).reduce(math.max);
    debugPrint("ðŸŒŠ Nombre de vagues Ã  rÃ©vÃ©ler : $maxCards");

    for (int waveIndex = 0; waveIndex < maxCards; waveIndex++) {
      debugPrint("ðŸŒŠ VAGUE #$waveIndex");

      // 1. SCROLL : Faire descendre ceux qui ont encore des cartes (ou qui viennent de finir)
      await _animateScroll(waveIndex, players);

      // 2. RÃ‰VÃ‰LATION : Mettre Ã  jour l'index global pour dÃ©clencher les flips
      setState(() {
        currentRevealIndex = waveIndex;
      });
      await _flipController.forward(from: 0.0);

      // 3. SCORE : Calculer et animer les points
      setState(() {
        for (var player in players) {
          if (waveIndex < player.hand.length) {
            currentScores[player.id] = (currentScores[player.id] ?? 0) + player.hand[waveIndex].points;
          }
        }
      });
      await _scorePopController.forward(from: 0.0);

      // Petite pause pour admirer le rÃ©sultat
      await Future.delayed(const Duration(milliseconds: 600));
    }

    // Fin de la sÃ©quence
    _highlightWinner();
  }

  Future<void> _animateScroll(int targetIndex, List<Player> players) async {
    List<Future> scrollAnimations = [];
    double targetOffset = targetIndex * SCROLL_STEP;

    for (var player in players) {
      // On ne scrolle que si le joueur a encore des cartes ou vient juste de finir (pour afficher le trait rouge)
      // Si targetIndex > hand.length, on ne scrolle plus, on reste sur le trait rouge
      if (targetIndex <= player.hand.length) {
        if (_scrollControllers.containsKey(player.id) && _scrollControllers[player.id]!.hasClients) {
          scrollAnimations.add(
            _scrollControllers[player.id]!.animateTo(
              targetOffset,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOutCubic,
            ),
          );
        }
      }
    }

    if (scrollAnimations.isNotEmpty) {
      await Future.wait(scrollAnimations);
    }
  }

  void _highlightWinner() async {
    debugPrint("ðŸ† Calcul du vainqueur...");
    
    // 1. Trouver le score minimum
    int minScore = 999;
    for (var score in currentScores.values) {
      if (score < minScore) minScore = score;
    }

    // 2. Trouver les gagnants potentiels (cas d'Ã©galitÃ©)
    List<String> winners = [];
    currentScores.forEach((id, score) {
      if (score == minScore) winners.add(id);
    });

    // 3. Gestion de la prioritÃ© au Dutch Caller
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    String? finalWinnerId;
    
    if (gameProvider.gameState!.dutchCallerId != null && 
        winners.contains(gameProvider.gameState!.dutchCallerId)) {
      finalWinnerId = gameProvider.gameState!.dutchCallerId;
    } else {
      finalWinnerId = winners.isNotEmpty ? winners.first : null;
    }

    setState(() {
      winnerId = finalWinnerId;
      revealComplete = true;
    });

    // Navigation vers les rÃ©sultats aprÃ¨s dÃ©lai
    await Future.delayed(const Duration(milliseconds: 2500));
    if (mounted) {
      // Reset pour Ã©viter les boucles
      // ✅ FIX BUG : Ne PAS réinitialiser dutchCallerId ici !
      // Sinon ResultsScreen ne peut pas détecter qui a appelé Dutch
      // La réinitialisation se fera dans quitGame() ou au début de la prochaine partie
      // gameProvider.gameState!.dutchCallerId = null;
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
          if (!gameProvider.hasActiveGame) return const SizedBox();

          final gameState = gameProvider.gameState!;
          // Ordonner : Bots, Humain, Bots
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
                  // En-tÃªte
                  const Text("DUTCH !",
                      style: TextStyle(
                          fontFamily: 'Rye', fontSize: 40, color: Colors.amber)),
                  const SizedBox(height: 20),

                  // GRILLE DES JOUEURS
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: players.map((p) => _buildPlayerColumn(p, gameState)).toList(),
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

  Widget _buildPlayerColumn(Player player, GameState gameState) {
    bool isWinner = winnerId == player.id;
    bool isDutchCaller = gameState.dutchCallerId == player.id;
    int score = currentScores[player.id] ?? 0;

    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isWinner ? Colors.amber.withOpacity(0.2) : Colors.black12,
          borderRadius: BorderRadius.circular(12),
          border: isWinner ? Border.all(color: Colors.amber, width: 2) : null,
        ),
        child: Column(
          children: [
            // AVATAR & INFO
            Text(player.displayAvatar, style: const TextStyle(fontSize: 32)),
            Text(player.name,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
            if (isDutchCaller)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(4)),
                child: const Text("DUTCH", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
              ),
            
            const SizedBox(height: 10),

            // LISTE DÃ‰FILANTE DES CARTES
            Expanded(
              child: Stack(
                children: [
                  // Masque pour cacher les cartes non scrollÃ©es
                  Positioned.fill(
                    child: ShaderMask(
                      shaderCallback: (Rect bounds) {
                        return const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                          stops: [0.0, 0.1, 0.8, 1.0],
                        ).createShader(bounds);
                      },
                      blendMode: BlendMode.dstIn,
                      child: ListView.builder(
                        controller: _scrollControllers[player.id],
                        physics: const NeverScrollableScrollPhysics(), // Scroll manuel uniquement
                        padding: const EdgeInsets.only(top: SCROLL_STEP), // Espace initial
                        itemCount: player.hand.length + 1, // +1 pour l'espace du trait rouge final
                        itemBuilder: (context, index) {
                          // Cas : Trait rouge de fin
                          if (index == player.hand.length) {
                            // On affiche le trait rouge seulement si on a dÃ©passÃ© la derniÃ¨re carte
                            // ET que le reveal est assez avancÃ©
                            bool showRedLine = currentRevealIndex >= player.hand.length;
                            return AnimatedOpacity(
                              duration: const Duration(milliseconds: 300),
                              opacity: showRedLine ? 1.0 : 0.0,
                              child: Container(
                                height: SCROLL_STEP,
                                alignment: Alignment.topCenter,
                                padding: const EdgeInsets.only(top: 10),
                                child: Container(
                                  width: 40,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    borderRadius: BorderRadius.circular(2),
                                    boxShadow: [
                                      BoxShadow(color: Colors.red.withOpacity(0.5), blurRadius: 4, spreadRadius: 1)
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }

                          // Cas : Carte normale
                          bool shouldReveal = index <= currentRevealIndex;
                          // On anime le flip uniquement si c'est la vague actuelle
                          double animValue = (index == currentRevealIndex) ? _flipController.value : (shouldReveal ? 1.0 : 0.0);

                          return SizedBox(
                            height: SCROLL_STEP,
                            child: Center(
                              child: _FlipCard(
                                card: player.hand[index],
                                isRevealed: shouldReveal,
                                animationValue: animValue,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // SCORE AVEC EFFET RESSORT
            AnimatedBuilder(
              animation: _scorePopController,
              builder: (context, child) {
                // Effet de scale : grossit puis revient
                double scale = 1.0;
                if (_scorePopController.value < 0.5) {
                  scale = 1.0 + (_scorePopController.value * 0.4); // Max 1.2
                } else {
                  scale = 1.2 - ((_scorePopController.value - 0.5) * 0.4); // Retour Ã  1.0
                }
                
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isWinner ? Colors.amber : Colors.black45,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "$score",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isWinner ? Colors.black : Colors.amber,
                      ),
                    ),
                  ),
                );
              },
            ),
            
            if (isWinner && revealComplete)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Icon(Icons.emoji_events, color: Colors.amber),
              ),
          ],
        ),
      ),
    );
  }
  
  // Utilitaire pour l'ordre d'affichage
  List<Player> _orderPlayers(List<Player> allPlayers) {
    Player human = allPlayers.firstWhere((p) => p.isHuman);
    List<Player> bots = allPlayers.where((p) => !p.isHuman).toList();
    List<Player> ordered = [];
    if (bots.isNotEmpty) ordered.add(bots[0]);
    if (bots.length > 1) ordered.add(bots[1]);
    ordered.add(human);
    if (bots.length > 2) ordered.add(bots[2]);
    return ordered;
  }
}

// Widget simple pour gÃ©rer la rotation 3D
class _FlipCard extends StatelessWidget {
  final PlayingCard card;
  final bool isRevealed;
  final double animationValue;

  const _FlipCard({required this.card, required this.isRevealed, required this.animationValue});

  @override
  Widget build(BuildContext context) {
    final angle = animationValue * math.pi;
    final transform = Matrix4.identity()..setEntry(3, 2, 0.001)..rotateY(angle);
    bool showFront = animationValue > 0.5; // On change la face Ã  90 degrÃ©s

    return Transform(
      transform: transform,
      alignment: Alignment.center,
      child: showFront && isRevealed
          ? Transform(
              transform: Matrix4.rotationY(math.pi), // Miroir pour lire dans le bon sens
              alignment: Alignment.center,
              child: CardWidget(card: card, size: CardSize.small, isRevealed: true),
            )
          : const CardWidget(card: null, size: CardSize.small, isRevealed: false),
    );
  }
}