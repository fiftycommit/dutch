import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'core/service_locator.dart';
import 'core/firebase_app_check_bootstrap.dart';
import 'core/interfaces/i_haptic_service.dart';
import 'core/interfaces/i_bot_ai_service.dart';
import 'core/interfaces/i_stats_service.dart';
import 'firebase_options.dart';
import 'models/game_settings.dart';
import 'providers/game_provider.dart';
import 'providers/game_tracking_provider.dart';
import 'providers/multiplayer_game_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/auth_provider.dart';
import 'router/app_router.dart';
import 'services/multiplayer/client_id_service.dart';
import 'services/logging/error_reporting_service.dart';
import 'services/notifications/in_app_notification_service.dart';
import 'services/push/push_notification_service.dart';
import 'utils/ui_constants.dart';
import 'widgets/notifications/notification_overlay_controller.dart';

/// Global navigator key for legacy code compatibility (bot_ai.dart)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

void main() {
  final errorService = ErrorReportingService();

  // Capturer les erreurs async non gérées via runZonedGuarded
  // IMPORTANT : ensureInitialized() et runApp() doivent être dans la même zone
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Capturer les erreurs Flutter (widget build, layout, etc.)
    FlutterError.onError = (details) {
      errorService.reportFlutterError(details);
      // En debug, on garde aussi le comportement par défaut (écran rouge)
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
    };
    // Lancer Firebase et l'orientation en parallèle (non séquentiel)
    await Future.wait([
      Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ),
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]),
    ]);

    try {
      await activateFirebaseAppCheck();
    } catch (error, stackTrace) {
      errorService.reportZoneError(error, stackTrace);
    }

    // Sur macOS natif, ignorer les erreurs Keychain (ad-hoc signing)
    // setPersistence n'est supporté que sur le web
    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Initialiser le service locator avec tous les services
    ServiceLocator.setupDefaultServices();

    // Plein écran edge-to-edge : contenu sous les barres système
    // mais SafeArea toujours respectée (contrairement à immersiveSticky)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ));

    // Warm-up non bloquant: ne jamais retarder le boot de l'app sur le web/PWA.
    unawaited(_warmupClientId());

    runApp(const DutchGameApp());
  }, (error, stackTrace) {
    errorService.reportZoneError(error, stackTrace);
  });
}

ThemeData _buildLightTheme() => ThemeData(
      brightness: Brightness.light,
      primarySwatch: Colors.green,
      scaffoldBackgroundColor:
          kIsWeb ? Colors.transparent : AppColors.gradientBottom,
      fontFamily: 'Roboto',
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF007AFF),
        secondary: Color(0xFF34C759),
        error: Color(0xFFFF3B30),
        surface: Color(0xFFFFFFFF),
      ),
      // Transitions de page explicites : predictive back Android 14+, swipe iOS/macOS
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
            color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
        bodyLarge: TextStyle(color: Colors.white, fontSize: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.buttonSecondary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );

ThemeData _buildDarkTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor:
          kIsWeb ? Colors.transparent : AppColors.gradientBottom,
      fontFamily: 'Roboto',
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF0A84FF),
        secondary: Color(0xFF30D158),
        error: Color(0xFFFF453A),
        surface: Color(0xFF1C1C1E),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      // Transitions de page explicites : predictive back Android 14+, swipe iOS/macOS
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
            color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
        bodyLarge: TextStyle(color: Colors.white, fontSize: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.buttonSecondary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );

ThemeData _buildGreenTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor:
          kIsWeb ? Colors.transparent : AppColors.gradientBottom,
      fontFamily: 'Roboto',
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF4CAF50),
        secondary: Color(0xFF66BB6A),
        error: Color(0xFFFF453A),
        surface: Color(0xFF1A3A28),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A3A28),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      // Transitions de page explicites : predictive back Android 14+, swipe iOS/macOS
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
            color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
        bodyLarge: TextStyle(color: Colors.white, fontSize: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.buttonSecondary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );

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
    final push = PushNotificationService();
    push.onRoomInviteTapped = (roomCode) {
      // Naviguer vers le menu multijoueur avec le code salon en paramètre
      // Le menu gérera le join automatique au chargement.
      _router?.go('/multiplayer?joinRoom=$roomCode');
    };
    unawaited(push.init(context.read<AuthProvider>().authService));
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
        ChangeNotifierProvider(
          create: (_) => MultiplayerGameProvider(
            hapticService: ServiceLocator().get<IHapticService>(),
          ),
        ),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: Builder(
        builder: (context) {
          final isLoggedIn =
              context.select<AuthProvider, bool>((auth) => auth.isLoggedIn);
          final appTheme =
              context.select<SettingsProvider, AppTheme>((s) => s.appTheme);
          _initPush(context, isLoggedIn);
          // Créer le router une seule fois pour éviter de reset la navigation
          _router ??= AppRouter.createRouter(context);

          InAppNotificationService.instance.router = _router;

          return MaterialApp.router(
            routerConfig: _router!,
            title: 'Dutch Card Game',
            debugShowCheckedModeBanner: false,
            themeMode: appTheme.themeMode,
            theme: _buildLightTheme(),
            darkTheme: appTheme == AppTheme.green
                ? _buildGreenTheme()
                : _buildDarkTheme(),
            builder: (context, child) =>
                NotificationOverlayController(child: child ?? const SizedBox()),
          );
        },
      ),
    );
  }
}
