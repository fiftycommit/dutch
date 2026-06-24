import 'dart:math';

/// Source d'aléatoire centralisée et seedable du moteur de jeu.
///
/// Objectif : permettre une génération de parties **reproductible** (dataset ML
/// self-play) en seedant un unique flux partagé par tout le moteur.
///
/// Garantie de non-régression : **non seedée**, [instance] renvoie un `Random()`
/// standard — comportement strictement identique à avant l'introduction de cette
/// classe (la production n'appelle jamais [seed]).
///
/// Principe GRASP : Pure Fabrication — responsabilité unique = fournir l'aléa moteur.
class EngineRandom {
  EngineRandom._();

  static Random _rng = Random();

  /// Réinitialise la source avec une graine déterministe (générateur de dataset).
  static void seed(int s) => _rng = Random(s);

  /// Restaure une source non déterministe (équivalent prod / isolation de tests).
  static void reset() => _rng = Random();

  /// Le flux partagé. À utiliser partout où le moteur tirait `Random()`.
  static Random get instance => _rng;
}
