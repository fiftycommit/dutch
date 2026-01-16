import 'package:flutter/material.dart';

// Profils d'appareils pour gérer les layouts
enum DeviceProfile {
  iPhonePortrait,    // iPhone en mode portrait
  iPhoneLandscape,   // iPhone en mode paysage
  iPadPortrait,      // iPad en mode portrait
  iPadLandscape,     // iPad en mode paysage
}

class ScreenUtils {
  // Tailles de référence (iPhone 14 Pro)
  static const double _referenceWidth = 393.0;
  static const double _referenceHeight = 852.0;

  // Obtenir le MediaQuery context
  static MediaQueryData _getMediaQuery(BuildContext context) {
    return MediaQuery.of(context);
  }

  // Largeur de l'écran
  static double width(BuildContext context) {
    return _getMediaQuery(context).size.width;
  }

  // Hauteur de l'écran
  static double height(BuildContext context) {
    return _getMediaQuery(context).size.height;
  }

  // Ratio de largeur par rapport à la référence
  static double widthRatio(BuildContext context) {
    return width(context) / _referenceWidth;
  }

  // Ratio de hauteur par rapport à la référence
  static double heightRatio(BuildContext context) {
    return height(context) / _referenceHeight;
  }

  // Ratio global (moyenne des deux)
  static double globalRatio(BuildContext context) {
    return (widthRatio(context) + heightRatio(context)) / 2;
  }

  // Scaler une largeur
  static double scaleWidth(BuildContext context, double size) {
    return size * widthRatio(context);
  }

  // Scaler une hauteur
  static double scaleHeight(BuildContext context, double size) {
    return size * heightRatio(context);
  }

  // Scaler une dimension (utilise le ratio global)
  static double scale(BuildContext context, double size) {
    return size * globalRatio(context);
  }

  // Scaler une font
  static double scaleFont(BuildContext context, double fontSize) {
    final ratio = globalRatio(context);
    // Limiter le scaling des fonts entre 0.85 et 1.2
    final clampedRatio = ratio.clamp(0.85, 1.2);
    return fontSize * clampedRatio;
  }

  // Safe area padding
  static EdgeInsets safeAreaPadding(BuildContext context) {
    return _getMediaQuery(context).padding;
  }

  // Safe area top
  static double safeAreaTop(BuildContext context) {
    return _getMediaQuery(context).padding.top;
  }

  // Safe area bottom
  static double safeAreaBottom(BuildContext context) {
    return _getMediaQuery(context).padding.bottom;
  }

  // Safe area left
  static double safeAreaLeft(BuildContext context) {
    return _getMediaQuery(context).padding.left;
  }

  // Safe area right
  static double safeAreaRight(BuildContext context) {
    return _getMediaQuery(context).padding.right;
  }

  // Hauteur utilisable (sans safe areas)
  static double usableHeight(BuildContext context) {
    final mq = _getMediaQuery(context);
    return mq.size.height - mq.padding.top - mq.padding.bottom;
  }

  // Largeur utilisable (sans safe areas)
  static double usableWidth(BuildContext context) {
    final mq = _getMediaQuery(context);
    return mq.size.width - mq.padding.left - mq.padding.right;
  }

  // Vérifier si c'est un petit écran (iPhone SE, etc.)
  static bool isSmallScreen(BuildContext context) {
    return width(context) < 375 || height(context) < 667;
  }

  // Vérifier si c'est un grand écran (iPhone Pro Max, etc.)
  static bool isLargeScreen(BuildContext context) {
    return width(context) > 430 || height(context) > 920;
  }

  // Vérifier si on est en mode portrait
  static bool isPortrait(BuildContext context) {
    return height(context) > width(context);
  }

  // Vérifier si on est en mode paysage
  static bool isLandscape(BuildContext context) {
    return width(context) > height(context);
  }

  // Vérifier si c'est une tablette (iPad)
  static bool isTablet(BuildContext context) {
    final diagonal = MediaQuery.of(context).size.shortestSide;
    return diagonal >= 600;
  }

  // Obtenir le profil d'appareil actuel
  static DeviceProfile getDeviceProfile(BuildContext context) {
    if (isTablet(context)) {
      return isPortrait(context) ? DeviceProfile.iPadPortrait : DeviceProfile.iPadLandscape;
    } else {
      return isPortrait(context) ? DeviceProfile.iPhonePortrait : DeviceProfile.iPhoneLandscape;
    }
  }

  // Calculer la taille d'une carte en fonction de l'écran
  static double cardWidth(BuildContext context, {bool isLarge = false}) {
    final baseWidth = isLarge ? 90.0 : 70.0;
    final scaled = scaleWidth(context, baseWidth);

    // Limiter la taille min/max
    if (isLarge) {
      return scaled.clamp(75.0, 110.0);
    } else {
      return scaled.clamp(55.0, 85.0);
    }
  }

  // Calculer la hauteur d'une carte (ratio 1.4)
  static double cardHeight(BuildContext context, {bool isLarge = false}) {
    return cardWidth(context, isLarge: isLarge) * 1.4;
  }

  // Espacement adaptatif
  static double spacing(BuildContext context, double baseSpacing) {
    return scale(context, baseSpacing).clamp(baseSpacing * 0.7, baseSpacing * 1.3);
  }

  // Taille de bouton adaptative
  static double buttonHeight(BuildContext context) {
    return scaleHeight(context, 50.0).clamp(45.0, 60.0);
  }

  // Padding adaptatif
  static EdgeInsets adaptivePadding(BuildContext context, {
    double horizontal = 16.0,
    double vertical = 16.0,
  }) {
    return EdgeInsets.symmetric(
      horizontal: spacing(context, horizontal),
      vertical: spacing(context, vertical),
    );
  }

  // Border radius adaptatif
  static double borderRadius(BuildContext context, double baseRadius) {
    return scale(context, baseRadius).clamp(baseRadius * 0.8, baseRadius * 1.2);
  }

  // Taille de la carte piochée selon le profil
  static double drawnCardSize(BuildContext context) {
    final profile = getDeviceProfile(context);
    switch (profile) {
      case DeviceProfile.iPhonePortrait:
        return 140.0; // Plus grand en portrait iPhone
      case DeviceProfile.iPhoneLandscape:
        return 100.0; // Moyen en paysage iPhone
      case DeviceProfile.iPadPortrait:
        return 160.0; // Grand sur iPad portrait
      case DeviceProfile.iPadLandscape:
        return 140.0; // Grand sur iPad paysage
    }
  }

  // Taille des cartes en main selon le profil
  static double handCardSize(BuildContext context) {
    final profile = getDeviceProfile(context);
    switch (profile) {
      case DeviceProfile.iPhonePortrait:
        return 80.0; // Assez grand en portrait
      case DeviceProfile.iPhoneLandscape:
        return 65.0; // Plus petit en paysage
      case DeviceProfile.iPadPortrait:
        return 160.0; // Très grand sur iPad
      case DeviceProfile.iPadLandscape:
        return 150.0; // Très grand sur iPad paysage
    }
  }

  // Taille des cartes des bots selon le profil
  static double botCardSize(BuildContext context) {
    final profile = getDeviceProfile(context);
    switch (profile) {
      case DeviceProfile.iPhonePortrait:
        return 65.0; // Augmenté pour meilleure visibilité
      case DeviceProfile.iPhoneLandscape:
        return 60.0; // Un peu plus grand en paysage
      case DeviceProfile.iPadPortrait:
        return 88.0; // Réduit de 20% (110 * 0.8)
      case DeviceProfile.iPadLandscape:
        return 96.0; // Réduit de 20% (120 * 0.8)
    }
  }

  // Espacement entre zones selon le profil
  static double zoneSpacing(BuildContext context) {
    final profile = getDeviceProfile(context);
    switch (profile) {
      case DeviceProfile.iPhonePortrait:
        return 8.0; // Espacement minimal en portrait
      case DeviceProfile.iPhoneLandscape:
        return 16.0; // Plus d'espace en paysage
      case DeviceProfile.iPadPortrait:
        return 24.0;
      case DeviceProfile.iPadLandscape:
        return 32.0;
    }
  }

  // ========== LAYOUT CIRCULAIRE ADAPTATIF (style Ocho) ==========

  // Rayon du cercle pour positionner les joueurs
  static double circleRadius(BuildContext context) {
    final profile = getDeviceProfile(context);
    final screenWidth = width(context);
    final screenHeight = height(context);
    final smallestDimension = screenWidth < screenHeight ? screenWidth : screenHeight;

    switch (profile) {
      case DeviceProfile.iPhonePortrait:
        return smallestDimension * 0.32; // Plus serré en portrait
      case DeviceProfile.iPhoneLandscape:
        return smallestDimension * 0.38; // Plus grand en paysage
      case DeviceProfile.iPadPortrait:
        return smallestDimension * 0.35;
      case DeviceProfile.iPadLandscape:
        return smallestDimension * 0.40; // Très grand sur iPad paysage
    }
  }

  // Taille d'un widget joueur (largeur approximative)
  static double playerWidgetWidth(BuildContext context) {
    final profile = getDeviceProfile(context);
    switch (profile) {
      case DeviceProfile.iPhonePortrait:
        return 150.0;
      case DeviceProfile.iPhoneLandscape:
        return 160.0;
      case DeviceProfile.iPadPortrait:
        return 180.0;
      case DeviceProfile.iPadLandscape:
        return 200.0;
    }
  }

  // Hauteur d'un widget joueur (approximative)
  static double playerWidgetHeight(BuildContext context) {
    final profile = getDeviceProfile(context);
    switch (profile) {
      case DeviceProfile.iPhonePortrait:
        return 160.0; // Avatar + cartes + spacing
      case DeviceProfile.iPhoneLandscape:
        return 140.0;
      case DeviceProfile.iPadPortrait:
        return 180.0;
      case DeviceProfile.iPadLandscape:
        return 160.0;
    }
  }

  // Largeur du widget central (pioche + défausse)
  static double centerWidgetWidth(BuildContext context) {
    final profile = getDeviceProfile(context);
    switch (profile) {
      case DeviceProfile.iPhonePortrait:
        return 200.0; // Augmenté pour meilleure visibilité
      case DeviceProfile.iPhoneLandscape:
        return 220.0;
      case DeviceProfile.iPadPortrait:
        return 450.0; // Très grand pour iPad - pioche/défausse bien visibles
      case DeviceProfile.iPadLandscape:
        return 480.0; // Très grand pour iPad paysage - pioche/défausse bien visibles
    }
  }

  // Hauteur du widget central
  static double centerWidgetHeight(BuildContext context) {
    final profile = getDeviceProfile(context);
    switch (profile) {
      case DeviceProfile.iPhonePortrait:
        return 200.0; // Augmenté pour meilleure visibilité
      case DeviceProfile.iPhoneLandscape:
        return 160.0;
      case DeviceProfile.iPadPortrait:
        return 400.0; // Très grand pour iPad - pioche/défausse bien visibles
      case DeviceProfile.iPadLandscape:
        return 380.0; // Très grand pour iPad paysage - pioche/défausse bien visibles
    }
  }

  // Offset du joueur en bas (distance from bottom)
  static double bottomPlayerOffset(BuildContext context) {
    final profile = getDeviceProfile(context);
    switch (profile) {
      case DeviceProfile.iPhonePortrait:
        return 40.0; // Plus proche du bord en portrait
      case DeviceProfile.iPhoneLandscape:
        return 50.0;
      case DeviceProfile.iPadPortrait:
        return 60.0;
      case DeviceProfile.iPadLandscape:
        return 70.0; // Plus d'espace sur iPad
    }
  }

  // Offset du joueur en haut (distance from top supplémentaire)
  static double topPlayerExtraOffset(BuildContext context) {
    final profile = getDeviceProfile(context);
    switch (profile) {
      case DeviceProfile.iPhonePortrait:
        return 20.0;
      case DeviceProfile.iPhoneLandscape:
        return 30.0;
      case DeviceProfile.iPadPortrait:
        return 40.0;
      case DeviceProfile.iPadLandscape:
        return 50.0;
    }
  }

  // Offset horizontal pour les joueurs latéraux
  static double sidePlayerExtraOffset(BuildContext context) {
    final profile = getDeviceProfile(context);
    switch (profile) {
      case DeviceProfile.iPhonePortrait:
        return 10.0;
      case DeviceProfile.iPhoneLandscape:
        return 20.0;
      case DeviceProfile.iPadPortrait:
        return 30.0;
      case DeviceProfile.iPadLandscape:
        return 40.0;
    }
  }
}
