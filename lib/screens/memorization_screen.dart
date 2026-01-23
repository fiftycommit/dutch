import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/player.dart';
import '../providers/game_provider.dart';
import '../widgets/card_widget.dart';
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
          child: SingleChildScrollView(
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: ScreenUtils.spacing(context, 16),
                  vertical: ScreenUtils.spacing(context, 20),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.visibility,
                        size: 60, color: Colors.white54),
                    SizedBox(height: ScreenUtils.spacing(context, 20)),
                    Text(
                      "MÉMORISATION",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Rye',
                        fontSize: ScreenUtils.scaleFont(context, 36),
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
                    SizedBox(height: ScreenUtils.spacing(context, 10)),
                    Text(
                      "Clique sur 2 cartes pour les mémoriser.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: ScreenUtils.scaleFont(context, 16),
                      ),
                    ),
                    SizedBox(height: ScreenUtils.spacing(context, 30)),
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: ScreenUtils.spacing(context, 8),
                        runSpacing: ScreenUtils.spacing(context, 8),
                        children: List.generate(4, (index) {
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
                                      0,
                                      isSelected ? -10 : 0,
                                      0,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        ScreenUtils.borderRadius(context, 8),
                                      ),
                                      border: isSelected
                                          ? Border.all(
                                              color: Colors.amber, width: 3)
                                          : null,
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: Colors.amber
                                                    .withValues(alpha: 0.5),
                                                blurRadius: 15,
                                                spreadRadius: 3,
                                              )
                                            ]
                                          : null,
                                    ),
                                    child: const CardWidget(
                                      card: null,
                                      size: CardSize.large,
                                      isRevealed: false,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        }),
                      ),
                    ),
                    SizedBox(height: ScreenUtils.spacing(context, 30)),
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
                              horizontal: ScreenUtils.spacing(context, 40),
                              vertical: ScreenUtils.spacing(context, 20),
                            ),
                            textStyle: TextStyle(
                              fontSize: ScreenUtils.scaleFont(context, 18),
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
                    SizedBox(height: ScreenUtils.spacing(context, 20)),
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
        child: Dialog(
          backgroundColor: Colors.black87,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.remove_red_eye, color: Colors.amber, size: 50),
                const SizedBox(height: 16),
                const Text(
                  "VOS CARTES",
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: revealedCards.map((card) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: CardWidget(
                        card: card,
                        size: CardSize.large,
                        isRevealed: true,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Mémorisez bien ces cartes !",
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(seconds: 3),
                  builder: (context, value, child) {
                    return Column(
                      children: [
                        LinearProgressIndicator(
                          value: value,
                          backgroundColor: Colors.white24,
                          color: Colors.amber,
                          minHeight: 4,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "${((1 - value) * 3).ceil()}s",
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).pop();
  }
}
