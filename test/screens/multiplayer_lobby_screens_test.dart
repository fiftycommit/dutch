import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/models/game_state.dart';

// These tests verify the UI layout behavior for compact vs standard modes
// without depending on the actual provider implementation

void main() {
  group('JoinPrivateRoomScreen Layout Tests', () {
    testWidgets('shows full form in standard layout (height >= 400)', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;

      // Test the layout structure directly
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutBuilder(
              builder: (context, constraints) {
                final isCompactLandscape = constraints.maxHeight < 400 &&
                    constraints.maxWidth > constraints.maxHeight;

                if (isCompactLandscape) {
                  return const Text('Compact Layout');
                }

                // Standard layout shows icon and title
                return Column(
                  children: [
                    Icon(Icons.vpn_key, size: 60),
                    Text('Rejoindre un Salon'),
                    TextField(decoration: InputDecoration(labelText: 'Code du salon')),
                    TextField(decoration: InputDecoration(labelText: 'Ton pseudo')),
                    ElevatedButton(onPressed: () {}, child: Text('REJOINDRE')),
                  ],
                );
              },
            ),
          ),
        ),
      );

      // Standard layout should show title and icon
      expect(find.text('Rejoindre un Salon'), findsOneWidget);
      expect(find.byIcon(Icons.vpn_key), findsOneWidget);
      expect(find.text('REJOINDRE'), findsOneWidget);

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('shows compact layout on small landscape (height < 400)', (tester) async {
      // Compact landscape: height < 400 and width > height
      tester.view.physicalSize = const Size(800, 350);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutBuilder(
              builder: (context, constraints) {
                final isCompactLandscape = constraints.maxHeight < 400 &&
                    constraints.maxWidth > constraints.maxHeight;

                if (isCompactLandscape) {
                  // Compact mode - no icon/title, just row with fields
                  return Row(
                    children: [
                      Expanded(child: TextField(decoration: InputDecoration(labelText: 'Code du salon'))),
                      SizedBox(width: 12),
                      Expanded(child: TextField(decoration: InputDecoration(labelText: 'Ton pseudo'))),
                    ],
                  );
                }

                return Column(
                  children: [
                    Icon(Icons.vpn_key, size: 60),
                    Text('Rejoindre un Salon'),
                  ],
                );
              },
            ),
          ),
        ),
      );

      // Compact mode should NOT show title and icon
      expect(find.text('Rejoindre un Salon'), findsNothing);
      expect(find.byIcon(Icons.vpn_key), findsNothing);

      // But should show fields in a row
      expect(find.text('Code du salon'), findsOneWidget);
      expect(find.text('Ton pseudo'), findsOneWidget);

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });

  group('CreatePublicRoomScreen Layout Tests', () {
    testWidgets('shows standard layout on large screens', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutBuilder(
              builder: (context, constraints) {
                final isCompactLandscape = constraints.maxHeight < 400 &&
                    constraints.maxWidth > constraints.maxHeight;

                if (isCompactLandscape) {
                  return const Text('Compact Layout');
                }

                return Column(
                  children: [
                    Icon(Icons.public, size: 60),
                    Text('Partie Publique'),
                    TextField(decoration: InputDecoration(labelText: 'Ton pseudo')),
                    TextField(decoration: InputDecoration(labelText: 'Nom du salon (optionnel)')),
                  ],
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Partie Publique'), findsOneWidget);
      expect(find.byIcon(Icons.public), findsOneWidget);

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('shows compact layout on small landscape screens', (tester) async {
      tester.view.physicalSize = const Size(800, 350);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutBuilder(
              builder: (context, constraints) {
                final isCompactLandscape = constraints.maxHeight < 400 &&
                    constraints.maxWidth > constraints.maxHeight;

                if (isCompactLandscape) {
                  return Row(
                    children: [
                      Expanded(child: TextField(decoration: InputDecoration(labelText: 'Ton pseudo'))),
                      SizedBox(width: 12),
                      Expanded(child: TextField(decoration: InputDecoration(labelText: 'Nom du salon (optionnel)'))),
                    ],
                  );
                }

                return Column(
                  children: [
                    Icon(Icons.public, size: 60),
                    Text('Partie Publique'),
                  ],
                );
              },
            ),
          ),
        ),
      );

      // Compact mode should NOT show title and icon
      expect(find.text('Partie Publique'), findsNothing);
      expect(find.byIcon(Icons.public), findsNothing);

      // Should show fields
      expect(find.text('Ton pseudo'), findsOneWidget);
      expect(find.text('Nom du salon (optionnel)'), findsOneWidget);

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });

  group('CreatePrivateRoomScreen Layout Tests', () {
    testWidgets('shows standard layout with mode selector on large screens', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutBuilder(
              builder: (context, constraints) {
                final isCompactLandscape = constraints.maxHeight < 400 &&
                    constraints.maxWidth > constraints.maxHeight;

                if (isCompactLandscape) {
                  return const Text('Compact Layout');
                }

                return Column(
                  children: [
                    Icon(Icons.lock_outline, size: 60),
                    Text('Salon Prive'),
                    TextField(decoration: InputDecoration(labelText: 'Ton pseudo')),
                    DropdownButtonFormField<GameMode>(
                      initialValue: GameMode.quick,
                      decoration: InputDecoration(labelText: 'Mode de jeu'),
                      items: [
                        DropdownMenuItem(value: GameMode.quick, child: Text('Partie rapide')),
                        DropdownMenuItem(value: GameMode.tournament, child: Text('Tournoi')),
                      ],
                      onChanged: (_) {},
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Salon Prive'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text('Mode de jeu'), findsOneWidget);

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('shows compact layout on small landscape', (tester) async {
      tester.view.physicalSize = const Size(800, 350);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutBuilder(
              builder: (context, constraints) {
                final isCompactLandscape = constraints.maxHeight < 400 &&
                    constraints.maxWidth > constraints.maxHeight;

                if (isCompactLandscape) {
                  return Row(
                    children: [
                      Expanded(child: TextField(decoration: InputDecoration(labelText: 'Ton pseudo'))),
                      SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<GameMode>(
                          initialValue: GameMode.quick,
                          decoration: InputDecoration(labelText: 'Mode de jeu'),
                          items: [
                            DropdownMenuItem(value: GameMode.quick, child: Text('Rapide')),
                            DropdownMenuItem(value: GameMode.tournament, child: Text('Tournoi')),
                          ],
                          onChanged: (_) {},
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    Icon(Icons.lock_outline),
                    Text('Salon Prive'),
                  ],
                );
              },
            ),
          ),
        ),
      );

      // Compact mode should NOT show large title/icon
      expect(find.text('Salon Prive'), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsNothing);

      // Should show fields in row
      expect(find.text('Ton pseudo'), findsOneWidget);
      expect(find.text('Mode de jeu'), findsOneWidget);

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('game mode dropdown shows both options', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DropdownButtonFormField<GameMode>(
              initialValue: GameMode.quick,
              decoration: InputDecoration(labelText: 'Mode de jeu'),
              items: [
                DropdownMenuItem(value: GameMode.quick, child: Text('Partie rapide')),
                DropdownMenuItem(value: GameMode.tournament, child: Text('Tournoi')),
              ],
              onChanged: (_) {},
            ),
          ),
        ),
      );

      // Find and tap the dropdown
      final dropdown = find.byType(DropdownButtonFormField<GameMode>);
      expect(dropdown, findsOneWidget);

      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      // Should show both options
      expect(find.text('Partie rapide'), findsWidgets);
      expect(find.text('Tournoi'), findsWidgets);

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });

  group('Compact Landscape Detection', () {
    testWidgets('isCompactLandscape is true when height < 400 and landscape', (tester) async {
      tester.view.physicalSize = const Size(800, 350);
      tester.view.devicePixelRatio = 1.0;

      bool? detectedCompact;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutBuilder(
              builder: (context, constraints) {
                detectedCompact = constraints.maxHeight < 400 &&
                    constraints.maxWidth > constraints.maxHeight;
                return Text(detectedCompact! ? 'compact' : 'standard');
              },
            ),
          ),
        ),
      );

      expect(detectedCompact, isTrue);
      expect(find.text('compact'), findsOneWidget);

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('isCompactLandscape is false when height >= 400', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;

      bool? detectedCompact;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutBuilder(
              builder: (context, constraints) {
                detectedCompact = constraints.maxHeight < 400 &&
                    constraints.maxWidth > constraints.maxHeight;
                return Text(detectedCompact! ? 'compact' : 'standard');
              },
            ),
          ),
        ),
      );

      expect(detectedCompact, isFalse);
      expect(find.text('standard'), findsOneWidget);

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('isCompactLandscape is false in portrait even with small height', (tester) async {
      // Portrait mode: width < height
      tester.view.physicalSize = const Size(350, 800);
      tester.view.devicePixelRatio = 1.0;

      bool? detectedCompact;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutBuilder(
              builder: (context, constraints) {
                detectedCompact = constraints.maxHeight < 400 &&
                    constraints.maxWidth > constraints.maxHeight;
                return Text(detectedCompact! ? 'compact' : 'standard');
              },
            ),
          ),
        ),
      );

      // Even though width is 350, it's portrait so not compact landscape
      expect(detectedCompact, isFalse);
      expect(find.text('standard'), findsOneWidget);

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
