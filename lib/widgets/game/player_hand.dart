import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../models/player.dart';
import 'card_widget.dart';
import 'svg_builder_provider.dart';
import '../../utils/screen_utils.dart';

const double _cardAspectRatio = 7 / 5;

class HandMetrics {
  final double cardWidth;
  final double cardHeight;
  final double overlap;
  final double totalWidth;

  const HandMetrics({
    required this.cardWidth,
    required this.cardHeight,
    required this.overlap,
    required this.totalWidth,
  });
}

class PlayerHandWidget extends StatefulWidget {
  final Player player;
  final bool isHuman;
  final bool isActive;
  final Function(int)? onCardTap;
  final List<int>? selectedIndices;
  final List<int>? highlightedIndices;
  final List<int>? hiddenIndices;
  final List<String>? hiddenCardIds;
  final CardSize cardSize;
  final bool overlapCards;
  final bool fitToWidth;
  final SvgBuilder? svgBuilder;
  final bool isBeingShuffled;

  const PlayerHandWidget({
    super.key,
    required this.player,
    required this.isHuman,
    required this.isActive,
    this.onCardTap,
    this.selectedIndices,
    this.highlightedIndices,
    this.hiddenIndices,
    this.hiddenCardIds,
    this.cardSize = CardSize.medium,
    this.overlapCards = true,
    this.fitToWidth = false,
    this.svgBuilder,
    this.isBeingShuffled = false,
  });

  @override
  State<PlayerHandWidget> createState() => _PlayerHandWidgetState();

  static double overlapFactor(CardSize size) {
    switch (size) {
      case CardSize.tiny:
        return 0.3;
      case CardSize.small:
        return 0.28;
      case CardSize.medium:
        return 0.26;
      case CardSize.large:
        return 0.24;
      case CardSize.drawn:
        return 0.26;
    }
  }

  static HandMetrics metrics(
    BuildContext context,
    CardSize cardSize,
    int count, {
    bool overlapCards = true,
    double cardGap = 0.0,
  }) {
    final cardHeight = _scaledCardHeight(context, cardSize);
    final cardWidth = cardHeight / _cardAspectRatio;
    final overlap = overlapCards
        ? cardWidth * overlapFactor(cardSize)
        : cardWidth + cardGap;
    final visibleCount = math.max(1, count);
    final totalWidth = cardWidth + (visibleCount - 1) * overlap;
    return HandMetrics(
      cardWidth: cardWidth,
      cardHeight: cardHeight,
      overlap: overlap,
      totalWidth: totalWidth,
    );
  }

  static double _scaledCardHeight(BuildContext context, CardSize cardSize) {
    return ScreenUtils.scale(context, _baseCardHeight(cardSize)) *
        ScreenUtils.cardScaleFactor;
  }

  static double _baseCardHeight(CardSize cardSize) {
    switch (cardSize) {
      case CardSize.tiny:
        return 34;
      case CardSize.small:
        return 50;
      case CardSize.medium:
        return 76;
      case CardSize.large:
        return 128;
      case CardSize.drawn:
        return 102;
    }
  }
}

class _PlayerHandWidgetState extends State<PlayerHandWidget>
    with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  int _lastHandLength = 0;
  int? _penaltyHighlightIndex;
  Timer? _penaltyTimer;

  // Joker shuffle animation
  AnimationController? _shuffleController;
  bool _wasShuffled = false;
  late List<_ShuffleCardData> _shuffleOffsets;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _lastHandLength = widget.player.hand.length;
    _shuffleOffsets = [];
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _penaltyTimer?.cancel();
    _shuffleController?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PlayerHandWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.player.id != widget.player.id) {
      _penaltyTimer?.cancel();
      _penaltyHighlightIndex = null;
      _lastHandLength = widget.player.hand.length;
      return;
    }

    if (widget.player.hand.length > _lastHandLength) {
      _penaltyTimer?.cancel();
      setState(() {
        _penaltyHighlightIndex = widget.player.hand.length - 1;
      });
      _penaltyTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) {
          setState(() {
            _penaltyHighlightIndex = null;
          });
        }
      });
    }

    _lastHandLength = widget.player.hand.length;

    // Joker shuffle detection
    if (widget.isBeingShuffled && !_wasShuffled) {
      _startShuffleAnimation();
    }
    _wasShuffled = widget.isBeingShuffled;
  }

  void _startShuffleAnimation() {
    _shuffleController?.dispose();
    _shuffleController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    final rng = math.Random();
    final count = widget.player.hand.length;
    _shuffleOffsets = List.generate(count, (_) {
      return _ShuffleCardData(
        dx: (rng.nextDouble() - 0.5) * 40,
        dy: (rng.nextDouble() - 0.5) * 24,
        rotation: (rng.nextDouble() - 0.5) * 0.5,
      );
    });

    _shuffleController!.addListener(() {
      if (mounted) setState(() {});
    });

    _shuffleController!.forward().then((_) {
      if (mounted) {
        setState(() {
          _shuffleOffsets = [];
        });
      }
      _shuffleController?.dispose();
      _shuffleController = null;
    });
  }

  double _shuffleIntensity() {
    if (_shuffleController == null) return 0.0;
    final t = _shuffleController!.value;
    // Peaks at 0.35, then comes back to 0
    if (t < 0.35) {
      return Curves.easeOut.transform(t / 0.35);
    } else {
      return Curves.easeInOut.transform(1.0 - ((t - 0.35) / 0.65));
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.player.hand.length;
    final cardGap = ScreenUtils.spacing(context, 4.0);
    final metrics = PlayerHandWidget.metrics(
      context,
      widget.cardSize,
      count,
      overlapCards: widget.overlapCards,
      cardGap: cardGap,
    );

    return SizedBox(
      height: metrics.cardHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : metrics.totalWidth;
          double overlap = metrics.overlap;
          double totalWidth = metrics.totalWidth;

          if (widget.fitToWidth && count > 1 && totalWidth > maxWidth + 0.5) {
            final desiredOverlap = (maxWidth - metrics.cardWidth) / (count - 1);
            final minOverlap = metrics.cardWidth * 0.55;
            overlap = desiredOverlap.clamp(minOverlap, overlap);
            totalWidth = metrics.cardWidth + (count - 1) * overlap;
          }

          final needsScroll = totalWidth > maxWidth + 0.5;
          final content = SizedBox(
            width: totalWidth,
            height: metrics.cardHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: List.generate(
                count,
                (index) => Positioned(
                  left: index * overlap,
                  child: _buildCard(context, index),
                ),
              ),
            ),
          );

          if (!needsScroll) {
            return Align(alignment: Alignment.center, child: content);
          }

          final scrollView = SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: content,
          );

          return widget.isHuman
              ? Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: scrollView,
                )
              : scrollView;
        },
      ),
    );
  }

  Widget _buildCard(BuildContext context, int index) {
    final isSelected = widget.selectedIndices?.contains(index) ?? false;
    final isMemorizedHighlight =
        widget.highlightedIndices?.contains(index) ?? false;
    final isPenaltyHighlight = _penaltyHighlightIndex == index;
    final cardId = widget.player.hand[index].id;
    final isHidden = (widget.hiddenIndices?.contains(index) ?? false) ||
        (widget.hiddenCardIds?.contains(cardId) ?? false);
    const bool shouldReveal = false;

    final cardBody = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: isSelected ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 500),
      builder: (context, shakeValue, child) {
        final offset = isSelected
            ? (shakeValue < 0.5 ? shakeValue * 20 : (1 - shakeValue) * 20)
            : 0.0;

        return Transform.translate(
          offset: Offset(offset, 0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: isSelected
                  ? Border.all(color: Colors.red, width: 3)
                  : (isPenaltyHighlight
                      ? Border.all(color: Colors.redAccent, width: 2)
                      : (isMemorizedHighlight
                          ? Border.all(color: const Color(0xFFB8FF32), width: 2)
                          : null)),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.5),
                        blurRadius: 10,
                        spreadRadius: 2,
                      )
                    ]
                  : (isPenaltyHighlight
                      ? [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.45),
                            blurRadius: 8,
                            spreadRadius: 1,
                          )
                        ]
                      : (isMemorizedHighlight
                          ? [
                              BoxShadow(
                                color: const Color(0xFFB8FF32)
                                    .withValues(alpha: 0.65),
                                blurRadius: 12,
                                spreadRadius: 1.5,
                              ),
                              BoxShadow(
                                color:
                                    Colors.cyanAccent.withValues(alpha: 0.35),
                                blurRadius: 20,
                                spreadRadius: 1,
                              ),
                            ]
                          : null)),
            ),
            child: CardWidget(
              card: null,
              size: widget.cardSize,
              isRevealed: shouldReveal,
              svgBuilder: widget.svgBuilder,
            ),
          ),
        );
      },
    );

    Widget card = GestureDetector(
      onTap: () {
        if (widget.onCardTap != null && widget.isActive && !isHidden) {
          widget.onCardTap!(index);
        }
      },
      child: cardBody,
    );

    // Joker shuffle animation overlay
    final intensity = _shuffleIntensity();
    if (intensity > 0 && index < _shuffleOffsets.length) {
      final data = _shuffleOffsets[index];
      card = Transform.translate(
        offset: Offset(data.dx * intensity, data.dy * intensity),
        child: Transform.rotate(
          angle: data.rotation * intensity,
          child: card,
        ),
      );
    }

    if (!isHidden) return card;

    return Visibility(
      visible: false,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: IgnorePointer(child: card),
    );
  }
}

class _ShuffleCardData {
  final double dx;
  final double dy;
  final double rotation;

  const _ShuffleCardData({
    required this.dx,
    required this.dy,
    required this.rotation,
  });
}
