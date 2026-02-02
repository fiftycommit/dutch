import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../responsive_dialog.dart';

/// Dialogs spécifiques au mode multiplayer
/// Pattern GRASP: Pure Fabrication - Regroupe les dialogs UI multiplayer
class MultiplayerDialogs {
  /// Dialog pour partie terminée par l'hôte
  static void showHostClosedDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: const Color(0xFF1a472a),
        builder: (ctx, metrics) => Column(
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
              onPressed: () {
                Navigator.of(ctx).pop(); // Fermer le dialog
                context.go('/multiplayer'); // Retour à l'accueil multiplayer
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              child: const Text("MENU PRINCIPAL"),
            ),
          ],
        ),
      ),
    );
  }

  /// Dialog pour joueur exclu (peut revenir)
  static void showKickedDialog(BuildContext context, String? message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: const Color(0xFF1a472a),
        builder: (ctx, metrics) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Exclu de la room",
              style: TextStyle(
                color: Colors.white,
                fontSize: metrics.font(24),
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: metrics.space(20)),
            Text(
              message ?? "Vous avez été exclu de la room.",
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white70, fontSize: metrics.font(16)),
            ),
            SizedBox(height: metrics.space(30)),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop(); // Fermer le dialog
                context.go('/multiplayer'); // Retour à l'accueil multiplayer
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text("OK"),
            ),
          ],
        ),
      ),
    );
  }

  /// Dialog pour joueur banni (définitif)
  static void showBannedDialog(BuildContext context, String? message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: const Color(0xFF1a472a),
        builder: (ctx, metrics) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Banni de la room",
              style: TextStyle(
                color: Colors.white,
                fontSize: metrics.font(24),
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: metrics.space(20)),
            Text(
              message ?? "Vous avez été banni de cette room.",
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white70, fontSize: metrics.font(16)),
            ),
            SizedBox(height: metrics.space(10)),
            Text(
              "Vous ne pouvez plus rejoindre cette room.",
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.redAccent, fontSize: metrics.font(14)),
            ),
            SizedBox(height: metrics.space(30)),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop(); // Fermer le dialog
                context.go('/multiplayer'); // Retour à l'accueil multiplayer
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text("OK"),
            ),
          ],
        ),
      ),
    );
  }
}
