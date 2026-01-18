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
  int currentCardIndex = 0;
  Map<String, int> currentScores = {};
  late AnimationController _flipController;
  late AnimationController _scoreController;
  String? winnerId;
  bool revealComplete = false;
  bool isFlipping = false;
  
  // ✅ NOUVEAU : Un controller par colonne pour synchroniser manuellement
  Map<String, ScrollController> _scrollControllers = {};
  
  // ✅ NOUVEAU : Hauteur fixe d'une "case" de grille
  static const double GRID_CELL_HEIGHT = 68.0; // Carte (64px) + espacement (4px)

  @override
  void initState() {
    super.initState();
    
    debugPrint("🎬 [DutchRevealScreen] INIT");

    _flipController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scoreController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final players = gameProvider.gameState!.players;
    
    debugPrint("   - Nombre de joueurs: ${players.length}");
    
    for (var player in players) {
      currentScores[player.id] = 0;
      // ✅ Créer un controller par joueur
      _scrollControllers[player.id] = ScrollController();
      debugPrint("   - Controller créé pour ${player.name}");
    }

    Future.delayed(const Duration(milliseconds: 1500), () {
      debugPrint("🎬 Début de la révélation");
      _revealNextCardColumn();
    });
  }

  @override
  void dispose() {
    debugPrint("🎬 [DutchRevealScreen] DISPOSE");
    _flipController.dispose();
    _scoreController.dispose();
    // ✅ Disposer tous les scroll controllers
    for (var controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // ✅ NOUVEAU : Scroll synchronisé de TOUTES les colonnes en même temps
  Future<void> _scrollToNextGridCell() async {
    debugPrint("📜 [_scrollToNextGridCell] DEBUT");
    debugPrint("   - currentCardIndex: $currentCardIndex");
    debugPrint("   - Nombre de controllers: ${_scrollControllers.length}");
    
    if (!mounted) {
      debugPrint("   ❌ Widget non monté");
      return;
    }
    
    if (_scrollControllers.isEmpty) {
      debugPrint("   ❌ Pas de scroll controllers");
      return;
    }

    double targetOffset = GRID_CELL_HEIGHT * currentCardIndex;
    debugPrint("   - Target offset: $targetOffset");
    
    // ✅ Animer TOUTES les colonnes ensemble vers la même position
    List<Future> animations = [];
    
    for (var entry in _scrollControllers.entries) {
      String playerId = entry.key;
      ScrollController controller = entry.value;
      
      if (!controller.hasClients) {
        debugPrint("   ⚠️ Controller pour $playerId n'a pas de clients");
        continue;
      }
      
      debugPrint("   - Animation pour $playerId vers $targetOffset");
      
      animations.add(
        controller.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        ),
      );
    }
    
    if (animations.isNotEmpty) {
      debugPrint("   ✅ Lancement de ${animations.length} animations");
      await Future.wait(animations);
      debugPrint("   ✅ Animations terminées");
    } else {
      debugPrint("   ⚠️ Aucune animation à lancer");
    }
  }

  void _revealNextCardColumn() async {
    debugPrint("🎴 [_revealNextCardColumn] DEBUT - Index: $currentCardIndex");
    
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final players = gameProvider.gameState!.players;

    int maxCards = players.map((p) => p.hand.length).reduce(math.max);
    debugPrint("   - Max cartes: $maxCards");

    if (currentCardIndex >= maxCards) {
      debugPrint("   ✅ Toutes les cartes révélées");
      await Future.delayed(const Duration(milliseconds: 800));
      _highlightWinner();
      return;
    }

    // ✅ NOUVEAU : Scroller AVANT le flip (toutes les colonnes ensemble)
    debugPrint("   📜 Scroll vers index $currentCardIndex");
    await _scrollToNextGridCell();

    debugPrint("   🔄 Début flip");
    setState(() {
      isFlipping = true;
    });

    await _flipController.forward();

    debugPrint("   ✅ Flip terminé, mise à jour des scores");
    setState(() {
      isFlipping = false;
      
      // Mettre à jour les scores
      for (var player in players) {
        if (currentCardIndex < player.hand.length) {
          int cardPoints = player.hand[currentCardIndex].points;
          currentScores[player.id] = currentScores[player.id]! + cardPoints;
          debugPrint("   - ${player.name}: +$cardPoints pts = ${currentScores[player.id]}");
        }
      }
    });

    await _scoreController.forward();
    await _scoreController.reverse();
    await _flipController.reverse();

    setState(() {
      currentCardIndex++;
    });

    debugPrint("   ⏸️ Pause 600ms");
    await Future.delayed(const Duration(milliseconds: 600));

    if (mounted) {
      debugPrint("   ➡️ Carte suivante");
      _revealNextCardColumn();
    } else {
      debugPrint("   ❌ Widget non monté, arrêt");
    }
  }

  void _highlightWinner() async {
    debugPrint("🏆 [_highlightWinner] DEBUT");
    
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final gameState = gameProvider.gameState!;
    
    String? minId;
    int minScore = 999;
    
    for (var entry in currentScores.entries) {
      debugPrint("   - ${entry.key}: ${entry.value} pts");
      if (entry.value < minScore) {
        minScore = entry.value;
        minId = entry.key;
      }
    }
    
    debugPrint("   🏆 Gagnant: $minId avec $minScore pts");
    
    setState(() {
      winnerId = minId;
      revealComplete = true;
    });
    
    await Future.delayed(const Duration(milliseconds: 2000));
    
    if (mounted && gameState.dutchCallerId != null) {
      debugPrint("🔄 [DutchRevealScreen] Reset dutchCallerId pour éviter la boucle");
      gameState.dutchCallerId = null;
      
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

                  // ✅ NOUVEAU : Grille synchronisée
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

  List<Player> _orderPlayers(List<Player> allPlayers) {
    Player human = allPlayers.firstWhere((p) => p.isHuman);
    List<Player> bots = allPlayers.where((p) => !p.isHuman).toList();

    List<Player> ordered = [];

    if (bots.length >= 1) ordered.add(bots[0]);
    if (bots.length >= 2) ordered.add(bots[1]);
    ordered.add(human);
    if (bots.length >= 3) ordered.add(bots[2]);

    return ordered;
  }

  Widget _buildPlayerColumn(Player player, GameState gameState) {
    bool isWinner = winnerId == player.id;
    int displayScore = currentScores[player.id] ?? 0;
    bool isDutchCaller = gameState.dutchCallerId == player.id;
    
    // ✅ NOUVEAU : Détecter si le joueur n'a plus de cartes à révéler
    bool hasNoMoreCards = currentCardIndex >= player.hand.length;

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

            // ✅ NOUVEAU : Grille de cartes synchronisée
            Expanded(
              child: Stack(
                children: [
                  // Liste scrollable des cartes
                  SingleChildScrollView(
                    controller: _scrollControllers[player.id],
                    physics: const NeverScrollableScrollPhysics(), // Scroll contrôlé
                    child: Column(
                      children: List.generate(player.hand.length, (index) {
                        bool isRevealed = index < currentCardIndex;
                        return Container(
                          height: GRID_CELL_HEIGHT,
                          alignment: Alignment.center,
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
                  
                  // ✅ NOUVEAU : Indicateur visuel si plus de cartes
                  if (hasNoMoreCards && !revealComplete)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.red.withValues(alpha: 0.0),
                              Colors.red,
                              Colors.red.withValues(alpha: 0.0),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.6),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
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
    final angle = animationValue * math.pi;
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.001)
      ..rotateY(angle);

    bool showFront = animationValue > 0.5;

    return Transform(
      transform: transform,
      alignment: Alignment.center,
      child: showFront && isRevealed
          ? Transform(
              transform: Matrix4.rotationY(math.pi),
              alignment: Alignment.center,
              child: CardWidget(
                card: card,
                size: CardSize.small,
                isRevealed: true,
              ),
            )
          : CardWidget(
              card: null,
              size: CardSize.small,
              isRevealed: false,
            ),
    );
  }
}