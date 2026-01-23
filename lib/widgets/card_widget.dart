import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/card.dart';
import '../utils/screen_utils.dart';

enum CardSize { tiny, small, medium, large, drawn }

class CardWidget extends StatelessWidget {
  final PlayingCard? card;
  final CardSize size;
  final bool isRevealed;
  final VoidCallback? onTap;

  const CardWidget({
    super.key,
    required this.card,
    required this.size,
    required this.isRevealed,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    double width;
    double height;

    switch (size) {
      case CardSize.tiny:
        width = 28;
        height = 42;
        break;
      case CardSize.small:
        width = 40;
        height = 60;
        break;
      case CardSize.medium:
        width = 60;
        height = 90;
        break;
      case CardSize.large:
        width = 100;
        height = 150;
        break;
      case CardSize.drawn:
        width = 80;
        height = 120;
        break;
    }

    width = ScreenUtils.scale(context, width);
    height = ScreenUtils.scale(context, height);

    return GestureDetector(
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
          child: _buildCardImage(width, height),
        ),
      ),
    );
  }

  Widget _buildCardImage(double w, double h) {
    if (card == null || !isRevealed) {
      return SvgPicture.asset(
        'assets/images/cards/dos-bleu.svg',
        width: w,
        height: h,
        fit: BoxFit.contain,
      );
    }

    return SvgPicture.asset(
      card!.imagePath,
      width: w,
      height: h,
      fit: BoxFit.contain,
      placeholderBuilder: (context) => Container(
        color: Colors.white,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}
