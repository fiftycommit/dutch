import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';
import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/screens/multiplayer/game/multiplayer_results_screen.dart';
import '../mocks/mock_multiplayer_service.dart';
import '../mocks/mock_services.dart';

void main() {
  testWidgets('results display the exact RP supplied by the multiplayer server',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = MockMultiplayerService();
    final provider = MultiplayerGameProvider(
        multiplayerService: service, hapticService: MockHapticService());
    addTearDown(provider.dispose);
    await provider.createRoom(
        settings: GameSettings(gameMode: GameMode.quick), playerName: 'Winner');
    final players = [
      Player(
          id: 'test_player',
          name: 'Winner',
          isHuman: true,
          hand: [PlayingCard.create('hearts', '5')],
          serverRPChange: 50),
      Player(
          id: 'other',
          name: 'Other',
          isHuman: true,
          hand: [PlayingCard.create('hearts', '10')],
          serverRPChange: -50),
    ];
    final game = GameState(
        players: players,
        deck: [],
        discardPile: [],
        currentPlayerIndex: 0,
        phase: GamePhase.ended,
        dutchCallerId: 'test_player');
    service.simulateGameStateUpdate(game);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
          home: MultiplayerResultsScreen(
              gameState: game, localPlayerId: 'test_player')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('+50 RP'), findsOneWidget);
    expect(find.text('-50 RP'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
