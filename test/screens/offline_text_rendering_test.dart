import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dutch_game/core/service_locator.dart';
import 'package:dutch_game/core/interfaces/i_haptic_service.dart';
import 'package:dutch_game/providers/auth_provider.dart';
import 'package:dutch_game/providers/game_provider.dart';
import 'package:dutch_game/providers/game_tracking_provider.dart';
import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/providers/settings_provider.dart';
import 'package:dutch_game/services/network/network_probe_service.dart';
import 'package:dutch_game/screens/menu/main_menu_screen.dart';
import 'package:dutch_game/screens/auth/register_screen.dart';
import 'package:dutch_game/screens/auth/forgot_password_screen.dart';
import 'package:dutch_game/screens/auth/login_screen.dart';
import 'package:dutch_game/widgets/game/svg_builder_provider.dart';

import '../mocks/mock_multiplayer_service.dart';
import '../mocks/mock_services.dart';

/// Ces tests montent les VRAIS écrans (pas des réimplémentations) en mode
/// hors-ligne / déconnecté et vérifient que les libellés clés sont présents
/// dans l'arbre. Ils gardent contre le retour du bug « texte absent » côté
/// widget (libellé supprimé, écran vide, texte conditionné à un état réseau).
Widget _svgBox(String assetPath, double width, double height) =>
    SizedBox(width: width, height: height);

Widget _hostScreen(Widget screen) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>(create: (_) => SettingsProvider()),
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ChangeNotifierProvider<GameProvider>(
        create: (_) => GameProvider(
          hapticService: MockHapticService(),
          statsService: MockStatsService(),
          botAIService: MockBotAIService(),
          trackingProvider: GameTrackingProvider(),
        ),
      ),
      ChangeNotifierProvider<MultiplayerGameProvider>(
        create: (_) => MultiplayerGameProvider(
          multiplayerService: MockMultiplayerService(),
          hapticService: MockHapticService(),
        ),
      ),
    ],
    child: SvgBuilderProvider(
      svgBuilder: _svgBox,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: screen,
      ),
    ),
  );
}

// Assets servis en test pour que Image.asset ET le précache SVG des écrans se
// chargent sans erreur (sinon exceptions asynchrones qui polluent les tests) :
// un SVG minimal valide pour les .svg, un PNG 1×1 sinon. On teste la présence
// du texte, pas les assets eux-mêmes.
final Uint8List _transparentPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');
final Uint8List _minimalSvg = Uint8List.fromList(utf8.encode(
    '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
    '<rect width="10" height="10" fill="#1a472a"/></svg>'));

ByteData _assetFor(ByteData? message) {
  final key = message == null
      ? ''
      : utf8.decode(message.buffer.asUint8List(
          message.offsetInBytes, message.lengthInBytes));
  if (key.endsWith('.svg')) {
    return ByteData.sublistView(_minimalSvg);
  }
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
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (message) async => _assetFor(message),
    );
    // Mode hors-ligne : la sonde réseau ne part jamais (pas d'appel HTTP réel
    // ni de timers réseau) — c'est justement le contexte du bug testé.
    NetworkProbeService.resetForTest();
    NetworkProbeService.connectivityProbe = (_) async => false;
  });

  tearDown(() {
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    NetworkProbeService.resetForTest();
  });

  /// Monte l'écran puis draine les débordements de layout : la police de test
  /// (Ahem) rend chaque glyphe carré, donc plus large que la vraie police, ce
  /// qui provoque des overflows inexistants en réel (cf. screenshots). On teste
  /// la PRÉSENCE du texte, pas le pixel-perfect — toute AUTRE exception échoue.
  Future<void> pumpScreenIgnoringOverflow(
      WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // On filtre AVANT que le binding n'agrège les erreurs les artefacts connus
    // de l'environnement de test — pour que toute AUTRE erreur reste fatale :
    //  - débordements de layout (police de test Ahem plus large que la vraie) ;
    //  - échecs de chargement d'assets image/SVG (le bundle de test ne les sert
    //    pas : FormatException « Message corrupted »).
    // Aucun de ces deux artefacts n'existe en réel (cf. screenshots).
    bool isTestEnvArtifact(FlutterErrorDetails d) {
      final s = d.exceptionAsString();
      return s.contains('overflowed') || s.contains('Message corrupted');
    }

    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (isTestEnvArtifact(details)) return;
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    await tester.pumpWidget(_hostScreen(screen));
    // Assez long pour laisser filer les timers différés (pluie de cartes à
    // 600 ms) et éviter l'assertion « Timer still pending » en fin de test.
    await tester.pump(const Duration(milliseconds: 700));
  }

  testWidgets('MainMenuScreen (hors-ligne) affiche ses libellés clés',
      (tester) async {
    await pumpScreenIgnoringOverflow(tester, const MainMenuScreen());

    expect(find.text("DUTCH'78"), findsWidgets);
    expect(find.text('PARTIE RAPIDE'), findsWidgets);
    expect(find.text('MULTIJOUEUR'), findsWidgets);
  });

  testWidgets('RegisterScreen (hors-ligne) affiche ses libellés clés',
      (tester) async {
    await pumpScreenIgnoringOverflow(tester, const RegisterScreen());

    expect(find.text('Créer un compte'), findsWidgets);
    expect(find.text('Créer mon compte'), findsWidgets);
  });

  testWidgets('ForgotPasswordScreen (hors-ligne) se rend sans texte manquant',
      (tester) async {
    await pumpScreenIgnoringOverflow(tester, const ForgotPasswordScreen());

    // Au moins un libellé texte visible (l'écran n'est pas vide de texte).
    expect(find.byType(Text), findsWidgets);
  });

  testWidgets('LoginScreen (hors-ligne) affiche ses libellés clés',
      (tester) async {
    await pumpScreenIgnoringOverflow(tester, const LoginScreen());

    expect(find.text('Connexion'), findsWidgets);
  });
}
