import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';
import 'package:dutch_game/screens/shared/unified_dutch_reveal_screen.dart';

/// Monte le VRAI `DutchRevealScreen` (au lieu de réimplémenter des badges/cartes
/// en local) et vérifie le comportement d'alignement réel : seul l'appelant du
/// Dutch reçoit le badge « DUTCH », les autres reçoivent un espace réservé de
/// même hauteur (d'où l'alignement des colonnes).
GameState _revealState({required String dutchCallerId}) {
  final players = [
    Player(id: 'human', name: 'Human', isHuman: true, position: 0),
    Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
    Player(id: 'bot2', name: 'Bot 2', isHuman: false, position: 2),
  ];
  for (final player in players) {
    player.hand = [
      PlayingCard.create('hearts', 'A'),
      PlayingCard.create('diamonds', '2'),
    ];
    player.knownCards = List.filled(2, true, growable: true);
  }
  return GameState(
    players: players,
    deck: GameState.createFullDeck().sublist(0, 40),
    discardPile: [PlayingCard.create('hearts', '5')],
    currentPlayerIndex: 0,
    phase: GamePhase.playing,
    dutchCallerId: dutchCallerId,
  );
}

Widget _wrap(GameState state) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: DutchRevealScreen(
      config: DutchRevealConfig(
        gameState: state,
        localPlayerId: 'human',
        buildResultsScreen: (_) => const Scaffold(body: Text('résultats')),
      ),
    ),
  );
}

Future<void> _mountReveal(WidgetTester tester, GameState state) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    previousOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = previousOnError);

  await tester.pumpWidget(_wrap(state));
  await tester.pump();
}

// La séquence de révélation enchaîne Future.delayed + animations sur quelques
// secondes ; on la draine pour éviter l'assertion « Timer still pending ».
Future<void> _drainReveal(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 700));
  }
}

final Uint8List _transparentPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');
final Uint8List _minimalSvg = Uint8List.fromList(utf8.encode(
    '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
    '<rect width="10" height="10" fill="#1a472a"/></svg>'));

ByteData _assetFor(ByteData? message) {
  final key = message == null
      ? ''
      : utf8.decode(message.buffer
          .asUint8List(message.offsetInBytes, message.lengthInBytes));
  if (key.endsWith('.svg')) return ByteData.sublistView(_minimalSvg);
  return ByteData.sublistView(_transparentPng);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (m) async => _assetFor(m));
  });

  tearDown(() {
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  testWidgets('seul l\'appelant du Dutch a le badge DUTCH', (tester) async {
    await _mountReveal(tester, _revealState(dutchCallerId: 'human'));

    // Un seul badge de joueur « DUTCH » (l'appelant) parmi les 3 joueurs.
    expect(find.text('DUTCH'), findsOneWidget);

    await _drainReveal(tester);
  });

  testWidgets('le badge suit l\'appelant quand ce n\'est pas le joueur local',
      (tester) async {
    await _mountReveal(tester, _revealState(dutchCallerId: 'bot1'));

    expect(find.text('DUTCH'), findsOneWidget);

    await _drainReveal(tester);
  });
}
