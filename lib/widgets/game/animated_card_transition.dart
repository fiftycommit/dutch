import 'package:flutter/material.dart';
import '../../models/card.dart';
import 'card_widget.dart';

class AnimatedCardTransition extends StatefulWidget {
  final PlayingCard? card;
  final Offset startPosition;
  final Offset endPosition;
  final CardSize size;
  final bool isRevealed;
  final VoidCallback? onComplete;
  final Duration duration;

  const AnimatedCardTransition({
    super.key,
    required this.card,
    required this.startPosition,
    required this.endPosition,
    required this.size,
    this.isRevealed = false,
    this.onComplete,
    this.duration = const Duration(milliseconds: 600),
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
      curve: Curves.easeInOutCubic,
    ));

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.2),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 1.0),
        weight: 70,
      ),
    ]).animate(_controller);

    _rotationAnimation = Tween<double>(
      begin: 0,
      end: 0.1,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
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
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Transform.rotate(
              angle: _rotationAnimation.value,
              child: CardWidget(
                card: widget.card,
                size: widget.size,
                isRevealed: widget.isRevealed,
              ),
            ),
          ),
        );
      },
    );
  }
}
