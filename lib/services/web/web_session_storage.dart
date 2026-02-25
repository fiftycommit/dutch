import 'package:web/web.dart' as web;

/// Persists room session data in sessionStorage for web reload recovery.
class WebSessionStorage {
  static const _roomKey = 'dutch_room_code';
  static const _routeKey = 'dutch_route';

  static void saveSession(String roomCode) {
    try {
      web.window.sessionStorage.setItem(_roomKey, roomCode);
    } catch (_) {}
  }

  static void saveRoute(String? route) {
    try {
      if (route != null) {
        web.window.sessionStorage.setItem(_routeKey, route);
      } else {
        web.window.sessionStorage.removeItem(_routeKey);
      }
    } catch (_) {}
  }

  static String? getRoomCode() {
    try {
      return web.window.sessionStorage.getItem(_roomKey);
    } catch (_) {
      return null;
    }
  }

  static String? getRoute() {
    try {
      return web.window.sessionStorage.getItem(_routeKey);
    } catch (_) {
      return null;
    }
  }

  static void clearSession() {
    try {
      web.window.sessionStorage.removeItem(_roomKey);
      web.window.sessionStorage.removeItem(_routeKey);
    } catch (_) {}
  }
}
