import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../models/player.dart';
import '../../utils/ui_constants.dart';
import '../../widgets/game/card_widget.dart';
import '../../widgets/game/flip_card_widget.dart';
import '../../widgets/dialogs/responsive_dialog.dart';
import '../../utils/screen_utils.dart';

/// Configuration pour l'écran de mémorisation
class MemorizationConfig {
  /// Le joueur local qui doit mémoriser ses cartes
  final Player localPlayer;

  /// Callback quand la mémorisation est terminée
  final Future<void> Function(Set<int> selectedIndices) onMemorizationComplete;

  /// Navigation vers l'écran de jeu via GoRouter
  final void Function(BuildContext context) navigateToGame;

  /// Durée du timer en secondes (null = pas de timer)
  final int? countdownSeconds;

  /// Afficher l'écran d'attente après confirmation (multiplayer)
  final bool showWaitingScreen;

  /// Stream d'événements pour démarrer le jeu (multiplayer)
  final Stream<void>? gameStartStream;

  /// Callback pour marquer le joueur comme prêt (multiplayer)
  final VoidCallback? onMarkReady;

  /// Builder pour l'info de joueurs prêts (multiplayer)
  final Widget Function(BuildContext context)? buildReadyInfo;

  /// Message quand le joueur n'existe pas
  final String noPlayerMessage;

  /// Titre du message quand le joueur n'existe pas
  final String noPlayerTitle;

  const MemorizationConfig({
    required this.localPlayer,
    required this.onMemorizationComplete,
    required this.navigateToGame,
    this.countdownSeconds,
    this.showWaitingScreen = false,
    this.gameStartStream,
    this.onMarkReady,
    this.buildReadyInfo,
    this.noPlayerMessage = "Les bots continuent...",
    this.noPlayerTitle = "VOUS ÊTES ÉLIMINÉ",
  });
}

/// Écran de mémorisation unifié (solo + multiplayer)
class MemorizationScreen extends StatefulWidget {
  final MemorizationConfig config;

  const MemorizationScreen({super.key, required this.config});

  @override
  State<MemorizationScreen> createState() => _MemorizationScreenState();
}

class _MemorizationScreenState extends State<MemorizationScreen>
    with TickerProviderStateMixin {
  final Set<int> _selectedCards = {};
  bool _isRevealing = false;
  bool _isWaiting = false;
  late AnimationController _pulseController;

  Timer? _countdownTimer;
  int _remainingSeconds = 0;
  StreamSubscription? _gameStartSubscription;

  MemorizationConfig get config => widget.config;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat(reverse: true);

    // Setup countdown if enabled
    if (config.countdownSeconds != null) {
      _remainingSeconds = config.countdownSeconds!;
      _startCountdown();
    }

    // Setup game start listener for multiplayer
    if (config.gameStartStream != null) {
      _gameStartSubscription = config.gameStartStream!.listen((_) {
        if (mounted) {
          _navigateToGame();
        }
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _countdownTimer?.cancel();
    _gameStartSubscription?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          timer.cancel();
          _handleTimeout();
        }
      });
    });
  }

  void _handleTimeout() {
    if (_isRevealing || _isWaiting) return;

    // Auto-select random cards if not enough selected
    if (_selectedCards.length < 2) {
      final availableIndices =
          List.generate(config.localPlayer.hand.length, (i) => i)
              .where((i) => !_selectedCards.contains(i))
              .toList();
      availableIndices.shuffle();

      int needed = 2 - _selectedCards.length;
      for (int i = 0; i < needed && i < availableIndices.length; i++) {
        _selectedCards.add(availableIndices[i]);
      }
    }

    _confirmAndStart();
  }

  void _onCardTap(int index) {
    if (_isRevealing || _isWaiting) return;

    setState(() {
      if (_selectedCards.contains(index)) {
        _selectedCards.remove(index);
      } else if (_selectedCards.length < 2) {
        _selectedCards.add(index);
      }
    });

  }

  void _confirmAndStart() async {
    if (_selectedCards.length != 2 || _isRevealing || _isWaiting) return;

    setState(() => _isRevealing = true);
    _countdownTimer?.cancel();

    if (!mounted) return;
    await _showRevealedCardsDialog();

    if (!mounted) return;

    // Call completion callback
    await config.onMemorizationComplete(_selectedCards);

    if (!mounted) return;

    if (config.showWaitingScreen) {
      setState(() => _isWaiting = true);
      config.onMarkReady?.call();
      // Navigation will happen via gameStartStream
    } else {
      _navigateToGame();
    }
  }

  void _navigateToGame() {
    config.navigateToGame(context);
  }

  Future<void> _showRevealedCardsDialog() async {
    // Toutes les cartes avec leurs indices
    final allCards = config.localPlayer.hand;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: ResponsiveDialog(
          backgroundColor: Colors.black87,
          builder: (context, metrics) {
            const aspect = 7 / 5;

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
                          math.max(maxWidth * 0.02, metrics.space(4)),
                          metrics.space(10),
                        );
                        // 4 cartes côte à côte
                        final cardWidthByWidth =
                            (maxWidth - cardSpacing * 3) / 4;
                        final cardWidthByHeight = maxHeight / aspect;
                        final cardWidth = math.max(
                          0.0,
                          math.min(cardWidthByWidth, cardWidthByHeight),
                        );
                        final cardHeight = cardWidth * aspect;

                        return Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (int i = 0; i < allCards.length; i++) ...[
                                if (i > 0) SizedBox(width: cardSpacing),
                                SizedBox(
                                  width: cardWidth,
                                  height: cardHeight,
                                  child: FittedBox(
                                    fit: BoxFit.contain,
                                    child: _selectedCards.contains(i)
                                        ? AnimatedFlipCard(
                                            card: allCards[i],
                                            isRevealed: true,
                                            cardSize: CardSize.large,
                                            delay: Duration(
                                                milliseconds: 200 + i * 150),
                                            duration: const Duration(
                                                milliseconds: 500),
                                          )
                                        : CardWidget(
                                            card: null,
                                            size: CardSize.large,
                                            isRevealed: false,
                                          ),
                                  ),
                                ),
                              ],
                            ],
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
                                color: AppColors.textSecondary,
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
                              duration: const Duration(seconds: 4),
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
                                        "${((1 - value) * 4).ceil()}s",
                                        style: TextStyle(
                                          color: AppColors.textDisabled,
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

    await Future.delayed(const Duration(seconds: 4));

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Waiting screen (multiplayer)
    if (_isWaiting) {
      return Scaffold(
        backgroundColor: AppColors.gradientBottom,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.amber),
              const SizedBox(height: 20),
              const Text(
                'En attente des autres joueurs...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (config.buildReadyInfo != null) ...[
                const SizedBox(height: 10),
                config.buildReadyInfo!(context),
              ],
            ],
          ),
        ),
      );
    }

    // No player / spectator screen
    if (config.localPlayer.isSpectator) {
      return Scaffold(
        backgroundColor: AppColors.gradientBottom,
        body: Container(
          color: AppColors.gradientBottom,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.visibility_off,
                    size: 60, color: AppColors.textDisabled),
                const SizedBox(height: 20),
                Text(
                  config.noPlayerTitle,
                  style: const TextStyle(
                    fontFamily: 'Rye',
                    fontSize: 32,
                    color: Colors.amberAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  config.noPlayerMessage,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 16),
                ),
                const SizedBox(height: 30),
                const CircularProgressIndicator(color: Colors.amber),
              ],
            ),
          ),
        ),
      );
    }

    final canConfirm = _selectedCards.length == 2;
    final screenSize = MediaQuery.of(context).size;
    final isCompact = screenSize.height < 500 || screenSize.width < 600;
    final isMedium =
        !isCompact && (screenSize.height < 700 || screenSize.width < 900);
    final profile = ScreenUtils.getDeviceProfile(context);
    final isIphoneLandscape = profile == DeviceProfile.iPhoneLandscape;

    final iconSize = isIphoneLandscape ? 36.0 : (isCompact ? 44.0 : 64.0);
    final titleSize = isIphoneLandscape
        ? 24.0
        : (isCompact ? 28.0 : (isMedium ? 34.0 : 40.0));
    final subtitleSize = isIphoneLandscape
        ? 12.0
        : (isCompact ? 14.0 : (isMedium ? 16.0 : 18.0));
    final verticalSpacing =
        isIphoneLandscape ? 4.0 : (isCompact ? 6.0 : (isMedium ? 12.0 : 18.0));
    final horizontalPadding =
        isIphoneLandscape ? 8.0 : (isCompact ? 4.0 : 24.0);
    final verticalPadding = isIphoneLandscape ? 4.0 : (isCompact ? 4.0 : 24.0);
    final usableHeight = ScreenUtils.usableHeight(context);
    final isLandscape = ScreenUtils.isLandscape(context);
    final cardColumns = isLandscape ? 4 : 2;
    final cardRows = (4 / cardColumns).ceil();
    final cardAreaHeight = usableHeight * (isLandscape ? 0.5 : 0.38);

    return Scaffold(
      backgroundColor: AppColors.gradientBottom,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: AppColors.gradientBottom,
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
                        size: iconSize, color: AppColors.textDisabled),
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
                    SizedBox(
                        height: isIphoneLandscape ? 2 : (isCompact ? 2 : 10)),
                    // Countdown timer (multiplayer)
                    if (config.countdownSeconds != null) ...[
                      Text(
                        "Temps restant: $_remainingSeconds s",
                        style: TextStyle(
                          color: _remainingSeconds <= 5
                              ? Colors.redAccent
                              : Colors.amberAccent,
                          fontSize: subtitleSize * 1.2,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(
                          height: isIphoneLandscape ? 2 : (isCompact ? 2 : 5)),
                    ],
                    Text(
                      "Clique sur 2 cartes pour les mémoriser.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: subtitleSize,
                      ),
                    ),
                    SizedBox(height: verticalSpacing),
                    SizedBox(
                      height: cardAreaHeight,
                      child: _buildCardGrid(
                        isCompact: isCompact,
                        cardColumns: cardColumns,
                        cardRows: cardRows,
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

  Widget _buildCardGrid({
    required bool isCompact,
    required int cardColumns,
    required int cardRows,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const aspect = 7 / 5;
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final spacing = (maxWidth * 0.03).clamp(6.0, 12.0);
        final widthLimit =
            (maxWidth - (cardColumns - 1) * spacing) / cardColumns;
        const liftFactor = 0.08;
        const maxScale = 1.05;
        const extraTopFactor = liftFactor + ((maxScale - 1.0) / 2);
        final heightLimit = (maxHeight - (cardRows - 1) * spacing) /
            (cardRows + extraTopFactor);
        final cardWidth =
            math.max(0.0, math.min(widthLimit, heightLimit / aspect));
        final cardHeight = cardWidth * aspect;
        final lift = cardHeight * liftFactor;
        final topInset = cardHeight * extraTopFactor;

        return Center(
          child: Padding(
            padding: EdgeInsets.only(top: topInset),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: spacing,
              runSpacing: spacing,
              children: List.generate(config.localPlayer.hand.length, (index) {
                final isSelected = _selectedCards.contains(index);

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
                              0, isSelected ? -lift : 0, 0),
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
                                      color:
                                          Colors.amber.withValues(alpha: 0.5),
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
                              // Pendant la sélection, toutes les cartes restent dos visible
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
          ),
        );
      },
    );
  }
}
