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
    'assets/images/cards/dos-rouge.svg',
    // Cœurs
    'assets/images/cards/c-01.svg',
    'assets/images/cards/c-02.svg',
    'assets/images/cards/c-03.svg',
    'assets/images/cards/c-04.svg',
    'assets/images/cards/c-05.svg',
    'assets/images/cards/c-06.svg',
    'assets/images/cards/c-07.svg',
    'assets/images/cards/c-08.svg',
    'assets/images/cards/c-09.svg',
    'assets/images/cards/c-10.svg',
    'assets/images/cards/c-11.svg',
    'assets/images/cards/c-12.svg',
    'assets/images/cards/c-13.svg',
    // Carreaux
    'assets/images/cards/d-01.svg',
    'assets/images/cards/d-02.svg',
    'assets/images/cards/d-03.svg',
    'assets/images/cards/d-04.svg',
    'assets/images/cards/d-05.svg',
    'assets/images/cards/d-06.svg',
    'assets/images/cards/d-07.svg',
    'assets/images/cards/d-08.svg',
    'assets/images/cards/d-09.svg',
    'assets/images/cards/d-10.svg',
    'assets/images/cards/d-11.svg',
    'assets/images/cards/d-12.svg',
    'assets/images/cards/d-13.svg',
    // Trèfles
    'assets/images/cards/s-01.svg',
    'assets/images/cards/s-02.svg',
    'assets/images/cards/s-03.svg',
    'assets/images/cards/s-04.svg',
    'assets/images/cards/s-05.svg',
    'assets/images/cards/s-06.svg',
    'assets/images/cards/s-07.svg',
    'assets/images/cards/s-08.svg',
    'assets/images/cards/s-09.svg',
    'assets/images/cards/s-10.svg',
    'assets/images/cards/s-11.svg',
    'assets/images/cards/s-12.svg',
    'assets/images/cards/s-13.svg',
    // Piques
    'assets/images/cards/h-01.svg',
    'assets/images/cards/h-02.svg',
    'assets/images/cards/h-03.svg',
    'assets/images/cards/h-04.svg',
    'assets/images/cards/h-05.svg',
    'assets/images/cards/h-06.svg',
    'assets/images/cards/h-07.svg',
    'assets/images/cards/h-08.svg',
    'assets/images/cards/h-09.svg',
    'assets/images/cards/h-10.svg',
    'assets/images/cards/h-11.svg',
    'assets/images/cards/h-12.svg',
    'assets/images/cards/h-13.svg',
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
