import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_settings.dart';
import '../services/ui/haptic_service.dart';
import '../services/ui/sound_service.dart';

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
    HapticService.setEnabled(value);
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

  void setActionTextDisplayTime(int ms) {
    _settings = _settings.copyWith(actionTextDisplayMs: ms);
    _saveSettings();
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final String? settingsJson = prefs.getString(_prefsKey);
    if (settingsJson != null) {
      _settings = GameSettings.fromJson(jsonDecode(settingsJson));
      SoundService.setEnabled(_settings.soundEnabled);
      HapticService.setEnabled(_settings.hapticEnabled);
      notifyListeners();
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_settings.toJson()));
  }
}
