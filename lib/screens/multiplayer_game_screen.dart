import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../widgets/multiplayer_special_power_dialogs.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/card.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../providers/multiplayer_game_provider.dart';
import '../widgets/card_widget.dart';
import '../widgets/player_hand.dart';
import '../widgets/player_avatar.dart';
import '../widgets/responsive_dialog.dart';
import '../utils/screen_utils.dart';
import '../widgets/game_action_button.dart';
import 'multiplayer_results_screen.dart';

import 'multiplayer_dutch_reveal_screen.dart';
import '../services/web_orientation_service.dart';
import '../widgets/center_table.dart';
import '../widgets/presence_check_overlay.dart';

class MultiplayerGameScreen extends StatefulWidget {
  const MultiplayerGameScreen({super.key});

  @override
  State<MultiplayerGameScreen> createState() => _MultiplayerGameScreenState();
}

class _MultiplayerGameScreenState extends State<MultiplayerGameScreen> {
  static const double _cardAspectRatio = 7 / 5;
  StreamSubscription? _eventSubscription;

  @override
  void initState() {
    super.initState();

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
      _setupEventListeners();
    });
  }

  void _setupEventListeners() {
    final provider =
        Provider.of<MultiplayerGameProvider>(context, listen: false);
    _eventSubscription = provider.events.listen((event) {
      if (!mounted) return;

      // In game, we care about Player Left, Errors, Kicked (though kicked handles navigation)
      // and maybe Info. Joined is less relevant unless spectator?

      String? message;
      Color color = Colors.black87;
      IconData icon = Icons.info;

      switch (event.type) {
        case GameEventType.playerLeft:
          message = event.message;
          color = Colors.orange.shade800;
          icon = Icons.person_remove;
          break;
        case GameEventType.error:
          message = event.message;
          color = Colors.red.shade800;
          icon = Icons.error;
          break;
        case GameEventType.kicked:
          message = event.message;
          color = Colors.red.shade900;
          icon = Icons.block;
          break;
        case GameEventType.info:
          message = event.message;
          color = Colors.blue.shade800;
          break;
        default:
          break;
      }

      if (message != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(icon, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: color,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
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

    _eventSubscription?.cancel();
    super.dispose();
  }

  void _checkAndNavigateIfEnded() {
    // Handling navigation in build/listener is usually safer for Provider updates
  }

  @override
  Widget build(BuildContext context) {
    // Consume MultiplayerGameProvider
    return Consumer<MultiplayerGameProvider>(
      builder: (context, gameProvider, child) {
        final gameState = gameProvider.gameState;

        if (gameState == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF1a472a),
            body: Center(child: CircularProgressIndicator(color: Colors.amber)),
          );
        }

        // Handle Host Left
        if (gameProvider.roomClosedByHost) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ModalRoute.of(context)?.isCurrent == true && mounted) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => ResponsiveDialog(
                  backgroundColor: const Color(0xFF1a472a),
                  builder: (context, metrics) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Partie terminée",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: metrics.font(24),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: metrics.space(20)),
                      Text(
                        "L'hôte a fermé la partie.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white70, fontSize: metrics.font(16)),
                      ),
                      SizedBox(height: metrics.space(30)),
                      GameActionButton(
                        label: "MENU PRINCIPAL",
                        onTap: () => Navigator.of(context)
                            .popUntil((route) => route.isFirst),
                        color: Colors.amber,
                      ),
                    ],
                  ),
                ),
              );
            }
          });
          return const Scaffold(backgroundColor: Color(0xFF1a472a));
        }

        // Handle Kicked (AFK or manually)
        if (gameProvider.wasKicked) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ModalRoute.of(context)?.isCurrent == true && mounted) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => ResponsiveDialog(
                  backgroundColor: const Color(0xFF1a472a),
                  builder: (context, metrics) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Exclu du jeu",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: metrics.font(24),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: metrics.space(20)),
                      Text(
                        gameProvider.kickedMessage ??
                            "Vous avez été exclu de la partie.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white70, fontSize: metrics.font(16)),
                      ),
                      SizedBox(height: metrics.space(30)),
                      GameActionButton(
                        label: "OK",
                        onTap: () => Navigator.of(context)
                            .popUntil((route) => route.isFirst),
                        color: Colors.redAccent,
                      ),
                    ],
                  ),
                ),
              );
            }
          });
          return const Scaffold(backgroundColor: Color(0xFF1a472a));
        }

        // Navigate if ended
        if (gameState.phase == GamePhase.ended) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ModalRoute.of(context)?.isCurrent == true && mounted) {
              if (gameState.dutchCallerId != null) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (context) =>
                          const MultiplayerDutchRevealScreen()),
                );
              } else {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (context) => MultiplayerResultsScreen(
                            gameState: gameState,
                            localPlayerId: gameProvider.playerId,
                          )),
                );
              }
            }
          });
        }

        // Check for Spied Card Dialog
        if (gameProvider.showSpiedCardDialog &&
            gameProvider.lastSpiedCard != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ModalRoute.of(context)?.isCurrent == true && mounted) {
              MultiplayerSpecialPowerDialogs.showCardRevealDialog(
                      context,
                      gameProvider.lastSpiedCard!,
                      gameProvider.spiedTargetName ?? 'Joueur')
                  .then((_) => gameProvider.closeSpiedCardDialog());
            }
          });
        }

        final size = MediaQuery.of(context).size;
        final isPortrait = size.height > size.width;

        if (kIsWeb && isPortrait) {
          return _buildRotateScreenOverlay();
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            _showQuitConfirmation(context, gameProvider);
          },
          child: Scaffold(
            backgroundColor: const Color(0xFF1a472a),
            body: Stack(
              children: [
                _buildGameTable(context, gameProvider, gameState),

                // Room Code and FPS/Status Overlay would go here if desired
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.videogame_asset,
                            color: Colors.white70, size: 16),
                        const SizedBox(width: 8),
                        Text("Room: ${gameProvider.roomCode ?? '?'}",
                            style: const TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
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

                // Notification: joueur a quitté
                if (gameProvider.playerLeftNotification)
                  Positioned(
                    top: 60,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade800.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black38,
                                blurRadius: 8,
                                offset: const Offset(0, 3))
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.exit_to_app,
                                color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              "${gameProvider.lastPlayerLeftName ?? 'Un joueur'} a quitté",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Notification: pouvoir spécial utilisé sur nous
                if (gameProvider.specialPowerNotification)
                  Positioned(
                    top: 60,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade700.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black38,
                                blurRadius: 8,
                                offset: const Offset(0, 3))
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome,
                                color: Colors.amber, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              "${gameProvider.specialPowerByName ?? 'Un joueur'} utilise un pouvoir sur vous !",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Pause Button
                Positioned(
                  top: 10,
                  right: 10,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.pause_circle_filled,
                            color: Colors.white54, size: 32),
                        onPressed: () => gameProvider.pauseGame(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.exit_to_app,
                            color: Colors.white54, size: 32),
                        onPressed: () =>
                            _showQuitConfirmation(context, gameProvider),
                      ),
                    ],
                  ),
                ),

                if (gameProvider.isPaused) _buildPauseOverlay(gameProvider),

                if (gameProvider.showAfkWarning)
                  Container(
                    color: Colors.black54,
                    alignment: Alignment.center,
                    child: Container(
                      width: 300,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.amber, width: 2),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: Colors.amber, size: 48),
                          const SizedBox(height: 16),
                          const Text(
                            "Êtes-vous toujours là ?",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "Expulsion imminente...",
                            style: TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 16),
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 1.0, end: 0.0),
                            duration: const Duration(
                                seconds: 15), // Durée estimée avant kick
                            builder: (context, value, _) =>
                                LinearProgressIndicator(
                              value: value,
                              backgroundColor: Colors.black26,
                              color: Colors.amber,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: () => gameProvider.resetAfkTimer(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 32, vertical: 12),
                            ),
                            child: const Text("OUI, JE SUIS LÀ",
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ),

                PresenceCheckOverlay(
                  active: gameProvider.presenceCheckActive,
                  deadlineMs: gameProvider.presenceCheckDeadlineMs,
                  reason: gameProvider.presenceCheckReason,
                  onConfirm: gameProvider.confirmPresence,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGameTable(
      BuildContext context, MultiplayerGameProvider gp, GameState gs) {
    // Identify participants
    final myId = gp.playerId;
    Player human = gs.players
        .firstWhere((p) => p.id == myId, orElse: () => gs.players.first);
    // If spectator or eliminated, we might need fallback? For now assume player exists.

    // Get opponents (exclude me)
    List<Player> opponents = gs.players.where((p) => p.id != myId).toList();
    // Reorder opponents based on position relative to me?
    // MultiplayerService usually returns list. If we want constant relative position:
    // (opponent_pos - my_pos + total) % total
    // But simplified: just list them.

    // Sort logic to keep them stable if needed?
    // Opponents are usually stable in the list from server.

    bool isMyTurn =
        gs.currentPlayer.id == human.id && gs.phase == GamePhase.playing;
    bool hasDrawn = gs.drawnCard != null;

    bool canInteractWithCards = isMyTurn || gs.phase == GamePhase.reaction;

    final screenSize = MediaQuery.of(context).size;
    final screenHeight = screenSize.height;
    final screenWidth = screenSize.width;
    final isCompactMode = screenHeight < 400 || screenWidth < 700;

    final botCardType = isCompactMode ? CardSize.tiny : CardSize.small;
    final playerCardType = isCompactMode ? CardSize.small : CardSize.medium;
    final botCardMetrics = _cardVisualSize(context, botCardType);
    final playerCardMetrics = _cardVisualSize(context, playerCardType);
    final blockSpacing =
        ScreenUtils.spacing(context, isCompactMode ? 4.0 : 6.0);
    final botOverlap =
        botCardMetrics.width * PlayerHandWidget.overlapFactor(botCardType);
    final outerGapBase =
        math.min(botCardMetrics.height, playerCardMetrics.height) *
            (isCompactMode ? 0.05 : 0.035);
    final outerGap = outerGapBase.clamp(0.0, 6.0);
    final centerGapX = botCardMetrics.width * (isCompactMode ? 0.3 : 0.22);
    final botBadgeSize = isCompactMode ? 18.0 : 24.0;

    final botBadgeHeight = opponents.isEmpty
        ? 0.0
        : opponents
            .map((bot) => _compactBadgeHeight(context, bot, botBadgeSize))
            .fold(0.0, math.max);

    final botBlockHeight =
        botBadgeHeight + blockSpacing + botCardMetrics.height;

    final maxBotBadgeWidth = opponents.isEmpty
        ? 0.0
        : opponents
            .map((bot) => _compactBadgeWidth(context, bot, botBadgeSize))
            .fold(0.0, math.max);

    final maxBotHandWidth = opponents.isEmpty
        ? botCardMetrics.width
        : opponents.map((bot) {
            final count = math.max(1, bot.hand.length);
            return botCardMetrics.width + (count - 1) * botOverlap;
          }).fold(0.0, math.max);

    final playerBadgeSize = isCompactMode ? 24.0 : 28.0;
    final playerBadgeHeight =
        _compactBadgeHeight(context, human, playerBadgeSize);
    final playerBlockHeight =
        playerBadgeHeight + blockSpacing + playerCardMetrics.height;
    final actionLayout =
        _actionButtonLayout(context, isCompactMode, playerCardMetrics);
    final playerAreaHeight =
        math.max(actionLayout.columnHeight, playerBlockHeight);

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
          const bottomGap = 0.0;
          final topBandHeight = botBlockHeight + outerGap + topGap;
          final bottomBandHeight = playerAreaHeight + outerGap + bottomGap;
          final centerWidth =
              math.max(0.0, constraints.maxWidth - (sideBandWidth * 2));
          final centerHeight = math.max(
            0.0,
            constraints.maxHeight - topBandHeight - bottomBandHeight,
          );
          final isDrawnCardVisible =
              isMyTurn && hasDrawn && gs.drawnCard != null;
          final centerShiftY = (botCardMetrics.height -
                  playerCardMetrics.height -
                  topBandHeight +
                  bottomBandHeight) /
              2.0;
          final centerShiftFraction = centerHeight == 0
              ? 0.0
              : (centerShiftY / (centerHeight / 2)).clamp(-1.0, 1.0);

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
                    child: Align(
                      alignment: Alignment(
                        0,
                        isDrawnCardVisible ? centerShiftFraction : 0.0,
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
                          onDrawCard: gp.drawCard,
                          onTakeFromDiscard: gp.takeFromDiscard,
                          reactionTimeTotalMs: gp.currentReactionTimeMs,
                          enableHaptics: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // OPPONENTS PLACEMENT
              // Identical logic to bots: op[1] is TOP, op[0] is LEFT, op[2] is RIGHT usually
              if (opponents.length > 1)
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
                                child: _buildOpponentArea(
                                  context,
                                  opponents[1],
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
              if (opponents.isNotEmpty)
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
                        child: _buildOpponentArea(
                          context,
                          opponents[0],
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
              if (opponents.length > 2)
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
                        child: _buildOpponentArea(
                          context,
                          opponents[2],
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
            ],
          );
        },
      ),
    );
  }

  Widget _buildPlayerArea(
    MultiplayerGameProvider gp,
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
    final availableWidth = screenWidth - safePadding.left - safePadding.right;
    final cardMetrics = _cardVisualSize(context, cardSize);
    final cardGap = ScreenUtils.spacing(context, 4.0);
    final naturalHandWidth = PlayerHandWidget.metrics(
      context,
      cardSize,
      human.hand.length,
      overlapCards: false,
      cardGap: cardGap,
    ).totalWidth;
    final actionLayout =
        _actionButtonLayout(context, isCompactMode, cardMetrics);
    final sideButtonWidth = actionLayout.width;
    final baseSideGap =
        (cardMetrics.width * (isCompactMode ? 0.08 : 0.12)).clamp(
      ScreenUtils.spacing(context, 4.0),
      ScreenUtils.spacing(context, isCompactMode ? 12.0 : 18.0),
    );
    double sideGap = baseSideGap;
    if (!isCompactMode) {
      final maxGapForHand = math.max(
        0.0,
        (availableWidth - (naturalHandWidth + (sideButtonWidth * 2))) / 2,
      );
      if (maxGapForHand > baseSideGap) {
        final desiredGap = baseSideGap + (cardMetrics.width * 0.35);
        sideGap = desiredGap.clamp(baseSideGap, maxGapForHand);
      }
    }
    final actionButtonHeight = actionLayout.height;
    final actionButtonMargin = actionLayout.margin;
    final reservedWidth = (sideButtonWidth * 2) + (sideGap * 2);
    final maxHandWidth =
        math.max(cardMetrics.width, availableWidth - reservedWidth);
    final handMaxWidth = math.min(maxHandWidth, naturalHandWidth);

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
              height: actionButtonHeight,
              child: hasDrawn
                  ? GameActionButton(
                      label: "JETER",
                      color: Colors.redAccent,
                      onTap: gp.discardDrawnCard,
                      withPulse: true,
                      compact: true,
                    )
                  : GameActionButton(
                      label: "PIOCHER",
                      color: Colors.green,
                      onTap: gp.drawCard,
                      withPulse: true,
                      compact: true,
                    ),
            ),
          if (!isMyTurn) SizedBox(width: sideButtonWidth),
          SizedBox(width: sideGap),
          fittedPlayerBlock,
          SizedBox(width: sideGap),
          if (isMyTurn && !hasDrawn)
            SizedBox(
              width: sideButtonWidth,
              height: actionButtonHeight,
              child: GameActionButton(
                label: "DUTCH",
                color: Colors.amber.shade700,
                onTap: () => _confirmDutch(gp),
                withPulse: true,
                compact: true,
              ),
            ),
          if (isMyTurn && hasDrawn)
            Container(
              width: sideButtonWidth,
              height: actionButtonHeight,
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
                  height: actionButtonHeight,
                  margin: EdgeInsets.only(bottom: actionButtonMargin),
                  child: hasDrawn
                      ? GameActionButton(
                          label: "JETER",
                          color: Colors.redAccent,
                          onTap: gp.discardDrawnCard,
                          withPulse: true,
                        )
                      : GameActionButton(
                          label: "PIOCHER",
                          color: Colors.green,
                          onTap: gp.drawCard,
                          withPulse: true,
                        ),
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
                  height: actionButtonHeight,
                  margin: EdgeInsets.only(bottom: actionButtonMargin),
                  child: GameActionButton(
                    label: "DUTCH",
                    color: Colors.amber.shade700,
                    onTap: () => _confirmDutch(gp),
                    withPulse: true,
                  ),
                ),
              if (isMyTurn && hasDrawn)
                Container(
                  height: actionButtonHeight,
                  margin: EdgeInsets.only(bottom: actionButtonMargin),
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
    // Check connection status for opponents
    final gp = Provider.of<MultiplayerGameProvider>(context, listen: false);
    final presence = gp.presenceById[player.id];
    final isConnected = presence == null || presence['connected'] == true;

    final badge = Stack(
      children: [
        PlayerAvatar(
          player: player,
          size: badgeSize,
          isActive: isActive,
          showName: true,
          compactMode: true,
        ),
        // Indicateur de connexion (toujours visible)
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isConnected ? Colors.green : Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
        ),
      ],
    );

    final nameplate = showCountBadge
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              badge,
              Positioned(
                right: -6,
                top: -6,
                child:
                    _buildBotCardCountBadge(player.hand.length, isCompactMode),
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

  Widget _buildOpponentArea(
    BuildContext context,
    Player opponent,
    MultiplayerGameProvider gp,
    bool isCompactMode, {
    required CardSize cardSize,
    required double badgeSize,
    required double spacing,
  }) {
    final cardMetrics = _cardVisualSize(context, cardSize);
    final overlap =
        cardMetrics.width * PlayerHandWidget.overlapFactor(cardSize);
    final count = math.max(1, opponent.hand.length);
    final handWidth = cardMetrics.width + (count - 1) * overlap;
    final isActive = gp.gameState!.currentPlayer.id == opponent.id;

    // Allow interaction if waiting for special power (e.g. Spy)
    final canInteract = gp.gameState!.isWaitingForSpecialPower &&
        gp.gameState!.currentPlayer.id == gp.playerId;

    return _buildPlayerBlock(
      context: context,
      player: opponent,
      isActive: isActive,
      canInteract: canInteract,
      isHuman: false,
      cardSize: cardSize,
      badgeSize: badgeSize,
      spacing: spacing,
      handWidth: handWidth,
      showCountBadge: true,
      isCompactMode: isCompactMode,
      onCardTap: canInteract
          ? (index) {
              gp.useSpecialPower(opponent.position, index);
            }
          : null,
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

  double _compactBadgeHeight(BuildContext context, Player player, double size) {
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
    final contentHeight = math.max(textPainter.height, emojiPainter.height);
    final verticalPadding = ScreenUtils.spacing(context, 4) * 2;
    return size + contentHeight + verticalPadding;
  }

  double _compactBadgeWidth(BuildContext context, Player player, double size) {
    // Approximate width based on avatar + text
    return size * 3;
  }

  _ActionButtonLayout _actionButtonLayout(
      BuildContext context, bool isCompactMode, Size cardMetrics) {
    final heightTarget = cardMetrics.height * (isCompactMode ? 0.7 : 0.85);
    final widthTarget = cardMetrics.width * (isCompactMode ? 1.6 : 2.4);
    final height = heightTarget.clamp(
        isCompactMode ? 34.0 : 56.0, isCompactMode ? 52.0 : 92.0);
    final width = widthTarget.clamp(
        isCompactMode ? 72.0 : 110.0, isCompactMode ? 120.0 : 220.0);
    final margin = ScreenUtils.spacing(context, isCompactMode ? 4.0 : 8.0);
    return _ActionButtonLayout(width: width, height: height, margin: margin);
  }

  void _confirmDutch(MultiplayerGameProvider gp) {
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
                        style: TextStyle(
                            color: Colors.white, fontSize: titleSize)),
                    SizedBox(height: gap),
                    Text('Êtes-vous sûr ?',
                        style: TextStyle(
                            color: Colors.white70, fontSize: bodySize)),
                    SizedBox(height: gap),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text('Non',
                                style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: buttonSize))),
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
                        style: TextStyle(
                            color: Colors.white, fontSize: titleSize)),
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

  Future<void> _showQuitConfirmation(
      BuildContext context, MultiplayerGameProvider gp) async {
    final leave = await showDialog<bool>(
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
                        style: TextStyle(
                            color: Colors.white, fontSize: titleSize)),
                    SizedBox(height: gap),
                    Text(
                        "Quitter la partie ? Elle sera sauvegardée et comptée comme un abandon.",
                        style: TextStyle(
                            color: Colors.white70, fontSize: bodySize),
                        textAlign: TextAlign.center),
                    SizedBox(height: gap),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text("Non",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: buttonSize))),
                        TextButton(
                            onPressed: () {
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

    if (leave == true && mounted) {
      gp.leaveRoom();
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Widget _buildRotateScreenOverlay() {
    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.screen_rotation, color: Colors.white, size: 50),
            SizedBox(height: 20),
            Text(
              "Veuillez tourner votre appareil\nen mode paysage",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDutchNotification(GameState gs) {
    // Basic implementation of Dutch notification overlay
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(15),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("DUTCH !",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("Dernier tour pour tout le monde !",
                style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecialPowerOverlay(MultiplayerGameProvider gp, GameState gs) {
    if (gs.specialCardToActivate == null && gs.pendingSwap == null)
      return const SizedBox();
    if (!gs.currentPlayer.isHuman && gs.pendingSwap == null)
      return const SizedBox();

    // Check if it's MY turn and I need to act OR if I have a pending swap
    bool isMyTurn = gs.currentPlayer.id == gp.playerId;
    bool isPendSwap = gs.pendingSwap != null && isMyTurn;

    if (!isMyTurn && !isPendSwap) return const SizedBox();

    // Prevent re-showing if already processing or dismissed locally
    if (gp.isProcessing) return const SizedBox();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Check if a dialog is likely already open (not perfect but helpful)
      // or if we are just waiting for server
      if (ModalRoute.of(context)?.isCurrent == true) {
        // Use a local tag to prevent loops if state hasn't updated yet?
        // Actually, reliable fix is optimistic update in provider.
        // But let's safe guard here too.

        if (gs.pendingSwap != null) {
          // ... existing logic ...
          MultiplayerSpecialPowerDialogs.showCompleteSwapDialog(context);
          return;
        }

        if (gs.isWaitingForSpecialPower && gs.specialCardToActivate != null) {
          PlayingCard trigger = gs.specialCardToActivate!;
          String val = trigger.value;

          // Ensure we don't spam

          if (val == '7' || val == '8') {
            MultiplayerSpecialPowerDialogs.showLookOwnCardDialog(
                context, trigger);
          } else if (val == '9' || val == '10') {
            bool isSwap = (val == '10');
            MultiplayerSpecialPowerDialogs.showOpponentSelectionDialog(
                context, trigger, isSwap);
          } else if (val == 'V') {
            MultiplayerSpecialPowerDialogs.showOpponentSelectionDialog(
                context, trigger, true);
          } else if (val == 'JOKER') {
            MultiplayerSpecialPowerDialogs.showJokerDialog(context, trigger);
          } else {
            gp.skipSpecialPower();
          }
        }
      }
    });

    return Container(color: Colors.black54);
  }

  Widget _buildPauseOverlay(MultiplayerGameProvider gp) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pause_circle_outline,
                color: Colors.amber, size: 80),
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
            const SizedBox(height: 10),
            if (gp.pausedByName != null)
              Text("Mis en pause par ${gp.pausedByName}",
                  style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => gp.resumeGame(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              ),
              child: const Text("REPRENDRE",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  double _estimateCenterMinHeight(
      BuildContext context, GameState gs, bool isCompactMode) {
    final cardSize = _cardVisualSize(
        context, isCompactMode ? CardSize.small : CardSize.medium);
    final padding = isCompactMode ? 8.0 : 15.0;
    return cardSize.height + (padding * 2);
  }

  void _handleCardTap(
      MultiplayerGameProvider provider, GameState gameState, int index) {
    // Gestion des clics sur les cartes selon la phase du jeu
    if (gameState.phase == GamePhase.reaction) {
      // Tenter un match
      provider.attemptMatch(index);
    } else if (gameState.phase == GamePhase.playing &&
        gameState.drawnCard != null &&
        gameState.currentPlayer.id == provider.playerId) {
      provider.replaceCard(index);
    } else if (gameState.isWaitingForSpecialPower) {
      // Special powers handling
      // Usually involves choosing a card
      if (gameState.pendingSwap != null) {
        provider.completeSwap(index);
      } else {
        // Generic special power use (e.g. Look at own card)
        // Assuming 'human' is consistent with index being my own hand index
        // Wait, we need my position.
        final me =
            gameState.players.firstWhere((p) => p.id == provider.playerId);
        provider.useSpecialPower(me.position, index);
      }
    }
  }

  Widget _buildBotCardCountBadge(int count, bool isCompact) {
    return Container(
      padding: EdgeInsets.all(isCompact ? 4 : 6),
      decoration: BoxDecoration(
        color: Colors.amber,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Text(
        "$count",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: isCompact ? 10 : 14,
          color: Colors.black,
        ),
      ),
    );
  }
}

class _ActionButtonLayout {
  final double width;
  final double height;
  final double margin;
  final double columnHeight;

  _ActionButtonLayout({
    required this.width,
    required this.height,
    required this.margin,
  }) : columnHeight = (height * 2) + margin;
}
