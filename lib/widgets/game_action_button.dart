import 'package:flutter/material.dart';

class GameActionButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool compact;
  final bool withPulse;
  final bool enabled;

  const GameActionButton({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.compact = false,
    this.withPulse = false,
    this.enabled = true,
  });

  @override
  State<GameActionButton> createState() => _GameActionButtonState();
}

class _GameActionButtonState extends State<GameActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.withPulse) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(GameActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.withPulse && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.withPulse && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.enabled && widget.onTap != null;
    final radius = widget.compact ? 6.0 : 10.0;
    final borderWidth = widget.compact ? 1.2 : 1.4;
    final fontSize = widget.compact ? 9.0 : 11.0;
    final baseColor =
        isEnabled ? widget.color : widget.color.withValues(alpha: 0.35);
    final labelColor = isEnabled ? Colors.white : Colors.white70;

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isEnabled ? widget.onTap : null,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: baseColor.withValues(alpha: isEnabled ? 0.3 : 0.2),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: baseColor, width: borderWidth),
          ),
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: labelColor,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );

    if (!widget.withPulse || !isEnabled) {
      return button;
    }

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final t = ((_pulseAnimation.value - 1.0) / 0.08).clamp(0.0, 1.0);
        final glow = widget.compact ? 6 + (8 * t) : 8 + (12 * t);
        final spread = widget.compact ? 0.8 + (0.8 * t) : 1.0 + (1.0 * t);
        final alpha = widget.compact ? 0.3 + (0.2 * t) : 0.35 + (0.25 * t);
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: alpha),
                  blurRadius: glow,
                  spreadRadius: spread,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: button,
    );
  }
}
