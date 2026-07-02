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

  /// Retourne `true` si le backend est joignable rapidement.
  ///
  /// Stratégie: GET /health avec timeout court (ACK + timeout).
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

    final hasNetworkPath = await connectivity_probe
        .hasNetworkInterface()
        .timeout(timeout, onTimeout: () => false);
    if (!hasNetworkPath) {
      _lastCheckAt = now;
      _lastResult = false;
      return false;
    }

    bool reachable = false;
    try {
      // Le backend est considéré joignable uniquement sur réponses HTTP "OK".
      final response = await http.get(Uri.parse(_healthUrl)).timeout(timeout);
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
