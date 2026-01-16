import 'package:flutter/services.dart';

enum SoundType {
  cardFlip,      // Carte retournée
  cardDraw,      // Carte piochée
  cardDiscard,   // Carte défaussée
  cardPlace,     // Carte placée
  buttonTap,     // Bouton cliqué
  dutch,         // Cri "Dutch!"
  powerActivate, // Pouvoir activé
  win,           // Victoire
  lose,          // Défaite
  error,         // Erreur
}

class SoundService {
  static bool _isEnabled = true;

  // Activer/désactiver les sons
  static void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  static bool get isEnabled => _isEnabled;

  // Jouer un son
  static Future<void> play(SoundType sound) async {
    if (!_isEnabled) return;

    try {
      // Utiliser les sons système de Flutter
      // Pour l'instant on utilise SystemSound, plus tard on pourra ajouter audioplayers
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
          // Triple son pour succès
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
      // Ignorer les erreurs de son
    }
  }

  // Raccourcis pour les sons communs
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
