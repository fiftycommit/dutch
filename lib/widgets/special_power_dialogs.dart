import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/card.dart';
import '../models/player.dart';
import '../providers/game_provider.dart';
import 'card_widget.dart';
import 'responsive_dialog.dart';

class SpecialPowerDialogs {
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
      {required double width,
      required bool isRevealed,
      PlayingCard? card}) {
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
  // Carte 7 : Regarder UNE de ses cartes
  static void showLookCardDialog(
      BuildContext context, PlayingCard trigger, bool ownCard) {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final gameState = gameProvider.gameState!;
    final humanPlayer = gameState.players.firstWhere((p) => p.isHuman);

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
          final columns = math.min(humanPlayer.hand.length, 4);
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
                    ownCard ? "👁️ REGARDER UNE CARTE" : "👁 ESPIONNER",
                    style: TextStyle(
                        color: Colors.amber,
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: smallSpacing),
                  Text(
                    ownCard
                        ? "Choisissez UNE de vos cartes à regarder"
                        : "Choisissez un adversaire puis une de ses cartes",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: bodySize),
                  ),
                  SizedBox(height: spacing),
                  if (ownCard) ...[
                    Wrap(
                      spacing: smallSpacing,
                      runSpacing: smallSpacing,
                      alignment: WrapAlignment.center,
                      children: List.generate(humanPlayer.hand.length, (index) {
                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(ctx);
                            _showCardRevealed(context, humanPlayer, index,
                                humanPlayer.hand[index]);
                            gameProvider.executeLookAtCard(humanPlayer, index);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              border:
                                  Border.all(color: Colors.amber, width: borderWidth),
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
                        gameProvider.skipSpecialPower();
                      },
                      child: Text(
                        "PASSER",
                        style: TextStyle(color: Colors.white54, fontSize: buttonSize),
                      ),
                    ),
                  ] else ...[
                    _buildOpponentSelection(context, gameProvider, gameState, metrics),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static void _showCardRevealed(
      BuildContext context, Player player, int index, PlayingCard card) {
    player.knownCards[index] = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: Colors.black87,
        builder: (context, metrics) {
          const aspect = _cardAspectRatio;

          return SizedBox(
            width: metrics.contentWidth,
            height: metrics.contentHeight,
            child: Column(
              children: [
                Expanded(
                  flex: 22,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final height = constraints.maxHeight;
                      final iconSize = height * 0.45;
                      final titleSize = height * 0.22;
                      final gap = height * 0.08;

                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle,
                                color: Colors.green, size: iconSize),
                            SizedBox(height: gap),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                "CARTE RÉVÉLÉE",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: titleSize,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Expanded(
                  flex: 56,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final maxWidth = constraints.maxWidth;
                      final maxHeight = constraints.maxHeight;
                      final cardWidth = math.max(
                        0.0,
                        math.min(maxWidth * 0.8, maxHeight / aspect),
                      );
                      final cardHeight = cardWidth * aspect;

                      return Center(
                        child: SizedBox(
                          width: cardWidth,
                          height: cardHeight,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: CardWidget(
                              card: card,
                              size: CardSize.large,
                              isRevealed: true,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Expanded(
                  flex: 22,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final height = constraints.maxHeight;
                      final valueSize = height * 0.22;
                      final gap = height * 0.12;
                      final buttonHeight = height * 0.48;
                      final buttonWidth = constraints.maxWidth * 0.6;

                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              "${card.value} (${card.points} pts)",
                              style: TextStyle(
                                color: Colors.amber,
                                fontSize: valueSize,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                            ),
                          ),
                          SizedBox(height: gap),
                          SizedBox(
                            width: buttonWidth,
                            height: buttonHeight,
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  "OK",
                                  style: TextStyle(fontSize: valueSize),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static Widget _buildOpponentSelection(
      BuildContext context, GameProvider gp, gameState, DialogMetrics metrics) {

    List<Player> opponents =
        gameState.players.where((p) => !p.isHuman && p.hand.isNotEmpty).toList();

    if (opponents.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Aucun adversaire n'a de cartes !",
              style: TextStyle(color: Colors.redAccent, fontSize: metrics.font(14))),
          SizedBox(height: metrics.space(16)),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              gp.skipSpecialPower();
            },
            child: Text(
              "OK",
              style: TextStyle(color: Colors.white54, fontSize: metrics.font(16)),
            ),
          ),
        ],
      );
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
                _showOpponentCardSelection(context, gp, opponent, metrics);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                padding: EdgeInsets.symmetric(
                    horizontal: metrics.space(14),
                    vertical: metrics.space(10)),
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
      BuildContext context, GameProvider gp, Player opponent, DialogMetrics metrics) {

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
                          _showCardRevealed(
                              context, opponent, index, opponent.hand[index]);
                          gp.executeLookAtCard(opponent, index);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: Colors.blue, width: borderWidth),
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
                      style: TextStyle(color: Colors.white54, fontSize: buttonSize),
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


  static void showValetSwapDialog(BuildContext context, PlayingCard trigger) {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final gameState = gameProvider.gameState!;
    final allPlayers = gameState.players;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: Colors.black87,
        builder: (context, metrics) {
          final gapS = metrics.space(8);
          final gapM = metrics.space(16);
          final iconSize = metrics.size(40);
          final titleSize = metrics.font(20);
          final bodySize = metrics.font(14);
          final buttonSize = metrics.font(16);
          final buttonHeight = metrics.space(56);
          final buttonWidth = metrics.contentWidth;

          return SingleChildScrollView(
            child: SizedBox(
              width: metrics.contentWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_horiz, color: Colors.purple, size: iconSize),
                  SizedBox(height: gapS),
                  Text(
                    "🤵 VALET : ÉCHANGE",
                    style: TextStyle(
                        color: Colors.purple,
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: gapS),
                  Text(
                    "Échangez 2 cartes à l'aveugle",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: bodySize),
                  ),
                  SizedBox(height: gapM),
                  SizedBox(
                    width: buttonWidth,
                    height: buttonHeight,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showUniversalSwap(context, gameProvider, allPlayers);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade700,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        "CHOISIR\n2 CARTES",
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: buttonSize,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                    ),
                  ),
                  SizedBox(height: gapM),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      gameProvider.skipSpecialPower();
                    },
                    child: Text("ANNULER",
                        style: TextStyle(
                            color: Colors.white54, fontSize: metrics.font(14))),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }


  static void _showUniversalSwap(
      BuildContext context, GameProvider gp, List<Player> allPlayers) {
    Player? player1;
    int? card1;
    Player? player2;
    int? card2;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return ResponsiveDialog(
            backgroundColor: Colors.black87,
            builder: (context, metrics) {
              final spacing = metrics.space(8);
              final sectionSpacing = metrics.space(16);
              final titleSize = metrics.font(14);
              final buttonSize = metrics.font(16);
              final buttonPad = metrics.space(12);
              final cardBorderWidth = math.max(1.0, metrics.scale * 1.5);
              final cardWidth = _cardWidthForGrid(metrics,
                  columns: 6, maxHeightFraction: 0.18);

              return SingleChildScrollView(
                child: SizedBox(
                  width: metrics.contentWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("1️⃣ Joueur A :",
                          style: TextStyle(
                              color: Colors.white, fontSize: titleSize)),
                      SizedBox(height: spacing),
                      Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: allPlayers.map((p) {
                          final isSelected = player1?.id == p.id;
                          return GestureDetector(
                            onTap: () => setState(() {
                              player1 = p;
                              card1 = null;
                            }),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: metrics.space(12),
                                  vertical: metrics.space(8)),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.blue.shade700
                                    : Colors.blue.shade900,
                                border: Border.all(
                                    color: isSelected
                                        ? Colors.amber
                                        : Colors.white30),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(p.isHuman ? "Vous" : p.name,
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: metrics.font(12))),
                            ),
                          );
                        }).toList(),
                      ),
                      if (player1 != null) ...[
                        SizedBox(height: sectionSpacing),
                        Text(
                            "2️⃣ Carte de ${player1!.isHuman ? 'votre main' : player1!.name} :",
                            style: TextStyle(
                                color: Colors.white, fontSize: titleSize)),
                        SizedBox(height: spacing),
                        Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: List.generate(player1!.hand.length, (index) {
                            final isSelected = card1 == index;
                            return GestureDetector(
                              onTap: () => setState(() => card1 = index),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.amber
                                        : Colors.white30,
                                    width: isSelected ? cardBorderWidth * 2 : cardBorderWidth,
                                  ),
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
                      ],
                      SizedBox(height: sectionSpacing),
                      Text("3️⃣ Joueur B :",
                          style: TextStyle(
                              color: Colors.white, fontSize: titleSize)),
                      SizedBox(height: spacing),
                      Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children:
                            allPlayers.where((p) => p.id != player1?.id).map((p) {
                          final isSelected = player2?.id == p.id;
                          return GestureDetector(
                            onTap: () => setState(() {
                              player2 = p;
                              card2 = null;
                            }),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: metrics.space(12),
                                  vertical: metrics.space(8)),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.red.shade700
                                    : Colors.red.shade900,
                                border: Border.all(
                                    color: isSelected
                                        ? Colors.amber
                                        : Colors.white30),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(p.isHuman ? "Vous" : p.name,
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: metrics.font(12))),
                            ),
                          );
                        }).toList(),
                      ),
                      if (player2 != null) ...[
                        SizedBox(height: sectionSpacing),
                        Text(
                            "4️⃣ Carte de ${player2!.isHuman ? 'votre main' : player2!.name} :",
                            style: TextStyle(
                                color: Colors.white, fontSize: titleSize)),
                        SizedBox(height: spacing),
                        Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: List.generate(player2!.hand.length, (index) {
                            final isSelected = card2 == index;
                            return GestureDetector(
                              onTap: () => setState(() => card2 = index),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.amber
                                        : Colors.white30,
                                    width: isSelected ? cardBorderWidth * 2 : cardBorderWidth,
                                  ),
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
                      ],
                      SizedBox(height: sectionSpacing),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              gp.skipSpecialPower();
                            },
                            child: Text("ANNULER",
                                style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: metrics.font(14))),
                          ),
                          ElevatedButton(
                            onPressed: (player1 != null &&
                                    card1 != null &&
                                    player2 != null &&
                                    card2 != null)
                                ? () {
                                    Navigator.pop(ctx);

                                    String name1 =
                                        player1!.isHuman ? "Vous" : player1!.name;
                                    String name2 =
                                        player2!.isHuman ? "Vous" : player2!.name;

                                    _showSwapNotification(
                                        context, name1, card1!, name2, card2!);

                                    final p1 = gp.gameState!.players
                                        .firstWhere((p) => p.id == player1!.id);
                                    final p2 = gp.gameState!.players
                                        .firstWhere((p) => p.id == player2!.id);

                                    final temp = p1.hand[card1!];
                                    p1.hand[card1!] = p2.hand[card2!];
                                    p2.hand[card2!] = temp;

                                    p1.knownCards[card1!] = false;
                                    p2.knownCards[card2!] = false;

                                    gp.gameState!.addToHistory(
                                        "🔄 Échange : $name1 carte #${card1! + 1} ↔ $name2 carte #${card2! + 1}.");

                                    gp.skipSpecialPower();
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                              padding: EdgeInsets.symmetric(
                                  horizontal: metrics.space(20), vertical: buttonPad),
                            ),
                            child: Text("ÉCHANGER",
                                style: TextStyle(fontSize: buttonSize)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static void _showSwapNotification(BuildContext context, String player1,
      int card1, String player2, int card2) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: Colors.purple.shade900,
        builder: (context, metrics) {
          final gapS = metrics.space(12);
          final gapM = metrics.space(20);
          final iconSize = metrics.size(50);
          final titleSize = metrics.font(20);
          final bodySize = metrics.font(14);
          final buttonSize = metrics.font(16);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_horiz, color: Colors.white, size: iconSize),
              SizedBox(height: gapS),
              Text(
                "ÉCHANGE EFFECTUÉ",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: titleSize,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: gapS),
              Text(
                "$player1 carte #${card1 + 1} ↔ $player2 carte #${card2 + 1}",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: bodySize),
              ),
              SizedBox(height: gapM),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.purple.shade900,
                  padding: EdgeInsets.symmetric(
                      horizontal: metrics.space(28),
                      vertical: metrics.space(12)),
                ),
                child: Text("OK",
                    style:
                        TextStyle(fontSize: buttonSize, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }


  static void showJokerDialog(BuildContext context, PlayingCard trigger) {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final gameState = gameProvider.gameState!;
    final allPlayers = gameState.players;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: Colors.black87,
        builder: (context, metrics) {
          final gapS = metrics.space(8);
          final gapM = metrics.space(16);
          final iconSize = metrics.size(40);
          final titleSize = metrics.font(20);
          final bodySize = metrics.font(14);
          final buttonSize = metrics.font(14);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shuffle, color: Colors.red, size: iconSize),
              SizedBox(height: gapS),
              Text(
                "🃏 JOKER : CHAOS",
                style: TextStyle(
                    color: Colors.red,
                    fontSize: titleSize,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: gapS),
              Text(
                "Choisissez un joueur pour mélanger sa main",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: bodySize),
              ),
              SizedBox(height: gapM),
              Wrap(
                spacing: metrics.space(12),
                runSpacing: metrics.space(8),
                alignment: WrapAlignment.center,
                children: allPlayers.map((player) {
                  return ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showShuffleNotification(context, player);
                      gameProvider.executeJokerEffect(player);
                    },
                    icon: Icon(player.isHuman ? Icons.person : Icons.smart_toy,
                        size: metrics.size(20)),
                    label: Text(player.name,
                        style: TextStyle(fontSize: buttonSize)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: player.isHuman
                          ? Colors.amber.shade700
                          : Colors.blue.shade800,
                      padding: EdgeInsets.symmetric(
                          horizontal: metrics.space(14),
                          vertical: metrics.space(10)),
                    ),
                  );
                }).toList(),
              ),
              SizedBox(height: gapM),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  gameProvider.skipSpecialPower();
                },
                child: Text("ANNULER",
                    style: TextStyle(
                        color: Colors.white54, fontSize: metrics.font(14))),
              ),
            ],
          );
        },
      ),
    );
  }

  static void _showShuffleNotification(BuildContext context, Player target) {
    final isMe = target.isHuman;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: Colors.red.shade900,
        builder: (context, metrics) {
          final gapS = metrics.space(12);
          final gapM = metrics.space(20);
          final iconSize = metrics.size(50);
          final titleSize = metrics.font(20);
          final bodySize = metrics.font(14);
          final buttonSize = metrics.font(16);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shuffle, color: Colors.white, size: iconSize),
              SizedBox(height: gapS),
              Text(
                isMe
                    ? "VOS CARTES ONT ÉTÉ MÉLANGÉES !"
                    : "CARTES DE ${target.name.toUpperCase()} MÉLANGÉES !",
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: titleSize,
                    fontWeight: FontWeight.bold),
              ),
              SizedBox(height: gapS),
              Text(
                isMe
                    ? "Vous ne savez plus où sont vos cartes !"
                    : "${target.name} ne sait plus où sont ses cartes !",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: bodySize),
              ),
              SizedBox(height: gapM),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red.shade900,
                  padding: EdgeInsets.symmetric(
                      horizontal: metrics.space(28),
                      vertical: metrics.space(12)),
                ),
                child: Text("OK",
                    style:
                        TextStyle(fontSize: buttonSize, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  static void showBotSwapNotification(BuildContext context, Player bot,
      String targetName, int targetCardIndex) {

    String botDisplay = _getBotPositionDisplay(context, bot);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: Colors.purple.shade900,
        builder: (context, metrics) {
          final gapS = metrics.space(12);
          final gapM = metrics.space(20);
          final iconSize = metrics.size(50);
          final titleSize = metrics.font(20);
          final bodySize = metrics.font(14);
          final alertSize = metrics.font(12);
          final buttonSize = metrics.font(16);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_horiz, color: Colors.white, size: iconSize),
              SizedBox(height: gapS),
              Text(
                "🤵 VALET !",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: titleSize,
                    fontWeight: FontWeight.bold),
              ),
              SizedBox(height: gapS),
              Text(
                "$botDisplay a échangé une carte avec ${targetName == "Vous" ? "vous" : targetName} !",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: bodySize),
              ),
              if (targetName == "Vous") ...[
                SizedBox(height: metrics.space(8)),
                Text(
                  "Votre carte #${targetCardIndex + 1} a été échangée",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.amber,
                      fontSize: alertSize,
                      fontWeight: FontWeight.bold),
                ),
              ],
              SizedBox(height: gapM),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.purple.shade900,
                  padding: EdgeInsets.symmetric(
                      horizontal: metrics.space(28),
                      vertical: metrics.space(12)),
                ),
                child: Text("OK",
                    style:
                        TextStyle(fontSize: buttonSize, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  static void showBotJokerNotification(
      BuildContext context, Player bot, String targetName) {
    final isMe = targetName == "Vous";

    String botDisplay = _getBotPositionDisplay(context, bot);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: Colors.red.shade900,
        builder: (context, metrics) {
          final gapS = metrics.space(12);
          final gapM = metrics.space(20);
          final iconSize = metrics.size(50);
          final titleSize = metrics.font(20);
          final bodySize = metrics.font(14);
          final alertSize = metrics.font(12);
          final buttonSize = metrics.font(16);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shuffle, color: Colors.white, size: iconSize),
              SizedBox(height: gapS),
              Text(
                isMe
                    ? "VOS CARTES ONT ÉTÉ MÉLANGÉES !"
                    : "CARTES DE ${targetName.toUpperCase()} MÉLANGÉES !",
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: titleSize,
                    fontWeight: FontWeight.bold),
              ),
              SizedBox(height: gapS),
              Text(
                "$botDisplay a utilisé le Joker !",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: bodySize),
              ),
              SizedBox(height: metrics.space(8)),
              Text(
                isMe
                    ? "Vous ne savez plus où sont vos cartes !"
                    : "$targetName ne sait plus où sont ses cartes !",
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.amber,
                    fontSize: alertSize,
                    fontWeight: FontWeight.bold),
              ),
              SizedBox(height: gapM),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red.shade900,
                  padding: EdgeInsets.symmetric(
                      horizontal: metrics.space(28),
                      vertical: metrics.space(12)),
                ),
                child: Text("OK",
                    style:
                        TextStyle(fontSize: buttonSize, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _getBotPositionDisplay(BuildContext context, Player bot) {
    try {
      final gameProvider = Provider.of<GameProvider>(context, listen: false);
      final players = gameProvider.gameState?.players;
      if (players == null) return bot.name;
      
      // Trouver l'index du bot
      int index = players.indexWhere((p) => p.id == bot.id);
      String position;
      
      switch (index) {
        case 1:
          position = "Bot Gauche";
          break;
        case 2:
          position = "Bot Haut";
          break;
        case 3:
          position = "Bot Droite";
          break;
        default:
          position = "";
      }
      
      return "${bot.displayAvatar} $position";
    } catch (e) {
      return bot.name;
    }
  }
}
