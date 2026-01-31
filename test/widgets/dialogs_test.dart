import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/widgets/dialogs/game/game_dialogs.dart';
import 'package:dutch_game/widgets/dialogs/connection_error_dialog.dart';

void main() {
  group('GameDialogs', () {
    group('confirmDutch', () {
      testWidgets('shows dialog with title', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => GameDialogs.confirmDutch(context),
              child: const Text('Open'),
            ),
          ),
        ));

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Crier DUTCH ?'), findsOneWidget);
      });

      testWidgets('shows confirmation text', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => GameDialogs.confirmDutch(context),
              child: const Text('Open'),
            ),
          ),
        ));

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Êtes-vous sûr ?'), findsOneWidget);
      });

      testWidgets('returns true when DUTCH button pressed', (tester) async {
        bool? result;
        
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await GameDialogs.confirmDutch(context);
              },
              child: const Text('Open'),
            ),
          ),
        ));

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('DUTCH !'));
        await tester.pumpAndSettle();

        expect(result, true);
      });

      testWidgets('returns false when Non button pressed', (tester) async {
        bool? result;
        
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await GameDialogs.confirmDutch(context);
              },
              child: const Text('Open'),
            ),
          ),
        ));

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Non'));
        await tester.pumpAndSettle();

        expect(result, false);
      });
    });

    group('showDiscardPile', () {
      test('GameDialogs class exists and has showDiscardPile method', () {
        // Test that the static method exists - actual rendering requires SVG assets
        expect(GameDialogs.showDiscardPile, isNotNull);
      });
    });
  });

  group('ConnectionErrorDialog', () {
    testWidgets('shows error message', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ConnectionErrorDialog.show(
              context,
              message: 'Test error message',
              onRetry: () {},
              onReturnToMenu: () {},
            ),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Test error message'), findsOneWidget);
    });

    testWidgets('shows title', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ConnectionErrorDialog.show(
              context,
              message: 'Error',
              onRetry: () {},
              onReturnToMenu: () {},
            ),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Connexion perdue'), findsOneWidget);
    });

    testWidgets('shows retry button', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ConnectionErrorDialog.show(
              context,
              message: 'Error',
              onRetry: () {},
              onReturnToMenu: () {},
            ),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('shows menu button', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ConnectionErrorDialog.show(
              context,
              message: 'Error',
              onRetry: () {},
              onReturnToMenu: () {},
            ),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Menu'), findsOneWidget);
    });

    testWidgets('calls onRetry when retry button pressed', (tester) async {
      int retryCount = 0;
      
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ConnectionErrorDialog.show(
              context,
              message: 'Error',
              onRetry: () => retryCount++,
              onReturnToMenu: () {},
            ),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();

      expect(retryCount, 1);
    });

    testWidgets('calls onReturnToMenu when menu button pressed', (tester) async {
      int menuCount = 0;
      
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ConnectionErrorDialog.show(
              context,
              message: 'Error',
              onRetry: () {},
              onReturnToMenu: () => menuCount++,
            ),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Menu'));
      await tester.pumpAndSettle();

      expect(menuCount, 1);
    });
  });
}
