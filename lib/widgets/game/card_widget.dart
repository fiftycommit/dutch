import 'package:flutter/material.dart';
import '../../models/playing_card.dart';
import '../../utils/screen_utils.dart';
import 'svg_builder_provider.dart';

enum CardSize { tiny, small, medium, large, drawn }

const double _cardAspectRatio = 7 / 5;

class CardWidget extends StatelessWidget {
  final PlayingCard? card;
  final CardSize size;
  final bool isRevealed;
  final VoidCallback? onTap;
  final SvgBuilder? svgBuilder;

  const CardWidget({
    super.key,
    required this.card,
    required this.size,
    required this.isRevealed,
    this.onTap,
    this.svgBuilder,
  });

  @override
  Widget build(BuildContext context) {
    double width;
    double height;

    switch (size) {
      case CardSize.tiny:
        height = 34;
        break;
      case CardSize.small:
        height = 50;
        break;
      case CardSize.medium:
        height = 76;
        break;
      case CardSize.large:
        height = 128;
        break;
      case CardSize.drawn:
        height = 102;
        break;
    }

    width = height / _cardAspectRatio;
    width = ScreenUtils.scale(context, width) * ScreenUtils.cardScaleFactor;
    height = ScreenUtils.scale(context, height) * ScreenUtils.cardScaleFactor;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(ScreenUtils.borderRadius(context, 4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(2, 2),
              )
            ],
          ),
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(ScreenUtils.borderRadius(context, 4)),
            child: _buildCardImage(context, width, height),
          ),
        ),
      ),
    );
  }

  Widget _buildCardImage(BuildContext context, double w, double h) {
    final builder = svgBuilder ?? SvgBuilderProvider.maybeOf(context);
    
    if (card == null || !isRevealed) {
      return builder('assets/images/cards/dos-bleu.svg', w, h);
    }

    return builder(card!.imagePath, w, h);
  }
}
