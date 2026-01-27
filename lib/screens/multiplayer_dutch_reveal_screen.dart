import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import '../models/game_state.dart';
import '../models/player.dart';
import '../providers/multiplayer_game_provider.dart';
import '../widgets/card_widget.dart';
import 'multiplayer_results_screen.dart';
import 'multiplayer_lobby_screen.dart';

class MultiplayerDutchRevealScreen extends StatefulWidget {
  const MultiplayerDutchRevealScreen({super.key});

  @override
  State<MultiplayerDutchRevealScreen> createState() => _MultiplayerDutchRevealScreenState();
}

class _MultiplayerDutchRevealScreenState extends State<MultiplayerDutchRevealScreen>
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

    final gameProvider = Provider.of<MultiplayerGameProvider>(context, listen: false);
    for (var player in gameProvider.gameState!.players) {
      currentScores[player.id] = 0;
      _scrollControllers[player.id] = ScrollController();
    }

    Future.delayed(const Duration(milliseconds: 800), _startRevealSequence);
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
    final gameProvider = Provider.of<MultiplayerGameProvider>(context, listen: false);
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
    final gameProvider = Provider.of<MultiplayerGameProvider>(context, listen: false);
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

    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => MultiplayerResultsScreen(
          gameState: gameProvider.gameState!,
          localPlayerId: gameProvider.playerId,
        )),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenHeight < 400;

    return Scaffold(
      body: Consumer<MultiplayerGameProvider>(
        builder: (context, gameProvider, child) {
          // Si la room a été redémarrée, naviguer vers le lobby
          if (gameProvider.isInLobby && !gameProvider.isPlaying && gameProvider.roomCode != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && ModalRoute.of(context)?.isCurrent == true) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const MultiplayerLobbyScreen()),
                );
              }
            });
            return const SizedBox();
          }

          if (!gameProvider.isPlaying || gameProvider.gameState == null) return const SizedBox();

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
                  const SizedBox(height: 12),
                  Expanded(
                    child: Row(
                      children: players.map((p) => _buildPlayerColumn(p, gameState, isCompact)).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
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
          color: isWinner ? Colors.amber.withValues(alpha: 0.12) : Colors.black12,
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
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: _scrollControllers[player.id],
                itemCount: player.hand.length,
                itemBuilder: (context, index) {
                  final card = player.hand[index];
                  final revealed = index <= currentRevealIndex;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: CardWidget(card: revealed ? card : null, size: CardSize.small, isRevealed: revealed),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            AnimatedBuilder(
              animation: _scorePopController,
              builder: (context, child) {
                double scale = 1.0 + (_scorePopController.value * 0.25);
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(6)),
                    child: Text('$score pts', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
}
