import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../multiplayer/socket_connection_handler.dart';
import '../auth/auth_service.dart';

class FriendInfo {
  final int userId;
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
      userId: json['userId'] as int,
      username: json['username'] as String,
      displayName: json['displayName'] as String,
      addedAt: json['addedAt'] as String,
      isOnline: json['isOnline'] as bool? ?? false,
    );
  }
}

class FriendRequestInfo {
  final int requestId;
  final int userId;
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
      requestId: json['requestId'] as int,
      userId: json['userId'] as int,
      username: json['username'] as String,
      displayName: json['displayName'] as String,
      requestedAt: json['requestedAt'] as String,
    );
  }
}

class BlockedUserInfo {
  final int userId;
  final String username;
  final String displayName;

  const BlockedUserInfo({
    required this.userId,
    required this.username,
    required this.displayName,
  });

  factory BlockedUserInfo.fromJson(Map<String, dynamic> json) {
    return BlockedUserInfo(
      userId: json['userId'] as int,
      username: json['username'] as String,
      displayName: json['displayName'] as String,
    );
  }
}

class FriendsApiService {
  static const String _baseUrl = SocketConnectionHandler.serverUrl;
  final AuthService _authService;

  FriendsApiService(this._authService);

  Future<Map<String, String>> _headers() async {
    final token = await _authService.getStoredToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<List<FriendInfo>> getFriends() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/friends'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
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

  Future<({List<FriendRequestInfo> incoming, List<FriendRequestInfo> outgoing})> getRequests() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/friends/requests'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
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
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/friends/request'),
        headers: await _headers(),
        body: jsonEncode({'username': username}),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      return (success: data['success'] == true, error: data['error'] as String?);
    } catch (e) {
      return (success: false, error: 'Erreur reseau');
    }
  }

  Future<bool> acceptRequest(int requestId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/friends/accept'),
        headers: await _headers(),
        body: jsonEncode({'requestId': requestId}),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> rejectRequest(int requestId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/friends/reject'),
        headers: await _headers(),
        body: jsonEncode({'requestId': requestId}),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> cancelRequest(int requestId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/friends/cancel'),
        headers: await _headers(),
        body: jsonEncode({'requestId': requestId}),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> removeFriend(int userId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/api/friends/$userId'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> blockUser(int userId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/friends/block'),
        headers: await _headers(),
        body: jsonEncode({'userId': userId}),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> unblockUser(int userId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/api/friends/block/$userId'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<List<BlockedUserInfo>> getBlockedUsers() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/friends/blocked'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
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

  Future<bool> inviteToRoom(String roomCode, int friendUserId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/friends/invite'),
        headers: await _headers(),
        body: jsonEncode({'roomCode': roomCode, 'friendUserId': friendUserId}),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      return data['success'] == true;
    } catch (e) {
      return false;
    }
  }
}
