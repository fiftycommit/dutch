/// Constantes UI centralisées pour l'accessibilité et la cohérence
/// Basé sur les critères Bastien & Scapin
library;

import 'package:flutter/material.dart';

/// Couleurs avec contraste WCAG AA minimum (4.5:1 pour texte normal)
class AppColors {
  AppColors._();

  // === Couleurs de texte sur fond sombre ===
  /// Texte secondaire lisible (remplace Colors.white70)
  /// Ratio de contraste ~7:1 sur fond #1a3a28
  static const Color textSecondary = Color(0xDEFFFFFF); // 87% opacity = white87

  /// Texte désactivé visible (remplace white54/white60)
  /// Ratio de contraste ~5:1
  static const Color textDisabled = Color(0xB3FFFFFF); // 70% opacity

  /// Texte tertiaire/hint
  static const Color textHint = Color(0x99FFFFFF); // 60% opacity

  /// Texte principal
  static const Color textPrimary = Colors.white;

  // === Couleurs d'état ===
  /// Élément désactivé - visible mais clairement inactif
  static const Color disabledBackground = Color(0xFF3D5C4A);
  static const Color disabledForeground = Color(0xB3FFFFFF);

  /// Couleur de fond pour éléments interactifs désactivés
  static Color buttonDisabledBackground = Colors.grey.shade700;
  static const Color buttonDisabledForeground = Color(0x99FFFFFF);

  // === Fonds avec opacité visible ===
  /// Fond semi-transparent lisible (remplace withOpacity(0.1-0.2))
  static const Color overlayLight = Color(0x40000000); // 25% noir
  static const Color overlayMedium = Color(0x60000000); // 37% noir

  // === Couleurs du thème ===
  static const Color primary = Colors.amber;
  static const Color primaryDark = Color(0xFFFF8F00);
  static const Color success = Color(0xFF4CAF50);
  static const Color error = Color(0xFFEF5350);
  static const Color warning = Color(0xFFFF9800);

  // === Fonds de l'app ===
  static const Color backgroundDark = Color(0xFF0d1f15);
  static const Color backgroundMedium = Color(0xFF1a3a28);
  static const Color cardBackground = Color(0xFF2a4a38);

  // === Couleurs de gradient ===
  static const Color gradientTop = Color(0xFF0d2818);
  static const Color gradientBottom = Color(0xFF1a472a);

  // === Couleurs de surface ===
  static const Color buttonSecondary = Color(0xFF2d5f3e);
  static const Color dialogBackground = Color(0xFF1a3a28);
  static const Color dialogDanger = Color(0xFF2d1a1a);
}

/// Gradients et décorations réutilisables
class AppDecorations {
  AppDecorations._();

  /// Gradient principal de fond (utilisé par la plupart des écrans)
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.gradientTop, AppColors.gradientBottom],
  );

  /// Gradient plus sombre (splash, loading)
  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.backgroundMedium, AppColors.backgroundDark],
  );

  /// Gradient diagonal (lobby, multiplayer screens)
  static const LinearGradient diagonalGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.gradientTop, AppColors.gradientBottom],
  );

  /// Fond de page standard
  static const BoxDecoration pageBackground = BoxDecoration(
    gradient: backgroundGradient,
  );

  /// Fond de page diagonal
  static const BoxDecoration pageDiagonalBackground = BoxDecoration(
    gradient: diagonalGradient,
  );

  /// Fond de carte semi-transparent
  static BoxDecoration cardDecoration = BoxDecoration(
    color: Colors.white.withValues(alpha: 0.1),
    borderRadius: BorderRadius.circular(12),
  );
}

/// Tailles de police minimales pour l'accessibilité
class AppFontSizes {
  AppFontSizes._();

  /// Taille minimale absolue (jamais en dessous)
  static const double minimum = 11.0;

  /// Petits labels (remplace 8-9px)
  static const double small = 11.0;

  /// Corps de texte compact
  static const double bodySmall = 12.0;

  /// Corps de texte standard
  static const double body = 14.0;

  /// Sous-titres
  static const double subtitle = 16.0;

  /// Titres
  static const double title = 18.0;

  /// Grands titres
  static const double headline = 20.0;

  /// Très grands titres
  static const double display = 24.0;
}

/// Dimensions standardisées des boutons
class AppButtonSizes {
  AppButtonSizes._();

  /// Hauteur minimale tactile (WCAG recommande 44px)
  static const double minTouchTarget = 44.0;

  /// Bouton compact (mode paysage/compact)
  static const double compact = 40.0;

  /// Bouton standard
  static const double standard = 48.0;

  /// Grand bouton (actions principales)
  static const double large = 56.0;

  /// Largeur minimale pour boutons avec texte
  static const double minWidth = 88.0;
}

/// Espacements cohérents
class AppSpacing {
  AppSpacing._();

  /// Espacement minimal (remplace 2-4px incohérents)
  static const double xs = 4.0;

  /// Petit espacement
  static const double sm = 8.0;

  /// Espacement standard
  static const double md = 12.0;

  /// Espacement moyen-grand
  static const double lg = 16.0;

  /// Grand espacement
  static const double xl = 24.0;

  /// Très grand espacement
  static const double xxl = 32.0;
}

/// Styles de texte prédéfinis accessibles
class AppTextStyles {
  AppTextStyles._();

  /// Texte secondaire lisible (remplace white70)
  static const TextStyle secondary = TextStyle(
    color: AppColors.textSecondary,
    fontSize: AppFontSizes.body,
  );

  /// Texte secondaire petit
  static const TextStyle secondarySmall = TextStyle(
    color: AppColors.textSecondary,
    fontSize: AppFontSizes.bodySmall,
  );

  /// Texte désactivé visible
  static const TextStyle disabled = TextStyle(
    color: AppColors.textDisabled,
    fontSize: AppFontSizes.body,
  );

  /// Label petit mais lisible
  static const TextStyle labelSmall = TextStyle(
    color: AppColors.textSecondary,
    fontSize: AppFontSizes.small,
    fontWeight: FontWeight.w500,
  );

  /// Corps de texte standard
  static const TextStyle body = TextStyle(
    color: AppColors.textPrimary,
    fontSize: AppFontSizes.body,
  );

  /// Titre de section
  static const TextStyle sectionTitle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: AppFontSizes.title,
    fontWeight: FontWeight.bold,
  );
}

/// Durées d'animation et timeouts
class AppDurations {
  AppDurations._();

  /// Animation rapide
  static const Duration fast = Duration(milliseconds: 150);

  /// Animation standard
  static const Duration normal = Duration(milliseconds: 300);

  /// Timeout réseau par défaut
  static const Duration networkTimeout = Duration(seconds: 15);

  /// Timeout pour opérations longues
  static const Duration longTimeout = Duration(seconds: 30);
}
