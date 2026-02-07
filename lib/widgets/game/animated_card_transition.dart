import 'package:flutter/material.dart';
import '../../models/playing_card.dart';
import 'card_widget.dart';

class AnimatedCardTransition extends StatefulWidget {
  final PlayingCard? card;
  final Offset startPosition;
  final Offset endPosition;
  final CardSize size;
  final bool isRevealed;
  final VoidCallback? onComplete;
  final Duration duration;
  final Curve curve;

  const AnimatedCardTransition({
    super.key,
    required this.card,
    required this.startPosition,
    required this.endPosition,
    required this.size,
    this.isRevealed = false,
    this.onComplete,
    this.duration = const Duration(milliseconds: 420),
    this.curve = Curves.easeOutCubic,
  });

  @override
  State<AnimatedCardTransition> createState() => _AnimatedCardTransitionState();
}

class _AnimatedCardTransitionState extends State<AnimatedCardTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _positionAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _shadowAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _positionAnimation = Tween<Offset>(
      begin: widget.startPosition,
      end: widget.endPosition,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: widget.curve,
    ));

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.08),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.08, end: 1.0),
        weight: 80,
      ),
    ]).animate(_controller);

    _rotationAnimation = Tween<double>(
      begin: 0,
      end: 0.06,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _shadowAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 4.0, end: 16.0),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 16.0, end: 4.0),
        weight: 70,
      ),
    ]).animate(_controller);

    _opacityAnimation = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
    ));

    _controller.forward().then((_) {
      if (widget.onComplete != null) {
        widget.onComplete!();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          left: _positionAnimation.value.dx,
          top: _positionAnimation.value.dy,
          child: IgnorePointer(
            child: RepaintBoundary(
              child: Opacity(
                opacity: _opacityAnimation.value,
                child: Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: _shadowAnimation.value,
                        offset: Offset(0, _shadowAnimation.value * 0.3),
                      ),
                    ],
                  ),
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Transform.rotate(
                      angle: _rotationAnimation.value,
                      child: child!,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: CardWidget(
        card: widget.card,
        size: widget.size,
        isRevealed: widget.isRevealed,
      ),
    );
  }
}
