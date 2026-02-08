import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/ui/stats_service.dart';
import '../../utils/ui_constants.dart';
import 'main_menu_widgets.dart';
import '../web_splash_helper.dart'
    if (dart.library.io) '../web_splash_helper_stub.dart';

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
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WebSplashHelper.hideSplash();
      });
    }
    _loadDataParallel();
  }

  /// Load all data in parallel for faster startup
  Future<void> _loadDataParallel() async {
    // Run all async operations in parallel
    final results = await Future.wait([
      SharedPreferences.getInstance(),
      StatsService.getStats(slotId: 1),
      StatsService.getStats(slotId: 2),
      StatsService.getStats(slotId: 3),
    ]);

    if (mounted) {
      final prefs = results[0] as SharedPreferences;
      setState(() {
        selectedSlot = prefs.getInt('lastSelectedSlot') ?? 1;
        slotsData = {
          1: results[1] as Map<String, dynamic>,
          2: results[2] as Map<String, dynamic>,
          3: results[3] as Map<String, dynamic>,
        };
        isLoading = false;
      });
    }
  }

  Future<void> _saveSelectedSlot(int slotId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastSelectedSlot', slotId);
  }

  /// Naviguer vers le menu multijoueur
  void _goToMultiplayer() {
    context.go('/multiplayer');
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;
    final isSmallLandscape = isLandscape && screenSize.height < 500;

    return Scaffold(
      backgroundColor: AppColors.gradientBottom,
      body: SafeArea(
        child: isSmallLandscape
            ? _buildLandscapeLayout(context)
            : _buildPortraitLayout(context),
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
                      Shadow(
                          color: Colors.black45,
                          blurRadius: 10,
                          offset: Offset(2, 2))
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'réalisé par Max, Irfat et EL Roy',
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
                        child: CompactSlotCard(
                          id: slotId,
                          name: "J$slotId",
                          rank: rankName,
                          rp: "$mmr RP",
                          isSelected: selectedSlot == slotId,
                          rankColor: getRankColor(rankName),
                          onTap: () {
                            setState(() => selectedSlot = slotId);
                            _saveSelectedSlot(slotId);
                          },
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
                CompactMenuButton(
                  label: 'PARTIE RAPIDE',
                  icon: Icons.flash_on,
                  isPrimary: true,
                  onPressed: () {
                    context
                        .go('/solo/setup?tournament=false&slot=$selectedSlot');
                  },
                ),
                const SizedBox(height: 18),
                CompactMenuButton(
                  label: 'TOURNOI',
                  icon: Icons.emoji_events,
                  isPrimary: false,
                  onPressed: () {
                    context
                        .go('/solo/setup?tournament=true&slot=$selectedSlot');
                  },
                ),
                const SizedBox(height: 18),
                CompactMenuButton(
                  label: 'MULTIJOUEUR',
                  icon: Icons.groups,
                  isPrimary: false,
                  onPressed: _goToMultiplayer,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SmallIconButton(
                      icon: Icons.settings,
                      onPressed: () => context.go('/settings'),
                    ),
                    const SizedBox(width: 18),
                    SmallIconButton(
                      icon: Icons.menu_book,
                      onPressed: () => context.go('/rules'),
                    ),
                    const SizedBox(width: 18),
                    SmallIconButton(
                      icon: Icons.bar_chart,
                      onPressed: () => context.go('/stats'),
                    ),
                    const SizedBox(width: 18),
                    SmallIconButton(
                      icon: Icons.psychology,
                      onPressed: () =>
                          context.go('/ai-profile?slot=$selectedSlot'),
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
        // Adapter les espacements selon la hauteur disponible
        final screenHeight = constraints.maxHeight;
        final isLargeScreen = screenHeight > 700;
        final spacing1 = isLargeScreen ? 20.0 : 10.0;
        final spacing2 = isLargeScreen ? 50.0 : 25.0;
        final spacing3 = isLargeScreen ? 40.0 : 20.0;
        final spacing4 = isLargeScreen ? 16.0 : 12.0;
        final iconSize = isLargeScreen ? 80.0 : 60.0;
        final titleSize = isLargeScreen ? 60.0 : 48.0;

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
            ),
            child: IntrinsicHeight(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: spacing1),
                  Icon(Icons.style, size: iconSize, color: Colors.amber),
                  const SizedBox(height: 10),
                  Text(
                    'DUTCH\' 78',
                    style: TextStyle(
                      fontFamily: 'Rye',
                      fontSize: titleSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: const [
                        Shadow(
                            color: Colors.black45,
                            blurRadius: 10,
                            offset: Offset(2, 2))
                      ],
                    ),
                  ),
                  Text(
                    'réalisé par Max, Irfat et EL Roy',
                    style: TextStyle(
                      fontSize: isLargeScreen ? 16 : 14,
                      letterSpacing: isLargeScreen ? 4 : 2,
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: spacing2),
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
                          child: SaveSlotCard(
                            id: slotId,
                            name: "Joueur $slotId",
                            rank: rankName,
                            rp: "$mmr RP",
                            isSelected: selectedSlot == slotId,
                            rankColor: getRankColor(rankName),
                            onTap: () {
                              setState(() => selectedSlot = slotId);
                              _saveSelectedSlot(slotId);
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  SizedBox(height: spacing3),
                  MenuButton(
                    label: 'PARTIE RAPIDE',
                    icon: Icons.flash_on,
                    isPrimary: true,
                    onPressed: () {
                      context.go(
                          '/solo/setup?tournament=false&slot=$selectedSlot');
                    },
                  ),
                  SizedBox(height: spacing4),
                  MenuButton(
                    label: 'TOURNOI',
                    icon: Icons.emoji_events,
                    isPrimary: false,
                    onPressed: () {
                      context
                          .go('/solo/setup?tournament=true&slot=$selectedSlot');
                    },
                  ),
                  SizedBox(height: spacing4),
                  MenuButton(
                    label: 'MULTIJOUEUR',
                    icon: Icons.groups,
                    isPrimary: false,
                    onPressed: _goToMultiplayer,
                  ),
                  SizedBox(height: spacing3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      LabeledIconButton(
                        icon: Icons.settings,
                        label: 'Réglages',
                        onPressed: () =>
                            context.go('/settings?slot=$selectedSlot'),
                      ),
                      const SizedBox(width: 20),
                      LabeledIconButton(
                        icon: Icons.menu_book,
                        label: 'Règles',
                        onPressed: () => context.go('/rules'),
                      ),
                      const SizedBox(width: 20),
                      LabeledIconButton(
                        icon: Icons.bar_chart,
                        label: 'Stats',
                        onPressed: () =>
                            context.go('/stats?slot=$selectedSlot'),
                      ),
                      const SizedBox(width: 20),
                      LabeledIconButton(
                        icon: Icons.psychology,
                        label: 'Profil IA',
                        onPressed: () =>
                            context.go('/ai-profile?slot=$selectedSlot'),
                      ),
                    ],
                  ),
                  SizedBox(height: spacing1),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
