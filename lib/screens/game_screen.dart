import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/card.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../providers/game_provider.dart';
import '../widgets/card_widget.dart';
import '../widgets/player_hand.dart';
import '../widgets/player_avatar.dart';
import '../widgets/responsive_dialog.dart';
import 'results_screen.dart';
import '../widgets/special_power_dialogs.dart';
import 'main_menu_screen.dart';
import 'dutch_reveal_screen.dart';
import '../services/web_orientation_service.dart';
import 'game_screen/center_table.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    if (kIsWeb) {
      WebOrientationService.lockLandscape();
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndNavigateIfEnded();
      _checkAndStartBotTurn();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    if (kIsWeb) {
      WebOrientationService.unlock();
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    super.dispose();
  }

  void _checkAndNavigateIfEnded() {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    if (gameProvider.gameState != null && gameProvider.gameState!.phase == GamePhase.ended) {
      if (ModalRoute.of(context)?.isCurrent == true && mounted) {
        if (gameProvider.gameState!.dutchCallerId != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const DutchRevealScreen()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const ResultsScreen()),
          );
        }
      }
    }
  }

  void _checkAndStartBotTurn() {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final gameState = gameProvider.gameState;

    if (gameState == null) return;

    if (!gameState.currentPlayer.isHuman &&
        gameState.phase == GamePhase.playing &&
        !gameProvider.isProcessing) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          gameProvider.checkIfBotShouldPlay();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameState = context.watch<GameProvider>().gameState;

    if (gameState != null && gameState.phase == GamePhase.ended) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ModalRoute.of(context)?.isCurrent == true && mounted) {
          if (gameState.dutchCallerId != null) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const DutchRevealScreen()),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const ResultsScreen()),
            );
          }
        }
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1a472a),
      body: Consumer<GameProvider>(
        builder: (context, gameProvider, child) {
          if (!gameProvider.hasActiveGame) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.amber));
          }

          final gameState = gameProvider.gameState!;

          final size = MediaQuery.of(context).size;
          final isPortrait = size.height > size.width;
          
          if (kIsWeb && isPortrait) {
            return _buildRotateScreenOverlay();
          }

          return Stack(
            children: [
              _buildGameTable(context, gameProvider, gameState),
              if (gameState.gameMode == GameMode.tournament)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text("Manche ${gameState.tournamentRound}",
                        style: const TextStyle(
                            color: Colors.amber, fontWeight: FontWeight.bold)),
                  ),
                ),
              if (gameState.phase == GamePhase.dutchCalled)
                _buildDutchNotification(gameState),
              if (gameState.isWaitingForSpecialPower)
                _buildSpecialPowerOverlay(gameProvider, gameState),
              if (gameProvider.isProcessing)
                const Positioned(
                  top: 20,
                  right: 60,
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white54)),
                ),
              if (gameProvider.isPaused)
                _buildPauseOverlay(gameProvider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGameTable(BuildContext context, GameProvider gp, GameState gs) {
    Player human = gs.players.firstWhere((p) => p.isHuman);
    List<Player> bots = gs.players.where((p) => !p.isHuman).toList();

    bool isMyTurn =
        gs.currentPlayer.id == human.id && gs.phase == GamePhase.playing;
    bool hasDrawn = gs.drawnCard != null;

    bool canInteractWithCards = isMyTurn || gs.phase == GamePhase.reaction;
    
    final screenSize = MediaQuery.of(context).size;
    final screenHeight = screenSize.height;
    final screenWidth = screenSize.width;
    final isCompactMode = screenHeight < 400 || screenWidth < 700;
    final isMediumMode = !isCompactMode && (screenHeight < 600 || screenWidth < 1000);

    final safePadding = MediaQuery.of(context).padding;
    final leftInset = safePadding.left;
    final rightInset = safePadding.right;

    final s = screenWidth < screenHeight ? screenWidth : screenHeight;
    final distanceFromCenter = s * 0.06;
    final topBandHeight = distanceFromCenter + (isCompactMode ? 60.0 : 80.0);
    final bottomBandHeight = distanceFromCenter + (isCompactMode ? 102.0 : 128.0);
    final sideBandWidth = distanceFromCenter + (isCompactMode ? 60.0 : 80.0);

    final centerLeft = sideBandWidth + leftInset;
    final centerRight = sideBandWidth + rightInset;
    final centerWidth = screenWidth - centerLeft - centerRight;
    final centerHeight = screenHeight - topBandHeight - bottomBandHeight;
    final buttonMargin = isCompactMode ? 2.0 : (isMediumMode ? 12.0 : 24.0);

    return Stack(
      children: [
        Positioned(
          left: centerLeft,
          right: centerRight,
          top: topBandHeight,
          bottom: bottomBandHeight,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: centerWidth,
                maxHeight: centerHeight,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: CenterTable(
                  gameState: gs,
                  isMyTurn: isMyTurn,
                  hasDrawn: hasDrawn,
                  isCompactMode: isCompactMode,
                  onShowDiscard: () => _showDiscardPile(gs),
                ),
              ),
            ),
          ),
        ),
        if (bots.length > 1)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topBandHeight,
            child: Center(
              child: RotatedBox(
                quarterTurns: 2,
                child: _buildBotArea(context, bots[1], gp, isCompactMode),
              ),
            ),
          ),
        if (bots.isNotEmpty)
          Positioned(
            left: leftInset,
            top: topBandHeight,
            bottom: bottomBandHeight,
            width: sideBandWidth,
            child: Center(
              child: Transform.translate(
                offset: Offset(
                  0,
                  ((isCompactMode ? 18.0 : 24.0) +
                          (isCompactMode ? 4.0 : 6.0)) /
                      2,
                ),
                child: RotatedBox(
                  quarterTurns: 1,
                  child: _buildBotArea(context, bots[0], gp, isCompactMode),
                ),
              ),
            ),
          ),
        if (bots.length > 2)
          Positioned(
            right: rightInset,
            top: topBandHeight,
            bottom: bottomBandHeight,
            width: sideBandWidth,
            child: Center(
              child: Transform.translate(
                offset: Offset(
                  0,
                  ((isCompactMode ? 18.0 : 24.0) +
                          (isCompactMode ? 4.0 : 6.0)) /
                      2,
                ),
                child: RotatedBox(
                  quarterTurns: 3,
                  child: _buildBotArea(context, bots[2], gp, isCompactMode),
                ),
              ),
            ),
          ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: bottomBandHeight,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: isCompactMode ? 4 : 8),
              child: _buildPlayerArea(gp, gs, human, isMyTurn, hasDrawn, canInteractWithCards, isCompactMode),
            ),
          ),
        ),
        Positioned(
          top: buttonMargin,
          right: rightInset + sideBandWidth + buttonMargin,
          child: IconButton(
            icon: Icon(Icons.pause_circle_filled,
                color: Colors.white54, size: isCompactMode ? 24 : 32),
            onPressed: () => gp.pauseGame(),
          ),
        ),
      ],
    );
  }
  
  Widget _buildPlayerArea(GameProvider gp, GameState gs, Player human, bool isMyTurn, bool hasDrawn, bool canInteractWithCards, bool isCompactMode) {
    if (isCompactMode) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isMyTurn)
            SizedBox(
              width: 60,
              height: 36,
              child: hasDrawn
                  ? _buildCompactActionButton(
                      icon: Icons.delete,
                      label: "JETER",
                      color: Colors.redAccent,
                      onTap: gp.discardDrawnCard,
                      withPulse: true)
                  : _buildCompactActionButton(
                      icon: Icons.get_app,
                      label: "PIOCHER",
                      color: Colors.green,
                      onTap: gp.drawCard,
                      withPulse: true),
            ),
          if (!isMyTurn) const SizedBox(width: 60),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayerAvatar(
                  player: human,
                  size: 24,
                  isActive: isMyTurn,
                  showName: true,
                  compactMode: true),
              const SizedBox(height: 4),
              PlayerHandWidget(
                player: human,
                isHuman: true,
                isActive: canInteractWithCards,
                onCardTap: (index) => _handleCardTap(gp, gs, index),
                selectedIndices: gp.shakingCardIndices.toList(),
                cardSize: CardSize.small,
              ),
            ],
          ),
          const SizedBox(width: 8),
          if (isMyTurn && !hasDrawn)
            SizedBox(
              width: 60,
              height: 36,
              child: _buildCompactActionButton(
                  icon: Icons.campaign,
                  label: "DUTCH",
                  color: Colors.amber.shade700,
                  onTap: () => _confirmDutch(gp)),
            ),
          if (isMyTurn && hasDrawn)
            Container(
              width: 60,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.blueAccent)),
              child: const Text("GARDER",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold)),
            ),
          if (!isMyTurn) const SizedBox(width: 60),
        ],
      );
    }
    
    return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 90,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isMyTurn)
                    Container(
                      height: 50,
                      margin: const EdgeInsets.only(bottom: 10),
                      child: hasDrawn
                          ? _buildActionButton(
                              icon: Icons.delete,
                              label: "JETER",
                              color: Colors.redAccent,
                              onTap: gp.discardDrawnCard,
                              withPulse: true)
                          : _buildActionButton(
                              icon: Icons.get_app,
                              label: "PIOCHER",
                              color: Colors.green,
                              onTap: gp.drawCard,
                              withPulse: true),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 15),
            Column(
              children: [
                PlayerAvatar(
                    player: human,
                    size: 28,
                    isActive: isMyTurn,
                    showName: true,
                    compactMode: true),
                const SizedBox(height: 6),
                PlayerHandWidget(
                  player: human,
                  isHuman: true,
                  isActive: canInteractWithCards,
                  onCardTap: (index) => _handleCardTap(gp, gs, index),
                  selectedIndices: gp.shakingCardIndices.toList(),
                  cardSize: CardSize.medium,
                ),
              ],
            ),
            const SizedBox(width: 15),
            SizedBox(
              width: 90,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isMyTurn && !hasDrawn)
                    Container(
                      height: 50,
                      margin: const EdgeInsets.only(bottom: 10),
                      child: _buildActionButton(
                          icon: Icons.campaign,
                          label: "DUTCH",
                          color: Colors.amber.shade700,
                          onTap: () => _confirmDutch(gp)),
                    ),
                  if (isMyTurn && hasDrawn)
                    Container(
                      height: 50,
                      margin: const EdgeInsets.only(bottom: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blueAccent)),
                      child: const Text("GARDER\n(Clique main)",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
          ],
        );
  }

  Widget _buildBotArea(BuildContext context, Player bot, GameProvider gp, bool isCompactMode) {
    final badgeSize = isCompactMode ? 18.0 : 24.0;
    final cardHeight = isCompactMode ? 25.0 : 40.0;
    final cardWidth = isCompactMode ? 50.0 : 80.0;
    final cardSpacing = isCompactMode ? 10.0 : 15.0;
    final handCount = bot.hand.length;
    final stackWidth = handCount == 0
        ? cardWidth
        : cardWidth + (handCount - 1) * cardSpacing;
    final isActive = gp.gameState!.currentPlayer.id == bot.id;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            PlayerAvatar(
              player: bot,
              size: badgeSize,
              isActive: isActive,
              showName: true,
              compactMode: true,
            ),
            Positioned(
              right: -6,
              top: -6,
              child: _buildBotCardCountBadge(bot.hand.length, isCompactMode),
            ),
          ],
        ),
        SizedBox(height: isCompactMode ? 4 : 6),
        SizedBox(
          height: cardHeight,
          width: stackWidth,
          child: Stack(
            children: List.generate(bot.hand.length, (index) {
              return Positioned(
                left: index * cardSpacing,
                child: CardWidget(
                    card: null, size: isCompactMode ? CardSize.tiny : CardSize.small, isRevealed: false),
              );
            }),
          ),
        )
      ],
    );
  }

  Widget _buildBotCardCountBadge(int count, bool isCompactMode) {
    final size = isCompactMode ? 16.0 : 20.0;
    final fontSize = isCompactMode ? 9.0 : 11.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: Colors.white30, width: 1),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildActionButton(
      {required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap,
      bool withPulse = false}) {
    Widget button = ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 4,
        shadowColor: color.withValues(alpha: 0.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
        ],
      ),
    );
    
    if (withPulse) {
      return AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _pulseAnimation.value,
            child: button,
          );
        },
      );
    }
    return button;
  }
  
  Widget _buildCompactActionButton(
      {required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap,
      bool withPulse = false}) {
    Widget button = ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        elevation: 3,
        shadowColor: color.withValues(alpha: 0.5),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14),
            const SizedBox(width: 2),
            Text(label,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 8)),
          ],
        ),
      ),
    );
    
    if (withPulse) {
      return AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _pulseAnimation.value,
            child: button,
          );
        },
      );
    }
    return button;
  }

  void _handleCardTap(GameProvider gp, GameState gs, int index) {
    if (gs.phase == GamePhase.reaction) {
      final humanPlayer = gs.players.firstWhere((p) => p.isHuman);
      gp.attemptMatch(index, forcedPlayer: humanPlayer);
    } else if (gs.phase == GamePhase.playing && gs.currentPlayer.isHuman) {
      if (gs.drawnCard != null) {
        gp.replaceCard(index);
      }
    }
  }

  Widget _buildSpecialPowerOverlay(GameProvider gp, GameState gs) {
    if (gs.specialCardToActivate == null) return const SizedBox();
    if (!gs.currentPlayer.isHuman) return const SizedBox();

    Player? playerWithPower;

    if (gs.currentPlayer.isHuman && gs.isWaitingForSpecialPower) {
      playerWithPower = gs.currentPlayer;
    } else {
      try {
        playerWithPower = gs.players.firstWhere((p) => p.isHuman);
      } catch (e) {
        return const SizedBox();
      }
    }

    if (!playerWithPower.isHuman) return const SizedBox();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ModalRoute.of(context)?.isCurrent == true &&
          gs.isWaitingForSpecialPower) {
        PlayingCard trigger = gs.specialCardToActivate!;
        String val = trigger.value;

        if (val == '7') {
          SpecialPowerDialogs.showLookCardDialog(context, trigger, true);
        } else if (val == '10') {
          SpecialPowerDialogs.showLookCardDialog(context, trigger, false);
        } else if (val == 'V') {
          SpecialPowerDialogs.showValetSwapDialog(context, trigger);
        } else if (val == 'JOKER') {
          SpecialPowerDialogs.showJokerDialog(context, trigger);
        } else {
          gp.skipSpecialPower();
        }
      }
    });

    return Container(color: Colors.black54);
  }

  Widget _buildDutchNotification(GameState gs) {
    return Container(
      color: Colors.amber.withValues(alpha: 0.9),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.campaign, size: 80, color: Colors.black),
            Text(
                "${gs.dutchCallerId == null ? 'DUTCH' : 'QUELQU\'UN'} A CRIÉ DUTCH !",
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _confirmDutch(GameProvider gp) {
    showDialog(
        context: context,
        builder: (ctx) => ResponsiveDialog(
              backgroundColor: const Color(0xFF1a3a28),
              builder: (context, metrics) {
                final titleSize = metrics.font(18);
                final bodySize = metrics.font(14);
                final gap = metrics.space(12);
                final buttonSize = metrics.font(16);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Crier DUTCH ?',
                        style: TextStyle(color: Colors.white, fontSize: titleSize)),
                    SizedBox(height: gap),
                    Text('Êtes-vous sûr ?',
                        style:
                            TextStyle(color: Colors.white70, fontSize: bodySize)),
                    SizedBox(height: gap),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text('Non',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: buttonSize))),
                        TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              gp.callDutch();
                            },
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.redAccent),
                            child: Text('DUTCH !',
                                style: TextStyle(fontSize: buttonSize)))
                      ],
                    )
                  ],
                );
              },
            ));
  }

  void _showDiscardPile(GameState gs) {
    showDialog(
        context: context,
        builder: (ctx) => ResponsiveDialog(
              backgroundColor: const Color(0xFF1a3a28),
              builder: (context, metrics) {
                final titleSize = metrics.font(18);
                final gap = metrics.space(12);
                final listHeight = metrics.contentHeight * 0.6;
                final cardWidth =
                    math.min(metrics.contentWidth * 0.25, listHeight / 1.5);
                final cardHeight = cardWidth * 1.5;
                final cardPadding = metrics.space(6);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Défausse',
                        style: TextStyle(color: Colors.white, fontSize: titleSize)),
                    SizedBox(height: gap),
                    SizedBox(
                      width: metrics.contentWidth,
                      height: listHeight,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: gs.discardPile.reversed
                            .map((c) => Padding(
                                  padding: EdgeInsets.all(cardPadding),
                                  child: SizedBox(
                                    width: cardWidth,
                                    height: cardHeight,
                                    child: FittedBox(
                                      fit: BoxFit.contain,
                                      child: CardWidget(
                                          card: c,
                                          size: CardSize.large,
                                          isRevealed: true),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                );
              },
            ));
  }

  Future<bool?> _showQuitConfirmation() {
    return showDialog<bool>(
        context: context,
        builder: (ctx) => ResponsiveDialog(
              backgroundColor: const Color(0xFF1a3a28),
              builder: (context, metrics) {
                final titleSize = metrics.font(18);
                final bodySize = metrics.font(14);
                final gap = metrics.space(12);
                final buttonSize = metrics.font(16);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Quitter ?",
                        style: TextStyle(color: Colors.white, fontSize: titleSize)),
                    SizedBox(height: gap),
                    Text(
                        "Quitter la partie ? Elle sera sauvegardée et comptée comme un abandon.",
                        style:
                            TextStyle(color: Colors.white70, fontSize: bodySize),
                        textAlign: TextAlign.center),
                    SizedBox(height: gap),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text("Non",
                                style: TextStyle(
                                    color: Colors.white, fontSize: buttonSize))),
                        TextButton(
                            onPressed: () {
                              final gp = Provider.of<GameProvider>(context,
                                  listen: false);
                              gp.quitGame();
                              Navigator.pop(ctx, true);
                            },
                            child: Text("Oui",
                                style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: buttonSize))),
                      ],
                    ),
                  ],
                );
              },
            ));
  }

  Widget _buildPauseOverlay(GameProvider gp) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pause_circle_outline, color: Colors.amber, size: 80),
            const SizedBox(height: 20),
            const Text(
              "PAUSE",
              style: TextStyle(
                color: Colors.amber,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                fontFamily: 'Rye',
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () => gp.resumeGame(),
              icon: const Icon(Icons.play_arrow, size: 28),
              label: const Text("REPRENDRE", style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () async {
                gp.resumeGame();
                final shouldQuit = await _showQuitConfirmation();
                if (shouldQuit == true && mounted) {
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const MainMenuScreen()),
                    (route) => false,
                  );
                } else {
                  gp.pauseGame();
                }
              },
              icon: const Icon(Icons.exit_to_app, color: Colors.redAccent),
              label: const Text("Quitter la partie", style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRotateScreenOverlay() {
    return Container(
      color: const Color(0xFF1a472a),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1500),
              builder: (context, value, child) {
                return Transform.rotate(
                  angle: value * 1.57,
                  child: const Icon(
                    Icons.screen_rotation,
                    size: 80,
                    color: Colors.amber,
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            const Text(
              '📱 Tournez votre écran',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Le jeu Dutch se joue en mode paysage',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '(ou agrandissez la fenêtre)',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
