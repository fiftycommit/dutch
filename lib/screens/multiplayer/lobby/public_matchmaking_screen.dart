import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../../../providers/multiplayer_game_provider.dart';
import '../../../../../providers/auth_provider.dart';
import '../../../../../utils/ui_constants.dart';
import 'dart:async';

class PublicMatchmakingScreen extends StatefulWidget {
  const PublicMatchmakingScreen({super.key});

  @override
  State<PublicMatchmakingScreen> createState() =>
      _PublicMatchmakingScreenState();
}

class _PublicMatchmakingScreenState extends State<PublicMatchmakingScreen> {
  List<Map<String, dynamic>>? _publicRooms;
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadPublicRooms();
    // Rafraîchir toutes les 5 secondes
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _loadPublicRooms();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPublicRooms() async {
    final provider =
        Provider.of<MultiplayerGameProvider>(context, listen: false);

    final rooms = await provider.getPublicRooms();

    if (mounted) {
      setState(() {
        _publicRooms = rooms;
        _isLoading = false;
      });
    }
  }

  Future<void> _joinRoom(String roomCode, String playerName) async {
    final provider =
        Provider.of<MultiplayerGameProvider>(context, listen: false);

    try {
      await provider.joinRoom(
        roomCode: roomCode,
        playerName: playerName,
      );

      if (!mounted) return;
      context.go('/lobby');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _connectedPlayerName() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final displayName = authProvider.user?.displayName.trim() ?? '';
    if (displayName.isNotEmpty) {
      return displayName;
    }
    final username = authProvider.user?.username.trim() ?? '';
    if (username.isNotEmpty) {
      return username;
    }
    return 'Joueur';
  }

  Future<void> _goBack() async {
    final didPop = await Navigator.of(context).maybePop();
    if (!didPop && mounted) {
      context.go('/multiplayer/join-selection');
    }
  }

  String _getTierFromMMR(int? mmr) {
    if (mmr == null) return 'Bronze';

    // Même logique que CompetitiveService._getTier()
    if (mmr >= 2200) return 'Diamant';
    if (mmr >= 1900) return 'Platine';
    if (mmr >= 1600) return 'Or';
    if (mmr >= 1300) return 'Argent';
    return 'Bronze';
  }

  Color _getTierColor(String tier) {
    switch (tier) {
      case 'Diamant':
        return Colors.cyan.shade700;
      case 'Platine':
        return Colors.purple.shade400;
      case 'Or':
        return Colors.amber.shade700;
      case 'Argent':
        return Colors.grey.shade600;
      case 'Bronze':
        return Colors.brown.shade600;
      default:
        return Colors.grey;
    }
  }

  IconData _getTierIcon(String tier) {
    switch (tier) {
      case 'Diamant':
        return Icons.diamond;
      case 'Platine':
      case 'Or':
      case 'Argent':
        return Icons.military_tech;
      case 'Bronze':
        return Icons.shield;
      default:
        return Icons.emoji_events;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.gradientTop,
              AppColors.gradientBottom,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: _goBack,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'SALONS PUBLICS',
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: _loadPublicRooms,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.amber),
                      )
                    : _publicRooms == null || _publicRooms!.isEmpty
                        ? _buildEmptyState()
                        : _buildRoomList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 20 : 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search_off,
                      size: isMobile ? 80 : 100,
                      color: AppColors.textDisabled,
                    ),
                    SizedBox(height: isMobile ? 16 : 24),
                    Text(
                      'Aucun salon disponible',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isMobile ? 20 : 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: isMobile ? 8 : 12),
                    Text(
                      'Créez un salon ou réessayez plus tard',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: isMobile ? 14 : 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoomList() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        return ListView.builder(
          padding: EdgeInsets.all(isMobile ? 16 : 20),
          itemCount: _publicRooms!.length,
          itemBuilder: (context, index) {
            final room = _publicRooms![index];
            final roomCode = room['code'] as String;
            final roomName = room['roomName'] as String?;
            final players = room['players'] as int;
            final maxPlayers = room['maxPlayers'] as int;
            final host = room['host'] as String;
            final hostMMR = room['hostMMR'] as int?;
            final tier = _getTierFromMMR(hostMMR);
            final tierColor = _getTierColor(tier);
            final tierIcon = _getTierIcon(tier);

            return Card(
              margin: EdgeInsets.only(bottom: isMobile ? 12 : 16),
              color: Colors.white.withValues(alpha: 0.95),
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: InkWell(
                onTap: () => _showJoinDialog(roomCode),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: EdgeInsets.all(isMobile ? 16 : 20),
                  child: Row(
                    children: [
                      Container(
                        width: isMobile ? 50 : 60,
                        height: isMobile ? 50 : 60,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.people,
                          size: isMobile ? 28 : 32,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      SizedBox(width: isMobile ? 12 : 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (roomName != null && roomName.isNotEmpty) ...[
                              Text(
                                roomName,
                                style: TextStyle(
                                  fontSize: isMobile ? 16 : 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Code: $roomCode',
                                style: TextStyle(
                                  fontSize: isMobile ? 12 : 14,
                                  color: Colors.black54,
                                  letterSpacing: 1,
                                ),
                              ),
                            ] else
                              Text(
                                roomCode,
                                style: TextStyle(
                                  fontSize: isMobile ? 16 : 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                  letterSpacing: 2,
                                ),
                              ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isMobile ? 6 : 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: tierColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        tierIcon,
                                        size: isMobile ? 12 : 14,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        tier,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: isMobile ? 10 : 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: isMobile ? 4 : 6),
                            Text(
                              'Hôte: $host',
                              style: TextStyle(
                                fontSize: isMobile ? 13 : 14,
                                color: Colors.black54,
                              ),
                            ),
                            SizedBox(height: isMobile ? 4 : 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.person,
                                  size: isMobile ? 14 : 16,
                                  color: Colors.black54,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$players/$maxPlayers joueurs',
                                  style: TextStyle(
                                    fontSize: isMobile ? 13 : 14,
                                    color: Colors.black54,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.blue.shade700,
                        size: isMobile ? 18 : 20,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showJoinDialog(String roomCode) {
    final playerName = _connectedPlayerName();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rejoindre le salon'),
        content: Text(
          'Tu vas rejoindre ce salon en tant que "$playerName".',
          style: const TextStyle(color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _joinRoom(roomCode, playerName);
            },
            child: const Text('Rejoindre'),
          ),
        ],
      ),
    );
  }
}
