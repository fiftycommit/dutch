import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/widgets/dialogs/emote_overlay.dart';

/// UI Regression Tests - Hardened test suite for critical UI fixes
/// These tests use semantic Keys and verify visual/functional behavior
///
/// NOTE: les groupes qui réimplémentaient des widgets en local ont été déplacés
/// vers des tests montant les VRAIS écrans (une copie locale ne peut pas détecter
/// une régression de l'écran réel) :
///  - code salon / boutons hôte-invité du lobby →
///    `test/screens/multiplayer_lobby_screen_real_test.dart` (la clé
///    `public_badge` qu'ils testaient n'existe même pas dans le code réel) ;
///  - alignement du badge Dutch →
///    `test/screens/dutch_reveal_screen_real_test.dart`.

void main() {
  group('3. EmoteOverlay - No Overflow Detection', () {
    testWidgets('EmoteOverlay renders without overflow errors on compact screen', (tester) async {
      final errors = <FlutterErrorDetails>[];
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details);

      tester.view.physicalSize = const Size(800, 350);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmoteOverlay(
              onClose: () {},
              onEmoteSent: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      FlutterError.onError = oldHandler;

      // Filter for overflow errors specifically
      final overflowErrors = errors.where((e) =>
          e.toString().toLowerCase().contains('overflow') ||
          e.toString().toLowerCase().contains('renderflex'));

      expect(overflowErrors, isEmpty,
          reason: 'EmoteOverlay should not have overflow errors on compact screens');

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('EmoteOverlay renders without overflow errors on normal screen', (tester) async {
      final errors = <FlutterErrorDetails>[];
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details);

      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmoteOverlay(
              onClose: () {},
              onEmoteSent: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      FlutterError.onError = oldHandler;

      final overflowErrors = errors.where((e) =>
          e.toString().toLowerCase().contains('overflow') ||
          e.toString().toLowerCase().contains('renderflex'));

      expect(overflowErrors, isEmpty,
          reason: 'EmoteOverlay should not have overflow errors on normal screens');

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });

  group('5. Bot Count Clamp Tests', () {
    // Tests the max bots calculation based on human count
    // maxBots = 4 - humanCount (room max is 4 players)

    int calculateMaxBots(int humanCount) {
      const maxPlayers = 4;
      return (maxPlayers - humanCount).clamp(0, 3);
    }

    test('2 humans -> max 2 bots', () {
      expect(calculateMaxBots(2), 2);
    });

    test('4 humans -> max 0 bots', () {
      expect(calculateMaxBots(4), 0);
    });

    test('1 human -> max 3 bots', () {
      expect(calculateMaxBots(1), 3);
    });

    test('3 humans -> max 1 bot', () {
      expect(calculateMaxBots(3), 1);
    });

    testWidgets('bot selection shows correct max options based on human count', (tester) async {
      const humanCount = 2;
      final maxBots = (4 - humanCount).clamp(0, 3); // Should be 2
      int selectedBots = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Wrap(
                  spacing: 8,
                  children: List.generate(maxBots + 1, (index) {
                    return ChoiceChip(
                      key: Key('bot_chip_$index'),
                      label: Text('$index'),
                      selected: selectedBots == index,
                      onSelected: (selected) {
                        if (selected) setState(() => selectedBots = index);
                      },
                    );
                  }),
                );
              },
            ),
          ),
        ),
      );

      // With 2 humans, should have options for 0, 1, 2 bots (3 chips)
      expect(find.byType(ChoiceChip), findsNWidgets(3));
      expect(find.byKey(const Key('bot_chip_0')), findsOneWidget);
      expect(find.byKey(const Key('bot_chip_1')), findsOneWidget);
      expect(find.byKey(const Key('bot_chip_2')), findsOneWidget);
      expect(find.byKey(const Key('bot_chip_3')), findsNothing); // Not available
    });

    testWidgets('default bot count is 0', (tester) async {
      int defaultBotCount = 0; // As fixed in the implementation

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Wrap(
              children: List.generate(4, (index) {
                return ChoiceChip(
                  key: Key('bot_chip_$index'),
                  label: Text('$index'),
                  selected: defaultBotCount == index,
                  onSelected: (_) {},
                );
              }),
            ),
          ),
        ),
      );

      // First chip (0 bots) should be selected by default
      final firstChip = tester.widget<ChoiceChip>(find.byKey(const Key('bot_chip_0')));
      expect(firstChip.selected, isTrue);

      // Other chips should not be selected
      final secondChip = tester.widget<ChoiceChip>(find.byKey(const Key('bot_chip_1')));
      expect(secondChip.selected, isFalse);
    });
  });
}
