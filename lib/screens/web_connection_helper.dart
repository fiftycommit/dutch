import 'dart:js_interop';

/// Helper to detect low-bandwidth connections on web.
class WebConnectionHelper {
  static bool isLowBandwidth() {
    try {
      return _isLowBandwidth();
    } catch (_) {
      return false;
    }
  }
}

@JS('isLowBandwidth')
external bool _isLowBandwidth();
