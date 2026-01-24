import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/player.dart';
import '../providers/game_provider.dart';
import '../widgets/card_widget.dart';
import '../widgets/responsive_dialog.dart';
import '../utils/screen_utils.dart';
import 'game_screen.dart';
import '../models/game_state.dart';

class MemorizationScreen extends StatefulWidget {
  const MemorizationScreen({super.key});

  @override
  State<MemorizationScreen> createState() => _MemorizationScreenState();
}

class _MemorizationScreenState extends State<MemorizationScreen>
    with TickerProviderStateMixin {
  final Set<int> _selectedCards = {};
  bool _isRevealing = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gameState = context.watch<GameProvider>().gameState;

    if (gameState == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0d2818),
        body: Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    }

    final humanPlayer = gameState.players.where((p) => p.isHuman).firstOrNull;

    if (humanPlayer == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0d2818),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0d2818), Color(0xFF1a472a)],
            ),
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.visibility_off, size: 60, color: Colors.white54),
                SizedBox(height: 20),
                Text(
                  "VOUS ÊTES ÉLIMINÉ",
                  style: TextStyle(
                    fontFamily: 'Rye',
                    fontSize: 32,
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  "Les bots continuent...",
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                SizedBox(height: 30),
                CircularProgressIndicator(color: Colors.amber),
              ],
            ),
          ),
        ),
      );
    }

    final canConfirm = _selectedCards.length == 2;
    // Responsive: adapter selon la taille d'écran
    final screenSize = MediaQuery.of(context).size;
    final isCompact = screenSize.height < 500 || screenSize.width < 600;
    final isMedium = !isCompact && (screenSize.height < 700 || screenSize.width < 900);
    final profile = ScreenUtils.getDeviceProfile(context);
    final isIphoneLandscape = profile == DeviceProfile.iPhoneLandscape;
    // Optimisation : moins de padding, cartes plus grandes sur mobile
    final iconSize = isIphoneLandscape ? 36.0 : (isCompact ? 44.0 : 64.0);
    final titleSize = isIphoneLandscape ? 24.0 : (isCompact ? 28.0 : (isMedium ? 34.0 : 40.0));
    final subtitleSize = isIphoneLandscape ? 12.0 : (isCompact ? 14.0 : (isMedium ? 16.0 : 18.0));
    final verticalSpacing = isIphoneLandscape ? 4.0 : (isCompact ? 6.0 : (isMedium ? 12.0 : 18.0));
    final horizontalPadding = isIphoneLandscape ? 8.0 : (isCompact ? 4.0 : 24.0);
    final verticalPadding = isIphoneLandscape ? 4.0 : (isCompact ? 4.0 : 24.0);
    final usableHeight = ScreenUtils.usableHeight(context);
    final isLandscape = ScreenUtils.isLandscape(context);
    final cardColumns = isLandscape ? 4 : 2;
    final cardRows = (4 / cardColumns).ceil();
    final cardAreaHeight = usableHeight * (isLandscape ? 0.5 : 0.38);

    return Scaffold(
      backgroundColor: const Color(0xFF0d2818),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0d2818), Color(0xFF1a472a)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.visibility,
                        size: iconSize, color: Colors.white54),
                    SizedBox(height: verticalSpacing),
                    Text(
                      "MÉMORISATION",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Rye',
                        fontSize: titleSize,
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                        shadows: const [
                          Shadow(
                            color: Colors.black45,
                            blurRadius: 10,
                            offset: Offset(2, 2),
                          )
                        ],
                      ),
                    ),
                    SizedBox(height: isIphoneLandscape ? 2 : (isCompact ? 2 : 10)),
                    Text(
                      "Clique sur 2 cartes pour les mémoriser.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: subtitleSize,
                      ),
                    ),
                    SizedBox(height: verticalSpacing),
                    SizedBox(
                      height: cardAreaHeight,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const aspect = 1.5;
                          final maxWidth = constraints.maxWidth;
                          final maxHeight = constraints.maxHeight;
                          final spacing =
                              (maxWidth * 0.03).clamp(6.0, 12.0);
                          final widthLimit =
                              (maxWidth - (cardColumns - 1) * spacing) /
                                  cardColumns;
                          final heightLimit =
                              (maxHeight - (cardRows - 1) * spacing) /
                                  cardRows;
                          final cardWidth = math.max(
                            0.0,
                            math.min(widthLimit, heightLimit / aspect),
                          );
                          final cardHeight = cardWidth * aspect;
                          final lift = cardHeight * 0.08;

                          return Center(
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: spacing,
                              runSpacing: spacing,
                              children: List.generate(4, (index) {
                                final isSelected =
                                    _selectedCards.contains(index);

                                return GestureDetector(
                                  onTap: () => _onCardTap(index),
                                  child: AnimatedBuilder(
                                    animation: _pulseController,
                                    builder: (context, child) {
                                      return Transform.scale(
                                        scale: isSelected
                                            ? 1.0 + (_pulseController.value * 0.05)
                                            : 1.0,
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 300),
                                          transform: Matrix4.translationValues(
                                            0,
                                            isSelected ? -lift : 0,
                                            0,
                                          ),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              ScreenUtils.borderRadius(context, 8),
                                            ),
                                            border: isSelected
                                                ? Border.all(
                                                    color: Colors.amber,
                                                    width: isCompact ? 2 : 3)
                                                : null,
                                            boxShadow: isSelected
                                                ? [
                                                    BoxShadow(
                                                      color: Colors.amber
                                                          .withValues(alpha: 0.5),
                                                      blurRadius: isCompact ? 10 : 15,
                                                      spreadRadius: isCompact ? 2 : 3,
                                                    )
                                                  ]
                                                : null,
                                          ),
                                          child: SizedBox(
                                            width: cardWidth,
                                            height: cardHeight,
                                            child: FittedBox(
                                              fit: BoxFit.contain,
                                              child: CardWidget(
                                                card: null,
                                                size: CardSize.large,
                                                isRevealed: false,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              }),
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(height: verticalSpacing * 1.2),
                    Center(
                      child: AnimatedOpacity(
                        opacity: canConfirm && !_isRevealing ? 1.0 : 0.3,
                        duration: const Duration(milliseconds: 300),
                        child: ElevatedButton(
                          onPressed: canConfirm && !_isRevealing
                              ? _confirmAndStart
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.black,
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompact ? 20 : 40,
                              vertical: isCompact ? 12 : 20,
                            ),
                            textStyle: TextStyle(
                              fontSize: isCompact ? 14 : 18,
                              fontWeight: FontWeight.bold,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                ScreenUtils.borderRadius(context, 12),
                              ),
                            ),
                          ),
                          child: Text(
                            canConfirm
                                ? "C'EST BON !"
                                : "CHOISIS ${2 - _selectedCards.length} CARTE(S)",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: isCompact ? 10 : 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onCardTap(int index) {
    if (_isRevealing) return;

    setState(() {
      if (_selectedCards.contains(index)) {
        _selectedCards.remove(index);
      } else if (_selectedCards.length < 2) {
        _selectedCards.add(index);
      }
    });
  }

  void _confirmAndStart() async {
    if (_selectedCards.length != 2 || _isRevealing) return;

    setState(() => _isRevealing = true);

    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final humanPlayer =
        gameProvider.gameState!.players.firstWhere((p) => p.isHuman);

    for (int index in _selectedCards) {
      humanPlayer.knownCards[index] = true;
    }

    if (!mounted) return;
    await _showRevealedCardsDialog(humanPlayer);

    for (var p in gameProvider.gameState!.players) {
      for (int i = 0; i < p.hand.length; i++) {
        p.knownCards[i] = false;
      }
    }

    gameProvider.gameState!.phase = GamePhase.playing;
    gameProvider.gameState!.isWaitingForSpecialPower = false;
    gameProvider.gameState!.specialCardToActivate = null;

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const GameScreen()),
    );

    Future.delayed(const Duration(milliseconds: 300), () {
      gameProvider.checkIfBotShouldPlay();
    });
  }

  Future<void> _showRevealedCardsDialog(Player humanPlayer) async {
    final revealedCards =
        _selectedCards.map((idx) => humanPlayer.hand[idx]).toList();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: ResponsiveDialog(
          backgroundColor: Colors.black87,
          builder: (context, metrics) {
            const aspect = 1.5;

            return SizedBox(
              width: metrics.contentWidth,
              height: metrics.contentHeight,
              child: Column(
                children: [
                  Expanded(
                    flex: 20,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final height = constraints.maxHeight;
                        final iconSize = height * 0.45;
                        final titleSize = height * 0.25;
                        final gap = height * 0.08;

                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.remove_red_eye,
                                  color: Colors.amber, size: iconSize),
                              SizedBox(height: gap),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  "VOS CARTES",
                                  style: TextStyle(
                                    color: Colors.amber,
                                    fontSize: titleSize,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    flex: 54,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final maxWidth = constraints.maxWidth;
                        final maxHeight = constraints.maxHeight;
                        final cardSpacing = math.min(
                          math.max(maxWidth * 0.04, metrics.space(6)),
                          metrics.space(14),
                        );
                        final cardWidthByWidth =
                            (maxWidth - cardSpacing) / 2;
                        final cardWidthByHeight = maxHeight / aspect;
                        final cardWidth = math.max(
                          0.0,
                          math.min(cardWidthByWidth, cardWidthByHeight),
                        );
                        final cardHeight = cardWidth * aspect;
                        final cardWidgets = <Widget>[];

                        for (int i = 0; i < revealedCards.length; i++) {
                          if (i > 0) {
                            cardWidgets.add(SizedBox(width: cardSpacing));
                          }

                          final card = revealedCards[i];
                          cardWidgets.add(
                            SizedBox(
                              width: cardWidth,
                              height: cardHeight,
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: CardWidget(
                                  card: card,
                                  size: CardSize.large,
                                  isRevealed: true,
                                ),
                              ),
                            ),
                          );
                        }

                        return Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: cardWidgets,
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    flex: 10,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final height = constraints.maxHeight;
                        final subtitleSize = height * 0.6;

                        return Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              "Mémorisez bien ces cartes !",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: subtitleSize,
                              ),
                              maxLines: 1,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    flex: 16,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final height = constraints.maxHeight;
                        final barHeight =
                            math.max(2.0, math.min(6.0, height * 0.18));
                        final gap = height * 0.16;
                        final textSize = height * 0.34;

                        return Center(
                          child: SizedBox(
                            width: constraints.maxWidth,
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: const Duration(seconds: 3),
                              builder: (context, value, child) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    LinearProgressIndicator(
                                      value: value,
                                      backgroundColor: Colors.white24,
                                      color: Colors.amber,
                                      minHeight: barHeight,
                                    ),
                                    SizedBox(height: gap),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        "${((1 - value) * 3).ceil()}s",
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: textSize,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).pop();
  }
}
