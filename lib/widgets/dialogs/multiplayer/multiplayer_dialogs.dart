import 'package:flutter/material.dart';
import '../responsive_dialog.dart';

/// Dialogs spécifiques au mode multiplayer
/// Pattern GRASP: Pure Fabrication - Regroupe les dialogs UI multiplayer
class MultiplayerDialogs {
  /// Dialog pour partie terminée par l'hôte
  static void showHostClosedDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ResponsiveDialog(
        backgroundColor: const Color(0xFF1a472a),
        builder: (context, metrics) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Partie terminée",
              style: TextStyle(
                color: Colors.white,
                fontSize: metrics.font(24),
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: metrics.space(20)),
            Text(
              "L'hôte a fermé la partie.",
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white70, fontSize: metrics.font(16)),
            ),
            SizedBox(height: metrics.space(30)),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              child: const Text("MENU PRINCIPAL"),
            ),
          ],
        ),
      ),
    );
  }

  /// Dialog pour joueur exclu
  static void showKickedDialog(BuildContext context, String? message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ResponsiveDialog(
        backgroundColor: const Color(0xFF1a472a),
        builder: (context, metrics) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Exclu du jeu",
              style: TextStyle(
                color: Colors.white,
                fontSize: metrics.font(24),
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: metrics.space(20)),
            Text(
              message ?? "Vous avez été exclu de la partie.",
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white70, fontSize: metrics.font(16)),
            ),
            SizedBox(height: metrics.space(30)),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text("OK"),
            ),
          ],
        ),
      ),
    );
  }
}
