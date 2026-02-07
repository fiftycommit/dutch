import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service pour précacher tous les SVG de cartes au démarrage
/// Cela évite le lag d'animation sur Safari mobile
class SvgPrecacheService {
  static final SvgPrecacheService _instance = SvgPrecacheService._internal();
  factory SvgPrecacheService() => _instance;
  SvgPrecacheService._internal();

  bool _isPrecached = false;
  bool get isPrecached => _isPrecached;
  static const String _prefsKey = 'svg_precache_v1';

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
  /// [onProgress] est appelé avec une valeur entre 0.0 et 1.0.
  Future<void> precacheCardSvgs({
    void Function(double progress)? onProgress,
    bool skipIfCached = false,
  }) async {
    if (_isPrecached) {
      onProgress?.call(1.0);
      return;
    }

    final desiredCacheSize = _allCardSvgPaths.length + 20;
    if (svg.cache.maximumSize < desiredCacheSize) {
      svg.cache.maximumSize = desiredCacheSize;
    }

    if (skipIfCached) {
      final wasPrecached = await _wasPrecachedPersisted();
      if (wasPrecached) {
        onProgress?.call(1.0);
        return;
      }
    }

    final stopwatch = Stopwatch()..start();
    final total = _allCardSvgPaths.length;
    int loaded = 0;
    onProgress?.call(0.0);

    try {
      // Charger par batch de 10 pour paralléliser efficacement
      for (int i = 0; i < _allCardSvgPaths.length; i += 10) {
        final batch = _allCardSvgPaths.skip(i).take(10);
        await Future.wait(
          batch.map((path) async {
            await _loadSvg(path);
            loaded++;
            if (onProgress != null) {
              onProgress(loaded / total);
            }
          }),
          eagerError: false,
        );
      }
      
      stopwatch.stop();
      _isPrecached = true;
      await _setPrecachedPersisted();
      onProgress?.call(1.0);
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Erreur précache SVG: $e');
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
      if (kDebugMode) debugPrint('⚠️ SVG precache individuel: $e');
    }
  }

  Future<bool> _wasPrecachedPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefsKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _setPrecachedPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, true);
    } catch (_) {
      // Ignorer si le stockage n'est pas dispo
    }
  }
}
