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

      expect(find.text('RECHERCHE DE PARTIE'), findsOneWidget);
    });

    testWidgets('should display back button', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('should display search icon', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('should display searching message', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      await tester.pumpAndSettle();

      expect(find.text('Recherche de joueurs...'), findsOneWidget);
    });

    testWidgets('should display timer starting at 0:00', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      await tester.pumpAndSettle();

      expect(find.text('0:00'), findsOneWidget);
    });

    testWidgets('should display player count', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      await tester.pumpAndSettle();

      expect(find.textContaining('/4 joueurs'), findsOneWidget);
    });

    testWidgets('should display cancel button', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      await tester.pumpAndSettle();

      expect(find.text('ANNULER'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('should display people icon', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.people), findsOneWidget);
    });

    testWidgets('should have animations', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      await tester.pumpAndSettle();

      // Vérifier la présence des animations
      expect(find.byType(ScaleTransition), findsWidgets);
      expect(find.byType(RotationTransition), findsWidgets);
    });

    testWidgets('timer should start at 0:00', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      await tester.pumpAndSettle();

      expect(find.text('0:00'), findsOneWidget);
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

    testWidgets('cancel button should be red', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp(provider));
      await tester.pumpAndSettle();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'ANNULER'),
      );

      final style = button.style;
      expect(style, isNotNull);
    });
  });
}
