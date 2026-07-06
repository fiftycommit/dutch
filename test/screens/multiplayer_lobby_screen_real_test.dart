import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dutch_game/core/service_locator.dart';
import 'package:dutch_game/core/interfaces/i_haptic_service.dart';
import 'package:dutch_game/models/game_settings.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/providers/auth_provider.dart';
import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/providers/settings_provider.dart';
import 'package:dutch_game/screens/multiplayer/lobby/multiplayer_lobby_screen.dart';
import 'package:dutch_game/services/multiplayer/socket_connection_handler.dart';
import 'package:dutch_game/services/network/network_probe_service.dart';

import '../mocks/mock_services.dart';

/// Faux provider minimal pour piloter l'ÉTAT du vrai `MultiplayerLobbyScreen`
/// (hôte/invité, salon public/privé) sans socket réel.
class _FakeLobbyProvider extends ChangeNotifier
    implements MultiplayerGameProvider {
  _FakeLobbyProvider({required this.isHost, required bool isPublic})
      : roomSettings = GameSettings(isPublic: isPublic);

  @override
  final bool isHost;
  @override
  final GameSettings? roomSettings;

  final StreamController<GameEvent> _events =
      StreamController<GameEvent>.broadcast();

  @override
  Stream<GameEvent> get events => _events.stream;
  @override
  String? get roomCode => 'ABC123';
  @override
  List<Map<String, dynamic>> get playersInLobby => const [];
  @override
  List<Map<String, dynamic>> get chatMessages => const [];
  @override
  SocketConnectionState get connectionState => SocketConnectionState.connected;
  @override
  String get roomStatus => 'waiting';
  @override
  GameState? get gameState => null;
  @override
  bool get isReady => false;
  @override
  int get readyHumanCount => 0;
  @override
  bool get isPlaying => false;
  @override
  String? get errorMessage => null;
  @override
  bool get wasKicked => false;
  @override
  bool get wasBanned => false;
  @override
  bool get roomClosedByHost => false;
  @override
  bool get showWizzAnimation => false;
  @override
  String? get wizzFromName => null;
  @override
  List<Map<String, dynamic>> get cumulativeScores => const [];
  @override
  String? get hostPlayerId => null;
  @override
  String? get playerId => null;
  @override
  String? get clientId => null;
  @override
  Map<String, Map<String, dynamic>> get presenceByClientId => const {};
  @override
  Map<String, Map<String, dynamic>> get presenceById => const {};
  @override
  bool get canSendWizz => false;
  @override
  void setScreenFocused(bool focused) {}

  @override
  void dispose() {
    _events.close();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
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
    SharedPreferences.setMockInitialValues({});
    final sl = ServiceLocator();
    if (!sl.isRegistered<IHapticService>()) {
      sl.register<IHapticService>(MockHapticService());
    }
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (m) async => _assetFor(m));
    NetworkProbeService.resetForTest();
    NetworkProbeService.connectivityProbe = (_) async => false;
  });

  tearDown(() {
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    NetworkProbeService.resetForTest();
  });

  Widget host(_FakeLobbyProvider provider) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider()),
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ChangeNotifierProvider<MultiplayerGameProvider>.value(value: provider),
      ],
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: MultiplayerLobbyScreen(),
      ),
    );
  }

  Future<void> pumpLobby(WidgetTester tester, _FakeLobbyProvider provider) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    await tester.pumpWidget(host(provider));
    await tester.pump(); // post-frame initState (abonnement events)
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('hôte : le VRAI écran affiche les boutons Prêt et Lancer',
      (tester) async {
    final provider = _FakeLobbyProvider(isHost: true, isPublic: false);
    addTearDown(provider.dispose);
    await pumpLobby(tester, provider);

    expect(find.byKey(const Key('host_ready_button')), findsOneWidget);
    expect(find.byKey(const Key('host_start_button')), findsOneWidget);
    expect(find.byKey(const Key('guest_ready_button')), findsNothing);
    // L'hôte a accès aux paramètres du salon (dont la config des bots).
    expect(find.text('Paramètres'), findsOneWidget);
  });

  testWidgets('invité : le VRAI écran affiche uniquement le bouton Prêt',
      (tester) async {
    final provider = _FakeLobbyProvider(isHost: false, isPublic: false);
    addTearDown(provider.dispose);
    await pumpLobby(tester, provider);

    expect(find.byKey(const Key('guest_ready_button')), findsOneWidget);
    expect(find.byKey(const Key('host_start_button')), findsNothing);
    // Libellé réel du bouton invité non-prêt.
    expect(find.text('Passer pret'), findsOneWidget);
  });

  testWidgets('salon privé : le VRAI écran affiche la carte code salon',
      (tester) async {
    final provider = _FakeLobbyProvider(isHost: true, isPublic: false);
    addTearDown(provider.dispose);
    await pumpLobby(tester, provider);

    expect(find.byKey(const Key('room_code_card')), findsOneWidget);
  });

  testWidgets('salon public : le VRAI écran masque la carte code salon',
      (tester) async {
    final provider = _FakeLobbyProvider(isHost: true, isPublic: true);
    addTearDown(provider.dispose);
    await pumpLobby(tester, provider);

    expect(find.byKey(const Key('room_code_card')), findsNothing);
  });
}
