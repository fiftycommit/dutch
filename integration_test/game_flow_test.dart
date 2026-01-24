import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dutch_game/main.dart' as app;
import 'package:dutch_game/widgets/card_widget.dart';

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  const step = Duration(milliseconds: 100);
  var elapsed = Duration.zero;

  while (elapsed < timeout) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(step);
    elapsed += step;
  }
  throw TestFailure('Timeout waiting for $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('drawn card auto-collapses after draw', (tester) async {
    app.main();
    await tester.pump();

    await _pumpUntilFound(tester, find.text('PARTIE RAPIDE'),
        timeout: const Duration(seconds: 12));
    await tester.tap(find.text('PARTIE RAPIDE'));
    await tester.pump(const Duration(milliseconds: 600));

    await _pumpUntilFound(tester, find.text('COMMENCER'));
    await tester.tap(find.text('COMMENCER'));
    await tester.pump(const Duration(milliseconds: 600));

    await _pumpUntilFound(tester, find.text('MÉMORISATION'),
        timeout: const Duration(seconds: 12));

    final memorizationCards = find.byType(CardWidget);
    expect(memorizationCards, findsNWidgets(4));
    await tester.tap(memorizationCards.at(0));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(memorizationCards.at(1));
    await tester.pump(const Duration(milliseconds: 200));

    await _pumpUntilFound(tester, find.text("C'EST BON !"));
    await tester.tap(find.text("C'EST BON !"));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.pump(const Duration(seconds: 4));

    await _pumpUntilFound(tester, find.text('PIOCHER'),
        timeout: const Duration(seconds: 20));
    await tester.tap(find.text('PIOCHER'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('CARTE PIOCHÉE'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('TAP POUR AGRANDIR'), findsOneWidget);
  });
}
