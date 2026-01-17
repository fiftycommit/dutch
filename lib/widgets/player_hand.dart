import 'package:flutter/material.dart';
import '../models/player.dart';
import '../models/card.dart';
import 'card_widget.dart';

class PlayerHandWidget extends StatelessWidget {
  final Player player;
  final bool isHuman;
  final bool isActive;
  final Function(int)? onCardTap;
  final List<int>? selectedIndices;
  final CardSize cardSize;

  const PlayerHandWidget({
    super.key,
    required this.player,
    required this.isHuman,
    required this.isActive,
    this.onCardTap,
    this.selectedIndices,
    this.cardSize = CardSize.medium,
  });

  @override
  Widget build(BuildContext context) {
    debugPrint("🃏 [PlayerHandWidget] BUILD - Joueur: ${player.name}");
    debugPrint("   - isActive: $isActive");
    debugPrint("   - onCardTap fourni: ${onCardTap != null}");
    debugPrint("   - Nombre de cartes: ${player.hand.length}");
    
    return SizedBox(
      height: _getHandHeight(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          player.hand.length,
          (index) {
            debugPrint("   🃏 Création carte #$index");
            return _buildCard(index);
          },
        ),
      ),
    );
  }

  Widget _buildCard(int index) {
    final isSelected = selectedIndices?.contains(index) ?? false;
    final bool shouldReveal = false;

    return GestureDetector(
      onTap: () {
        debugPrint("🔥🔥🔥 [PlayerHandWidget._buildCard] ════════════════════");
        debugPrint("👆 TAP DÉTECTÉ sur carte #$index");
        debugPrint("   - Joueur: ${player.name}");
        debugPrint("   - isActive: $isActive");
        debugPrint("   - onCardTap fourni: ${onCardTap != null}");
        
        if (onCardTap != null && isActive) {
          debugPrint("   ✅ CONDITIONS REMPLIES - Appel onCardTap($index)");
          onCardTap!(index);
        } else {
          debugPrint("   ❌ CONDITIONS NON REMPLIES");
          debugPrint("      - onCardTap null: ${onCardTap == null}");
          debugPrint("      - isActive false: ${!isActive}");
        }
        
        debugPrint("🔥🔥🔥 [PlayerHandWidget._buildCard] FIN ═══════════════════");
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: _getCardSpacing()),
        child: TweenAnimationBuilder<double>(
          // ✅ Animation de shake pour les erreurs
          tween: Tween(begin: 0.0, end: isSelected ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 500),
          builder: (context, shakeValue, child) {
            // Shake horizontal pour l'erreur
            final offset = isSelected ? (shakeValue < 0.5 ? shakeValue * 20 : (1 - shakeValue) * 20) : 0.0;
            
            return Transform.translate(
              offset: Offset(offset - 10, 0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(color: Colors.red, width: 3) // ✅ Rouge pour erreur
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.5), // ✅ Rouge pour erreur
                            blurRadius: 10,
                            spreadRadius: 2,
                          )
                        ]
                      : null,
                ),
                child: CardWidget(
                  card: null,
                  size: cardSize,
                  isRevealed: shouldReveal,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  double _getHandHeight() {
    CardSize taille = cardSize;

    if (taille == CardSize.small) {
      return 70;
    }
    else if (taille == CardSize.medium) {
      return 100;
    }
    else if (taille == CardSize.large) {
      return 140;
    }
    return 70;
  }

  double _getCardSpacing() {
    CardSize taille = cardSize;

    if (taille == CardSize.small) {
      return 2;
    }
    else if (taille == CardSize.medium) {
      return 4;
    }
    else if (taille == CardSize.large) {
      return 6;
    }
    return 2;
  }
}