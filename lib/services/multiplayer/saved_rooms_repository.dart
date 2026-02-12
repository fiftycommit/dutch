import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/auth_service.dart';
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

/// Repository pour la persistance des rooms sauvegardées
/// Sync avec le serveur quand l'utilisateur est connecté, fallback local sinon
class SavedRoomsRepository {
  static const String _myRoomsKey = 'my_multiplayer_rooms';
  static const int _maxSavedRooms = 5;
  static const String _baseUrl = SocketConnectionHandler.serverUrl;

  AuthService? _authService;

  void setAuthService(AuthService? authService) {
    _authService = authService;
  }

  Future<Map<String, String>?> _authHeaders() async {
    final token = await _authService?.getStoredToken();
    if (token == null) return null;
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<List<SavedRoom>> getMyRooms() async {
    // Essayer le serveur d'abord
    final headers = await _authHeaders();
    if (headers != null) {
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/api/rooms/mine'),
          headers: headers,
        ).timeout(const Duration(seconds: 10));

        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return (data['rooms'] as List).map((r) => SavedRoom(
            roomCode: r['roomCode'] as String,
            isHost: r['isHost'] as bool,
            joinedAt: DateTime.tryParse(r['joinedAt'] as String? ?? '') ?? DateTime.now(),
          )).toList();
        }
      } catch (e) {
        if (kDebugMode) debugPrint('getMyRooms server error: $e');
      }
    }

    // Fallback local
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_myRoomsKey) ?? [];
    return jsonList
        .map((jsonStr) => SavedRoom.fromJson(json.decode(jsonStr)))
        .toList();
  }

  Future<void> saveRoom(String roomCode, {required bool isHost}) async {
    // Sauvegarder côté serveur
    final headers = await _authHeaders();
    if (headers != null) {
      try {
        await http.post(
          Uri.parse('$_baseUrl/api/rooms/save'),
          headers: headers,
          body: jsonEncode({'roomCode': roomCode, 'isHost': isHost}),
        ).timeout(const Duration(seconds: 10));
      } catch (e) {
        if (kDebugMode) debugPrint('saveRoom server error: $e');
      }
    }

    // Aussi sauvegarder localement
    final prefs = await SharedPreferences.getInstance();
    final rooms = await _getLocalRooms(prefs);

    rooms.removeWhere((r) => r.roomCode == roomCode);
    rooms.insert(
        0,
        SavedRoom(
          roomCode: roomCode,
          isHost: isHost,
          joinedAt: DateTime.now(),
        ));

    if (rooms.length > _maxSavedRooms) {
      rooms.removeLast();
    }

    final jsonList = rooms.map((r) => json.encode(r.toJson())).toList();
    await prefs.setStringList(_myRoomsKey, jsonList);
  }

  Future<void> removeRoom(String roomCode) async {
    // Supprimer côté serveur
    final headers = await _authHeaders();
    if (headers != null) {
      try {
        await http.delete(
          Uri.parse('$_baseUrl/api/rooms/$roomCode'),
          headers: headers,
        ).timeout(const Duration(seconds: 10));
      } catch (e) {
        if (kDebugMode) debugPrint('removeRoom server error: $e');
      }
    }

    // Supprimer localement
    final prefs = await SharedPreferences.getInstance();
    final rooms = await _getLocalRooms(prefs);
    rooms.removeWhere((r) => r.roomCode == roomCode);
    final jsonList = rooms.map((r) => json.encode(r.toJson())).toList();
    await prefs.setStringList(_myRoomsKey, jsonList);
  }

  Future<void> cleanupInactiveRooms(Set<String> activeCodes) async {
    final rooms = await getMyRooms();

    for (final room in rooms) {
      if (!activeCodes.contains(room.roomCode)) {
        await removeRoom(room.roomCode);
      }
    }
  }

  Future<List<SavedRoom>> _getLocalRooms(SharedPreferences prefs) async {
    final jsonList = prefs.getStringList(_myRoomsKey) ?? [];
    return jsonList
        .map((jsonStr) => SavedRoom.fromJson(json.decode(jsonStr)))
        .toList();
  }
}
