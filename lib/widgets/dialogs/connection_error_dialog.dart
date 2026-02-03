import 'package:flutter/material.dart';
import 'responsive_dialog.dart';
import '../../utils/ui_constants.dart';

/// A dialog shown when the player loses connection to the server.
/// Provides "Retry" and "Return to Menu" options.
/// Uses ResponsiveDialog for consistent UI across the app.
class ConnectionErrorDialog {
  /// Shows the connection error dialog.
  /// Returns true if user chose to retry, false if they chose to return to menu.
  static Future<bool?> show(
    BuildContext context, {
    required String message,
    required VoidCallback onRetry,
    required VoidCallback onReturnToMenu,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: const Color(0xFF1a472a),
        builder: (context, metrics) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.wifi_off,
                  color: Colors.redAccent,
                  size: metrics.size(32),
                ),
                SizedBox(width: metrics.space(12)),
                Text(
                  'Connexion perdue',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: metrics.font(22),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: metrics.space(20)),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: metrics.font(15),
              ),
            ),
            SizedBox(height: metrics.space(30)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop(false);
                    onReturnToMenu();
                  },
                  icon: Icon(
                    Icons.home,
                    color: AppColors.textSecondary,
                    size: metrics.size(20),
                  ),
                  label: Text(
                    'Menu',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: metrics.font(14),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop(true);
                    onRetry();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent.shade700,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      horizontal: metrics.space(20),
                      vertical: metrics.space(12),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(Icons.refresh, size: metrics.size(20)),
                  label: Text(
                    'Réessayer',
                    style: TextStyle(fontSize: metrics.font(14)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
