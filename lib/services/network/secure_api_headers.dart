import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SecureApiHeaders {
  static Future<Map<String, String>> json({
    bool includeAuth = false,
    String? bearerToken,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    final resolvedToken = bearerToken ??
        (includeAuth ? await FirebaseAuth.instance.currentUser?.getIdToken() : null);
    if (resolvedToken != null && resolvedToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $resolvedToken';
    }

    final appCheckToken = await _getAppCheckToken();
    if (appCheckToken != null) {
      headers['X-Firebase-AppCheck'] = appCheckToken;
    }

    return headers;
  }

  static Future<Map<String, String>> authorizedJson() {
    return json(includeAuth: true);
  }

  static Future<String?> _getAppCheckToken() async {
    try {
      final token = await FirebaseAppCheck.instance.getToken();
      if (token == null || token.isEmpty) {
        return null;
      }
      return token;
    } catch (_) {
      return null;
    }
  }
}
