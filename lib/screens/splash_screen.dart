import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../main.dart';
import '../utils/screen_utils.dart';
import 'main_menu_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();

    // Animation de la barre de progression
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _progressController,
        curve: Curves.easeInOut,
      ),
    );

    _initializeAndNavigate();
  }

  Future<void> _initializeAndNavigate() async {
    // Démarrer l'animation
    _progressController.forward();

    // Initialiser l'application
    await initializeApp();

    // Attendre que l'animation soit terminée
    await _progressController.forward();

    // Petit délai supplémentaire
    await Future.delayed(const Duration(milliseconds: 300));

    // Naviguer vers le menu principal
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const MainMenuScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Fond qui occupe TOUT l'écran (ignore SafeArea)
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
          // Contenu dans SafeArea
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: ScreenUtils.spacing(context, 40)),

                    // Logo ou icône du jeu (SVG d'une carte)
                    SvgPicture.asset(
                      'assets/images/cards/joker-rouge.svg',
                      width: ScreenUtils.scale(context, 120),
                      height: ScreenUtils.scale(context, 168),
                    ),

                    SizedBox(height: ScreenUtils.spacing(context, 40)),

                    // Titre du jeu
                    Text(
                      'DUTCH',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: ScreenUtils.scaleFont(context, 48),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            offset: const Offset(0, 4),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: ScreenUtils.spacing(context, 8)),

                    // Sous-titre
                    Text(
                      'Jeu de Mémoire et Stratégie',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: ScreenUtils.scaleFont(context, 16),
                        letterSpacing: 2,
                      ),
                    ),

                    SizedBox(height: ScreenUtils.spacing(context, 40)),

                    // Barre de progression
                    Padding(
                      padding:
                          ScreenUtils.adaptivePadding(context, horizontal: 60),
                      child: Column(
                        children: [
                          AnimatedBuilder(
                            animation: _progressAnimation,
                            builder: (context, child) {
                              return Column(
                                children: [
                                  // Barre de progression
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      ScreenUtils.borderRadius(context, 8),
                                    ),
                                    child: LinearProgressIndicator(
                                      value: _progressAnimation.value,
                                      minHeight: ScreenUtils.scale(context, 8),
                                      backgroundColor:
                                          Colors.white.withValues(alpha: 0.2),
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                        Color(0xFF4CAF50),
                                      ),
                                    ),
                                  ),

                                  SizedBox(
                                      height: ScreenUtils.spacing(context, 16)),

                                  // Texte de chargement
                                  Text(
                                    _getLoadingText(_progressAnimation.value),
                                    style: TextStyle(
                                      color: Colors.white60,
                                      fontSize:
                                          ScreenUtils.scaleFont(context, 14),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: ScreenUtils.spacing(context, 40)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getLoadingText(double progress) {
    if (progress < 0.3) {
      return 'Initialisation...';
    } else if (progress < 0.6) {
      return 'Chargement des cartes...';
    } else if (progress < 0.9) {
      return 'Préparation des bots...';
    } else {
      return 'Prêt !';
    }
  }
}
