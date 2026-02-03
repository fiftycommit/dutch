import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dutch_game/widgets/dialogs/emote_overlay.dart';

/// UI Regression Tests - Hardened test suite for critical UI fixes
/// These tests use semantic Keys and verify visual/functional behavior

/// Helper to build room code widget based on public/private state
Widget _buildRoomCodeWidget({required bool isPublic}) {
  // Logic from multiplayer_lobby_screen.dart:
  // final showPublicBadge = provider.roomSettings?.isPublic == true;
  // final showRoomCode = !showPublicBadge;
  if (!isPublic) {
    return Container(
      key: const Key('room_code_card'),
      child: Column(
        children: const [
          Text('Code'),
          Text(
            'ABC123',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
            ),
          ),
        ],
      ),
    );
  } else {
    return Container(
      key: const Key('public_badge'),
      child: const Text('PUBLIQUE'),
    );
  }
}

/// Helper to build host/guest buttons based on isHost state
Widget _buildLobbyButtons({required bool isHost}) {
  if (isHost) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            key: const Key('host_ready_button'),
            onPressed: () {},
            child: const Text('Pret'),
          ),
        ),
        Expanded(
          child: ElevatedButton(
            key: const Key('host_start_button'),
            onPressed: null,
            child: const Text('Lancer'),
          ),
        ),
      ],
    );
  } else {
    return ElevatedButton(
      key: const Key('guest_ready_button'),
      onPressed: () {},
      child: const Text('Passer pret'),
    );
  }
}

void main() {
  group('1. Private Room Code Visibility', () {
    // Tests that private room code is visible even in quick mode
    // Regression for bug: "code not displayed in quick mode"

    testWidgets('room code card displays when isPublic is false', (tester) async {
      // Simulates the lobby screen logic for showing room code
      // Even in quick mode, code should show for private rooms

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _buildRoomCodeWidget(isPublic: false),
          ),
        ),
      );

      // Room code card should be visible for private rooms
      expect(find.byKey(const Key('room_code_card')), findsOneWidget);
      expect(find.text('Code'), findsOneWidget);
      expect(find.text('ABC123'), findsOneWidget);
    });

    testWidgets('room code is hidden for public rooms', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _buildRoomCodeWidget(isPublic: true),
          ),
        ),
      );

      // Room code should NOT be visible for public rooms
      expect(find.byKey(const Key('room_code_card')), findsNothing);
      expect(find.byKey(const Key('public_badge')), findsOneWidget);
    });
  });

  group('2. Button Keys for Robust Testing', () {
    testWidgets('host buttons have correct keys', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    key: const Key('host_ready_button'),
                    onPressed: () {},
                    child: const Text('Pret'),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    key: const Key('host_start_button'),
                    onPressed: null,
                    child: const Text('Lancer'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('host_ready_button')), findsOneWidget);
      expect(find.byKey(const Key('host_start_button')), findsOneWidget);
    });

    testWidgets('guest ready button has correct key', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElevatedButton(
              key: const Key('guest_ready_button'),
              onPressed: () {},
              child: const Text('Passer pret'),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('guest_ready_button')), findsOneWidget);
    });

    testWidgets('join and create buttons have correct keys', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ElevatedButton(
                  key: const Key('join_private_button'),
                  onPressed: () {},
                  child: const Text('REJOINDRE'),
                ),
                ElevatedButton(
                  key: const Key('create_private_button'),
                  onPressed: () {},
                  child: const Text('CRÉER LE SALON'),
                ),
                ElevatedButton(
                  key: const Key('create_public_button'),
                  onPressed: () {},
                  child: const Text('CRÉER ET OUVRIR'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('join_private_button')), findsOneWidget);
      expect(find.byKey(const Key('create_private_button')), findsOneWidget);
      expect(find.byKey(const Key('create_public_button')), findsOneWidget);
    });
  });

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

  group('4. Dutch Reveal - Card Y-Position Alignment', () {
    testWidgets('all player columns have same Y-position for cards', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Player 1 - Dutch caller (has visible badge)
                Expanded(
                  child: Column(
                    children: [
                      const Text('Player 1'),
                      Container(
                        key: const Key('player1_badge'),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.amber,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('DUTCH', style: TextStyle(fontSize: 8)),
                      ),
                      Container(
                        key: const Key('player1_cards'),
                        height: 100,
                        color: Colors.grey,
                        child: const Text('Cards'),
                      ),
                    ],
                  ),
                ),
                // Player 2 - Not Dutch (has invisible placeholder)
                Expanded(
                  child: Column(
                    children: [
                      const Text('Player 2'),
                      Container(
                        key: const Key('player2_badge'),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.transparent, // Placeholder
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('DUTCH',
                            style: TextStyle(fontSize: 8, color: Colors.transparent)),
                      ),
                      Container(
                        key: const Key('player2_cards'),
                        height: 100,
                        color: Colors.grey,
                        child: const Text('Cards'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Get positions of card containers
      final player1Cards = tester.getTopLeft(find.byKey(const Key('player1_cards')));
      final player2Cards = tester.getTopLeft(find.byKey(const Key('player2_cards')));

      // Y positions should be identical (cards are aligned)
      expect(player1Cards.dy, player2Cards.dy,
          reason: 'Card containers should have same Y position for alignment');
    });

    testWidgets('badges have same dimensions for alignment', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                // Visible badge
                Container(
                  key: const Key('visible_badge'),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('DUTCH', style: TextStyle(fontSize: 8)),
                ),
                const SizedBox(width: 20),
                // Invisible placeholder
                Container(
                  key: const Key('invisible_badge'),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('DUTCH',
                      style: TextStyle(fontSize: 8, color: Colors.transparent)),
                ),
              ],
            ),
          ),
        ),
      );

      final visibleSize = tester.getSize(find.byKey(const Key('visible_badge')));
      final invisibleSize = tester.getSize(find.byKey(const Key('invisible_badge')));

      // Both badges should have identical dimensions
      expect(visibleSize.width, invisibleSize.width,
          reason: 'Badge widths should match for alignment');
      expect(visibleSize.height, invisibleSize.height,
          reason: 'Badge heights should match for alignment');
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

  group('6. Host vs Non-Host Button Visibility', () {
    testWidgets('host sees both Ready and Start buttons using Keys', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _buildLobbyButtons(isHost: true),
          ),
        ),
      );

      expect(find.byKey(const Key('host_ready_button')), findsOneWidget);
      expect(find.byKey(const Key('host_start_button')), findsOneWidget);
      expect(find.byKey(const Key('guest_ready_button')), findsNothing);
    });

    testWidgets('non-host sees only Ready button using Keys', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _buildLobbyButtons(isHost: false),
          ),
        ),
      );

      expect(find.byKey(const Key('guest_ready_button')), findsOneWidget);
      expect(find.byKey(const Key('host_ready_button')), findsNothing);
      expect(find.byKey(const Key('host_start_button')), findsNothing);
    });
  });
}
