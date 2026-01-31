import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:dutch_game/core/interfaces/i_game_controller.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/utils/screen_utils.dart';
import 'package:dutch_game/widgets/game/game_layout_mixin.dart';
import 'package:dutch_game/widgets/game/card_widget.dart';
import 'package:dutch_game/widgets/game/player_hand.dart';
import 'package:dutch_game/widgets/game/center_table.dart';
import 'package:dutch_game/widgets/dialogs/game/game_dialogs.dart';

/// Configuration pour les callbacks d'actions de jeu
class GameTableCallbacks {
  final VoidCallback onDrawCard;
  final VoidCallback onDiscardDrawnCard;
  final VoidCallback onCallDutch;
  final VoidCallback? onTakeFromDiscard;
  final ValueChanged<int> onCardTap;
  final void Function(int opponentIndex, int cardIndex)? onOpponentCardTap;
  final VoidCallback onShowDiscardPile;

  const GameTableCallbacks({
    required this.onDrawCard,
    required this.onDiscardDrawnCard,
    required this.onCallDutch,
    this.onTakeFromDiscard,
    required this.onCardTap,
    this.onOpponentCardTap,
    required this.onShowDiscardPile,
  });

  /// Factory pour créer des callbacks à partir d'un IGameController
  /// Réduit le couplage entre l'UI et les providers concrets
  /// Auto-wire onShowDiscardPile et onCardTap depuis le controller
  factory GameTableCallbacks.fromController({
    required BuildContext context,
    required IGameController controller,
    void Function(int opponentIndex, int cardIndex)? onOpponentCardTap,
    bool supportsTakeFromDiscard = true,
  }) {
    return GameTableCallbacks(
      onDrawCard: controller.drawCard,
      onTakeFromDiscard: supportsTakeFromDiscard ? controller.takeFromDiscard : null,
      onDiscardDrawnCard: controller.discardDrawnCard,
      onCallDutch: controller.callDutch,
      onCardTap: controller.handleCardTap,
      onOpponentCardTap: onOpponentCardTap,
      onShowDiscardPile: () {
        final gs = controller.gameState;
        if (gs == null || gs.discardPile.isEmpty) return;
        GameDialogs.showDiscardPile(context, gs);
      },
    );
  }
}

/// Configuration optionnelle pour le mode multiplayer
class MultiplayerConfig {
  final String? playerId;
  final Map<String, bool> playerConnections;
  final Map<String, bool> playerAfkStatus;
  final int? turnStartTime;
  final int? turnDuration;
  final int reactionTimeTotalMs;

  const MultiplayerConfig({
    this.playerId,
    this.playerConnections = const {},
    this.playerAfkStatus = const {},
    this.turnStartTime,
    this.turnDuration,
    this.reactionTimeTotalMs = 0,
  });

  static const solo = MultiplayerConfig();
}

/// Widget principal de la table de jeu - partagé entre solo et multiplayer
class GameTableWidget extends StatelessWidget {
  final GameState gameState;
  final GameTableCallbacks callbacks;
  final MultiplayerConfig multiplayerConfig;
  final List<int> shakingCardIndices;
  final bool isProcessing;
  final bool isSpectator;

  const GameTableWidget({
    super.key,
    required this.gameState,
    required this.callbacks,
    this.multiplayerConfig = MultiplayerConfig.solo,
    this.shakingCardIndices = const [],
    this.isProcessing = false,
    this.isSpectator = false,
  });

  @override
  Widget build(BuildContext context) {
    return _GameTableContent(
      gameState: gameState,
      callbacks: callbacks,
      multiplayerConfig: multiplayerConfig,
      shakingCardIndices: shakingCardIndices,
      isProcessing: isProcessing,
      isSpectator: isSpectator,
    );
  }
}

class _GameTableContent extends StatefulWidget {
  final GameState gameState;
  final GameTableCallbacks callbacks;
  final MultiplayerConfig multiplayerConfig;
  final List<int> shakingCardIndices;
  final bool isProcessing;
  final bool isSpectator;

  const _GameTableContent({
    required this.gameState,
    required this.callbacks,
    required this.multiplayerConfig,
    required this.shakingCardIndices,
    required this.isProcessing,
    required this.isSpectator,
  });

  @override
  State<_GameTableContent> createState() => _GameTableContentState();
}

class _GameTableContentState extends State<_GameTableContent>
    with GameLayoutMixin<_GameTableContent> {
  GameState get gs => widget.gameState;
  GameTableCallbacks get callbacks => widget.callbacks;
  MultiplayerConfig get mpConfig => widget.multiplayerConfig;
  bool get isSpectator => widget.isSpectator;

  Player? get _humanPlayer {
    if (mpConfig.playerId != null) {
      try {
        return gs.players.firstWhere((p) => p.id == mpConfig.playerId);
      } catch (_) {
        return null;
      }
    }
    try {
      return gs.players.firstWhere((p) => p.isHuman);
    } catch (_) {
      return null;
    }
  }

  List<Player> get _opponents {
    final human = _humanPlayer;
    if (human == null) return gs.players;
    return gs.players.where((p) => p.id != human.id).toList();
  }

  bool get _isMyTurn {
    final human = _humanPlayer;
    if (human == null) return false;
    return gs.currentPlayer.id == human.id && gs.phase == GamePhase.playing;
  }

  bool get _hasDrawn => gs.drawnCard != null;

  bool get _canInteractWithCards {
    if (isSpectator) return false;
    return _isMyTurn || gs.phase == GamePhase.reaction;
  }

  @override
  Widget build(BuildContext context) {
    final human = _humanPlayer;
    final opponents = _opponents;

    final screenSize = MediaQuery.of(context).size;
    final screenHeight = screenSize.height;
    final screenWidth = screenSize.width;
    final isCompact = screenHeight < 400 || screenWidth < 700;
    final botCardType = isCompact ? CardSize.tiny : CardSize.small;
    final playerCardType = isCompact ? CardSize.small : CardSize.medium;
    final botCardMetrics = cardVisualSize(context, botCardType);
    final playerCardMetrics = cardVisualSize(context, playerCardType);
    final blockSpacing = ScreenUtils.spacing(context, isCompact ? 4.0 : 6.0);
    final botOverlap =
        botCardMetrics.width * PlayerHandWidget.overlapFactor(botCardType);
    final outerGapBase =
        math.min(botCardMetrics.height, playerCardMetrics.height) *
            (isCompact ? 0.05 : 0.035);
    final outerGap = outerGapBase.clamp(0.0, 6.0);
    final centerGapX = botCardMetrics.width * (isCompact ? 0.3 : 0.22);
    final botBadgeSize = isCompact ? 18.0 : 24.0;

    final botBadgeHeight = opponents.isEmpty
        ? 0.0
        : opponents
            .map((bot) => compactBadgeHeight(context, bot, botBadgeSize))
            .fold(0.0, math.max);

    final botBlockHeight =
        botBadgeHeight + blockSpacing + botCardMetrics.height;

    final maxBotBadgeWidth = opponents.isEmpty
        ? 0.0
        : opponents
            .map((bot) => compactBadgeWidth(context, bot, botBadgeSize))
            .fold(0.0, math.max);

    final maxBotHandWidth = opponents.isEmpty
        ? botCardMetrics.width
        : opponents.map((bot) {
            final count = math.max(1, bot.hand.length);
            return botCardMetrics.width + (count - 1) * botOverlap;
          }).fold(0.0, math.max);

    final playerBadgeSize = isCompact ? 24.0 : 28.0;
    final playerBadgeHeight = isSpectator || human == null
        ? 40.0
        : compactBadgeHeight(context, human, playerBadgeSize);

    final playerBlockHeight = isSpectator
        ? 60.0
        : playerBadgeHeight + blockSpacing + playerCardMetrics.height;

    final layout = actionButtonLayout(context, isCompact, playerCardMetrics);
    final playerAreaHeight =
        isSpectator ? 60.0 : math.max(layout.columnHeight, playerBlockHeight);

    final sideBandContentWidth =
        math.max(botBlockHeight, math.max(maxBotBadgeWidth, maxBotHandWidth));
    final sideBandWidth = sideBandContentWidth + outerGap + centerGapX;
    final centerMinHeight = estimateCenterMinHeight(context, gs, isCompact);

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
              _isMyTurn && _hasDrawn && gs.drawnCard != null;
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
              // Centre - Table (pioche + défausse)
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
                          isMyTurn: _isMyTurn,
                          hasDrawn: _hasDrawn,
                          isCompactMode: isCompact,
                          onShowDiscard: callbacks.onShowDiscardPile,
                          onDrawCard: callbacks.onDrawCard,
                          onTakeFromDiscard: callbacks.onTakeFromDiscard,
                          reactionTimeTotalMs:
                              mpConfig.reactionTimeTotalMs,
                          enableHaptics: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Gauche - Adversaires
              if (opponents.isNotEmpty)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: sideBandWidth,
                  child: _buildLeftOpponents(
                    context,
                    opponents,
                    isCompact,
                    botCardType,
                    botBadgeSize,
                    blockSpacing,
                    outerGap,
                  ),
                ),

              // Haut - Adversaire position 3 (si 4 joueurs)
              if (opponents.length >= 3)
                Positioned(
                  top: 0,
                  left: sideBandWidth,
                  right: sideBandWidth,
                  height: topBandHeight,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: outerGap),
                      child: _buildOpponentBlock(
                        context,
                        opponents[2],
                        isCompact,
                        botCardType,
                        botBadgeSize,
                        blockSpacing,
                      ),
                    ),
                  ),
                ),

              // Droite - Adversaire position 4 (si 4+ joueurs)
              if (opponents.length >= 4)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: sideBandWidth,
                  child: _buildRightOpponents(
                    context,
                    opponents,
                    isCompact,
                    botCardType,
                    botBadgeSize,
                    blockSpacing,
                    outerGap,
                  ),
                ),

              // Bas - Zone joueur
              if (!isSpectator && human != null)
                Positioned(
                  left: sideBandWidth,
                  right: sideBandWidth,
                  bottom: outerGap,
                  height: playerAreaHeight,
                  child: _buildPlayerArea(
                    context,
                    human,
                    isCompact,
                    playerCardType,
                    playerBadgeSize,
                    blockSpacing,
                    playerAreaHeight,
                    constraints.maxWidth - (sideBandWidth * 2),
                  ),
                ),

              // Spectateur - Bandeau info
              if (isSpectator)
                Positioned(
                  left: sideBandWidth,
                  right: sideBandWidth,
                  bottom: outerGap,
                  height: 60,
                  child: _buildSpectatorBanner(context),
                ),

            ],
          );
        },
      ),
    );
  }

  Widget _buildLeftOpponents(
    BuildContext context,
    List<Player> opponents,
    bool isCompact,
    CardSize cardSize,
    double badgeSize,
    double spacing,
    double outerGap,
  ) {
    if (opponents.length >= 2) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.center,
              child: Padding(
                padding: EdgeInsets.only(left: outerGap),
                child: RotatedBox(
                  quarterTurns: 1,
                  child: _buildOpponentBlock(
                    context,
                    opponents[1],
                    isCompact,
                    cardSize,
                    badgeSize,
                    spacing,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.center,
              child: Padding(
                padding: EdgeInsets.only(left: outerGap),
                child: RotatedBox(
                  quarterTurns: 1,
                  child: _buildOpponentBlock(
                    context,
                    opponents[0],
                    isCompact,
                    cardSize,
                    badgeSize,
                    spacing,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(left: outerGap),
        child: RotatedBox(
          quarterTurns: 1,
          child: _buildOpponentBlock(
            context,
            opponents[0],
            isCompact,
            cardSize,
            badgeSize,
            spacing,
          ),
        ),
      ),
    );
  }

  Widget _buildRightOpponents(
    BuildContext context,
    List<Player> opponents,
    bool isCompact,
    CardSize cardSize,
    double badgeSize,
    double spacing,
    double outerGap,
  ) {
    if (opponents.length >= 5) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.center,
              child: Padding(
                padding: EdgeInsets.only(right: outerGap),
                child: RotatedBox(
                  quarterTurns: 3,
                  child: _buildOpponentBlock(
                    context,
                    opponents[3],
                    isCompact,
                    cardSize,
                    badgeSize,
                    spacing,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.center,
              child: Padding(
                padding: EdgeInsets.only(right: outerGap),
                child: RotatedBox(
                  quarterTurns: 3,
                  child: _buildOpponentBlock(
                    context,
                    opponents[4],
                    isCompact,
                    cardSize,
                    badgeSize,
                    spacing,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.only(right: outerGap),
        child: RotatedBox(
          quarterTurns: 3,
          child: _buildOpponentBlock(
            context,
            opponents[3],
            isCompact,
            cardSize,
            badgeSize,
            spacing,
          ),
        ),
      ),
    );
  }

  Widget _buildOpponentBlock(
    BuildContext context,
    Player opponent,
    bool isCompact,
    CardSize cardSize,
    double badgeSize,
    double spacing,
  ) {
    final isActive = gs.currentPlayer.id == opponent.id;
    final isConnected = mpConfig.playerConnections[opponent.id];
    final isAfk = mpConfig.playerAfkStatus[opponent.id] ?? false;

    final canInteract = gs.isWaitingForSpecialPower &&
        _humanPlayer != null &&
        gs.currentPlayer.id == _humanPlayer!.id;

    return buildOpponentArea(
      context: context,
      opponent: opponent,
      isActive: isActive,
      canInteract: canInteract,
      cardSize: cardSize,
      badgeSize: badgeSize,
      spacing: spacing,
      isCompactMode: isCompact,
      isConnected: isConnected,
      isAfk: isAfk,
      turnStartTime: isActive ? mpConfig.turnStartTime : null,
      turnDuration: isActive ? mpConfig.turnDuration : null,
      onCardTap: canInteract && callbacks.onOpponentCardTap != null
          ? (index) => callbacks.onOpponentCardTap!(opponent.position, index)
          : null,
    );
  }

  Widget _buildPlayerArea(
    BuildContext context,
    Player human,
    bool isCompact,
    CardSize cardSize,
    double badgeSize,
    double spacing,
    double maxHeight,
    double availableWidth,
  ) {
    return buildPlayerAreaWithButtons(
      context: context,
      human: human,
      isMyTurn: _isMyTurn,
      hasDrawn: _hasDrawn,
      canInteractWithCards: _canInteractWithCards,
      isCompactMode: isCompact,
      cardSize: cardSize,
      badgeSize: badgeSize,
      spacing: spacing,
      maxHeight: maxHeight,
      selectedIndices: widget.shakingCardIndices,
      onCardTap: callbacks.onCardTap,
      onDraw: callbacks.onDrawCard,
      onDiscard: callbacks.onDiscardDrawnCard,
      onDutch: () async {
        final confirmed = await GameDialogs.confirmDutch(context);
        if (confirmed == true) {
          callbacks.onCallDutch();
        }
      },
      constrainedWidth: availableWidth,
    );
  }

  Widget _buildSpectatorBanner(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility, color: Colors.amber, size: 24),
            SizedBox(width: 12),
            Text(
              "Mode Spectateur",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
