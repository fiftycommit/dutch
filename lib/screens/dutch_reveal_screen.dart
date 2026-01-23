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
  static const double cardHeight = 64.0;
  static const double cardSpacing = 2.0;
  static const double scrollStep = cardHeight + cardSpacing;

  int currentRevealIndex = -1; // -1 = rien révélé
  Map<String, int> currentScores = {};

  late AnimationController _flipController;
  late AnimationController _scorePopController;
  final Map<String, ScrollController> _scrollControllers = {};

  String? winnerId;
  bool revealComplete = false;

  @override
  void initState() {
    super.initState();

    _flipController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scorePopController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    for (var player in gameProvider.gameState!.players) {
      currentScores[player.id] = 0;
      _scrollControllers[player.id] = ScrollController();
    }

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
    int maxCards = players.map((p) => p.hand.length).reduce(math.max);

    for (int waveIndex = 0; waveIndex < maxCards; waveIndex++) {
      await _animateScroll(waveIndex, players);

      setState(() => currentRevealIndex = waveIndex);
      await _flipController.forward(from: 0.0);
      setState(() {
        for (var player in players) {
          if (waveIndex < player.hand.length) {
            currentScores[player.id] = (currentScores[player.id] ?? 0) + player.hand[waveIndex].points;
          }
        }
      });
      await _scorePopController.forward(from: 0.0);
      await Future.delayed(const Duration(milliseconds: 600));
    }

    _highlightWinner();
  }

  Future<void> _animateScroll(int targetIndex, List<Player> players) async {
    List<Future> scrollAnimations = [];
    double targetOffset = targetIndex * scrollStep;

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
    int minScore = currentScores.values.reduce((a, b) => a < b ? a : b);
    List<String> winners = currentScores.entries
        .where((e) => e.value == minScore)
        .map((e) => e.key)
        .toList();
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

    // Navigation vers les résultats après délai
    await Future.delayed(const Duration(milliseconds: 2500));
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ResultsScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenHeight < 400;
    
    return Scaffold(
      body: Consumer<GameProvider>(
        builder: (context, gameProvider, child) {
          if (!gameProvider.hasActiveGame) return const SizedBox();

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
                  SizedBox(height: isCompact ? 5 : 20),
                  Text("DUTCH !",
                      style: TextStyle(
                          fontFamily: 'Rye', fontSize: isCompact ? 24 : 40, color: Colors.amber)),
                  SizedBox(height: isCompact ? 5 : 20),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: players.map((p) => _buildPlayerColumn(p, gameState, isCompact)).toList(),
                    ),
                  ),
                  SizedBox(height: isCompact ? 5 : 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlayerColumn(Player player, GameState gameState, bool isCompact) {
    bool isWinner = winnerId == player.id;
    bool isDutchCaller = gameState.dutchCallerId == player.id;
    int score = currentScores[player.id] ?? 0;

    return Expanded(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: isCompact ? 2 : 4),
        padding: EdgeInsets.all(isCompact ? 4 : 8),
        decoration: BoxDecoration(
          color: isWinner ? Colors.amber.withValues(alpha: 0.2) : Colors.black12,
          borderRadius: BorderRadius.circular(12),
          border: isWinner ? Border.all(color: Colors.amber, width: 2) : null,
        ),
        child: Column(
          children: [
            Text(player.displayAvatar, style: TextStyle(fontSize: isCompact ? 20 : 32)),
            Text(player.name,
                style: TextStyle(color: Colors.white, fontSize: isCompact ? 9 : 12, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
            if (isDutchCaller)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(4)),
                child: Text("DUTCH", style: TextStyle(fontSize: isCompact ? 6 : 8, fontWeight: FontWeight.bold)),
              ),
            
            SizedBox(height: isCompact ? 4 : 10),
            Expanded(
              child: Stack(
                children: [
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
                        physics: const NeverScrollableScrollPhysics(),
                        // ignore: prefer_const_constructors
                        padding: EdgeInsets.only(top: isCompact ? scrollStep * 0.6 : scrollStep),
                        itemCount: player.hand.length + 1,
                        itemBuilder: (context, index) {
                          if (index == player.hand.length) {
                            bool showRedLine = currentRevealIndex >= player.hand.length;
                            return AnimatedOpacity(
                              duration: const Duration(milliseconds: 300),
                              opacity: showRedLine ? 1.0 : 0.0,
                              child: Container(
                                height: isCompact ? scrollStep * 0.6 : scrollStep,
                                alignment: Alignment.topCenter,
                                padding: const EdgeInsets.only(top: 10),
                                child: Container(
                                  width: isCompact ? 30 : 40,
                                  height: isCompact ? 3 : 4,
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    borderRadius: BorderRadius.circular(2),
                                    boxShadow: [
                                      BoxShadow(color: Colors.red.withValues(alpha: 0.5), blurRadius: 4, spreadRadius: 1)
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }

                          bool shouldReveal = index <= currentRevealIndex;
                          double animValue = (index == currentRevealIndex) ? _flipController.value : (shouldReveal ? 1.0 : 0.0);

                          return SizedBox(
                            height: isCompact ? scrollStep * 0.6 : scrollStep,
                            child: Center(
                              child: _FlipCard(
                                card: player.hand[index],
                                isRevealed: shouldReveal,
                                animationValue: animValue,
                                isCompact: isCompact,
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

            SizedBox(height: isCompact ? 4 : 10),
            AnimatedBuilder(
              animation: _scorePopController,
              builder: (context, child) {
                double scale = 1.0;
                if (_scorePopController.value < 0.5) {
                  scale = 1.0 + (_scorePopController.value * 0.4);
                } else {
                  scale = 1.2 - ((_scorePopController.value - 0.5) * 0.4);
                }
                
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 10 : 16,
                      vertical: isCompact ? 4 : 8,
                    ),
                    decoration: BoxDecoration(
                      color: isWinner ? Colors.amber : Colors.black45,
                      borderRadius: BorderRadius.circular(isCompact ? 8 : 12),
                    ),
                    child: Text(
                      "$score",
                      style: TextStyle(
                        fontSize: isCompact ? 16 : 24,
                        fontWeight: FontWeight.bold,
                        color: isWinner ? Colors.black : Colors.amber,
                      ),
                    ),
                  ),
                );
              },
            ),
            
            if (isWinner && revealComplete)
              Padding(
                padding: EdgeInsets.only(top: isCompact ? 4.0 : 8.0),
                child: Icon(Icons.emoji_events, color: Colors.amber, size: isCompact ? 16 : 24),
              ),
          ],
        ),
      ),
    );
  }

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

class _FlipCard extends StatelessWidget {
  final PlayingCard card;
  final bool isRevealed;
  final double animationValue;
  final bool isCompact;

  const _FlipCard({
    required this.card,
    required this.isRevealed,
    required this.animationValue,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final angle = animationValue * math.pi;
    final transform = Matrix4.identity()..setEntry(3, 2, 0.001)..rotateY(angle);
    bool showFront = animationValue > 0.5;
    final cardSize = isCompact ? CardSize.tiny : CardSize.small;

    return Transform(
      transform: transform,
      alignment: Alignment.center,
      child: showFront && isRevealed
          ? Transform(
              transform: Matrix4.rotationY(math.pi),
              alignment: Alignment.center,
              child: CardWidget(card: card, size: cardSize, isRevealed: true),
            )
          : CardWidget(card: null, size: cardSize, isRevealed: false),
    );
  }
}