import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../logging/error_reporting_service.dart';

class SecureApiHeaders {
  static const Duration _tokenTimeout = Duration(seconds: 2);

  static Future<Map<String, String>> json({
    bool includeAuth = false,
    String? bearerToken,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    final resolvedToken =
        bearerToken ?? (includeAuth ? await _getAuthToken() : null);
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

  static Future<String?> _getAuthToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      final token = await user.getIdToken().timeout(_tokenTimeout);
      if (token == null || token.isEmpty) return null;
      return token;
    } catch (e, stackTrace) {
      ErrorReportingService().reportNetwork(
        e,
        stackTrace: stackTrace,
        endpoint: 'firebase-auth-token',
      );
      return null;
    }
  }

  static Future<String?> _getAppCheckToken() async {
    try {
      final token = await FirebaseAppCheck.instance.getToken().timeout(
            _tokenTimeout,
          );
      if (token == null || token.isEmpty) {
        return null;
      }
      return token;
    } catch (e, stackTrace) {
      ErrorReportingService().reportNetwork(
        e,
        stackTrace: stackTrace,
        endpoint: 'firebase-app-check-token',
      );
      return null;
    }
  }
}
