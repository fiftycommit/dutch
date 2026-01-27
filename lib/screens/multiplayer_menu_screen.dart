import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/multiplayer_game_provider.dart';
import '../models/game_state.dart';
import '../models/game_settings.dart';
import '../services/multiplayer_service.dart';
import 'multiplayer_lobby_screen.dart';

enum _MenuFlow { choose, create, join }

class MultiplayerMenuScreen extends StatefulWidget {
  const MultiplayerMenuScreen({super.key});

  @override
  State<MultiplayerMenuScreen> createState() => _MultiplayerMenuScreenState();
}

class _MultiplayerMenuScreenState extends State<MultiplayerMenuScreen> {
  final _nameController = TextEditingController(text: 'Joueur');
  final _roomCodeController = TextEditingController();
  GameMode _gameMode = GameMode.quick;
  _MenuFlow _flow = _MenuFlow.choose;

  // Mes rooms sauvegardées
  List<SavedRoom> _myRooms = [];
  List<Map<String, dynamic>> _activeRooms = [];
  bool _loadingRooms = false;

  @override
  void initState() {
    super.initState();
    _loadMyRooms();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _roomCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadMyRooms() async {
    setState(() => _loadingRooms = true);

    final provider = context.read<MultiplayerGameProvider>();
    final savedRooms = await provider.getMyRooms();

    if (savedRooms.isEmpty) {
      setState(() {
        _myRooms = [];
        _activeRooms = [];
        _loadingRooms = false;
      });
      return;
    }

    // Vérifier quelles rooms sont actives
    final roomCodes = savedRooms.map((r) => r.roomCode).toList();
    final active = await provider.checkActiveRooms(roomCodes);

    if (!mounted) return;

    setState(() {
      _myRooms = savedRooms;
      _activeRooms = active;
      _loadingRooms = false;
    });

    // Nettoyer les rooms inactives
    await provider.cleanupInactiveRooms();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.primary.withValues(alpha: 0.94),
              colors.secondary.withValues(alpha: 0.94),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        if (_flow == _MenuFlow.choose) {
                          Navigator.pop(context);
                        } else {
                          setState(() => _flow = _MenuFlow.choose);
                        }
                      },
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Multijoueur en ligne',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: SizedBox(
                      key: ValueKey(_flow),
                      width: 520,
                      child: _buildFlow(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFlow(BuildContext context) {
    switch (_flow) {
      case _MenuFlow.create:
        return _buildCreate(context);
      case _MenuFlow.join:
        return _buildJoin(context);
      case _MenuFlow.choose:
        return _buildChoose(context);
    }
  }

  Widget _buildChoose(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeroCard(
            context,
            icon: Icons.add_circle,
            title: 'Creer une partie',
            subtitle: 'Tu deviens hote et tu invites tes amis.',
            color: colors.primaryContainer,
            onTap: () => setState(() => _flow = _MenuFlow.create),
          ),
          const SizedBox(height: 16),
          _buildHeroCard(
            context,
            icon: Icons.login,
            title: 'Rejoindre une partie',
            subtitle: 'Entre un code a 6 caracteres pour rejoindre.',
            color: colors.secondaryContainer,
            onTap: () => setState(() => _flow = _MenuFlow.join),
          ),
          const SizedBox(height: 24),
          _buildMyRoomsSection(context, colors),
        ],
      ),
    );
  }

  Widget _buildMyRoomsSection(BuildContext context, ColorScheme colors) {
    // Ne rien afficher si aucune room sauvegardée
    if (_myRooms.isEmpty && !_loadingRooms) {
      return const SizedBox.shrink();
    }

    final activeRoomCodes = _activeRooms.map((r) => r['roomCode'] as String).toSet();
    final activeMyRooms = _myRooms.where((r) => activeRoomCodes.contains(r.roomCode)).toList();

    if (activeMyRooms.isEmpty && !_loadingRooms) {
      return const SizedBox.shrink();
    }

    return Card(
      color: Colors.white.withValues(alpha: 0.14),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.26)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Mes rooms',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                if (_loadingRooms)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
                    onPressed: _loadMyRooms,
                    tooltip: 'Actualiser',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingRooms)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Chargement...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              )
            else if (activeMyRooms.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Aucune room active',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              )
            else
              ...activeMyRooms.map((room) {
                final roomInfo = _activeRooms.firstWhere(
                  (r) => r['roomCode'] == room.roomCode,
                  orElse: () => {},
                );
                final playerCount = roomInfo['playerCount'] ?? 0;
                final status = roomInfo['status'] ?? 'unknown';

                return _buildRoomTile(
                  context,
                  room: room,
                  playerCount: playerCount,
                  status: status,
                  colors: colors,
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomTile(
    BuildContext context, {
    required SavedRoom room,
    required int playerCount,
    required String status,
    required ColorScheme colors,
  }) {
    final isHost = room.isHost;
    final statusLabel = status == 'waiting'
        ? 'En attente'
        : status == 'playing'
            ? 'En cours'
            : status;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isHost ? colors.primaryContainer : colors.secondaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isHost ? Icons.star : Icons.group,
            color: colors.onPrimaryContainer,
          ),
        ),
        title: Row(
          children: [
            Text(
              room.roomCode,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 8),
            if (isHost)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Hôte',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '$statusLabel • $playerCount joueur${playerCount > 1 ? 's' : ''}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        trailing: FilledButton(
          onPressed: () => _rejoinRoom(context, room.roomCode),
          style: FilledButton.styleFrom(
            backgroundColor: colors.primaryContainer,
            foregroundColor: colors.onPrimaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: const Text('Rejoindre'),
        ),
      ),
    );
  }

  Future<void> _rejoinRoom(BuildContext context, String roomCode) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Veuillez entrer votre nom');
      return;
    }

    final provider = context.read<MultiplayerGameProvider>();
    final navigator = Navigator.of(context);

    try {
      await provider.joinRoom(
        roomCode: roomCode,
        playerName: name,
      );

      if (!mounted || provider.roomCode == null) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => const MultiplayerLobbyScreen(),
        ),
      );
    } catch (e) {
      _showError(e.toString());
    }
  }

  Widget _buildCreate(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      color: Colors.white.withValues(alpha: 0.96),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configurer la partie',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 16),
            _buildNameField(),
            const SizedBox(height: 18),
            Text(
              'Mode de jeu',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<GameMode>(
              segments: const [
                ButtonSegment(
                  value: GameMode.quick,
                  label: Text('Partie rapide'),
                  icon: Icon(Icons.flash_on),
                ),
                ButtonSegment(
                  value: GameMode.tournament,
                  label: Text('Tournoi'),
                  icon: Icon(Icons.emoji_events),
                ),
              ],
              selected: {_gameMode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                setState(() => _gameMode = selection.first);
              },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return colors.primaryContainer;
                  }
                  return Colors.white;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return colors.onPrimaryContainer;
                  }
                  return colors.primary;
                }),
                side: WidgetStatePropertyAll(
                  BorderSide(color: colors.primary.withValues(alpha: 0.3)),
                ),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _createRoom(context),
                icon: const Icon(Icons.rocket_launch),
                label: const Text('Creer et ouvrir le lobby'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoin(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      color: Colors.white.withValues(alpha: 0.96),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rejoindre un lobby',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 16),
            _buildNameField(),
            const SizedBox(height: 16),
            TextField(
              controller: _roomCodeController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              ),
              decoration: InputDecoration(
                labelText: 'Code de la partie',
                labelStyle: const TextStyle(color: Colors.black87),
                hintText: 'ABC123',
                hintStyle: const TextStyle(color: Colors.black45),
                filled: true,
                fillColor: Colors.white,
                prefixIcon: Icon(Icons.key, color: colors.primary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _joinRoom(context),
                icon: const Icon(Icons.group_add),
                label: const Text('Rejoindre le lobby'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      color: Colors.white.withValues(alpha: 0.96),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, size: 34, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return TextField(
      controller: _nameController,
      textCapitalization: TextCapitalization.words,
      maxLength: 20,
      style: const TextStyle(color: Colors.black87),
      decoration: const InputDecoration(
        labelText: 'Votre nom',
        labelStyle: TextStyle(color: Colors.black87),
        hintText: 'Entrez votre nom',
        hintStyle: TextStyle(color: Colors.black54),
        filled: true,
        fillColor: Colors.white,
        prefixIcon: Icon(Icons.person, color: Colors.black87),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
    );
  }

  Future<void> _createRoom(BuildContext context) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Veuillez entrer votre nom');
      return;
    }

    final provider = context.read<MultiplayerGameProvider>();
    final navigator = Navigator.of(context);

    try {
      await provider.createRoom(
        settings: GameSettings(
          gameMode: _gameMode,
          luckDifficulty: Difficulty.medium,
          botDifficulty: Difficulty.medium,
          minPlayers: 2,
          maxPlayers: 4,
          fillBots: false,
        ),
        playerName: name,
      );

      if (!mounted || provider.roomCode == null) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => const MultiplayerLobbyScreen(),
        ),
      );
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _joinRoom(BuildContext context) async {
    final name = _nameController.text.trim();
    final code = _roomCodeController.text.trim().toUpperCase();

    if (name.isEmpty) {
      _showError('Veuillez entrer votre nom');
      return;
    }

    if (code.length != 6) {
      _showError('Le code doit contenir 6 caracteres');
      return;
    }

    final provider = context.read<MultiplayerGameProvider>();
    final navigator = Navigator.of(context);

    try {
      await provider.joinRoom(
        roomCode: code,
        playerName: name,
      );

      if (!mounted || provider.roomCode == null) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => const MultiplayerLobbyScreen(),
        ),
      );
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}
