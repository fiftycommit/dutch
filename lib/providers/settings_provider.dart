import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_settings.dart';
import '../models/app_theme_ext.dart';
import '../core/interfaces/i_haptic_service.dart';
import '../core/service_locator.dart';
import '../services/ui/sound_service.dart';
import '../services/logging/error_reporting_service.dart';

class SettingsProvider with ChangeNotifier {
  GameSettings _settings = GameSettings();
  static const String _prefsKey = 'game_settings';

  SettingsProvider() {
    _loadSettings();
  }

  GameSettings get settings => _settings;

  bool get soundEnabled => _settings.soundEnabled;
  bool get hapticEnabled => _settings.hapticEnabled;
  bool get animationsEnabled => _settings.animationsEnabled;
  bool get cardRainEnabled => _settings.cardRainEnabled;
  bool get useSBMM => _settings.useSBMM;
  AppTheme get appTheme => _settings.appTheme;
  ThemeMode get themeMode => _settings.appTheme.themeMode;

  Difficulty get botDifficulty => _settings.botDifficulty;
  int get reactionTimeMs => _settings.reactionTimeMs;
  int get actionTextDisplayMs => _settings.actionTextDisplayMs;

  void toggleSound(bool value) {
    _settings = _settings.copyWith(soundEnabled: value);
    SoundService.setEnabled(value);
    _saveSettings();
    notifyListeners();
  }

  void toggleHaptic(bool value) {
    _settings = _settings.copyWith(hapticEnabled: value);
    // Synchroniser avec l'instance DI unique (corrige le bug où solo ignorait le toggle)
    ServiceLocator().get<IHapticService>().setEnabled(value);
    _saveSettings();
    notifyListeners();
  }

  void toggleAnimations(bool value) {
    _settings = _settings.copyWith(animationsEnabled: value);
    _saveSettings();
    notifyListeners();
  }

  void toggleCardRain(bool value) {
    _settings = _settings.copyWith(cardRainEnabled: value);
    _saveSettings();
    notifyListeners();
  }

  void toggleSBMM(bool value) {
    _settings = _settings.copyWith(useSBMM: value);
    _saveSettings();
    notifyListeners();
  }

  void setBotDifficulty(Difficulty difficulty) {
    _settings = _settings.copyWith(botDifficulty: difficulty);
    _saveSettings();
    notifyListeners();
  }

  void setReactionTime(int ms) {
    _settings = _settings.copyWith(reactionTimeMs: ms);
    _saveSettings();
    notifyListeners();
  }

  void setAppTheme(AppTheme theme) {
    _settings = _settings.copyWith(appTheme: theme);
    _saveSettings();
    notifyListeners();
  }

  void setActionTextDisplayTime(int ms) {
    _settings = _settings.copyWith(actionTextDisplayMs: ms);
    _saveSettings();
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? settingsJson = prefs.getString(_prefsKey);
      if (settingsJson != null) {
        _settings = GameSettings.fromJson(jsonDecode(settingsJson));
        SoundService.setEnabled(_settings.soundEnabled);
        // Synchroniser avec l'instance DI unique
        ServiceLocator()
            .get<IHapticService>()
            .setEnabled(_settings.hapticEnabled);
        notifyListeners();
      }
    } catch (e, stackTrace) {
      // En cas de données corrompues, on garde les paramètres par défaut
      // et on supprime la valeur corrompue pour éviter le même crash au prochain lancement
      ErrorReportingService().reportStorage(
        e,
        stackTrace: stackTrace,
        operation: 'lecture',
        key: _prefsKey,
      );
      _settings = GameSettings();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefsKey);
      } catch (_) {
        // Impossible de nettoyer — on continue avec les valeurs par défaut
      }
      notifyListeners();
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_settings.toJson()));
    } catch (e, stackTrace) {
      ErrorReportingService().reportStorage(
        e,
        stackTrace: stackTrace,
        operation: 'écriture',
        key: _prefsKey,
      );
    }
  }
}
