import 'package:flutter/material.dart';
import '../../services/ui/haptic_service.dart';

class PresenceCheckOverlay extends StatefulWidget {
  const PresenceCheckOverlay({
    super.key,
    required this.active,
    required this.deadlineMs,
    required this.onConfirm,
    this.onAbandon,
    this.reason,
  });

  final bool active;
  final int deadlineMs;
  final String? reason;
  final VoidCallback onConfirm;
  final VoidCallback? onAbandon;

  @override
  State<PresenceCheckOverlay> createState() => _PresenceCheckOverlayState();
}

class _PresenceCheckOverlayState extends State<PresenceCheckOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  int _lastHapticTick = 0;
  bool _wasActive = false;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: Duration(
          milliseconds: widget.deadlineMs > 0 ? widget.deadlineMs : 15000),
    )..addListener(() {
        if (mounted) setState(() {});
        _checkHaptic();
      });

    if (widget.active) {
      _wasActive = true;
      _startCountdown(widget.deadlineMs);
    }
  }

  @override
  void didUpdateWidget(PresenceCheckOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active) {
      if (!_wasActive || widget.deadlineMs != oldWidget.deadlineMs) {
        _startCountdown(widget.deadlineMs);
      }
      _wasActive = true;
    } else if (_wasActive) {
      _stopCountdown();
      _wasActive = false;
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  void _startCountdown(int ms) {
    if (ms <= 0) return;
    _progressController.duration = Duration(milliseconds: ms);
    _progressController.value = 1.0;
    _progressController.reverse();
  }

  void _stopCountdown() {
    _progressController.stop();
  }

  void _checkHaptic() {
    if (!widget.active) return;

    // 80 BPM = une vibration toutes les 750ms
    final elapsedTotal = widget.deadlineMs * (1.0 - _progressController.value);
    final tickIndex = (elapsedTotal / 100).round();

    // On vibre continuellement pendant tout le compte à rebours de présence
    if (tickIndex != _lastHapticTick && tickIndex % 7 == 0) {
      _lastHapticTick = tickIndex;
      HapticService.cardTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();

    final remainingMs = (widget.deadlineMs * _progressController.value).round();
    final seconds = (remainingMs / 1000).ceil().clamp(0, 60).toInt();
    final progress = _progressController.value;
    final reason = widget.reason ?? 'Confirme ta présence pour continuer.';

    // Couleur progressive de la barre
    final Color barColor;
    if (progress > 0.5) {
      final t = ((progress - 0.5) / 0.5).clamp(0.0, 1.0);
      barColor = Color.lerp(Colors.orange, const Color(0xFF4CAF50), t)!;
    } else {
      final t = (progress / 0.5).clamp(0.0, 1.0);
      barColor = Color.lerp(Colors.red, Colors.orange, t)!;
    }

    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        alignment: Alignment.center,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 340,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: barColor.withValues(alpha: 0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: barColor.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icône
                Icon(
                  Icons.access_time_rounded,
                  color: barColor,
                  size: 48,
                ),
                const SizedBox(height: 12),

                // Titre
                const Text(
                  'Toujours là ?',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),

                // Raison
                Text(
                  reason,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 20),

                // Barre de progression
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 12,
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(barColor),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Compteur
                Text(
                  'Éjection dans ${seconds}s',
                  style: TextStyle(
                    fontSize: 13,
                    color: barColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),

                // Boutons
                Row(
                  children: [
                    // Bouton Abandonner
                    if (widget.onAbandon != null)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: widget.onAbandon,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Abandonner',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    if (widget.onAbandon != null) const SizedBox(width: 12),

                    // Bouton Continuer
                    Expanded(
                      child: ElevatedButton(
                        onPressed: widget.onConfirm,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: const Color(0xFF4CAF50),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Continuer',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
