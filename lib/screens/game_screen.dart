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

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    debugPrint("🎮 [GameScreen] INIT");
    
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint("🎮 [GameScreen] PostFrameCallback");
      _checkAndNavigateIfEnded();
      _checkAndStartBotTurn();
    });
  }

  @override
  void dispose() {
    debugPrint("🎮 [GameScreen] DISPOSE");
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  void _checkAndNavigateIfEnded() {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    if (gameProvider.gameState != null && gameProvider.gameState!.phase == GamePhase.ended) {
      debugPrint("🏁 [GameScreen] Partie terminée");
      
      if (ModalRoute.of(context)?.isCurrent == true && mounted) {
        // ✅ Si Dutch a été appelé, passer par DutchRevealScreen
        if (gameProvider.gameState!.dutchCallerId != null) {
          debugPrint("   📢 Dutch détecté -> Navigation vers DutchRevealScreen");
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const DutchRevealScreen()),
          );
        } else {
          // ✅ Sinon, aller directement aux résultats
          debugPrint("   📊 Pas de Dutch -> Navigation vers ResultsScreen");
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
    
    if (gameState == null) {
      debugPrint("⚠️ [GameScreen] GameState NULL");
      return;
    }
    
    debugPrint("📊 [GameScreen] État du jeu:");
    debugPrint("   - Phase: ${gameState.phase}");
    debugPrint("   - Joueur actuel: ${gameState.currentPlayer.name}");
    debugPrint("   - Est humain: ${gameState.currentPlayer.isHuman}");
    debugPrint("   - isProcessing: ${gameProvider.isProcessing}");
    
    if (!gameState.currentPlayer.isHuman && 
        gameState.phase == GamePhase.playing && 
        !gameProvider.isProcessing) {
      debugPrint("🤖 [GameScreen] Démarrage tour du bot");
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          debugPrint("🤖 [GameScreen] Appel _checkAndPlayBotTurn");
          gameProvider.gameState;
        }
      });
    } else {
      debugPrint("👤 [GameScreen] Tour humain ou phase incorrecte");
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("🎨 [GameScreen] BUILD");
    
    final gameState = context.watch<GameProvider>().gameState;

    if (gameState != null && gameState.phase == GamePhase.ended) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ModalRoute.of(context)?.isCurrent == true && mounted) {
          // ✅ Si Dutch a été appelé, passer par DutchRevealScreen
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
            debugPrint("⚠️ [GameScreen] Pas de partie active");
            return const Center(child: CircularProgressIndicator(color: Colors.amber));
          }

          final gameState = gameProvider.gameState!;
          
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && 
                !gameState.currentPlayer.isHuman && 
                gameState.phase == GamePhase.playing &&
                !gameProvider.isProcessing) {
              debugPrint("🔔 [GameScreen] Build détecté: bot doit jouer");
              gameProvider.gameState;
            }
          });

          return Stack(
            children: [
              _buildGameTable(context, gameProvider, gameState),

              if (gameState.gameMode == GameMode.tournament)
                Positioned(
                  top: 10, left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                    child: Text("Manche ${gameState.tournamentRound}", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                  ),
                ),

              if (gameState.phase == GamePhase.dutchCalled) 
                _buildDutchNotification(gameState),

              if (gameState.isWaitingForSpecialPower && gameState.currentPlayer.isHuman)
                _buildSpecialPowerOverlay(gameProvider, gameState),

              if (gameProvider.isProcessing)
                Positioned(
                  top: 20, right: 60,
                  child: const SizedBox(
                    width: 20, height: 20, 
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)
                  ),
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
    
    bool isMyTurn = gs.currentPlayer.id == human.id && gs.phase == GamePhase.playing;
    bool hasDrawn = gs.drawnCard != null;
    
    // ✅ FIX : Pendant la phase de réaction, tout le monde peut cliquer sur ses cartes
    bool canInteractWithCards = isMyTurn || gs.phase == GamePhase.reaction;

    return Stack(
      children: [
        Center(
          child: _buildCenterTable(gs, gp, isMyTurn, hasDrawn),
        ),
        
        if (bots.isNotEmpty) 
          Positioned(
            left: 40, top: 0, bottom: 0, 
            child: Center(child: RotatedBox(quarterTurns: 1, child: _buildBotArea(context, bots[0], gp))), 
          ),
        if (bots.length > 1) 
          Positioned(
            top: 20, left: 0, right: 0, 
            child: Center(child: RotatedBox(quarterTurns: 2, child: _buildBotArea(context, bots[1], gp))),
          ),
        if (bots.length > 2) 
          Positioned(
            right: 40, top: 0, bottom: 0,
            child: Center(child: RotatedBox(quarterTurns: 3, child: _buildBotArea(context, bots[2], gp))), 
          ),

        Positioned(
          bottom: 10, left: 0, right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isMyTurn && hasDrawn && gs.drawnCard != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber)),
                    child: Column(
                      children: [
                        const Text("CARTE PIOCHÉE", style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        CardWidget(card: gs.drawnCard, size: CardSize.small, isRevealed: true),
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
                                  onTap: gp.discardDrawnCard
                                )
                              : _buildActionButton(
                                  icon: Icons.get_app, 
                                  label: "PIOCHER", 
                                  color: Colors.green, 
                                  onTap: gp.drawCard
                                ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 15),

                  Column(
                    children: [
                      PlayerAvatar(player: human, size: 30, isActive: isMyTurn, showName: false), 
                      const SizedBox(height: 5),
                      PlayerHandWidget(
                        player: human, 
                        isHuman: true, 
                        isActive: canInteractWithCards, // ✅ FIX : Peut cliquer pendant la réaction
                        onCardTap: (index) => _handleCardTap(gp, gs, index),
                        selectedIndices: gp.shakingCardIndices.toList(), // ✅ Animation d'erreur
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
                              onTap: () => _confirmDutch(gp)
                            ),
                          ),
                        
                        if (isMyTurn && hasDrawn)
                          Container(
                            height: 50,
                            margin: const EdgeInsets.only(bottom: 10),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.3), 
                              borderRadius: BorderRadius.circular(10), 
                              border: Border.all(color: Colors.blueAccent)
                            ),
                            child: const Text(
                              "GARDER\n(Clique main)", 
                              textAlign: TextAlign.center, 
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        Positioned(
          top: 20, right: 20,
          child: IconButton(
            icon: const Icon(Icons.pause_circle_filled, color: Colors.white54, size: 32),
            onPressed: () async {
              final shouldQuit = await _showQuitConfirmation();
              if (shouldQuit == true && mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const MainMenuScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCenterTable(GameState gs, GameProvider gp, bool isMyTurn, bool hasDrawn) {
    bool isReaction = gs.phase == GamePhase.reaction;
    //String topCardValue = gs.topDiscardCard?.value ?? "?";
    String topCardValue = gs.topDiscardCard?.displayName ?? "?";
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isReaction) ...[
          Text(
            "Vite ! Avez-vous un$topCardValue ?", 
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 5)])
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: 150, 
            height: 8,
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
          const SizedBox(height: 10),
        ],

        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.2), 
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: (isMyTurn && !hasDrawn) ? 1.0 : 0.6,
                child: const CardWidget(card: null, size: CardSize.medium, isRevealed: false),
              ),
              const SizedBox(width: 20),
              GestureDetector(
                onTap: () => _showDiscardPile(gs),
                child: CardWidget(card: gs.topDiscardCard, size: CardSize.medium, isRevealed: true),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBotArea(BuildContext context, Player bot, GameProvider gp) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerAvatar(
          player: bot, 
          size: 30, 
          isActive: gp.gameState!.currentPlayer.id == bot.id,
          showName: false, 
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 40, 
          width: 80,  
          child: Stack(
            children: List.generate(bot.hand.length, (index) {
              return Positioned(
                left: index * 15.0, 
                child: const CardWidget(
                  card: null, 
                  size: CardSize.small, 
                  isRevealed: false
                ),
              );
            }),
          ),
        )
      ],
    );
  }

  Widget _buildActionButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
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
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
        ],
      ),
    );
  }

  void _handleCardTap(GameProvider gp, GameState gs, int index) {
    debugPrint("🔥🔥🔥 [_handleCardTap] ═══════════════════════════════");
    debugPrint("👆 [_handleCardTap] CLICK DÉTECTÉ !");
    debugPrint("   - Index carte: $index");
    debugPrint("   - Phase actuelle: ${gs.phase}");
    debugPrint("   - Joueur actuel: ${gs.currentPlayer.name}");
    debugPrint("   - isHuman: ${gs.currentPlayer.isHuman}");
    debugPrint("   - Carte du dessus: ${gs.topDiscardCard?.value}");
    
    if (gs.phase == GamePhase.reaction) {
      debugPrint("   ✅ PHASE REACTION confirmée");
      debugPrint("   - Tentative match en phase réaction (JOUEUR HUMAIN)");
      
      final humanPlayer = gs.players.firstWhere((p) => p.isHuman);
      debugPrint("   - Joueur humain trouvé: ${humanPlayer.name}");
      debugPrint("   - Main du joueur: ${humanPlayer.hand.map((c) => c.value).toList()}");
      debugPrint("   - Carte sélectionnée: ${humanPlayer.hand[index].value}");
      
      debugPrint("   🎯 APPEL attemptMatch avec forcedPlayer");
      gp.attemptMatch(index, forcedPlayer: humanPlayer);
      
    } else if (gs.phase == GamePhase.playing && gs.currentPlayer.isHuman) {
      debugPrint("   ℹ️ PHASE PLAYING - Tour du joueur");
      
      if (gs.drawnCard != null) {
        debugPrint("   - Remplacement de carte");
        gp.replaceCard(index);
      } else {
        debugPrint("   - Pas de carte piochée, aucune action");
      }
      
    } else {
      debugPrint("   ❌ AUCUNE ACTION POSSIBLE");
      debugPrint("   - Phase: ${gs.phase}");
      debugPrint("   - Tour du joueur: ${gs.currentPlayer.name}");
      debugPrint("   - Est humain: ${gs.currentPlayer.isHuman}");
    }
    
    debugPrint("🔥🔥🔥 [_handleCardTap] FIN ═══════════════════════════════");
  }

  Widget _buildSpecialPowerOverlay(GameProvider gp, GameState gs) {
    debugPrint("🔍 [_buildSpecialPowerOverlay] ENTREE");
    debugPrint("   - specialCardToActivate: ${gs.specialCardToActivate?.value}");
    debugPrint("   - isWaitingForSpecialPower: ${gs.isWaitingForSpecialPower}");
    debugPrint("   - currentPlayer: ${gs.currentPlayer.name}");
    debugPrint("   - isHuman: ${gs.currentPlayer.isHuman}");
    
    if (gs.specialCardToActivate == null) {
      debugPrint("   ❌ Pas de carte spéciale, retour SizedBox");
      return const SizedBox();
    }

    if (!gs.currentPlayer.isHuman) {
      debugPrint("   ❌ Pas un humain, retour SizedBox");
      return const SizedBox();
    }
    
    debugPrint("   ✅ Affichage du dialogue via PostFrameCallback");
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint("   📢 [PostFrameCallback] EXECUTION");
      debugPrint("      - Route isCurrent: ${ModalRoute.of(context)?.isCurrent}");
      debugPrint("      - isWaitingForSpecialPower: ${gs.isWaitingForSpecialPower}");
      
      if (ModalRoute.of(context)?.isCurrent == true && gs.isWaitingForSpecialPower) {
        PlayingCard trigger = gs.specialCardToActivate!;
        String val = trigger.value;
        
        debugPrint("      ✅ Conditions OK, affichage dialogue pour: $val");
        
        if (val == '7') {
          debugPrint("      🎯 Dialogue carte 7");
          SpecialPowerDialogs.showLookCardDialog(context, trigger, true); 
        } else if (val == '10') {
          debugPrint("      🎯 Dialogue carte 10");
          SpecialPowerDialogs.showLookCardDialog(context, trigger, false); 
        } else if (val == 'V') {
          debugPrint("      🎯 Dialogue Valet");
          SpecialPowerDialogs.showValetSwapDialog(context, trigger);
        } else if (val == 'JOKER') {
          debugPrint("      🎯 Dialogue Joker");
          SpecialPowerDialogs.showJokerDialog(context, trigger);
        } else {
          debugPrint("      ⏭️ Carte sans dialogue, skip direct");
          gp.skipSpecialPower(); 
        }
      } else {
        debugPrint("      ❌ Conditions NON OK, pas de dialogue");
      }
    });
    
    debugPrint("   🖤 Retour Container noir");
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
            Text("${gs.dutchCallerId == null ? 'DUTCH' : 'QUELQU\'UN'} A CRIÉ DUTCH !", textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
  
  void _confirmDutch(GameProvider gp) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1a3a28),
      title: const Text('Crier DUTCH ?', style: TextStyle(color: Colors.white)), 
      content: const Text('Êtes-vous sûr ?', style: TextStyle(color: Colors.white70)), 
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Non', style: TextStyle(color: Colors.white54))), 
        TextButton(
          onPressed: () { 
            Navigator.pop(ctx); 
            gp.callDutch(); 
          }, 
          style: TextButton.styleFrom(foregroundColor: Colors.redAccent), 
          child: const Text('DUTCH !')
        )
      ]
    ));
  }
  
  void _showDiscardPile(GameState gs) { 
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1a3a28),
      title: const Text('Défausse', style: TextStyle(color: Colors.white)), 
      content: SizedBox(width: 300, height: 300, child: ListView(scrollDirection: Axis.horizontal, children: gs.discardPile.reversed.map((c) => Padding(padding: const EdgeInsets.all(4), child: CardWidget(card: c, size: CardSize.medium, isRevealed: true))).toList()))
    )); 
  }
  
  Future<bool?> _showQuitConfirmation() { 
    return showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1a3a28),
      title: const Text("Quitter ?", style: TextStyle(color: Colors.white)), 
      content: const Text("Quitter la partie ? (Les données ne seront pas sauvegardés)", style: TextStyle(color: Colors.white70)), 
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non", style: TextStyle(color: Colors.white))), 
        TextButton(
          onPressed: () {
            // ✅ AJOUTER CES 2 LIGNES :
            final gp = Provider.of<GameProvider>(context, listen: false);
            gp.quitGame(); // Nettoyer le gameState
            
            Navigator.pop(ctx, true);
          }, 
          child: const Text("Oui", style: TextStyle(color: Colors.redAccent))
        )
      ]
    )); 
  }
}