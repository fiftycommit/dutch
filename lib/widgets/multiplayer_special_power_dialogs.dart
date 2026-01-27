import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/card.dart';
import '../models/player.dart';
import '../providers/multiplayer_game_provider.dart';
import 'card_widget.dart';
import 'responsive_dialog.dart';

class MultiplayerSpecialPowerDialogs {
  static const double _cardAspectRatio = 7 / 5;

  static double _cardWidthForGrid(DialogMetrics metrics,
      {required int columns, double maxHeightFraction = 0.35}) {
    final spacing = metrics.space(8);
    final widthByCols = columns > 0
        ? (metrics.contentWidth - spacing * (columns - 1)) / columns
        : metrics.contentWidth;
    final heightByRows =
        (metrics.contentHeight * maxHeightFraction) / _cardAspectRatio;
    return math.max(0.0, math.min(widthByCols, heightByRows));
  }

  static Widget _scaledCard(
      {required double width, required bool isRevealed, PlayingCard? card}) {
    final height = width * _cardAspectRatio;
    return SizedBox(
      width: width,
      height: height,
      child: FittedBox(
        fit: BoxFit.contain,
        child: CardWidget(
          card: card,
          size: CardSize.large,
          isRevealed: isRevealed,
        ),
      ),
    );
  }

  // 7 & 8: Look at one of YOUR OWN cards
  static void showLookOwnCardDialog(BuildContext context, PlayingCard trigger) {
    final gameProvider =
        Provider.of<MultiplayerGameProvider>(context, listen: false);
    final gameState = gameProvider.gameState!;
    // Find "me"
    final me =
        gameState.players.firstWhere((p) => p.id == gameProvider.playerId);
    final myIndex = gameState.players.indexOf(me);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: Colors.black87,
        builder: (context, metrics) {
          final spacing = metrics.space(12);
          final smallSpacing = metrics.space(8);
          final iconSize = metrics.size(40);
          final titleSize = metrics.font(20);
          final bodySize = metrics.font(14);
          final buttonSize = metrics.font(16);
          final columns = math.min(me.hand.length, 4);
          final cardWidth = _cardWidthForGrid(metrics,
              columns: columns, maxHeightFraction: 0.35);
          final borderWidth = math.max(1.0, metrics.scale * 2);

          return SingleChildScrollView(
            child: SizedBox(
              width: metrics.contentWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.visibility, color: Colors.amber, size: iconSize),
                  SizedBox(height: smallSpacing),
                  Text(
                    "👁️ REGARDER UNE CARTE",
                    style: TextStyle(
                        color: Colors.amber,
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: smallSpacing),
                  Text(
                    "Choisissez UNE de vos cartes à regarder",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: bodySize),
                  ),
                  SizedBox(height: spacing),
                  Wrap(
                    spacing: smallSpacing,
                    runSpacing: smallSpacing,
                    alignment: WrapAlignment.center,
                    children: List.generate(me.hand.length, (index) {
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          // In multiplayer, looking at own card is a "Special Power" action targeting self
                          gameProvider.useSpecialPower(myIndex, index);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: Colors.amber, width: borderWidth),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _scaledCard(
                            width: cardWidth,
                            isRevealed: false, // Hidden until server confirms
                          ),
                        ),
                      );
                    }),
                  ),
                  SizedBox(height: spacing),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      gameProvider.skipSpecialPower();
                    },
                    child: Text(
                      "PASSER",
                      style: TextStyle(
                          color: Colors.white54, fontSize: buttonSize),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // 9 & 10: Look at opponent card (9) or Swap (10 - part 1)
  static void showOpponentSelectionDialog(
      BuildContext context, PlayingCard trigger, bool isSwap) {
    final gameProvider =
        Provider.of<MultiplayerGameProvider>(context, listen: false);
    final gameState = gameProvider.gameState!;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: Colors.black87,
        builder: (context, metrics) {
          final iconSize = metrics.size(40);
          final titleSize = metrics.font(20);

          return SingleChildScrollView(
            child: SizedBox(
              width: metrics.contentWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(isSwap ? Icons.swap_horiz : Icons.visibility,
                      color: isSwap ? Colors.purple : Colors.amber,
                      size: iconSize),
                  SizedBox(height: metrics.space(8)),
                  Text(
                    isSwap ? "ÉCHANGE" : "ESPIONNER",
                    style: TextStyle(
                        color: isSwap ? Colors.purple : Colors.amber,
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: metrics.space(8)),
                  _buildOpponentSelection(
                      context, gameProvider, gameState, metrics, isSwap),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static Widget _buildOpponentSelection(BuildContext context,
      MultiplayerGameProvider gp, state, DialogMetrics metrics, bool isSwap) {
    final meId = gp.playerId;
    List<Player> opponents = state.players
        .where((p) => p.id != meId && p.hand.isNotEmpty)
        .toList()
        .cast<Player>();

    if (opponents.isEmpty) {
      return Column(children: [
        Text("Personne à cibler !", style: TextStyle(color: Colors.white)),
        TextButton(
            onPressed: () {
              Navigator.pop(context);
              gp.skipSpecialPower();
            },
            child: Text("Passer"))
      ]);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("Choisissez un adversaire :",
            style: TextStyle(color: Colors.white, fontSize: metrics.font(14))),
        SizedBox(height: metrics.space(10)),
        Wrap(
          spacing: metrics.space(10),
          runSpacing: metrics.space(10),
          alignment: WrapAlignment.center,
          children: opponents.map((opponent) {
            return ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _showOpponentCardSelection(
                    context, gp, opponent, metrics, isSwap);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                padding: EdgeInsets.symmetric(
                    horizontal: metrics.space(14), vertical: metrics.space(10)),
              ),
              child: Text("${opponent.displayAvatar} ${opponent.name}",
                  style: TextStyle(fontSize: metrics.font(14))),
            );
          }).toList(),
        ),
        SizedBox(height: metrics.space(16)),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            gp.skipSpecialPower();
          },
          child: Text(
            "PASSER",
            style: TextStyle(color: Colors.white54, fontSize: metrics.font(16)),
          ),
        ),
      ],
    );
  }

  static void _showOpponentCardSelection(
      BuildContext context,
      MultiplayerGameProvider gp,
      Player opponent,
      DialogMetrics metrics,
      bool isSwap) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: Colors.black87,
        builder: (context, dialogMetrics) {
          final spacing = dialogMetrics.space(12);
          final titleSize = dialogMetrics.font(18);
          final buttonSize = dialogMetrics.font(16);
          final columns = math.min(opponent.hand.length, 4);
          final cardWidth = _cardWidthForGrid(dialogMetrics,
              columns: columns, maxHeightFraction: 0.35);
          final borderWidth = math.max(1.0, dialogMetrics.scale * 2);

          return SingleChildScrollView(
            child: SizedBox(
              width: dialogMetrics.contentWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Cartes de ${opponent.name}",
                    style: TextStyle(
                        color: Colors.amber,
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: spacing),
                  Wrap(
                    spacing: dialogMetrics.space(8),
                    runSpacing: dialogMetrics.space(8),
                    alignment: WrapAlignment.center,
                    children: List.generate(opponent.hand.length, (index) {
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          // Execute action (Look or Swap-Step-1)
                          // Mapping opponent back to global index
                          final targetIndex =
                              gp.gameState!.players.indexOf(opponent);
                          gp.useSpecialPower(targetIndex, index);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: Colors.blue, width: borderWidth),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _scaledCard(
                            width: cardWidth,
                            isRevealed: false,
                          ),
                        ),
                      );
                    }),
                  ),
                  SizedBox(height: spacing),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      gp.skipSpecialPower();
                    },
                    child: Text(
                      "PASSER",
                      style: TextStyle(
                          color: Colors.white54, fontSize: buttonSize),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // JOKER: Shuffle opponent
  static void showJokerDialog(BuildContext context, PlayingCard trigger) {
    final gameProvider =
        Provider.of<MultiplayerGameProvider>(context, listen: false);
    final gameState = gameProvider.gameState!;
    final meId = gameProvider.playerId;

    // Find opponents
    List<Player> opponents =
        gameState.players.where((p) => p.id != meId).toList();

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => ResponsiveDialog(
            backgroundColor: Colors.black87,
            builder: (context, metrics) {
              return SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.shuffle,
                    color: Colors.orange, size: metrics.size(40)),
                Text("JOKER : MÉLANGE",
                    style: TextStyle(
                        color: Colors.orange, fontSize: metrics.font(20))),
                SizedBox(height: metrics.space(10)),
                Text("Choisissez un adversaire à mélanger",
                    style: TextStyle(color: Colors.white)),
                SizedBox(height: metrics.space(10)),
                Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: opponents
                        .map((opp) => ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange),
                            onPressed: () {
                              Navigator.pop(ctx);
                              final idx = gameState.players.indexOf(opp);
                              gameProvider.useSpecialPower(
                                  idx, 0); // Card index 0 is dummy
                            },
                            child: Text(opp.name)))
                        .toList()),
                TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      gameProvider.skipSpecialPower();
                    },
                    child: Text("PASSER"))
              ]));
            }));
  }

  // Own Card Selection (Step 2 of Swap)
  static void showCompleteSwapDialog(BuildContext context) {
    final gameProvider =
        Provider.of<MultiplayerGameProvider>(context, listen: false);
    final gameState = gameProvider.gameState!;
    // Find "me"
    final me =
        gameState.players.firstWhere((p) => p.id == gameProvider.playerId);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: Colors.black87,
        builder: (context, metrics) {
          final spacing = metrics.space(12);
          final titleSize = metrics.font(18);
          final columns = math.min(me.hand.length, 4);
          final cardWidth = _cardWidthForGrid(metrics,
              columns: columns, maxHeightFraction: 0.35);

          return SingleChildScrollView(
            child: SizedBox(
              width: metrics.contentWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Donnez une de vos cartes",
                    style: TextStyle(
                        color: Colors.purple,
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: spacing),
                  Wrap(
                    spacing: metrics.space(8),
                    runSpacing: metrics.space(8),
                    alignment: WrapAlignment.center,
                    children: List.generate(me.hand.length, (index) {
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          gameProvider.completeSwap(index);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.amber, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _scaledCard(
                            width: cardWidth,
                            isRevealed: false, // My cards
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
