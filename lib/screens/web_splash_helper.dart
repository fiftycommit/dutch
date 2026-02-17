import 'dart:js_interop';

/// Helper to communicate with HTML splash screen on web
class WebSplashHelper {
  static void updateProgress(int progress, String status) {
    try {
      _callUpdateSplash(progress, status);
    } catch (e) {
      // Ignore errors
    }
  }

  static void flutterReady() {
    try {
      _callFlutterReady();
    } catch (e) {
      // Ignore errors
    }
  }

  static void hideSplash() {
    try {
      _callHideSplash();
    } catch (e) {
      // Ignore errors
    }
  }

  /// Change le background CSS des safe areas (bandes iOS paysage)
  static void setSafeAreaBackground(String cssValue) {
    try {
      _callSetSafeBg(cssValue);
    } catch (e) {
      // Ignore errors
    }
  }
}

@JS('updateSplash')
external void _callUpdateSplash(int progress, String status);

@JS('flutterReady')
external void _callFlutterReady();

@JS('hideSplash')
external void _callHideSplash();

@JS('setSafeBg')
external void _callSetSafeBg(String value);
