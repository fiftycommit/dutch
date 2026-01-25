import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../models/player.dart';
import 'card_widget.dart';
import '../utils/screen_utils.dart';

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
  final CardSize cardSize;
  final bool overlapCards;

  const PlayerHandWidget({
    super.key,
    required this.player,
    required this.isHuman,
    required this.isActive,
    this.onCardTap,
    this.selectedIndices,
    this.cardSize = CardSize.medium,
    this.overlapCards = true,
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

class _PlayerHandWidgetState extends State<PlayerHandWidget> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
          final needsScroll = metrics.totalWidth > maxWidth + 0.5;
          final content = SizedBox(
            width: metrics.totalWidth,
            height: metrics.cardHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: List.generate(
                count,
                (index) => Positioned(
                  left: index * metrics.overlap,
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
    const bool shouldReveal = false;

    return GestureDetector(
      onTap: () {
        if (widget.onCardTap != null && widget.isActive) {
          widget.onCardTap!(index);
        }
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: isSelected ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 500),
        builder: (context, shakeValue, child) {
          final offset = isSelected
              ? (shakeValue < 0.5 ? shakeValue * 20 : (1 - shakeValue) * 20)
              : 0.0;

          return Transform.translate(
            offset: Offset(offset, 0),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border:
                    isSelected ? Border.all(color: Colors.red, width: 3) : null,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        )
                      ]
                    : null,
              ),
              child: CardWidget(
                card: null,
                size: widget.cardSize,
                isRevealed: shouldReveal,
              ),
            ),
          );
        },
      ),
    );
  }
}
