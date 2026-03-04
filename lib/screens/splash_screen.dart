import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import '../utils/ui_constants.dart';
import 'package:vector_graphics/vector_graphics.dart';
import 'package:go_router/go_router.dart';
import '../router/app_router.dart';
import '../utils/screen_utils.dart';
import '../providers/auth_provider.dart';
import '../services/ui/svg_precache_service.dart';
import 'web_splash_helper.dart'
    if (dart.library.io) 'web_splash_helper_stub.dart';
import 'web_connection_helper.dart'
    if (dart.library.io) 'web_connection_helper_stub.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  String _statusText = 'Initialisation...';
  late AnimationController _progressController;
  int _lastSentProgress = -1;
  bool _didNavigate = false;

  @override
  void initState() {
    super.initState();

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      lowerBound: 0.0,
      upperBound: 1.0,
    );

    _progressController.addListener(_onAnimationTick);
    _initializeAndNavigate();
  }

  void _onAnimationTick() {
    final progress = (_progressController.value * 100).round();
    if (progress != _lastSentProgress) {
      _lastSentProgress = progress;
      if (kIsWeb) {
        WebSplashHelper.updateProgress(progress, _statusText);
      }
    }
  }

  void _setProgress(double target,
      {Duration duration = Duration.zero, Curve curve = Curves.linear}) {
    if (!mounted) return;
    final clamped = target.clamp(0.0, 1.0).toDouble();
    if (clamped <= _progressController.value + 0.001) return;
    if (duration == Duration.zero) {
      _progressController.value = clamped;
    } else {
      _progressController.animateTo(clamped, duration: duration, curve: curve);
    }
  }

  void _setStatus(String status,
      {double? progress,
      Duration duration = Duration.zero,
      Curve curve = Curves.linear}) {
    if (!mounted) return;
    setState(() => _statusText = status);
    if (progress != null) {
      _setProgress(progress, duration: duration, curve: curve);
    }
  }

  Future<void> _initializeAndNavigate() async {
    if (kIsWeb) {
      WebSplashHelper.flutterReady();
    }

    _setStatus('Initialisation...', progress: 0.02);

    try {
      await _runInitializationSteps().timeout(const Duration(seconds: 10));
    } catch (_) {
      _setStatus('Mode sécurisé…', progress: 0.98);
    }

    _setStatus('Prêt !', progress: 1.0);
    _navigateHomeOnce();
  }

  Future<void> _runInitializationSteps() async {
    final skipPrecache = kIsWeb && WebConnectionHelper.isLowBandwidth();
    if (!skipPrecache) {
      _setStatus('Chargement...', progress: 0.10);

      // Précache uniquement les SVGs critiques (dos + joker = 3 fichiers)
      // Les .vec pré-compilés sont chargés en priorité (quasi-instantané)
      await SvgPrecacheService()
          .precacheCriticalSvgs()
          .timeout(const Duration(seconds: 3));

      _setProgress(0.80);
    } else {
      _setStatus('Mode léger (connexion lente)', progress: 0.80);
    }

    // Attendre que l'AuthProvider soit initialisé (session Firebase).
    // Timeout court pour ne pas bloquer si le réseau est lent.
    // Cela évite un flash "non connecté" au menu quand l'user est déjà auth.
    _setStatus('Connexion...', progress: 0.88);
    try {
      final authProvider = context.read<AuthProvider>();
      if (!authProvider.isInitialized) {
        await _waitForAuth(authProvider).timeout(const Duration(seconds: 3));
      }
    } catch (_) {
      // Timeout ou erreur : on continue sans bloquer
    }

    _setStatus('Préparation...', progress: 0.95);
  }

  /// Attend que l'AuthProvider termine son init (poll léger).
  Future<void> _waitForAuth(AuthProvider auth) async {
    // L'init a déjà été lancée par le create du Provider (..init())
    // On attend simplement que isInitialized devienne true.
    while (!auth.isInitialized && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  void _navigateHomeOnce() {
    if (_didNavigate || !mounted) return;
    _didNavigate = true;
    AppRouter.markSplashDone();
    if (kIsWeb) {
      WebSplashHelper.hideSplash();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final deepLink = AppRouter.consumePendingDeepLink();
      context.go(deepLink ?? '/');
    });
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _progressController,
      builder: (context, _) => Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.2,
                    colors: [
                      AppColors.buttonSecondary,
                      AppColors.gradientBottom,
                      AppColors.gradientTop,
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isShort = constraints.maxHeight < 420;
                  final logoWidth =
                      ScreenUtils.scale(context, isShort ? 90 : 120);
                  final logoHeight =
                      ScreenUtils.scale(context, isShort ? 126 : 168);
                  final titleSize =
                      ScreenUtils.scaleFont(context, isShort ? 34 : 48);
                  final subtitleSize =
                      ScreenUtils.scaleFont(context, isShort ? 12 : 16);
                  final spacingLarge =
                      ScreenUtils.spacing(context, isShort ? 24 : 40);
                  final spacingSmall =
                      ScreenUtils.spacing(context, isShort ? 6 : 8);
                  final progressHeight =
                      ScreenUtils.scale(context, isShort ? 8 : 12);
                  final statusFont =
                      ScreenUtils.scaleFont(context, isShort ? 12 : 14);
                  final horizontalPadding = isShort ? 40.0 : 60.0;
                  final titleSpacing = isShort ? 6.0 : 8.0;
                  final subtitleSpacing = isShort ? 1.5 : 2.0;

                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        VectorGraphic(
                          loader: const AssetBytesLoader(
                            'assets/images/cards/joker-rouge.vec',
                          ),
                          width: logoWidth,
                          height: logoHeight,
                        ),
                        SizedBox(height: spacingLarge),
                        Text(
                          'DUTCH',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: titleSize,
                            fontWeight: FontWeight.bold,
                            letterSpacing: titleSpacing,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                offset: const Offset(0, 4),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: spacingSmall),
                        Text(
                          'Jeu de Mémoire et Stratégie',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: subtitleSize,
                            letterSpacing: subtitleSpacing,
                          ),
                        ),
                        SizedBox(height: spacingLarge),
                        Padding(
                          padding: ScreenUtils.adaptivePadding(
                            context,
                            horizontal: horizontalPadding,
                          ),
                          child: Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  ScreenUtils.borderRadius(context, 8),
                                ),
                                child: LinearProgressIndicator(
                                  value: null,
                                  minHeight: progressHeight,
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.2),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                    Color(0xFF4CAF50),
                                  ),
                                ),
                              ),
                              SizedBox(
                                  height: ScreenUtils.spacing(
                                      context, isShort ? 10 : 16)),
                              Text(
                                _statusText,
                                style: TextStyle(
                                  color: AppColors.textDisabled,
                                  fontSize: statusFont,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
