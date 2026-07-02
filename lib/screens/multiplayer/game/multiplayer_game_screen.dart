import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show kIsWeb, listEquals, mapEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/providers/multiplayer_game_provider.dart';
import 'package:dutch_game/providers/settings_provider.dart';
import 'package:dutch_game/services/multiplayer/multiplayer_service.dart';
import 'package:dutch_game/services/ui/emote_service.dart';
import 'package:dutch_game/utils/ui_constants.dart';
import 'package:dutch_game/widgets/dialogs/shared/unified_power_dialogs.dart';
import 'package:dutch_game/widgets/dialogs/shared/power_lottery_dialog.dart';
import 'package:dutch_game/widgets/dialogs/presence_check_overlay.dart';
import 'package:dutch_game/widgets/dialogs/connection_error_dialog.dart';
import 'package:dutch_game/widgets/dialogs/emote_overlay.dart';
import 'package:dutch_game/widgets/dialogs/game/game_dialogs.dart';
import 'package:dutch_game/widgets/dialogs/multiplayer/multiplayer_dialogs.dart';
import 'package:dutch_game/widgets/multiplayer/game_overlays.dart';
import 'package:dutch_game/screens/shared/game_screen_mixin.dart';
import 'package:dutch_game/widgets/game/game_table_widget.dart';
import 'package:dutch_game/utils/tournament_labels.dart';
import 'package:dutch_game/utils/rebuild_probe.dart';
import 'package:dutch_game/services/platform/wake_lock_service.dart';

class MultiplayerGameScreen extends StatefulWidget {
  const MultiplayerGameScreen({super.key});

  @override
  State<MultiplayerGameScreen> createState() => _MultiplayerGameScreenState();
}

class _MultiplayerGameScreenState extends State<MultiplayerGameScreen>
    with
        GameLayoutMixin<MultiplayerGameScreen>,
        GameScreenMixin<MultiplayerGameScreen> {
  StreamSubscription? _eventSubscription;
  StreamSubscription? _emoteSubscription;
  final List<Widget> _floatingEmotes = [];
  bool _showEmoteOverlay = false;
  bool _hostClosedDialogShown = false;
  bool _kickedDialogShown = false;
  bool _bannedDialogShown = false;
  bool _spiedCardDialogShown = false;
  String? _specialPowerReadyId;
  String? _specialPowerDialogShownId;
  MultiplayerGameProvider? _cachedProvider;
  bool _wasPausedLastFrame = false;
  bool _pauseDialogShown = false;
  String? _lotteryDialogShownId;

  @override
  void initState() {
    super.initState();
    resetEndGameNavigation(); // Reset guard on screen entry
    lockLandscapeOrientation(autoFullscreenOnWeb: false);
    WakeLockService.instance.enable();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupEventListeners();
      _setupEmoteListener();
      _setupProviderListener();
    });
  }

  void _setupProviderListener() {
    _cachedProvider =
        Provider.of<MultiplayerGameProvider>(context, listen: false);
    _cachedProvider!.addListener(_onProviderChanged);
  }

  void _onProviderChanged() {
    if (!mounted) return;
    final provider =
        Provider.of<MultiplayerGameProvider>(context, listen: false);
    final gameState = provider.gameState;

    // Safety: room destroyed or we were removed → exit game screen
    // Ne pas interférer si un dialog de kick/ban/host-closed est déjà affiché
    if (provider.roomCode == null &&
        !_kickedDialogShown &&
        !_bannedDialogShown &&
        !_hostClosedDialogShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          context.go('/multiplayer');
        }
      });
      return;
    }

    // Safety: gameState null but we're in lobby (room restarted) → go to lobby
    if (gameState == null && provider.isInLobby) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          context.go('/lobby');
        }
      });
      return;
    }

    if (gameState == null) return;

    // Fermer le dialog de loterie si les pendingMatchPowers ont été consommés
    if (_lotteryDialogShownId != null &&
        (gameState.pendingMatchPowers.isEmpty ||
            gameState.phase == GamePhase.specialPower)) {
      _lotteryDialogShownId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent != true) {
          // Un dialog (la loterie) est ouvert par-dessus, le fermer
          Navigator.of(context, rootNavigator: true).pop();
        }
      });
    }

    // Handle Host Left
    if (provider.roomClosedByHost && !_hostClosedDialogShown) {
      _hostClosedDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ModalRoute.of(context)?.isCurrent == true && mounted) {
          MultiplayerDialogs.showHostClosedDialog(context);
        }
      });
    }

    // Handle Disconnection
    if (provider.connectionState == SocketConnectionState.disconnected &&
        provider.errorMessage != null &&
        provider.errorMessage!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ModalRoute.of(context)?.isCurrent == true && mounted) {
          _showConnectionErrorDialog(context, provider);
        }
      });
    }

    // Handle Kicked (AFK or manually)
    if (provider.wasKicked && !_kickedDialogShown) {
      _kickedDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ModalRoute.of(context)?.isCurrent == true && mounted) {
          provider.acknowledgeKicked();
          MultiplayerDialogs.showKickedDialog(context, provider.kickedMessage);
        }
      });
    }

    // Handle Banned
    if (provider.wasBanned && !_bannedDialogShown) {
      _bannedDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ModalRoute.of(context)?.isCurrent == true && mounted) {
          provider.acknowledgeBanned();
          MultiplayerDialogs.showBannedDialog(context, provider.bannedMessage);
        }
      });
    }

    // Navigate if ended
    if (gameState.phase == GamePhase.ended) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tryNavigateToEnd(gameState);
      });
    }

    // Check for Spied Card Dialog (pouvoir 7 ou 10)
    if (provider.showSpiedCardDialog &&
        provider.lastSpiedCard != null &&
        !_spiedCardDialogShown) {
      _spiedCardDialogShown = true;
      final spiedCard = provider.lastSpiedCard!;
      final targetName = provider.spiedTargetName ?? 'Joueur';

      WidgetsBinding.instance.addPostFrameCallback((_) {
        provider.closeSpiedCardDialog();
        _spiedCardDialogShown = false;

        if (ModalRoute.of(context)?.isCurrent == true && mounted) {
          final title = targetName == 'vous' ? 'VOTRE CARTE' : 'CARTE REVELEE';
          UnifiedPowerDialogs.showCardRevealDialog(context, spiedCard,
              title: title);
        }
      });
    }

    // Notification Valet : notre carte a ete echangee par un autre joueur
    if (provider.pendingSwapNotification != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (ModalRoute.of(context)?.isCurrent == true && mounted) {
          final data = provider.pendingSwapNotification!;
          provider.clearSwapNotification();
          await UnifiedPowerDialogs.showSwapNotificationDialog(
            context,
            data['byPlayerName'] ?? 'Un joueur',
            data['cardIndex'] ?? 0,
            swapPartnerName: data['swapPartnerName'],
            receivedCardPosition: data['receivedCardPosition'],
            autoCloseSeconds: 15,
            onTimeout: () => provider.triggerPowerTimeoutKick(),
          );
        }
      });
    }

    // Notification Joker : nos cartes ont ete melangees par un autre joueur
    if (provider.pendingJokerNotification != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (ModalRoute.of(context)?.isCurrent == true && mounted) {
          final data = provider.pendingJokerNotification!;
          provider.clearJokerNotification();
          await UnifiedPowerDialogs.showJokerNotificationDialog(
            context,
            data['byPlayerName'] ?? 'Un joueur',
            autoCloseSeconds: 15,
            onTimeout: () => provider.triggerPowerTimeoutKick(),
          );
        }
      });
    }

    // Notification Espionnage : quelqu'un regarde notre carte (pouvoir 10)
    if (provider.pendingSpyNotification != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (ModalRoute.of(context)?.isCurrent == true && mounted) {
          final data = provider.pendingSpyNotification!;
          provider.clearSpyNotification();
          await UnifiedPowerDialogs.showSpyNotificationDialog(
            context,
            data['byPlayerName'] ?? 'Un joueur',
            data['cardIndex'] ?? 0,
            autoCloseSeconds: 15,
            onTimeout: () => provider.triggerPowerTimeoutKick(),
          );
        }
      });
    }

    // ── Pause overlay au-dessus des dialogs de pouvoir ──
    // Quand isPaused passe à true et qu'un dialog de pouvoir est ouvert,
    // on affiche un showDialog supplémentaire par-dessus pour bloquer les
    // interactions et signaler visuellement la pause.
    final isPaused = provider.isPaused;
    if (isPaused &&
        !_wasPausedLastFrame &&
        _specialPowerDialogShownId != null) {
      if (!_pauseDialogShown) {
        _pauseDialogShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !provider.isPaused) {
            _pauseDialogShown = false;
            return;
          }
          showDialog(
            context: context,
            barrierDismissible: false,
            barrierColor: Colors.transparent,
            builder: (_) => PopScope(
              canPop: false,
              child: GameOverlays.pauseOverlay(
                pausedByName: provider.pausedByName,
                onResume: provider.resumeGame,
                isLocalPauser: provider.isLocalPauser,
                pauseDeadlineMs: provider.pauseDeadlineMs,
              ),
            ),
          );
        });
      }
    }
    if (!isPaused && _wasPausedLastFrame && _pauseDialogShown) {
      _pauseDialogShown = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Retirer le dialog de pause empilé
          Navigator.of(context, rootNavigator: true).pop();
        }
      });
    }
    _wasPausedLastFrame = isPaused;
  }

  void _setupEmoteListener() {
    final provider =
        Provider.of<MultiplayerGameProvider>(context, listen: false);
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
            _floatingEmotes
                .removeWhere((w) => w.key == ValueKey('emote_$emoteId'));
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
          color = MultiplayerColors.warning;
          icon = Icons.person_remove;
          break;
        case GameEventType.error:
          message = event.message;
          color = MultiplayerColors.danger;
          icon = Icons.error;
          break;
        case GameEventType.kicked:
          message = event.message;
          color = MultiplayerColors.kicked;
          icon = Icons.block;
          break;
        case GameEventType.info:
          message = event.message;
          color = MultiplayerColors.info;
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
    _cachedProvider?.removeListener(_onProviderChanged);
    unlockOrientation();
    WakeLockService.instance.disable();
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
    return PopScope(
      canPop: false,
      child: Selector<MultiplayerGameProvider, _MultiplayerGameScreenModel>(
        selector: (_, gameProvider) =>
            _MultiplayerGameScreenModel.from(gameProvider),
        builder: (context, model, child) {
          RebuildProbe.bump('screen_body');
          final gameProvider = context.read<MultiplayerGameProvider>();
          final gameState = model.gameState;

          if (gameState == null) {
            return const Scaffold(
              backgroundColor: AppColors.gradientBottom,
              body: Center(
                  child:
                      CircularProgressIndicator(color: AppColors.textPrimary)),
            );
          }

          // Early returns pour états bloquants (dialogs déclenchés par le listener)
          if (model.roomClosedByHost && _hostClosedDialogShown) {
            return Scaffold(backgroundColor: AppColors.gradientBottom);
          }
          if (model.wasKicked && _kickedDialogShown) {
            return Scaffold(backgroundColor: AppColors.gradientBottom);
          }
          if (model.wasBanned && _bannedDialogShown) {
            return Scaffold(backgroundColor: AppColors.gradientBottom);
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
            child: GamePauseScope(
              isPaused: model.isPaused,
              child: Scaffold(
                backgroundColor: AppColors.gradientBottom,
                body: Stack(
                  children: [
                    GameTableWidget(
                      gameState: gameState,
                      isProcessing: model.isProcessing,
                      shakingCardIndices: model.shakingCardIndices,
                      isSpectator: !gameState.players
                          .any((p) => p.id == model.playerId && !p.isSpectator),
                      callbacks: GameTableCallbacks.fromController(
                        context: context,
                        controller: gameProvider,
                        onOpponentCardTap: (opponentIndex, cardIndex) {
                          gameProvider.sendSpecialPowerTargetSelection(
                              opponentIndex, null, null, null);
                          gameProvider.usePower10SpyOpponent(
                              opponentIndex, cardIndex);
                        },
                      ),
                      onSpecialPowerAnimationComplete: (cardId) {
                        if (!mounted) return;
                        setState(() {
                          _specialPowerReadyId = cardId;
                          _specialPowerDialogShownId = null;
                        });
                      },
                      multiplayerConfig: MultiplayerConfig(
                        playerId: model.playerId,
                        playerConnections: model.playerConnections,
                        playerAfkStatus: model.playerAfkStatus,
                        turnStartTime: gameState.turnStartTime != null
                            ? gameState.turnStartTime! -
                                model.serverTimeOffsetMs
                            : null,
                        turnDuration: gameState.turnTimeoutMs,
                        reactionTimeTotalMs: model.currentReactionTimeMs,
                        powerTargetPlayerIds: model.powerTargetPlayerIds,
                      ),
                      isPaused: model.isPaused,
                    ),

                    // Room Code and Tournament Info Overlay
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(20)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  gameState.gameMode == GameMode.tournament
                                      ? Icons.emoji_events
                                      : Icons.videogame_asset,
                                  color:
                                      gameState.gameMode == GameMode.tournament
                                          ? Colors.amber
                                          : AppColors.textSecondary,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  gameState.gameMode == GameMode.tournament
                                      ? tournamentStageLabel(
                                          gameState.tournamentRound,
                                          totalRounds:
                                              model.tournamentTotalRounds,
                                        )
                                      // Masquer le code pour les parties publiques
                                      : (model.isPublicRoom == true
                                          ? "Partie publique"
                                          : "Room: ${model.roomCode ?? '?'}"),
                                  style: const TextStyle(
                                    color: Colors.amber,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            if (gameState.gameMode == GameMode.tournament) ...[
                              const SizedBox(height: 2),
                              Text(
                                "Manches restantes : ${(model.tournamentTotalRounds - gameState.tournamentRound).clamp(0, 99)}",
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    if (gameState.phase == GamePhase.dutchCalled)
                      GameOverlays.dutchNotification(),

                    if (gameState.pendingMatchPowers.length >= 2 &&
                        gameState.pendingMatchPowers.first.drawNumber != null)
                      _buildPowerLotteryOverlay(gameProvider, gameState),

                    if (gameState.phase == GamePhase.specialPower)
                      _buildSpecialPowerOverlay(gameProvider, gameState),

                    if (model.isProcessing)
                      const Positioned(
                        top: 20,
                        right: 60,
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.textDisabled)),
                      ),

                    // Notification: joueur a quitté
                    if (model.playerLeftNotification)
                      GameOverlays.playerLeftBanner(model.lastPlayerLeftName),

                    // Notification: pouvoir spécial utilisé sur nous
                    if (model.specialPowerNotification)
                      GameOverlays.specialPowerBanner(model.specialPowerByName),

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
                                color: AppColors.textDisabled, size: 32),
                            onPressed: () => gameProvider.pauseGame(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.exit_to_app,
                                color: AppColors.textDisabled, size: 32),
                            onPressed: () =>
                                _showQuitConfirmation(context, gameProvider),
                          ),
                        ],
                      ),
                    ),

                    // Indicateur de reconnexion silencieuse
                    if (model.isSilentReconnecting)
                      GameOverlays.reconnectingBanner(),

                    if (model.isPaused)
                      GameOverlays.pauseOverlay(
                        pausedByName: model.pausedByName,
                        onResume: gameProvider.resumeGame,
                        isLocalPauser: model.isLocalPauser,
                        pauseDeadlineMs: model.pauseDeadlineMs,
                      ),

                    PresenceCheckOverlay(
                      active: model.presenceCheckActive,
                      deadlineMs: model.presenceCheckDeadlineMs,
                      reason: model.presenceCheckReason,
                      onConfirm: gameProvider.confirmPresence,
                      onAbandon: () {
                        gameProvider.confirmPresence(); // Clear the check first
                        gameProvider.forfeitGame();
                        // Don't navigate to /lobby - stay as spectator.
                        // The game will end and navigate to results automatically.
                      },
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
            ),
          );
        },
      ),
    );
  }

  Future<void> _showQuitConfirmation(
      BuildContext context, MultiplayerGameProvider gp) async {
    final leave = await GameDialogs.confirmQuit(context);
    if (leave == true && mounted) {
      gp.forfeitGame();
      // Don't navigate to /lobby - stay as spectator.
      // The game will end and navigate to results automatically.
    }
  }

  Widget _buildSpecialPowerOverlay(MultiplayerGameProvider gp, GameState gs) {
    // Vérifier si c'est à nous de jouer et si on attend un pouvoir spécial
    if (gs.specialCardToActivate == null) {
      _specialPowerReadyId = null;
      _specialPowerDialogShownId = null;
      return const SizedBox();
    }

    // Autoriser le joueur pouvoiré (match power) ou le joueur actif (normal)
    final isMyPower = gs.specialPowerPlayerId != null
        ? gs.specialPowerPlayerId == gp.playerId
        : gs.currentPlayer.id == gp.playerId;
    if (!isMyPower) return const SizedBox();

    // Prevent re-showing if already processing
    if (gp.isProcessing) return const SizedBox();

    final animationsEnabled =
        context.watch<SettingsProvider>().animationsEnabled;

    final trigger = gs.specialCardToActivate!;
    final triggerId = trigger.id;

    if (gs.phase != GamePhase.specialPower) {
      _resetSpecialPowerState();
      return const SizedBox();
    }

    // Pour un match power, pas d'animation de carte à attendre
    final isMatchPower = gs.specialPowerPlayerId != null;
    final ready =
        isMatchPower || !animationsEnabled || _specialPowerReadyId == triggerId;
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
            current.phase != GamePhase.specialPower ||
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

  Widget _buildPowerLotteryOverlay(MultiplayerGameProvider gp, GameState gs) {
    final lotteryId = gs.pendingMatchPowers.map((p) => p.playerId).join('_');
    if (_lotteryDialogShownId != lotteryId) {
      _lotteryDialogShownId = lotteryId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Vérifier que les pendingMatchPowers sont toujours présents
        final current = gp.gameState;
        if (current == null || current.pendingMatchPowers.isEmpty) return;
        PowerLotteryDialog.show(
          context,
          pendingPowers: current.pendingMatchPowers,
          localPlayerId: gp.playerId,
          onComplete: () {
            _lotteryDialogShownId = null;
            // En multijoueur le serveur gère la suite, rien à faire côté client
          },
        );
      });
    }
    return Container(color: Colors.black54);
  }

  void _resetSpecialPowerState() {
    _specialPowerReadyId = null;
    _specialPowerDialogShownId = null;
    // Si le dialog de pause était empilé au-dessus d'un dialog de pouvoir,
    // le retirer lorsque le pouvoir se termine.
    if (_pauseDialogShown) {
      _pauseDialogShown = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      });
    }
  }
}

class _MultiplayerGameScreenModel {
  final GameState? gameState;
  final bool roomClosedByHost;
  final bool wasKicked;
  final bool wasBanned;
  final bool isProcessing;
  final List<int> shakingCardIndices;
  final String? playerId;
  final Map<String, bool> playerConnections;
  final Map<String, bool> playerAfkStatus;
  final int serverTimeOffsetMs;
  final int currentReactionTimeMs;
  final Set<String> powerTargetPlayerIds;
  final bool isPaused;
  final String? pausedByName;
  final bool isLocalPauser;
  final int pauseDeadlineMs;
  final int tournamentTotalRounds;
  final bool? isPublicRoom;
  final String? roomCode;
  final bool playerLeftNotification;
  final String? lastPlayerLeftName;
  final bool specialPowerNotification;
  final String? specialPowerByName;
  final bool isSilentReconnecting;
  final bool presenceCheckActive;
  final int presenceCheckDeadlineMs;
  final String? presenceCheckReason;

  const _MultiplayerGameScreenModel({
    required this.gameState,
    required this.roomClosedByHost,
    required this.wasKicked,
    required this.wasBanned,
    required this.isProcessing,
    required this.shakingCardIndices,
    required this.playerId,
    required this.playerConnections,
    required this.playerAfkStatus,
    required this.serverTimeOffsetMs,
    required this.currentReactionTimeMs,
    required this.powerTargetPlayerIds,
    required this.isPaused,
    required this.pausedByName,
    required this.isLocalPauser,
    required this.pauseDeadlineMs,
    required this.tournamentTotalRounds,
    required this.isPublicRoom,
    required this.roomCode,
    required this.playerLeftNotification,
    required this.lastPlayerLeftName,
    required this.specialPowerNotification,
    required this.specialPowerByName,
    required this.isSilentReconnecting,
    required this.presenceCheckActive,
    required this.presenceCheckDeadlineMs,
    required this.presenceCheckReason,
  });

  factory _MultiplayerGameScreenModel.from(MultiplayerGameProvider provider) {
    final gameState = provider.gameState;
    final shakingCardIndices = provider.shakingCardIndices.toList()..sort();
    final powerTargetPlayerIds = provider.powerTargetPlayerIds;

    return _MultiplayerGameScreenModel(
      gameState: gameState,
      roomClosedByHost: provider.roomClosedByHost,
      wasKicked: provider.wasKicked,
      wasBanned: provider.wasBanned,
      isProcessing: provider.isProcessing,
      shakingCardIndices: shakingCardIndices,
      playerId: provider.playerId,
      playerConnections: _buildConnectionMap(provider, gameState),
      playerAfkStatus: _buildAfkMap(provider, gameState),
      serverTimeOffsetMs: provider.serverTimeOffsetMs,
      currentReactionTimeMs: provider.currentReactionTimeMs,
      powerTargetPlayerIds: powerTargetPlayerIds,
      isPaused: provider.isPaused,
      pausedByName: provider.pausedByName,
      isLocalPauser: provider.isLocalPauser,
      pauseDeadlineMs: provider.pauseDeadlineMs,
      tournamentTotalRounds: provider.tournamentTotalRounds,
      isPublicRoom: provider.roomSettings?.isPublic,
      roomCode: provider.roomCode,
      playerLeftNotification: provider.playerLeftNotification,
      lastPlayerLeftName: provider.lastPlayerLeftName,
      specialPowerNotification: provider.specialPowerNotification,
      specialPowerByName: provider.specialPowerByName,
      isSilentReconnecting: provider.isSilentReconnecting,
      presenceCheckActive: provider.presenceCheckActive,
      presenceCheckDeadlineMs: provider.presenceCheckDeadlineMs,
      presenceCheckReason: provider.presenceCheckReason,
    );
  }

  static Map<String, bool> _buildConnectionMap(
    MultiplayerGameProvider provider,
    GameState? gameState,
  ) {
    final map = <String, bool>{};
    for (final player in gameState?.players ?? []) {
      final presence = provider.presenceById[player.id];
      map[player.id] = presence == null || presence['connected'] == true;
    }
    return map;
  }

  static Map<String, bool> _buildAfkMap(
    MultiplayerGameProvider provider,
    GameState? gameState,
  ) {
    final map = <String, bool>{};
    for (final player in gameState?.players ?? []) {
      map[player.id] = provider.isPlayerAfk(player.id);
    }
    return map;
  }

  @override
  bool operator ==(Object other) {
    return other is _MultiplayerGameScreenModel &&
        identical(gameState, other.gameState) &&
        roomClosedByHost == other.roomClosedByHost &&
        wasKicked == other.wasKicked &&
        wasBanned == other.wasBanned &&
        isProcessing == other.isProcessing &&
        listEquals(shakingCardIndices, other.shakingCardIndices) &&
        playerId == other.playerId &&
        mapEquals(playerConnections, other.playerConnections) &&
        mapEquals(playerAfkStatus, other.playerAfkStatus) &&
        serverTimeOffsetMs == other.serverTimeOffsetMs &&
        currentReactionTimeMs == other.currentReactionTimeMs &&
        setEquals(powerTargetPlayerIds, other.powerTargetPlayerIds) &&
        isPaused == other.isPaused &&
        pausedByName == other.pausedByName &&
        isLocalPauser == other.isLocalPauser &&
        pauseDeadlineMs == other.pauseDeadlineMs &&
        tournamentTotalRounds == other.tournamentTotalRounds &&
        isPublicRoom == other.isPublicRoom &&
        roomCode == other.roomCode &&
        playerLeftNotification == other.playerLeftNotification &&
        lastPlayerLeftName == other.lastPlayerLeftName &&
        specialPowerNotification == other.specialPowerNotification &&
        specialPowerByName == other.specialPowerByName &&
        isSilentReconnecting == other.isSilentReconnecting &&
        presenceCheckActive == other.presenceCheckActive &&
        presenceCheckDeadlineMs == other.presenceCheckDeadlineMs &&
        presenceCheckReason == other.presenceCheckReason;
  }

  @override
  int get hashCode => Object.hashAll([
        identityHashCode(gameState),
        roomClosedByHost,
        wasKicked,
        wasBanned,
        isProcessing,
        Object.hashAll(shakingCardIndices),
        playerId,
        Object.hashAll(playerConnections.entries.map(
          (entry) => Object.hash(entry.key, entry.value),
        )),
        Object.hashAll(playerAfkStatus.entries.map(
          (entry) => Object.hash(entry.key, entry.value),
        )),
        serverTimeOffsetMs,
        currentReactionTimeMs,
        Object.hashAll(powerTargetPlayerIds),
        isPaused,
        pausedByName,
        isLocalPauser,
        pauseDeadlineMs,
        tournamentTotalRounds,
        isPublicRoom,
        roomCode,
        playerLeftNotification,
        lastPlayerLeftName,
        specialPowerNotification,
        specialPowerByName,
        isSilentReconnecting,
        presenceCheckActive,
        presenceCheckDeadlineMs,
        presenceCheckReason,
      ]);
}
