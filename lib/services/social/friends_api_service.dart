import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../multiplayer/socket_connection_handler.dart';
import '../auth/auth_service.dart';
import '../network/network_probe_service.dart';
import '../network/secure_api_headers.dart';
import '../logging/error_reporting_service.dart';

class FriendInfo {
  final String userId;
  final String username;
  final String displayName;
  final String addedAt;
  final bool isOnline;

  const FriendInfo({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.addedAt,
    required this.isOnline,
  });

  factory FriendInfo.fromJson(Map<String, dynamic> json) {
    return FriendInfo(
      userId: json['userId']?.toString() ?? '',
      username: json['username'] as String,
      displayName: json['displayName'] as String,
      addedAt: json['addedAt']?.toString() ?? '',
      isOnline: json['isOnline'] as bool? ?? false,
    );
  }
}

class FriendRequestInfo {
  final String requestId;
  final String userId;
  final String username;
  final String displayName;
  final String requestedAt;

  const FriendRequestInfo({
    required this.requestId,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.requestedAt,
  });

  factory FriendRequestInfo.fromJson(Map<String, dynamic> json) {
    return FriendRequestInfo(
      requestId: json['requestId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      username: json['username'] as String,
      displayName: json['displayName'] as String,
      requestedAt: json['requestedAt']?.toString() ?? '',
    );
  }
}

class BlockedUserInfo {
  final String userId;
  final String username;
  final String displayName;

  const BlockedUserInfo({
    required this.userId,
    required this.username,
    required this.displayName,
  });

  factory BlockedUserInfo.fromJson(Map<String, dynamic> json) {
    return BlockedUserInfo(
      userId: json['userId']?.toString() ?? '',
      username: json['username'] as String,
      displayName: json['displayName'] as String,
    );
  }
}

class UserLookupInfo {
  final String userId;
  final String username;
  final String displayName;

  const UserLookupInfo({
    required this.userId,
    required this.username,
    required this.displayName,
  });

  factory UserLookupInfo.fromJson(Map<String, dynamic> json) {
    return UserLookupInfo(
      userId: json['id']?.toString() ?? '',
      username: json['username'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
    );
  }
}

/// Résultat typé pour les actions amis (accept, reject, remove, block, etc.)
/// Permet aux appelants de distinguer succès / erreur réseau / erreur serveur.
class FriendsActionResult {
  final bool success;
  final String? error;

  const FriendsActionResult({required this.success, this.error});

  const FriendsActionResult.ok()
      : success = true,
        error = null;

  const FriendsActionResult.networkError()
      : success = false,
        error = 'Serveur indisponible';

  const FriendsActionResult.failure([String? message])
      : success = false,
        error = message ?? 'Erreur inconnue';
}

class FriendsApiService {
  static const String _baseUrl = SocketConnectionHandler.serverUrl;
  final AuthService _authService;
  DateTime? _lastOfflineLogAt;
  DateTime? _lastResponseIssueLogAt;

  // Cache du probe réseau : valide 5 secondes pour éviter N sondes successives
  static DateTime? _lastProbeAt;
  static bool _lastProbeResult = true;
  static const _probeCacheDuration = Duration(seconds: 5);

  // Prefetch : lancé dès le login, consommé par le lobby
  static Future<
      ({
        List<FriendInfo> friends,
        List<FriendRequestInfo> incoming,
        List<FriendRequestInfo> outgoing
      })>? _prefetchedSummary;

  /// Lance le prefetch des données sociales en arrière-plan.
  /// Appeler dès que le login réussit.
  static void prefetchSummary(AuthService authService) {
    _prefetchedSummary = FriendsApiService(authService).getSummary();
  }

  /// Consomme le prefetch s'il existe, sinon fait un appel normal.
  Future<
      ({
        List<FriendInfo> friends,
        List<FriendRequestInfo> incoming,
        List<FriendRequestInfo> outgoing
      })> getSummaryOrPrefetched() async {
    final prefetched = _prefetchedSummary;
    if (prefetched != null) {
      _prefetchedSummary = null;
      return prefetched;
    }
    return getSummary();
  }

  /// Invalide le prefetch (ex: après inscription, pas besoin de fetch).
  static void clearPrefetch() {
    _prefetchedSummary = null;
  }

  FriendsApiService(this._authService);

  Future<Map<String, String>> _headers() async {
    final token = await _authService.getStoredToken();
    return SecureApiHeaders.json(bearerToken: token);
  }

  Future<bool> _canReachBackend() async {
    final now = DateTime.now();
    // Retourner le résultat mis en cache si récent
    if (_lastProbeAt != null &&
        now.difference(_lastProbeAt!) < _probeCacheDuration) {
      return _lastProbeResult;
    }
    final reachable = await NetworkProbeService.canReachBackend(
      timeout: const Duration(milliseconds: 900),
    );
    _lastProbeAt = now;
    _lastProbeResult = reachable;
    if (!reachable && kDebugMode) {
      if (_lastOfflineLogAt == null ||
          now.difference(_lastOfflineLogAt!) >= const Duration(seconds: 5)) {
        _lastOfflineLogAt = now;
        debugPrint(
          'Friends API skipped: backend unreachable (network/CORS).',
        );
      }
    }
    return reachable;
  }

  void _debugResponseIssue(String message) {
    if (!kDebugMode) return;
    final now = DateTime.now();
    if (_lastResponseIssueLogAt == null ||
        now.difference(_lastResponseIssueLogAt!) >=
            const Duration(seconds: 4)) {
      _lastResponseIssueLogAt = now;
      debugPrint(message);
    }
  }

  Map<String, dynamic>? _decodeJsonResponse(
    http.Response response, {
    required String endpoint,
  }) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _debugResponseIssue(
        '$endpoint: status ${response.statusCode} (body non exploitable)',
      );
      return null;
    }

    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    if (!contentType.contains('application/json')) {
      _debugResponseIssue(
        '$endpoint: réponse non-JSON ($contentType), probablement HTML/proxy.',
      );
      return null;
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      _debugResponseIssue('$endpoint: payload JSON inattendu.');
      return null;
    } catch (e) {
      _debugResponseIssue('$endpoint: JSON invalide ($e)');
      return null;
    }
  }

  /// Appel unique : amis + demandes entrantes/sortantes en un seul round-trip.
  Future<
      ({
        List<FriendInfo> friends,
        List<FriendRequestInfo> incoming,
        List<FriendRequestInfo> outgoing
      })> getSummary() async {
    const empty = (
      friends: <FriendInfo>[],
      incoming: <FriendRequestInfo>[],
      outgoing: <FriendRequestInfo>[]
    );
    if (!await _canReachBackend()) return empty;
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/api/friends/summary'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 10));

      final data = _decodeJsonResponse(response, endpoint: 'getSummary');
      if (data == null || data['success'] != true) return empty;

      final friends =
          (data['friends'] as List).map((f) => FriendInfo.fromJson(f)).toList();
      final incoming = (data['incoming'] as List)
          .map((r) => FriendRequestInfo.fromJson(r))
          .toList();
      final outgoing = (data['outgoing'] as List)
          .map((r) => FriendRequestInfo.fromJson(r))
          .toList();
      return (friends: friends, incoming: incoming, outgoing: outgoing);
    } catch (e) {
      if (kDebugMode) debugPrint('getSummary error: $e');
      return empty;
    }
  }

  Future<List<FriendInfo>> getFriends() async {
    if (!await _canReachBackend()) {
      return [];
    }
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/api/friends'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 10));

      final data = _decodeJsonResponse(response, endpoint: 'getFriends');
      if (data == null) return [];
      if (data['success'] == true) {
        return (data['friends'] as List)
            .map((f) => FriendInfo.fromJson(f))
            .toList();
      }
      return [];
    } catch (e) {
      if (kDebugMode) debugPrint('getFriends error: $e');
      return [];
    }
  }

  Future<({List<FriendRequestInfo> incoming, List<FriendRequestInfo> outgoing})>
      getRequests() async {
    if (!await _canReachBackend()) {
      return (incoming: <FriendRequestInfo>[], outgoing: <FriendRequestInfo>[]);
    }
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/api/friends/requests'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 10));

      final data = _decodeJsonResponse(response, endpoint: 'getRequests');
      if (data == null) {
        return (
          incoming: <FriendRequestInfo>[],
          outgoing: <FriendRequestInfo>[]
        );
      }
      if (data['success'] == true) {
        final incoming = (data['incoming'] as List)
            .map((r) => FriendRequestInfo.fromJson(r))
            .toList();
        final outgoing = (data['outgoing'] as List)
            .map((r) => FriendRequestInfo.fromJson(r))
            .toList();
        return (incoming: incoming, outgoing: outgoing);
      }
      return (incoming: <FriendRequestInfo>[], outgoing: <FriendRequestInfo>[]);
    } catch (e) {
      if (kDebugMode) debugPrint('getRequests error: $e');
      return (incoming: <FriendRequestInfo>[], outgoing: <FriendRequestInfo>[]);
    }
  }

  Future<({bool success, String? error})> sendRequest(String username) async {
    if (!await _canReachBackend()) {
      return (success: false, error: 'Serveur indisponible');
    }
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/friends/request'),
            headers: await _headers(),
            body: jsonEncode({'username': username}),
          )
          .timeout(const Duration(seconds: 10));

      final data = _decodeJsonResponse(response, endpoint: 'sendRequest');
      if (data == null) {
        return (success: false, error: 'Réponse serveur invalide');
      }
      return (
        success: data['success'] == true,
        error: data['error'] as String?
      );
    } catch (e) {
      return (success: false, error: 'Erreur reseau');
    }
  }

  Future<({bool exists, UserLookupInfo? user, String? error})>
      lookupUserByUsername(String username) async {
    if (!await _canReachBackend()) {
      return (exists: false, user: null, error: 'Serveur indisponible');
    }
    final normalized = username.trim();
    if (normalized.isEmpty) {
      return (exists: false, user: null, error: 'Nom d utilisateur requis');
    }
    try {
      final uri = Uri.parse('$_baseUrl/api/friends/lookup')
          .replace(queryParameters: {'username': normalized});
      final response = await http
          .get(
            uri,
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 404) {
        return (exists: false, user: null, error: 'Utilisateur introuvable');
      }

      final data =
          _decodeJsonResponse(response, endpoint: 'lookupUserByUsername');
      if (data == null) {
        return (exists: false, user: null, error: 'Réponse serveur invalide');
      }

      if (data['success'] == true &&
          data['exists'] == true &&
          data['user'] is Map) {
        return (
          exists: true,
          user: UserLookupInfo.fromJson(
            Map<String, dynamic>.from(data['user'] as Map),
          ),
          error: null,
        );
      }

      return (
        exists: false,
        user: null,
        error: data['error']?.toString() ?? 'Utilisateur introuvable',
      );
    } catch (_) {
      return (exists: false, user: null, error: 'Erreur reseau');
    }
  }

  Future<FriendsActionResult> acceptRequest(String requestId) async {
    final headers = await _headers();
    return _performAction(
      endpoint: 'acceptRequest',
      request: () => http
          .post(
            Uri.parse('$_baseUrl/api/friends/accept'),
            headers: headers,
            body: jsonEncode({'requestId': requestId}),
          )
          .timeout(const Duration(seconds: 10)),
    );
  }

  Future<FriendsActionResult> rejectRequest(String requestId) async {
    final headers = await _headers();
    return _performAction(
      endpoint: 'rejectRequest',
      request: () => http
          .post(
            Uri.parse('$_baseUrl/api/friends/reject'),
            headers: headers,
            body: jsonEncode({'requestId': requestId}),
          )
          .timeout(const Duration(seconds: 10)),
    );
  }

  Future<FriendsActionResult> cancelRequest(String requestId) async {
    final headers = await _headers();
    return _performAction(
      endpoint: 'cancelRequest',
      request: () => http
          .post(
            Uri.parse('$_baseUrl/api/friends/cancel'),
            headers: headers,
            body: jsonEncode({'requestId': requestId}),
          )
          .timeout(const Duration(seconds: 10)),
    );
  }

  Future<FriendsActionResult> removeFriend(String userId) async {
    final headers = await _headers();
    return _performAction(
      endpoint: 'removeFriend',
      request: () => http
          .delete(
            Uri.parse('$_baseUrl/api/friends/$userId'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10)),
    );
  }

  Future<FriendsActionResult> blockUser(String userId) async {
    final headers = await _headers();
    return _performAction(
      endpoint: 'blockUser',
      request: () => http
          .post(
            Uri.parse('$_baseUrl/api/friends/block'),
            headers: headers,
            body: jsonEncode({'userId': userId}),
          )
          .timeout(const Duration(seconds: 10)),
    );
  }

  Future<FriendsActionResult> unblockUser(String userId) async {
    final headers = await _headers();
    return _performAction(
      endpoint: 'unblockUser',
      request: () => http
          .delete(
            Uri.parse('$_baseUrl/api/friends/block/$userId'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10)),
    );
  }

  /// Helper centralisé pour les actions amis qui retournaient un simple bool.
  /// Gère le probe réseau, le décodage et le reporting d'erreurs.
  Future<FriendsActionResult> _performAction({
    required String endpoint,
    required Future<http.Response> Function() request,
  }) async {
    if (!await _canReachBackend()) {
      return const FriendsActionResult.networkError();
    }
    try {
      final response = await request();
      final data = _decodeJsonResponse(response, endpoint: endpoint);
      if (data == null) {
        return const FriendsActionResult.failure('Réponse serveur invalide');
      }
      if (data['success'] == true) {
        return const FriendsActionResult.ok();
      }
      return FriendsActionResult.failure(
        data['error']?.toString() ?? 'Échec de l\'opération',
      );
    } catch (e, stackTrace) {
      ErrorReportingService().reportNetwork(
        e,
        stackTrace: stackTrace,
        endpoint: endpoint,
      );
      return const FriendsActionResult.failure('Erreur réseau');
    }
  }

  Future<List<BlockedUserInfo>> getBlockedUsers() async {
    if (!await _canReachBackend()) {
      return [];
    }
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/api/friends/blocked'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 10));

      final data = _decodeJsonResponse(response, endpoint: 'getBlockedUsers');
      if (data == null) return [];
      if (data['success'] == true) {
        return (data['blocked'] as List)
            .map((b) => BlockedUserInfo.fromJson(b))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<({bool success, String? error})> inviteToRoom(
    String roomCode,
    String friendUserId,
  ) async {
    if (!await _canReachBackend()) {
      return (success: false, error: 'Serveur indisponible');
    }
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/friends/invite'),
            headers: await _headers(),
            body: jsonEncode(
                {'roomCode': roomCode, 'friendUserId': friendUserId}),
          )
          .timeout(const Duration(seconds: 10));

      final decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic>
          ? decoded
          : (decoded is Map
              ? Map<String, dynamic>.from(decoded)
              : <String, dynamic>{});
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return (
          success: false,
          error: data['error']?.toString() ?? 'Erreur lors de l\'envoi',
        );
      }
      return (
        success: data['success'] == true,
        error: data['error']?.toString(),
      );
    } catch (_) {
      return (success: false, error: 'Erreur reseau');
    }
  }
}
