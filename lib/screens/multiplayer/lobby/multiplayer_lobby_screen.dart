import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../../providers/multiplayer_game_provider.dart';
import '../../../../../services/multiplayer/multiplayer_service.dart';
import '../../../../../models/game_state.dart';
import '../../../../../models/game_settings.dart';
import '../../../../../utils/ui_constants.dart';
import '../../../widgets/dialogs/connection_error_dialog.dart';
import '../../../widgets/dialogs/multiplayer/multiplayer_dialogs.dart';


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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider =
          Provider.of<MultiplayerGameProvider>(context, listen: false);
      _eventSubscription = provider.events.listen((event) {
        if (!mounted) return;
        _handleGameEvent(event);
      });
    });
  }

  void _handleGameEvent(GameEvent event) {
    String? message;
    Color color = Colors.black87;
    IconData icon = Icons.info;

    switch (event.type) {
      case GameEventType.playerJoined:
        message = event.message;
        color = Colors.green.shade800;
        icon = Icons.person_add;
        break;
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
      case GameEventType.gameStarted:
        // Already handled by state change usually, but feedback is nice
        // message = "La partie commence !";
        // color = Colors.purple;
        break;
      case GameEventType.info:
        message = event.message;
        color = Colors.blue.shade800;
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
        // Naviguer vers le jeu si la partie a commencé (mais pas si elle est terminée)
        if (provider.isPlaying && provider.gameState != null && 
            provider.gameState!.phase != GamePhase.ended) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            // Only push if we are the current route to avoid multiple pushes
            if (ModalRoute.of(context)?.isCurrent == true) {
              context.go('/multiplayer/memorization');
            }
          });
        }

        // Afficher dialog si la room a été fermée par l'hôte
        if (provider.roomClosedByHost) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showRoomClosedDialog(context, provider);
          });
        }

        // Afficher dialog si kické (peut revenir)
        if (provider.wasKicked) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showKickedDialog(context, provider);
          });
        }

        // Afficher dialog si banni (définitif)
        if (provider.wasBanned) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showBannedDialog(context, provider);
          });
        }

        // Afficher dialog si déconnecté avec erreur
        if (provider.connectionState == SocketConnectionState.disconnected &&
            provider.errorMessage != null &&
            provider.errorMessage!.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showConnectionErrorDialog(context, provider);
          });
        }

        // Listen to events for feedback
        // We use a post frame callback to ensure context is valid, but ideally we should listen in initState.
        // However, Consumer rebuilds might duplicate listeners if not careful.
        // Better approach: Use a wrapper or side-effect listener.
        // For simplicity here:
        // We will add a Listener widget or handle it in initState if possible.
        // Given structure, let's use a side-effect hook in build if we can ensure single subscription?
        // No, build is bad for side effects.

        // Let's rely on the fact that Provider listeners are already set up.
        // We need to access the stream.
        // Let's stick to the plan: consume stream in initState is best, but we are inside build with Consumer.
        // We will wrap the body in a StreamListener (custom) or just use logic in build?
        // Actually, let's assume we can add a listener in initState of the State class if we have access to provider there.
        // In initState we don't have provider yet (unless listen:false).

        // Let's modify the State class to listen.

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
        // Pour les rooms publiques: afficher badge "PUBLIQUE" et pas de code
        // Pour les rooms privées: toujours afficher le code (même en mode rapide)
        final showPublicBadge = isPublicRoom;
        // Ne pas montrer le code aux non-hôtes dans les rooms publiques
        // (ils ont rejoint via matchmaking, pas besoin du code)
        final showRoomCode = !isPublicRoom || provider.isHost;
        final sectionSpacing = 8.0 * heightScale;
        final contentSpacing = 12.0 * heightScale;
        final bottomSpacing = 16.0 * heightScale;
        final maxPlayers = provider.roomSettings?.maxPlayers ?? 4;
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
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colors.primary.withValues(alpha: 0.92),
                      colors.secondary.withValues(alpha: 0.92),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      _buildHeader(context, provider, colors),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: [
                              // Pour les rooms publiques: afficher le badge pour tous
                              // sauf l'hôte qui voit aussi le code
                              if (showPublicBadge && !provider.isHost)
                                _buildPublicLobbyBadge()
                              else if (showRoomCode)
                                _buildRoomCodeCard(context, provider, colors),
                              if (provider.roomSettings != null)
                                _buildSettingsRow(
                                    context, provider, minPlayers, maxPlayers),
                              SizedBox(height: sectionSpacing),
                              Expanded(
                                child: isLandscape || isWide
                                    ? _buildLandscapeLayout(
                                        context,
                                        provider,
                                        connectedHumans,
                                        maxPlayers,
                                      )
                                    : _buildPortraitLayout(
                                        context,
                                        provider,
                                        connectedHumans,
                                        maxPlayers,
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
      padding:
          EdgeInsets.symmetric(horizontal: f(16), vertical: f(12)),
      child: Row(
        children: [
          // Bouton Quitter/Fermer
          IconButton(
            icon: Icon(
              provider.isHost ? Icons.close : Icons.arrow_back,
              color: Colors.white,
            ),
            iconSize: f(22),
            tooltip: provider.isHost ? 'Fermer la room' : 'Quitter',
            onPressed: () => _handleLeaveOrClose(context, provider),
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
          // Bouton paramètres (hôte uniquement)
          if (provider.isHost)
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              iconSize: f(22),
              tooltip: 'Paramètres',
              onPressed: () => _showSettingsDialog(context, provider),
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
    int luckDifficulty = settings.luckDifficulty.index;

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
              const SizedBox(height: 24),
              const Text(
                'Tri des cartes',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Aléatoire')),
                  ButtonSegment(value: 1, label: Text('Moyen')),
                  ButtonSegment(value: 2, label: Text('Trié')),
                ],
                selected: {luckDifficulty},
                onSelectionChanged: (selection) {
                  setState(() => luckDifficulty = selection.first);
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
                'luckDifficulty': luckDifficulty,
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
        luckDifficulty: Difficulty.values[result['luckDifficulty']!],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? 'Paramètres mis à jour'
                : 'Erreur lors de la mise à jour'),
            backgroundColor: success ? Colors.green : Colors.red,
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
      // Simplement quitter
      provider.leaveRoom();
      if (mounted) {
        context.go('/multiplayer');
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

    _roomClosedDialogShown = false;

    if (!mounted) return;

    if (choice == 'become_host') {
      final success = await provider.becomeHost();
      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vous êtes maintenant l\'hôte !')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de devenir hôte')),
        );
        provider.acknowledgeRoomClosed();
        if (mounted) {
          context.go('/multiplayer');
        }
      }
    } else {
      provider.acknowledgeRoomClosed();
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

  Widget _buildSettingsRow(
    BuildContext context,
    MultiplayerGameProvider provider,
    int minPlayers,
    int maxPlayers,
  ) {
    final scale = _uiScale(context);
    double f(double size) => size * scale;
    final isQuickMode = provider.roomSettings!.gameMode == GameMode.quick;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: f(8)),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: f(8),
        runSpacing: f(8),
        children: [
          // Mode de jeu - modifiable par l'hôte
          if (provider.isHost)
            _buildGameModeSelector(context, provider, isQuickMode)
          else
            _buildSettingChip(
              context,
              label: isQuickMode ? 'Rapide' : 'Tournoi',
              icon: Icons.flag,
            ),
          _buildSettingChip(
            context,
            label: 'Min $minPlayers',
            icon: Icons.people,
          ),
          _buildSettingChip(
            context,
            label: 'Max $maxPlayers',
            icon: Icons.groups,
          ),
        ],
      ),
    );
  }

  Widget _buildGameModeSelector(
    BuildContext context,
    MultiplayerGameProvider provider,
    bool isQuickMode,
  ) {
    final scale = _uiScale(context);
    double f(double size) => size * scale;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: f(4), vertical: f(2)),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(f(20)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeButton(
            context: context,
            label: 'Rapide',
            icon: Icons.bolt,
            isSelected: isQuickMode,
            onTap: () => provider.setGameMode(GameMode.quick),
          ),
          _buildModeButton(
            context: context,
            label: 'Tournoi',
            icon: Icons.emoji_events,
            isSelected: !isQuickMode,
            onTap: () => provider.setGameMode(GameMode.tournament),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final scale = _uiScale(context);
    double f(double size) => size * scale;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: f(10), vertical: f(6)),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(f(16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: f(14),
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            SizedBox(width: f(4)),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontSize: f(11),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout(
    BuildContext context,
    MultiplayerGameProvider provider,
    int connectedHumans,
    int maxPlayers,
  ) {
    final scale = _uiScale(context);
    final chatFlex = scale < 0.8 ? 1 : 2;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: _buildPlayersPanel(
              context, provider, connectedHumans, maxPlayers),
        ),
        SizedBox(width: 12 * scale),
        Expanded(
          flex: chatFlex,
          child: _buildChatPanel(context, provider),
        ),
      ],
    );
  }

  Widget _buildPortraitLayout(
    BuildContext context,
    MultiplayerGameProvider provider,
    int connectedHumans,
    int maxPlayers,
  ) {
    final scale = _uiScale(context);
    final chatHeight = (MediaQuery.of(context).size.height * 0.28)
        .clamp(120.0 * scale, 200.0 * scale);
    return Column(
      children: [
        Expanded(
          flex: 2,
          child: _buildPlayersPanel(
              context, provider, connectedHumans, maxPlayers),
        ),
        SizedBox(height: 12 * scale),
        SizedBox(
          height: chatHeight,
          child: _buildChatPanel(context, provider),
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
    {bool compact = false}
  ) {
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
            padding:
                EdgeInsets.symmetric(vertical: f(compact ? 12 : 16)),
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

  Widget _buildPublicLobbyBadge() {
    final scale = _uiScale(context);
    double f(double size) => size * scale;
    return Container(
      margin: EdgeInsets.symmetric(vertical: f(8)),
      padding: EdgeInsets.all(f(16)),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(f(16)),
        border: Border.all(
          color: Colors.green.withValues(alpha: 0.5),
          width: f(1.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.public,
            color: Colors.green.shade300,
            size: f(24),
          ),
          SizedBox(width: f(12)),
          Text(
            'Salon Public',
            style: TextStyle(
              color: Colors.green.shade300,
              fontSize: f(18),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomCodeCard(
    BuildContext context,
    MultiplayerGameProvider provider,
    ColorScheme colors,
  ) {
    final scale = _uiScale(context);
    double f(double size) => size * scale;
    // Version plus compacte du bandeau de code
    return Container(
      key: const Key('room_code_card'),
      margin: EdgeInsets.symmetric(vertical: f(4)),
      padding: EdgeInsets.symmetric(horizontal: f(16), vertical: f(10)),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(f(12)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.26),
          width: f(1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Code',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: f(11),
            ),
          ),
          SizedBox(width: f(12)),
          Text(
            provider.roomCode ?? '------',
            style: TextStyle(
              color: Colors.white,
              fontSize: f(22),
              fontWeight: FontWeight.bold,
              letterSpacing: f(3),
            ),
          ),
          SizedBox(width: f(8)),
          IconButton(
            icon: Icon(Icons.copy, color: AppColors.textSecondary, size: f(18)),
            tooltip: 'Copier',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              final code = provider.roomCode;
              if (code == null) return;
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Code copié'),
                  backgroundColor: colors.primaryContainer,
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPlayersPanel(
    BuildContext context,
    MultiplayerGameProvider provider,
    int connectedHumans,
    int maxPlayers,
  ) {
    final colors = Theme.of(context).colorScheme;
    final hasScores = provider.cumulativeScores.isNotEmpty;
    final scale = _uiScale(context);
    final size = MediaQuery.of(context).size;
    final isCompactLandscape = size.height < 400 && size.width > size.height;
    double f(double size) => size * scale;

    return Container(
      padding: EdgeInsets.all(f(isCompactLandscape ? 8 : 12)),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(f(isCompactLandscape ? 12 : 16)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.24),
          width: f(1.2),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Si l'espace est trop petit, afficher un placeholder
          if (constraints.maxHeight < 50) {
            return const Center(
              child: Text('...', style: TextStyle(color: AppColors.textDisabled)),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.people, size: f(isCompactLandscape ? 16 : 20), color: Colors.white),
                  SizedBox(width: f(6)),
                  Text(
                    'Joueurs ($connectedHumans/$maxPlayers)',
                    style: TextStyle(
                      fontSize: f(isCompactLandscape ? 13 : 16),
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (hasScores && !isCompactLandscape) ...[
                    const Spacer(),
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: f(8), vertical: f(3)),
                      decoration: BoxDecoration(
                        color: colors.tertiary.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(f(12)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.emoji_events,
                              size: f(14), color: Colors.white),
                          SizedBox(width: f(4)),
                          Text(
                            'Classement',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: f(11),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: f(isCompactLandscape ? 6 : 10)),
              Expanded(
                child: provider.playersInLobby.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: provider.playersInLobby.length,
                        itemBuilder: (context, index) {
                          final player = provider.playersInLobby[index];
                          final isYou = (player['clientId'] != null &&
                                  player['clientId'] == provider.clientId) ||
                              (player['id'] == provider.playerId);
                          final isHost = provider.hostPlayerId != null &&
                              player['id'] == provider.hostPlayerId;
                          final presence =
                              provider.presenceByClientId[player['clientId']] ??
                                  provider.presenceById[player['id']];
                          final isSpectator = presence?['isSpectator'] == true;
                          final isReady = presence?['ready'] == true ||
                              player['ready'] == true;

                          // Chercher le score cumulé du joueur
                          final playerClientId = player['clientId']?.toString();
                          final playerScore =
                              _getPlayerScore(provider, playerClientId);
                          final playerRank =
                              _getPlayerRank(provider, playerClientId);

                          // Version compacte pour petit ecran paysage
                          if (isCompactLandscape) {
                            return Container(
                              margin: EdgeInsets.only(bottom: f(4)),
                              padding: EdgeInsets.symmetric(
                                horizontal: f(8),
                                vertical: f(4),
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.94),
                                borderRadius: BorderRadius.circular(f(8)),
                              ),
                              child: Row(
                                children: [
                                  // Avatar compact
                                  CircleAvatar(
                                    radius: f(12),
                                    backgroundColor: colors.primary,
                                    foregroundColor: colors.onPrimary,
                                    child: Text(
                                      (player['name'] ?? 'J')[0].toUpperCase(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: f(10),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: f(6)),
                                  // Nom et tags
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            player['name'] ?? 'Joueur',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: f(11),
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ),
                                        if (isYou)
                                          _buildMiniTag(context, 'Vous', colors.primary),
                                        if (isHost)
                                          _buildMiniTag(context, 'Hote', colors.secondary),
                                      ],
                                    ),
                                  ),
                                  // Indicateurs
                                  if (isReady && !isSpectator)
                                    Icon(Icons.check_circle, color: colors.tertiary, size: f(14)),
                                  SizedBox(width: f(4)),
                                  _presenceDot(presence),
                                ],
                              ),
                            );
                          }

                          // Version normale
                          return Card(
                            margin: EdgeInsets.only(bottom: f(8)),
                            color: Colors.white.withValues(alpha: 0.94),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(f(12)),
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: f(12),
                                vertical: f(10),
                              ),
                              child: Row(
                                children: [
                                  // Avatar avec rang si scores existent
                                  Stack(
                                    children: [
                                      CircleAvatar(
                                        radius: f(18),
                                        backgroundColor: colors.primary,
                                        foregroundColor: colors.onPrimary,
                                        child: Text(
                                          (player['name'] ?? 'J')[0]
                                              .toUpperCase(),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: f(14),
                                          ),
                                        ),
                                      ),
                                      if (playerRank != null && playerRank <= 3)
                                        Positioned(
                                          right: -2,
                                          bottom: -2,
                                          child: Container(
                                            padding: EdgeInsets.all(f(3)),
                                            decoration: BoxDecoration(
                                              color: _getRankColor(playerRank),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white,
                                                width: f(1.5),
                                              ),
                                            ),
                                            child: Text(
                                              '$playerRank',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: f(9),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  SizedBox(width: f(10)),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                player['name'] ?? 'Joueur',
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: f(14),
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ),
                                            if (isYou)
                                              _buildMiniTag(
                                                  context, 'Vous', colors.primary),
                                            if (isHost)
                                              _buildMiniTag(
                                                  context, 'Hote', colors.secondary),
                                          ],
                                        ),
                                        SizedBox(height: f(2)),
                                        Row(
                                          children: [
                                            Text(
                                              _presenceLabel(presence,
                                                  provider.roomStatus),
                                              style: TextStyle(
                                                fontSize: f(11),
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                            if (playerScore != null) ...[
                                              SizedBox(width: f(8)),
                                              Container(
                                                padding:
                                                    EdgeInsets.symmetric(
                                                  horizontal: f(6),
                                                  vertical: f(1),
                                                ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      colors.primaryContainer,
                                                  borderRadius:
                                                      BorderRadius.circular(f(8)),
                                                ),
                                                child: Text(
                                                  '$playerScore pts',
                                                  style: TextStyle(
                                                    fontSize: f(10),
                                                    fontWeight: FontWeight.bold,
                                                    color: colors
                                                        .onPrimaryContainer,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isReady && !isSpectator)
                                    Icon(Icons.check_circle,
                                        color: colors.tertiary, size: f(20)),
                                  if (isSpectator)
                                    Icon(Icons.visibility,
                                        color: Colors.blueGrey, size: f(20)),
                                  SizedBox(width: f(4)),
                                  _presenceDot(presence),
                                  if (provider.isHost && !isYou) ...[
                                    SizedBox(width: f(8)),
                                    IconButton(
                                      icon: Icon(Icons.remove_circle_outline,
                                          color: Colors.orange, size: f(20)),
                                      tooltip: 'Exclure (peut revenir)',
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Exclure ce joueur ?'),
                                            content: Text(
                                                '${player['name']} sera exclu mais pourra revenir dans la room.'),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(ctx, false),
                                                child: const Text('Annuler'),
                                              ),
                                              FilledButton(
                                                onPressed: () => Navigator.pop(ctx, true),
                                                style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                                                child: const Text('Exclure'),
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirm == true) {
                                          final clientId = player['clientId'] as String?;
                                          if (clientId != null) {
                                            await provider.kickPlayer(clientId);
                                          }
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.block,
                                          color: colors.error, size: f(20)),
                                      tooltip: 'Bannir (définitif)',
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Bannir ce joueur ?'),
                                            content: Text(
                                                '${player['name']} sera banni et ne pourra PLUS rejoindre cette room.'),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(ctx, false),
                                                child: const Text('Annuler'),
                                              ),
                                              FilledButton(
                                                onPressed: () => Navigator.pop(ctx, true),
                                                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                                child: const Text('Bannir'),
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirm == true) {
                                          final clientId = player['clientId'] as String?;
                                          if (clientId != null) {
                                            await provider.banPlayer(clientId);
                                          }
                                        }
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  int? _getPlayerScore(MultiplayerGameProvider provider, String? clientId) {
    if (clientId == null || provider.cumulativeScores.isEmpty) return null;
    for (final entry in provider.cumulativeScores) {
      if (entry['clientId'] == clientId) {
        return entry['score'] as int?;
      }
    }
    return null;
  }

  int? _getPlayerRank(MultiplayerGameProvider provider, String? clientId) {
    if (clientId == null || provider.cumulativeScores.isEmpty) return null;
    for (int i = 0; i < provider.cumulativeScores.length; i++) {
      if (provider.cumulativeScores[i]['clientId'] == clientId) {
        return i + 1; // Rang 1-indexé
      }
    }
    return null;
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700); // Or
      case 2:
        return const Color(0xFFC0C0C0); // Argent
      case 3:
        return const Color(0xFFCD7F32); // Bronze
      default:
        return Colors.grey;
    }
  }

  Widget _buildChatPanel(
      BuildContext context, MultiplayerGameProvider provider) {
    final colors = Theme.of(context).colorScheme;
    final messages = provider.chatMessages;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.24),
          width: 1.2,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = (constraints.maxHeight / 320).clamp(0.55, 1.0);
          double f(double size) => size * scale;
          if (constraints.maxHeight < 120) {
            return Center(
              child: Text(
                'Chat',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontWeight: FontWeight.bold,
                  fontSize: f(12),
                ),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              Row(
                children: [
                  Icon(Icons.forum, size: f(18), color: Colors.white),
                  SizedBox(width: f(6)),
                  Text(
                    'Chat',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: f(14),
                    ),
                  ),
                ],
              ),
              SizedBox(height: f(8)),
              Expanded(
                child: Container(
                  padding: EdgeInsets.all(f(8)),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(f(10)),
                  ),
                  child: messages.isEmpty
                      ? Center(
                          child: Text(
                            'Soyez sympas :)',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: f(11),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _chatScrollController,
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            final isMe = (message['clientId'] != null &&
                                    message['clientId'] == provider.clientId) ||
                                (message['playerId'] == provider.playerId);
                            return Align(
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: EdgeInsets.only(bottom: f(6)),
                                padding: EdgeInsets.symmetric(
                                  horizontal: f(10),
                                  vertical: f(6),
                                ),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.6,
                                ),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? colors.primaryContainer
                                      : Colors.white.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(f(10)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isMe
                                          ? 'Vous'
                                          : (message['name'] ?? 'Joueur'),
                                      style: TextStyle(
                                        fontSize: f(10),
                                        fontWeight: FontWeight.bold,
                                        color: isMe
                                            ? colors.onPrimaryContainer
                                            : colors.primary,
                                      ),
                                    ),
                                    SizedBox(height: f(2)),
                                    Text(
                                      message['message']?.toString() ?? '',
                                      style: TextStyle(
                                        fontSize: f(13),
                                        color: isMe
                                            ? colors.onPrimaryContainer
                                            : Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
              SizedBox(height: f(8)),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: f(40),
                      child: TextField(
                        controller: _chatController,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendChat(provider),
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: f(14),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Message...',
                          hintStyle: TextStyle(
                            color: Colors.black45,
                            fontSize: f(13),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: f(12),
                            vertical: f(8),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(f(10)),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: f(6)),
                  SizedBox(
                    height: f(40),
                    width: f(40),
                    child: IconButton.filled(
                      onPressed: () => _sendChat(provider),
                      icon: Icon(Icons.send, size: f(18)),
                      style: IconButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  void _sendChat(MultiplayerGameProvider provider) {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    provider.sendChatMessage(text);
    _chatController.clear();
    _dismissKeyboard();
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

  int _connectedHumans(MultiplayerGameProvider provider) {
    return provider.playersInLobby.where((player) {
      if (player['isHuman'] != true) return false;
      if (player['isSpectator'] == true) return false;
      return player['connected'] != false;
    }).length;
  }

  Widget _buildSettingChip(
    BuildContext context, {
    required String label,
    required IconData icon,
  }) {
    final scale = _uiScale(context);
    double f(double size) => size * scale;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: f(10), vertical: f(6)),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(f(20)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: f(12), color: Colors.white),
          SizedBox(width: f(4)),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: f(11),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniTag(BuildContext context, String text, Color color) {
    final scale = _uiScale(context);
    double f(double size) => size * scale;
    return Container(
      margin: EdgeInsets.only(left: f(6)),
      padding: EdgeInsets.symmetric(horizontal: f(6), vertical: f(2)),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(f(10)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: f(9),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _presenceLabel(Map<String, dynamic>? presence, String roomStatus) {
    if (presence == null) return 'Statut inconnu';
    if (presence['isSpectator'] == true) return 'Spectateur';
    if (presence['connected'] != true) return 'Deconnecte';
    if (presence['focused'] != true) return 'En arriere-plan';

    if (roomStatus == 'playing') return 'En jeu';

    return presence['ready'] == true ? 'Pret' : 'En ligne';
  }

  Widget _presenceDot(Map<String, dynamic>? presence) {
    Color color = Colors.grey;
    if (presence != null) {
      final isSpectator = presence['isSpectator'] == true;
      final connected = presence['connected'] == true;
      final focused = presence['focused'] == true;

      if (isSpectator) {
        color = Colors.blueGrey;
      } else if (!connected) {
        color = Colors.red;
      } else if (!focused) {
        color = Colors.orange;
      } else if (presence['ready'] == true) {
        color = Colors.teal;
      } else {
        color = Colors.green;
      }
    }

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
