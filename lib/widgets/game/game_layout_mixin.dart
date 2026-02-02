import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/utils/screen_utils.dart';
import 'package:dutch_game/widgets/game/card_widget.dart';
import 'package:dutch_game/widgets/game/player_hand.dart';
import 'package:dutch_game/widgets/game/player_avatar.dart';
import 'package:dutch_game/widgets/game/game_action_button.dart';
import 'package:dutch_game/widgets/ui/card_count_badge.dart';

/// Données de layout calculées pour la zone joueur
class PlayerAreaLayoutData {
  final double sideButtonWidth;
  final double sideGap;
  final double actionButtonHeight;
  final double actionButtonMargin;
  final double handMaxWidth;
  final Size cardMetrics;

  const PlayerAreaLayoutData({
    required this.sideButtonWidth,
    required this.sideGap,
    required this.actionButtonHeight,
    required this.actionButtonMargin,
    required this.handMaxWidth,
    required this.cardMetrics,
  });
}

/// Layout des boutons d'action
class ActionButtonLayout {
  final double width;
  final double height;
  final double margin;
  final double columnHeight;

  ActionButtonLayout({
    required this.width,
    required this.height,
    required this.margin,
  }) : columnHeight = (height * 2) + margin;
}

/// Métriques calculées pour le layout de la table de jeu
class GameTableMetrics {
  final double sideBandWidth;
  final double topBandHeight;
  final double bottomBandHeight;
  final double centerWidth;
  final double centerHeight;
  final double centerShiftFraction;
  final double buttonMargin;
  final double outerGap;

  const GameTableMetrics({
    required this.sideBandWidth,
    required this.topBandHeight,
    required this.bottomBandHeight,
    required this.centerWidth,
    required this.centerHeight,
    required this.centerShiftFraction,
    required this.buttonMargin,
    required this.outerGap,
  });

  /// Calcule les métriques de layout pour la table de jeu
  static GameTableMetrics compute({
    required BoxConstraints constraints,
    required double sideBandContentWidth,
    required double outerGap,
    required double centerGapX,
    required double botBlockHeight,
    required double playerAreaHeight,
    required double centerMinHeight,
    required double botCardHeight,
    required double playerCardHeight,
    required bool isCompactMode,
    required bool isMediumMode,
    required bool isDrawnCardVisible,
  }) {
    final sideBandWidth = sideBandContentWidth + outerGap + centerGapX;
    
    final baseHeight = botBlockHeight + playerAreaHeight + centerMinHeight + (outerGap * 2);
    final slack = math.max(0.0, constraints.maxHeight - baseHeight);
    final totalWeight = botBlockHeight + playerAreaHeight + centerMinHeight;
    final centerExtra = totalWeight == 0 ? 0.0 : slack * (centerMinHeight / totalWeight);
    final gapSlack = slack - centerExtra;
    final topGap = gapSlack;
    const bottomGap = 0.0;
    
    final topBandHeight = botBlockHeight + outerGap + topGap;
    final bottomBandHeight = playerAreaHeight + outerGap + bottomGap;
    final centerWidth = math.max(0.0, constraints.maxWidth - (sideBandWidth * 2));
    final centerHeight = math.max(0.0, constraints.maxHeight - topBandHeight - bottomBandHeight);
    
    final centerShiftY = (botCardHeight - playerCardHeight - topBandHeight + bottomBandHeight) / 2.0;
    final centerShiftFraction = centerHeight == 0 
        ? 0.0 
        : (centerShiftY / (centerHeight / 2)).clamp(-1.0, 1.0);
    final buttonMargin = isCompactMode ? 2.0 : (isMediumMode ? 12.0 : 24.0);

    return GameTableMetrics(
      sideBandWidth: sideBandWidth,
      topBandHeight: topBandHeight,
      bottomBandHeight: bottomBandHeight,
      centerWidth: centerWidth,
      centerHeight: centerHeight,
      centerShiftFraction: isDrawnCardVisible ? centerShiftFraction : 0.0,
      buttonMargin: buttonMargin,
      outerGap: outerGap,
    );
  }
}

/// Mixin dédié aux calculs de layout et builders de widgets pour la table de jeu
/// Utilisé par GameTableWidget et potentiellement d'autres widgets de jeu
/// NE contient PAS de logique screen (navigation, orientation, etc.)
mixin GameLayoutMixin<T extends StatefulWidget> on State<T> {
  static const double cardAspectRatio = 7 / 5;

  // ============================================================
  // CARD SIZE CALCULATIONS
  // ============================================================

  Size cardVisualSize(BuildContext context, CardSize size) {
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
    final scaledWidth = scaledHeight / cardAspectRatio;
    return Size(scaledWidth, scaledHeight);
  }

  double compactBadgeHeight(BuildContext context, Player player, double size) {
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

  double compactBadgeWidth(BuildContext context, Player player, double size) {
    final fontSize = ScreenUtils.scaleFont(context, size * 0.35);
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
    final padding = ScreenUtils.spacing(context, 10);
    final reserveTrailing = ScreenUtils.spacing(context, 18);
    final contentWidth = textPainter.width + reserveTrailing;
    final minWidth = size * 2.9;
    final maxWidth = ScreenUtils.usableWidth(context) * 0.65;
    return (contentWidth + padding * 2).clamp(minWidth, maxWidth);
  }

  ActionButtonLayout actionButtonLayout(
      BuildContext context, bool isCompactMode, Size cardMetrics) {
    final heightTarget = cardMetrics.height * (isCompactMode ? 0.7 : 0.85);
    final widthTarget = cardMetrics.width * (isCompactMode ? 1.6 : 2.4);
    final height = heightTarget.clamp(
        isCompactMode ? 34.0 : 56.0, isCompactMode ? 52.0 : 92.0);
    final width = widthTarget.clamp(
        isCompactMode ? 72.0 : 110.0, isCompactMode ? 120.0 : 220.0);
    final margin = ScreenUtils.spacing(context, isCompactMode ? 4.0 : 8.0);
    return ActionButtonLayout(width: width, height: height, margin: margin);
  }

  /// Calcule les données de layout pour la zone joueur
  PlayerAreaLayoutData computePlayerAreaLayout({
    required BuildContext context,
    required int handLength,
    required CardSize cardSize,
    required bool isCompactMode,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final safePadding = MediaQuery.of(context).padding;
    final availableWidth = screenWidth - safePadding.left - safePadding.right;
    final cardMetrics = cardVisualSize(context, cardSize);
    final cardGap = ScreenUtils.spacing(context, 4.0);
    final naturalHandWidth = PlayerHandWidget.metrics(
      context,
      cardSize,
      handLength,
      overlapCards: false,
      cardGap: cardGap,
    ).totalWidth;
    final actionLayout = actionButtonLayout(context, isCompactMode, cardMetrics);
    final sideButtonWidth = actionLayout.width;
    final baseSideGap = (cardMetrics.width * (isCompactMode ? 0.08 : 0.12)).clamp(
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
    final reservedWidth = (sideButtonWidth * 2) + (sideGap * 2);
    final maxHandWidth = math.max(cardMetrics.width, availableWidth - reservedWidth);
    final handMaxWidth = math.min(maxHandWidth, naturalHandWidth);

    return PlayerAreaLayoutData(
      sideButtonWidth: sideButtonWidth,
      sideGap: sideGap,
      actionButtonHeight: actionLayout.height,
      actionButtonMargin: actionLayout.margin,
      handMaxWidth: handMaxWidth,
      cardMetrics: cardMetrics,
    );
  }

  double estimateCenterMinHeight(
      BuildContext context, GameState gs, bool isCompactMode) {
    final cardSize =
        cardVisualSize(context, isCompactMode ? CardSize.small : CardSize.medium);
    final padding = isCompactMode ? 8.0 : 15.0;
    return cardSize.height + (padding * 2);
  }

  // ============================================================
  // SCREEN MODE DETECTION
  // ============================================================

  bool isCompactModeFor(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.height < 400 || size.width < 700;
  }

  bool isMediumModeFor(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final compact = isCompactModeFor(context);
    return !compact && (size.height < 600 || size.width < 1000);
  }

  // ============================================================
  // PLAYER BLOCK BUILDER
  // ============================================================

  Widget buildPlayerBlock({
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
    int? turnStartTime,
    int? turnDuration,
    bool isAfk = false,
    bool? isConnected,
    Key? handKey,
    List<int>? hiddenIndices,
    List<String>? hiddenCardIds,
  }) {
    Widget badge = PlayerAvatar(
      player: player,
      size: badgeSize,
      isActive: isActive,
      showName: true,
      compactMode: true,
      reserveTrailingSpace: showCountBadge,
      turnStartTime: turnStartTime,
      turnDuration: turnDuration,
      isAfk: isAfk,
    );

    // Add connection indicator for multiplayer
    if (isConnected != null) {
      badge = Stack(
        children: [
          badge,
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
    }

    final nameplate = showCountBadge
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              badge,
              Positioned(
                right: -8,
                top: -8,
                child: CardCountBadge(
                  count: player.hand.length,
                  isCompact: isCompactMode,
                ),
              ),
            ],
          )
        : badge;

    final handWidget = PlayerHandWidget(
      key: handKey,
      player: player,
      isHuman: isHuman,
      isActive: canInteract,
      onCardTap: onCardTap,
      selectedIndices: selectedIndices,
      hiddenIndices: hiddenIndices,
      hiddenCardIds: hiddenCardIds,
      cardSize: cardSize,
      overlapCards: !isHuman,
      fitToWidth: isHuman,
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

  // ============================================================
  // PLAYER AREA WITH ACTION BUTTONS
  // ============================================================

  Widget buildPlayerAreaWithButtons({
    required BuildContext context,
    required Player human,
    required bool isMyTurn,
    required bool hasDrawn,
    required bool canInteractWithCards,
    required bool isCompactMode,
    required CardSize cardSize,
    required double badgeSize,
    required double spacing,
    required double maxHeight,
    required List<int> selectedIndices,
    required Function(int) onCardTap,
    required VoidCallback onDraw,
    required VoidCallback onDiscard,
    required VoidCallback onDutch,
    double? constrainedWidth,
    Key? handKey,
    List<int>? hiddenIndices,
    List<String>? hiddenCardIds,
    Widget? leftAccessory,
    Widget? rightAccessory,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final safePadding = MediaQuery.of(context).padding;
    final availableWidth = constrainedWidth ?? (screenWidth - safePadding.left - safePadding.right);
    final cardMetrics = cardVisualSize(context, cardSize);
    final cardGap = ScreenUtils.spacing(context, 4.0);
    final naturalHandWidth = PlayerHandWidget.metrics(
      context,
      cardSize,
      human.hand.length,
      overlapCards: false,
      cardGap: cardGap,
    ).totalWidth;
    final layout = actionButtonLayout(context, isCompactMode, cardMetrics);
    // Constrain sideButtonWidth to max 25% of available width to prevent overflow
    final sideButtonWidth = math.min(layout.width, availableWidth * 0.25);
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
    final actionButtonHeight = layout.height;
    final actionButtonMargin = layout.margin;
    final reservedWidth = (sideButtonWidth * 2) + (sideGap * 2);
    final maxHandWidth =
        math.max(cardMetrics.width, availableWidth - reservedWidth);
    final handMaxWidth = math.min(maxHandWidth, naturalHandWidth);

    final playerBlock = buildPlayerBlock(
      context: context,
      player: human,
      isActive: isMyTurn,
      canInteract: canInteractWithCards,
      isHuman: true,
      cardSize: cardSize,
      badgeSize: badgeSize,
      spacing: spacing,
      handWidth: handMaxWidth,
      selectedIndices: selectedIndices,
      onCardTap: onCardTap,
      handKey: handKey,
      hiddenIndices: hiddenIndices,
      hiddenCardIds: hiddenCardIds,
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
      return _buildCompactPlayerArea(
        context: context,
        isMyTurn: isMyTurn,
        hasDrawn: hasDrawn,
        sideButtonWidth: sideButtonWidth,
        actionButtonHeight: actionButtonHeight,
        sideGap: sideGap,
        fittedPlayerBlock: fittedPlayerBlock,
        onDraw: onDraw,
        onDiscard: onDiscard,
        onDutch: onDutch,
        maxHeight: maxHeight,
        leftAccessory: leftAccessory,
        rightAccessory: rightAccessory,
      );
    }

    return _buildNormalPlayerArea(
      isMyTurn: isMyTurn,
      hasDrawn: hasDrawn,
      sideButtonWidth: sideButtonWidth,
      actionButtonHeight: actionButtonHeight,
      actionButtonMargin: actionButtonMargin,
      sideGap: sideGap,
      fittedPlayerBlock: fittedPlayerBlock,
      onDraw: onDraw,
      onDiscard: onDiscard,
      onDutch: onDutch,
    );
  }

  Widget _buildCompactPlayerArea({
    required BuildContext context,
    required bool isMyTurn,
    required bool hasDrawn,
    required double sideButtonWidth,
    required double actionButtonHeight,
    required double sideGap,
    required Widget fittedPlayerBlock,
    required VoidCallback onDraw,
    required VoidCallback onDiscard,
    required VoidCallback onDutch,
    required double maxHeight,
    Widget? leftAccessory,
    Widget? rightAccessory,
  }) {
    final hasAccessories = leftAccessory != null || rightAccessory != null;
    if (hasAccessories) {
      final accessoryGap = ScreenUtils.spacing(context, 4.0);
      final accessoryHeight = math.max(
        0.0,
        maxHeight - actionButtonHeight - accessoryGap,
      );

      Widget buildSideColumn({
        required Widget? accessory,
        required Widget buttonChild,
      }) {
        return SizedBox(
          width: sideButtonWidth,
          height: maxHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                width: sideButtonWidth,
                height: accessoryHeight,
                child: accessory != null
                    ? FittedBox(
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomCenter,
                        child: accessory,
                      )
                    : const SizedBox.shrink(),
              ),
              if (accessoryHeight > 0) SizedBox(height: accessoryGap),
              SizedBox(
                width: sideButtonWidth,
                height: actionButtonHeight,
                child: buttonChild,
              ),
            ],
          ),
        );
      }

      final leftButtonChild = isMyTurn
          ? (hasDrawn
              ? GameActionButton(
                  label: "JETER",
                  color: Colors.redAccent,
                  onTap: onDiscard,
                  withPulse: true,
                  compact: true,
                )
              : GameActionButton(
                  label: "PIOCHER",
                  color: Colors.green,
                  onTap: onDraw,
                  withPulse: true,
                  compact: true,
                ))
          : const SizedBox.shrink();

      final rightButtonChild = isMyTurn && !hasDrawn
          ? GameActionButton(
              label: "DUTCH",
              color: Colors.amber.shade700,
              onTap: onDutch,
              withPulse: true,
              compact: true,
            )
          : (isMyTurn && hasDrawn
              ? Container(
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
                )
              : const SizedBox.shrink());

      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          buildSideColumn(
            accessory: leftAccessory,
            buttonChild: leftButtonChild,
          ),
          SizedBox(width: sideGap),
          Flexible(child: fittedPlayerBlock),
          SizedBox(width: sideGap),
          buildSideColumn(
            accessory: rightAccessory,
            buttonChild: rightButtonChild,
          ),
        ],
      );
    }

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
                    onTap: onDiscard,
                    withPulse: true,
                    compact: true,
                  )
                : GameActionButton(
                    label: "PIOCHER",
                    color: Colors.green,
                    onTap: onDraw,
                    withPulse: true,
                    compact: true,
                  ),
          ),
        if (!isMyTurn) SizedBox(width: sideButtonWidth),
        SizedBox(width: sideGap),
        Flexible(child: fittedPlayerBlock),
        SizedBox(width: sideGap),
        if (isMyTurn && !hasDrawn)
          SizedBox(
            width: sideButtonWidth,
            height: actionButtonHeight,
            child: GameActionButton(
              label: "DUTCH",
              color: Colors.amber.shade700,
              onTap: onDutch,
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

  Widget _buildNormalPlayerArea({
    required bool isMyTurn,
    required bool hasDrawn,
    required double sideButtonWidth,
    required double actionButtonHeight,
    required double actionButtonMargin,
    required double sideGap,
    required Widget fittedPlayerBlock,
    required VoidCallback onDraw,
    required VoidCallback onDiscard,
    required VoidCallback onDutch,
  }) {
    return ClipRect(
      child: Row(
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
                          onTap: onDiscard,
                          withPulse: true,
                        )
                      : GameActionButton(
                          label: "PIOCHER",
                          color: Colors.green,
                          onTap: onDraw,
                          withPulse: true,
                        ),
                ),
            ],
          ),
        ),
        SizedBox(width: sideGap),
        Flexible(child: fittedPlayerBlock),
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
                    onTap: onDutch,
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
    ),
    );
  }

  // ============================================================
  // OPPONENT/BOT AREA BUILDER
  // ============================================================

  Widget buildOpponentArea({
    required BuildContext context,
    required Player opponent,
    required bool isActive,
    required bool canInteract,
    required CardSize cardSize,
    required double badgeSize,
    required double spacing,
    required bool isCompactMode,
    Function(int)? onCardTap,
    int? turnStartTime,
    int? turnDuration,
    bool? isConnected,
    bool isAfk = false,
    Key? handKey,
    List<int>? hiddenIndices,
    List<String>? hiddenCardIds,
  }) {
    final cardMetrics = cardVisualSize(context, cardSize);
    final overlap =
        cardMetrics.width * PlayerHandWidget.overlapFactor(cardSize);
    final count = math.max(1, opponent.hand.length);
    final handWidth = cardMetrics.width + (count - 1) * overlap;

    return buildPlayerBlock(
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
      onCardTap: onCardTap,
      turnStartTime: turnStartTime,
      turnDuration: turnDuration,
      isConnected: isConnected,
      isAfk: isAfk,
      handKey: handKey,
      hiddenIndices: hiddenIndices,
      hiddenCardIds: hiddenCardIds,
    );
  }
}

/// Helper pour gérer le tap sur une carte (reaction match ou remplacement)
void handleCardTapCommon({
  required GameState gs,
  required int index,
  required bool isLocalPlayerTurn,
  required void Function(int index) onAttemptMatch,
  required void Function(int index) onReplaceCard,
}) {
  if (gs.phase == GamePhase.reaction) {
    onAttemptMatch(index);
  } else if (gs.phase == GamePhase.playing && isLocalPlayerTurn && gs.drawnCard != null) {
    onReplaceCard(index);
  }
}
