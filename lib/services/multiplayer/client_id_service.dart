import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class ClientIdService {
  static const String storageKey = 'multiplayer_client_id';
  static String? _cachedClientId;

  static Future<String> ensureClientId() async {
    final cached = _cachedClientId;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(storageKey);
    if (existing != null && existing.isNotEmpty) {
      _cachedClientId = existing;
      return existing;
    }

    final random = Random();
    final generated =
        '${DateTime.now().millisecondsSinceEpoch}-${random.nextInt(1 << 30)}';

    // Best effort persistence (private mode can reject writes).
    try {
      await prefs.setString(storageKey, generated);
    } catch (_) {}

    _cachedClientId = generated;
    return generated;
  }
}
