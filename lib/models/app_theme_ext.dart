import 'package:flutter/material.dart';

import 'game_settings.dart';

/// Extension de présentation : mappe [AppTheme] vers le [ThemeMode] Flutter.
///
/// Isolée ici (et non dans game_settings.dart) pour que game_settings reste du
/// **Dart pur** sans dépendance `dart:ui` — il peut ainsi être compilé hors
/// Flutter (ex. générateur ML lancé via `dart run`).
extension AppThemeExt on AppTheme {
  ThemeMode get themeMode {
    switch (this) {
      case AppTheme.system:
        return ThemeMode.system;
      case AppTheme.light:
        return ThemeMode.light;
      case AppTheme.dark:
        return ThemeMode.dark;
      case AppTheme.green:
        return ThemeMode.dark; // dark brightness, green palette
    }
  }
}
