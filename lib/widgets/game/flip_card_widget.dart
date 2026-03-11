import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/playing_card.dart';
import '../../utils/ui_constants.dart';
import 'card_widget.dart';

/// Widget réutilisable pour l'animation de retournement 3D d'une carte.
/// Utilisé dans l'écran de révélation Dutch et la mémorisation.
class FlipCardWidget extends StatelessWidget {
  final PlayingCard card;
  final bool isRevealed;
  final double animationValue;
  final CardSize cardSize;

  const FlipCardWidget({
    super.key,
    required this.card,
    required this.isRevealed,
    required this.animationValue,
    this.cardSize = CardSize.small,
  });

  @override
  Widget build(BuildContext context) {
    final angle = animationValue * math.pi;
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.001)
      ..rotateY(angle);
    final showFront = animationValue > 0.5;

    return Transform(
      transform: transform,
      alignment: Alignment.center,
      child: showFront && isRevealed
          ? Transform(
              transform: Matrix4.rotationY(math.pi),
              alignment: Alignment.center,
              child: CardWidget(card: card, size: cardSize, isRevealed: true),
            )
          : CardWidget(card: null, size: cardSize, isRevealed: false),
    );
  }
}

/// Version autonome avec animation intégrée (flip automatique).
/// Utile pour les listes de cartes avec staggered reveal.
class AnimatedFlipCard extends StatefulWidget {
  final PlayingCard card;
  final bool isRevealed;
  final CardSize cardSize;
  final Duration duration;
  final Duration delay;
  final Curve curve;

  const AnimatedFlipCard({
    super.key,
    required this.card,
    required this.isRevealed,
    this.cardSize = CardSize.large,
    this.duration = AppDurations.cardFlip,
    this.delay = Duration.zero,
    this.curve = Curves.easeInOutCubic,
  });

  @override
  State<AnimatedFlipCard> createState() => _AnimatedFlipCardState();
}

class _AnimatedFlipCardState extends State<AnimatedFlipCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _flipAnimation;
  bool _hasStarted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    _flipAnimation = CurvedAnimation(
      parent: _controller,
      curve: widget.curve,
    );

    if (widget.isRevealed) {
      _startWithDelay();
    }
  }

  void _startWithDelay() {
    if (_hasStarted) return;
    _hasStarted = true;
    Future.delayed(widget.delay, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void didUpdateWidget(covariant AnimatedFlipCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRevealed && !oldWidget.isRevealed) {
      _startWithDelay();
    } else if (!widget.isRevealed && oldWidget.isRevealed) {
      _hasStarted = false;
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flipAnimation,
      builder: (context, child) {
        return FlipCardWidget(
          card: widget.card,
          isRevealed: widget.isRevealed,
          animationValue: _flipAnimation.value,
          cardSize: widget.cardSize,
        );
      },
    );
  }
}
