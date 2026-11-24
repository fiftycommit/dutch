import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/playing_card.dart';
import 'card_widget.dart';

/// Retournement 3D d'une carte piloté par [animationValue] (0 = dos, 1 = face).
/// Utilisé dans l'écran de révélation Dutch.
///
/// Le dos et la face sont construits dès le départ dans un [IndexedStack] :
/// le SVG de la face est chargé avant le retournement, au lieu d'être décodé
/// à mi-animation (saccade au premier passage, quand rien n'est en cache).
/// Seule la matrice de transformation change à chaque frame ; chaque
/// [CardWidget] est isolé dans son propre RepaintBoundary.
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
    final showFront = isRevealed && animationValue > 0.5;
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.001)
      ..rotateY(animationValue * math.pi);

    return Transform(
      transform: transform,
      alignment: Alignment.center,
      child: IndexedStack(
        index: showFront ? 1 : 0,
        alignment: Alignment.center,
        children: [
          CardWidget(card: null, size: cardSize, isRevealed: false),
          Transform(
            transform: Matrix4.rotationY(math.pi),
            alignment: Alignment.center,
            child: CardWidget(card: card, size: cardSize, isRevealed: true),
          ),
        ],
      ),
    );
  }
}
