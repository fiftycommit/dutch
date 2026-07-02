import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/models/playing_card.dart';
import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/providers/settings_provider.dart';
import 'package:dutch_game/screens/multiplayer/game/multiplayer_game_screen.dart';
import 'package:dutch_game/services/multiplayer/socket_connection_handler.dart';
import 'package:dutch_game/services/ui/emote_service.dart';
import 'package:dutch_game/utils/rebuild_probe.dart';

/// Fake provider minimal pour monter le VRAI `MultiplayerGameScreen` et mesurer
/// les rebuilds par zone. `tickPresence()` change UNIQUEMENT
/// `presenceCheckDeadlineMs` (un champ d'overlay) : aucune zone qui n'en dépend
/// pas ne devrait se reconstruire après le découpage.
class _FakeMultiProvider extends ChangeNotifier
    implements MultiplayerGameProvider {
  _FakeMultiProvider(this._gameState);

  GameState? _gameState;
  int _presenceDeadline = 0;

  final StreamController<GameEvent> _events =
      StreamController<GameEvent>.broadcast();
  final StreamController<EmoteEvent> _emotes =
      StreamController<EmoteEvent>.broadcast();

  /// Simule un tick du compte à rebours de présence (champ d'overlay isolé).
  void tickPresence() {
    _presenceDeadline += 1000;
    notifyListeners();
  }

  /// Simule une action de jeu (nouvel état → nouvelle instance de gameState).
  void pushGameState(GameState next) {
    _gameState = next;
    notifyListeners();
  }

  @override
  GameState? get gameState => _gameState;
  @override
  int get presenceCheckDeadlineMs => _presenceDeadline;
  @override
  bool get presenceCheckActive => false;
  @override
  String? get presenceCheckReason => null;

  @override
  Stream<GameEvent> get events => _events.stream;
  @override
  Stream<EmoteEvent> get emoteStream => _emotes.stream;

  @override
  String? get roomCode => 'ABC123';
  @override
  bool get isInLobby => false;
  @override
  bool get roomClosedByHost => false;
  @override
  SocketConnectionState get connectionState => SocketConnectionState.connected;
  @override
  String? get errorMessage => null;
  @override
  bool get wasKicked => false;
  @override
  bool get wasBanned => false;
  @override
  bool get showSpiedCardDialog => false;
  @override
  bool get isProcessing => false;
  @override
  Set<int> get shakingCardIndices => const {};
  @override
  String? get playerId => 'human';
  @override
  Map<String, Map<String, dynamic>> get presenceById => const {};
  @override
  bool isPlayerAfk(String playerId) => false;
  @override
  int get serverTimeOffsetMs => 0;
  @override
  int get currentReactionTimeMs => 0;
  @override
  Set<String> get powerTargetPlayerIds => const {};
  @override
  bool get isPaused => false;
  @override
  String? get pausedByName => null;
  @override
  bool get isLocalPauser => false;
  @override
  int get pauseDeadlineMs => 0;
  @override
  int get tournamentTotalRounds => 0;
  @override
  GameSettings? get roomSettings => GameSettings(isPublic: false);
  @override
  bool get playerLeftNotification => false;
  @override
  String? get lastPlayerLeftName => null;
  @override
  bool get specialPowerNotification => false;
  @override
  String? get specialPowerByName => null;
  @override
  bool get isSilentReconnecting => false;

  @override
  void dispose() {
    _events.close();
    _emotes.close();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

GameState _multiState() {
  final players = [
    Player(id: 'human', name: 'Human', isHuman: true, position: 0),
    Player(id: 'bot1', name: 'Bot 1', isHuman: false, position: 1),
    Player(id: 'bot2', name: 'Bot 2', isHuman: false, position: 2),
  ];
  for (final p in players) {
    p.hand = [
      PlayingCard.create('hearts', 'A'),
      PlayingCard.create('diamonds', '2'),
    ];
    p.knownCards = List.filled(2, false, growable: true);
  }
  return GameState(
    players: players,
    deck: GameState.createFullDeck().sublist(0, 40),
    discardPile: [PlayingCard.create('hearts', '5')],
    currentPlayerIndex: 0,
    phase: GamePhase.playing,
  );
}

final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');
final Uint8List _svg = Uint8List.fromList(utf8.encode(
    '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
    '<rect width="10" height="10"/></svg>'));

ByteData _assetFor(ByteData? m) {
  final key = m == null
      ? ''
      : utf8.decode(m.buffer.asUint8List(m.offsetInBytes, m.lengthInBytes));
  if (key.endsWith('.svg')) return ByteData.sublistView(_svg);
  return ByteData.sublistView(_png);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    RebuildProbe.enabled = true;
    RebuildProbe.reset();
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (m) async => _assetFor(m));
  });

  tearDown(() {
    RebuildProbe.enabled = false;
    RebuildProbe.reset();
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  Future<_FakeMultiProvider> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = _FakeMultiProvider(_multiState());
    addTearDown(provider.dispose);

    final previousOnError = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) return;
      previousOnError?.call(d);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>(
              create: (_) => SettingsProvider()),
          ChangeNotifierProvider<MultiplayerGameProvider>.value(
              value: provider),
        ],
        child: const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: MultiplayerGameScreen(),
        ),
      ),
    );
    await tester.pump(); // post-frame : abonnement des listeners
    return provider;
  }

  testWidgets(
      'BASELINE : un tick de présence reconstruit tout le corps de l\'écran',
      (tester) async {
    final provider = await pumpScreen(tester);

    RebuildProbe.reset();
    for (var i = 0; i < 5; i++) {
      provider.tickPresence();
      await tester.pump();
    }

    // Avant découpage : le corps entier (screen_body) rebuild à chaque tick,
    // alors que presenceCheckDeadlineMs ne concerne que l'overlay de présence.
    expect(RebuildProbe.countFor('screen_body'), 5);
  });
}
