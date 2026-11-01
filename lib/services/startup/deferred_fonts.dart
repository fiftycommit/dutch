import 'package:flutter/services.dart';

/// Les familles utilisées uniquement après navigation ne bloquent pas le menu.
/// Les fichiers restent des assets locaux, y compris hors ligne.
class DeferredFonts {
  static Future<void>? _inter;
  static Future<void>? _montserrat;

  static Future<void> inter() =>
      _inter ??= _load('Inter').catchError((Object error, StackTrace stack) {
        _inter = null;
        Error.throwWithStackTrace(error, stack);
      });

  static Future<void> montserrat() => _montserrat ??=
          _load('Montserrat').catchError((Object error, StackTrace stack) {
        _montserrat = null;
        Error.throwWithStackTrace(error, stack);
      });

  static Future<void> _load(String family) async {
    final loader = FontLoader(family)
      ..addFont(rootBundle.load('assets/fonts/$family.ttf'))
      ..addFont(rootBundle.load('assets/fonts/$family-Italic.ttf'));
    await loader.load();
  }
}
