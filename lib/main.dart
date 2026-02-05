import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/service_locator.dart';
import 'core/interfaces/i_haptic_service.dart';
import 'core/interfaces/i_stats_service.dart';
import 'core/interfaces/i_bot_ai_service.dart';
import 'providers/game_provider.dart';
import 'providers/game_tracking_provider.dart';
import 'providers/multiplayer_game_provider.dart';
import 'providers/settings_provider.dart';
import 'router/app_router.dart';

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

  runApp(const DutchGameApp());
}

Future<void> initializeApp() async {
  // Initialiser Hive pour la sauvegarde (sans bloquer le démarrage)
  try {
    await Hive.initFlutter();
  } catch (e) {
    debugPrint('Erreur Hive: $e');
  }
}

class DutchGameApp extends StatefulWidget {
  const DutchGameApp({super.key});

  @override
  State<DutchGameApp> createState() => _DutchGameAppState();
}

class _DutchGameAppState extends State<DutchGameApp> {
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
          // Créer le router après que les providers soient disponibles
          final router = AppRouter.createRouter(context);

          return MaterialApp.router(
            routerConfig: router,
            title: 'Dutch Card Game',
            debugShowCheckedModeBanner: false,
            builder: (context, child) {
              return child ?? const SizedBox.shrink();
            },
            theme: ThemeData(
              primarySwatch: Colors.green,
              scaffoldBackgroundColor:
                  const Color(0xFF1a472a), // Vert foncé poker
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
                  backgroundColor: const Color(0xFF2d5f3e),
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
