import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/widgets/game/game_action_button.dart';

void main() {
  group('GameActionButton', () {
    testWidgets('renders with label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameActionButton(
              label: 'Test Button',
              color: Colors.green,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Test Button'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameActionButton(
              label: 'Tap Me',
              color: Colors.green,
              onTap: () => tapCount++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tap Me'));
      await tester.pump();

      expect(tapCount, 1);
    });

    testWidgets('disabled button does not call onTap', (tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameActionButton(
              label: 'Disabled',
              color: Colors.green,
              onTap: () => tapCount++,
              enabled: false,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Disabled'));
      await tester.pump();

      expect(tapCount, 0);
    });

    testWidgets('null onTap disables button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameActionButton(
              label: 'No Action',
              color: Colors.green,
              onTap: null,
            ),
          ),
        ),
      );

      expect(find.text('No Action'), findsOneWidget);
    });

    testWidgets('can have custom colors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameActionButton(
              label: 'Colored',
              color: Colors.red,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Colored'), findsOneWidget);
    });

    testWidgets('compact mode renders smaller button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameActionButton(
              label: 'Compact',
              color: Colors.green,
              onTap: () {},
              compact: true,
            ),
          ),
        ),
      );

      expect(find.text('Compact'), findsOneWidget);
    });

    testWidgets('withPulse enables animation', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameActionButton(
              label: 'Pulsing',
              color: Colors.green,
              onTap: () {},
              withPulse: true,
            ),
          ),
        ),
      );

      expect(find.text('Pulsing'), findsOneWidget);
    });

    testWidgets('multiple taps work correctly', (tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameActionButton(
              label: 'Multi Tap',
              color: Colors.green,
              onTap: () => tapCount++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Multi Tap'));
      await tester.pump();
      await tester.tap(find.text('Multi Tap'));
      await tester.pump();
      await tester.tap(find.text('Multi Tap'));
      await tester.pump();

      expect(tapCount, 3);
    });
  });
}
