import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'utils/ui_constants.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/service_locator.dart';
import 'core/interfaces/i_haptic_service.dart';
import 'core/interfaces/i_stats_service.dart';
import 'core/interfaces/i_bot_ai_service.dart';
import 'providers/game_provider.dart';
import 'providers/game_tracking_provider.dart';
import 'providers/multiplayer_game_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/auth_provider.dart';
import 'router/app_router.dart';
import 'services/multiplayer/client_id_service.dart';
import 'services/push/push_notification_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

/// Global navigator key for legacy code compatibility (bot_ai.dart)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialiser le service locator avec tous les services
  ServiceLocator.setupDefaultServices();

  // Autoriser toutes les orientations (le jeu s'adaptera)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Mode immersif : masquer toutes les barres système pour une expérience plein écran
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
    overlays: [],
  );

  // Warm-up non bloquant: ne jamais retarder le boot de l'app sur le web/PWA.
  unawaited(_warmupClientId());

  runApp(const DutchGameApp());
}

Future<void> _warmupClientId() async {
  try {
    await ClientIdService.ensureClientId().timeout(const Duration(seconds: 2));
  } catch (_) {
    // Best effort uniquement
  }
}

class DutchGameApp extends StatefulWidget {
  const DutchGameApp({super.key});

  @override
  State<DutchGameApp> createState() => _DutchGameAppState();
}

class _DutchGameAppState extends State<DutchGameApp> {
  GoRouter? _router;
  bool _pushInitialized = false;

  void _initPush(BuildContext context, bool isLoggedIn) {
    if (_pushInitialized) return;
    if (!isLoggedIn) return;

    _pushInitialized = true;
    unawaited(
      PushNotificationService().init(context.read<AuthProvider>().authService),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => GameProvider(
            hapticService: ServiceLocator().get<IHapticService>(),
            statsService: ServiceLocator().get<IStatsService>(),
            botAIService: ServiceLocator().get<IBotAIService>(),
            trackingProvider: ServiceLocator().get<GameTrackingProvider>(),
          ),
        ),
        ChangeNotifierProvider(create: (_) => AuthProvider()..init()),
        ChangeNotifierProvider(create: (_) => MultiplayerGameProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: Builder(
        builder: (context) {
          final isLoggedIn =
              context.select<AuthProvider, bool>((auth) => auth.isLoggedIn);
          _initPush(context, isLoggedIn);
          // Créer le router une seule fois pour éviter de reset la navigation
          _router ??= AppRouter.createRouter(context);

          return MaterialApp.router(
            routerConfig: _router!,
            title: 'Dutch Card Game',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              primarySwatch: Colors.green,
              scaffoldBackgroundColor:
                  AppColors.gradientBottom, // Vert foncé poker
              fontFamily: 'Roboto',
              textTheme: const TextTheme(
                headlineLarge: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
                bodyLarge: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.buttonSecondary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
