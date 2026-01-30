import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/screens/multiplayer_mode_selection_screen.dart';

void main() {
  group('MultiplayerModeSelectionScreen', () {
    testWidgets('should display title', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MultiplayerModeSelectionScreen(),
        ),
      );

      expect(find.text('MULTIJOUEUR'), findsOneWidget);
    });

    testWidgets('should display back button', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MultiplayerModeSelectionScreen(),
        ),
      );

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('should display public mode card', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MultiplayerModeSelectionScreen(),
        ),
      );

      expect(find.text('PARTIE PUBLIQUE'), findsOneWidget);
      expect(
        find.text('Rejoignez une partie rapide avec des joueurs aléatoires'),
        findsOneWidget,
      );
      expect(find.text('RAPIDE'), findsOneWidget);
    });

    testWidgets('should display private mode card', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MultiplayerModeSelectionScreen(),
        ),
      );

      expect(find.text('PARTIE PRIVÉE'), findsOneWidget);
      expect(
        find.text('Créez ou rejoignez une partie avec vos amis'),
        findsOneWidget,
      );
      expect(find.text('AMIS'), findsOneWidget);
    });

    testWidgets('should display public icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MultiplayerModeSelectionScreen(),
        ),
      );

      expect(find.byIcon(Icons.public), findsOneWidget);
    });

    testWidgets('should display private icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MultiplayerModeSelectionScreen(),
        ),
      );

      expect(find.byIcon(Icons.lock), findsOneWidget);
    });

    testWidgets('should display arrow icons on cards', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MultiplayerModeSelectionScreen(),
        ),
      );

      expect(find.byIcon(Icons.arrow_forward_ios), findsNWidgets(2));
    });

    testWidgets('should have gradient background', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MultiplayerModeSelectionScreen(),
        ),
      );

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

    testWidgets('should display selection prompt', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MultiplayerModeSelectionScreen(),
        ),
      );

      expect(find.text('Choisissez votre mode de jeu'), findsOneWidget);
    });
  });
}
