import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../models/playing_card.dart';
import '../../../utils/ui_constants.dart';
import '../../game/card_widget.dart';
import '../responsive_dialog.dart';
import 'power_dialog_widgets.dart';

/// Dialogs de notification partagés entre solo et multiplayer
/// Principe GRASP: Pure Fabrication - Regroupe les notifications UI communes
class PowerNotificationDialogs {
  /// Affiche la révélation d'une carte
  /// Retourne un Future qui se complète quand l'utilisateur ferme le dialog
  static Future<void> showCardRevealed(
    BuildContext context,
    PlayingCard card, {
    String title = "CARTE RÉVÉLÉE",
    String? valueOverride,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: Colors.black87,
        builder: (context, metrics) {
          const aspect = PowerDialogWidgets.cardAspectRatio;

          return SizedBox(
            width: metrics.contentWidth,
            height: metrics.contentHeight,
            child: Column(
              children: [
                // Header
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
                                title,
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
                // Card
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
                // Footer with value and OK button
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
                              valueOverride ?? "${card.value} (${card.points} pts)",
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

  /// Notification d'échange (Valet)
  static void showSwapNotification(
    BuildContext context,
    String player1,
    int card1,
    String player2,
    int card2,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: Colors.purple.shade900,
        builder: (context, metrics) {
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_horiz, color: Colors.white, size: metrics.size(50)),
                SizedBox(height: metrics.space(12)),
                Text(
                  "ÉCHANGE EFFECTUÉ",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: metrics.font(20),
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: metrics.space(12)),
                Text(
                  "$player1 carte #${card1 + 1} ↔ $player2 carte #${card2 + 1}",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: metrics.font(14)),
                ),
                SizedBox(height: metrics.space(20)),
                PowerDialogWidgets.confirmButton(
                  label: "OK",
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.purple.shade900,
                  onPressed: () => Navigator.pop(ctx),
                  metrics: metrics,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Notification de mélange (Joker)
  /// [autoCloseSeconds] : si > 0, ferme automatiquement après ce délai
  static Future<void> showShuffleNotification(
    BuildContext context, {
    required String targetName,
    required bool isMe,
    String? byPlayerName,
    int autoCloseSeconds = 0,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        if (autoCloseSeconds > 0) {
          Future.delayed(Duration(seconds: autoCloseSeconds), () {
            if (ctx.mounted) Navigator.of(ctx).pop();
          });
        }
        return ResponsiveDialog(
          backgroundColor: Colors.red.shade900,
          builder: (context, metrics) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shuffle, color: Colors.white, size: metrics.size(50)),
                  SizedBox(height: metrics.space(12)),
                  Text(
                    isMe
                        ? "VOS CARTES ONT ÉTÉ MÉLANGÉES !"
                        : "CARTES DE ${targetName.toUpperCase()} MÉLANGÉES !",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: metrics.font(20),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: metrics.space(12)),
                  Text(
                    byPlayerName != null
                        ? "$byPlayerName a utilisé le Joker !"
                        : (isMe
                            ? "Vous ne savez plus où sont vos cartes !"
                            : "$targetName ne sait plus où sont ses cartes !"),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: metrics.font(14)),
                  ),
                  if (byPlayerName != null) ...[
                    SizedBox(height: metrics.space(8)),
                    Text(
                      isMe
                          ? "Vous ne savez plus où sont vos cartes !"
                          : "$targetName ne sait plus où sont ses cartes !",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: metrics.font(12),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  SizedBox(height: metrics.space(16)),
                  PowerDialogWidgets.confirmButton(
                    label: autoCloseSeconds > 0 ? "OK ($autoCloseSeconds s)" : "OK",
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red.shade900,
                    onPressed: () => Navigator.pop(ctx),
                    metrics: metrics,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Notification d'échange par un bot/autre joueur
  /// [swapPartnerName] : nom du joueur avec qui la carte a été échangée
  /// [receivedCardPosition] : numéro (1-based) de la carte reçue chez le partenaire
  /// [autoCloseSeconds] : si > 0, ferme automatiquement après ce délai
  static Future<void> showSwapByOtherNotification(
    BuildContext context, {
    required String byPlayerName,
    required String targetName,
    required int targetCardIndex,
    String? swapPartnerName,
    int? receivedCardPosition,
    int autoCloseSeconds = 0,
  }) {
    final isMe = targetName == "Vous" || targetName == "vous";
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        // Auto-close timer
        if (autoCloseSeconds > 0) {
          Future.delayed(Duration(seconds: autoCloseSeconds), () {
            if (ctx.mounted) Navigator.of(ctx).pop();
          });
        }
        return ResponsiveDialog(
          backgroundColor: Colors.purple.shade900,
          builder: (context, metrics) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_horiz, color: Colors.white, size: metrics.size(50)),
                  SizedBox(height: metrics.space(12)),
                  Text(
                    "🤵 VALET !",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: metrics.font(20),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: metrics.space(8)),
                  Text(
                    "$byPlayerName a utilisé le Valet",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: metrics.font(14)),
                  ),
                  if (isMe) ...[
                    SizedBox(height: metrics.space(10)),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: metrics.space(12),
                        vertical: metrics.space(8),
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Text(
                            "Votre carte #${targetCardIndex + 1} a été échangée",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: metrics.font(13),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (swapPartnerName != null) ...[
                            SizedBox(height: metrics.space(4)),
                            Text(
                              "↔ avec $swapPartnerName",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: metrics.font(12),
                              ),
                            ),
                          ],
                          if (receivedCardPosition != null) ...[
                            SizedBox(height: metrics.space(4)),
                            Text(
                              "Vous avez reçu sa $receivedCardPosition${receivedCardPosition == 1 ? 'ère' : 'ème'} carte",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.greenAccent,
                                fontSize: metrics.font(12),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  SizedBox(height: metrics.space(16)),
                  PowerDialogWidgets.confirmButton(
                    label: autoCloseSeconds > 0 ? "OK ($autoCloseSeconds s)" : "OK",
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.purple.shade900,
                    onPressed: () => Navigator.pop(ctx),
                    metrics: metrics,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Notification d'espionnage par un bot/autre joueur
  /// [autoCloseSeconds] : si > 0, ferme automatiquement après ce délai
  static Future<void> showSpyByOtherNotification(
    BuildContext context, {
    required String byPlayerName,
    required int cardIndex,
    required bool isMe,
    int autoCloseSeconds = 0,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        if (autoCloseSeconds > 0) {
          Future.delayed(Duration(seconds: autoCloseSeconds), () {
            if (ctx.mounted) Navigator.of(ctx).pop();
          });
        }
        return ResponsiveDialog(
          backgroundColor: Colors.blue.shade900,
          builder: (context, metrics) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.remove_red_eye, color: Colors.white, size: metrics.size(50)),
                  SizedBox(height: metrics.space(12)),
                  Text(
                    "👁️ ESPIONNAGE !",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: metrics.font(20),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: metrics.space(12)),
                  Text(
                    "$byPlayerName espionne ${isMe ? "votre" : "la"} carte #${cardIndex + 1} !",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: metrics.font(14)),
                  ),
                  if (isMe) ...[
                    SizedBox(height: metrics.space(8)),
                    Text(
                      "Un joueur connaît maintenant votre carte",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: metrics.font(12),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  SizedBox(height: metrics.space(16)),
                  PowerDialogWidgets.confirmButton(
                    label: autoCloseSeconds > 0 ? "OK ($autoCloseSeconds s)" : "OK",
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blue.shade900,
                    onPressed: () => Navigator.pop(ctx),
                    metrics: metrics,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
