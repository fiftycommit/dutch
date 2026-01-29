import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dutch_game/services/multiplayer_service.dart';

// Mock subclass to simulate network responses
class MockMultiplayerService extends MultiplayerService {
  bool _isConnectedMock = false;
  List<Map<String, dynamic>>? _activeRoomsMock;

  void setConnected(bool value) {
    _isConnectedMock = value;
  }

  void setActiveRoomsResponse(List<Map<String, dynamic>>? rooms) {
    _activeRoomsMock = rooms;
  }

  @override
  bool get isConnected => _isConnectedMock;

  @override
  Future<List<Map<String, dynamic>>?> checkActiveRooms(
      List<String> roomCodes) async {
    return _activeRoomsMock;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MultiplayerService Persistence', () {
    late MockMultiplayerService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = MockMultiplayerService();
    });

    test(
        'cleanupInactiveRooms DOES NOT delete rooms if checkActiveRooms returns null (offline)',
        () async {
      // 1. Setup saved rooms
      final roomCode = 'ROOM1';
      // Manual save simulation
      final prefs = await SharedPreferences.getInstance();
      final savedRoom = SavedRoom(
        roomCode: roomCode,
        isHost: false,
        joinedAt: DateTime.now(),
      );
      await prefs.setStringList(
          'my_multiplayer_rooms', [json.encode(savedRoom.toJson())]);

      // 2. Simulate Offline / Error (returns null)
      service.setConnected(false);
      service.setActiveRoomsResponse(null);

      // 3. Run cleanup
      await service.cleanupInactiveRooms();

      // 4. Verify room is STILL there
      final rooms = await service.getMyRooms();
      expect(rooms.length, 1);
      expect(rooms.first.roomCode, roomCode);
    });

    test(
        'cleanupInactiveRooms DELETES rooms if checkActiveRooms returns empty list (online but room gone)',
        () async {
      // 1. Setup saved rooms
      final roomCode = 'ROOM1';
      final prefs = await SharedPreferences.getInstance();
      final savedRoom = SavedRoom(
        roomCode: roomCode,
        isHost: false,
        joinedAt: DateTime.now(),
      );
      await prefs.setStringList(
          'my_multiplayer_rooms', [json.encode(savedRoom.toJson())]);

      // 2. Simulate Online but room is actively missing
      service.setConnected(true);
      service.setActiveRoomsResponse([]); // Empty list = no active rooms

      // 3. Run cleanup
      await service.cleanupInactiveRooms();

      // 4. Verify room is GONE
      final rooms = await service.getMyRooms();
      expect(rooms.isEmpty, isTrue);
    });

    test('cleanupInactiveRooms KEEPS rooms that are returned as active',
        () async {
      // 1. Setup saved rooms
      final roomCode = 'ROOM1';
      final prefs = await SharedPreferences.getInstance();
      final savedRoom = SavedRoom(
        roomCode: roomCode,
        isHost: false,
        joinedAt: DateTime.now(),
      );
      await prefs.setStringList(
          'my_multiplayer_rooms', [json.encode(savedRoom.toJson())]);

      // 2. Simulate Online and room is active
      service.setConnected(true);
      service.setActiveRoomsResponse([
        {'roomCode': roomCode}
      ]);

      // 3. Run cleanup
      await service.cleanupInactiveRooms();

      // 4. Verify room is STILL there
      final rooms = await service.getMyRooms();
      expect(rooms.length, 1);
      expect(rooms.first.roomCode, roomCode);
    });
  });
}
