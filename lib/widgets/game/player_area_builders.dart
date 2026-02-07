import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:dutch_game/utils/screen_utils.dart';
import 'package:dutch_game/utils/ui_constants.dart';
import 'package:dutch_game/widgets/game/game_action_button.dart';

/// Construit la zone joueur en mode compact (petits écrans).
Widget buildCompactPlayerArea({
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
                        fontSize: AppFontSizes.small,
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
                  fontSize: AppFontSizes.small,
                  fontWeight: FontWeight.bold)),
        ),
      if (!isMyTurn) SizedBox(width: sideButtonWidth),
    ],
  );
}

/// Construit la zone joueur en mode normal (grands écrans).
Widget buildNormalPlayerArea({
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
