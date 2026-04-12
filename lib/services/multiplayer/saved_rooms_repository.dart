import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../network/secure_api_headers.dart';
import 'socket_connection_handler.dart';

/// Informations sur une room sauvegardée
class SavedRoom {
  final String roomCode;
  final bool isHost;
  final DateTime joinedAt;

  SavedRoom({
    required this.roomCode,
    required this.isHost,
    required this.joinedAt,
  });

  Map<String, dynamic> toJson() => {
        'roomCode': roomCode,
        'isHost': isHost,
        'joinedAt': joinedAt.toIso8601String(),
      };

  factory SavedRoom.fromJson(Map<String, dynamic> json) => SavedRoom(
        roomCode: json['roomCode'] as String,
        isHost: json['isHost'] as bool,
        joinedAt: DateTime.parse(json['joinedAt'] as String),
      );
}

/// Repository des salons actifs côté compte utilisateur.
class SavedRoomsRepository {
  static const String _baseUrl = SocketConnectionHandler.serverUrl;

  String? _authToken;

  void setAuthToken(String? token) {
    _authToken = token;
  }

  Future<Map<String, String>?> _authHeaders() async {
    final token = _authToken;
    if (token == null) return null;
    return SecureApiHeaders.json(bearerToken: token);
  }

  Future<List<SavedRoom>> getMyRooms() async {
    final headers = await _authHeaders();
    if (headers == null) {
      return <SavedRoom>[];
    }

    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/api/rooms/mine'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body);
      if (response.statusCode != 200 || data['success'] != true) {
        return <SavedRoom>[];
      }
      return (data['rooms'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .map((r) => SavedRoom(
                roomCode: (r['roomCode'] as String? ?? '').toUpperCase(),
                isHost: r['isHost'] == true,
                joinedAt: DateTime.tryParse(r['joinedAt'] as String? ?? '') ??
                    DateTime.now(),
              ))
          .where((room) => room.roomCode.isNotEmpty)
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('getMyRooms server error: $e');
      return <SavedRoom>[];
    }
  }

  Future<void> removeRoom(String roomCode) async {
    final headers = await _authHeaders();
    if (headers == null) {
      return;
    }

    try {
      await http
          .delete(
            Uri.parse('$_baseUrl/api/rooms/${roomCode.toUpperCase()}'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      if (kDebugMode) debugPrint('removeRoom server error: $e');
    }
  }
}
