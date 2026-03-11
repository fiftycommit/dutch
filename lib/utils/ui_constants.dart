/// Constantes UI centralisées pour l'accessibilité et la cohérence
/// Basé sur les critères Bastien & Scapin
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/game_settings.dart';
import '../providers/settings_provider.dart';

/// Schéma de couleurs pour l'espace multijoueur — light ou dark.
class MultiplayerColorScheme {
  const MultiplayerColorScheme({
    required this.primary,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.appBar,
    required this.inputBar,
    required this.sentBubble,
    required this.receivedBubble,
    required this.textPrimary,
    required this.textBody,
    required this.textSecondary,
    required this.separator,
    required this.success,
    required this.danger,
    required this.kicked,
    required this.warning,
    required this.info,
  });

  final Color primary;
  final Color background;
  final Color surface;       // cards, sheets
  final Color surfaceHigh;   // éléments surélevés (bulles reçues, input)
  final Color appBar;
  final Color inputBar;
  final Color sentBubble;
  final Color receivedBubble;
  final Color textPrimary;
  final Color textBody;      // texte secondaire légèrement atténué
  final Color textSecondary;
  final Color separator;
  final Color success;
  final Color danger;
  final Color kicked;        // même que danger, sémantique explicite
  final Color warning;
  final Color info;
}

/// Couleurs de l'espace multijoueur — palette iOS system (sobre, Apple-style).
/// Utiliser [MultiplayerColors.of(context)] dans les widgets.
class MultiplayerColors {
  MultiplayerColors._();

  /// Retourne le schéma adapté au thème choisi (clair / sombre / vert / système).
  static MultiplayerColorScheme of(BuildContext context) {
    try {
      final appTheme = Provider.of<SettingsProvider>(context, listen: false).appTheme;
      if (appTheme == AppTheme.green) return green;
    } catch (_) {}
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  static const light = MultiplayerColorScheme(
    primary:         Color(0xFF007AFF),
    background:      Color(0xFFF2F2F7),
    surface:         Color(0xFFFFFFFF),
    surfaceHigh:     Color(0xFFE9E9EB),
    appBar:          Color(0xFF007AFF),
    inputBar:        Color(0xFFF2F2F7),
    sentBubble:      Color(0xFF007AFF),
    receivedBubble:  Color(0xFFFFFFFF),
    textPrimary:     Color(0xFF000000),
    textBody:        Color(0xFF1C1C1E),
    textSecondary:   Color(0xFF6E6E73),
    separator:       Color(0xFFC6C6C8),
    success:         Color(0xFF34C759),
    danger:          Color(0xFFFF3B30),
    kicked:          Color(0xFFFF3B30),
    warning:         Color(0xFFFF9500),
    info:            Color(0xFF007AFF),
  );

  static const dark = MultiplayerColorScheme(
    primary:         Color(0xFF0A84FF),
    background:      Color(0xFF000000),
    surface:         Color(0xFF1C1C1E),
    surfaceHigh:     Color(0xFF2C2C2E),
    appBar:          Color(0xFF1E1E1E),
    inputBar:        Color(0xFF1C1C1E),
    sentBubble:      Color(0xFF0A84FF),
    receivedBubble:  Color(0xFF3A3A3C),
    textPrimary:     Color(0xFFFFFFFF),
    textBody:        Color(0xFFEBEBF5),
    textSecondary:   Color(0xFFAEAEB2),
    separator:       Color(0xFF38383A),
    success:         Color(0xFF30D158),
    danger:          Color(0xFFFF453A),
    kicked:          Color(0xFFFF453A),
    warning:         Color(0xFFFF9F0A),
    info:            Color(0xFF0A84FF),
  );

  /// Palette verte — inspirée du fond du jeu solo (AppColors.gradientTop/Bottom).
  static const green = MultiplayerColorScheme(
    primary:         Color(0xFF4CAF50),   // vert vif Apple-style
    background:      Color(0xFF0D1F15),   // proche de gradientTop
    surface:         Color(0xFF1A3A28),   // proche de gradientBottom
    surfaceHigh:     Color(0xFF234D35),   // légèrement plus clair
    appBar:          Color(0xFF1A3A28),
    inputBar:        Color(0xFF1A3A28),
    sentBubble:      Color(0xFF4CAF50),
    receivedBubble:  Color(0xFF234D35),
    textPrimary:     Color(0xFFFFFFFF),
    textBody:        Color(0xFFE8F5E9),   // blanc légèrement vert
    textSecondary:   Color(0xFFA8C5A8),   // vert grisé lisible
    separator:       Color(0xFF2E5C3D),
    success:         Color(0xFF66BB6A),
    danger:          Color(0xFFFF453A),
    kicked:          Color(0xFFFF453A),
    warning:         Color(0xFFFFB300),
    info:            Color(0xFF4CAF50),
  );

  // Fallbacks statiques (light) pour les rares cas sans contexte
  static const Color primary       = Color(0xFF007AFF);
  static const Color success       = Color(0xFF34C759);
  static const Color danger        = Color(0xFFFF3B30);
  static const Color kicked        = Color(0xFFFF3B30);
  static const Color warning       = Color(0xFFFF9500);
  static const Color info          = Color(0xFF007AFF);
  static const Color textPrimary   = Color(0xFF000000);
  static const Color textBody      = Color(0xFF1C1C1E);
  static const Color textSecondary = Color(0xFF6E6E73);
  static const Color background    = Color(0xFFF2F2F7);
  static const Color createAccent  = Color(0xFF007AFF);
  static const Color joinAccent    = Color(0xFF007AFF);
}

/// Couleurs avec contraste WCAG AA minimum (4.5:1 pour texte normal)
class AppColors {
  AppColors._();

  // === Couleurs de texte sur fond sombre ===
  /// Couleur de compatibilité (utilisée par les écrans Auth)
  static const Color gameBackground = gradientBottom;

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

  /// Animation rapide (états hover/opacity)
  static const Duration fast = Duration(milliseconds: 150);

  /// Transition de menu (sélection slot, boutons)
  static const Duration menuTransition = Duration(milliseconds: 200);

  /// Animation standard
  static const Duration normal = Duration(milliseconds: 300);

  /// Retournement de carte (flip 3D)
  static const Duration cardFlip = Duration(milliseconds: 500);

  /// Déplacement de carte (transition position)
  static const Duration cardMove = Duration(milliseconds: 420);

  /// Animation pulsation (Dutch, actions urgentes)
  static const Duration pulse = Duration(milliseconds: 1200);

  /// Timeout réseau par défaut
  static const Duration networkTimeout = Duration(seconds: 15);

  /// Timeout pour opérations longues
  static const Duration longTimeout = Duration(seconds: 30);
}
