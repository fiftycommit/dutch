import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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
/// Principe GRASP: Information Expert - Gère la persistance des rooms
class SavedRoomsRepository {
  static const String _myRoomsKey = 'my_multiplayer_rooms';
  static const int _maxSavedRooms = 5;

  Future<List<SavedRoom>> getMyRooms() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_myRoomsKey) ?? [];
    return jsonList
        .map((jsonStr) => SavedRoom.fromJson(json.decode(jsonStr)))
        .toList();
  }

  Future<void> saveRoom(String roomCode, {required bool isHost}) async {
    final prefs = await SharedPreferences.getInstance();
    final rooms = await getMyRooms();

    // Mettre à jour si existe déjà, sinon ajouter
    rooms.removeWhere((r) => r.roomCode == roomCode);
    rooms.insert(
        0,
        SavedRoom(
          roomCode: roomCode,
          isHost: isHost,
          joinedAt: DateTime.now(),
        ));

    // Garder seulement les N dernières
    if (rooms.length > _maxSavedRooms) {
      rooms.removeLast();
    }

    final jsonList = rooms.map((r) => json.encode(r.toJson())).toList();
    await prefs.setStringList(_myRoomsKey, jsonList);
  }

  Future<void> removeRoom(String roomCode) async {
    final prefs = await SharedPreferences.getInstance();
    final rooms = await getMyRooms();

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
}
