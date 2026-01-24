import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/stats_service.dart';
import 'game_setup_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'rules_screen.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  int selectedSlot = 1;

  Map<int, Map<String, dynamic>> slotsData = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSelectedSlot();
    _loadAllSlots();
  }

  Future<void> _loadSelectedSlot() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSlot = prefs.getInt('lastSelectedSlot') ?? 1;
    if (mounted) {
      setState(() {
        selectedSlot = savedSlot;
      });
    }
  }

  Future<void> _saveSelectedSlot(int slotId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastSelectedSlot', slotId);
  }

  Future<void> _loadAllSlots() async {
    final s1 = await StatsService.getStats(slotId: 1);
    final s2 = await StatsService.getStats(slotId: 2);
    final s3 = await StatsService.getStats(slotId: 3);

    if (mounted) {
      setState(() {
        slotsData = {1: s1, 2: s2, 3: s3};
        isLoading = false;
      });
    }
  }

  void _refreshStats() {
    _loadAllSlots();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;
    final isSmallLandscape = isLandscape && screenSize.height < 500;
    
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0d2818), Color(0xFF1a472a)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: isSmallLandscape 
              ? _buildLandscapeLayout(context)
              : _buildPortraitLayout(context),
          ),
        ],
      ),
    );
  }
  
  /// Layout paysage optimisé pour iPhone
  Widget _buildLandscapeLayout(BuildContext context) {
    // Moins de padding, éléments plus gros, centrage vertical
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Partie gauche: Logo et titre
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.style, size: 60, color: Colors.amber),
                const SizedBox(height: 8),
                const Text(
                  'DUTCH\' 78',
                  style: TextStyle(
                    fontFamily: 'Rye',
                    fontSize: 44,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(color: Colors.black45, blurRadius: 10, offset: Offset(2, 2))
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'réalisé par Max et EL Roy',
                  style: TextStyle(
                    fontSize: 13,
                    letterSpacing: 2,
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                // Slots de sauvegarde en ligne
                if (!isLoading)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [1, 2, 3].map((slotId) {
                      final data = slotsData[slotId] ?? {};
                      final mmr = data['mmr'] ?? 0;
                      final rankName = StatsService.getRankName(mmr);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: _buildCompactSlotCard(
                          slotId,
                          "J$slotId",
                          rankName,
                          "$mmr RP",
                          selectedSlot == slotId,
                          _getRankColor(rankName),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
          // Partie droite: Boutons
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildCompactMenuButton(
                  context,
                  label: 'PARTIE RAPIDE',
                  icon: Icons.flash_on,
                  isPrimary: true,
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GameSetupScreen(
                          isTournament: false,
                          saveSlot: selectedSlot,
                        ),
                      ),
                    );
                    _refreshStats();
                  },
                ),
                const SizedBox(height: 18),
                _buildCompactMenuButton(
                  context,
                  label: 'TOURNOI',
                  icon: Icons.emoji_events,
                  isPrimary: false,
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GameSetupScreen(
                          isTournament: true,
                          saveSlot: selectedSlot,
                        ),
                      ),
                    );
                    _refreshStats();
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildSmallIconButton(
                      icon: Icons.settings,
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (context) => const SettingsScreen())),
                    ),
                    const SizedBox(width: 18),
                    _buildSmallIconButton(
                      icon: Icons.menu_book,
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (context) => const RulesScreen())),
                    ),
                    const SizedBox(width: 18),
                    _buildSmallIconButton(
                      icon: Icons.bar_chart,
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (context) => const StatsScreen())),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  /// Layout portrait classique
  Widget _buildPortraitLayout(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
            ),
            child: IntrinsicHeight(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  const Icon(Icons.style, size: 80, color: Colors.amber),
                  const SizedBox(height: 10),
                  const Text(
                    'DUTCH\' 78',
                    style: TextStyle(
                      fontFamily: 'Rye',
                      fontSize: 60,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(color: Colors.black45, blurRadius: 10, offset: Offset(2, 2))
                      ],
                    ),
                  ),
                  const Text(
                    'réalisé par Max et EL Roy',
                    style: TextStyle(
                      fontSize: 16,
                      letterSpacing: 4,
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 50),
                  if (isLoading)
                    const CircularProgressIndicator(color: Colors.amber)
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [1, 2, 3].map((slotId) {
                        final data = slotsData[slotId] ?? {};
                        final mmr = data['mmr'] ?? 0;
                        final rankName = StatsService.getRankName(mmr);
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: _buildSaveSlotCard(
                            slotId,
                            "Joueur $slotId",
                            rankName,
                            "$mmr RP",
                            selectedSlot == slotId,
                            _getRankColor(rankName),
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 40),
                  _buildMenuButton(
                    context,
                    label: 'PARTIE RAPIDE',
                    icon: Icons.flash_on,
                    isPrimary: true,
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GameSetupScreen(
                            isTournament: false,
                            saveSlot: selectedSlot,
                          ),
                        ),
                      );
                      _refreshStats();
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildMenuButton(
                    context,
                    label: 'TOURNOI',
                    icon: Icons.emoji_events,
                    isPrimary: false,
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GameSetupScreen(
                            isTournament: true,
                            saveSlot: selectedSlot,
                          ),
                        ),
                      );
                      _refreshStats();
                    },
                  ),
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildIconButton(
                        icon: Icons.settings,
                        label: 'Réglages',
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (context) => const SettingsScreen())),
                      ),
                      const SizedBox(width: 20),
                      _buildIconButton(
                        icon: Icons.menu_book,
                        label: 'Règles',
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (context) => const RulesScreen())),
                      ),
                      const SizedBox(width: 20),
                      _buildIconButton(
                        icon: Icons.bar_chart,
                        label: 'Stats',
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (context) => const StatsScreen())),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getRankColor(String rank) {
    switch (rank) {
      case 'Platine':
        return const Color(0xFF00BFFF); // Bleu diamant brillant
      case 'Or':
        return Colors.amber;
      case 'Argent':
        return const Color(0xFFC0C0C0);
      default:
        return const Color(0xFFCD7F32); // Bronze
    }
  }
  
  /// Slot compact pour le mode paysage
  Widget _buildCompactSlotCard(int id, String name, String rank, String rp,
      bool isSelected, Color rankColor) {
    return GestureDetector(
      onTap: () {
        setState(() => selectedSlot = id);
        _saveSelectedSlot(id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          color: isSelected ? rankColor : Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: Colors.white, width: 2)
              : Border.all(color: Colors.transparent, width: 2),
          boxShadow: isSelected
              ? [BoxShadow(color: rankColor.withValues(alpha: 0.5), blurRadius: 8)]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person,
                color: isSelected ? Colors.black : Colors.white70, size: 20),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(name,
                  style: TextStyle(
                      color: isSelected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 10)),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(rank,
                  style: TextStyle(
                      color: isSelected ? Colors.black87 : rankColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 9)),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(rp,
                  style: TextStyle(
                      color: isSelected ? Colors.black54 : Colors.white60,
                      fontSize: 8)),
            ),
          ],
        ),
      ),
    );
  }
  
  /// Bouton de menu compact pour paysage
  Widget _buildCompactMenuButton(BuildContext context,
      {required String label,
      required IconData icon,
      required bool isPrimary,
      required VoidCallback onPressed}) {
    return SizedBox(
      width: 160,
      height: 40,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: isPrimary ? Colors.black : Colors.white, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? Colors.amber : const Color(0xFF2d5f3e),
          foregroundColor: isPrimary ? Colors.black : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: isPrimary ? 6 : 3,
        ),
      ),
    );
  }
  
  /// Petit bouton icône pour paysage
  Widget _buildSmallIconButton({required IconData icon, required VoidCallback onPressed}) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      color: Colors.white70,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFF1a3a28),
        padding: const EdgeInsets.all(8),
      ),
    );
  }

  Widget _buildSaveSlotCard(int id, String name, String rank, String rp,
      bool isSelected, Color rankColor) {
    return GestureDetector(
      onTap: () {
        setState(() => selectedSlot = id);
        _saveSelectedSlot(id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 100,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? rankColor : Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: Colors.white, width: 2)
              : Border.all(color: Colors.transparent, width: 2),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: rankColor.withValues(alpha: 0.5), blurRadius: 10)
                ]
              : [],
        ),
        child: Column(
          children: [
            Icon(Icons.person,
                color: isSelected ? Colors.black : Colors.white70, size: 30),
            const SizedBox(height: 4),
            Text(name,
                style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
            Text(rank,
                style: TextStyle(
                    color: isSelected ? Colors.black87 : rankColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 11)),
            Text(rp,
                style: TextStyle(
                    color: isSelected ? Colors.black54 : Colors.grey,
                    fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton(BuildContext context,
      {required String label,
      required IconData icon,
      required bool isPrimary,
      required VoidCallback onPressed}) {
    return SizedBox(
      width: 200,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: isPrimary ? Colors.black : Colors.white),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? Colors.amber : const Color(0xFF2d5f3e),
          foregroundColor: isPrimary ? Colors.black : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: isPrimary ? 8 : 4,
        ),
      ),
    );
  }

  Widget _buildIconButton(
      {required IconData icon,
      required String label,
      required VoidCallback onPressed}) {
    return Column(
      children: [
        IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 28),
          color: Colors.white70,
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFF1a3a28),
            padding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
