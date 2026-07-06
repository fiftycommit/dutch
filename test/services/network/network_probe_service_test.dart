import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:dutch_game/services/network/network_probe_service.dart';

void main() {
  group('NetworkProbeService.canReachBackend', () {
    setUp(NetworkProbeService.resetForTest);
    tearDown(NetworkProbeService.resetForTest);

    test('pas d\'interface réseau ⇒ false SANS aucune requête HTTP', () async {
      var httpCalls = 0;
      NetworkProbeService.connectivityProbe = (_) async => false; // hors-ligne
      NetworkProbeService.httpGet = (url) async {
        httpCalls++;
        return http.Response('ok', 200);
      };

      final result =
          await NetworkProbeService.canReachBackend(useOptimisticGrace: false);

      expect(result, isFalse);
      expect(httpCalls, 0,
          reason: 'aucune requête /health ne doit partir quand il n\'y a '
              'pas d\'interface réseau (court-circuit hors-ligne)');
    });

    test('interface réseau + /health OK ⇒ true, avec un GET émis', () async {
      var httpCalls = 0;
      NetworkProbeService.connectivityProbe = (_) async => true;
      NetworkProbeService.httpGet = (url) async {
        httpCalls++;
        return http.Response('ok', 200);
      };

      final result =
          await NetworkProbeService.canReachBackend(useOptimisticGrace: false);

      expect(result, isTrue);
      expect(httpCalls, 1);
    });

    test('interface réseau mais /health échoue ⇒ false', () async {
      NetworkProbeService.connectivityProbe = (_) async => true;
      NetworkProbeService.httpGet = (url) async => throw Exception('boom');

      final result =
          await NetworkProbeService.canReachBackend(useOptimisticGrace: false);

      expect(result, isFalse);
    });

    test('résultat négatif mis en cache: pas de nouvelle sonde dans le TTL',
        () async {
      var probeCalls = 0;
      NetworkProbeService.connectivityProbe = (_) async {
        probeCalls++;
        return false;
      };

      await NetworkProbeService.canReachBackend(useOptimisticGrace: false);
      await NetworkProbeService.canReachBackend(useOptimisticGrace: false);

      expect(probeCalls, 1, reason: 'le second appel doit sortir du cache');
    });
  });
}
