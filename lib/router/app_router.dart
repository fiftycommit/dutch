import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/multiplayer_game_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/ui_constants.dart';
import '../screens/web_splash_helper.dart'
    if (dart.library.io) '../screens/web_splash_helper_stub.dart';
import '../services/web/web_session_storage.dart'
    if (dart.library.io) '../services/web/web_session_storage_stub.dart';

// ── Eager imports (critical path: splash → menu → solo game) ──
import '../screens/splash_screen.dart';
import '../screens/menu/main_menu_screen.dart';
import '../screens/menu/rules_screen.dart';
import '../screens/menu/settings_screen.dart';
import '../screens/menu/stats_screen.dart';
import '../screens/menu/ai_profile_screen.dart';
import '../screens/game/game_setup_screen.dart';
import '../screens/game/memorization_screen.dart';
import '../screens/game/game_screen.dart';
import '../screens/game/results_screen.dart';
import '../screens/game/dutch_reveal_screen.dart';

// ── Deferred imports (loaded on demand) ──
import '../screens/auth/login_screen.dart' deferred as login;
import '../screens/auth/forgot_password_screen.dart' deferred as forgot_pwd;
import '../screens/multiplayer/menu/multiplayer_menu_screen.dart'
    deferred as mp_menu;
import '../screens/multiplayer/menu/multiplayer_mode_selection_screen.dart'
    deferred as mp_mode;
import '../screens/multiplayer/menu/create_mode_selection_screen.dart'
    deferred as mp_create_mode;
import '../screens/multiplayer/menu/join_mode_selection_screen.dart'
    deferred as mp_join_mode;
import '../screens/multiplayer/lobby/create_private_room_screen.dart'
    deferred as mp_create_private;
import '../screens/multiplayer/lobby/create_public_room_screen.dart'
    deferred as mp_create_public;
import '../screens/multiplayer/lobby/join_private_room_screen.dart'
    deferred as mp_join_private;
import '../screens/multiplayer/lobby/public_matchmaking_screen.dart'
    deferred as mp_matchmaking;
import '../screens/multiplayer/lobby/multiplayer_lobby_screen.dart'
    deferred as mp_lobby;
import '../screens/multiplayer/game/multiplayer_memorization_screen.dart'
    deferred as mp_memo;
import '../screens/multiplayer/game/multiplayer_game_screen.dart'
    deferred as mp_game;
import '../screens/multiplayer/game/multiplayer_results_screen.dart'
    deferred as mp_results;
import '../screens/multiplayer/game/multiplayer_dutch_reveal_screen.dart'
    deferred as mp_dutch;
import '../screens/friends/friends_page.dart' deferred as friends_page;
import '../screens/friends/chat_page.dart' deferred as friends_chat;

/// Widget wrapper pour charger un module deferred avant d'afficher l'écran
class _DeferredScreen extends StatelessWidget {
  final Future<void> Function() loader;
  final Widget Function() builder;

  const _DeferredScreen({required this.loader, required this.builder});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: loader(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasError) {
            return Scaffold(
              backgroundColor: AppColors.gradientBottom,
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    const Text('Erreur de chargement',
                        style: TextStyle(color: Colors.white, fontSize: 18)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => context.go('/'),
                      child: const Text('Retour'),
                    ),
                  ],
                ),
              ),
            );
          }
          return builder();
        }
        return const Scaffold(
          backgroundColor: Color(0xFF1a472a),
          body: Center(
            child: CircularProgressIndicator(color: Colors.amber),
          ),
        );
      },
    );
  }
}

/// Configuration du routeur pour l'application
/// Permet d'avoir des URLs propres sur le web (ex: /room/ABC123)
class AppRouter {
  static String? currentLocation;
  static final GlobalKey<NavigatorState> _rootNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'root');

  /// Sur le web, indique si le splash a déjà été exécuté.
  static bool _webSplashDone = false;

  /// URL que l'utilisateur a demandée avant le splash (deep link).
  static String? _pendingDeepLink;

  /// Appelé par le SplashScreen une fois l'init terminée.
  static void markSplashDone() => _webSplashDone = true;

  /// Retourne le deep link en attente (et le consomme).
  static String? consumePendingDeepLink() {
    final link = _pendingDeepLink;
    _pendingDeepLink = null;
    return link;
  }

  /// Routes qui nécessitent un état en mémoire (provider/socket) et ne
  /// peuvent pas survivre à un reload web sans session restore.
  static const _statefulPrefixes = [
    '/lobby',
    '/solo/game',
    '/solo/memorization',
    '/solo/results',
    '/solo/dutch-reveal',
    '/multiplayer/game',
    '/multiplayer/memorization',
    '/multiplayer/results',
    '/multiplayer/dutch-reveal',
  ];

  /// Prefixes multiplayer que l'on peut restaurer via sessionStorage.
  static const _restorablePrefixes = [
    '/lobby',
    '/multiplayer/game',
    '/multiplayer/memorization',
    '/multiplayer/results',
    '/multiplayer/dutch-reveal',
  ];

  /// Mapping route → CSS background pour les safe areas iOS
  static const _defaultSafeBg = 'linear-gradient(to bottom, #0d2818, #1a472a)';
  static const _routeSafeBg = <String, String>{
    '/multiplayer/profile': '#0B1223',
  };

  static String _safeBgForLocation(String location) {
    for (final entry in _routeSafeBg.entries) {
      if (location.startsWith(entry.key)) return entry.value;
    }
    return _defaultSafeBg;
  }

  static Page<void> _adaptivePage({
    required GoRouterState state,
    required Widget child,
  }) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return CupertinoPage<void>(key: state.pageKey, child: child);
    }
    return MaterialPage<void>(key: state.pageKey, child: child);
  }

  static GoRouter createRouter(BuildContext context) {
    final router = GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: '/splash',
      debugLogDiagnostics: true,
      redirect: !kIsWeb
          ? null
          : (context, state) {
              final path = state.matchedLocation;

              // Déjà passé par le splash → sauvegarder la route courante.
              if (_webSplashDone) {
                final isRestorable = _restorablePrefixes
                    .any((prefix) => path.startsWith(prefix));
                WebSessionStorage.saveRoute(isRestorable ? path : null);
                return null;
              }

              // On est sur le splash → le laisser tourner.
              if (path == '/splash') return null;

              final needsState =
                  _statefulPrefixes.any((prefix) => path.startsWith(prefix));

              if (needsState) {
                // Tenter la restauration via sessionStorage.
                final isRestorable = _restorablePrefixes
                    .any((prefix) => path.startsWith(prefix));
                final savedRoom =
                    isRestorable ? WebSessionStorage.getRoomCode() : null;
                final savedRoute = WebSessionStorage.getRoute();

                if (savedRoom != null) {
                  // Skip le splash, rejoindre directement.
                  final targetRoute = savedRoute ?? path;
                  _webSplashDone = true;
                  WebSplashHelper.flutterReady();
                  WebSplashHelper.hideSplash();
                  return '/room/$savedRoom?restore=${Uri.encodeComponent(targetRoute)}';
                } else {
                  _pendingDeepLink = null;
                }
              } else {
                _pendingDeepLink = state.uri.toString();
              }

              return '/splash';
            },
      routes: [
        // ShellRoute pour envelopper toutes les pages avec SelectionArea
        // (nécessite d'être à l'intérieur du Navigator pour avoir accès à l'Overlay)
        ShellRoute(
          builder: (context, state, child) =>
              kIsWeb ? SelectionArea(child: child) : child,
          routes: [
            // ============ ÉCRAN DE CHARGEMENT ============
            GoRoute(
              path: '/splash',
              name: 'splash',
              builder: (context, state) => const SplashScreen(),
            ),

            // ============ MENU PRINCIPAL ============
            GoRoute(
              path: '/',
              name: 'home',
              pageBuilder: (context, state) {
                if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
                  return CupertinoPage<void>(
                    key: state.pageKey,
                    child: const MainMenuScreen(),
                  );
                }
                return CustomTransitionPage(
                  key: state.pageKey,
                  child: const MainMenuScreen(),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  transitionDuration: const Duration(milliseconds: 300),
                );
              },
            ),

            // ============ MODE SOLO ============
            // Route avec query parameters pour isTournament et saveSlot
            GoRoute(
              path: '/solo/setup',
              name: 'soloSetup',
              pageBuilder: (context, state) {
                final isTournament =
                    state.uri.queryParameters['tournament'] == 'true';
                final saveSlot =
                    int.tryParse(state.uri.queryParameters['slot'] ?? '0') ?? 0;
                return _adaptivePage(
                  state: state,
                  child: GameSetupScreen(
                    isTournament: isTournament,
                    saveSlot: saveSlot,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/solo/memorization',
              name: 'soloMemorization',
              builder: (context, state) => const MemorizationScreen(),
            ),
            GoRoute(
              path: '/solo/game',
              name: 'soloGame',
              builder: (context, state) => const GameScreen(),
            ),
            GoRoute(
              path: '/solo/results',
              name: 'soloResults',
              builder: (context, state) => const ResultsScreen(),
            ),
            GoRoute(
              path: '/solo/dutch-reveal',
              name: 'soloDutchReveal',
              builder: (context, state) => const DutchRevealScreen(),
            ),

            // ============ RÈGLES / SETTINGS / STATS / PROFIL IA ============
            GoRoute(
              path: '/rules',
              name: 'rules',
              pageBuilder: (context, state) => _adaptivePage(
                state: state,
                child: const RulesScreen(),
              ),
            ),
            GoRoute(
              path: '/settings',
              name: 'settings',
              pageBuilder: (context, state) {
                final slot =
                    int.tryParse(state.uri.queryParameters['slot'] ?? '1') ?? 1;
                return _adaptivePage(
                  state: state,
                  child: SettingsScreen(initialSlot: slot),
                );
              },
            ),
            GoRoute(
              path: '/stats',
              name: 'stats',
              pageBuilder: (context, state) {
                final slot =
                    int.tryParse(state.uri.queryParameters['slot'] ?? '1') ?? 1;
                return _adaptivePage(
                  state: state,
                  child: StatsScreen(initialSlot: slot),
                );
              },
            ),

            GoRoute(
              path: '/ai-profile',
              name: 'aiProfile',
              pageBuilder: (context, state) {
                final slot =
                    int.tryParse(state.uri.queryParameters['slot'] ?? '1') ?? 1;
                return _adaptivePage(
                  state: state,
                  child: AiProfileScreen(slotId: slot),
                );
              },
            ),

            // ============ AUTHENTIFICATION (deferred) ============
            GoRoute(
              path: '/login',
              name: 'login',
              pageBuilder: (context, state) => _adaptivePage(
                state: state,
                child: _DeferredScreen(
                  loader: login.loadLibrary,
                  builder: () => login.LoginScreen(),
                ),
              ),
            ),
            GoRoute(
              path: '/register',
              name: 'register',
              pageBuilder: (context, state) => _adaptivePage(
                state: state,
                child: _DeferredScreen(
                  loader: login.loadLibrary,
                  builder: () => login.LoginScreen(startWithRegister: true),
                ),
              ),
            ),
            GoRoute(
              path: '/forgot-password',
              name: 'forgotPassword',
              pageBuilder: (context, state) => _adaptivePage(
                state: state,
                child: _DeferredScreen(
                  loader: forgot_pwd.loadLibrary,
                  builder: () => forgot_pwd.ForgotPasswordScreen(),
                ),
              ),
            ),

            // ============ MODE MULTIJOUEUR (deferred) ============
            GoRoute(
              path: '/multiplayer',
              name: 'multiplayer',
              pageBuilder: (context, state) => _adaptivePage(
                state: state,
                child: _DeferredScreen(
                  loader: mp_menu.loadLibrary,
                  builder: () => mp_menu.MultiplayerMenuScreen(),
                ),
              ),
            ),

            // Sélection du mode (public/privé) - ancien écran gardé pour compatibilité
            GoRoute(
              path: '/multiplayer/mode-selection',
              name: 'multiplayerModeSelection',
              pageBuilder: (context, state) => _adaptivePage(
                state: state,
                child: _DeferredScreen(
                  loader: mp_mode.loadLibrary,
                  builder: () => mp_mode.MultiplayerModeSelectionScreen(),
                ),
              ),
            ),

            // Sélection pour créer un salon
            GoRoute(
              path: '/multiplayer/create-selection',
              name: 'createModeSelection',
              pageBuilder: (context, state) => _adaptivePage(
                state: state,
                child: _DeferredScreen(
                  loader: mp_create_mode.loadLibrary,
                  builder: () => mp_create_mode.CreateModeSelectionScreen(),
                ),
              ),
            ),

            // Sélection pour rejoindre un salon
            GoRoute(
              path: '/multiplayer/join-selection',
              name: 'joinModeSelection',
              pageBuilder: (context, state) => _adaptivePage(
                state: state,
                child: _DeferredScreen(
                  loader: mp_join_mode.loadLibrary,
                  builder: () => mp_join_mode.JoinModeSelectionScreen(),
                ),
              ),
            ),

            // Créer un salon privé
            GoRoute(
              path: '/multiplayer/create-private',
              name: 'createPrivateRoom',
              pageBuilder: (context, state) => _adaptivePage(
                state: state,
                child: _DeferredScreen(
                  loader: mp_create_private.loadLibrary,
                  builder: () => mp_create_private.CreatePrivateRoomScreen(),
                ),
              ),
            ),

            // Créer un salon public
            GoRoute(
              path: '/multiplayer/create-public',
              name: 'createPublicRoom',
              pageBuilder: (context, state) => _adaptivePage(
                state: state,
                child: _DeferredScreen(
                  loader: mp_create_public.loadLibrary,
                  builder: () => mp_create_public.CreatePublicRoomScreen(),
                ),
              ),
            ),

            // Rejoindre un salon privé (avec code)
            GoRoute(
              path: '/multiplayer/join-private',
              name: 'joinPrivateRoom',
              pageBuilder: (context, state) => _adaptivePage(
                state: state,
                child: _DeferredScreen(
                  loader: mp_join_private.loadLibrary,
                  builder: () => mp_join_private.JoinPrivateRoomScreen(),
                ),
              ),
            ),

            // Liste des salons publics
            GoRoute(
              path: '/multiplayer/matchmaking',
              name: 'publicMatchmaking',
              pageBuilder: (context, state) => _adaptivePage(
                state: state,
                child: _DeferredScreen(
                  loader: mp_matchmaking.loadLibrary,
                  builder: () => mp_matchmaking.PublicMatchmakingScreen(),
                ),
              ),
            ),

            // Route pour le salon (le roomCode est géré par le provider)
            GoRoute(
              path: '/lobby',
              name: 'lobby',
              pageBuilder: (context, state) => _adaptivePage(
                state: state,
                child: _DeferredScreen(
                  loader: mp_lobby.loadLibrary,
                  builder: () => mp_lobby.MultiplayerLobbyScreen(),
                ),
              ),
            ),

            // Route dynamique pour rejoindre une room via URL partagée
            // Ex: dutch-game.me/room/ABC123?name=Max
            GoRoute(
              path: '/room/:roomCode',
              name: 'room',
              builder: (context, state) {
                final roomCode = state.pathParameters['roomCode']!;
                final playerName =
                    state.uri.queryParameters['name'] ?? 'Joueur';
                final restoreRoute = state.uri.queryParameters['restore'];

                return _RoomJoinHandler(
                  roomCode: roomCode,
                  playerName: playerName,
                  restoreRoute: restoreRoute,
                );
              },
            ),

            // ============ AMIS (deferred) ============
            GoRoute(
              path: '/friends',
              name: 'friends',
              pageBuilder: (context, state) => _adaptivePage(
                state: state,
                child: _DeferredScreen(
                  loader: friends_page.loadLibrary,
                  builder: () => friends_page.FriendsPage(
                    initialTabIndex:
                        int.tryParse(state.uri.queryParameters['tab'] ?? '') ??
                            0,
                  ),
                ),
              ),
            ),
            GoRoute(
              path: '/friends/chat/:friendUserId',
              name: 'friendChat',
              pageBuilder: (context, state) => _adaptivePage(
                state: state,
                child: _DeferredScreen(
                  loader: friends_chat.loadLibrary,
                  builder: () => friends_chat.ChatPage(
                    friendUserId: state.pathParameters['friendUserId']!,
                    friendDisplayName: (state.extra as String?) ??
                        state.uri.queryParameters['name'] ??
                        '',
                  ),
                ),
              ),
            ),

            // Routes pour les phases de jeu multiplayer
            GoRoute(
              path: '/multiplayer/memorization',
              name: 'multiplayerMemorization',
              pageBuilder: (context, state) => _adaptivePage(
                state: state,
                child: _DeferredScreen(
                  loader: mp_memo.loadLibrary,
                  builder: () => mp_memo.MultiplayerMemorizationScreen(),
                ),
              ),
            ),
            GoRoute(
              path: '/multiplayer/game',
              name: 'multiplayerGame',
              pageBuilder: (context, state) => _adaptivePage(
                state: state,
                child: _DeferredScreen(
                  loader: mp_game.loadLibrary,
                  builder: () => mp_game.MultiplayerGameScreen(),
                ),
              ),
            ),
            GoRoute(
              path: '/multiplayer/results',
              name: 'multiplayerResults',
              pageBuilder: (context, state) {
                final gameProvider = Provider.of<MultiplayerGameProvider>(
                    context,
                    listen: false);
                final gs = gameProvider.gameState;
                if (gs == null) {
                  // gameState déjà nettoyé (joueur retourné au salon) → rediriger
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (context.mounted) {
                      context.go(gameProvider.roomCode != null
                          ? '/lobby'
                          : '/multiplayer');
                    }
                  });
                  return _adaptivePage(
                    state: state,
                    child: const Scaffold(body: SizedBox.shrink()),
                  );
                }
                return _adaptivePage(
                  state: state,
                  child: _DeferredScreen(
                    loader: mp_results.loadLibrary,
                    builder: () => mp_results.MultiplayerResultsScreen(
                      gameState: gs,
                      localPlayerId: gameProvider.playerId,
                    ),
                  ),
                );
              },
            ),
            GoRoute(
              path: '/multiplayer/dutch-reveal',
              name: 'multiplayerDutchReveal',
              pageBuilder: (context, state) => _adaptivePage(
                state: state,
                child: _DeferredScreen(
                  loader: mp_dutch.loadLibrary,
                  builder: () => mp_dutch.MultiplayerDutchRevealScreen(),
                ),
              ),
            ),
          ],
        ),
      ],

      // Gestion des erreurs de navigation
      errorBuilder: (context, state) => Scaffold(
        backgroundColor: AppColors.gradientBottom,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 64),
              const SizedBox(height: 16),
              Text(
                'Page non trouvée',
                style: Theme.of(context)
                    .textTheme
                    .headlineLarge
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                state.uri.toString(),
                style: const TextStyle(color: AppColors.textDisabled),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('Retour au menu'),
              ),
            ],
          ),
        ),
      ),
    );

    router.routerDelegate.addListener(() {
      final location = router.routerDelegate.currentConfiguration.uri.path;
      currentLocation = location;
      if (kIsWeb) {
        WebSplashHelper.setSafeAreaBackground(_safeBgForLocation(location));
      }
    });

    return router;
  }
}

/// Widget intermédiaire pour gérer la connexion à une room via URL
class _RoomJoinHandler extends StatefulWidget {
  final String roomCode;
  final String playerName;
  final String? restoreRoute;

  const _RoomJoinHandler({
    required this.roomCode,
    required this.playerName,
    this.restoreRoute,
  });

  @override
  State<_RoomJoinHandler> createState() => _RoomJoinHandlerState();
}

class _RoomJoinHandlerState extends State<_RoomJoinHandler> {
  bool _isJoining = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _joinRoom());
  }

  Future<void> _joinRoom() async {
    try {
      final provider = Provider.of<MultiplayerGameProvider>(
        context,
        listen: false,
      );

      final target = widget.restoreRoute ?? '/lobby';

      // Si déjà dans cette room, aller directement à la destination
      if (provider.roomCode == widget.roomCode) {
        if (mounted) context.go(target);
        return;
      }

      // Initialiser l'auth et passer le token au multiplayer service
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (!authProvider.isInitialized) {
        await authProvider.init();
      }
      final token = await authProvider.getFreshToken();
      if (token == null) {
        throw Exception('Authentification requise');
      }
      provider.setAuthToken(token);
      await provider.init();

      // Attendre que le socket soit connecté (max 5s)
      for (var i = 0; i < 50; i++) {
        if (provider.isConnected) break;
        await Future.delayed(const Duration(milliseconds: 100));
        if (!mounted) return;
      }

      await provider.joinRoom(
        roomCode: widget.roomCode,
        playerName: widget.playerName,
      );

      if (mounted) context.go(target);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isJoining = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gradientBottom,
      body: Center(
        child: _isJoining
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.amber),
                  const SizedBox(height: 24),
                  Text(
                    'Connexion à la room ${widget.roomCode}...',
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Impossible de rejoindre',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error ?? 'Erreur inconnue',
                    style: const TextStyle(color: AppColors.textDisabled),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Retour au menu'),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Extension pour faciliter la navigation avec les routes nommées
extension GoRouterNavigation on BuildContext {
  // Menu principal
  void goHome() => go('/');

  // Solo
  void goSoloSetup({bool isTournament = false, int saveSlot = 0}) =>
      go('/solo/setup?tournament=$isTournament&slot=$saveSlot');
  void goSoloMemorization() => go('/solo/memorization');
  void goSoloGame() => go('/solo/game');
  void goSoloResults() => go('/solo/results');
  void goSoloDutchReveal() => go('/solo/dutch-reveal');

  // Auth
  void goLogin() => go('/login');
  void goRegister() => go('/register');
  void goForgotPassword() => go('/forgot-password');

  // Multiplayer
  void goMultiplayer() => go('/multiplayer');
  void goMultiplayerModeSelection() => go('/multiplayer/mode-selection');
  void goCreatePublicRoom() => go('/multiplayer/create-public');
  void goPublicMatchmaking() => go('/multiplayer/matchmaking');
  void goLobby() => go('/lobby');
  void goMultiplayerMemorization() => go('/multiplayer/memorization');
  void goMultiplayerGame() => go('/multiplayer/game');
  void goMultiplayerResults() => go('/multiplayer/results');
  void goMultiplayerDutchReveal() => go('/multiplayer/dutch-reveal');

  // Autres
  void goRules() => go('/rules');
  void goSettings() => go('/settings');
  void goStats() => go('/stats');

  // Rejoindre une room via URL
  void goToRoom(String roomCode, {String? playerName}) =>
      go('/room/$roomCode${playerName != null ? '?name=$playerName' : ''}');
}
