import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../models/game_state.dart';
import '../../models/player.dart';
import '../../widgets/game/card_widget.dart';
import '../../widgets/game/flip_card_widget.dart';
import '../../utils/ui_constants.dart';

/// Configuration pour l'écran de révélation Dutch
class DutchRevealConfig {
  final GameState gameState;
  final Widget Function(BuildContext context) buildResultsScreen;
  final void Function(BuildContext context)? navigateToResults;
  final Widget? Function(BuildContext context)? buildLobbyRedirect;
  final void Function(BuildContext context)? navigateToLobbyRedirect;
  final bool Function()? shouldRedirectToLobby;
  final List<Player> Function(List<Player>)? orderPlayers;

  const DutchRevealConfig({
    required this.gameState,
    required this.buildResultsScreen,
    this.navigateToResults,
    this.buildLobbyRedirect,
    this.navigateToLobbyRedirect,
    this.shouldRedirectToLobby,
    this.orderPlayers,
  });
}

/// Écran de révélation Dutch unifié (solo + multiplayer)
class DutchRevealScreen extends StatefulWidget {
  final DutchRevealConfig config;

  const DutchRevealScreen({super.key, required this.config});

  @override
  State<DutchRevealScreen> createState() => _DutchRevealScreenState();
}

class _DutchRevealScreenState extends State<DutchRevealScreen>
    with TickerProviderStateMixin {
  int _currentRevealIndex = -1;
  final Map<String, int> _currentScores = {};

  late AnimationController _flipController;
  late AnimationController _scorePopController;
  final ScrollController _gridScrollController = ScrollController();

  String? _winnerId;
  String? _eliminatedId;
  bool _revealComplete = false;

  // Clé pour mesurer la zone scrollable
  final GlobalKey _scrollAreaKey = GlobalKey();

  GameState get gameState => widget.config.gameState;

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

    for (var player in gameState.players) {
      _currentScores[player.id] = 0;
    }

    Future.delayed(const Duration(milliseconds: 800), _startRevealSequence);
  }

  @override
  void dispose() {
    _flipController.dispose();
    _scorePopController.dispose();
    _gridScrollController.dispose();
    super.dispose();
  }

  Future<void> _startRevealSequence() async {
    final players = gameState.players;
    int maxCards = players.map((p) => p.hand.length).reduce(math.max);

    for (int waveIndex = 0; waveIndex < maxCards; waveIndex++) {
      setState(() => _currentRevealIndex = waveIndex);

      // Scroll si le rang courant dépasse la zone visible
      await _ensureRowVisible(waveIndex);

      await _flipController.forward(from: 0.0);
      setState(() {
        for (var player in players) {
          if (waveIndex < player.hand.length) {
            _currentScores[player.id] =
                (_currentScores[player.id] ?? 0) + player.hand[waveIndex].points;
          }
        }
      });
      await _scorePopController.forward(from: 0.0);
      await Future.delayed(const Duration(milliseconds: 600));
    }

    _highlightWinner();
  }

  Future<void> _ensureRowVisible(int rowIndex) async {
    if (!_gridScrollController.hasClients) return;

    final scrollArea = _scrollAreaKey.currentContext;
    if (scrollArea == null) return;
    final viewportHeight = scrollArea.size?.height ?? 0;
    if (viewportHeight <= 0) return;

    // Estimer la position du bas du rang courant
    final maxOffset = _gridScrollController.position.maxScrollExtent;
    final players = gameState.players;
    final maxCards = players.map((p) => p.hand.length).reduce(math.max);
    if (maxCards <= 0) return;

    // Hauteur totale du contenu scrollable
    final totalContentHeight = _gridScrollController.position.maxScrollExtent + viewportHeight;
    final rowHeight = totalContentHeight / maxCards;
    final rowBottom = (rowIndex + 1) * rowHeight;
    final currentBottom = _gridScrollController.offset + viewportHeight;

    if (rowBottom > currentBottom) {
      final targetOffset = (rowBottom - viewportHeight).clamp(0.0, maxOffset);
      await _gridScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _highlightWinner() async {
    int minScore = _currentScores.values.reduce((a, b) => a < b ? a : b);
    List<String> winners = _currentScores.entries
        .where((e) => e.value == minScore)
        .map((e) => e.key)
        .toList();

    String? finalWinnerId;
    if (gameState.dutchCallerId != null &&
        winners.contains(gameState.dutchCallerId)) {
      finalWinnerId = gameState.dutchCallerId;
    } else {
      finalWinnerId = winners.isNotEmpty ? winners.first : null;
    }

    String? finalEliminatedId;
    if (gameState.gameMode == GameMode.tournament) {
      final ranking = gameState.getFinalRanking();
      finalEliminatedId = ranking.isNotEmpty ? ranking.last.id : null;
    }

    setState(() {
      _winnerId = finalWinnerId;
      _eliminatedId = finalEliminatedId;
      _revealComplete = true;
    });

    await Future.delayed(const Duration(milliseconds: 2000));
    if (mounted) {
      if (widget.config.navigateToResults != null) {
        widget.config.navigateToResults!(context);
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: widget.config.buildResultsScreen),
      );
    }
  }

  List<Player> _getOrderedPlayers() {
    final players = gameState.players;
    if (widget.config.orderPlayers != null) {
      return widget.config.orderPlayers!(players);
    }
    return players;
  }

  @override
  Widget build(BuildContext context) {
    // Check for lobby redirect (multiplayer)
    if (widget.config.shouldRedirectToLobby?.call() == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          if (widget.config.navigateToLobbyRedirect != null) {
            widget.config.navigateToLobbyRedirect!(context);
            return;
          }
          final lobbyScreen = widget.config.buildLobbyRedirect?.call(context);
          if (lobbyScreen != null) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => lobbyScreen),
            );
          }
        }
      });
      return const SizedBox();
    }

    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenHeight < 400;
    final players = _getOrderedPlayers();
    final maxCards = players.map((p) => p.hand.length).reduce(math.max);

    return Scaffold(
      body: Container(
        decoration: AppDecorations.pageBackground,
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(height: isCompact ? 5 : 12),
              Text(
                "DUTCH !",
                style: TextStyle(
                  fontFamily: 'Rye',
                  fontSize: isCompact ? 24 : 36,
                  color: Colors.amber,
                ),
              ),
              SizedBox(height: isCompact ? 5 : 10),

              // En-têtes joueurs (fixes)
              _buildPlayerHeaders(players, isCompact),
              SizedBox(height: isCompact ? 4 : 8),

              // Grille de cartes avec fonds de colonnes
              Expanded(
                key: _scrollAreaKey,
                child: Stack(
                  children: [
                    // Fonds de colonnes (alternance + highlight gagnant/perdant)
                    Row(
                      children: List.generate(players.length, (i) {
                        final player = players[i];
                        final isWinner = _winnerId == player.id;
                        final isEliminated = _revealComplete && _eliminatedId == player.id;
                        Color bgColor;
                        if (isWinner) {
                          bgColor = Colors.amber.withValues(alpha: 0.2);
                        } else if (isEliminated) {
                          bgColor = Colors.red.withValues(alpha: 0.15);
                        } else {
                          bgColor = i.isEven
                              ? Colors.white.withValues(alpha: 0.04)
                              : Colors.black.withValues(alpha: 0.08);
                        }
                        return Expanded(
                          child: Container(
                            margin: EdgeInsets.symmetric(horizontal: isCompact ? 2 : 3),
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: BorderRadius.circular(12),
                              border: isWinner
                                  ? Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 1.5)
                                  : (isEliminated
                                      ? Border.all(color: Colors.redAccent.withValues(alpha: 0.5), width: 1.5)
                                      : null),
                            ),
                          ),
                        );
                      }),
                    ),
                    // Grille de cartes scrollable par rang
                    AnimatedBuilder(
                      animation: _flipController,
                      builder: (context, _) {
                        return SingleChildScrollView(
                          controller: _gridScrollController,
                          physics: const NeverScrollableScrollPhysics(),
                          child: Column(
                            children: List.generate(maxCards, (rowIndex) {
                              return _buildCardRow(players, rowIndex, isCompact);
                            }),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(height: isCompact ? 4 : 8),

              // Scores (fixes en bas)
              _buildScoreRow(players, isCompact),
              SizedBox(height: isCompact ? 5 : 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerHeaders(List<Player> players, bool isCompact) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 4 : 8),
      child: Row(
        children: players.map((player) {
          final isDutchCaller = gameState.dutchCallerId == player.id;
          final isWinner = _winnerId == player.id;
          final isEliminated = _revealComplete && _eliminatedId == player.id;
          return Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(vertical: isCompact ? 2 : 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: isWinner
                    ? Colors.amber.withValues(alpha: 0.15)
                    : (isEliminated
                        ? Colors.red.withValues(alpha: 0.12)
                        : Colors.transparent),
              ),
              child: Column(
                children: [
                  Text(
                    player.displayAvatar,
                    style: TextStyle(fontSize: isCompact ? 18 : 28),
                  ),
                  Text(
                    player.name,
                    style: TextStyle(
                      color: isWinner
                          ? Colors.amber
                          : (isEliminated ? Colors.redAccent : Colors.white),
                      fontSize: isCompact ? 9 : 12,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  if (isDutchCaller)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "DUTCH",
                        style: TextStyle(
                          fontSize: isCompact ? 6 : 8,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    )
                  else
                    SizedBox(height: isCompact ? 11 : 15),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCardRow(List<Player> players, int rowIndex, bool isCompact) {
    final bool shouldReveal = rowIndex <= _currentRevealIndex;
    final bool isCurrentRow = rowIndex == _currentRevealIndex;
    final double animValue = isCurrentRow
        ? _flipController.value
        : (shouldReveal ? 1.0 : 0.0);
    final cardSize = isCompact ? CardSize.tiny : CardSize.small;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 4 : 8,
        vertical: isCompact ? 3 : 5,
      ),
      child: Row(
        children: players.map((player) {
          final hasCard = rowIndex < player.hand.length;
          return Expanded(
            child: Center(
              child: hasCard
                  ? FlipCardWidget(
                      card: player.hand[rowIndex],
                      isRevealed: shouldReveal,
                      animationValue: animValue,
                      cardSize: cardSize,
                    )
                  : const SizedBox(),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildScoreRow(List<Player> players, bool isCompact) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 4 : 8),
      child: Row(
        children: players.map((player) {
          final isWinner = _winnerId == player.id;
          final isEliminated = _revealComplete && _eliminatedId == player.id;
          final score = _currentScores[player.id] ?? 0;

          return Expanded(
            child: Center(
              child: AnimatedBuilder(
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 8 : 14,
                            vertical: isCompact ? 3 : 6,
                          ),
                          decoration: BoxDecoration(
                            color: isWinner
                                ? Colors.amber
                                : (isEliminated
                                    ? Colors.red.withValues(alpha: 0.7)
                                    : Colors.black45),
                            borderRadius: BorderRadius.circular(isCompact ? 6 : 10),
                            border: isEliminated
                                ? Border.all(color: Colors.redAccent, width: 2)
                                : null,
                          ),
                          child: Text(
                            "$score",
                            style: TextStyle(
                              fontSize: isCompact ? 14 : 22,
                              fontWeight: FontWeight.bold,
                              color: isWinner ? Colors.black : Colors.amber,
                            ),
                          ),
                        ),
                        if (isWinner && _revealComplete)
                          Padding(
                            padding: EdgeInsets.only(top: isCompact ? 2.0 : 4.0),
                            child: Icon(
                              Icons.emoji_events,
                              color: Colors.amber,
                              size: isCompact ? 14 : 20,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}


/// Helper pour ordonner les joueurs en mode solo (humain au centre)
List<Player> orderPlayersForSolo(List<Player> allPlayers) {
  Player human = allPlayers.firstWhere((p) => p.isHuman);
  List<Player> bots = allPlayers.where((p) => !p.isHuman).toList();
  List<Player> ordered = [];

  int halfBots = (bots.length / 2).ceil();
  for (int i = 0; i < halfBots && i < bots.length; i++) {
    ordered.add(bots[i]);
  }

  ordered.add(human);

  for (int i = halfBots; i < bots.length; i++) {
    ordered.add(bots[i]);
  }

  return ordered;
}
