import 'package:flutter/material.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/playing_card.dart';
import 'package:dutch_game/utils/ui_constants.dart';
import 'package:dutch_game/widgets/game/card_widget.dart';

/// Pioche latérale (entre adversaires gauche et centre)
class SideDeckWidget extends StatelessWidget {
  final GameState gameState;
  final bool canDraw;
  final VoidCallback onDrawCard;
  final GlobalKey deckKey;

  const SideDeckWidget({
    super.key,
    required this.gameState,
    required this.canDraw,
    required this.onDrawCard,
    required this.deckKey,
  });

  @override
  Widget build(BuildContext context) {
    const padding = 8.0;

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          padding: const EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12, width: 1.5),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Opacity(
                opacity: canDraw ? 1.0 : 0.6,
                child: GestureDetector(
                  onTap: canDraw ? onDrawCard : null,
                  child: CardWidget(
                    key: deckKey,
                    card: null,
                    size: CardSize.medium,
                    isRevealed: false,
                  ),
                ),
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${gameState.deck.length}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Défausse latérale (entre centre et adversaires droite)
class SideDiscardWidget extends StatelessWidget {
  final GameState gameState;
  final bool canTakeDiscard;
  final VoidCallback? onTakeFromDiscard;
  final VoidCallback onShowDiscardPile;
  final PlayingCard? discardCard;
  final GlobalKey discardKey;

  const SideDiscardWidget({
    super.key,
    required this.gameState,
    required this.canTakeDiscard,
    this.onTakeFromDiscard,
    required this.onShowDiscardPile,
    required this.discardCard,
    required this.discardKey,
  });

  @override
  Widget build(BuildContext context) {
    const padding = 8.0;

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          padding: const EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12, width: 1.5),
          ),
          child: GestureDetector(
            onTap: canTakeDiscard
                ? onTakeFromDiscard
                : onShowDiscardPile,
            child: CardWidget(
              key: discardKey,
              card: discardCard,
              size: CardSize.medium,
              isRevealed: true,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bandeau mode spectateur
class SpectatorBanner extends StatelessWidget {
  const SpectatorBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility, color: Colors.amber, size: 24),
            SizedBox(width: 12),
            Text(
              "Mode Spectateur",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
