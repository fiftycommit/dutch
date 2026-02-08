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
import 'router/app_router.dart';
import 'services/multiplayer/client_id_service.dart';

/// Global navigator key for legacy code compatibility (bot_ai.dart)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // Ensure a persistent client identity exists for learning/cloning uploads.
  await ClientIdService.ensureClientId();

  runApp(const DutchGameApp());
}

class DutchGameApp extends StatefulWidget {
  const DutchGameApp({super.key});

  @override
  State<DutchGameApp> createState() => _DutchGameAppState();
}

class _DutchGameAppState extends State<DutchGameApp> {
  GoRouter? _router;

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
        ChangeNotifierProvider(create: (_) => MultiplayerGameProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: Builder(
        builder: (context) {
          // Créer le router une seule fois pour éviter de reset la navigation
          _router ??= AppRouter.createRouter(context);

          return MaterialApp.router(
            routerConfig: _router!,
            title: 'Dutch Card Game',
            debugShowCheckedModeBanner: false,
            builder: (context, child) {
              return child ?? const SizedBox.shrink();
            },
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
