import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/providers/settings_provider.dart';
import 'package:dutch_game/services/multiplayer/multiplayer_service.dart';
import 'package:dutch_game/services/ui/emote_service.dart';
import 'package:dutch_game/widgets/dialogs/shared/unified_power_dialogs.dart';
import 'package:dutch_game/widgets/dialogs/presence_check_overlay.dart';
import 'package:dutch_game/widgets/dialogs/connection_error_dialog.dart';
import 'package:dutch_game/widgets/dialogs/emote_overlay.dart';
import 'package:dutch_game/widgets/dialogs/game/game_dialogs.dart';
import 'package:dutch_game/widgets/dialogs/multiplayer/multiplayer_dialogs.dart';
import 'package:dutch_game/widgets/multiplayer/game_overlays.dart';
import 'package:dutch_game/screens/shared/game_screen_mixin.dart';
import 'package:dutch_game/widgets/game/game_table_widget.dart';

class MultiplayerGameScreen extends StatefulWidget {
  const MultiplayerGameScreen({super.key});

  @override
  State<MultiplayerGameScreen> createState() => _MultiplayerGameScreenState();
}

class _MultiplayerGameScreenState extends State<MultiplayerGameScreen>
    with GameLayoutMixin<MultiplayerGameScreen>, GameScreenMixin<MultiplayerGameScreen> {
  StreamSubscription? _eventSubscription;
  StreamSubscription? _emoteSubscription;
  final List<Widget> _floatingEmotes = [];
  bool _showEmoteOverlay = false;
  bool _hostClosedDialogShown = false;
  bool _kickedDialogShown = false;
  bool _bannedDialogShown = false;
  String? _specialPowerReadyId;
  String? _specialPowerDialogShownId;

  @override
  void initState() {
    super.initState();
    resetEndGameNavigation(); // Reset guard on screen entry
    lockLandscapeOrientation();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupEventListeners();
      _setupEmoteListener();
    });
  }

  void _setupEmoteListener() {
    final provider = Provider.of<MultiplayerGameProvider>(context, listen: false);
    _emoteSubscription = provider.emoteStream.listen((emote) {
      if (!mounted) return;
      _showFloatingEmote(emote);
    });
  }

  final _random = math.Random();
  int _emoteIdCounter = 0;

  void _showFloatingEmote(EmoteEvent emote) {
    final screenSize = MediaQuery.of(context).size;
    final randomX = 100 + (screenSize.width - 300) * _random.nextDouble();
    final randomY = 100 + (screenSize.height - 300) * _random.nextDouble();
    final emoteId = _emoteIdCounter++;

    final floatingEmote = FloatingEmote(
      key: ValueKey('emote_$emoteId'),
      emoji: emote.emoji,
      playerName: emote.playerName,
      position: Offset(randomX, randomY),
      onComplete: () {
        if (mounted) {
          setState(() {
            _floatingEmotes.removeWhere((w) => w.key == ValueKey('emote_$emoteId'));
          });
        }
      },
    );

    setState(() {
      _floatingEmotes.add(floatingEmote);
    });
  }

  void _setupEventListeners() {
    final provider =
        Provider.of<MultiplayerGameProvider>(context, listen: false);
    _eventSubscription = provider.events.listen((event) {
      if (!mounted) return;

      // In game, we care about Player Left, Errors, Kicked (though kicked handles navigation)
      // and maybe Info. Joined is less relevant unless spectator?

      String? message;
      Color color = Colors.black87;
      IconData icon = Icons.info;

      switch (event.type) {
        case GameEventType.playerLeft:
          message = event.message;
          color = Colors.orange.shade800;
          icon = Icons.person_remove;
          break;
        case GameEventType.error:
          message = event.message;
          color = Colors.red.shade800;
          icon = Icons.error;
          break;
        case GameEventType.kicked:
          message = event.message;
          color = Colors.red.shade900;
          icon = Icons.block;
          break;
        case GameEventType.info:
          message = event.message;
          color = Colors.blue.shade800;
          break;
        default:
          break;
      }

      if (message != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(icon, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: color,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    unlockOrientation();
    _eventSubscription?.cancel();
    _emoteSubscription?.cancel();
    super.dispose();
  }

  void _tryNavigateToEnd(GameState gameState) {
    final routeLocation = gameState.dutchCallerId != null
        ? '/multiplayer/dutch-reveal'
        : '/multiplayer/results';
    maybeNavigateToEnd(gameState: gameState, routeLocation: routeLocation);
  }

  Map<String, bool> _buildConnectionMap(MultiplayerGameProvider gp) {
    final map = <String, bool>{};
    for (final player in gp.gameState?.players ?? []) {
      final presence = gp.presenceById[player.id];
      map[player.id] = presence == null || presence['connected'] == true;
    }
    return map;
  }

  Map<String, bool> _buildAfkMap(MultiplayerGameProvider gp, GameState gs) {
    final map = <String, bool>{};
    for (final player in gs.players) {
      map[player.id] = gp.isPlayerAfk(player.id);
    }
    return map;
  }

  bool _connectionErrorDialogShown = false;

  Future<void> _showConnectionErrorDialog(
    BuildContext context,
    MultiplayerGameProvider provider,
  ) async {
    if (_connectionErrorDialogShown) return;
    _connectionErrorDialogShown = true;

    await ConnectionErrorDialog.show(
      context,
      message: provider.errorMessage ?? 'Connexion perdue avec le serveur.',
      onRetry: () async {
        provider.clearError();
        final success = await provider.reconnect();
        if (!mounted) return;
        if (!success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Échec de la reconnexion'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      onReturnToMenu: () {
        provider.clearError();
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      },
    );

    _connectionErrorDialogShown = false;
  }

  @override
  Widget build(BuildContext context) {
    // Consume MultiplayerGameProvider
    return Consumer<MultiplayerGameProvider>(
      builder: (context, gameProvider, child) {
        final gameState = gameProvider.gameState;

        if (gameState == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF1a472a),
            body: Center(child: CircularProgressIndicator(color: Colors.amber)),
          );
        }

        // Handle Host Left
        if (gameProvider.roomClosedByHost && !_hostClosedDialogShown) {
          _hostClosedDialogShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ModalRoute.of(context)?.isCurrent == true && mounted) {
              MultiplayerDialogs.showHostClosedDialog(context);
            }
          });
          return const Scaffold(backgroundColor: Color(0xFF1a472a));
        }

        // Handle Disconnection
        if (gameProvider.connectionState ==
                SocketConnectionState.disconnected &&
            gameProvider.errorMessage != null &&
            gameProvider.errorMessage!.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ModalRoute.of(context)?.isCurrent == true && mounted) {
              _showConnectionErrorDialog(context, gameProvider);
            }
          });
        }

        // Handle Kicked (AFK or manually) - peut revenir
        if (gameProvider.wasKicked && !_kickedDialogShown) {
          _kickedDialogShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ModalRoute.of(context)?.isCurrent == true && mounted) {
              gameProvider.acknowledgeKicked();
              MultiplayerDialogs.showKickedDialog(context, gameProvider.kickedMessage);
            }
          });
          return const Scaffold(backgroundColor: Color(0xFF1a472a));
        }

        // Handle Banned - définitif
        if (gameProvider.wasBanned && !_bannedDialogShown) {
          _bannedDialogShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ModalRoute.of(context)?.isCurrent == true && mounted) {
              gameProvider.acknowledgeBanned();
              MultiplayerDialogs.showBannedDialog(context, gameProvider.bannedMessage);
            }
          });
          return const Scaffold(backgroundColor: Color(0xFF1a472a));
        }

        // Navigate if ended
        if (gameState.phase == GamePhase.ended) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _tryNavigateToEnd(gameState);
          });
        }

        // Check for Spied Card Dialog (pouvoir 7 ou 10)
        if (gameProvider.showSpiedCardDialog &&
            gameProvider.lastSpiedCard != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ModalRoute.of(context)?.isCurrent == true && mounted) {
              final targetName = gameProvider.spiedTargetName ?? 'Joueur';
              final title =
                  targetName == 'vous' ? 'VOTRE CARTE' : 'CARTE REVELEE';
              UnifiedPowerDialogs.showCardRevealDialog(
                      context, gameProvider.lastSpiedCard!, title: title)
                  .then((_) => gameProvider.closeSpiedCardDialog());
            }
          });
        }

        // Notification Valet : notre carte a ete echangee par un autre joueur
        if (gameProvider.pendingSwapNotification != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ModalRoute.of(context)?.isCurrent == true && mounted) {
              final data = gameProvider.pendingSwapNotification!;
              UnifiedPowerDialogs.showSwapNotificationDialog(
                context,
                data['byPlayerName'] ?? 'Un joueur',
                data['cardIndex'] ?? 0,
              );
              gameProvider.clearSwapNotification();
            }
          });
        }

        // Notification Joker : nos cartes ont ete melangees par un autre joueur
        if (gameProvider.pendingJokerNotification != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ModalRoute.of(context)?.isCurrent == true && mounted) {
              final data = gameProvider.pendingJokerNotification!;
              UnifiedPowerDialogs.showJokerNotificationDialog(
                context,
                data['byPlayerName'] ?? 'Un joueur',
              );
              gameProvider.clearJokerNotification();
            }
          });
        }

        // Notification Espionnage : quelqu'un regarde notre carte (pouvoir 10)
        if (gameProvider.pendingSpyNotification != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ModalRoute.of(context)?.isCurrent == true && mounted) {
              final data = gameProvider.pendingSpyNotification!;
              UnifiedPowerDialogs.showSpyNotificationDialog(
                context,
                data['byPlayerName'] ?? 'Un joueur',
                data['cardIndex'] ?? 0,
              );
              gameProvider.clearSpyNotification();
            }
          });
        }

        final size = MediaQuery.of(context).size;
        final isPortrait = size.height > size.width;

        if (kIsWeb && isPortrait) {
          return GameOverlays.rotateScreen();
        }

        return PopScope(
          onPopInvokedWithResult: (didPop, _) async {
            if (!didPop) {
              _showQuitConfirmation(context, gameProvider);
            }
          },
          child: Scaffold(
            backgroundColor: const Color(0xFF1a472a),
            body: Stack(
              children: [
                GameTableWidget(
                  gameState: gameState,
                  isProcessing: gameProvider.isProcessing,
                  shakingCardIndices: gameProvider.shakingCardIndices.toList(),
                  isSpectator: !gameState.players.any((p) => p.id == gameProvider.playerId && !p.isSpectator),
                  callbacks: GameTableCallbacks.fromController(
                    context: context,
                    controller: gameProvider,
                    onOpponentCardTap: (opponentIndex, cardIndex) => 
                        gameProvider.usePower10SpyOpponent(opponentIndex, cardIndex),
                    supportsTakeFromDiscard: true, // Multiplayer allows taking from discard
                  ),
                  onSpecialPowerAnimationComplete: (cardId) {
                    if (!mounted) return;
                    setState(() {
                      _specialPowerReadyId = cardId;
                      _specialPowerDialogShownId = null;
                    });
                  },
                  multiplayerConfig: MultiplayerConfig(
                    playerId: gameProvider.playerId,
                    playerConnections: _buildConnectionMap(gameProvider),
                    playerAfkStatus: _buildAfkMap(gameProvider, gameState),
                    turnStartTime: gameState.turnStartTime != null 
                        ? gameState.turnStartTime! - gameProvider.serverTimeOffsetMs 
                        : null,
                    turnDuration: gameState.turnTimeoutMs,
                    reactionTimeTotalMs: gameProvider.currentReactionTimeMs,
                  ),
                ),

                // Room Code and FPS/Status Overlay would go here if desired
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.videogame_asset,
                            color: Colors.white70, size: 16),
                        const SizedBox(width: 8),
                        Text("Room: ${gameProvider.roomCode ?? '?'}",
                            style: const TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),

                if (gameState.phase == GamePhase.dutchCalled)
                  GameOverlays.dutchNotification(),

                if (gameState.isWaitingForSpecialPower)
                  _buildSpecialPowerOverlay(gameProvider, gameState),

                if (gameProvider.isProcessing)
                  const Positioned(
                    top: 20,
                    right: 60,
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white54)),
                  ),

                // Notification: joueur a quitté
                if (gameProvider.playerLeftNotification)
                  GameOverlays.playerLeftBanner(gameProvider.lastPlayerLeftName),

                // Notification: pouvoir spécial utilisé sur nous
                if (gameProvider.specialPowerNotification)
                  GameOverlays.specialPowerBanner(gameProvider.specialPowerByName),

                // Boutons en haut à droite
                Positioned(
                  top: 10,
                  right: 10,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Bouton Émotes
                      IconButton(
                        icon: const Icon(Icons.emoji_emotions,
                            color: Colors.amber, size: 32),
                        onPressed: () {
                          setState(() {
                            _showEmoteOverlay = true;
                          });
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.pause_circle_filled,
                            color: Colors.white54, size: 32),
                        onPressed: () => gameProvider.pauseGame(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.exit_to_app,
                            color: Colors.white54, size: 32),
                        onPressed: () =>
                            _showQuitConfirmation(context, gameProvider),
                      ),
                    ],
                  ),
                ),

                // Indicateur de reconnexion silencieuse
                if (gameProvider.isSilentReconnecting)
                  GameOverlays.reconnectingBanner(),

                if (gameProvider.isPaused)
                  GameOverlays.pauseOverlay(
                    pausedByName: gameProvider.pausedByName,
                    onResume: gameProvider.resumeGame,
                  ),

                PresenceCheckOverlay(
                  active: gameProvider.presenceCheckActive,
                  deadlineMs: gameProvider.presenceCheckDeadlineMs,
                  reason: gameProvider.presenceCheckReason,
                  onConfirm: gameProvider.confirmPresence,
                ),

                // Émotes flottantes
                ..._floatingEmotes,

                // Overlay d'émotes
                if (_showEmoteOverlay)
                  EmoteOverlay(
                    onClose: () {
                      setState(() {
                        _showEmoteOverlay = false;
                      });
                    },
                    onEmoteSent: (emoji) {
                      gameProvider.sendEmote(emoji);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showQuitConfirmation(
      BuildContext context, MultiplayerGameProvider gp) async {
    final leave = await GameDialogs.confirmQuit(context);
    if (leave == true && mounted) {
      gp.forfeitGame();
      if (!context.mounted) return;
      context.go('/lobby');
    }
  }

  Widget _buildSpecialPowerOverlay(MultiplayerGameProvider gp, GameState gs) {
    // Vérifier si c'est à nous de jouer et si on attend un pouvoir spécial
    if (gs.specialCardToActivate == null) {
      _specialPowerReadyId = null;
      _specialPowerDialogShownId = null;
      return const SizedBox();
    }
    if (!gs.currentPlayer.isHuman) return const SizedBox();

    bool isMyTurn = gs.currentPlayer.id == gp.playerId;
    if (!isMyTurn) return const SizedBox();

    // Prevent re-showing if already processing
    if (gp.isProcessing) return const SizedBox();

    final animationsEnabled =
        context.watch<SettingsProvider>().animationsEnabled;

    final trigger = gs.specialCardToActivate!;
    final triggerId = trigger.id;

    if (!gs.isWaitingForSpecialPower) {
      _resetSpecialPowerState();
      return const SizedBox();
    }

    final ready = !animationsEnabled || _specialPowerReadyId == triggerId;
    if (!ready) {
      return const AbsorbPointer(
        child: SizedBox.expand(),
      );
    }

    if (_specialPowerDialogShownId != triggerId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final current = gp.gameState;
        if (current == null ||
            !current.isWaitingForSpecialPower ||
            current.specialCardToActivate?.id != triggerId) {
          return;
        }
        if (ModalRoute.of(context)?.isCurrent != true) return;
        _specialPowerDialogShownId = triggerId;
        final val = trigger.value;
        final config = PowerDialogConfig.multiplayer(context);
        if (val == '7') {
          UnifiedPowerDialogs.showPower7Dialog(context, trigger, config);
        } else if (val == '10') {
          UnifiedPowerDialogs.showPower10Dialog(context, trigger, config);
        } else if (val == 'V') {
          UnifiedPowerDialogs.showValetSwapDialog(context, trigger, config);
        } else if (val == 'JOKER') {
          UnifiedPowerDialogs.showJokerDialog(context, trigger, config);
        } else {
          gp.skipSpecialPower();
        }
      });
    }

    return Container(color: Colors.black54);
  }

  void _resetSpecialPowerState() {
    _specialPowerReadyId = null;
    _specialPowerDialogShownId = null;
  }

}
