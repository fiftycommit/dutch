import 'package:flutter/material.dart';

import '../../../utils/ui_constants.dart';

/// Shared UI tokens for multiplayer/auth screens.
class MultiplayerUiTokens {
  MultiplayerUiTokens._();

  static const Duration motionFast = Duration(milliseconds: 150);
  static const Duration motionMedium = Duration(milliseconds: 190);
  static const Duration motionSlow = Duration(milliseconds: 220);

  static const BorderRadius radiusSm = BorderRadius.all(Radius.circular(12));
  static const BorderRadius radiusMd = BorderRadius.all(Radius.circular(16));
  static const BorderRadius radiusLg = BorderRadius.all(Radius.circular(20));
  static const BorderRadius radiusPill = BorderRadius.all(Radius.circular(999));

  static const Color textPrimary = AppColors.textPrimary;
  static const Color textSecondary = AppColors.textSecondary;
  static const Color onSurfacePrimary = Color(0xFF1F2937);
  static const Color onSurfaceSecondary = Color(0xFF4B5563);
  static const Color accentPrimary = AppColors.primary;
  static const Color accentDanger = Color(0xFFB91C1C);

  static BoxDecoration get pageBg => AppDecorations.pageBackground;

  static Color surfaceCard([double alpha = 0.72]) =>
      Colors.white.withValues(alpha: alpha);

  static Color surfaceCardStrong([double alpha = 0.62]) =>
      Colors.white.withValues(alpha: alpha);

  static Color outline([double alpha = 0.18]) =>
      Colors.white.withValues(alpha: alpha);

  static bool motionEnabled(BuildContext context) {
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery == null) return true;
    return !mediaQuery.disableAnimations;
  }
}
