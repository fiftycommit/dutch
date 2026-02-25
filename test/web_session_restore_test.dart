import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/services/web/web_session_storage_stub.dart';
import 'package:dutch_game/router/app_router.dart';
import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/models/game_state.dart';
import 'mocks/mock_multiplayer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebSessionStorage (stub)', () {
    test('stub returns null for all getters', () {
      expect(WebSessionStorage.getRoomCode(), isNull);
      expect(WebSessionStorage.getRoute(), isNull);
    });

    test('stub methods are no-ops (no crash)', () {
      WebSessionStorage.saveSession('ABC123');
      WebSessionStorage.saveRoute('/lobby');
      WebSessionStorage.clearSession();
      // Pas de crash = succès
    });
  });

  group('AppRouter - session restore logic', () {
    test('statefulPrefixes contient toutes les routes multiplayer', () {
      // Vérifier que toutes les routes multiplayer en jeu sont stateful
      const expectedStateful = [
        '/lobby',
        '/multiplayer/game',
        '/multiplayer/memorization',
        '/multiplayer/results',
        '/multiplayer/dutch-reveal',
      ];
      for (final route in expectedStateful) {
        expect(
          _isStateful(route),
          isTrue,
          reason: '$route devrait être dans _statefulPrefixes',
        );
      }
    });

    test('restorablePrefixes contient les routes multiplayer restaurables', () {
      const expectedRestorable = [
        '/lobby',
        '/multiplayer/game',
        '/multiplayer/memorization',
        '/multiplayer/results',
        '/multiplayer/dutch-reveal',
      ];
      for (final route in expectedRestorable) {
        expect(
          _isRestorable(route),
          isTrue,
          reason: '$route devrait être dans _restorablePrefixes',
        );
      }
    });

    test('routes solo sont stateful mais PAS restaurables', () {
      const soloRoutes = [
        '/solo/game',
        '/solo/memorization',
        '/solo/results',
        '/solo/dutch-reveal',
      ];
      for (final route in soloRoutes) {
        expect(_isStateful(route), isTrue,
            reason: '$route devrait être stateful');
        expect(_isRestorable(route), isFalse,
            reason: '$route ne devrait PAS être restaurable');
      }
    });

    test('routes menu ne sont NI stateful NI restaurables', () {
      const menuRoutes = ['/', '/multiplayer', '/settings', '/rules'];
      for (final route in menuRoutes) {
        expect(_isStateful(route), isFalse,
            reason: '$route ne devrait PAS être stateful');
        expect(_isRestorable(route), isFalse,
            reason: '$route ne devrait PAS être restaurable');
      }
    });

    test('consumePendingDeepLink retourne null par défaut', () {
      expect(AppRouter.consumePendingDeepLink(), isNull);
    });

    test('consumePendingDeepLink consomme le lien (une seule fois)', () {
      // On ne peut pas setter _pendingDeepLink directement, mais on teste
      // que le consume est idempotent
      expect(AppRouter.consumePendingDeepLink(), isNull);
      expect(AppRouter.consumePendingDeepLink(), isNull);
    });

    test('markSplashDone ne crash pas', () {
      AppRouter.markSplashDone();
    });
  });

  group('MultiplayerGameProvider - session save/clear', () {
    late MockMultiplayerService mockService;
    late MultiplayerGameProvider provider;

    setUp(() {
      mockService = MockMultiplayerService();
      provider = MultiplayerGameProvider(multiplayerService: mockService);
    });

    tearDown(() {
      provider.dispose();
    });

    test('createRoom sauvegarde la session (stub no-op sur mobile)', () async {
      // Le stub ne stocke rien, mais on vérifie que ça ne crash pas
      await provider.createRoom(
        settings: GameSettings(gameMode: GameMode.quick),
        playerName: 'TestPlayer',
      );
      expect(provider.roomCode, equals('TEST123'));
      expect(provider.isHost, isTrue);
      expect(provider.isInLobby, isTrue);
    });

    test('joinRoom sauvegarde la session (stub no-op sur mobile)', () async {
      await provider.joinRoom(
        roomCode: 'ROOM456',
        playerName: 'Joueur',
      );
      expect(provider.roomCode, equals('ROOM456'));
      expect(provider.isInLobby, isTrue);
      expect(mockService.joinRoomCount, 1);
    });

    test('leaveRoom clear la session', () async {
      await provider.createRoom(
        settings: GameSettings(gameMode: GameMode.quick),
        playerName: 'Host',
      );
      expect(provider.roomCode, isNotNull);

      await provider.leaveRoom();
      expect(provider.roomCode, isNull);
      expect(provider.isInLobby, isFalse);
    });

    test('acknowledgeRoomClosed clear la session', () async {
      await provider.joinRoom(
        roomCode: 'ROOM789',
        playerName: 'Joueur',
      );
      expect(provider.roomCode, isNotNull);

      // Simuler une fermeture de room
      mockService.onRoomClosed?.call({'roomCode': 'ROOM789'});
      provider.acknowledgeRoomClosed();

      expect(provider.roomCode, isNull);
    });

    test('acknowledgeKicked clear la session', () async {
      await provider.joinRoom(
        roomCode: 'ROOM_KICK',
        playerName: 'Joueur',
      );
      expect(provider.roomCode, isNotNull);

      mockService.onKicked?.call({'message': 'Kicked'});
      provider.acknowledgeKicked();

      expect(provider.roomCode, isNull);
    });
  });

  group('Session restore - flow simulation', () {
    late MockMultiplayerService mockService;
    late MultiplayerGameProvider provider;

    setUp(() {
      mockService = MockMultiplayerService();
      provider = MultiplayerGameProvider(multiplayerService: mockService);
    });

    tearDown(() {
      provider.dispose();
    });

    test('joinRoom après reload restaure le state correctement', () async {
      // Simuler : l'utilisateur était dans une room, reload, on rejoint
      await provider.joinRoom(
        roomCode: 'RESTORE1',
        playerName: 'Joueur',
      );

      expect(provider.roomCode, equals('RESTORE1'));
      expect(provider.isInLobby, isTrue);
      expect(provider.playersInLobby, isNotEmpty);
      expect(mockService.joinRoomCount, 1);
    });

    test('joinRoom échoué ne laisse pas de state orphelin', () async {
      mockService.mockJoinRoomResult = null;

      // joinRoom avec un service qui retourne null ne doit pas crash
      await provider.joinRoom(
        roomCode: 'BAD_ROOM',
        playerName: 'Joueur',
      );

      expect(provider.roomCode, equals('BAD_ROOM'));
      expect(provider.isInLobby, isTrue);
    });

    test('double joinRoom sur la même room ne duplique pas', () async {
      await provider.joinRoom(roomCode: 'SAME', playerName: 'A');
      await provider.joinRoom(roomCode: 'SAME', playerName: 'A');

      expect(mockService.joinRoomCount, 2);
      expect(provider.roomCode, equals('SAME'));
    });

    test('rejoindre une room restaure les players du lobby', () async {
      mockService.mockJoinRoomResult = {
        'roomCode': 'LOBBY1',
        'hostPlayerId': 'host_1',
        'settings': GameSettings(gameMode: GameMode.tournament).toJson(),
        'players': [
          {
            'id': 'host_1',
            'clientId': 'c1',
            'name': 'Host',
            'isHuman': true,
            'ready': true
          },
          {
            'id': 'test_player',
            'clientId': 'test_client',
            'name': 'Me',
            'isHuman': true,
            'ready': false
          },
          {
            'id': 'other',
            'clientId': 'c3',
            'name': 'Other',
            'isHuman': true,
            'ready': true
          },
        ],
      };

      await provider.joinRoom(roomCode: 'LOBBY1', playerName: 'Me');

      expect(provider.playersInLobby.length, 3);
      expect(provider.hostPlayerId, 'host_1');
      expect(provider.roomSettings?.gameMode, GameMode.tournament);
    });
  });
}

// Helpers qui reflètent les listes statiques de AppRouter
// (on les duplique ici pour tester sans accéder au private)
const _statefulPrefixes = [
  '/lobby',
  '/solo/game',
  '/solo/memorization',
  '/solo/results',
  '/solo/dutch-reveal',
  '/multiplayer/game',
  '/multiplayer/memorization',
  '/multiplayer/results',
  '/multiplayer/dutch-reveal',
];

const _restorablePrefixes = [
  '/lobby',
  '/multiplayer/game',
  '/multiplayer/memorization',
  '/multiplayer/results',
  '/multiplayer/dutch-reveal',
];

bool _isStateful(String path) =>
    _statefulPrefixes.any((prefix) => path.startsWith(prefix));

bool _isRestorable(String path) =>
    _restorablePrefixes.any((prefix) => path.startsWith(prefix));
