import 'package:http/http.dart' as http;

import 'connectivity_probe_stub.dart'
    if (dart.library.ui) 'connectivity_probe_flutter.dart'
    as connectivity_probe;

/// Vérification rapide de connectivité vers le backend Dutch.
///
/// Objectif: éviter d'attendre des timeouts longs quand l'app est hors-ligne.
class NetworkProbeService {
  static const String _healthUrl = 'https://dutch-game.me/health';
  static const Duration _successCacheTtl = Duration(seconds: 4);
  static const Duration _failureCacheTtl = Duration(seconds: 1);
  static const Duration _optimisticGraceAfterSuccess = Duration(seconds: 12);

  static DateTime? _lastCheckAt;
  static bool? _lastResult;
  static DateTime? _lastSuccessAt;

  /// Sonde d'interface réseau (rapide, sans I/O réseau). Surchargée en test.
  static Future<bool> Function(Duration timeout) connectivityProbe =
      _defaultConnectivityProbe;

  /// GET utilisé pour la sonde `/health`. Surchargé en test pour vérifier
  /// qu'aucune requête ne part quand il n'y a pas de réseau.
  static Future<http.Response> Function(Uri url) httpGet = http.get;

  static Future<bool> _defaultConnectivityProbe(Duration timeout) {
    return connectivity_probe
        .hasNetworkInterface()
        .timeout(timeout, onTimeout: () => false);
  }

  /// Réinitialise le cache et les seams de test entre deux tests.
  static void resetForTest() {
    _lastCheckAt = null;
    _lastResult = null;
    _lastSuccessAt = null;
    connectivityProbe = _defaultConnectivityProbe;
    httpGet = http.get;
  }

  /// Retourne `true` si le backend est joignable rapidement.
  ///
  /// Stratégie: sonde d'interface réseau d'abord (instantanée), puis GET /health
  /// avec timeout court. Pas d'interface réseau ⇒ `false` immédiat, sans HTTP.
  static Future<bool> canReachBackend({
    Duration timeout = const Duration(milliseconds: 700),
    bool useOptimisticGrace = true,
  }) async {
    final now = DateTime.now();
    final lastAt = _lastCheckAt;
    final cached = _lastResult;
    final cacheTtl = cached == true ? _successCacheTtl : _failureCacheTtl;
    if (lastAt != null &&
        cached != null &&
        now.difference(lastAt) <= cacheTtl) {
      return cached;
    }

    final hasNetworkPath = await connectivityProbe(timeout);
    if (!hasNetworkPath) {
      _lastCheckAt = now;
      _lastResult = false;
      return false;
    }

    bool reachable = false;
    try {
      // Le backend est considéré joignable uniquement sur réponses HTTP "OK".
      final response = await httpGet(Uri.parse(_healthUrl)).timeout(timeout);
      reachable = response.statusCode >= 200 && response.statusCode <= 399;
    } catch (_) {
      reachable = false;
    }

    if (useOptimisticGrace &&
        !reachable &&
        _lastSuccessAt != null &&
        now.difference(_lastSuccessAt!) <= _optimisticGraceAfterSuccess) {
      // Évite les faux "offline" sur des fluctuations réseau courtes.
      reachable = true;
    }

    _lastCheckAt = now;
    _lastResult = reachable;
    if (reachable) {
      _lastSuccessAt = now;
    }
    return reachable;
  }
}
