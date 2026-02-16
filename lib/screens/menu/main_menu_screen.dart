import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
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

class _MainMenuScreenState extends State<MainMenuScreen>
    with TickerProviderStateMixin {
  int? selectedSlot;
  late final AnimationController _slotShakeController;
  late final AnimationController _slotPulseController;
  late final AnimationController _slotTapPulseController;

  Map<int, Map<String, dynamic>> slotsData = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _slotShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _slotPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _slotTapPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 290),
    );
    _syncSlotPulseAnimation();
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WebSplashHelper.hideSplash();
      });
    }
    _loadDataParallel();
  }

  @override
  void dispose() {
    _slotShakeController.dispose();
    _slotPulseController.dispose();
    _slotTapPulseController.dispose();
    super.dispose();
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
      final savedSlot = prefs.getInt('lastSelectedSlot');
      final initialSlot =
          (savedSlot != null && savedSlot >= 1 && savedSlot <= 3)
              ? savedSlot
              : null;

      setState(() {
        selectedSlot = initialSlot;
        slotsData = {
          1: results[1] as Map<String, dynamic>,
          2: results[2] as Map<String, dynamic>,
          3: results[3] as Map<String, dynamic>,
        };
        isLoading = false;
      });
      _syncSlotPulseAnimation();
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

  void _goToAuthEntry(bool isLoggedIn) {
    context.go(isLoggedIn ? '/multiplayer' : '/login');
  }

  void _shakeSlots() {
    _slotShakeController.forward(from: 0);
  }

  void _syncSlotPulseAnimation() {
    if (selectedSlot == null) {
      if (!_slotPulseController.isAnimating) {
        _slotPulseController.repeat();
      }
      return;
    }
    if (_slotPulseController.isAnimating) {
      _slotPulseController.stop();
    }
    _slotPulseController.value = 0;
  }

  void _handleBlockedGameButtonTap() {
    if (selectedSlot != null) return;
    _shakeSlots();

    _slotTapPulseController
      ..stop()
      ..value = 0
      ..repeat(reverse: true);

    Future<void>.delayed(const Duration(milliseconds: 760), () {
      if (!mounted || selectedSlot != null) return;
      _slotTapPulseController.stop();
      _slotTapPulseController.value = 0;
    });
  }

  void _handleSlotSelected(int slotId) {
    if (selectedSlot == slotId) return;
    setState(() => selectedSlot = slotId);
    _saveSelectedSlot(slotId);
    _slotTapPulseController.stop();
    _slotTapPulseController.value = 0;
    _syncSlotPulseAnimation();
  }

  Widget _buildShakableSlots({required Widget child}) {
    return AnimatedBuilder(
      animation: _slotShakeController,
      child: child,
      builder: (context, slotChild) {
        final shakeOffset = sin(_slotShakeController.value * pi * 4) * 16.0;
        return Transform.translate(
          offset: Offset(shakeOffset, 0),
          child: slotChild,
        );
      },
    );
  }

  Widget _buildSlotsAttentionBand({
    required double radius,
    required Widget child,
  }) {
    if (selectedSlot != null) {
      return child;
    }

    return AnimatedBuilder(
      animation: Listenable.merge([
        _slotPulseController,
        _slotTapPulseController,
      ]),
      child: child,
      builder: (context, bandChild) {
        final alertPulse = _slotTapPulseController.value;
        return CustomPaint(
          painter: _SnakeBorderPainter(
            progress: _slotPulseController.value,
            color: const Color.fromARGB(255, 243, 3, 3),
            strokeWidth: 2 + (alertPulse * 0.9),
            radius: radius,
            pulse: alertPulse,
          ),
          child: bandChild,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final isLoggedIn = authProvider.isLoggedIn;
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;
    final isSmallLandscape = isLandscape && screenSize.height < 500;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: AppDecorations.pageBackground,
            ),
          ),
          SafeArea(
            child: isSmallLandscape
                ? _buildLandscapeLayout(context, isLoggedIn)
                : _buildPortraitLayout(context, isLoggedIn),
          ),
        ],
      ),
    );
  }

  /// Layout paysage optimisé pour iPhone
  Widget _buildLandscapeLayout(BuildContext context, bool isLoggedIn) {
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
                  _buildShakableSlots(
                    child: _buildSlotsAttentionBand(
                      radius: 10,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [1, 2, 3].asMap().entries.map((entry) {
                            final index = entry.key;
                            final slotId = entry.value;
                            final data = slotsData[slotId] ?? {};
                            final mmr = data['mmr'] ?? 0;
                            final rankName = StatsService.getRankName(mmr);
                            return Padding(
                              padding:
                                  EdgeInsets.only(left: index == 0 ? 0 : 6),
                              child: CompactSlotCard(
                                id: slotId,
                                name: "J$slotId",
                                rank: rankName,
                                rp: "$mmr RP",
                                isSelected: selectedSlot == slotId,
                                rankColor: getRankColor(rankName),
                                onTap: () => _handleSlotSelected(slotId),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
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
                  enabled: selectedSlot != null,
                  onDisabledTap: _handleBlockedGameButtonTap,
                  onPressed: () {
                    final slot = selectedSlot;
                    if (slot == null) {
                      _handleBlockedGameButtonTap();
                      return;
                    }
                    context.go('/solo/setup?tournament=false&slot=$slot');
                  },
                ),
                const SizedBox(height: 18),
                CompactMenuButton(
                  label: 'TOURNOI',
                  icon: Icons.emoji_events,
                  isPrimary: false,
                  enabled: selectedSlot != null,
                  onDisabledTap: _handleBlockedGameButtonTap,
                  onPressed: () {
                    final slot = selectedSlot;
                    if (slot == null) {
                      _handleBlockedGameButtonTap();
                      return;
                    }
                    context.go('/solo/setup?tournament=true&slot=$slot');
                  },
                ),
                const SizedBox(height: 18),
                CompactMenuButton(
                  label: 'MULTIJOUEUR',
                  icon: Icons.groups,
                  isPrimary: false,
                  enabled: selectedSlot != null,
                  onDisabledTap: _handleBlockedGameButtonTap,
                  onPressed: () {
                    if (selectedSlot == null) {
                      _handleBlockedGameButtonTap();
                      return;
                    }
                    _goToMultiplayer();
                  },
                ),
                const SizedBox(height: 18),
                CompactMenuButton(
                  label: isLoggedIn ? 'MON COMPTE' : 'CONNEXION',
                  icon: isLoggedIn ? Icons.person : Icons.login,
                  isPrimary: false,
                  onPressed: () => _goToAuthEntry(isLoggedIn),
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
                          context.go('/ai-profile?slot=${selectedSlot ?? 1}'),
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
  Widget _buildPortraitLayout(BuildContext context, bool isLoggedIn) {
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
                    _buildShakableSlots(
                      child: _buildSlotsAttentionBand(
                        radius: 12,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 3),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [1, 2, 3].asMap().entries.map((entry) {
                              final index = entry.key;
                              final slotId = entry.value;
                              final data = slotsData[slotId] ?? {};
                              final mmr = data['mmr'] ?? 0;
                              final rankName = StatsService.getRankName(mmr);
                              return Padding(
                                padding:
                                    EdgeInsets.only(left: index == 0 ? 0 : 6),
                                child: SaveSlotCard(
                                  id: slotId,
                                  name: "Joueur $slotId",
                                  rank: rankName,
                                  rp: "$mmr RP",
                                  isSelected: selectedSlot == slotId,
                                  rankColor: getRankColor(rankName),
                                  onTap: () => _handleSlotSelected(slotId),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  SizedBox(height: spacing3),
                  MenuButton(
                    label: 'PARTIE RAPIDE',
                    icon: Icons.flash_on,
                    isPrimary: true,
                    enabled: selectedSlot != null,
                    onDisabledTap: _handleBlockedGameButtonTap,
                    onPressed: () {
                      final slot = selectedSlot;
                      if (slot == null) {
                        _handleBlockedGameButtonTap();
                        return;
                      }
                      context.go('/solo/setup?tournament=false&slot=$slot');
                    },
                  ),
                  SizedBox(height: spacing4),
                  MenuButton(
                    label: 'TOURNOI',
                    icon: Icons.emoji_events,
                    isPrimary: false,
                    enabled: selectedSlot != null,
                    onDisabledTap: _handleBlockedGameButtonTap,
                    onPressed: () {
                      final slot = selectedSlot;
                      if (slot == null) {
                        _handleBlockedGameButtonTap();
                        return;
                      }
                      context.go('/solo/setup?tournament=true&slot=$slot');
                    },
                  ),
                  SizedBox(height: spacing4),
                  MenuButton(
                    label: 'MULTIJOUEUR',
                    icon: Icons.groups,
                    isPrimary: false,
                    enabled: selectedSlot != null,
                    onDisabledTap: _handleBlockedGameButtonTap,
                    onPressed: () {
                      if (selectedSlot == null) {
                        _handleBlockedGameButtonTap();
                        return;
                      }
                      _goToMultiplayer();
                    },
                  ),
                  SizedBox(height: spacing3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      LabeledIconButton(
                        icon: Icons.settings,
                        label: 'Réglages',
                        onPressed: () =>
                            context.go('/settings?slot=${selectedSlot ?? 1}'),
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
                            context.go('/stats?slot=${selectedSlot ?? 1}'),
                      ),
                      const SizedBox(width: 20),
                      LabeledIconButton(
                        icon: Icons.psychology,
                        label: 'Profil IA',
                        onPressed: () =>
                            context.go('/ai-profile?slot=${selectedSlot ?? 1}'),
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

class _SnakeBorderPainter extends CustomPainter {
  const _SnakeBorderPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    required this.radius,
    required this.pulse,
  });

  final double progress;
  final Color color;
  final double strokeWidth;
  final double radius;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rect = Offset.zero & size;
    final safeRadius = max(0.0, min(radius, min(size.width, size.height) / 2));
    final borderRect = rect.deflate(strokeWidth / 2);
    final rrect = RRect.fromRectAndRadius(
      borderRect,
      Radius.circular(safeRadius),
    );

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color.withValues(alpha: 0.22 + (pulse * 0.56));
    canvas.drawRRect(rrect, basePaint);

    final snakePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -pi / 2,
        endAngle: 3 * pi / 2,
        transform: GradientRotation(progress * 2 * pi),
        colors: [
          Colors.transparent,
          Colors.transparent,
          color.withValues(alpha: 0.20),
          color.withValues(alpha: 1.0),
          color.withValues(alpha: 1.0),
          color.withValues(alpha: 0.20),
          Colors.transparent,
          Colors.transparent,
        ],
        stops: const [0.0, 0.56, 0.68, 0.74, 0.80, 0.88, 0.96, 1.0],
      ).createShader(borderRect)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.5 + (pulse * 3.0));
    canvas.drawRRect(rrect, snakePaint);

    if (pulse > 0) {
      final pulsePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + (pulse * 1.6)
        ..color = color.withValues(alpha: 0.15 + (pulse * 0.45))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + (pulse * 4));
      canvas.drawRRect(rrect, pulsePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SnakeBorderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.radius != radius ||
        oldDelegate.pulse != pulse;
  }
}
