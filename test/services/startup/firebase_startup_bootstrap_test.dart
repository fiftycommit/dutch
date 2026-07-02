import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/startup/firebase_startup_bootstrap.dart';

void main() {
  group('FirebaseStartupBootstrap.run — bornage réseau dégradé', () {
    // Un Future qui ne se résout jamais, pour simuler un appel Firebase qui pend
    // (réseau dégradé : sonde positive mais Firebase réellement injoignable).
    Future<void> hangs() => Completer<void>().future;

    const shortTimeouts = {
      'firebase': Duration(milliseconds: 120),
      'appCheck': Duration(milliseconds: 120),
      'auth': Duration(milliseconds: 120),
    };

    test('initializeApp qui pend ⇒ false dans la limite du timeout', () async {
      final sw = Stopwatch()..start();
      final ready = await FirebaseStartupBootstrap.run(
        reachBackend: () async => true,
        initializeApp: hangs,
        activateAppCheck: () async {},
        firebaseTimeout: shortTimeouts['firebase']!,
        appCheckTimeout: shortTimeouts['appCheck']!,
        authPersistenceTimeout: shortTimeouts['auth']!,
      );
      sw.stop();

      expect(ready, isFalse);
      expect(sw.elapsed, lessThan(const Duration(milliseconds: 600)),
          reason: 'initializeApp ne doit pas pouvoir bloquer au-delà de '
              'son timeout');
    });

    test('init OK mais AppCheck et persistence pendent ⇒ true, borné', () async {
      final sw = Stopwatch()..start();
      final ready = await FirebaseStartupBootstrap.run(
        reachBackend: () async => true,
        initializeApp: () async {},
        activateAppCheck: hangs, // best-effort, ne doit pas bloquer le démarrage
        setAuthPersistence: hangs,
        firebaseTimeout: shortTimeouts['firebase']!,
        appCheckTimeout: shortTimeouts['appCheck']!,
        authPersistenceTimeout: shortTimeouts['auth']!,
      );
      sw.stop();

      expect(ready, isTrue,
          reason: 'AppCheck/persistence sont best-effort : le démarrage réussit '
              'même si elles pendent');
      // appCheck (120ms) + auth (120ms) en série, + marge.
      expect(sw.elapsed, lessThan(const Duration(milliseconds: 700)));
    });

    test('sonde négative ⇒ false sans appeler initializeApp', () async {
      var initCalled = false;
      final ready = await FirebaseStartupBootstrap.run(
        reachBackend: () async => false,
        initializeApp: () async {
          initCalled = true;
        },
        activateAppCheck: () async {},
      );

      expect(ready, isFalse);
      expect(initCalled, isFalse);
    });

    test('plafond explicite des étapes Firebase reste raisonnable', () {
      // Garde-fou anti-régression du splash ~10s : si quelqu'un gonfle un
      // timeout, ce test tombe en rouge.
      expect(FirebaseStartupBootstrap.boundedStepsCap(),
          const Duration(seconds: 7));
      expect(FirebaseStartupBootstrap.boundedStepsCap(),
          lessThanOrEqualTo(const Duration(seconds: 8)));
    });
  });
}
