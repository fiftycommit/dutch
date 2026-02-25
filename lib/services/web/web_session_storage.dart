import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Persists room session data in sessionStorage for web reload recovery.
class WebSessionStorage {
  static const _roomKey = 'dutch_room_code';
  static const _routeKey = 'dutch_route';

  static JSObject get _storage =>
      globalContext.getProperty('sessionStorage'.toJS) as JSObject;

  static void saveSession(String roomCode) {
    try {
      _storage.callMethod('setItem'.toJS, _roomKey.toJS, roomCode.toJS);
    } catch (_) {}
  }

  static void saveRoute(String? route) {
    try {
      if (route != null) {
        _storage.callMethod('setItem'.toJS, _routeKey.toJS, route.toJS);
      } else {
        _storage.callMethod('removeItem'.toJS, _routeKey.toJS);
      }
    } catch (_) {}
  }

  static String? getRoomCode() {
    try {
      final val =
          _storage.callMethod('getItem'.toJS, _roomKey.toJS) as JSString?;
      return val?.toDart;
    } catch (_) {
      return null;
    }
  }

  static String? getRoute() {
    try {
      final val =
          _storage.callMethod('getItem'.toJS, _routeKey.toJS) as JSString?;
      return val?.toDart;
    } catch (_) {
      return null;
    }
  }

  static void clearSession() {
    try {
      _storage.callMethod('removeItem'.toJS, _roomKey.toJS);
      _storage.callMethod('removeItem'.toJS, _routeKey.toJS);
    } catch (_) {}
  }
}
