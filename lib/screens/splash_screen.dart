import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/ui_constants.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../main.dart';
import '../utils/screen_utils.dart';
import '../services/ui/svg_precache_service.dart';
import 'web_splash_helper.dart' if (dart.library.io) 'web_splash_helper_stub.dart';
import 'web_connection_helper.dart' if (dart.library.io) 'web_connection_helper_stub.dart';

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

  void _setProgress(double target, {Duration duration = Duration.zero, Curve curve = Curves.linear}) {
    if (!mounted) return;
    final clamped = target.clamp(0.0, 1.0).toDouble();
    if (clamped <= _progressController.value + 0.001) return;
    if (duration == Duration.zero) {
      _progressController.value = clamped;
    } else {
      _progressController.animateTo(clamped, duration: duration, curve: curve);
    }
  }

  void _setStatus(String status, {double? progress, Duration duration = Duration.zero, Curve curve = Curves.linear}) {
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

    await initializeApp();
    final skipPrecache = kIsWeb && WebConnectionHelper.isLowBandwidth();
    if (!skipPrecache) {
      _setStatus('Chargement des cartes...', progress: 0.05);

      await SvgPrecacheService().precacheCardSvgs(
        skipIfCached: true,
        onProgress: (progress) {
          // 5% -> 95% pendant le précache des cartes
          final weighted = 0.05 + (progress * 0.90);
          _setProgress(weighted);
        },
      );
    } else {
      _setStatus('Mode léger (connexion lente)', progress: 0.90);
    }
    _setStatus('Préparation...', progress: 0.95);

    _setStatus('Prêt !', progress: 1.0);
    if (mounted) context.go('/');
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
                    Color(0xFF2d5f3e),
                    Color(0xFF1a472a),
                    Color(0xFF0d2818),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isShort = constraints.maxHeight < 420;
                final logoWidth = ScreenUtils.scale(context, isShort ? 90 : 120);
                final logoHeight = ScreenUtils.scale(context, isShort ? 126 : 168);
                final titleSize = ScreenUtils.scaleFont(context, isShort ? 34 : 48);
                final subtitleSize = ScreenUtils.scaleFont(context, isShort ? 12 : 16);
                final spacingLarge = ScreenUtils.spacing(context, isShort ? 24 : 40);
                final spacingSmall = ScreenUtils.spacing(context, isShort ? 6 : 8);
                final progressHeight = ScreenUtils.scale(context, isShort ? 8 : 12);
                final statusFont = ScreenUtils.scaleFont(context, isShort ? 12 : 14);
                final horizontalPadding = isShort ? 40.0 : 60.0;
                final titleSpacing = isShort ? 6.0 : 8.0;
                final subtitleSpacing = isShort ? 1.5 : 2.0;

                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        'assets/images/cards/joker-rouge.svg',
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
                                backgroundColor: Colors.white.withValues(alpha: 0.2),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFF4CAF50),
                                ),
                              ),
                            ),
                            SizedBox(height: ScreenUtils.spacing(context, isShort ? 10 : 16)),
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
