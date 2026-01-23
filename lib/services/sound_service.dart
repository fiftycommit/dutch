import 'package:flutter/services.dart';

enum SoundType {
  cardFlip,
  cardDraw,
  cardDiscard,
  cardPlace,
  buttonTap,
  dutch,
  powerActivate,
  win,
  lose,
  error,
}

class SoundService {
  static bool _isEnabled = true;

  static void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  static bool get isEnabled => _isEnabled;

  static Future<void> play(SoundType sound) async {
    if (!_isEnabled) return;

    try {
      switch (sound) {
        case SoundType.cardFlip:
        case SoundType.cardDraw:
        case SoundType.cardPlace:
          await SystemSound.play(SystemSoundType.click);
          break;

        case SoundType.cardDiscard:
        case SoundType.buttonTap:
          await SystemSound.play(SystemSoundType.click);
          break;

        case SoundType.dutch:
        case SoundType.powerActivate:
          await SystemSound.play(SystemSoundType.alert);
          break;

        case SoundType.win:
          await SystemSound.play(SystemSoundType.click);
          await Future.delayed(const Duration(milliseconds: 100));
          await SystemSound.play(SystemSoundType.click);
          await Future.delayed(const Duration(milliseconds: 100));
          await SystemSound.play(SystemSoundType.click);
          break;

        case SoundType.lose:
          await SystemSound.play(SystemSoundType.alert);
          break;

        case SoundType.error:
          await SystemSound.play(SystemSoundType.alert);
          break;
      }
    } catch (e) {
      // Ignorer silencieusement
    }
  }

  static Future<void> cardFlip() => play(SoundType.cardFlip);
  static Future<void> cardDraw() => play(SoundType.cardDraw);
  static Future<void> cardDiscard() => play(SoundType.cardDiscard);
  static Future<void> cardPlace() => play(SoundType.cardPlace);
  static Future<void> buttonTap() => play(SoundType.buttonTap);
  static Future<void> dutch() => play(SoundType.dutch);
  static Future<void> powerActivate() => play(SoundType.powerActivate);
  static Future<void> win() => play(SoundType.win);
  static Future<void> lose() => play(SoundType.lose);
  static Future<void> error() => play(SoundType.error);
}
