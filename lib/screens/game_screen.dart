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
import '../utils/screen_utils.dart';
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
  static const double _cardAspectRatio = 7 / 5;
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

    final botCardType = isCompactMode ? CardSize.tiny : CardSize.small;
    final playerCardType = isCompactMode ? CardSize.small : CardSize.medium;
    final botCardMetrics = _cardVisualSize(context, botCardType);
    final playerCardMetrics = _cardVisualSize(context, playerCardType);
    final blockSpacing = ScreenUtils.spacing(context, isCompactMode ? 4.0 : 6.0);
    final botOverlap =
        botCardMetrics.width * PlayerHandWidget.overlapFactor(botCardType);
    final outerGapBase =
        math.min(botCardMetrics.height, playerCardMetrics.height) *
            (isCompactMode ? 0.05 : 0.035);
    final outerGap = outerGapBase.clamp(0.0, 6.0);
    final centerGapX = botCardMetrics.width * (isCompactMode ? 0.3 : 0.22);
    final botBadgeSize = isCompactMode ? 18.0 : 24.0;
    final botBadgeHeight = bots.isEmpty
        ? 0.0
        : bots
            .map((bot) => _compactBadgeHeight(context, bot, botBadgeSize))
            .reduce(math.max);
    final botBlockHeight =
        botBadgeHeight + blockSpacing + botCardMetrics.height;
    final maxBotBadgeWidth = bots.isEmpty
        ? 0.0
        : bots
            .map((bot) => _compactBadgeWidth(context, bot, botBadgeSize))
            .reduce(math.max);
    final maxBotHandWidth = bots.isEmpty
        ? botCardMetrics.width
        : bots
            .map((bot) {
              final count = math.max(1, bot.hand.length);
              return botCardMetrics.width + (count - 1) * botOverlap;
            })
            .reduce(math.max);

    final playerBadgeSize = isCompactMode ? 24.0 : 28.0;
    final playerBadgeHeight =
        _compactBadgeHeight(context, human, playerBadgeSize);
    final playerBlockHeight =
        playerBadgeHeight + blockSpacing + playerCardMetrics.height;
    final actionColumnHeight = isCompactMode ? 36.0 : 60.0;
    final playerAreaHeight =
        math.max(actionColumnHeight, playerBlockHeight);

    final sideBandContentWidth =
        math.max(botBlockHeight, math.max(maxBotBadgeWidth, maxBotHandWidth));
    final sideBandWidth = sideBandContentWidth + outerGap + centerGapX;
    final centerMinHeight =
        _estimateCenterMinHeight(context, gs, isCompactMode);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final baseHeight = botBlockHeight +
              playerAreaHeight +
              centerMinHeight +
              (outerGap * 2);
          final slack = math.max(0.0, constraints.maxHeight - baseHeight);
          final totalWeight =
              botBlockHeight + playerAreaHeight + centerMinHeight;
          final centerExtra =
              totalWeight == 0 ? 0.0 : slack * (centerMinHeight / totalWeight);
          final gapSlack = slack - centerExtra;
          final topGap = gapSlack;
          final bottomGap = 0.0;
          final topBandHeight = botBlockHeight + outerGap + topGap;
          final bottomBandHeight = playerAreaHeight + outerGap + bottomGap;
          final centerWidth =
              math.max(0.0, constraints.maxWidth - (sideBandWidth * 2));
          final centerHeight = math.max(
            0.0,
            constraints.maxHeight - topBandHeight - bottomBandHeight,
          );
          final buttonMargin = isCompactMode ? 2.0 : (isMediumMode ? 12.0 : 24.0);

          return Stack(
            children: [
              Positioned(
                left: sideBandWidth,
                right: sideBandWidth,
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
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.only(top: outerGap),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SizedBox(
                            height: constraints.maxHeight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.topCenter,
                              child: RotatedBox(
                                quarterTurns: 2,
                                child: _buildBotArea(
                                  context,
                                  bots[1],
                                  gp,
                                  isCompactMode,
                                  cardSize: botCardType,
                                  badgeSize: botBadgeSize,
                                  spacing: blockSpacing,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              if (bots.isNotEmpty)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: sideBandWidth,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(left: outerGap),
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: _buildBotArea(
                          context,
                          bots[0],
                          gp,
                          isCompactMode,
                          cardSize: botCardType,
                          badgeSize: botBadgeSize,
                          spacing: blockSpacing,
                        ),
                      ),
                    ),
                  ),
                ),
              if (bots.length > 2)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: sideBandWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: EdgeInsets.only(right: outerGap),
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: _buildBotArea(
                          context,
                          bots[2],
                          gp,
                          isCompactMode,
                          cardSize: botCardType,
                          badgeSize: botBadgeSize,
                          spacing: blockSpacing,
                        ),
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
                    padding: EdgeInsets.only(bottom: outerGap),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return _buildPlayerArea(
                          gp,
                          gs,
                          human,
                          isMyTurn,
                          hasDrawn,
                          canInteractWithCards,
                          isCompactMode,
                          cardSize: playerCardType,
                          badgeSize: playerBadgeSize,
                          spacing: blockSpacing,
                          maxHeight: constraints.maxHeight,
                        );
                      },
                    ),
                  ),
                ),
              ),
              Positioned(
                top: outerGap,
                right: sideBandWidth + buttonMargin,
                child: IconButton(
                  icon: Icon(Icons.pause_circle_filled,
                      color: Colors.white54, size: isCompactMode ? 24 : 32),
                  onPressed: () => gp.pauseGame(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
  
  Widget _buildPlayerArea(
    GameProvider gp,
    GameState gs,
    Player human,
    bool isMyTurn,
    bool hasDrawn,
    bool canInteractWithCards,
    bool isCompactMode, {
    required CardSize cardSize,
    required double badgeSize,
    required double spacing,
    required double maxHeight,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final safePadding = MediaQuery.of(context).padding;
    final availableWidth =
        screenWidth - safePadding.left - safePadding.right;
    final sideButtonWidth = isCompactMode ? 60.0 : 90.0;
    final sideGap = isCompactMode ? 8.0 : 15.0;
    final cardMetrics = _cardVisualSize(context, cardSize);
    final reservedWidth = (sideButtonWidth * 2) + (sideGap * 2);
    final handMaxWidth =
        math.max(cardMetrics.width, availableWidth - reservedWidth);

    final playerBlock = _buildPlayerBlock(
      context: context,
      player: human,
      isActive: isMyTurn,
      canInteract: canInteractWithCards,
      isHuman: true,
      cardSize: cardSize,
      badgeSize: badgeSize,
      spacing: spacing,
      handWidth: handMaxWidth,
      selectedIndices: gp.shakingCardIndices.toList(),
      onCardTap: (index) => _handleCardTap(gp, gs, index),
    );
    final fittedPlayerBlock = SizedBox(
      height: maxHeight,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.bottomCenter,
        child: playerBlock,
      ),
    );

    if (isCompactMode) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isMyTurn)
            SizedBox(
              width: sideButtonWidth,
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
          if (!isMyTurn) SizedBox(width: sideButtonWidth),
          SizedBox(width: sideGap),
          fittedPlayerBlock,
          SizedBox(width: sideGap),
          if (isMyTurn && !hasDrawn)
            SizedBox(
              width: sideButtonWidth,
              height: 36,
              child: _buildCompactActionButton(
                  icon: Icons.campaign,
                  label: "DUTCH",
                  color: Colors.amber.shade700,
                  onTap: () => _confirmDutch(gp)),
            ),
          if (isMyTurn && hasDrawn)
            Container(
              width: sideButtonWidth,
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
          if (!isMyTurn) SizedBox(width: sideButtonWidth),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: sideButtonWidth,
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
        SizedBox(width: sideGap),
        fittedPlayerBlock,
        SizedBox(width: sideGap),
        SizedBox(
          width: sideButtonWidth,
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

  Widget _buildPlayerBlock({
    required BuildContext context,
    required Player player,
    required bool isActive,
    required bool canInteract,
    required bool isHuman,
    required CardSize cardSize,
    required double badgeSize,
    required double spacing,
    double? handWidth,
    List<int>? selectedIndices,
    Function(int)? onCardTap,
    bool showCountBadge = false,
    bool isCompactMode = true,
  }) {
    final badge = PlayerAvatar(
      player: player,
      size: badgeSize,
      isActive: isActive,
      showName: true,
      compactMode: true,
    );
    final nameplate = showCountBadge
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              badge,
              Positioned(
                right: -6,
                top: -6,
                child: _buildBotCardCountBadge(player.hand.length, isCompactMode),
              ),
            ],
          )
        : badge;
    final handWidget = PlayerHandWidget(
      player: player,
      isHuman: isHuman,
      isActive: canInteract,
      onCardTap: onCardTap,
      selectedIndices: selectedIndices,
      cardSize: cardSize,
      overlapCards: !isHuman,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        nameplate,
        SizedBox(height: spacing),
        if (handWidth != null)
          SizedBox(width: handWidth, child: handWidget)
        else
          handWidget,
      ],
    );
  }

  Widget _buildBotArea(
    BuildContext context,
    Player bot,
    GameProvider gp,
    bool isCompactMode, {
    required CardSize cardSize,
    required double badgeSize,
    required double spacing,
  }) {
    final cardMetrics = _cardVisualSize(context, cardSize);
    final overlap =
        cardMetrics.width * PlayerHandWidget.overlapFactor(cardSize);
    final count = math.max(1, bot.hand.length);
    final handWidth = cardMetrics.width + (count - 1) * overlap;
    final isActive = gp.gameState!.currentPlayer.id == bot.id;

    return _buildPlayerBlock(
      context: context,
      player: bot,
      isActive: isActive,
      canInteract: false,
      isHuman: false,
      cardSize: cardSize,
      badgeSize: badgeSize,
      spacing: spacing,
      handWidth: handWidth,
      showCountBadge: true,
      isCompactMode: isCompactMode,
    );
  }

  Size _cardVisualSize(BuildContext context, CardSize size) {
    double height;
    switch (size) {
      case CardSize.tiny:
        height = 34;
        break;
      case CardSize.small:
        height = 50;
        break;
      case CardSize.medium:
        height = 76;
        break;
      case CardSize.large:
        height = 128;
        break;
      case CardSize.drawn:
        height = 102;
        break;
    }

    final scaledHeight =
        ScreenUtils.scale(context, height) * ScreenUtils.cardScaleFactor;
    final scaledWidth = scaledHeight / _cardAspectRatio;
    return Size(scaledWidth, scaledHeight);
  }

  double _compactBadgeHeight(
      BuildContext context, Player player, double size) {
    final fontSize = ScreenUtils.scaleFont(context, size * 0.35);
    final emojiSize = ScreenUtils.scaleFont(context, size * 0.4);
    final baseStyle = DefaultTextStyle.of(context).style;
    final textPainter = TextPainter(
      text: TextSpan(
        text: player.displayName,
        style: baseStyle.copyWith(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final emojiPainter = TextPainter(
      text: TextSpan(
        text: player.displayAvatar,
        style: baseStyle.copyWith(fontSize: emojiSize),
      ),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final contentHeight =
        math.max(textPainter.height, emojiPainter.height);
    final verticalPadding = ScreenUtils.spacing(context, 4) * 2;
    final minHeight = ScreenUtils.scale(context, size * 0.6);
    return math.max(contentHeight + verticalPadding, minHeight);
  }

  double _compactBadgeWidth(BuildContext context, Player player, double size) {
    final fontSize = ScreenUtils.scaleFont(context, size * 0.35);
    final emojiSize = ScreenUtils.scaleFont(context, size * 0.4);
    final baseStyle = DefaultTextStyle.of(context).style;
    final textPainter = TextPainter(
      text: TextSpan(
        text: player.displayName,
        style: baseStyle.copyWith(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final emojiPainter = TextPainter(
      text: TextSpan(
        text: player.displayAvatar,
        style: baseStyle.copyWith(fontSize: emojiSize),
      ),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final horizontalPadding = ScreenUtils.spacing(context, 10) * 2;
    final spacing = ScreenUtils.spacing(context, 4);
    return textPainter.width + emojiPainter.width + spacing + horizontalPadding;
  }

  double _estimateCenterMinHeight(
      BuildContext context, GameState gs, bool isCompactMode) {
    final cardSize =
        _cardVisualSize(context, isCompactMode ? CardSize.small : CardSize.medium);
    final padding = isCompactMode ? 8.0 : 15.0;
    final baseHeight = cardSize.height + (padding * 2);
    return baseHeight + _reactionHeaderHeight(context, gs, isCompactMode);
  }

  double _reactionHeaderHeight(
      BuildContext context, GameState gs, bool isCompactMode) {
    if (gs.phase != GamePhase.reaction) return 0.0;
    final fontSize = isCompactMode ? 12.0 : 16.0;
    final style = DefaultTextStyle.of(context).style.copyWith(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        );
    final topCardValue = gs.topDiscardCard?.displayName ?? "?";
    final textPainter = TextPainter(
      text: TextSpan(text: "Vite ! Avez-vous un$topCardValue ?", style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final textHeight = textPainter.height;
    final progressHeight = isCompactMode ? 5.0 : 8.0;
    final topSpacing = isCompactMode ? 2.0 : 5.0;
    final bottomSpacing = isCompactMode ? 4.0 : 10.0;
    return textHeight + topSpacing + progressHeight + bottomSpacing;
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
                const aspect = 7 / 5;
                final cardWidth =
                    math.min(metrics.contentWidth * 0.25, listHeight / aspect);
                final cardHeight = cardWidth * aspect;
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
