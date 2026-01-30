import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:dutch_game/screens/multiplayer_mode_selection_screen.dart';

Widget createTestApp() {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const MultiplayerModeSelectionScreen(),
      ),
      GoRoute(
        path: '/multiplayer',
        builder: (context, state) => const Scaffold(body: Text('Multiplayer')),
      ),
      GoRoute(
        path: '/public-matchmaking',
        builder: (context, state) => const Scaffold(body: Text('Public')),
      ),
      GoRoute(
        path: '/create-room',
        builder: (context, state) => const Scaffold(body: Text('Create')),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  group('MultiplayerModeSelectionScreen', () {
    testWidgets('should display title', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.text('MULTIJOUEUR'), findsOneWidget);
    });

    testWidgets('should display back button', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('should display create section', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.text('CRÉER UN SALON'), findsOneWidget);
    });

    testWidgets('should display join section', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.text('REJOINDRE UN SALON'), findsOneWidget);
    });

    testWidgets('should display section icons', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.login), findsOneWidget);
    });

    testWidgets('should display card icons', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Icons: lock_outline, public, vpn_key, list_alt
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byIcon(Icons.public), findsOneWidget);
    });

    testWidgets('should have gradient background', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());
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

    testWidgets('cards should be tappable', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MultiplayerModeSelectionScreen(),
        ),
      );

      // Trouver les GestureDetector
      expect(find.byType(GestureDetector), findsAtLeastNWidgets(2));
    });

  });
}
