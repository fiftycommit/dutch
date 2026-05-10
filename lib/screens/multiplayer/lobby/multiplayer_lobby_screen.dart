import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
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
import '../../../../../core/service_locator.dart';
import '../../../../../core/interfaces/i_haptic_service.dart';
import 'widgets/lobby_chat_bottom_sheet.dart';
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

  // Overlay du toast "hors ligne" affiché quand un bouton désactivé est tapé.
  OverlayEntry? _offlineToastEntry;

  // État réseau (mis à jour instantanément via connectivity_plus pour réagir
  // au mode avion, sans attendre le timeout heartbeat de Socket.IO).
  bool _hasNetwork = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // Section "Détails du salon" pliable. Ouverte par défaut pour rendre le
  // code de room visible immédiatement ; l'utilisateur peut la replier.
  bool _detailsExpanded = true;

  // Section "Joueurs" pliable (portrait mobile uniquement). Ouverte par défaut.
  bool _playersExpanded = true;

  // Suivi des messages chat lus pour afficher le badge "non lu" sur le bouton
  // d'ouverture du bottom sheet (mobile portrait).
  int _lastSeenChatCount = 0;
  bool _chatSheetOpen = false;

  Difficulty _normalizeDisplayedBotDifficulty(Difficulty difficulty) {
    return difficulty == Difficulty.hard ? Difficulty.platinum : difficulty;
  }

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
      // Considère les messages déjà présents comme "lus" à l'arrivée pour
      // ne pas afficher un badge artificiel.
      _lastSeenChatCount = _provider!.chatMessages.length;
    });
    _initConnectivity();
  }

  Future<void> _initConnectivity() async {
    try {
      final initial = await Connectivity().checkConnectivity();
      if (!mounted) return;
      setState(() => _hasNetwork = _isConnected(initial));
    } catch (_) {
      // plugin indisponible : on suppose qu'il y a du réseau
    }
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      final hasNet = _isConnected(results);
      if (hasNet != _hasNetwork) {
        setState(() => _hasNetwork = hasNet);
      }
    });
  }

  bool _isConnected(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  /// Renvoie l'état "effectif" : si le réseau est coupé (mode avion),
  /// on bascule en `disconnected` sans attendre le heartbeat Socket.IO.
  SocketConnectionState _effectiveConnectionState(
      MultiplayerGameProvider provider) {
    if (!_hasNetwork) return SocketConnectionState.disconnected;
    return provider.connectionState;
  }

  void _onProviderChanged() {
    if (!mounted) return;
    final provider = _provider;
    if (provider == null) return;

    // Si le bottom sheet du chat est ouvert, considère les nouveaux messages
    // comme immédiatement lus (sinon le badge clignoterait au retour).
    if (_chatSheetOpen) {
      _lastSeenChatCount = provider.chatMessages.length;
    }

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
    _connectivitySub?.cancel();
    _offlineToastEntry?.remove();
    _offlineToastEntry = null;
    super.dispose();
  }

  void _showOfflineToast() {
    if (!mounted) return;
    if (_offlineToastEntry != null) return; // déjà visible, pas de spam
    ServiceLocator().get<IHapticService>().error();
    final entry = OverlayEntry(
      builder: (_) => _OfflineToast(
        onDismiss: () {
          if (!mounted) return;
          _offlineToastEntry?.remove();
          _offlineToastEntry = null;
        },
      ),
    );
    _offlineToastEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
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

        // Sur portrait étroit (mobile), le chat est déplacé dans un
        // showModalBottomSheet pour libérer de l'espace et contourner les
        // bugs Flutter Web iOS Safari (clavier qui ne s'ouvre pas avec un
        // GestureDetector parent qui appelle unfocus()).
        final useChatBottomSheet = !isLandscape && !isWide;
        final unreadChat =
            (provider.chatMessages.length - _lastSeenChatCount).clamp(0, 999);
        final isOnline = _effectiveConnectionState(provider) ==
            SocketConnectionState.connected;

        return PopScope(
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) {
              provider.leaveRoom();
            }
          },
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
                            _buildCollapsibleDetails(
                              provider: provider,
                              showPublicBadge: showPublicBadge,
                              showRoomCode: showRoomCode,
                              minPlayers: minPlayers,
                              maxPlayers: maxPlayers,
                              heightScale: heightScale,
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
                                  : _buildPortraitPlayersOnly(
                                      provider,
                                      connectedHumans,
                                      maxPlayers,
                                      heightScale,
                                    ),
                            ),
                            if (useChatBottomSheet) ...[
                              SizedBox(height: contentSpacing),
                              LobbyChatButton(
                                unreadCount: unreadChat,
                                enabled: isOnline,
                                onPressed: () =>
                                    isOnline ? _openChatSheet() : _showOfflineToast(),
                              ),
                            ],
                            SizedBox(height: contentSpacing),
                            _OfflineGate(
                              isOnline: isOnline,
                              onBlockedTap: _showOfflineToast,
                              child: _buildBottomButtons(
                                context,
                                provider,
                                colors,
                                canStart,
                                connectedHumans,
                                maxPlayers,
                                minPlayers,
                                compact: isCompactLandscape,
                              ),
                            ),
                            SizedBox(height: bottomSpacing),
                          ],
                        ),
                      ),
                    ),
                    _buildOfflineBanner(provider),
                  ],
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

    final isLoggedIn = context.read<AuthProvider>().isLoggedIn;
    final width = MediaQuery.of(context).size.width;
    // En dessous de 380dp, on regroupe Inviter + Paramètres dans un menu kebab
    // pour éviter que les labels du header poussent le titre en ellipsis.
    final isNarrow = width < 380;
    final isOnline = _effectiveConnectionState(provider) ==
        SocketConnectionState.connected;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: f(16), vertical: f(12)),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            iconSize: f(22),
            tooltip: 'Retour',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: () => context.go('/multiplayer'),
          ),
          SizedBox(width: f(4)),
          Flexible(
            child: Text(
              "Salle d'attente",
              style: TextStyle(
                fontSize: f(isNarrow ? 17 : 20),
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          if (provider.isHost && isNarrow)
            _buildHostOverflowMenu(
              context,
              provider,
              isLoggedIn: isLoggedIn,
              isOnline: isOnline,
            )
          else ...[
            if (provider.isHost && isLoggedIn) ...[
              _buildHeaderAction(
                context,
                icon: Icons.person_add,
                label: 'Inviter',
                onPressed: isOnline
                    ? () => _showInviteFriendDialog(context, provider)
                    : _showOfflineToast,
                enabled: isOnline,
              ),
              SizedBox(width: f(6)),
            ],
            if (provider.isHost) ...[
              _buildHeaderAction(
                context,
                icon: Icons.tune,
                label: 'Paramètres',
                onPressed: isOnline
                    ? () => _showSettingsDialog(context, provider)
                    : _showOfflineToast,
                enabled: isOnline,
              ),
              SizedBox(width: f(6)),
            ],
          ],
          if (provider.isHost && isNarrow) SizedBox(width: f(6)),
          _buildHeaderAction(
            context,
            icon: Icons.logout,
            label: 'Quitter',
            iconOnly: isNarrow,
            onPressed: () => _handleLeaveOrClose(context, provider),
            destructive: true,
          ),
        ],
      ),
    );
  }

  /// Menu kebab regroupant Inviter + Paramètres pour les hôtes sur écrans
  /// étroits. Les actions désactivées (offline) déclenchent le toast.
  Widget _buildHostOverflowMenu(
    BuildContext context,
    MultiplayerGameProvider provider, {
    required bool isLoggedIn,
    required bool isOnline,
  }) {
    return PopupMenuButton<String>(
      tooltip: 'Plus',
      icon: const Icon(Icons.more_vert, color: Colors.white),
      iconSize: 22,
      // Touch target accessible : 44dp min.
      padding: const EdgeInsets.all(10),
      color: const Color(0xFF1a3a28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
      ),
      onSelected: (value) {
        if (!isOnline) {
          _showOfflineToast();
          return;
        }
        switch (value) {
          case 'invite':
            _showInviteFriendDialog(context, provider);
            break;
          case 'settings':
            _showSettingsDialog(context, provider);
            break;
        }
      },
      itemBuilder: (ctx) => [
        if (isLoggedIn)
          const PopupMenuItem<String>(
            value: 'invite',
            child: Row(
              children: [
                Icon(Icons.person_add, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Text('Inviter', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        const PopupMenuItem<String>(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.tune, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text('Paramètres', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool destructive = false,
    bool enabled = true,
    bool iconOnly = false,
  }) {
    final scale = _uiScale(context);
    double f(double size) => size * scale;

    final bg = destructive
        ? Colors.redAccent.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.10);
    final borderColor = destructive
        ? Colors.redAccent.withValues(alpha: 0.45)
        : Colors.white.withValues(alpha: 0.22);
    final fg = destructive ? const Color(0xFFFF8A80) : Colors.white;

    // Garantit un touch target ≥ 44dp même au scale minimum.
    final minSide = iconOnly ? 44.0 : 44.0;

    final actionWidget = Semantics(
      button: true,
      label: label,
      enabled: enabled,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(f(14)),
          onTap: onPressed,
          child: Container(
            constraints:
                BoxConstraints(minHeight: minSide, minWidth: minSide),
            padding: iconOnly
                ? EdgeInsets.zero
                : EdgeInsets.symmetric(horizontal: f(10), vertical: f(6)),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(f(14)),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: fg, size: f(18)),
                if (!iconOnly) ...[
                  SizedBox(width: f(6)),
                  Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w600,
                      fontSize: f(13),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: actionWidget,
    );
  }

  Widget _buildOfflineBanner(MultiplayerGameProvider provider) {
    final state = _effectiveConnectionState(provider);
    if (state == SocketConnectionState.connected) {
      return const SizedBox.shrink();
    }

    final String label;
    final IconData icon;
    final Color color;
    if (!_hasNetwork) {
      label = 'Pas de réseau — vérifie ta connexion';
      icon = Icons.wifi_off;
      color = const Color(0xFFB23A48);
    } else {
      switch (state) {
        case SocketConnectionState.connecting:
          label = 'Connexion au serveur…';
          icon = Icons.wifi_find;
          color = const Color(0xFFB35C00);
          break;
        case SocketConnectionState.reconnecting:
          label = 'Reconnexion…';
          icon = Icons.wifi_off;
          color = const Color(0xFFB35C00);
          break;
        case SocketConnectionState.disconnected:
          label = 'Non connecté — interactions désactivées';
          icon = Icons.wifi_off;
          color = const Color(0xFFB23A48);
          break;
        case SocketConnectionState.connected:
          return const SizedBox.shrink();
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: color,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
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
    Difficulty botDifficulty =
        _normalizeDisplayedBotDifficulty(settings.botDifficulty);
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
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<Difficulty>(
                    emptySelectionAllowed: true,
                    segments: const [
                      ButtonSegment(
                        value: Difficulty.easy,
                        label: Text('Facile'),
                      ),
                      ButtonSegment(
                        value: Difficulty.medium,
                        label: Text('Moyen'),
                      ),
                      ButtonSegment(
                        value: Difficulty.platinum,
                        label: Text('Difficile'),
                      ),
                    ],
                    selected: botDifficulty == Difficulty.mix
                        ? <Difficulty>{}
                        : {botDifficulty},
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) return;
                      setState(() => botDifficulty = selection.first);
                    },
                  ),
                  ChoiceChip(
                    avatar: Icon(
                      Icons.shuffle,
                      size: 16,
                      color: botDifficulty == Difficulty.mix
                          ? Colors.black
                          : Colors.white,
                    ),
                    label: const Text('Mix'),
                    selected: botDifficulty == Difficulty.mix,
                    onSelected: (_) {
                      setState(() => botDifficulty = Difficulty.mix);
                    },
                    selectedColor: Colors.blueGrey.shade200,
                    backgroundColor: Colors.blueGrey.shade700,
                    labelStyle: TextStyle(
                      color: botDifficulty == Difficulty.mix
                          ? Colors.black
                          : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    side: BorderSide(color: Colors.blueGrey.shade400),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                ServiceLocator().get<IHapticService>().buttonTap();
                Navigator.pop(ctx, {
                  'botDifficulty': botDifficulty.index,
                });
              },
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
              onPressed: () {
                ServiceLocator().get<IHapticService>().buttonTap();
                Navigator.pop(ctx, true);
              },
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
              onPressed: () {
                ServiceLocator().get<IHapticService>().buttonTap();
                Navigator.pop(ctx, true);
              },
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
            onPressed: () {
              ServiceLocator().get<IHapticService>().buttonTap();
              Navigator.pop(ctx, 'become_host');
            },
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
    final isOnline =
        _effectiveConnectionState(provider) == SocketConnectionState.connected;
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
          child: _OfflineGate(
            isOnline: isOnline,
            onBlockedTap: _showOfflineToast,
            child: LobbyChatPanel(
              provider: provider,
              chatController: _chatController,
              chatScrollController: _chatScrollController,
              onDismissKeyboard: _dismissKeyboard,
            ),
          ),
        ),
      ],
    );
  }

  /// Portrait mobile : seulement la liste des joueurs. Le chat est déporté
  /// dans un `showModalBottomSheet` (cf. `_openChatSheet`).
  Widget _buildPortraitPlayersOnly(
    MultiplayerGameProvider provider,
    int connectedHumans,
    int maxPlayers,
    double scale,
  ) {
    return LobbyPlayersPanel(
      provider: provider,
      connectedHumans: connectedHumans,
      maxPlayers: maxPlayers,
      uiScale: scale,
      isExpanded: _playersExpanded,
      onToggleExpanded: () {
        ServiceLocator().get<IHapticService>().buttonTap();
        setState(() => _playersExpanded = !_playersExpanded);
      },
    );
  }

  Future<void> _openChatSheet() async {
    final provider = _provider;
    if (provider == null) return;
    setState(() {
      _chatSheetOpen = true;
      _lastSeenChatCount = provider.chatMessages.length;
    });
    await LobbyChatBottomSheet.show(
      context,
      provider: provider,
      controller: _chatController,
      scrollController: _chatScrollController,
    );
    if (!mounted) return;
    setState(() {
      _chatSheetOpen = false;
      // Tout ce qui est arrivé pendant l'ouverture est lu.
      _lastSeenChatCount = provider.chatMessages.length;
    });
  }

  /// Section "Détails du salon" pliable. Affiche en repliée un résumé compact
  /// (code/badge + mode + min/max) ; en dépliée, les widgets complets.
  Widget _buildCollapsibleDetails({
    required MultiplayerGameProvider provider,
    required bool showPublicBadge,
    required bool showRoomCode,
    required int minPlayers,
    required int maxPlayers,
    required double heightScale,
  }) {
    final colors = Theme.of(context).colorScheme;
    final settings = provider.roomSettings;
    final modeLabel = settings == null
        ? null
        : (settings.gameMode == GameMode.quick ? 'Rapide' : 'Tournoi');

    final summary = <String>[
      if (showPublicBadge)
        'Salon public'
      else if (showRoomCode)
        provider.roomCode ?? '------',
      if (modeLabel != null) modeLabel,
      '$minPlayers–$maxPlayers joueurs',
    ].join(' · ');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      margin: EdgeInsets.symmetric(vertical: 4 * heightScale),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              ServiceLocator().get<IHapticService>().buttonTap();
              setState(() => _detailsExpanded = !_detailsExpanded);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _detailsExpanded
                        ? Icons.info
                        : Icons.info_outline,
                    color: Colors.white.withValues(alpha: 0.85),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _detailsExpanded ? 'Détails du salon' : summary,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 200),
                    turns: _detailsExpanded ? 0.5 : 0,
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: colors.tertiary,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeOutCubic,
            crossFadeState: _detailsExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
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
                ],
              ),
            ),
          ),
        ],
      ),
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
          onPressed: () {
            ServiceLocator().get<IHapticService>().buttonTap();
            provider.watchGame();
          },
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
                  onPressed: () {
                    ServiceLocator().get<IHapticService>().buttonTap();
                    provider.setReady(!provider.isReady);
                  },
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
                      ? () {
                          ServiceLocator().get<IHapticService>().buttonTap();
                          _handleStartPressed(
                            context,
                            provider,
                            connectedHumans,
                            maxPlayers,
                          );
                        }
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
            onPressed: () {
              ServiceLocator().get<IHapticService>().buttonTap();
              provider.setReady(!provider.isReady);
            },
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
    Difficulty botDifficulty = _normalizeDisplayedBotDifficulty(
      provider.roomSettings?.botDifficulty ?? Difficulty.medium,
    );

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
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<Difficulty>(
                        emptySelectionAllowed: true,
                        style: SegmentedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          selectedForegroundColor: Colors.white,
                          selectedBackgroundColor: const Color(0xFF2E7D32),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: Difficulty.easy,
                            label: Text('Facile'),
                          ),
                          ButtonSegment(
                            value: Difficulty.medium,
                            label: Text('Moyen'),
                          ),
                          ButtonSegment(
                            value: Difficulty.platinum,
                            label: Text('Difficile'),
                          ),
                        ],
                        selected: botDifficulty == Difficulty.mix
                            ? <Difficulty>{}
                            : {botDifficulty},
                        onSelectionChanged: (selection) {
                          if (selection.isEmpty) return;
                          setState(() => botDifficulty = selection.first);
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ChoiceChip(
                        avatar: Icon(
                          Icons.shuffle,
                          size: 16,
                          color: botDifficulty == Difficulty.mix
                              ? Colors.black
                              : Colors.white,
                        ),
                        label: const Text('Mix'),
                        selected: botDifficulty == Difficulty.mix,
                        onSelected: (_) {
                          setState(() => botDifficulty = Difficulty.mix);
                        },
                        selectedColor: Colors.blueGrey.shade200,
                        backgroundColor: Colors.blueGrey.shade700,
                        labelStyle: TextStyle(
                          color: botDifficulty == Difficulty.mix
                              ? Colors.black
                              : Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        side: BorderSide(color: Colors.blueGrey.shade400),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
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
              onPressed: () {
                ServiceLocator().get<IHapticService>().buttonTap();
                Navigator.pop(dialogContext, {
                  'numberOfBots': numberOfBots,
                  'useSBMM': useSBMM,
                  'botDifficulty': useSBMM ? null : botDifficulty.index,
                });
              },
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
          width: (MediaQuery.of(ctx).size.width - 48).clamp(0.0, 300.0),
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

/// Encadre un sous-arbre interactif et capte tous les taps quand on est hors
/// ligne, en déclenchant `onBlockedTap`. Quand en ligne, le widget est
/// transparent et laisse passer les évènements normalement.
class _OfflineGate extends StatelessWidget {
  final bool isOnline;
  final Widget child;
  final VoidCallback onBlockedTap;

  const _OfflineGate({
    required this.isOnline,
    required this.child,
    required this.onBlockedTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: isOnline ? 1.0 : 0.5,
          child: child,
        ),
        if (!isOnline)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onBlockedTap,
            ),
          ),
      ],
    );
  }
}

/// Toast centré sur l'écran avec barre de progression de 5 s.
/// Joue un haptic d'erreur à l'apparition et s'auto-ferme à la fin.
class _OfflineToast extends StatefulWidget {
  final VoidCallback onDismiss;

  const _OfflineToast({required this.onDismiss});

  @override
  State<_OfflineToast> createState() => _OfflineToastState();
}

class _OfflineToastState extends State<_OfflineToast>
    with SingleTickerProviderStateMixin {
  static const Duration _totalDuration = Duration(seconds: 5);
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _totalDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onDismiss();
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Material(
                color: Colors.transparent,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final progress = 1.0 - _controller.value;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A).withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFB23A48).withValues(alpha: 0.7),
                          width: 1.4,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 20,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off,
                              color: Color(0xFFFF8A80), size: 36),
                          const SizedBox(height: 10),
                          const Text(
                            'Action indisponible',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tu es hors ligne — reconnecte-toi pour continuer',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 4,
                              backgroundColor: Colors.white12,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFFFF8A80),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
