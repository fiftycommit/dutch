import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/multiplayer_game_provider.dart';
import '../services/multiplayer_service.dart';
import '../models/game_state.dart';

import 'multiplayer_memorization_screen.dart';

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
    _chatController.dispose();
    _chatScrollController.dispose();
    _eventSubscription?.cancel();
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MultiplayerGameProvider>(
      builder: (context, provider, _) {
        // Naviguer vers le jeu si la partie a commencé
        if (provider.isPlaying && provider.gameState != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const MultiplayerMemorizationScreen(),
              ),
            );
          });
        }

        // Afficher dialog si la room a été fermée par l'hôte
        if (provider.roomClosedByHost) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showRoomClosedDialog(context, provider);
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
                              _buildRoomCodeCard(context, provider, colors),
                              if (provider.roomSettings != null)
                                _buildSettingsRow(
                                    provider, minPlayers, maxPlayers),
                              const SizedBox(height: 8),
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
                              const SizedBox(height: 12),
                              _buildBottomButtons(
                                context,
                                provider,
                                colors,
                                canStart,
                                connectedHumans,
                                maxPlayers,
                                minPlayers,
                              ),
                              const SizedBox(height: 16),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Bouton Quitter/Fermer
          IconButton(
            icon: Icon(
              provider.isHost ? Icons.close : Icons.arrow_back,
              color: Colors.white,
            ),
            tooltip: provider.isHost ? 'Fermer la room' : 'Quitter',
            onPressed: () => _handleLeaveOrClose(context, provider),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              "Salle d'attente",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          _buildConnectionIndicator(provider, colors),
        ],
      ),
    );
  }

  Widget _buildConnectionIndicator(
    MultiplayerGameProvider provider,
    ColorScheme colors,
  ) {
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
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
          Navigator.pop(context);
        }
      }
    } else {
      // Simplement quitter
      provider.leaveRoom();
      if (mounted) {
        Navigator.pop(context);
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
        Navigator.pop(context); // Close dialog
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context); // Leave lobby
        }
      }
    } else {
      provider.acknowledgeRoomClosed();
      Navigator.pop(context); // Close dialog
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context); // Leave lobby
      }
    }
  }

  Widget _buildSettingsRow(
    MultiplayerGameProvider provider,
    int minPlayers,
    int maxPlayers,
  ) {
    final isQuickMode = provider.roomSettings!.gameMode == GameMode.quick;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          // Mode de jeu - modifiable par l'hôte
          if (provider.isHost)
            _buildGameModeSelector(provider, isQuickMode)
          else
            _buildSettingChip(
              label: isQuickMode ? 'Rapide' : 'Tournoi',
              icon: Icons.flag,
            ),
          _buildSettingChip(
            label: 'Min $minPlayers',
            icon: Icons.people,
          ),
          _buildSettingChip(
            label: 'Max $maxPlayers',
            icon: Icons.groups,
          ),
        ],
      ),
    );
  }

  Widget _buildGameModeSelector(
    MultiplayerGameProvider provider,
    bool isQuickMode,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeButton(
            label: 'Rapide',
            icon: Icons.bolt,
            isSelected: isQuickMode,
            onTap: () => provider.setGameMode(GameMode.quick),
          ),
          _buildModeButton(
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
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : Colors.white70,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 11,
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: _buildPlayersPanel(
              context, provider, connectedHumans, maxPlayers),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
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
    return Column(
      children: [
        Expanded(
          flex: 2,
          child: _buildPlayersPanel(
              context, provider, connectedHumans, maxPlayers),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
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
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => provider.setReady(!provider.isReady),
                icon: Icon(
                  provider.isReady
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 20,
                ),
                label: Text(provider.isReady ? 'Pret' : 'Passer pret'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor:
                      provider.isReady ? colors.tertiary : Colors.white,
                  foregroundColor:
                      provider.isReady ? Colors.white : colors.primary,
                  elevation: provider.isReady ? 6 : 2,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: canStart
                    ? () => _handleStartPressed(
                          context,
                          provider,
                          connectedHumans,
                          maxPlayers,
                        )
                    : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: colors.primaryContainer,
                  foregroundColor: colors.onPrimaryContainer,
                  disabledBackgroundColor: Colors.white.withValues(alpha: 0.35),
                ),
                child: Text(
                  provider.isHost
                      ? (canStart
                          ? 'Lancer'
                          : 'Pret: ${provider.readyHumanCount}/$minPlayers')
                      : "Attente hote",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (!provider.isHost)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              provider.isReady
                  ? "Tu es pret. L'hote peut lancer."
                  : 'Appuie sur "Passer pret"',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRoomCodeCard(
    BuildContext context,
    MultiplayerGameProvider provider,
    ColorScheme colors,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.26),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            children: [
              Text(
                'Code',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                provider.roomCode ?? '------',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white),
            tooltip: 'Copier',
            onPressed: () {
              final code = provider.roomCode;
              if (code == null) return;
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Code copie'),
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
          // Si l'espace est trop petit, afficher un placeholder
          if (constraints.maxHeight < 50) {
            return const Center(
              child: Text('...', style: TextStyle(color: Colors.white54)),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.people, size: 20, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'Joueurs ($connectedHumans/$maxPlayers)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (hasScores) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colors.tertiary.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.emoji_events,
                              size: 14, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'Classement',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
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

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: Colors.white.withValues(alpha: 0.94),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  // Avatar avec rang si scores existent
                                  Stack(
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: colors.primary,
                                        foregroundColor: colors.onPrimary,
                                        child: Text(
                                          (player['name'] ?? 'J')[0]
                                              .toUpperCase(),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      if (playerRank != null && playerRank <= 3)
                                        Positioned(
                                          right: -2,
                                          bottom: -2,
                                          child: Container(
                                            padding: const EdgeInsets.all(3),
                                            decoration: BoxDecoration(
                                              color: _getRankColor(playerRank),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 1.5,
                                              ),
                                            ),
                                            child: Text(
                                              '$playerRank',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 10),
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
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ),
                                            if (isYou)
                                              _buildMiniTag(
                                                  'Vous', colors.primary),
                                            if (isHost)
                                              _buildMiniTag(
                                                  'Hote', colors.secondary),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Text(
                                              _presenceLabel(presence),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                            if (playerScore != null) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 1,
                                                ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      colors.primaryContainer,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  '$playerScore pts',
                                                  style: TextStyle(
                                                    fontSize: 10,
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
                                        color: colors.tertiary, size: 20),
                                  if (isSpectator)
                                    const Icon(Icons.visibility,
                                        color: Colors.blueGrey, size: 20),
                                  const SizedBox(width: 4),
                                  _presenceDot(presence),
                                  if (provider.isHost && !isYou) ...[
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(Icons.remove_circle_outline,
                                          color: colors.error, size: 20),
                                      tooltip: 'Expulser',
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text(
                                                'Expulser ce joueur ?'),
                                            content: Text(
                                                'Voulez-vous vraiment expulser ${player['name']} ?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text('Annuler'),
                                              ),
                                              FilledButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                style: FilledButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.red),
                                                child: const Text('Expulser'),
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirm == true) {
                                          final clientId =
                                              player['clientId'] as String?;
                                          if (clientId != null) {
                                            await provider.kickPlayer(clientId);
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.forum, size: 18, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'Chat',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: messages.isEmpty
                  ? Center(
                      child: Text(
                        'Soyez sympas :)',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 11,
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
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.6,
                            ),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? colors.primaryContainer
                                  : Colors.white.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isMe ? 'Vous' : (message['name'] ?? 'Joueur'),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isMe
                                        ? colors.onPrimaryContainer
                                        : colors.primary,
                                  ),
                                ),
                                Text(
                                  message['message']?.toString() ?? '',
                                  style: TextStyle(
                                    fontSize: 13,
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
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _chatController,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendChat(provider),
                    style: const TextStyle(color: Colors.black87, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Message...',
                      hintStyle:
                          const TextStyle(color: Colors.black45, fontSize: 13),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                height: 40,
                width: 40,
                child: IconButton.filled(
                  onPressed: () => _sendChat(provider),
                  icon: const Icon(Icons.send, size: 18),
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
    bool fillBots = false;
    if (connectedHumans < maxPlayers) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Completer la table ?'),
          content: Text(
            'Vous etes $connectedHumans/$maxPlayers.\n'
            'Remplir avec des bots ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Non'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Oui'),
            ),
          ],
        ),
      );
      fillBots = choice == true;
    }

    await provider.startGame(fillBots: fillBots);
    if (!mounted) return;
    if (provider.errorMessage != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(provider.errorMessage!)),
      );
      provider.clearError();
    }
  }

  int _connectedHumans(MultiplayerGameProvider provider) {
    return provider.playersInLobby.where((player) {
      if (player['isHuman'] != true) return false;
      if (player['isSpectator'] == true) return false;
      return player['connected'] != false;
    }).length;
  }

  Widget _buildSettingChip({required String label, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniTag(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _presenceLabel(Map<String, dynamic>? presence) {
    if (presence == null) return 'Statut inconnu';
    if (presence['isSpectator'] == true) return 'Spectateur';
    if (presence['connected'] != true) return 'Deconnecte';
    if (presence['focused'] != true) return 'En arriere-plan';
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
