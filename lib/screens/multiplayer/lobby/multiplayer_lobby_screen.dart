import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../../providers/multiplayer_game_provider.dart';
import '../../../../../providers/auth_provider.dart';
import '../../../../../services/multiplayer/multiplayer_service.dart';
import '../../../../../services/social/friends_api_service.dart';
import '../../../../../models/game_state.dart';
import '../../../../../models/game_settings.dart';
import '../../../../../utils/ui_constants.dart';
import '../../../widgets/dialogs/connection_error_dialog.dart';
import '../../../widgets/dialogs/multiplayer/multiplayer_dialogs.dart';
import 'widgets/lobby_chat_panel.dart';
import 'widgets/lobby_players_panel.dart';
import 'widgets/lobby_room_info.dart';

class MultiplayerLobbyScreen extends StatefulWidget {
  const MultiplayerLobbyScreen({super.key});

  @override
  State<MultiplayerLobbyScreen> createState() => _MultiplayerLobbyScreenState();
}

class _MultiplayerLobbyScreenState extends State<MultiplayerLobbyScreen> {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  int _lastChatCount = 0;
  StreamSubscription? _eventSubscription;
  MultiplayerGameProvider? _provider;

  // Tracking pour éviter de re-trigger les side effects
  bool _hasNavigatedToGame = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _provider = Provider.of<MultiplayerGameProvider>(context, listen: false);
      // Signaler au serveur qu'on est actif dans le lobby
      _provider!.setScreenFocused(true);
      _eventSubscription = _provider!.events.listen((event) {
        if (!mounted) return;
        _handleGameEvent(event);
      });
      _provider!.addListener(_onProviderChanged);
    });
  }

  void _onProviderChanged() {
    if (!mounted) return;
    final provider = _provider;
    if (provider == null) return;

    // Navigation vers le jeu si la partie a commencé
    if (!_hasNavigatedToGame &&
        provider.isPlaying &&
        provider.gameState != null &&
        provider.gameState!.phase != GamePhase.ended) {
      _hasNavigatedToGame = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ModalRoute.of(context)?.isCurrent == true) {
          context.go('/multiplayer/memorization');
        }
      });
    }

    // Wizz animation reçue
    if (provider.showWizzAnimation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.notification_important, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                      "${provider.wizzFromName ?? 'Quelqu\'un'} te rappelle !"),
                ),
              ],
            ),
            backgroundColor: Colors.amber.shade700,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 2),
          ),
        );
        provider.dismissWizzAnimation();
      });
    }

    // Dialog si la room a été fermée par l'hôte
    if (provider.roomClosedByHost) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showRoomClosedDialog(context, provider);
      });
    }

    // Dialog si kické
    if (provider.wasKicked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showKickedDialog(context, provider);
      });
    }

    // Dialog si banni
    if (provider.wasBanned) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showBannedDialog(context, provider);
      });
    }

    // Dialog si déconnecté avec erreur
    if (provider.connectionState == SocketConnectionState.disconnected &&
        provider.errorMessage != null &&
        provider.errorMessage!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showConnectionErrorDialog(context, provider);
      });
    }
  }

  void _handleGameEvent(GameEvent event) {
    String? message;
    Color color = Colors.black87;
    IconData icon = Icons.info;

    switch (event.type) {
      case GameEventType.playerJoined:
        message = event.message;
        color = MultiplayerColors.success;
        icon = Icons.person_add;
        break;
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
      case GameEventType.gameStarted:
        // Already handled by state change usually, but feedback is nice
        // message = "La partie commence !";
        // color = Colors.purple;
        break;
      case GameEventType.info:
        message = event.message;
        color = MultiplayerColors.info;
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
  }

  @override
  void dispose() {
    // Signaler au serveur qu'on quitte le lobby (arrière-plan)
    _provider?.setScreenFocused(false);
    _provider?.removeListener(_onProviderChanged);
    _chatController.dispose();
    _chatScrollController.dispose();
    _eventSubscription?.cancel();
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  double _uiScale(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return (height / 700).clamp(0.55, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MultiplayerGameProvider>(
      builder: (context, provider, _) {
        _maybeScrollChatToBottom(provider);

        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final mediaQuery = MediaQuery.of(context);
        final size = mediaQuery.size;
        final isLandscape = size.width > size.height;
        final isWide = size.width >= 700;
        final heightScale = (size.height / 700).clamp(0.55, 1.0);
        final isCompactLandscape = isLandscape && heightScale < 0.85;
        final isPublicRoom = provider.roomSettings?.isPublic == true;
        // Pour les rooms publiques: afficher badge "PUBLIQUE" et jamais de code
        // (les joueurs rejoignent via matchmaking, pas via un code)
        // Pour les rooms privées: toujours afficher le code
        final showPublicBadge = isPublicRoom;
        final showRoomCode = !isPublicRoom;
        final sectionSpacing = 8.0 * heightScale;
        final contentSpacing = 12.0 * heightScale;
        final bottomSpacing = 16.0 * heightScale;
        final maxPlayers = provider.roomSettings?.maxPlayers ?? 6;
        final minPlayers = provider.roomSettings?.minPlayers ?? 2;
        final connectedHumans = _connectedHumans(provider);
        final canStart = provider.isHost &&
            provider.isReady &&
            provider.readyHumanCount >= minPlayers;

        return PopScope(
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) {
              provider.leaveRoom();
            }
          },
          child: GestureDetector(
            onTap: _dismissKeyboard,
            child: Scaffold(
              resizeToAvoidBottomInset: true,
              body: Container(
                decoration: AppDecorations.pageBackground,
                child: SafeArea(
                  child: Column(
                    children: [
                      _buildHeader(context, provider, colors),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: [
                              if (showPublicBadge)
                                LobbyPublicBadge(uiScale: heightScale)
                              else if (showRoomCode)
                                LobbyRoomCodeCard(
                                    provider: provider, uiScale: heightScale),
                              if (provider.roomSettings != null)
                                LobbySettingsRow(
                                  provider: provider,
                                  minPlayers: minPlayers,
                                  maxPlayers: maxPlayers,
                                  uiScale: heightScale,
                                ),
                              SizedBox(height: sectionSpacing),
                              Expanded(
                                child: isLandscape || isWide
                                    ? _buildLandscapeLayout(
                                        provider,
                                        connectedHumans,
                                        maxPlayers,
                                        heightScale,
                                      )
                                    : _buildPortraitLayout(
                                        provider,
                                        connectedHumans,
                                        maxPlayers,
                                        heightScale,
                                      ),
                              ),
                              SizedBox(height: contentSpacing),
                              _buildBottomButtons(
                                context,
                                provider,
                                colors,
                                canStart,
                                connectedHumans,
                                maxPlayers,
                                minPlayers,
                                compact: isCompactLandscape,
                              ),
                              SizedBox(height: bottomSpacing),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    MultiplayerGameProvider provider,
    ColorScheme colors,
  ) {
    final scale = _uiScale(context);
    double f(double size) => size * scale;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: f(16), vertical: f(12)),
      child: Row(
        children: [
          // Bouton retour (revenir au menu sans quitter la room)
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            iconSize: f(22),
            tooltip: 'Retour',
            onPressed: () => context.go('/multiplayer'),
          ),
          SizedBox(width: f(8)),
          Expanded(
            child: Text(
              "Salle d'attente",
              style: TextStyle(
                fontSize: f(20),
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          // Bouton inviter un ami (hôte uniquement)
          if (provider.isHost && context.read<AuthProvider>().isLoggedIn)
            IconButton(
              icon: const Icon(Icons.person_add, color: Colors.white),
              iconSize: f(22),
              tooltip: 'Inviter un ami',
              onPressed: () => _showInviteFriendDialog(context, provider),
            ),
          // Bouton paramètres (hôte uniquement)
          if (provider.isHost)
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              iconSize: f(22),
              tooltip: 'Paramètres',
              onPressed: () => _showSettingsDialog(context, provider),
            ),
          // Bouton quitter la room
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            iconSize: f(22),
            tooltip: 'Quitter la room',
            onPressed: () => _handleLeaveOrClose(context, provider),
          ),
          _buildConnectionIndicator(context, provider, colors),
        ],
      ),
    );
  }

  Widget _buildConnectionIndicator(
    BuildContext context,
    MultiplayerGameProvider provider,
    ColorScheme colors,
  ) {
    final scale = _uiScale(context);
    double f(double size) => size * scale;

    String label;
    Color color;
    IconData icon;

    switch (provider.connectionState) {
      case SocketConnectionState.connected:
        label = 'Connecte';
        color = colors.tertiary;
        icon = Icons.wifi;
        break;
      case SocketConnectionState.connecting:
        label = 'Connexion...';
        color = Colors.orange;
        icon = Icons.wifi_find;
        break;
      case SocketConnectionState.reconnecting:
        label = 'Reconnexion...';
        color = Colors.orange;
        icon = Icons.wifi_off;
        break;
      case SocketConnectionState.disconnected:
        label = 'Hors ligne';
        color = colors.error;
        icon = Icons.wifi_off;
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: f(10), vertical: f(5)),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(f(14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: f(14)),
          SizedBox(width: f(4)),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: f(12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSettingsDialog(
    BuildContext context,
    MultiplayerGameProvider provider,
  ) async {
    if (!provider.isHost) return;

    final settings = provider.roomSettings;
    if (settings == null) return;

    // Valeurs par défaut
    int botDifficulty = settings.botDifficulty.index;
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.settings),
              SizedBox(width: 8),
              Text('Paramètres de la partie'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Niveau des bots',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Facile')),
                  ButtonSegment(value: 1, label: Text('Moyen')),
                  ButtonSegment(value: 2, label: Text('Difficile')),
                ],
                selected: {botDifficulty},
                onSelectionChanged: (selection) {
                  setState(() => botDifficulty = selection.first);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, {
                'botDifficulty': botDifficulty,
              }),
              child: const Text('Appliquer'),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      final success = await provider.updateRoomSettings(
        botDifficulty: Difficulty.values[result['botDifficulty']!],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? 'Paramètres mis à jour'
                : 'Erreur lors de la mise à jour'),
            backgroundColor:
                success ? MultiplayerColors.success : MultiplayerColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _handleLeaveOrClose(
    BuildContext context,
    MultiplayerGameProvider provider,
  ) async {
    if (provider.isHost) {
      // Demander confirmation pour fermer la room
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Fermer la room ?'),
          content: const Text(
            'Les autres joueurs pourront choisir de devenir hôte ou quitter.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );

      if (confirm == true && mounted) {
        await provider.closeRoom();
        if (mounted) {
          context.go('/multiplayer');
        }
      }
    } else {
      // Demander confirmation pour quitter la room
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Quitter la room ?'),
          content: const Text(
            'Tu seras retiré de la room. Tu pourras la rejoindre à nouveau avec le code.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Quitter'),
            ),
          ],
        ),
      );

      if (confirm == true && mounted) {
        provider.leaveRoom();
        if (mounted) {
          context.go('/multiplayer');
        }
      }
    }
  }

  bool _roomClosedDialogShown = false;

  Future<void> _showRoomClosedDialog(
    BuildContext context,
    MultiplayerGameProvider provider,
  ) async {
    // Éviter d'afficher plusieurs fois
    if (_roomClosedDialogShown) return;
    _roomClosedDialogShown = true;

    final colors = Theme.of(context).colorScheme;

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: colors.error),
            const SizedBox(width: 8),
            const Text('Room fermée'),
          ],
        ),
        content: const Text(
          "L'hôte a fermé la room.\n\nVoulez-vous devenir le nouvel hôte ou quitter ?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'leave'),
            child: const Text('Quitter'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, 'become_host'),
            icon: const Icon(Icons.star),
            label: const Text('Devenir hôte'),
          ),
        ],
      ),
    );

    if (!mounted) {
      _roomClosedDialogShown = false;
      return;
    }

    if (choice == 'become_host') {
      final success = await provider.becomeHost();
      if (!mounted) {
        _roomClosedDialogShown = false;
        return;
      }

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vous êtes maintenant l\'hôte !')),
        );
        // becomeHost() a déjà fait clearRoomClosedAfterBecomeHost() et notifyListeners()
        // Le flag _roomClosedDialogShown reste true pour éviter tout re-trigger
        // Il sera reset si on quitte la room plus tard
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de devenir hôte')),
        );
        provider.acknowledgeRoomClosed();
        _roomClosedDialogShown = false;
        if (mounted) {
          context.go('/multiplayer');
        }
      }
    } else {
      provider.acknowledgeRoomClosed();
      _roomClosedDialogShown = false;
      if (mounted) {
        context.go('/multiplayer');
      }
    }
  }

  bool _kickedDialogShown = false;

  void _showKickedDialog(
    BuildContext context,
    MultiplayerGameProvider provider,
  ) {
    if (_kickedDialogShown) return;
    _kickedDialogShown = true;

    provider.acknowledgeKicked();
    MultiplayerDialogs.showKickedDialog(context, provider.kickedMessage);

    // Reset après fermeture
    Future.delayed(const Duration(milliseconds: 500), () {
      _kickedDialogShown = false;
    });
  }

  bool _bannedDialogShown = false;

  void _showBannedDialog(
    BuildContext context,
    MultiplayerGameProvider provider,
  ) {
    if (_bannedDialogShown) return;
    _bannedDialogShown = true;

    provider.acknowledgeBanned();
    MultiplayerDialogs.showBannedDialog(context, provider.bannedMessage);

    // Reset après fermeture
    Future.delayed(const Duration(milliseconds: 500), () {
      _bannedDialogShown = false;
    });
  }

  bool _connectionErrorDialogShown = false;

  Future<void> _showConnectionErrorDialog(
    BuildContext context,
    MultiplayerGameProvider provider,
  ) async {
    // Éviter d'afficher plusieurs fois
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
          context.go('/multiplayer');
        }
      },
    );

    _connectionErrorDialogShown = false;
  }

  Widget _buildLandscapeLayout(
    MultiplayerGameProvider provider,
    int connectedHumans,
    int maxPlayers,
    double scale,
  ) {
    final chatFlex = scale < 0.8 ? 1 : 2;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: LobbyPlayersPanel(
            provider: provider,
            connectedHumans: connectedHumans,
            maxPlayers: maxPlayers,
            uiScale: scale,
          ),
        ),
        SizedBox(width: 12 * scale),
        Expanded(
          flex: chatFlex,
          child: LobbyChatPanel(
            provider: provider,
            chatController: _chatController,
            chatScrollController: _chatScrollController,
            onDismissKeyboard: _dismissKeyboard,
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitLayout(
    MultiplayerGameProvider provider,
    int connectedHumans,
    int maxPlayers,
    double scale,
  ) {
    final chatHeight = (MediaQuery.of(context).size.height * 0.28)
        .clamp(120.0 * scale, 200.0 * scale);
    return Column(
      children: [
        Expanded(
          flex: 2,
          child: LobbyPlayersPanel(
            provider: provider,
            connectedHumans: connectedHumans,
            maxPlayers: maxPlayers,
            uiScale: scale,
          ),
        ),
        SizedBox(height: 12 * scale),
        SizedBox(
          height: chatHeight,
          child: LobbyChatPanel(
            provider: provider,
            chatController: _chatController,
            chatScrollController: _chatScrollController,
            onDismissKeyboard: _dismissKeyboard,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomButtons(
      BuildContext context,
      MultiplayerGameProvider provider,
      ColorScheme colors,
      bool canStart,
      int connectedHumans,
      int maxPlayers,
      int minPlayers,
      {bool compact = false}) {
    final scale = _uiScale(context);
    double f(double size) => size * scale;
    // Si la partie est en cours, afficher le bouton "Regarder"
    if (provider.roomStatus == 'playing') {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => provider.watchGame(),
          icon: Icon(Icons.visibility, size: f(18)),
          label: const Text('REGARDER LA PARTIE'),
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(vertical: f(compact ? 12 : 16)),
            backgroundColor: colors.tertiary,
            foregroundColor: Colors.white,
            elevation: 4,
          ),
        ),
      );
    }

    // Pour l'hote: bouton Pret + bouton Lancer
    // Pour les autres: seulement bouton Pret (pleine largeur)
    if (provider.isHost) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  key: const Key('host_ready_button'),
                  onPressed: () => provider.setReady(!provider.isReady),
                  icon: Icon(
                    provider.isReady
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: f(20),
                  ),
                  label: Text(provider.isReady ? 'Pret' : 'Passer pret'),
                  style: ElevatedButton.styleFrom(
                    padding:
                        EdgeInsets.symmetric(vertical: f(compact ? 12 : 14)),
                    backgroundColor:
                        provider.isReady ? colors.tertiary : Colors.white,
                    foregroundColor:
                        provider.isReady ? Colors.white : colors.primary,
                    elevation: provider.isReady ? 6 : 2,
                  ),
                ),
              ),
              SizedBox(width: f(12)),
              Expanded(
                child: ElevatedButton(
                  key: const Key('host_start_button'),
                  onPressed: canStart
                      ? () => _handleStartPressed(
                            context,
                            provider,
                            connectedHumans,
                            maxPlayers,
                          )
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding:
                        EdgeInsets.symmetric(vertical: f(compact ? 12 : 14)),
                    backgroundColor: colors.primaryContainer,
                    foregroundColor: colors.onPrimaryContainer,
                    disabledBackgroundColor: AppColors.disabledBackground,
                    disabledForegroundColor: AppColors.disabledForeground,
                  ),
                  child: Text(
                    canStart
                        ? 'Lancer'
                        : 'Pret: ${provider.readyHumanCount}/$minPlayers',
                    style: TextStyle(
                      fontSize: f(14),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    // Non-hote: seulement bouton Pret
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            key: const Key('guest_ready_button'),
            onPressed: () => provider.setReady(!provider.isReady),
            icon: Icon(
              provider.isReady
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              size: f(20),
            ),
            label: Text(provider.isReady ? 'Pret' : 'Passer pret'),
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: f(compact ? 12 : 14)),
              backgroundColor:
                  provider.isReady ? colors.tertiary : Colors.white,
              foregroundColor: provider.isReady ? Colors.white : colors.primary,
              elevation: provider.isReady ? 6 : 2,
            ),
          ),
        ),
        if (!compact)
          Padding(
            padding: EdgeInsets.only(top: f(8)),
            child: Text(
              provider.isReady
                  ? "Tu es pret. L'hote peut lancer."
                  : 'Appuie sur "Passer pret"',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: f(12),
              ),
            ),
          ),
      ],
    );
  }

  void _maybeScrollChatToBottom(MultiplayerGameProvider provider) {
    final count = provider.chatMessages.length;
    if (count == _lastChatCount) return;
    _lastChatCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      final position = _chatScrollController.position.maxScrollExtent;
      _chatScrollController.animateTo(
        position,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _handleStartPressed(
    BuildContext context,
    MultiplayerGameProvider provider,
    int connectedHumans,
    int maxPlayers,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    // Si on a déjà le maximum de joueurs, lancer directement
    if (connectedHumans >= maxPlayers) {
      await provider.startGame(fillBots: false);
      if (!mounted) return;
      if (provider.errorMessage != null) {
        messenger.showSnackBar(
          SnackBar(content: Text(provider.errorMessage!)),
        );
        provider.clearError();
      }
      return;
    }

    // Sinon, afficher le dialogue de sélection de bots
    final result = await _showBotSelectionDialog(
      context,
      connectedHumans,
      maxPlayers,
      provider,
    );

    if (result == null) return; // Annulé

    final numberOfBots = result['numberOfBots'] as int;
    final useSBMM = result['useSBMM'] as bool;
    final botDifficulty = result['botDifficulty'] as int?;

    // Démarrer la partie avec les paramètres de bots
    if (numberOfBots > 0) {
      await provider.startGame(
        fillBots: numberOfBots > 0,
        numberOfBots: numberOfBots,
        useSBMM: useSBMM,
        botDifficulty: botDifficulty,
      );
    } else {
      await provider.startGame(fillBots: false);
    }

    if (!mounted) return;
    if (provider.errorMessage != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(provider.errorMessage!)),
      );
      provider.clearError();
    }
  }

  Future<Map<String, dynamic>?> _showBotSelectionDialog(
    BuildContext context,
    int connectedHumans,
    int maxPlayers,
    MultiplayerGameProvider provider,
  ) async {
    int numberOfBots = 0; // Par defaut 0 bots en multi
    bool useSBMM = true;
    int botDifficulty = 1; // Moyen par défaut

    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.smart_toy),
              SizedBox(width: 8),
              Text('Ajouter des bots'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vous êtes $connectedHumans/$maxPlayers joueurs.',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),

                // Nombre de bots
                const Text(
                  'Nombre de bots',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: List.generate(
                    maxPlayers - connectedHumans + 1,
                    (index) => ChoiceChip(
                      label: Text('$index'),
                      selected: numberOfBots == index,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => numberOfBots = index);
                        }
                      },
                    ),
                  ),
                ),

                if (numberOfBots > 0) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Mode SBMM ou Manuel
                  const Text(
                    'Niveau des bots',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Mode adaptatif (SBMM)'),
                    subtitle: Text(
                      useSBMM
                          ? 'Les bots s\'adaptent à votre niveau'
                          : 'Choisissez le niveau manuellement',
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: useSBMM,
                    onChanged: (value) {
                      setState(() => useSBMM = value);
                    },
                  ),

                  if (!useSBMM) ...[
                    const SizedBox(height: 8),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Facile')),
                        ButtonSegment(value: 1, label: Text('Moyen')),
                        ButtonSegment(value: 2, label: Text('Difficile')),
                        ButtonSegment(value: 3, label: Text('Mix')),
                      ],
                      selected: {botDifficulty},
                      onSelectionChanged: (selection) {
                        setState(() => botDifficulty = selection.first);
                      },
                    ),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'numberOfBots': numberOfBots,
                'useSBMM': useSBMM,
                'botDifficulty': useSBMM ? null : botDifficulty,
              }),
              child: const Text('Lancer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showInviteFriendDialog(
    BuildContext context,
    MultiplayerGameProvider provider,
  ) async {
    final authProvider = context.read<AuthProvider>();
    if (!authProvider.isLoggedIn) return;

    final friendsApi = FriendsApiService(authProvider.authService);
    final friends = await friendsApi.getFriends();

    if (!mounted) return;

    final roomCode = provider.roomCode;
    if (roomCode == null) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.person_add),
            SizedBox(width: 8),
            Text('Inviter un ami'),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: friends.isEmpty
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text(
                      'Aucun ami pour le moment',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: friends.length,
                  itemBuilder: (context, index) {
                    final friend = friends[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: friend.isOnline
                            ? MultiplayerColors.success.withValues(alpha: 0.2)
                            : Colors.grey.withValues(alpha: 0.2),
                        child: Icon(
                          Icons.person,
                          color: friend.isOnline
                              ? MultiplayerColors.success
                              : Colors.grey,
                        ),
                      ),
                      title: Text(friend.displayName),
                      subtitle: Text(
                        '@${friend.username}${friend.isOnline ? ' • En ligne' : ''}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.send,
                            color: MultiplayerColors.success),
                        tooltip: 'Inviter',
                        onPressed: () async {
                          final result = await friendsApi.inviteToRoom(
                            roomCode,
                            friend.userId,
                          );
                          if (!ctx.mounted) return;
                          Navigator.of(ctx).pop();
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  result.success
                                      ? '${friend.displayName} a été ajouté au salon'
                                      : (result.error?.trim().isNotEmpty == true
                                          ? result.error!
                                          : 'Erreur lors de l\'invitation'),
                                ),
                                backgroundColor: result.success
                                    ? MultiplayerColors.success
                                    : MultiplayerColors.danger,
                              ),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  int _connectedHumans(MultiplayerGameProvider provider) {
    return provider.playersInLobby.where((player) {
      if (player['isHuman'] != true) return false;
      if (player['isSpectator'] == true) return false;
      return player['connected'] != false;
    }).length;
  }
}
