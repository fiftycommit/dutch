import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/card.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../providers/game_provider.dart';
import '../widgets/card_widget.dart';
import '../widgets/player_hand.dart';
import '../widgets/player_avatar.dart';
import 'results_screen.dart';
import '../widgets/special_power_dialogs.dart';
import 'main_menu_screen.dart';
import 'dutch_reveal_screen.dart';
import '../services/web_orientation_service.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    
    if (kIsWeb) {
      // Sur le web, essayer de forcer le mode paysage via l'API Screen Orientation
      WebOrientationService.lockLandscape();
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndNavigateIfEnded();
      _checkAndStartBotTurn();
    });
  }

  @override
  void dispose() {
    if (kIsWeb) {
      WebOrientationService.unlock();
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    super.dispose();
  }

  void _checkAndNavigateIfEnded() {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    if (gameProvider.gameState != null && gameProvider.gameState!.phase == GamePhase.ended) {
      if (ModalRoute.of(context)?.isCurrent == true && mounted) {
        if (gameProvider.gameState!.dutchCallerId != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const DutchRevealScreen()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const ResultsScreen()),
          );
        }
      }
    }
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
          gameProvider.gameState;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameState = context.watch<GameProvider>().gameState;

    if (gameState != null && gameState.phase == GamePhase.ended) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ModalRoute.of(context)?.isCurrent == true && mounted) {
          if (gameState.dutchCallerId != null) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const DutchRevealScreen()),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const ResultsScreen()),
            );
          }
        }
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

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                !gameState.currentPlayer.isHuman &&
                gameState.phase == GamePhase.playing &&
                !gameProvider.isProcessing) {
              gameProvider.gameState;
            }
          });

          // Sur le web, afficher une overlay si l'écran est en portrait
          final size = MediaQuery.of(context).size;
          final isPortrait = size.height > size.width;
          
          if (kIsWeb && isPortrait) {
            return _buildRotateScreenOverlay();
          }

          return Stack(
            children: [
              _buildGameTable(context, gameProvider, gameState),
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
                    child: Text("Manche ${gameState.tournamentRound}",
                        style: const TextStyle(
                            color: Colors.amber, fontWeight: FontWeight.bold)),
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
                          strokeWidth: 2, color: Colors.white54)),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGameTable(BuildContext context, GameProvider gp, GameState gs) {
    Player human = gs.players.firstWhere((p) => p.isHuman);
    List<Player> bots = gs.players.where((p) => !p.isHuman).toList();

    bool isMyTurn =
        gs.currentPlayer.id == human.id && gs.phase == GamePhase.playing;
    bool hasDrawn = gs.drawnCard != null;

    bool canInteractWithCards = isMyTurn || gs.phase == GamePhase.reaction;
    
    // Détecter si on est sur un petit écran (mobile web en paysage)
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompactMode = kIsWeb && screenHeight < 400;

    return Stack(
      children: [
        Center(
          child: _buildCenterTable(gs, gp, isMyTurn, hasDrawn, isCompactMode),
        ),
        if (bots.isNotEmpty)
          Positioned(
            left: isCompactMode ? 10 : 40,
            top: 0,
            bottom: 0,
            child: Center(
                child: RotatedBox(
                    quarterTurns: 1,
                    child: _buildBotArea(context, bots[0], gp, isCompactMode))),
          ),
        if (bots.length > 1)
          Positioned(
            top: isCompactMode ? 5 : 20,
            left: 0,
            right: 0,
            child: Center(
                child: RotatedBox(
                    quarterTurns: 2,
                    child: _buildBotArea(context, bots[1], gp, isCompactMode))),
          ),
        if (bots.length > 2)
          Positioned(
            right: isCompactMode ? 10 : 40,
            top: 0,
            bottom: 0,
            child: Center(
                child: RotatedBox(
                    quarterTurns: 3,
                    child: _buildBotArea(context, bots[2], gp, isCompactMode))),
          ),
        Positioned(
          bottom: isCompactMode ? 2 : 10,
          left: 0,
          right: 0,
          child: _buildPlayerArea(gp, gs, human, isMyTurn, hasDrawn, canInteractWithCards, isCompactMode),
        ),
        Positioned(
          top: isCompactMode ? 5 : 20,
          right: isCompactMode ? 5 : 20,
          child: IconButton(
            icon: Icon(Icons.pause_circle_filled,
                color: Colors.white54, size: isCompactMode ? 24 : 32),
            onPressed: () async {
              final shouldQuit = await _showQuitConfirmation();
              if (shouldQuit == true && mounted) {
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                      builder: (context) => const MainMenuScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ),
      ],
    );
  }
  
  Widget _buildPlayerArea(GameProvider gp, GameState gs, Player human, bool isMyTurn, bool hasDrawn, bool canInteractWithCards, bool isCompactMode) {
    if (isCompactMode) {
      // Layout compact pour mobile web
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Bouton gauche
          if (isMyTurn)
            SizedBox(
              width: 60,
              height: 36,
              child: hasDrawn
                  ? _buildCompactActionButton(
                      icon: Icons.delete,
                      label: "JETER",
                      color: Colors.redAccent,
                      onTap: gp.discardDrawnCard)
                  : _buildCompactActionButton(
                      icon: Icons.get_app,
                      label: "PIOCHER",
                      color: Colors.green,
                      onTap: gp.drawCard),
            ),
          if (!isMyTurn) const SizedBox(width: 60),
          const SizedBox(width: 8),
          // Carte piochée (si applicable)
          if (isMyTurn && hasDrawn && gs.drawnCard != null)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber, width: 1)),
              child: CardWidget(
                  card: gs.drawnCard,
                  size: CardSize.tiny,
                  isRevealed: true),
            ),
          if (isMyTurn && hasDrawn) const SizedBox(width: 8),
          // Main du joueur
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayerAvatar(
                  player: human,
                  size: 20,
                  isActive: isMyTurn,
                  showName: false),
              const SizedBox(height: 2),
              PlayerHandWidget(
                player: human,
                isHuman: true,
                isActive: canInteractWithCards,
                onCardTap: (index) => _handleCardTap(gp, gs, index),
                selectedIndices: gp.shakingCardIndices.toList(),
                cardSize: CardSize.small,
              ),
            ],
          ),
          const SizedBox(width: 8),
          // Bouton droit
          if (isMyTurn && !hasDrawn)
            SizedBox(
              width: 60,
              height: 36,
              child: _buildCompactActionButton(
                  icon: Icons.campaign,
                  label: "DUTCH",
                  color: Colors.amber.shade700,
                  onTap: () => _confirmDutch(gp)),
            ),
          if (isMyTurn && hasDrawn)
            Container(
              width: 60,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.blueAccent)),
              child: const Text("GARDER",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold)),
            ),
          if (!isMyTurn) const SizedBox(width: 60),
        ],
      );
    }
    
    // Layout normal
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isMyTurn && hasDrawn && gs.drawnCard != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber)),
              child: Column(
                children: [
                  const Text("CARTE PIOCHÉE",
                      style: TextStyle(
                          color: Colors.amber,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  CardWidget(
                      card: gs.drawnCard,
                      size: CardSize.small,
                      isRevealed: true),
                ],
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 90,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isMyTurn)
                    Container(
                      height: 50,
                      margin: const EdgeInsets.only(bottom: 10),
                      child: hasDrawn
                          ? _buildActionButton(
                              icon: Icons.delete,
                              label: "JETER",
                              color: Colors.redAccent,
                              onTap: gp.discardDrawnCard)
                          : _buildActionButton(
                              icon: Icons.get_app,
                              label: "PIOCHER",
                              color: Colors.green,
                              onTap: gp.drawCard),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 15),
            Column(
              children: [
                PlayerAvatar(
                    player: human,
                    size: 30,
                    isActive: isMyTurn,
                    showName: false),
                const SizedBox(height: 5),
                PlayerHandWidget(
                  player: human,
                  isHuman: true,
                  isActive: canInteractWithCards,
                  onCardTap: (index) => _handleCardTap(gp, gs, index),
                  selectedIndices: gp.shakingCardIndices.toList(),
                  cardSize: CardSize.medium,
                ),
              ],
            ),
            const SizedBox(width: 15),
            SizedBox(
              width: 90,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isMyTurn && !hasDrawn)
                    Container(
                      height: 50,
                      margin: const EdgeInsets.only(bottom: 10),
                      child: _buildActionButton(
                          icon: Icons.campaign,
                          label: "DUTCH",
                          color: Colors.amber.shade700,
                          onTap: () => _confirmDutch(gp)),
                    ),
                  if (isMyTurn && hasDrawn)
                    Container(
                      height: 50,
                      margin: const EdgeInsets.only(bottom: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blueAccent)),
                      child: const Text("GARDER\n(Clique main)",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCenterTable(
      GameState gs, GameProvider gp, bool isMyTurn, bool hasDrawn, bool isCompactMode) {
    bool isReaction = gs.phase == GamePhase.reaction;
    String topCardValue = gs.topDiscardCard?.displayName ?? "?";
    
    final cardSize = isCompactMode ? CardSize.small : CardSize.medium;
    final padding = isCompactMode ? 8.0 : 15.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isReaction) ...[
          Text("Vite ! Avez-vous un$topCardValue ?",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: isCompactMode ? 12 : 16,
                  fontWeight: FontWeight.bold,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 5)])),
          SizedBox(height: isCompactMode ? 2 : 5),
          SizedBox(
            width: isCompactMode ? 100 : 150,
            height: isCompactMode ? 5 : 8,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 1.0, end: 0.0),
              duration: const Duration(milliseconds: 2000),
              builder: (context, value, child) {
                return LinearProgressIndicator(
                  value: value,
                  backgroundColor: Colors.black26,
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(4),
                );
              },
            ),
          ),
          SizedBox(height: isCompactMode ? 4 : 10),
        ],
        Container(
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(isCompactMode ? 12 : 20),
            border: Border.all(color: Colors.white10, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: (isMyTurn && !hasDrawn) ? 1.0 : 0.6,
                child: CardWidget(
                    card: null, size: cardSize, isRevealed: false),
              ),
              SizedBox(width: isCompactMode ? 10 : 20),
              GestureDetector(
                onTap: () => _showDiscardPile(gs),
                child: CardWidget(
                    card: gs.topDiscardCard,
                    size: cardSize,
                    isRevealed: true),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBotArea(BuildContext context, Player bot, GameProvider gp, bool isCompactMode) {
    final avatarSize = isCompactMode ? 20.0 : 30.0;
    final cardHeight = isCompactMode ? 25.0 : 40.0;
    final cardWidth = isCompactMode ? 50.0 : 80.0;
    final cardSpacing = isCompactMode ? 10.0 : 15.0;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerAvatar(
          player: bot,
          size: avatarSize,
          isActive: gp.gameState!.currentPlayer.id == bot.id,
          showName: false,
        ),
        SizedBox(height: isCompactMode ? 2 : 4),
        SizedBox(
          height: cardHeight,
          width: cardWidth,
          child: Stack(
            children: List.generate(bot.hand.length, (index) {
              return Positioned(
                left: index * cardSpacing,
                child: CardWidget(
                    card: null, size: isCompactMode ? CardSize.tiny : CardSize.small, isRevealed: false),
              );
            }),
          ),
        )
      ],
    );
  }

  Widget _buildActionButton(
      {required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap}) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 3,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
        ],
      ),
    );
  }
  
  Widget _buildCompactActionButton(
      {required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap}) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        elevation: 2,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 2),
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 8)),
        ],
      ),
    );
  }

  void _handleCardTap(GameProvider gp, GameState gs, int index) {
    if (gs.phase == GamePhase.reaction) {
      final humanPlayer = gs.players.firstWhere((p) => p.isHuman);
      gp.attemptMatch(index, forcedPlayer: humanPlayer);
    } else if (gs.phase == GamePhase.playing && gs.currentPlayer.isHuman) {
      if (gs.drawnCard != null) {
        gp.replaceCard(index);
      }
    }
  }

  Widget _buildSpecialPowerOverlay(GameProvider gp, GameState gs) {
    if (gs.specialCardToActivate == null) return const SizedBox();
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ModalRoute.of(context)?.isCurrent == true &&
          gs.isWaitingForSpecialPower) {
        PlayingCard trigger = gs.specialCardToActivate!;
        String val = trigger.value;

        if (val == '7') {
          SpecialPowerDialogs.showLookCardDialog(context, trigger, true);
        } else if (val == '10') {
          SpecialPowerDialogs.showLookCardDialog(context, trigger, false);
        } else if (val == 'V') {
          SpecialPowerDialogs.showValetSwapDialog(context, trigger);
        } else if (val == 'JOKER') {
          SpecialPowerDialogs.showJokerDialog(context, trigger);
        } else {
          gp.skipSpecialPower();
        }
      }
    });

    return Container(color: Colors.black54);
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

  void _confirmDutch(GameProvider gp) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1a3a28),
                title: const Text('Crier DUTCH ?',
                    style: TextStyle(color: Colors.white)),
                content: const Text('Êtes-vous sûr ?',
                    style: TextStyle(color: Colors.white70)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Non',
                          style: TextStyle(color: Colors.white54))),
                  TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        gp.callDutch();
                      },
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent),
                      child: const Text('DUTCH !'))
                ]));
  }

  void _showDiscardPile(GameState gs) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1a3a28),
            title:
                const Text('Défausse', style: TextStyle(color: Colors.white)),
            content: SizedBox(
                width: 300,
                height: 300,
                child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: gs.discardPile.reversed
                        .map((c) => Padding(
                            padding: const EdgeInsets.all(4),
                            child: CardWidget(
                                card: c,
                                size: CardSize.medium,
                                isRevealed: true)))
                        .toList()))));
  }

  Future<bool?> _showQuitConfirmation() {
    return showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1a3a28),
                title: const Text("Quitter ?",
                    style: TextStyle(color: Colors.white)),
                content: const Text(
                    "Quitter la partie ? (Les données ne seront pas sauvegardées)",
                    style: TextStyle(color: Colors.white70)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text("Non",
                          style: TextStyle(color: Colors.white))),
                  TextButton(
                      onPressed: () {
                        final gp =
                            Provider.of<GameProvider>(context, listen: false);
                        gp.quitGame();
                        Navigator.pop(ctx, true);
                      },
                      child: const Text("Oui",
                          style: TextStyle(color: Colors.redAccent))),
                ]));
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
                  angle: value * 1.57, // 90 degrés
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
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '(ou agrandissez la fenêtre)',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
