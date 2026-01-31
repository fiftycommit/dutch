import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../models/playing_card.dart';
import '../../game/card_widget.dart';
import '../responsive_dialog.dart';

/// Widgets partagés pour les dialogs de pouvoirs spéciaux
/// Principe GRASP: Pure Fabrication - Regroupe les widgets UI communs
class PowerDialogWidgets {
  static const double cardAspectRatio = 7 / 5;

  /// Calcule la largeur de carte pour une grille
  static double cardWidthForGrid(DialogMetrics metrics,
      {required int columns, double maxHeightFraction = 0.35}) {
    final spacing = metrics.space(8);
    final widthByCols = columns > 0
        ? (metrics.contentWidth - spacing * (columns - 1)) / columns
        : metrics.contentWidth;
    final heightByRows =
        (metrics.contentHeight * maxHeightFraction) / cardAspectRatio;
    return math.max(0.0, math.min(widthByCols, heightByRows));
  }

  /// Crée une carte mise à l'échelle
  static Widget scaledCard({
    required double width,
    required bool isRevealed,
    PlayingCard? card,
  }) {
    final height = width * cardAspectRatio;
    return SizedBox(
      width: width,
      height: height,
      child: FittedBox(
        fit: BoxFit.contain,
        child: CardWidget(
          card: card,
          size: CardSize.large,
          isRevealed: isRevealed,
        ),
      ),
    );
  }

  /// Crée un bouton de sélection de joueur
  static Widget playerSelectionButton({
    required String label,
    required bool isSelected,
    required Color baseColor,
    required VoidCallback onTap,
    required DialogMetrics metrics,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: metrics.space(12),
          vertical: metrics.space(8),
        ),
        decoration: BoxDecoration(
          color: isSelected ? baseColor.withValues(alpha: 0.8) : baseColor,
          border: Border.all(
            color: isSelected ? Colors.amber : Colors.white30,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: metrics.font(12),
          ),
        ),
      ),
    );
  }

  /// Crée une sélection de carte cliquable
  static Widget cardSelectionItem({
    required double cardWidth,
    required bool isSelected,
    required Color borderColor,
    required VoidCallback onTap,
    required DialogMetrics metrics,
  }) {
    final borderWidth = math.max(1.0, metrics.scale * 1.5);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Colors.amber : borderColor,
            width: isSelected ? borderWidth * 2 : borderWidth,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: scaledCard(width: cardWidth, isRevealed: false),
      ),
    );
  }

  /// En-tête de dialog avec icône et titre
  static Widget dialogHeader({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Color titleColor,
    String? subtitle,
    required DialogMetrics metrics,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: metrics.size(40)),
        SizedBox(height: metrics.space(8)),
        Text(
          title,
          style: TextStyle(
            color: titleColor,
            fontSize: metrics.font(20),
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        if (subtitle != null) ...[
          SizedBox(height: metrics.space(8)),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: metrics.font(14),
            ),
          ),
        ],
      ],
    );
  }

  /// Bouton "PASSER" ou "ANNULER"
  static Widget skipButton({
    required String label,
    required VoidCallback onPressed,
    required DialogMetrics metrics,
  }) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white54,
          fontSize: metrics.font(16),
        ),
      ),
    );
  }

  /// Bouton de confirmation stylisé
  static Widget confirmButton({
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
    required VoidCallback? onPressed,
    required DialogMetrics metrics,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        padding: EdgeInsets.symmetric(
          horizontal: metrics.space(28),
          vertical: metrics.space(12),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: metrics.font(16),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
