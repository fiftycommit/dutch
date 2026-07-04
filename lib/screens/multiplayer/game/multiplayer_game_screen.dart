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

  /// Barre de boutons (émotes / pause / quitter). Aucune dépendance au provider :
  /// passée en `child` du Selector du corps, elle n'est construite qu'une fois.
  Widget _buildTopRightButtons(BuildContext context) {
    RebuildProbe.bump('buttons');
    final gp = context.read<MultiplayerGameProvider>();
    return Positioned(
      top: 10,
      right: 10,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon:
                const Icon(Icons.emoji_emotions, color: Colors.amber, size: 32),
            onPressed: () {
              setState(() {
                _showEmoteOverlay = true;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.pause_circle_filled,
                color: AppColors.textDisabled, size: 32),
            onPressed: () => gp.pauseGame(),
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app,
                color: AppColors.textDisabled, size: 32),
            onPressed: () => _showQuitConfirmation(context, gp),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Selector<MultiplayerGameProvider, _MultiplayerGameScreenModel>(
        selector: (_, gameProvider) =>
            _MultiplayerGameScreenModel.from(gameProvider),
        // Zone sans dépendance provider : construite une seule fois puis passée
        // inchangée à chaque rebuild du corps.
        child: _buildTopRightButtons(context),
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
                    // Zone table de jeu isolée : son propre Selector projette
                    // SES entrées (dont currentReactionTimeMs, qui tick ~30 ms).
                    // Ces champs étant sortis du modèle du corps, un tick du
                    // timer de réaction ne reconstruit plus que GameTableWidget,
                    // pas les overlays inline (code salon, notifications…).
                    Selector<MultiplayerGameProvider, _GameTableModel>(
                      selector: (_, p) => _GameTableModel.from(p),
                      builder: (context, gt, __) {
                        RebuildProbe.bump('gametable');
                        final gp = context.read<MultiplayerGameProvider>();
                        final gs = gt.gameState!;
                        return GameTableWidget(
                          gameState: gs,
                          isProcessing: gt.isProcessing,
                          shakingCardIndices: gt.shakingCardIndices,
                          isSpectator: !gs.players.any(
                              (p) => p.id == gt.playerId && !p.isSpectator),
                          callbacks: GameTableCallbacks.fromController(
                            context: context,
                            controller: gp,
                            onOpponentCardTap: (opponentIndex, cardIndex) {
                              gp.sendSpecialPowerTargetSelection(
                                  opponentIndex, null, null, null);
                              gp.usePower10SpyOpponent(
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
                            playerId: gt.playerId,
                            playerConnections: gt.playerConnections,
                            playerAfkStatus: gt.playerAfkStatus,
                            turnStartTime: gs.turnStartTime != null
                                ? gs.turnStartTime! - gt.serverTimeOffsetMs
                                : null,
                            turnDuration: gs.turnTimeoutMs,
                            reactionTimeTotalMs: gt.currentReactionTimeMs,
                            powerTargetPlayerIds: gt.powerTargetPlayerIds,
                          ),
                          isPaused: gt.isPaused,
                        );
                      },
                    ),

                    // Overlay code salon / info tournoi. Ne dépend que de champs
                    // quasi-statiques (mode, code, round) : son propre Selector
                    // l'empêche de se reconstruire sur les ticks du timer de
                    // réaction (currentReactionTimeMs, ~30 ms) ou toute autre
                    // notification qui ne le concerne pas.
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Selector<MultiplayerGameProvider, _RoomInfoModel>(
                        selector: (_, p) => _RoomInfoModel.from(p),
                        builder: (context, info, __) {
                          RebuildProbe.bump('roomcode');
                          final isTournament =
                              info.gameMode == GameMode.tournament;
                          return Container(
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
                                      isTournament
                                          ? Icons.emoji_events
                                          : Icons.videogame_asset,
                                      color: isTournament
                                          ? Colors.amber
                                          : AppColors.textSecondary,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      isTournament
                                          ? tournamentStageLabel(
                                              info.tournamentRound,
                                              totalRounds:
                                                  info.tournamentTotalRounds,
                                            )
                                          // Masquer le code pour les parties publiques
                                          : (info.isPublicRoom == true
                                              ? "Partie publique"
                                              : "Room: ${info.roomCode ?? '?'}"),
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                if (isTournament) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    "Manches restantes : ${(info.tournamentTotalRounds - info.tournamentRound).clamp(0, 99)}",
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
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

                    // Boutons en haut à droite. Ils ne lisent AUCUN champ du
                    // provider : passés en `child` du Selector (construits une
                    // fois), ils ne se reconstruisent plus quand le corps
                    // rebuild sur une notification (tick de présence, gameState…).
                    if (child != null) child,

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

                    // Zone présence isolée : son propre Selector écoute
                    // seulement les champs de présence, donc un tick du compte à
                    // rebours ne reconstruit plus le corps ni GameTableWidget.
                    Selector<MultiplayerGameProvider, _PresenceModel>(
                      selector: (_, p) => _PresenceModel(
                        active: p.presenceCheckActive,
                        deadlineMs: p.presenceCheckDeadlineMs,
                        reason: p.presenceCheckReason,
                      ),
                      builder: (context, presence, __) {
                        RebuildProbe.bump('presence');
                        final gp = context.read<MultiplayerGameProvider>();
                        return PresenceCheckOverlay(
                          active: presence.active,
                          deadlineMs: presence.deadlineMs,
                          reason: presence.reason,
                          onConfirm: gp.confirmPresence,
                          onAbandon: () {
                            gp.confirmPresence(); // Clear the check first
                            gp.forfeitGame();
                            // Rester spectateur : la partie se terminera et
                            // naviguera vers les résultats automatiquement.
                          },
                        );
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
  final bool isPaused;
  final String? pausedByName;
  final bool isLocalPauser;
  final int pauseDeadlineMs;
  final bool playerLeftNotification;
  final String? lastPlayerLeftName;
  final bool specialPowerNotification;
  final String? specialPowerByName;
  final bool isSilentReconnecting;

  const _MultiplayerGameScreenModel({
    required this.gameState,
    required this.roomClosedByHost,
    required this.wasKicked,
    required this.wasBanned,
    required this.isProcessing,
    required this.isPaused,
    required this.pausedByName,
    required this.isLocalPauser,
    required this.pauseDeadlineMs,
    required this.playerLeftNotification,
    required this.lastPlayerLeftName,
    required this.specialPowerNotification,
    required this.specialPowerByName,
    required this.isSilentReconnecting,
  });

  factory _MultiplayerGameScreenModel.from(MultiplayerGameProvider provider) {
    return _MultiplayerGameScreenModel(
      gameState: provider.gameState,
      roomClosedByHost: provider.roomClosedByHost,
      wasKicked: provider.wasKicked,
      wasBanned: provider.wasBanned,
      isProcessing: provider.isProcessing,
      isPaused: provider.isPaused,
      pausedByName: provider.pausedByName,
      isLocalPauser: provider.isLocalPauser,
      pauseDeadlineMs: provider.pauseDeadlineMs,
      playerLeftNotification: provider.playerLeftNotification,
      lastPlayerLeftName: provider.lastPlayerLeftName,
      specialPowerNotification: provider.specialPowerNotification,
      specialPowerByName: provider.specialPowerByName,
      isSilentReconnecting: provider.isSilentReconnecting,
    );
  }

  static Map<String, bool> _buildConnectionMap(
    MultiplayerGameProvider provider,
    GameState? gameState,
  ) {
    final map = <String, bool>{};
    for (final player in gameState?.players ?? []) {
      // Source de vérité : le `connected` réel porté par gameState.players,
      // mis à jour par le serveur sur déconnexion/reconnexion (fail-safe, plus
      // le défaut fail-open « présence inconnue = en ligne » d'avant). Les bots
      // sont toujours connectés.
      map[player.id] = player.isHuman ? player.connected : true;
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
        isPaused == other.isPaused &&
        pausedByName == other.pausedByName &&
        isLocalPauser == other.isLocalPauser &&
        pauseDeadlineMs == other.pauseDeadlineMs &&
        playerLeftNotification == other.playerLeftNotification &&
        lastPlayerLeftName == other.lastPlayerLeftName &&
        specialPowerNotification == other.specialPowerNotification &&
        specialPowerByName == other.specialPowerByName &&
        isSilentReconnecting == other.isSilentReconnecting;
  }

  @override
  int get hashCode => Object.hashAll([
        identityHashCode(gameState),
        roomClosedByHost,
        wasKicked,
        wasBanned,
        isProcessing,
        isPaused,
        pausedByName,
        isLocalPauser,
        pauseDeadlineMs,
        playerLeftNotification,
        lastPlayerLeftName,
        specialPowerNotification,
        specialPowerByName,
        isSilentReconnecting,
      ]);
}

/// Modèle restreint de GameTableWidget : ses seules entrées réelles, dont
/// currentReactionTimeMs (tick ~30 ms). Ces champs étant SORTIS du modèle du
/// corps, un tick du timer de réaction ne reconstruit que cette zone, pas les
/// overlays inline.
class _GameTableModel {
  final GameState? gameState;
  final bool isProcessing;
  final bool isPaused;
  final String? playerId;
  final List<int> shakingCardIndices;
  final Map<String, bool> playerConnections;
  final Map<String, bool> playerAfkStatus;
  final int serverTimeOffsetMs;
  final int currentReactionTimeMs;
  final Set<String> powerTargetPlayerIds;

  const _GameTableModel({
    required this.gameState,
    required this.isProcessing,
    required this.isPaused,
    required this.playerId,
    required this.shakingCardIndices,
    required this.playerConnections,
    required this.playerAfkStatus,
    required this.serverTimeOffsetMs,
    required this.currentReactionTimeMs,
    required this.powerTargetPlayerIds,
  });

  factory _GameTableModel.from(MultiplayerGameProvider provider) {
    final gameState = provider.gameState;
    return _GameTableModel(
      gameState: gameState,
      isProcessing: provider.isProcessing,
      isPaused: provider.isPaused,
      playerId: provider.playerId,
      shakingCardIndices: provider.shakingCardIndices.toList()..sort(),
      playerConnections:
          _MultiplayerGameScreenModel._buildConnectionMap(provider, gameState),
      playerAfkStatus:
          _MultiplayerGameScreenModel._buildAfkMap(provider, gameState),
      serverTimeOffsetMs: provider.serverTimeOffsetMs,
      currentReactionTimeMs: provider.currentReactionTimeMs,
      powerTargetPlayerIds: provider.powerTargetPlayerIds,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _GameTableModel &&
      identical(gameState, other.gameState) &&
      isProcessing == other.isProcessing &&
      isPaused == other.isPaused &&
      playerId == other.playerId &&
      listEquals(shakingCardIndices, other.shakingCardIndices) &&
      mapEquals(playerConnections, other.playerConnections) &&
      mapEquals(playerAfkStatus, other.playerAfkStatus) &&
      serverTimeOffsetMs == other.serverTimeOffsetMs &&
      currentReactionTimeMs == other.currentReactionTimeMs &&
      setEquals(powerTargetPlayerIds, other.powerTargetPlayerIds);

  @override
  int get hashCode => Object.hashAll([
        identityHashCode(gameState),
        isProcessing,
        isPaused,
        playerId,
        Object.hashAll(shakingCardIndices),
        Object.hashAll(
            playerConnections.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAll(
            playerAfkStatus.entries.map((e) => Object.hash(e.key, e.value))),
        serverTimeOffsetMs,
        currentReactionTimeMs,
        Object.hashAll(powerTargetPlayerIds),
      ]);
}

/// Modèle restreint de la zone de présence : seul un changement de ces champs
/// reconstruit l'overlay de présence, sans toucher au corps ni à GameTableWidget.
class _PresenceModel {
  final bool active;
  final int deadlineMs;
  final String? reason;

  const _PresenceModel({
    required this.active,
    required this.deadlineMs,
    required this.reason,
  });

  @override
  bool operator ==(Object other) =>
      other is _PresenceModel &&
      active == other.active &&
      deadlineMs == other.deadlineMs &&
      reason == other.reason;

  @override
  int get hashCode => Object.hash(active, deadlineMs, reason);
}

/// Modèle restreint de l'overlay code salon / tournoi. Ne projette que des
/// champs quasi-statiques (mode, round, code) : reconstruit ~jamais en cours de
/// partie, notamment pas sur les ticks du timer de réaction.
class _RoomInfoModel {
  final GameMode? gameMode;
  final int tournamentRound;
  final int tournamentTotalRounds;
  final bool? isPublicRoom;
  final String? roomCode;

  const _RoomInfoModel({
    required this.gameMode,
    required this.tournamentRound,
    required this.tournamentTotalRounds,
    required this.isPublicRoom,
    required this.roomCode,
  });

  factory _RoomInfoModel.from(MultiplayerGameProvider p) {
    final gs = p.gameState;
    return _RoomInfoModel(
      gameMode: gs?.gameMode,
      tournamentRound: gs?.tournamentRound ?? 0,
      tournamentTotalRounds: p.tournamentTotalRounds,
      isPublicRoom: p.roomSettings?.isPublic,
      roomCode: p.roomCode,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _RoomInfoModel &&
      gameMode == other.gameMode &&
      tournamentRound == other.tournamentRound &&
      tournamentTotalRounds == other.tournamentTotalRounds &&
      isPublicRoom == other.isPublicRoom &&
      roomCode == other.roomCode;

  @override
  int get hashCode => Object.hash(
      gameMode, tournamentRound, tournamentTotalRounds, isPublicRoom, roomCode);
}
