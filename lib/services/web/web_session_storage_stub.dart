/// Stub for non-web platforms — all operations are no-ops.
class WebSessionStorage {
  static void saveSession(String roomCode) {}
  static void saveRoute(String? route) {}
  static String? getRoomCode() => null;
  static String? getRoute() => null;
  static void clearSession() {}
}
