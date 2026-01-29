import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/multiplayer_game_provider.dart';
import '../screens/splash_screen.dart';
import '../screens/main_menu_screen.dart';
import '../screens/game_setup_screen.dart';
import '../screens/memorization_screen.dart';
import '../screens/game_screen.dart';
import '../screens/results_screen.dart';
import '../screens/dutch_reveal_screen.dart';
import '../screens/rules_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/stats_screen.dart';
import '../screens/multiplayer_menu_screen.dart';
import '../screens/multiplayer_lobby_screen.dart';
import '../screens/multiplayer_memorization_screen.dart';
import '../screens/multiplayer_game_screen.dart';
import '../screens/multiplayer_results_screen.dart';
import '../screens/multiplayer_dutch_reveal_screen.dart';

/// Configuration du routeur pour l'application
/// Permet d'avoir des URLs propres sur le web (ex: /room/ABC123)
class AppRouter {
  static final GlobalKey<NavigatorState> _rootNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'root');

  static GoRouter createRouter(BuildContext context) {
    return GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: '/splash',
      debugLogDiagnostics: true,
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
          builder: (context, state) => const MainMenuScreen(),
        ),

        // ============ MODE SOLO ============
        // Route avec query parameters pour isTournament et saveSlot
        GoRoute(
          path: '/solo/setup',
          name: 'soloSetup',
          builder: (context, state) {
            final isTournament =
                state.uri.queryParameters['tournament'] == 'true';
            final saveSlot =
                int.tryParse(state.uri.queryParameters['slot'] ?? '0') ?? 0;
            return GameSetupScreen(
              isTournament: isTournament,
              saveSlot: saveSlot,
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

        // ============ RÈGLES / SETTINGS / STATS ============
        GoRoute(
          path: '/rules',
          name: 'rules',
          builder: (context, state) => const RulesScreen(),
        ),
        GoRoute(
          path: '/settings',
          name: 'settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/stats',
          name: 'stats',
          builder: (context, state) => const StatsScreen(),
        ),

        // ============ MODE MULTIJOUEUR ============
        GoRoute(
          path: '/multiplayer',
          name: 'multiplayer',
          builder: (context, state) => const MultiplayerMenuScreen(),
        ),

        // Route pour le lobby (le roomCode est géré par le provider)
        GoRoute(
          path: '/lobby',
          name: 'lobby',
          builder: (context, state) => const MultiplayerLobbyScreen(),
        ),

        // Route dynamique pour rejoindre une room via URL partagée
        // Ex: dutch-game.me/room/ABC123?name=Max
        GoRoute(
          path: '/room/:roomCode',
          name: 'room',
          builder: (context, state) {
            final roomCode = state.pathParameters['roomCode']!;
            final playerName = state.uri.queryParameters['name'] ?? 'Joueur';

            // On utilise un widget intermédiaire pour gérer la connexion
            return _RoomJoinHandler(
              roomCode: roomCode,
              playerName: playerName,
            );
          },
        ),

        // Routes pour les phases de jeu multiplayer
        GoRoute(
          path: '/multiplayer/memorization',
          name: 'multiplayerMemorization',
          builder: (context, state) => const MultiplayerMemorizationScreen(),
        ),
        GoRoute(
          path: '/multiplayer/game',
          name: 'multiplayerGame',
          builder: (context, state) => const MultiplayerGameScreen(),
        ),
        GoRoute(
          path: '/multiplayer/results',
          name: 'multiplayerResults',
          builder: (context, state) {
            final gameProvider =
                Provider.of<MultiplayerGameProvider>(context, listen: false);
            return MultiplayerResultsScreen(
              gameState: gameProvider.gameState!,
              localPlayerId: gameProvider.playerId,
            );
          },
        ),
        GoRoute(
          path: '/multiplayer/dutch-reveal',
          name: 'multiplayerDutchReveal',
          builder: (context, state) => const MultiplayerDutchRevealScreen(),
        ),
      ],

      // Gestion des erreurs de navigation
      errorBuilder: (context, state) => Scaffold(
        backgroundColor: const Color(0xFF1a472a),
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
                style: const TextStyle(color: Colors.white54),
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
  }
}

/// Widget intermédiaire pour gérer la connexion à une room via URL
class _RoomJoinHandler extends StatefulWidget {
  final String roomCode;
  final String playerName;

  const _RoomJoinHandler({
    required this.roomCode,
    required this.playerName,
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
    _joinRoom();
  }

  Future<void> _joinRoom() async {
    try {
      final provider = Provider.of<MultiplayerGameProvider>(
        context,
        listen: false,
      );

      // Si déjà dans cette room, aller directement au lobby
      if (provider.roomCode == widget.roomCode) {
        if (mounted) context.go('/lobby');
        return;
      }

      await provider.joinRoom(
        roomCode: widget.roomCode,
        playerName: widget.playerName,
      );

      if (mounted) context.go('/lobby');
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
      backgroundColor: const Color(0xFF1a472a),
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
                    style: const TextStyle(color: Colors.white54),
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

  // Multiplayer
  void goMultiplayer() => go('/multiplayer');
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
