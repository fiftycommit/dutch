import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

const String _webAppCheckSiteKey =
    String.fromEnvironment('FIREBASE_APP_CHECK_WEB_SITE_KEY');
const String _webDebugAppCheckToken =
    String.fromEnvironment('FIREBASE_APP_CHECK_WEB_DEBUG_TOKEN');

/// Active Firebase App Check avant tout accès aux services Firebase.
Future<void> activateFirebaseAppCheck() async {
  await FirebaseAppCheck.instance.activate(
    providerWeb: _buildWebProvider(),
    providerAndroid: _buildAndroidProvider(),
    providerApple: _buildAppleProvider(),
  );

  await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
}

dynamic _buildWebProvider() {
  if (!kIsWeb) {
    return null;
  }

  if (kDebugMode) {
    final debugToken = _webDebugAppCheckToken.trim();
    if (debugToken.isEmpty) {
      return WebDebugProvider();
    }
    return WebDebugProvider(debugToken: debugToken);
  }

  final siteKey = _webAppCheckSiteKey.trim();
  if (siteKey.isEmpty) {
    throw StateError(
      'FIREBASE_APP_CHECK_WEB_SITE_KEY manquant pour le build web.',
    );
  }

  return ReCaptchaV3Provider(siteKey);
}

AndroidAppCheckProvider _buildAndroidProvider() {
  if (kDebugMode) {
    return const AndroidDebugProvider();
  }

  return const AndroidPlayIntegrityProvider();
}

AppleAppCheckProvider _buildAppleProvider() {
  if (kDebugMode) {
    return const AppleDebugProvider();
  }

  return const AppleAppAttestWithDeviceCheckFallbackProvider();
}
