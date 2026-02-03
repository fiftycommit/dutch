import 'package:flutter/material.dart';
import 'game_action_button.dart';
import '../../utils/ui_constants.dart';

/// Widget réutilisable pour la zone joueur avec boutons d'action
/// Utilisé par game_screen.dart et multiplayer_game_screen.dart
class PlayerAreaWidget extends StatelessWidget {
  final Widget playerBlock;
  final bool isMyTurn;
  final bool hasDrawn;
  final bool isCompactMode;
  final double sideButtonWidth;
  final double sideGap;
  final double actionButtonHeight;
  final double actionButtonMargin;
  final double maxHeight;
  final VoidCallback onDraw;
  final VoidCallback onDiscard;
  final VoidCallback onDutch;

  const PlayerAreaWidget({
    super.key,
    required this.playerBlock,
    required this.isMyTurn,
    required this.hasDrawn,
    required this.isCompactMode,
    required this.sideButtonWidth,
    required this.sideGap,
    required this.actionButtonHeight,
    required this.actionButtonMargin,
    required this.maxHeight,
    required this.onDraw,
    required this.onDiscard,
    required this.onDutch,
  });

  @override
  Widget build(BuildContext context) {
    final fittedPlayerBlock = SizedBox(
      height: maxHeight,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.bottomCenter,
        child: playerBlock,
      ),
    );

    if (isCompactMode) {
      return _buildCompactLayout(fittedPlayerBlock);
    }
    return _buildNormalLayout(fittedPlayerBlock);
  }

  Widget _buildCompactLayout(Widget fittedPlayerBlock) {
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
        fittedPlayerBlock,
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
              border: Border.all(color: Colors.blueAccent),
            ),
            child: const Text(
              "GARDER",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: AppFontSizes.small,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        if (!isMyTurn) SizedBox(width: sideButtonWidth),
      ],
    );
  }

  Widget _buildNormalLayout(Widget fittedPlayerBlock) {
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
                    border: Border.all(color: Colors.blueAccent),
                  ),
                  child: const Text(
                    "GARDER\n(Clique main)",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Classe helper pour calculer les métriques de la zone joueur
class PlayerAreaMetrics {
  final double sideGap;
  final double sideButtonWidth;
  final double actionButtonHeight;
  final double actionButtonMargin;
  final double handMaxWidth;

  const PlayerAreaMetrics({
    required this.sideGap,
    required this.sideButtonWidth,
    required this.actionButtonHeight,
    required this.actionButtonMargin,
    required this.handMaxWidth,
  });
}
