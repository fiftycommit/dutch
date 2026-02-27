import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/playing_card.dart';
import '../../../models/player.dart';
import '../../../models/game_state.dart';
import '../../../providers/game_provider.dart';
import '../../../providers/multiplayer_game_provider.dart';
import '../../../services/game/game_logic.dart';
import '../../../utils/ui_constants.dart';
import '../responsive_dialog.dart';
import 'power_dialog_widgets.dart';
import 'power_notification_dialogs.dart';
import 'power_selection_widgets.dart';

/// Configuration pour les dialogues de pouvoirs spéciaux
/// Pattern Strategy : encapsule les différences entre solo et multiplayer
class PowerDialogConfig {
  final GameState gameState;
  final Player localPlayer;
  final List<Player> allPlayers;
  final VoidCallback onSkipPower;
  final void Function(Player player, int cardIndex) onLookAtCard;
  final void Function(Player player) onShuffleHand;
  final void Function(Player p1, int c1, Player p2, int c2) onSwapCards;

  /// Pour identifier le joueur local (solo: isHuman, multi: id == playerId)
  final bool Function(Player p) isLocalPlayer;

  /// En mode multijoueur, les cartes sont cachées côté client
  /// Le serveur envoie la vraie carte via game:spied_card
  final bool isMultiplayer;

  /// Callback appelé quand un joueur est ciblé (pour illuminer sa main en temps réel)
  final void Function(Set<int> targetPlayerIndices)? onPlayerTargeted;

  const PowerDialogConfig({
    required this.gameState,
    required this.localPlayer,
    required this.allPlayers,
    required this.onSkipPower,
    required this.onLookAtCard,
    required this.onShuffleHand,
    required this.onSwapCards,
    required this.isLocalPlayer,
    this.isMultiplayer = false,
    this.onPlayerTargeted,
  });

  List<Player> get opponents =>
      allPlayers.where((p) => !isLocalPlayer(p) && p.hand.isNotEmpty).toList();

  /// Factory pour le mode SOLO
  static PowerDialogConfig solo(BuildContext context) {
    final gp = Provider.of<GameProvider>(context, listen: false);
    final gs = gp.gameState!;
    final human = gs.players.firstWhere((p) => p.isHuman);

    return PowerDialogConfig(
      gameState: gs,
      localPlayer: human,
      allPlayers: gs.players,
      isLocalPlayer: (p) => p.isHuman,
      isMultiplayer: false,
      onSkipPower: gp.skipSpecialPower,
      onLookAtCard: gp.executeLookAtCard,
      onShuffleHand: gp.executeJokerEffect,
      onSwapCards: (p1, c1, p2, c2) {
        final player1 = gs.players.firstWhere((p) => p.id == p1.id);
        final player2 = gs.players.firstWhere((p) => p.id == p2.id);
        GameLogic.swapCards(gs, player1, c1, player2, c2);
        gp.skipSpecialPower();
      },
    );
  }

  /// Factory pour le mode MULTIPLAYER
  static PowerDialogConfig multiplayer(BuildContext context) {
    final gp = Provider.of<MultiplayerGameProvider>(context, listen: false);
    final gs = gp.gameState!;
    final me = gs.players.firstWhere((p) => p.id == gp.playerId);

    return PowerDialogConfig(
      gameState: gs,
      localPlayer: me,
      allPlayers: gs.players.where((p) => !p.isSpectator).toList(),
      isLocalPlayer: (p) => p.id == gp.playerId,
      isMultiplayer: true,
      onSkipPower: gp.skipSpecialPower,
      onLookAtCard: (player, index) {
        // En multi, on envoie au serveur via les méthodes spécifiques
        if (player.id == gp.playerId) {
          gp.usePower7LookOwnCard(index);
        } else {
          final targetIndex = gs.players.indexOf(player);
          gp.usePower10SpyOpponent(targetIndex, index);
        }
      },
      onShuffleHand: (player) {
        gp.usePowerJokerShuffle(gs.players.indexOf(player));
      },
      onSwapCards: (p1, c1, p2, c2) {
        final p1Index = gs.players.indexOf(p1);
        final p2Index = gs.players.indexOf(p2);
        gp.usePowerValetSwap(p1Index, c1, p2Index, c2);
      },
      onPlayerTargeted: (targetIndices) {
        // Émet les indices des joueurs ciblés pour illuminer leur main
        // chez les autres joueurs en temps réel
        final p1 = targetIndices.isNotEmpty ? targetIndices.first : null;
        final p2 = targetIndices.length > 1 ? targetIndices.last : null;
        gp.sendSpecialPowerTargetSelection(p1, null, p2, null);
      },
    );
  }
}

/// Dialogues unifiés pour les pouvoirs spéciaux (solo + multiplayer)
class UnifiedPowerDialogs {
  static double _cardWidthForGrid(DialogMetrics metrics,
          {required int columns, double maxHeightFraction = 0.35}) =>
      PowerDialogWidgets.cardWidthForGrid(metrics,
          columns: columns, maxHeightFraction: maxHeightFraction);

  static Widget _scaledCard(
          {required double width,
          required bool isRevealed,
          PlayingCard? card}) =>
      PowerDialogWidgets.scaledCard(
          width: width, isRevealed: isRevealed, card: card);

  // ============================================================
  // CARTE 7 : Regarder UNE de ses propres cartes
  // ============================================================
  static void showPower7Dialog(
      BuildContext context, PlayingCard trigger, PowerDialogConfig config) {
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
          final columns = math.min(config.localPlayer.hand.length, 4);
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
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: bodySize),
                  ),
                  SizedBox(height: spacing),
                  Wrap(
                    spacing: smallSpacing,
                    runSpacing: smallSpacing,
                    alignment: WrapAlignment.center,
                    children:
                        List.generate(config.localPlayer.hand.length, (index) {
                      return GestureDetector(
                        onTap: () async {
                          Navigator.pop(ctx);
                          if (!config.isMultiplayer) {
                            await _showCardRevealed(context, config.localPlayer,
                                index, config.localPlayer.hand[index]);
                          }
                          config.onLookAtCard(config.localPlayer, index);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: Colors.amber, width: borderWidth),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child:
                              _scaledCard(width: cardWidth, isRevealed: false),
                        ),
                      );
                    }),
                  ),
                  SizedBox(height: spacing),
                  PowerDialogWidgets.tickingSkipButton(
                    labelPrefix: "PASSER",
                    onPressed: () {
                      Navigator.pop(ctx);
                      config.onSkipPower();
                    },
                    metrics: metrics,
                    autoCloseSeconds: config.isMultiplayer ? 15 : 0,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // CARTE 10 : Espionner une carte adversaire
  // ============================================================
  static void showPower10Dialog(
      BuildContext context, PlayingCard trigger, PowerDialogConfig config) {
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

          return SingleChildScrollView(
            child: SizedBox(
              width: metrics.contentWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.visibility, color: Colors.blue, size: iconSize),
                  SizedBox(height: smallSpacing),
                  Text(
                    "👁 ESPIONNER",
                    style: TextStyle(
                        color: Colors.blue,
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: smallSpacing),
                  Text(
                    "Choisissez un adversaire puis une de ses cartes",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: bodySize),
                  ),
                  SizedBox(height: spacing),
                  _buildOpponentSelection(context, config, metrics),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static Widget _buildOpponentSelection(
      BuildContext context, PowerDialogConfig config, DialogMetrics metrics) {
    final opponents = config.opponents;

    if (opponents.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Aucun adversaire n'a de cartes !",
              style: TextStyle(
                  color: Colors.redAccent, fontSize: metrics.font(14))),
          SizedBox(height: metrics.space(16)),
          PowerDialogWidgets.tickingSkipButton(
            labelPrefix: "OK",
            onPressed: () {
              Navigator.pop(context);
              config.onSkipPower();
            },
            metrics: metrics,
            autoCloseSeconds: config.isMultiplayer ? 15 : 0,
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
            final count = opponent.hand.length;
            return ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _showOpponentCardSelection(context, config, opponent);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                padding: EdgeInsets.symmetric(
                    horizontal: metrics.space(14), vertical: metrics.space(10)),
              ),
              child: Text(
                "${opponent.displayAvatar} ${opponent.name} ($count carte${count > 1 ? 's' : ''})",
                style: TextStyle(fontSize: metrics.font(14)),
              ),
            );
          }).toList(),
        ),
        SizedBox(height: metrics.space(16)),
        PowerDialogWidgets.tickingSkipButton(
          labelPrefix: "PASSER",
          onPressed: () {
            Navigator.pop(context);
            config.onSkipPower();
          },
          metrics: metrics,
          autoCloseSeconds: config.isMultiplayer ? 15 : 0,
        ),
      ],
    );
  }

  static void _showOpponentCardSelection(
      BuildContext context, PowerDialogConfig config, Player opponent) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: Colors.black87,
        builder: (context, metrics) {
          final spacing = metrics.space(12);
          final titleSize = metrics.font(18);
          final columns = math.min(opponent.hand.length, 4);
          final cardWidth = _cardWidthForGrid(metrics,
              columns: columns, maxHeightFraction: 0.35);
          final borderWidth = math.max(1.0, metrics.scale * 2);

          return SingleChildScrollView(
            child: SizedBox(
              width: metrics.contentWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Cartes de ${opponent.name} (${opponent.hand.length} carte${opponent.hand.length > 1 ? 's' : ''})",
                    style: TextStyle(
                        color: Colors.amber,
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: spacing),
                  Wrap(
                    spacing: metrics.space(8),
                    runSpacing: metrics.space(8),
                    alignment: WrapAlignment.center,
                    children: List.generate(opponent.hand.length, (index) {
                      return GestureDetector(
                        onTap: () async {
                          Navigator.pop(ctx);
                          if (!config.isMultiplayer) {
                            await _showCardRevealed(
                                context, opponent, index, opponent.hand[index]);
                          }
                          config.onLookAtCard(opponent, index);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: Colors.blue, width: borderWidth),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child:
                              _scaledCard(width: cardWidth, isRevealed: false),
                        ),
                      );
                    }),
                  ),
                  SizedBox(height: spacing),
                  PowerDialogWidgets.tickingSkipButton(
                    labelPrefix: "PASSER",
                    onPressed: () {
                      Navigator.pop(ctx);
                      config.onSkipPower();
                    },
                    metrics: metrics,
                    autoCloseSeconds: config.isMultiplayer ? 15 : 0,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static Future<void> _showCardRevealed(
      BuildContext context, Player player, int index, PlayingCard card) {
    player.knownCards[index] = true;
    return PowerNotificationDialogs.showCardRevealed(context, card);
  }

  // ============================================================
  // VALET : Échange universel
  // ============================================================
  static void showValetSwapDialog(
      BuildContext context, PlayingCard trigger, PowerDialogConfig config) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: Colors.black87,
        builder: (context, metrics) =>
            PowerSelectionWidgets.buildPowerIntroDialog(
          icon: Icons.swap_horiz,
          color: Colors.purple,
          title: "🤵 VALET : ÉCHANGE",
          subtitle: "Échangez 2 cartes à l'aveugle",
          buttonText: "CHOISIR\n2 CARTES",
          fullWidthButton: true,
          onConfirm: () {
            Navigator.pop(ctx);
            _showUniversalSwap(context, config);
          },
          onCancel: () {
            Navigator.pop(ctx);
            config.onSkipPower();
          },
          metrics: metrics,
          autoCloseSeconds: config.isMultiplayer ? 15 : 0,
          onTimeout: () {
            Navigator.pop(ctx);
            config.onSkipPower();
          },
        ),
      ),
    );
  }

  static void _showUniversalSwap(
      BuildContext context, PowerDialogConfig config) {
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
              return PowerSelectionWidgets.buildSwapDialogContent(
                allPlayers: config.allPlayers,
                player1: player1,
                card1: card1,
                player2: player2,
                card2: card2,
                onSelectPlayer1: (p) => setState(() {
                  player1 = p;
                  card1 = null;
                  final gs = config.gameState;
                  final indices = <int>{
                    gs.players.indexOf(p),
                    if (player2 != null) gs.players.indexOf(player2!),
                  };
                  config.onPlayerTargeted?.call(indices);
                }),
                onSelectCard1: (i) => setState(() => card1 = i),
                onSelectPlayer2: (p) => setState(() {
                  player2 = p;
                  card2 = null;
                  final gs = config.gameState;
                  final indices = <int>{
                    if (player1 != null) gs.players.indexOf(player1!),
                    gs.players.indexOf(p),
                  };
                  config.onPlayerTargeted?.call(indices);
                }),
                onSelectCard2: (i) => setState(() => card2 = i),
                onCancel: () {
                  Navigator.pop(ctx);
                  config.onSkipPower();
                },
                onConfirm: (player1 != null &&
                        card1 != null &&
                        player2 != null &&
                        card2 != null)
                    ? () {
                        Navigator.pop(ctx);
                        // Ne pas afficher showSwapNotification ici pour le joueur actif
                        // cela l'empêcherait de jouer pendant la phase de match (reaction timer)
                        config.onSwapCards(player1!, card1!, player2!, card2!);
                      }
                    : null,
                getPlayerLabel: (p) =>
                    config.isLocalPlayer(p) ? "Vous" : p.name,
                getCardLabel: (p) =>
                    config.isLocalPlayer(p) ? "votre main" : p.name,
                metrics: metrics,
              );
            },
          );
        },
      ),
    );
  }

  // ============================================================
  // JOKER : Mélanger la main d'un joueur
  // ============================================================
  static void showJokerDialog(
      BuildContext context, PlayingCard trigger, PowerDialogConfig config) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: Colors.black87,
        builder: (context, metrics) =>
            PowerSelectionWidgets.buildPlayerSelectionDialog(
          icon: Icons.shuffle,
          color: Colors.red,
          title: "🃏 JOKER : CHAOS",
          subtitle: "Choisissez un joueur pour mélanger sa main",
          players: config.allPlayers,
          onSelectPlayer: (player, index) {
            config.onPlayerTargeted
                ?.call({config.gameState.players.indexOf(player)});
            Navigator.pop(ctx);
            // On lance directement l'effet du joker, sans boite de dialogue supplémentaire
            // pour le joueur actif, ce qui préserve son temps de réaction
            config.onShuffleHand(player);
          },
          onCancel: () {
            Navigator.pop(ctx);
            config.onSkipPower();
          },
          getLabel: (p) => config.isLocalPlayer(p) ? "Vous" : p.name,
          isMe: config.isLocalPlayer,
          metrics: metrics,
          autoCloseSeconds: config.isMultiplayer ? 15 : 0,
          onTimeout: () {
            Navigator.pop(ctx);
            config.onSkipPower();
          },
        ),
      ),
    );
  }

  // ============================================================
  // NOTIFICATIONS (utilisées par multiplayer pour les événements serveur)
  // ============================================================

  /// Notification quand une carte est révélée (pouvoir 7/10)
  static Future<void> showCardRevealDialog(
      BuildContext context, PlayingCard card,
      {String title = "CARTE RÉVÉLÉE",
      int autoCloseSeconds = 0,
      VoidCallback? onTimeout}) {
    return PowerNotificationDialogs.showCardRevealed(context, card,
        title: title, autoCloseSeconds: autoCloseSeconds, onTimeout: onTimeout);
  }

  /// Notification quand un autre joueur utilise le Valet sur nous
  static Future<void> showSwapNotificationDialog(
    BuildContext context,
    String byPlayerName,
    int cardIndex, {
    String? swapPartnerName,
    int? receivedCardPosition,
    int autoCloseSeconds = 0,
    VoidCallback? onTimeout,
  }) {
    return PowerNotificationDialogs.showSwapByOtherNotification(
      context,
      byPlayerName: byPlayerName,
      targetName: "Vous",
      targetCardIndex: cardIndex,
      swapPartnerName: swapPartnerName,
      receivedCardPosition: receivedCardPosition,
      autoCloseSeconds: autoCloseSeconds,
      onTimeout: onTimeout,
    );
  }

  /// Notification quand un autre joueur nous espionne (pouvoir 10)
  static Future<void> showSpyNotificationDialog(
    BuildContext context,
    String byPlayerName,
    int cardIndex, {
    int autoCloseSeconds = 0,
    VoidCallback? onTimeout,
  }) {
    return PowerNotificationDialogs.showSpyByOtherNotification(
      context,
      byPlayerName: byPlayerName,
      cardIndex: cardIndex,
      isMe: true,
      autoCloseSeconds: autoCloseSeconds,
      onTimeout: onTimeout,
    );
  }

  /// Notification quand un autre joueur utilise le Joker sur nous
  static Future<void> showJokerNotificationDialog(
    BuildContext context,
    String byPlayerName, {
    int autoCloseSeconds = 0,
    VoidCallback? onTimeout,
  }) {
    return PowerNotificationDialogs.showShuffleNotification(
      context,
      targetName: "Vous",
      isMe: true,
      byPlayerName: byPlayerName,
      autoCloseSeconds: autoCloseSeconds,
      onTimeout: onTimeout,
    );
  }

  /// Notification bot swap (solo) - attend que le joueur clique OK
  static Future<void> showBotSwapNotification(
    BuildContext context,
    Player bot,
    String targetName,
    int targetCardIndex, {
    String? swapPartnerName,
    int? receivedCardPosition,
  }) {
    final gp = Provider.of<GameProvider>(context, listen: false);
    final index = gp.gameState?.players.indexWhere((p) => p.id == bot.id) ?? -1;
    return PowerNotificationDialogs.showSwapByOtherNotification(
      context,
      byPlayerName: bot.getPositionDisplay(index),
      targetName: targetName,
      targetCardIndex: targetCardIndex,
      swapPartnerName: swapPartnerName,
      receivedCardPosition: receivedCardPosition,
    );
  }

  /// Notification bot joker (solo) - attend que le joueur clique OK
  static Future<void> showBotJokerNotification(
      BuildContext context, Player bot, String targetName) {
    final gp = Provider.of<GameProvider>(context, listen: false);
    final index = gp.gameState?.players.indexWhere((p) => p.id == bot.id) ?? -1;
    return PowerNotificationDialogs.showShuffleNotification(context,
        targetName: targetName,
        isMe: targetName == "Vous",
        byPlayerName: bot.getPositionDisplay(index));
  }

  /// Notification bot spy (solo) - attend que le joueur clique OK
  static Future<void> showBotSpyNotification(
      BuildContext context, Player bot, String targetName, int cardIndex) {
    final gp = Provider.of<GameProvider>(context, listen: false);
    final index = gp.gameState?.players.indexWhere((p) => p.id == bot.id) ?? -1;
    return PowerNotificationDialogs.showSpyByOtherNotification(context,
        byPlayerName: bot.getPositionDisplay(index),
        cardIndex: cardIndex,
        isMe: targetName == "Vous");
  }
}
