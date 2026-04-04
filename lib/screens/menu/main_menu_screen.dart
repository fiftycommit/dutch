import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/service_locator.dart';
import '../../core/interfaces/i_haptic_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/game_provider.dart';
import '../../providers/multiplayer_game_provider.dart';
import '../../services/ui/stats_service.dart';
import '../../providers/settings_provider.dart';
import '../../utils/ui_constants.dart';
import '../../widgets/card_rain_background.dart';
import '../../services/ui/svg_precache_service.dart';
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
  late final AnimationController _slotTapPulseController;

  // Keys for card rain obstacle collision
  final _titleKey = GlobalKey();
  final _btn1Key = GlobalKey();
  final _btn2Key = GlobalKey();
  final _btn3Key = GlobalKey();
  final _icon1Key = GlobalKey();
  final _icon2Key = GlobalKey();
  final _icon3Key = GlobalKey();
  final _icon4Key = GlobalKey();

  Map<int, Map<String, dynamic>> slotsData = {};
  Map<int, String> slotNames = {
    1: 'Joueur 1',
    2: 'Joueur 2',
    3: 'Joueur 3',
  };
  Future<void>? _multiplayerWarmupFuture;
  bool isLoading = true;
  bool _isProfileStackOpen = false;

  /// Pluie de cartes différée : on attend que le menu soit interactif
  /// avant de monter le widget animé coûteux (CRP: priorité au contenu critique)
  bool _cardRainReady = false;

  @override
  void initState() {
    super.initState();
    _slotShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _slotTapPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 290),
    );
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WebSplashHelper.hideSplash();
      });
    }
    _loadDataParallel();
    // Vérifier si un tournoi a été abandonné (fermeture d'app)
    unawaited(GameProvider.checkForAbandonedGame());
    // Précache les SVGs restants en arrière-plan (non bloquant)
    unawaited(SvgPrecacheService().precacheRemainingSvgs());
    // Préparer l'entrée multijoueur après le 1er frame pour éviter
    // des notifyListeners() pendant la phase de build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_ensureMultiplayerWarmupStarted());
    });
    // Différer la pluie de cartes : laisser le menu se rendre d'abord
    // pour un Time-to-Interactive optimal (approche CRP)
    _deferCardRain();
  }

  /// Monte la pluie de cartes après un court délai pour ne pas bloquer
  /// le rendu initial du menu (les boutons doivent être interactifs d'abord).
  void _deferCardRain() {
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() => _cardRainReady = true);
    });
  }

  @override
  void dispose() {
    _slotShakeController.dispose();
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
      final loadedNames = {
        1: _getSavedSlotName(prefs, 1),
        2: _getSavedSlotName(prefs, 2),
        3: _getSavedSlotName(prefs, 3),
      };

      setState(() {
        selectedSlot = initialSlot;
        slotNames = loadedNames;
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

  Future<void> _ensureMultiplayerWarmupStarted() {
    final current = _multiplayerWarmupFuture;
    if (current != null) {
      return current;
    }
    late final Future<void> next;
    next = _warmupMultiplayerEntry().whenComplete(() {
      if (identical(_multiplayerWarmupFuture, next)) {
        _multiplayerWarmupFuture = null;
      }
    });
    _multiplayerWarmupFuture = next;
    return next;
  }

  Future<void> _warmupMultiplayerEntry() async {
    try {
      final authProvider = context.read<AuthProvider>();
      if (!authProvider.isInitialized) {
        await authProvider.init();
      }
      if (!mounted || !authProvider.isLoggedIn) {
        return;
      }

      final multiProvider = context.read<MultiplayerGameProvider>();
      final freshToken = await authProvider.getFreshToken();
      multiProvider.setAuthToken(freshToken);
      await multiProvider.init();
      unawaited(multiProvider.getMyActiveRooms());
    } catch (_) {
      // Warmup optionnel: ignorer les erreurs sans bloquer l'UI.
    }
  }

  String _slotNameKey(int slotId) => 'slot_name_$slotId';

  String _defaultSlotName(int slotId) => 'Joueur $slotId';

  String _getSavedSlotName(SharedPreferences prefs, int slotId) {
    final raw = prefs.getString(_slotNameKey(slotId));
    if (raw == null) return _defaultSlotName(slotId);
    final trimmed = raw.trim();
    return trimmed.isEmpty ? _defaultSlotName(slotId) : trimmed;
  }

  Future<void> _saveSlotName(int slotId, String slotName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_slotNameKey(slotId), slotName);
  }

  Future<void> _promptRenameSlot(int slotId) async {
    final initialName = slotNames[slotId] ?? _defaultSlotName(slotId);
    final controller = TextEditingController(text: initialName);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: initialName.length,
    );
    String? nextName;

    try {
      nextName = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('Renommer Joueur $slotId'),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 18,
              style: const TextStyle(color: Colors.black),
              cursorColor: Colors.black,
              decoration: const InputDecoration(
                labelText: 'Nom du profil',
                labelStyle: TextStyle(color: Colors.black87),
                floatingLabelStyle: TextStyle(color: Colors.black87),
                counterStyle: TextStyle(color: Colors.black54),
              ),
              onSubmitted: (value) {
                Navigator.of(dialogContext).pop(value);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () {
                  ServiceLocator().get<IHapticService>().buttonTap();
                  Navigator.of(dialogContext).pop(
                    controller.text,
                  );
                },
                child: const Text('Enregistrer'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }

    if (nextName == null) return;
    final trimmed = nextName.trim();
    if (trimmed.isEmpty || trimmed == initialName) return;

    if (mounted) {
      setState(() {
        slotNames[slotId] = trimmed;
      });
    }
    await _saveSlotName(slotId, trimmed);
  }

  /// Naviguer vers le menu multijoueur
  Future<void> _goToMultiplayer() async {
    unawaited(_ensureMultiplayerWarmupStarted());
    var authProvider = context.read<AuthProvider>();
    if (!authProvider.isInitialized) {
      await authProvider.init();
    }
    if (!mounted) return;

    if (!authProvider.isLoggedIn) {
      final loggedIn = await context.push<bool>('/login');
      if (!mounted || loggedIn != true) return;
      authProvider = context.read<AuthProvider>();
      if (!authProvider.isLoggedIn) return;
    }

    unawaited(_ensureMultiplayerWarmupStarted());
    await context.push('/multiplayer');
  }

  void _shakeSlots() {
    _slotShakeController.forward(from: 0);
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

  void _handleSlotSelected(int slotId, {bool closeStack = false}) {
    final selectionChanged = selectedSlot != slotId;
    if (!selectionChanged && !closeStack) return;

    setState(() {
      selectedSlot = slotId;
      if (closeStack) {
        _isProfileStackOpen = false;
      }
    });

    if (selectionChanged) {
      _saveSelectedSlot(slotId);
    }
    _slotTapPulseController.stop();
    _slotTapPulseController.value = 0;
  }

  void _handleProfileCardTap(int slotId) {
    if (!_isProfileStackOpen) {
      setState(() => _isProfileStackOpen = true);
      return;
    }
    _handleSlotSelected(slotId, closeStack: true);
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
      animation: _slotTapPulseController,
      child: child,
      builder: (context, bandChild) {
        final t = _slotTapPulseController.value;
        final isPulsing = _slotTapPulseController.isAnimating || t > 0;
        if (!isPulsing) {
          return bandChild!;
        }

        final easedT = Curves.easeInOut.transform(t);
        final borderColor = Color.lerp(
          const Color(0x55FF1744),
          const Color(0xFFFF1744),
          easedT,
        )!;
        final borderWidth = 1.4 + (easedT * 1.8);

        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: borderWidth),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: bandChild,
        );
      },
    );
  }

  Widget _buildProfileSelectionTitle({required bool compact}) {
    final showTitle = selectedSlot == null;
    return SizedBox(
      width: double.infinity,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: showTitle
            ? Padding(
                padding: EdgeInsets.only(top: compact ? 8 : 12),
                child: Text(
                  'Sélectionnez votre profil',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: compact ? 12 : 16,
                    letterSpacing: compact ? 0.8 : 1.2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildProfileSelectionBox({
    required bool compact,
    required double radius,
    required EdgeInsets padding,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildShakableSlots(
            child: _buildSlotsAttentionBand(
              radius: radius,
              child: Padding(
                padding: padding,
                child: _buildProfileCardStack(compact: compact),
              ),
            ),
          ),
          _buildProfileSelectionTitle(compact: compact),
        ],
      ),
    );
  }

  Widget _buildProfileCardStack({required bool compact}) {
    const slotIds = [1, 2, 3];
    final frontSlotId = selectedSlot ?? 1;

    final cardWidth = compact ? 78.0 : 100.0;
    final openGap = compact ? 12.0 : 14.0;
    final openWidth = (cardWidth * 3) + (openGap * 2);
    final closedSpread = compact ? 38.0 : 46.0;
    final closedWidth = cardWidth + (closedSpread * 2);
    final stackWidth = _isProfileStackOpen ? openWidth : closedWidth;
    final stackHeight = compact ? 88.0 : 126.0;

    final centerLeft = (stackWidth - cardWidth) / 2;
    final openStart = (stackWidth - openWidth) / 2;
    final backSlots = slotIds.where((slot) => slot != frontSlotId).toList();

    final poses = <int, _ProfileCardPose>{};
    if (_isProfileStackOpen) {
      for (final entry in slotIds.asMap().entries) {
        final index = entry.key;
        final slotId = entry.value;
        final left = openStart + (index * (cardWidth + openGap));
        final rotation = (index - 1) * (compact ? 0.035 : 0.045);
        final z = (selectedSlot == slotId) ? 10 : index;
        poses[slotId] = _ProfileCardPose(
          left: left,
          top: compact ? 2 : 4,
          rotationRadians: rotation,
          scale: 1,
          zIndex: z,
        );
      }
    } else {
      poses[frontSlotId] = _ProfileCardPose(
        left: centerLeft,
        top: compact ? 2 : 4,
        rotationRadians: 0,
        scale: 1,
        zIndex: 3,
      );
      poses[backSlots[0]] = _ProfileCardPose(
        left: centerLeft - (compact ? 32 : 40),
        top: compact ? 9 : 13,
        rotationRadians: -0.16,
        scale: 0.98,
        zIndex: 1,
      );
      poses[backSlots[1]] = _ProfileCardPose(
        left: centerLeft + (compact ? 32 : 40),
        top: compact ? 8 : 11,
        rotationRadians: 0.16,
        scale: 0.99,
        zIndex: 2,
      );
    }

    final paintOrder = slotIds.toList()
      ..sort((a, b) => poses[a]!.zIndex.compareTo(poses[b]!.zIndex));

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_isProfileStackOpen) return;
        setState(() => _isProfileStackOpen = true);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        width: stackWidth,
        height: stackHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: paintOrder.map((slotId) {
            final pose = poses[slotId]!;
            return AnimatedPositioned(
              key: ValueKey('profile_card_$slotId'),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              left: pose.left,
              top: pose.top,
              child: AnimatedRotation(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                turns: pose.rotationRadians / (2 * pi),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  scale: pose.scale,
                  child: _buildProfileCard(
                    slotId: slotId,
                    compact: compact,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildProfileCard({
    required int slotId,
    required bool compact,
  }) {
    final data = slotsData[slotId] ?? {};
    final mmr = data['mmr'] ?? 0;
    final rankName = StatsService.getRankName(mmr);
    final slotName = slotNames[slotId] ?? _defaultSlotName(slotId);

    if (compact) {
      return CompactSlotCard(
        id: slotId,
        name: slotName,
        rank: rankName,
        rp: "$mmr RP",
        isSelected: selectedSlot == slotId,
        rankColor: getRankColor(rankName),
        onTap: () => _handleProfileCardTap(slotId),
        onEditTap: () => _promptRenameSlot(slotId),
      );
    }

    return SaveSlotCard(
      id: slotId,
      name: slotName,
      rank: rankName,
      rp: "$mmr RP",
      isSelected: selectedSlot == slotId,
      rankColor: getRankColor(rankName),
      onTap: () => _handleProfileCardTap(slotId),
      onEditTap: () => _promptRenameSlot(slotId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final isLoggedIn = authProvider.isLoggedIn;
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;
    final isSmallLandscape = isLandscape && screenSize.height < 500;

    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: AppDecorations.pageBackground,
            ),
          ),
          if (_cardRainReady &&
              settings.cardRainEnabled &&
              settings.animationsEnabled)
            Positioned.fill(
              child: CardRainBackground(
                obstacleKeys: [
                  _titleKey,
                  _btn1Key,
                  _btn2Key,
                  _btn3Key,
                  _icon1Key,
                  _icon2Key,
                  _icon3Key,
                  _icon4Key,
                ],
              ),
            ),
          SafeArea(
            child: isLandscape
                ? _buildLandscapeLayout(context, isLoggedIn, isSmallLandscape)
                : _buildPortraitLayout(context, isLoggedIn),
          ),
        ],
      ),
    );
  }

  /// Layout paysage (iPhone petit écran + desktop/web grand écran)
  Widget _buildLandscapeLayout(
      BuildContext context, bool isLoggedIn, bool isCompact) {
    final showLabels = !isCompact;
    final buttonSpacing = isCompact ? 18.0 : 20.0;
    final titleSize = isCompact ? 44.0 : 52.0;
    final iconSize = isCompact ? 60.0 : 70.0;
    final subtitleSize = isCompact ? 13.0 : 15.0;
    final profileSpacing = isCompact ? 20.0 : 28.0;

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
                Icon(Icons.style, size: iconSize, color: Colors.amber),
                const SizedBox(height: 8),
                Text(
                  "DUTCH'78",
                  style: TextStyle(
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
                const SizedBox(height: 4),
                Text(
                  'réalisé par Max, Irfat, Leon et EL Roy',
                  style: TextStyle(
                    fontSize: subtitleSize,
                    letterSpacing: 2,
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: profileSpacing),
                // Slots de sauvegarde en ligne
                if (!isLoading)
                  _buildProfileSelectionBox(
                    compact: isCompact,
                    radius: 10,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 3,
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
                    context.push('/solo/setup?tournament=false&slot=$slot');
                  },
                ),
                SizedBox(height: buttonSpacing),
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
                    context.push('/solo/setup?tournament=true&slot=$slot');
                  },
                ),
                SizedBox(height: buttonSpacing),
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
                SizedBox(height: buttonSpacing + 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: showLabels
                      ? [
                          LabeledIconButton(
                            icon: Icons.settings,
                            label: 'Réglages',
                            onPressed: () => context
                                .push('/settings?slot=${selectedSlot ?? 1}'),
                          ),
                          const SizedBox(width: 20),
                          LabeledIconButton(
                            icon: Icons.menu_book,
                            label: 'Règles',
                            onPressed: () => context.push('/rules'),
                          ),
                          const SizedBox(width: 20),
                          LabeledIconButton(
                            icon: Icons.bar_chart,
                            label: 'Statistiques',
                            onPressed: () => context
                                .push('/stats?slot=${selectedSlot ?? 1}'),
                          ),
                          const SizedBox(width: 20),
                          LabeledIconButton(
                            icon: Icons.psychology,
                            label: 'Profil IA',
                            onPressed: () => context
                                .push('/ai-profile?slot=${selectedSlot ?? 1}'),
                          ),
                        ]
                      : [
                          SmallIconButton(
                            icon: Icons.settings,
                            onPressed: () => context
                                .push('/settings?slot=${selectedSlot ?? 1}'),
                          ),
                          const SizedBox(width: 18),
                          SmallIconButton(
                            icon: Icons.menu_book,
                            onPressed: () => context.push('/rules'),
                          ),
                          const SizedBox(width: 18),
                          SmallIconButton(
                            icon: Icons.bar_chart,
                            onPressed: () => context
                                .push('/stats?slot=${selectedSlot ?? 1}'),
                          ),
                          const SizedBox(width: 18),
                          SmallIconButton(
                            icon: Icons.psychology,
                            onPressed: () => context
                                .push('/ai-profile?slot=${selectedSlot ?? 1}'),
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
        // Sur Android Chrome, la barre d'adresse réduit le viewport (~600-650px)
        final screenHeight = constraints.maxHeight;
        final isVerySmall = screenHeight < 580;
        final isSmall = screenHeight < 700;
        final spacing1 = isVerySmall ? 4.0 : (isSmall ? 8.0 : 20.0);
        final spacing2 = isVerySmall ? 12.0 : (isSmall ? 18.0 : 50.0);
        final spacing3 = isVerySmall ? 10.0 : (isSmall ? 14.0 : 40.0);
        final spacing4 = isVerySmall ? 8.0 : (isSmall ? 10.0 : 16.0);
        final iconSize = isVerySmall ? 40.0 : (isSmall ? 54.0 : 80.0);
        final titleSize = isVerySmall ? 36.0 : (isSmall ? 44.0 : 60.0);
        final useCompactProfile = isSmall;

        // CustomScrollView + SliverFillRemaining : plus robuste que
        // IntrinsicHeight sur le renderer HTML web (Android Chrome)
        return CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: spacing1),
                  Icon(Icons.style, size: iconSize, color: Colors.amber),
                  SizedBox(height: isVerySmall ? 4 : 10),
                  Text(
                    key: _titleKey,
                    "DUTCH'78",
                    style: TextStyle(
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
                  if (!isVerySmall)
                    Text(
                      'réalisé par Max, Irfat, LEON et EL Roy',
                      style: TextStyle(
                        fontSize: isSmall ? 13 : 16,
                        letterSpacing: isSmall ? 1.5 : 4,
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  SizedBox(height: spacing2),
                  if (isLoading)
                    const CircularProgressIndicator(color: Colors.amber)
                  else
                    _buildProfileSelectionBox(
                      compact: useCompactProfile,
                      radius: useCompactProfile ? 10 : 12,
                      padding: EdgeInsets.symmetric(
                        horizontal: useCompactProfile ? 4 : 6,
                        vertical: useCompactProfile ? 3 : 4,
                      ),
                    ),
                  SizedBox(height: spacing3),
                  KeyedSubtree(
                    key: _btn1Key,
                    child: MenuButton(
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
                        context.push('/solo/setup?tournament=false&slot=$slot');
                      },
                    ),
                  ),
                  SizedBox(height: spacing4),
                  KeyedSubtree(
                    key: _btn2Key,
                    child: MenuButton(
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
                        context.push('/solo/setup?tournament=true&slot=$slot');
                      },
                    ),
                  ),
                  SizedBox(height: spacing4),
                  KeyedSubtree(
                    key: _btn3Key,
                    child: MenuButton(
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
                  ),
                  SizedBox(height: spacing3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      KeyedSubtree(
                        key: _icon1Key,
                        child: LabeledIconButton(
                          icon: Icons.settings,
                          label: 'Réglages',
                          onPressed: () => context
                              .push('/settings?slot=${selectedSlot ?? 1}'),
                        ),
                      ),
                      const SizedBox(width: 20),
                      KeyedSubtree(
                        key: _icon2Key,
                        child: LabeledIconButton(
                          icon: Icons.menu_book,
                          label: 'Règles',
                          onPressed: () => context.push('/rules'),
                        ),
                      ),
                      const SizedBox(width: 20),
                      KeyedSubtree(
                        key: _icon3Key,
                        child: LabeledIconButton(
                          icon: Icons.bar_chart,
                          label: 'Stats',
                          onPressed: () =>
                              context.push('/stats?slot=${selectedSlot ?? 1}'),
                        ),
                      ),
                      const SizedBox(width: 20),
                      KeyedSubtree(
                        key: _icon4Key,
                        child: LabeledIconButton(
                          icon: Icons.psychology,
                          label: 'Profil IA',
                          onPressed: () => context
                              .push('/ai-profile?slot=${selectedSlot ?? 1}'),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: spacing1),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProfileCardPose {
  const _ProfileCardPose({
    required this.left,
    required this.top,
    required this.rotationRadians,
    required this.scale,
    required this.zIndex,
  });

  final double left;
  final double top;
  final double rotationRadians;
  final double scale;
  final int zIndex;
}
