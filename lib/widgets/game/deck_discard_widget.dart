import 'package:flutter/material.dart';
import '../../utils/ui_constants.dart';
import '../../models/playing_card.dart';
import 'card_widget.dart';
import 'svg_builder_provider.dart';

class DeckCardWidget extends StatelessWidget {
  final int deckCount;
  final CardSize cardSize;
  final bool isCompact;
  final bool enabled;
  final VoidCallback? onTap;
  final SvgBuilder? svgBuilder;

  const DeckCardWidget({
    super.key,
    required this.deckCount,
    required this.cardSize,
    required this.isCompact,
    required this.enabled,
    this.onTap,
    this.svgBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final deckCard = Opacity(
      opacity: enabled ? 1.0 : 0.6,
      child: CardWidget(
        card: null,
        size: cardSize,
        isRevealed: false,
        svgBuilder: svgBuilder,
      ),
    );
    final deckWidget = enabled && onTap != null
        ? GestureDetector(onTap: onTap, child: deckCard)
        : deckCard;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        deckWidget,
        Positioned(
          bottom: -2,
          right: -2,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 4 : 6,
              vertical: isCompact ? 1 : 2,
            ),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$deckCount',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: isCompact ? 9 : 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class DiscardCardWidget extends StatelessWidget {
  final PlayingCard? card;
  final CardSize cardSize;
  final VoidCallback? onTap;
  final SvgBuilder? svgBuilder;

  const DiscardCardWidget({
    super.key,
    required this.card,
    required this.cardSize,
    this.onTap,
    this.svgBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final discardCard = CardWidget(
      card: card,
      size: cardSize,
      isRevealed: true,
      svgBuilder: svgBuilder,
    );

    return onTap != null
        ? GestureDetector(onTap: onTap, child: discardCard)
        : discardCard;
  }
}
