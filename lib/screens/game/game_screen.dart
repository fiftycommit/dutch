import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:dutch_game/models/game_state.dart';
import 'package:dutch_game/models/player.dart';
import 'package:dutch_game/providers/game_provider.dart';
import 'package:dutch_game/providers/settings_provider.dart';
import 'package:dutch_game/widgets/dialogs/shared/unified_power_dialogs.dart';
import 'package:dutch_game/screens/shared/game_screen_mixin.dart';
import 'package:dutch_game/widgets/dialogs/game/game_dialogs.dart';
import 'package:dutch_game/widgets/game/game_table_widget.dart';
import 'package:dutch_game/utils/tournament_labels.dart';
import 'package:dutch_game/utils/ui_constants.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with GameLayoutMixin<GameScreen>, GameScreenMixin<GameScreen> {
  String? _specialPowerReadyId;
  String? _specialPowerDialogShownId;

  @override
  void initState() {
    super.initState();
    resetEndGameNavigation(); // Reset guard on screen entry
    lockLandscapeOrientation();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final gameProvider = Provider.of<GameProvider>(context, listen: false);
      gameProvider.setContext(context);
      _tryNavigateToEnd(gameProvider.gameState);
      _checkAndStartBotTurn();
    });
  }

  @override
  void dispose() {
    unlockOrientation();
    super.dispose();
  }

  void _tryNavigateToEnd(GameState? gameState) {
    if (gameState == null) return;
    final routeLocation = gameState.dutchCallerId != null
        ? '/solo/dutch-reveal'
        : '/solo/results';
    maybeNavigateToEnd(gameState: gameState, routeLocation: routeLocation);
  }

  void _checkAndStartBotTurn() {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    final gameState = gameProvider.gameState;

    if (gameState == null) return;

    if (!gameState.currentPlayer.isHuman &&
        gameState.phase == GamePhase.playing &&
        !gameProvider.isProcessing) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          gameProvider.checkIfBotShouldPlay();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameState = context.watch<GameProvider>().gameState;

    if (gameState != null && gameState.phase == GamePhase.ended) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tryNavigateToEnd(gameState);
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1a472a),
      body: Consumer<GameProvider>(
        builder: (context, gameProvider, child) {
          if (!gameProvider.hasActiveGame) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.amber));
          }

          final gameState = gameProvider.gameState!;
          final totalRounds = gameState.gameMode == GameMode.tournament
              ? gameProvider.tournamentTotalRounds
              : 1;
          final remainingRounds = (totalRounds - gameState.tournamentRound)
              .clamp(0, totalRounds)
              .toInt();

          final size = MediaQuery.of(context).size;
          final isPortrait = size.height > size.width;
          
          if (kIsWeb && isPortrait) {
            return _buildRotateScreenOverlay();
          }

          return Stack(
            children: [
              GameTableWidget(
                gameState: gameState,
                isProcessing: gameProvider.isProcessing,
                shakingCardIndices: gameProvider.shakingCardIndices.toList(),
                callbacks: GameTableCallbacks.fromController(
                  context: context,
                  controller: gameProvider,
                  supportsTakeFromDiscard: false, // Solo mode
                ),
                onSpecialPowerAnimationComplete: (cardId) {
                  if (!mounted) return;
                  setState(() {
                    _specialPowerReadyId = cardId;
                    _specialPowerDialogShownId = null;
                  });
                },
                multiplayerConfig: MultiplayerConfig(
                  reactionTimeTotalMs: gameProvider.currentReactionTimeMs,
                ),
              ),
              if (gameState.gameMode == GameMode.tournament)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            tournamentStageLabel(
                              gameState.tournamentRound,
                              totalRounds: totalRounds,
                            ),
                            style: const TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(
                          "Manches restantes : $remainingRounds",
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (gameState.phase == GamePhase.dutchCalled)
                _buildDutchNotification(gameState),
              if (gameState.isWaitingForSpecialPower)
                _buildSpecialPowerOverlay(gameProvider, gameState),
              if (gameProvider.isProcessing)
                const Positioned(
                  top: 20,
                  right: 60,
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.textDisabled)),
                ),
              // Bouton Pause
              Positioned(
                top: 10,
                right: 10,
                child: IconButton(
                  onPressed: () => gameProvider.pauseGame(),
                  icon: const Icon(Icons.pause_circle_outline, color: AppColors.textSecondary, size: 32),
                  tooltip: 'Pause',
                ),
              ),
              if (gameProvider.isPaused)
                _buildPauseOverlay(gameProvider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSpecialPowerOverlay(GameProvider gp, GameState gs) {
    if (gs.specialCardToActivate == null) {
      _specialPowerReadyId = null;
      _specialPowerDialogShownId = null;
      return const SizedBox();
    }
    if (!gs.currentPlayer.isHuman) return const SizedBox();

    Player? playerWithPower;

    if (gs.currentPlayer.isHuman && gs.isWaitingForSpecialPower) {
      playerWithPower = gs.currentPlayer;
    } else {
      try {
        playerWithPower = gs.players.firstWhere((p) => p.isHuman);
      } catch (e) {
        return const SizedBox();
      }
    }

    if (!playerWithPower.isHuman) return const SizedBox();

    final animationsEnabled =
        context.watch<SettingsProvider>().animationsEnabled;

    final trigger = gs.specialCardToActivate!;
    final triggerId = trigger.id;

    if (!gs.isWaitingForSpecialPower) {
      _resetSpecialPowerState();
      return const SizedBox();
    }

    final ready = !animationsEnabled || _specialPowerReadyId == triggerId;
    if (!ready) {
      return const AbsorbPointer(
        child: SizedBox.expand(),
      );
    }

    if (_specialPowerDialogShownId != triggerId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final current = gp.gameState;
        if (current == null ||
            !current.isWaitingForSpecialPower ||
            current.specialCardToActivate?.id != triggerId) {
          return;
        }
        if (ModalRoute.of(context)?.isCurrent != true) return;
        _specialPowerDialogShownId = triggerId;
        final val = trigger.value;
        final config = PowerDialogConfig.solo(context);
        if (val == '7') {
          UnifiedPowerDialogs.showPower7Dialog(context, trigger, config);
        } else if (val == '10') {
          UnifiedPowerDialogs.showPower10Dialog(context, trigger, config);
        } else if (val == 'V') {
          UnifiedPowerDialogs.showValetSwapDialog(context, trigger, config);
        } else if (val == 'JOKER') {
          UnifiedPowerDialogs.showJokerDialog(context, trigger, config);
        } else {
          gp.skipSpecialPower();
        }
      });
    }

    return Container(color: Colors.black54);
  }

  void _resetSpecialPowerState() {
    _specialPowerReadyId = null;
    _specialPowerDialogShownId = null;
  }

  Widget _buildDutchNotification(GameState gs) {
    return Container(
      color: Colors.amber.withValues(alpha: 0.9),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.campaign, size: 80, color: Colors.black),
            Text(
                "${gs.dutchCallerId == null ? 'DUTCH' : 'QUELQU\'UN'} A CRIÉ DUTCH !",
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showQuitConfirmation() {
    return GameDialogs.confirmQuit(context);
  }

  Widget _buildPauseOverlay(GameProvider gp) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pause_circle_outline, color: Colors.amber, size: 80),
            const SizedBox(height: 20),
            const Text(
              "PAUSE",
              style: TextStyle(
                color: Colors.amber,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                fontFamily: 'Rye',
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () => gp.resumeGame(),
              icon: const Icon(Icons.play_arrow, size: 28),
              label: const Text("REPRENDRE", style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () async {
                gp.resumeGame();
                final shouldQuit = await _showQuitConfirmation();
                if (shouldQuit == true && mounted) {
                  if (!context.mounted) return;
                  gp.quitGame();
                  context.go('/');
                } else {
                  gp.pauseGame();
                }
              },
              icon: const Icon(Icons.exit_to_app, color: Colors.redAccent),
              label: const Text("Quitter la partie", style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRotateScreenOverlay() {
    return Container(
      color: const Color(0xFF1a472a),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1500),
              builder: (context, value, child) {
                return Transform.rotate(
                  angle: value * 1.57,
                  child: const Icon(
                    Icons.screen_rotation,
                    size: 80,
                    color: Colors.amber,
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            const Text(
              '📱 Tournez votre écran',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Le jeu Dutch se joue en mode paysage',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '(ou agrandissez la fenêtre)',
              style: TextStyle(
                color: AppColors.textDisabled,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
