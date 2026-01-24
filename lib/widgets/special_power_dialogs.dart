import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/card.dart';
import '../models/player.dart';
import '../providers/game_provider.dart';
import 'card_widget.dart';

class SpecialPowerDialogs {
  // Carte 7 : Regarder UNE de ses cartes
  static void showLookCardDialog(
      BuildContext context, PlayingCard trigger, bool ownCard) {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final gameState = gameProvider.gameState!;
    final humanPlayer = gameState.players.firstWhere((p) => p.isHuman);
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenHeight < 400;
    final cardSize = isCompact ? CardSize.small : CardSize.medium;
    final padding = isCompact ? 12.0 : 20.0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black87,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: EdgeInsets.symmetric(
          horizontal: isCompact ? 24 : 40,
          vertical: isCompact ? 16 : 24,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.visibility, color: Colors.amber, size: isCompact ? 32 : 40),
                  SizedBox(height: isCompact ? 8 : 12),
                  Text(
                    ownCard ? "👁️ REGARDER UNE CARTE" : "👁 ESPIONNER",
                    style: TextStyle(
                        color: Colors.amber,
                        fontSize: isCompact ? 16 : 20,
                        fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: isCompact ? 4 : 8),
                  Text(
                    ownCard
                        ? "Choisissez UNE de vos cartes à regarder"
                        : "Choisissez un adversaire puis une de ses cartes",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: isCompact ? 12 : 14),
                  ),
                  SizedBox(height: isCompact ? 12 : 20),
                  if (ownCard) ...[
                    Wrap(
                      spacing: isCompact ? 6 : 8,
                      runSpacing: isCompact ? 6 : 8,
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
                              border: Border.all(color: Colors.amber, width: 2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: CardWidget(
                              card: null,
                              size: cardSize,
                              isRevealed: false,
                            ),
                          ),
                        );
                      }),
                    ),
                    SizedBox(height: isCompact ? 12 : 20),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        gameProvider.skipSpecialPower();
                      },
                      child: Text(
                        "PASSER",
                        style: TextStyle(color: Colors.white54, fontSize: isCompact ? 14 : 16),
                      ),
                    ),
                  ] else ...[
                    _buildOpponentSelection(context, gameProvider, gameState, isCompact),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void _showCardRevealed(
      BuildContext context, Player player, int index, PlayingCard card) {
    player.knownCards[index] = true;

    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenHeight < 400;
    // iPhone: carte plus petite pour tenir sans scroll, pas de bottom overflow
    final cardSize = isCompact ? CardSize.small : CardSize.large;
    final padding = isCompact ? 10.0 : 20.0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black87,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: EdgeInsets.symmetric(
          horizontal: isCompact ? 28 : 40,
          vertical: isCompact ? 12 : 24,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: screenHeight * (isCompact ? 0.7 : 0.85),
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: isCompact ? 24 : 40),
                  SizedBox(height: isCompact ? 4 : 12),
                  Text(
                    "CARTE RÉVÉLÉE",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: isCompact ? 12 : 18,
                        fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: isCompact ? 6 : 20),
                  CardWidget(card: card, size: cardSize, isRevealed: true),
                  SizedBox(height: isCompact ? 6 : 20),
                  Text(
                    "${card.value} (${card.points} pts)",
                    style: TextStyle(
                        color: Colors.amber,
                        fontSize: isCompact ? 11 : 16,
                        fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: isCompact ? 8 : 20),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? 16 : 32,
                        vertical: isCompact ? 6 : 12,
                      ),
                    ),
                    child: Text("OK", style: TextStyle(fontSize: isCompact ? 13 : 16)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildOpponentSelection(
      BuildContext context, GameProvider gp, gameState, [bool isCompact = false]) {

    List<Player> opponents =
        gameState.players.where((p) => !p.isHuman && p.hand.isNotEmpty).toList();

    if (opponents.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Aucun adversaire n'a de cartes !",
              style: TextStyle(color: Colors.redAccent, fontSize: isCompact ? 12 : 14)),
          SizedBox(height: isCompact ? 12 : 20),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              gp.skipSpecialPower();
            },
            child: Text(
              "OK",
              style: TextStyle(color: Colors.white54, fontSize: isCompact ? 14 : 16),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("Choisissez un adversaire :",
            style: TextStyle(color: Colors.white, fontSize: isCompact ? 12 : 14)),
        SizedBox(height: isCompact ? 8 : 12),
        Wrap(
          spacing: isCompact ? 8 : 12,
          runSpacing: isCompact ? 8 : 12,
          alignment: WrapAlignment.center,
          children: opponents.map((opponent) {
            return ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _showOpponentCardSelection(context, gp, opponent, isCompact);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 12 : 16,
                    vertical: isCompact ? 8 : 12),
              ),
              child: Text("${opponent.displayAvatar} ${opponent.name}",
                  style: TextStyle(fontSize: isCompact ? 12 : 14)),
            );
          }).toList(),
        ),
        SizedBox(height: isCompact ? 12 : 20),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            gp.skipSpecialPower();
          },
          child: Text(
            "PASSER",
            style: TextStyle(color: Colors.white54, fontSize: isCompact ? 14 : 16),
          ),
        ),
      ],
    );
  }

  static void _showOpponentCardSelection(
      BuildContext context, GameProvider gp, Player opponent, [bool isCompact = false]) {
    final screenHeight = MediaQuery.of(context).size.height;
    final cardSize = isCompact ? CardSize.small : CardSize.medium;
    final padding = isCompact ? 12.0 : 20.0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black87,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: EdgeInsets.symmetric(
          horizontal: isCompact ? 24 : 40,
          vertical: isCompact ? 16 : 24,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Cartes de ${opponent.name}",
                    style: TextStyle(
                        color: Colors.amber,
                        fontSize: isCompact ? 14 : 18,
                        fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: isCompact ? 12 : 20),
                  Wrap(
                    spacing: isCompact ? 6 : 8,
                    runSpacing: isCompact ? 6 : 8,
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
                            border: Border.all(color: Colors.blue, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: CardWidget(
                            card: null,
                            size: cardSize,
                            isRevealed: false,
                          ),
                        ),
                      );
                    }),
                  ),
                  SizedBox(height: isCompact ? 12 : 20),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      gp.skipSpecialPower();
                    },
                    child: Text(
                      "PASSER",
                      style: TextStyle(color: Colors.white54, fontSize: isCompact ? 14 : 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black87,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.swap_horiz, color: Colors.purple, size: 40),
              const SizedBox(height: 12),
              const Text(
                "🤵 VALET : ÉCHANGE",
                style: TextStyle(
                    color: Colors.purple,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Échangez 2 cartes à l'aveugle",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showUniversalSwap(context, gameProvider, allPlayers);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade700,
                  minimumSize: const Size(250, 50),
                ),
                child: const Text("CHOISIR 2 CARTES",
                    style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  gameProvider.skipSpecialPower();
                },
                child: const Text("ANNULER",
                    style: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
        ),
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
          return Dialog(
            backgroundColor: Colors.black87,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("1️⃣ Joueur A :",
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: allPlayers.map((p) {
                        bool isSelected = player1?.id == p.id;
                        return GestureDetector(
                          onTap: () => setState(() {
                            player1 = p;
                            card1 = null;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
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
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                          ),
                        );
                      }).toList(),
                    ),
                    if (player1 != null) ...[
                      const SizedBox(height: 16),
                      Text(
                          "2️⃣ Carte de ${player1!.isHuman ? 'votre main' : player1!.name} :",
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: List.generate(player1!.hand.length, (index) {
                          bool isSelected = card1 == index;
                          return GestureDetector(
                            onTap: () => setState(() => card1 = index),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.amber
                                      : Colors.white30,
                                  width: isSelected ? 3 : 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const CardWidget(
                                  card: null,
                                  size: CardSize.small,
                                  isRevealed: false),
                            ),
                          );
                        }),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Text("3️⃣ Joueur B :",
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children:
                          allPlayers.where((p) => p.id != player1?.id).map((p) {
                        bool isSelected = player2?.id == p.id;
                        return GestureDetector(
                          onTap: () => setState(() {
                            player2 = p;
                            card2 = null;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
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
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                          ),
                        );
                      }).toList(),
                    ),
                    if (player2 != null) ...[
                      const SizedBox(height: 16),
                      Text(
                          "4️⃣ Carte de ${player2!.isHuman ? 'votre main' : player2!.name} :",
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: List.generate(player2!.hand.length, (index) {
                          bool isSelected = card2 == index;
                          return GestureDetector(
                            onTap: () => setState(() => card2 = index),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.amber
                                      : Colors.white30,
                                  width: isSelected ? 3 : 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const CardWidget(
                                  card: null,
                                  size: CardSize.small,
                                  isRevealed: false),
                            ),
                          );
                        }),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            gp.skipSpecialPower();
                          },
                          child: const Text("ANNULER",
                              style: TextStyle(color: Colors.white54)),
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

                                  // Effectuer l'échange
                                  final p1 = gp.gameState!.players
                                      .firstWhere((p) => p.id == player1!.id);
                                  final p2 = gp.gameState!.players
                                      .firstWhere((p) => p.id == player2!.id);

                                  final temp = p1.hand[card1!];
                                  p1.hand[card1!] = p2.hand[card2!];
                                  p2.hand[card2!] = temp;

                                  // Réinitialiser la connaissance (on ne sait plus ce qu'on a)
                                  p1.knownCards[card1!] = false;
                                  p2.knownCards[card2!] = false;

                                  gp.gameState!.addToHistory(
                                      "🔄 Échange : $name1 carte #${card1! + 1} ↔ $name2 carte #${card2! + 1}.");

                                  gp.skipSpecialPower();
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                          ),
                          child: const Text("ÉCHANGER",
                              style: TextStyle(fontSize: 16)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
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
      builder: (ctx) => Dialog(
        backgroundColor: Colors.purple.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.swap_horiz, color: Colors.white, size: 50),
              const SizedBox(height: 12),
              const Text(
                "ÉCHANGE EFFECTUÉ",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                "$player1 carte #${card1 + 1} ↔ $player2 carte #${card2 + 1}",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.purple.shade900,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text("OK",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
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
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black87,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shuffle, color: Colors.red, size: 40),
              const SizedBox(height: 12),
              const Text(
                "🃏 JOKER : CHAOS",
                style: TextStyle(
                    color: Colors.red,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Choisissez un joueur pour mélanger sa main",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                children: allPlayers.map((player) {
                  return ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showShuffleNotification(context, player);
                      gameProvider.executeJokerEffect(player);
                    },
                    icon: Icon(player.isHuman ? Icons.person : Icons.smart_toy,
                        size: 20),
                    label: Text(player.name),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: player.isHuman
                          ? Colors.amber.shade700
                          : Colors.blue.shade800,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  gameProvider.skipSpecialPower();
                },
                child: const Text("ANNULER",
                    style: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _showShuffleNotification(BuildContext context, Player target) {
    final isMe = target.isHuman;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.red.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shuffle, color: Colors.white, size: 50),
              const SizedBox(height: 12),
              Text(
                isMe
                    ? "VOS CARTES ONT ÉTÉ MÉLANGÉES !"
                    : "CARTES DE ${target.name.toUpperCase()} MÉLANGÉES !",
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                isMe
                    ? "Vous ne savez plus où sont vos cartes !"
                    : "${target.name} ne sait plus où sont ses cartes !",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red.shade900,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text("OK",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void showBotSwapNotification(BuildContext context, Player bot,
      String targetName, int targetCardIndex) {

    String botDisplay = _getBotPositionDisplay(context, bot);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.purple.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.swap_horiz, color: Colors.white, size: 50),
              const SizedBox(height: 12),
              const Text(
                "🤵 VALET !",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                "$botDisplay a échangé une carte avec ${targetName == "Vous" ? "vous" : targetName} !",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              if (targetName == "Vous") ...[
                const SizedBox(height: 8),
                Text(
                  "Votre carte #${targetCardIndex + 1} a été échangée",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.purple.shade900,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text("OK",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
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
      builder: (ctx) => Dialog(
        backgroundColor: Colors.red.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shuffle, color: Colors.white, size: 50),
              const SizedBox(height: 12),
              Text(
                isMe
                    ? "VOS CARTES ONT ÉTÉ MÉLANGÉES !"
                    : "CARTES DE ${targetName.toUpperCase()} MÉLANGÉES !",
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                "$botDisplay a utilisé le Joker !",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                isMe
                    ? "Vous ne savez plus où sont vos cartes !"
                    : "$targetName ne sait plus où sont ses cartes !",
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red.shade900,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: const Text("OK",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
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