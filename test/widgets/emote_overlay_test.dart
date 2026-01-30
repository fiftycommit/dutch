import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/widgets/emote_overlay.dart';

void main() {
  group('EmoteOverlay', () {
    testWidgets('should display emote grid', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmoteOverlay(
              onClose: () {},
              onEmoteSent: (emoji) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('ÉMOTES'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('should close when close button is tapped', (WidgetTester tester) async {
      bool closeCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmoteOverlay(
              onClose: () => closeCalled = true,
              onEmoteSent: (emoji) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(closeCalled, isTrue);
    });

    testWidgets('should close when background is tapped', (WidgetTester tester) async {
      bool closeCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmoteOverlay(
              onClose: () => closeCalled = true,
              onEmoteSent: (emoji) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(closeCalled, isTrue);
    });

    testWidgets('should send emote when emote button is tapped', (WidgetTester tester) async {
      String? sentEmote;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmoteOverlay(
              onClose: () {},
              onEmoteSent: (emoji) => sentEmote = emoji,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final emoteButton = find.text('😂').first;
      await tester.tap(emoteButton);
      await tester.pumpAndSettle();

      expect(sentEmote, '😂');
    });

    testWidgets('should display all 12 emotes', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmoteOverlay(
              onClose: () {},
              onEmoteSent: (emoji) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('😂'), findsWidgets);
      expect(find.text('😎'), findsWidgets);
      expect(find.text('🤔'), findsWidgets);
      expect(find.text('😱'), findsWidgets);
      expect(find.text('🎉'), findsWidgets);
      expect(find.text('😤'), findsWidgets);
      expect(find.text('👍'), findsWidgets);
      expect(find.text('👎'), findsWidgets);
      expect(find.text('🔥'), findsWidgets);
      expect(find.text('💪'), findsWidgets);
      expect(find.text('🤷'), findsWidgets);
      expect(find.text('😴'), findsWidgets);
    });
  });

  group('FloatingEmote', () {
    testWidgets('should display emoji and player name', (WidgetTester tester) async {
      bool completeCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                FloatingEmote(
                  emoji: '🎉',
                  playerName: 'TestPlayer',
                  position: const Offset(100, 100),
                  onComplete: () => completeCalled = true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('🎉'), findsOneWidget);
      expect(find.text('TestPlayer'), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(completeCalled, isTrue);
    });

    testWidgets('should animate and fade out', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                FloatingEmote(
                  emoji: '👍',
                  playerName: 'Player1',
                  position: const Offset(200, 200),
                  onComplete: () {},
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('👍'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('👍'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('👍'), findsOneWidget);

      await tester.pumpAndSettle();
    });
  });
}
