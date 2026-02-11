import 'package:http/http.dart' as http;

/// Vérification rapide de connectivité vers le backend Dutch.
///
/// Objectif: éviter d'attendre des timeouts longs quand l'app est hors-ligne.
class NetworkProbeService {
  static const String _healthUrl = 'https://dutch-game.me/health';
  static const Duration _cacheTtl = Duration(seconds: 3);

  static DateTime? _lastCheckAt;
  static bool? _lastResult;

  /// Retourne `true` si le backend est joignable rapidement.
  ///
  /// Stratégie: GET /health avec timeout court (ACK + timeout).
  static Future<bool> canReachBackend({
    Duration timeout = const Duration(milliseconds: 700),
  }) async {
    final now = DateTime.now();
    final lastAt = _lastCheckAt;
    final cached = _lastResult;
    if (lastAt != null &&
        cached != null &&
        now.difference(lastAt) <= _cacheTtl) {
      return cached;
    }

    bool reachable = false;
    try {
      final response = await http.get(Uri.parse(_healthUrl)).timeout(timeout);
      reachable = response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      reachable = false;
    }

    _lastCheckAt = now;
    _lastResult = reachable;
    return reachable;
  }
}
