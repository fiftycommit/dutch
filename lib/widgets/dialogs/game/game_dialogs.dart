import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../models/game_state.dart';
import '../../../utils/ui_constants.dart';
import '../../game/card_widget.dart';
import '../responsive_dialog.dart';

/// Dialogs communs réutilisables pour les écrans de jeu (solo et multiplayer)
/// Pattern GRASP: Pure Fabrication - Regroupe les dialogs UI communs
class GameDialogs {
  /// Dialog de confirmation pour crier DUTCH
  static Future<bool?> confirmDutch(BuildContext context) {
    return showDialog<bool>(
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
                  style: TextStyle(color: Colors.white, fontSize: titleSize)),
              SizedBox(height: gap),
              Text('Êtes-vous sûr ?',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: bodySize)),
              SizedBox(height: gap),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('Non',
                          style: TextStyle(
                              color: AppColors.textDisabled, fontSize: buttonSize))),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style:
                          TextButton.styleFrom(foregroundColor: Colors.redAccent),
                      child:
                          Text('DUTCH !', style: TextStyle(fontSize: buttonSize)))
                ],
              )
            ],
          );
        },
      ),
    );
  }

  /// Dialog pour afficher la pile de défausse
  static void showDiscardPile(BuildContext context, GameState gs) {
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
                  style: TextStyle(color: Colors.white, fontSize: titleSize)),
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
      ),
    );
  }

  /// Dialog de confirmation pour quitter la partie
  static Future<bool?> confirmQuit(BuildContext context) {
    return showDialog<bool>(
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
                  style: TextStyle(color: Colors.white, fontSize: titleSize)),
              SizedBox(height: gap),
              Text(
                  "Quitter la partie ? Elle sera sauvegardée et comptée comme un abandon.",
                  style: TextStyle(color: AppColors.textSecondary, fontSize: bodySize),
                  textAlign: TextAlign.center),
              SizedBox(height: gap),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text("Non",
                          style: TextStyle(
                              color: Colors.white, fontSize: buttonSize))),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text("Oui",
                          style: TextStyle(
                              color: Colors.redAccent, fontSize: buttonSize))),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
