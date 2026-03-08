import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../utils/ui_constants.dart';

/// InheritedWidget qui propage l'état de pause dans l'arbre widget.
/// Utilisé pour que les Ticker des dialogs de pouvoir se gèlent
/// automatiquement pendant la pause, même à travers des showDialog.
class GamePauseScope extends InheritedWidget {
  final bool isPaused;

  const GamePauseScope({
    super.key,
    required this.isPaused,
    required super.child,
  });

  /// Retourne true si le jeu est en pause. Retourne false si pas
  /// de GamePauseScope dans l'arbre (solo, tests, etc.)
  static bool of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<GamePauseScope>()
            ?.isPaused ??
        false;
  }

  @override
  bool updateShouldNotify(GamePauseScope oldWidget) =>
      isPaused != oldWidget.isPaused;
}

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

  /// Overlay de pause (avec countdown + barre de progression)
  static Widget pauseOverlay({
    String? pausedByName,
    required VoidCallback onResume,
    required bool isLocalPauser,
    int pauseDeadlineMs = 0,
  }) {
    return _PauseOverlay(
      pausedByName: pausedByName,
      onResume: onResume,
      isLocalPauser: isLocalPauser,
      pauseDeadlineMs: pauseDeadlineMs,
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
              AutoSizeText(
                "${byPlayerName ?? 'Un joueur'} utilise un pouvoir sur vous !",
                maxLines: 1,
                minFontSize: 5,
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

// ─────────────────────────────────────────────────────────────────────────────
// Widget interne : overlay de pause avec countdown animé
// ─────────────────────────────────────────────────────────────────────────────
class _PauseOverlay extends StatefulWidget {
  final String? pausedByName;
  final VoidCallback onResume;
  final bool isLocalPauser;
  final int pauseDeadlineMs;

  const _PauseOverlay({
    required this.pausedByName,
    required this.onResume,
    required this.isLocalPauser,
    required this.pauseDeadlineMs,
  });

  @override
  State<_PauseOverlay> createState() => _PauseOverlayState();
}

class _PauseOverlayState extends State<_PauseOverlay>
    with SingleTickerProviderStateMixin {
  static const int _totalSeconds = 90;
  Ticker? _ticker;
  int _secondsRemaining = _totalSeconds;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void didUpdateWidget(covariant _PauseOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pauseDeadlineMs != widget.pauseDeadlineMs) {
      _startCountdown();
    }
  }

  void _startCountdown() {
    _ticker?.dispose();
    _ticker = null;
    if (widget.pauseDeadlineMs <= 0) {
      setState(() => _secondsRemaining = _totalSeconds);
      return;
    }
    _tick();
    _ticker = createTicker((_) => _tick());
    _ticker!.start();
  }

  void _tick() {
    if (!mounted) return;
    final remaining =
        ((widget.pauseDeadlineMs - DateTime.now().millisecondsSinceEpoch) /
                1000)
            .ceil()
            .clamp(0, _totalSeconds);
    if (remaining != _secondsRemaining) {
      setState(() => _secondsRemaining = remaining);
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  Color get _progressColor {
    final ratio = _secondsRemaining / _totalSeconds;
    if (ratio > 0.5) return Colors.green;
    if (ratio > 0.25) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        widget.pauseDeadlineMs > 0 ? _secondsRemaining / _totalSeconds : 1.0;
    final showCountdown = widget.pauseDeadlineMs > 0;

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pause_circle_outline,
                    color: Colors.amber, size: 72),
                const SizedBox(height: 16),
                const Text(
                  "PAUSE",
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.pausedByName != null)
                  Text(
                    "Mis en pause par ${widget.pausedByName}",
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 15),
                    textAlign: TextAlign.center,
                  ),

                // ── Countdown + barre de progression ──
                if (showCountdown) ...[
                  const SizedBox(height: 20),
                  Text(
                    "Temps restant à ${widget.pausedByName ?? '?'} pour lever la pause",
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(_progressColor),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "$_secondsRemaining s",
                    style: TextStyle(
                        color: _progressColor,
                        fontSize: 14,
                        fontWeight: FontWeight.bold),
                  ),
                ],

                const SizedBox(height: 24),

                // Bouton REPRENDRE — visible seulement pour le pauseur
                if (widget.isLocalPauser)
                  ElevatedButton(
                    onPressed: widget.onResume,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 40, vertical: 14),
                    ),
                    child: const Text("REPRENDRE",
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                  )
                else
                  const Text(
                    "En attente que le joueur lève la pause…",
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                        fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
