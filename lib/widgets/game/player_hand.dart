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
  final bool isPowerHighlighted;
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
    this.isPowerHighlighted = false,
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
    with TickerProviderStateMixin {
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
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    final rng = math.Random();
    final count = widget.player.hand.length;
    _shuffleOffsets = List.generate(count, (index) {
      // Forcer un déplacement significatif pour chaque carte
      int t1 = _randomFarIndex(rng, index, count);
      int t2 = _randomFarIndex(rng, t1, count);
      return _ShuffleCardData(
        targetIndex1: t1,
        targetIndex2: t2,
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

  /// Génère un index suffisamment éloigné de [fromIndex] pour un mouvement visible
  int _randomFarIndex(math.Random rng, int fromIndex, int count) {
    if (count <= 2) return (count - 1) - fromIndex;
    // Essayer de trouver un index à distance >= 2
    for (int attempt = 0; attempt < 10; attempt++) {
      final candidate = rng.nextInt(count);
      if ((candidate - fromIndex).abs() >= 2) return candidate;
    }
    // Fallback : aller à l'extrémité opposée
    return fromIndex < count ~/ 2 ? count - 1 : 0;
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
                  key: ValueKey(
                    'hand-card-${widget.player.id}-$index-${widget.player.hand[index].id}',
                  ),
                  left: index * overlap,
                  child: _buildCard(context, index, overlap),
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

  Widget _buildCard(BuildContext context, int index, double overlap) {
    final isSelected = widget.selectedIndices?.contains(index) ?? false;
    final isHighlighted = widget.highlightedIndices?.contains(index) ?? false;
    final highlightColor = widget.isPowerHighlighted
        ? const Color(0xFFFFD700)
        : const Color(0xFFB8FF32);
    final highlightGlowColor =
        widget.isPowerHighlighted ? Colors.amber : Colors.cyanAccent;
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
                      : (isHighlighted
                          ? Border.all(color: highlightColor, width: 2)
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
                      : (isHighlighted
                          ? [
                              BoxShadow(
                                color: highlightColor.withValues(alpha: 0.65),
                                blurRadius: 12,
                                spreadRadius: 1.5,
                              ),
                              BoxShadow(
                                color:
                                    highlightGlowColor.withValues(alpha: 0.35),
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

    // Joker shuffle animation overlay (3 phases : pos1, pos2, retour)
    if (_shuffleController != null && index < _shuffleOffsets.length) {
      final t = _shuffleController!.value;
      final data = _shuffleOffsets[index];

      double dx = 0.0;
      final dx1 = (data.targetIndex1 - index) * overlap;
      final dx2 = (data.targetIndex2 - index) * overlap;

      if (t < 0.33) {
        // Phase 1 : aller vers targetIndex1
        final p = Curves.easeInOut.transform(t / 0.33);
        dx = dx1 * p;
      } else if (t < 0.66) {
        // Phase 2 : aller de targetIndex1 vers targetIndex2
        final p = Curves.easeInOut.transform((t - 0.33) / 0.33);
        dx = dx1 + (dx2 - dx1) * p;
      } else {
        // Phase 3 : retour à la position d'origine
        final p = Curves.easeInOut.transform((t - 0.66) / 0.34);
        dx = dx2 * (1 - p);
      }

      card = Transform.translate(
        offset: Offset(dx, 0),
        child: card,
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
  final int targetIndex1;
  final int targetIndex2;

  const _ShuffleCardData({
    required this.targetIndex1,
    required this.targetIndex2,
  });
}
