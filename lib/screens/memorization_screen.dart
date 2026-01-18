import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/player.dart';
import '../models/card.dart';
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
  Set<int> _selectedCards =
      {}; // ✅ Cartes sélectionnées (mais PAS encore révélées)
  bool _isRevealing = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    debugPrint("🎬 [MemorizationScreen] INIT");
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
    final gameProvider = Provider.of<GameProvider>(context);
    final gameState = gameProvider.gameState;

    if (gameState == null) {
      debugPrint("⚠️ [MemorizationScreen] GameState NULL");
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    }

    final humanPlayer = gameState.players.where((p) => p.isHuman).firstOrNull;

    if (humanPlayer == null) {
      // Mode spectateur : joueur éliminé
      debugPrint(
          "⚠️ [MemorizationScreen] Aucun joueur humain (mode spectateur)");

      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0d2818), Color(0xFF1a472a)],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.visibility_off,
                    size: 60, color: Colors.white54),
                const SizedBox(height: 20),
                const Text(
                  "VOUS ÊTES ÉLIMINÉ",
                  style: TextStyle(
                    fontFamily: 'Rye',
                    fontSize: 32,
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Les bots continuent...",
                  style: TextStyle(color: Colors.white70, fontSize: 16),
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

    debugPrint("📊 [MemorizationScreen] Cartes sélectionnées: $_selectedCards");

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0d2818), Color(0xFF1a472a)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
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
                        const Icon(Icons.visibility,
                            size: 60, color: Colors.white54),
                        SizedBox(height: ScreenUtils.spacing(context, 20)),

                        Text(
                          "MÉMORISATION",
                          style: TextStyle(
                            fontFamily: 'Rye',
                            fontSize: ScreenUtils.scaleFont(context, 36),
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                            shadows: const [
                              Shadow(
                                  color: Colors.black45,
                                  blurRadius: 10,
                                  offset: Offset(2, 2))
                            ],
                          ),
                        ),

                        SizedBox(height: ScreenUtils.spacing(context, 10)),

                        Text(
                          "Clique sur 2 cartes pour les mémoriser.",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: ScreenUtils.scaleFont(context, 16),
                          ),
                        ),

                        SizedBox(height: ScreenUtils.spacing(context, 30)),

                        // ✅ CARTES (Sélection SANS révélation immédiate)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(4, (index) {
                            final isSelected = _selectedCards.contains(index);

                            return Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: ScreenUtils.spacing(context, 8),
                              ),
                              child: GestureDetector(
                                onTap: () => _onCardTap(index),
                                child: AnimatedBuilder(
                                  animation: _pulseController,
                                  builder: (context, child) {
                                    return Transform.scale(
                                      scale: isSelected
                                          ? 1.0 +
                                              (_pulseController.value * 0.05)
                                          : 1.0,
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 300),
                                        transform: Matrix4.translationValues(
                                          0,
                                          isSelected ? -10 : 0,
                                          0,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            ScreenUtils.borderRadius(
                                                context, 8),
                                          ),
                                          border: isSelected
                                              ? Border.all(
                                                  color: Colors.amber, width: 3)
                                              : null,
                                          boxShadow: isSelected
                                              ? [
                                                  BoxShadow(
                                                    color: Colors.amber
                                                        .withOpacity(0.5),
                                                    blurRadius: 15,
                                                    spreadRadius: 3,
                                                  )
                                                ]
                                              : null,
                                        ),
                                        child: CardWidget(
                                          card: null, // ✅ Toujours DOS
                                          size: CardSize.large,
                                          isRevealed: false, // ✅ Toujours FAUX
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          }),
                        ),

                        SizedBox(height: ScreenUtils.spacing(context, 30)),

                        // Bouton de confirmation
                        AnimatedOpacity(
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
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _onCardTap(int index) {
    if (_isRevealing) {
      debugPrint(
          "⏸️ [MemorizationScreen] Action bloquée (révélation en cours)");
      return;
    }

    setState(() {
      if (_selectedCards.contains(index)) {
        debugPrint("❌ [MemorizationScreen] Désélection carte $index");
        _selectedCards.remove(index);
      } else if (_selectedCards.length < 2) {
        debugPrint("✅ [MemorizationScreen] Sélection carte $index");
        _selectedCards.add(index);
      }
    });
  }

  void _confirmAndStart() async {
    if (_selectedCards.length != 2 || _isRevealing) return;

    debugPrint(
        "🎯 [MemorizationScreen] CONFIRMATION - Cartes sélectionnées: $_selectedCards");

    setState(() => _isRevealing = true);

    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final humanPlayer =
        gameProvider.gameState!.players.firstWhere((p) => p.isHuman);

    // ✅ Révéler TEMPORAIREMENT les cartes sélectionnées
    for (int index in _selectedCards) {
      humanPlayer.knownCards[index] = true;
    }
    debugPrint("👁️ [MemorizationScreen] Cartes révélées temporairement");

    // ✅ Afficher un dialogue avec les cartes révélées
    if (!mounted) return;
    await _showRevealedCardsDialog(humanPlayer);

    // ✅ Masquer TOUTES les cartes après mémorisation
    for (var p in gameProvider.gameState!.players) {
      for (int i = 0; i < p.hand.length; i++) {
        p.knownCards[i] = false;
      }
    }
    debugPrint("🙈 [MemorizationScreen] Toutes les cartes masquées");

    // ✅ Passer en phase PLAYING
    gameProvider.gameState!.phase = GamePhase.playing;
    gameProvider.gameState!.isWaitingForSpecialPower = false;
    gameProvider.gameState!.specialCardToActivate = null;

    debugPrint("🎮 [MemorizationScreen] Passage en phase PLAYING");
    debugPrint(
        "👤 [MemorizationScreen] Joueur actuel: ${gameProvider.gameState!.currentPlayer.name}");
    debugPrint(
        "🤖 [MemorizationScreen] Est un bot: ${!gameProvider.gameState!.currentPlayer.isHuman}");

    if (!mounted) return;

    // ✅ Naviguer vers l'écran de jeu
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const GameScreen()),
    );

    debugPrint("🚀 [MemorizationScreen] Navigation vers GameScreen");

    // ✅ CRITIQUE: Vérifier si un bot doit jouer après la navigation
    Future.delayed(const Duration(milliseconds: 300), () {
      debugPrint("🔍 [MemorizationScreen] Check post-navigation");
      gameProvider.checkIfBotShouldPlay();
    });
  }

  Future<void> _showRevealedCardsDialog(Player humanPlayer) async {
    debugPrint("🎭 [_showRevealedCardsDialog] Affichage dialogue");

    final revealedCards =
        _selectedCards.map((idx) => humanPlayer.hand[idx]).toList();

    // 🔍 VAR TACTIQUE : Révélation
    debugPrint("\n🔍 [VAR - MEMO] --------------------------------------");
    debugPrint("👀 Tu as regardé les indices : $_selectedCards");
    debugPrint(
        "🃏 Valeurs révélées : ${revealedCards.map((c) => c.value).toList()}");
    debugPrint("-------------------------------------------------------\n");

    // Afficher le dialogue
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false, // Empêcher la fermeture
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

                // Afficher les 2 cartes révélées
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

                // Indicateur de progression
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

    debugPrint("   ⏳ Attente 3 secondes...");

    // Attendre 3 secondes pour mémoriser
    await Future.delayed(const Duration(seconds: 3));

    debugPrint("   ✅ Fin de mémorisation");

    if (!mounted) {
      debugPrint("   ⚠️ Widget non monté, abandon");
      return;
    }

    // Fermer le dialogue
    Navigator.of(context, rootNavigator: true).pop();
    debugPrint("   🚪 Dialogue fermé");
  }
}
