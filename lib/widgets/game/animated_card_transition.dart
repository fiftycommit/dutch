import 'package:flutter/material.dart';
import '../../models/playing_card.dart';
import '../../utils/ui_constants.dart';
import 'card_flight_stub.dart'
    if (dart.library.js_interop) 'card_flight_web.dart';
import 'card_widget.dart';

/// Carte volante entre deux positions de la table (pioche, défausse,
/// pénalité, échange Valet).
///
/// Coût par frame limité au compositing : la carte reste ancrée à
/// [startPosition] (pas de relayout via Positioned animé), le déplacement,
/// l'échelle et la rotation passent par une seule matrice [Transform], et
/// l'opacité par [FadeTransition]. L'ombre est statique et peinte une fois
/// dans le RepaintBoundary.
class AnimatedCardTransition extends StatefulWidget {
  final PlayingCard? card;
  final Offset startPosition;
  final Offset endPosition;
  final CardSize size;
  final bool isRevealed;
  final VoidCallback? onComplete;
  final Duration duration;
  final Curve curve;
  final bool preferBrowser;

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
    this.preferBrowser = false,
  });

  @override
  State<AnimatedCardTransition> createState() => _AnimatedCardTransitionState();
}

class _AnimatedCardTransitionState extends State<AnimatedCardTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offsetAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _rotationAnimation;
  late final Animation<double> _opacityAnimation;
  late bool _useBrowser;
  VoidCallback? _cancelBrowser;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);

    _offsetAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: widget.endPosition - widget.startPosition,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));

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
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _opacityAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
      ),
    );

    _useBrowser = widget.preferBrowser && webFlightAvailable;
    if (_useBrowser) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startBrowser());
    } else {
      _startFlutter();
    }
  }

  void _startFlutter() {
    _controller.forward().then((_) {
      if (mounted) widget.onComplete?.call();
    });
  }

  void _startBrowser() {
    if (!mounted) return;
    final box = context.findRenderObject()! as RenderBox;
    final start = box.localToGlobal(Offset.zero);
    final delta = widget.endPosition - widget.startPosition;
    final asset = widget.isRevealed
        ? widget.card?.imagePath ?? CardWidget.backAsset
        : CardWidget.backAsset;
    _cancelBrowser = startWebFlight(
      asset,
      start.dx,
      start.dy,
      delta.dx,
      delta.dy,
      box.size.width,
      box.size.height,
      widget.duration.inMilliseconds,
      (success) {
        if (!mounted) return;
        if (success) {
          widget.onComplete?.call();
        } else {
          setState(() => _useBrowser = false);
          _startFlutter();
        }
      },
    );
  }

  @override
  void dispose() {
    _cancelBrowser?.call();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_useBrowser) {
      return Positioned(
        left: widget.startPosition.dx,
        top: widget.startPosition.dy,
        child: SizedBox.fromSize(
          size: CardWidget.visualSize(context, widget.size),
        ),
      );
    }
    return Positioned(
      left: widget.startPosition.dx,
      top: widget.startPosition.dy,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final offset = _offsetAnimation.value;
            final transform = Matrix4.translationValues(offset.dx, offset.dy, 0)
              ..scaleByDouble(
                  _scaleAnimation.value, _scaleAnimation.value, 1, 1)
              ..rotateZ(_rotationAnimation.value);
            return Transform(
              transform: transform,
              alignment: Alignment.center,
              child: child,
            );
          },
          child: FadeTransition(
            opacity: _opacityAnimation,
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: CardWidget(
                  card: widget.card,
                  size: widget.size,
                  isRevealed: widget.isRevealed,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
