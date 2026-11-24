import 'package:flutter/material.dart';
import '../../models/playing_card.dart';
import '../../utils/ui_constants.dart';
import 'card_widget.dart';

/// Carte volante entre deux positions de la table (pioche, défausse,
/// pénalité, échange Valet).
///
/// La carte reste ancrée à [startPosition]. Seule sa translation change :
/// pas de relayout, de couche d'opacité ni de flou pendant le vol.
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
    this.duration = AppDurations.cardMove,
    this.curve = Curves.easeOutCubic,
  });

  @override
  State<AnimatedCardTransition> createState() => _AnimatedCardTransitionState();
}

class _AnimatedCardTransitionState extends State<AnimatedCardTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);

    _offsetAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: widget.endPosition - widget.startPosition,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));

    _controller.forward().then((_) => widget.onComplete?.call());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.startPosition.dx,
      top: widget.startPosition.dy,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Transform.translate(
            offset: _offsetAnimation.value,
            child: child,
          ),
          child: CardWidget(
            card: widget.card,
            size: widget.size,
            isRevealed: widget.isRevealed,
            showShadow: false,
          ),
        ),
      ),
    );
  }
}
