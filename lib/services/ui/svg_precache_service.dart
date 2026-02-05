import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Service pour précacher tous les SVG de cartes au démarrage
/// Cela évite le lag d'animation sur Safari mobile
class SvgPrecacheService {
  static final SvgPrecacheService _instance = SvgPrecacheService._internal();
  factory SvgPrecacheService() => _instance;
  SvgPrecacheService._internal();

  bool _isPrecached = false;
  bool get isPrecached => _isPrecached;

  /// Tous les SVGs de cartes
  static const List<String> _allCardSvgPaths = [
    // Dos de cartes
    'assets/images/cards/dos-bleu.svg',
    'assets/images/cards/back.svg',
    // Cœurs (01-10, V, D, R)
    'assets/images/cards/01-coeur.svg',
    'assets/images/cards/02-coeur.svg',
    'assets/images/cards/03-coeur.svg',
    'assets/images/cards/04-coeur.svg',
    'assets/images/cards/05-coeur.svg',
    'assets/images/cards/06-coeur.svg',
    'assets/images/cards/07-coeur.svg',
    'assets/images/cards/08-coeur.svg',
    'assets/images/cards/09-coeur.svg',
    'assets/images/cards/10-coeur.svg',
    'assets/images/cards/V-coeur.svg',
    'assets/images/cards/D-coeur.svg',
    'assets/images/cards/R-coeur.svg',
    // Carreaux
    'assets/images/cards/01-carreau.svg',
    'assets/images/cards/02-carreau.svg',
    'assets/images/cards/03-carreau.svg',
    'assets/images/cards/04-carreau.svg',
    'assets/images/cards/05-carreau.svg',
    'assets/images/cards/06-carreau.svg',
    'assets/images/cards/07-carreau.svg',
    'assets/images/cards/08-carreau.svg',
    'assets/images/cards/09-carreau.svg',
    'assets/images/cards/10-carreau.svg',
    'assets/images/cards/V-carreau.svg',
    'assets/images/cards/D-carreau.svg',
    'assets/images/cards/R-carreau.svg',
    // Trèfles
    'assets/images/cards/01-trefle.svg',
    'assets/images/cards/02-trefle.svg',
    'assets/images/cards/03-trefle.svg',
    'assets/images/cards/04-trefle.svg',
    'assets/images/cards/05-trefle.svg',
    'assets/images/cards/06-trefle.svg',
    'assets/images/cards/07-trefle.svg',
    'assets/images/cards/08-trefle.svg',
    'assets/images/cards/09-trefle.svg',
    'assets/images/cards/10-trefle.svg',
    'assets/images/cards/V-trefle.svg',
    'assets/images/cards/D-trefle.svg',
    'assets/images/cards/R-trefle.svg',
    // Piques
    'assets/images/cards/01-pique.svg',
    'assets/images/cards/02-pique.svg',
    'assets/images/cards/03-pique.svg',
    'assets/images/cards/04-pique.svg',
    'assets/images/cards/05-pique.svg',
    'assets/images/cards/06-pique.svg',
    'assets/images/cards/07-pique.svg',
    'assets/images/cards/08-pique.svg',
    'assets/images/cards/09-pique.svg',
    'assets/images/cards/10-pique.svg',
    'assets/images/cards/V-pique.svg',
    'assets/images/cards/D-pique.svg',
    'assets/images/cards/R-pique.svg',
    // Jokers
    'assets/images/cards/joker-noir.svg',
    'assets/images/cards/joker-rouge.svg',
  ];

  /// Précache tous les SVGs de cartes
  Future<void> precacheCardSvgs() async {
    if (_isPrecached) return;

    final stopwatch = Stopwatch()..start();
    int loaded = 0;

    try {
      // Charger par batch de 10 pour paralléliser efficacement
      for (int i = 0; i < _allCardSvgPaths.length; i += 10) {
        final batch = _allCardSvgPaths.skip(i).take(10);
        await Future.wait(
          batch.map((path) async {
            await _loadSvg(path);
            loaded++;
          }),
          eagerError: false,
        );
      }
      
      stopwatch.stop();
      _isPrecached = true;
      debugPrint('✅ SVG précachés: $loaded/${_allCardSvgPaths.length} en ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('⚠️ Erreur précache SVG: $e');
    }
  }

  Future<void> _loadSvg(String path) async {
    try {
      final loader = SvgAssetLoader(path);
      await svg.cache.putIfAbsent(
        loader.cacheKey(null),
        () => loader.loadBytes(null),
      );
    } catch (e) {
      // Ignorer les erreurs individuelles
    }
  }
}
