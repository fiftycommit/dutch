import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/services/multiplayer_service.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockMultiplayerService extends MultiplayerService {
  List<Map<String, dynamic>>? mockPublicRooms;
  bool shouldFailGetPublicRooms = false;
  String? lastCreatedRoomCode;
  GameSettings? lastCreatedSettings;

  @override
  Future<List<Map<String, dynamic>>?> getPublicRooms() async {
    if (shouldFailGetPublicRooms) {
      throw Exception('Failed to get public rooms');
    }
    return mockPublicRooms;
  }

  @override
  Future<String?> createRoom({
    required GameSettings settings,
    required String playerName,
  }) async {
    lastCreatedSettings = settings;
    lastCreatedRoomCode = 'TEST123';
    return lastCreatedRoomCode;
  }

  @override
  Future<Map<String, dynamic>?> joinRoom({
    required String roomCode,
    required String playerName,
  }) async {
    return {
      'code': roomCode,
      'players': [],
    };
  }
}

void main() {
  group('MultiplayerGameProvider - Public Rooms', () {
    late MultiplayerGameProvider provider;
    late MockMultiplayerService mockService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      mockService = MockMultiplayerService();
      provider = MultiplayerGameProvider(multiplayerService: mockService);
    });

    test('should get public rooms successfully', () async {
      mockService.mockPublicRooms = [
        {
          'code': 'ABC123',
          'players': 2,
          'maxPlayers': 4,
          'gameMode': 'quick',
          'host': 'Player1',
        },
        {
          'code': 'XYZ789',
          'players': 3,
          'maxPlayers': 4,
          'gameMode': 'quick',
          'host': 'Player2',
        },
      ];

      final rooms = await provider.getPublicRooms();

      expect(rooms, isNotNull);
      expect(rooms!.length, 2);
      expect(rooms[0]['code'], 'ABC123');
      expect(rooms[1]['code'], 'XYZ789');
    });

    test('should return null when getting public rooms fails', () async {
      mockService.shouldFailGetPublicRooms = true;

      final rooms = await provider.getPublicRooms();

      expect(rooms, isNull);
    });

    test('should return empty list when no public rooms available', () async {
      mockService.mockPublicRooms = [];

      final rooms = await provider.getPublicRooms();

      expect(rooms, isNotNull);
      expect(rooms!.length, 0);
    });

    test('searchAndJoinPublicRoom should join existing room when available', () async {
      mockService.mockPublicRooms = [
        {
          'code': 'ABC123',
          'players': 2,
          'maxPlayers': 4,
          'gameMode': 'quick',
          'host': 'Player1',
        },
      ];

      await provider.searchAndJoinPublicRoom();

      // Vérifier qu'on n'a pas créé de nouvelle room
      expect(mockService.lastCreatedSettings, isNull);
    });

    test('createPublicRoom should create new room', () async {
      await provider.createPublicRoom(playerName: 'TestPlayer');

      // Vérifier qu'une nouvelle room a été créée
      expect(mockService.lastCreatedSettings, isNotNull);
      expect(mockService.lastCreatedSettings!.isPublic, true);
      expect(mockService.lastCreatedSettings!.numberOfPlayers, 4);
    });

    test('searchAndJoinPublicRoom should throw when no rooms available', () async {
      mockService.mockPublicRooms = [];

      expect(
        () => provider.searchAndJoinPublicRoom(),
        throwsException,
      );
    });
  });

  group('GameSettings - Public Room Parameters', () {
    test('should have default values for public room parameters', () {
      final settings = GameSettings();

      expect(settings.isPublic, false);
      expect(settings.numberOfPlayers, 4);
    });

    test('should create public room settings', () {
      final settings = GameSettings(
        isPublic: true,
        numberOfPlayers: 3,
      );

      expect(settings.isPublic, true);
      expect(settings.numberOfPlayers, 3);
    });

    test('should serialize and deserialize public room parameters', () {
      final settings = GameSettings(
        isPublic: true,
        numberOfPlayers: 2,
        gameMode: GameMode.quick,
      );

      final json = settings.toJson();
      final restored = GameSettings.fromJson(json);

      expect(restored.isPublic, true);
      expect(restored.numberOfPlayers, 2);
      expect(restored.gameMode, GameMode.quick);
    });

    test('should copy with public room parameters', () {
      final settings = GameSettings();
      final updated = settings.copyWith(
        isPublic: true,
        numberOfPlayers: 3,
      );

      expect(updated.isPublic, true);
      expect(updated.numberOfPlayers, 3);
      expect(settings.isPublic, false); // Original unchanged
    });
  });
}
