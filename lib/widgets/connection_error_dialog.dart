import 'package:flutter/material.dart';

/// A dialog shown when the player loses connection to the server.
/// Provides "Retry" and "Return to Menu" options.
class ConnectionErrorDialog extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onReturnToMenu;

  const ConnectionErrorDialog({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onReturnToMenu,
  });

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
      builder: (ctx) => ConnectionErrorDialog(
        message: message,
        onRetry: () {
          Navigator.of(ctx).pop(true);
          onRetry();
        },
        onReturnToMenu: () {
          Navigator.of(ctx).pop(false);
          onReturnToMenu();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2D2D44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.wifi_off, color: Colors.redAccent, size: 28),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Connexion perdue',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: const TextStyle(color: Colors.white70, fontSize: 15),
      ),
      actionsAlignment: MainAxisAlignment.spaceEvenly,
      actions: [
        TextButton.icon(
          onPressed: onReturnToMenu,
          icon: const Icon(Icons.home, color: Colors.white70),
          label: const Text(
            'Menu',
            style: TextStyle(color: Colors.white70),
          ),
        ),
        ElevatedButton.icon(
          onPressed: onRetry,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.greenAccent.shade700,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.refresh),
          label: const Text('Réessayer'),
        ),
      ],
    );
  }
}
