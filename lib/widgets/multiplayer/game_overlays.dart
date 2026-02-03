import 'package:flutter/material.dart';
import '../../utils/ui_constants.dart';

/// Overlays réutilisables pour les écrans de jeu multiplayer
class GameOverlays {
  /// Overlay "Veuillez tourner votre appareil"
  static Widget rotateScreen() {
    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.screen_rotation, color: Colors.white, size: 50),
            SizedBox(height: 20),
            Text(
              "Veuillez tourner votre appareil\nen mode paysage",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }

  /// Notification "DUTCH !"
  static Widget dutchNotification() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(15),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("DUTCH !",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Text("Dernier tour pour tout le monde !",
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  /// Overlay de pause
  static Widget pauseOverlay({
    String? pausedByName,
    required VoidCallback onResume,
  }) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pause_circle_outline,
                color: Colors.amber, size: 80),
            const SizedBox(height: 20),
            const Text(
              "PAUSE",
              style: TextStyle(
                color: Colors.amber,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                fontFamily: 'Rye',
              ),
            ),
            const SizedBox(height: 10),
            if (pausedByName != null)
              Text("Mis en pause par $pausedByName",
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 16)),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: onResume,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              ),
              child: const Text("REPRENDRE",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  /// Notification d'un joueur qui a quitté
  static Widget playerLeftBanner(String? playerName) {
    return Positioned(
      top: 60,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.orange.shade800.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(25),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.exit_to_app, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                "${playerName ?? 'Un joueur'} a quitté",
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Notification de pouvoir spécial utilisé sur nous
  static Widget specialPowerBanner(String? byPlayerName) {
    return Positioned(
      top: 60,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.purple.shade700.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(25),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Text(
                "${byPlayerName ?? 'Un joueur'} utilise un pouvoir sur vous !",
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Indicateur de reconnexion silencieuse
  static Widget reconnectingBanner() {
    return Positioned(
      top: 60,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.blue.shade800.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(25),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text(
                'Reconnexion en cours...',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Badge compteur de cartes pour les adversaires
  static Widget cardCountBadge(int count, {bool isCompact = false}) {
    return Container(
      padding: EdgeInsets.all(isCompact ? 4 : 6),
      decoration: BoxDecoration(
        color: Colors.amber,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Text(
        "$count",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: isCompact ? 10 : 14,
          color: Colors.black,
        ),
      ),
    );
  }
}
