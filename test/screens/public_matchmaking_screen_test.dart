import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:dutch_game/screens/public_matchmaking_screen.dart';
import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/services/multiplayer_service.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockMultiplayerService extends MultiplayerService {
  @override
  Future<List<Map<String, dynamic>>?> getPublicRooms() async {
    return [];
  }

  @override
  Future<String?> createRoom({
    required GameSettings settings,
    required String playerName,
  }) async {
    return 'TEST123';
  }

  @override
  Future<Map<String, dynamic>?> joinRoom({
    required String roomCode,
    required String playerName,
  }) async {
    return {'success': true};
  }

  @override
  Future<void> leaveRoom() async {}

  @override
  Future<void> connect() async {}

  @override
  Future<bool> startGame({
    bool fillBots = false,
    int? numberOfBots,
    bool? useSBMM,
    int? botDifficulty,
  }) async => true;
}

Widget createTestApp(MultiplayerGameProvider provider) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const PublicMatchmakingScreen(),
      ),
      GoRoute(
        path: '/multiplayer',
        builder: (context, state) => const Scaffold(body: Text('Back')),
      ),
    ],
  );

  return ChangeNotifierProvider<MultiplayerGameProvider>.value(
    value: provider,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('PublicMatchmakingScreen', () {
    late MultiplayerGameProvider provider;
    late MockMultiplayerService mockService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      mockService = MockMultiplayerService();
      provider = MultiplayerGameProvider(multiplayerService: mockService);
    });

    testWidgets('should display title', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      await tester.pumpAndSettle();

      expect(find.text('SALONS PUBLICS'), findsOneWidget);
    });

    testWidgets('should display back button', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('should display refresh icon', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('should display empty state when no rooms', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      await tester.pumpAndSettle();

      // Le mock retourne une liste vide, donc on devrait voir l'état vide
      expect(find.text('Aucun salon disponible'), findsOneWidget);
    });

    testWidgets('should display empty state icon', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.search_off), findsOneWidget);
    });

    testWidgets('should have gradient background', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      await tester.pumpAndSettle();

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(Scaffold),
          matching: find.byType(Container),
        ).first,
      );

      expect(container.decoration, isA<BoxDecoration>());
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.gradient, isA<LinearGradient>());
    });
  });
}
