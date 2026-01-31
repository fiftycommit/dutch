import 'dart:async';
import 'package:flutter/material.dart';

class PresenceCheckOverlay extends StatefulWidget {
  const PresenceCheckOverlay({
    super.key,
    required this.active,
    required this.deadlineMs,
    required this.onConfirm,
    this.reason,
  });

  final bool active;
  final int deadlineMs;
  final String? reason;
  final VoidCallback onConfirm;

  @override
  State<PresenceCheckOverlay> createState() => _PresenceCheckOverlayState();
}

class _PresenceCheckOverlayState extends State<PresenceCheckOverlay> {
  Timer? _timer;
  int _remainingMs = 0;
  bool _wasActive = false;

  @override
  void initState() {
    super.initState();
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
    _stopCountdown();
    super.dispose();
  }

  void _startCountdown(int ms) {
    _stopCountdown();
    _remainingMs = ms;
    _timer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!mounted) return;
      setState(() {
        _remainingMs = (_remainingMs - 200).clamp(0, 600000).toInt();
      });
      if (_remainingMs <= 0) {
        _stopCountdown();
      }
    });
  }

  void _stopCountdown() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();

    final seconds = (_remainingMs / 1000).ceil().clamp(0, 30).toInt();
    final reason = widget.reason ?? 'Confirme ta présence pour continuer.';

    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        alignment: Alignment.center,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Toujours là ?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  reason,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                Text(
                  'Spectateur dans ${seconds}s',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: widget.onConfirm,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Je suis là'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
