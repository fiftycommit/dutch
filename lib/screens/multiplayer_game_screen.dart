import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/multiplayer_game_provider.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../widgets/player_hand.dart';
import '../widgets/player_avatar.dart';
import '../widgets/center_table.dart';
import '../widgets/game_controls.dart';
import '../widgets/card_widget.dart';
import '../widgets/presence_check_overlay.dart';
import 'multiplayer_results_screen.dart';

class MultiplayerGameScreen extends StatefulWidget {
  const MultiplayerGameScreen({super.key});

  @override
  State<MultiplayerGameScreen> createState() => _MultiplayerGameScreenState();
}

class _MultiplayerGameScreenState extends State<MultiplayerGameScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<MultiplayerGameProvider>(
      builder: (context, provider, _) {
        final gameState = provider.gameState;

        if (gameState == null) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  const Text('Chargement de la partie...'),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      provider.leaveRoom();
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    child: const Text('Quitter'),
                  ),
                ],
              ),
            ),
          );
        }

        // Si la partie est terminée, naviguer vers l'écran de résultats
        if (gameState.phase == GamePhase.ended) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.canPop(context)) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => MultiplayerResultsScreen(
                    gameState: gameState,
                    localPlayerId: provider.playerId,
                  ),
                ),
              );
            }
          });
        }

        // Trouver le joueur humain (celui qui joue sur cet appareil)
        final humanPlayer = gameState.players.firstWhere(
          (p) => p.id == provider.playerId,
          orElse: () => gameState.players.first,
        );

        final size = MediaQuery.of(context).size;
        final isCompactMode = size.height < 600 || size.width < 900;
        final isMyTurn = gameState.currentPlayer.id == humanPlayer.id &&
            gameState.phase == GamePhase.playing;
        final hasDrawn = gameState.drawnCard != null;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final shouldLeave = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Quitter la partie ?'),
                content: const Text(
                  'Êtes-vous sûr de vouloir quitter la partie en cours ?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Rester'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Quitter'),
                  ),
                ],
              ),
            );

            if (shouldLeave == true) {
              provider.leaveRoom();
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            }
          },
          child: Scaffold(
            body: Stack(
              children: [
                // Background gradient
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                        Theme.of(context).colorScheme.secondary.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                ),

                // Game layout
                SafeArea(
                  child: Column(
                    children: [
                      // Header avec infos de la room
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Code de la room
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Room: ${provider.roomCode ?? '---'}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),

                            // Indicateur de tour
                            if (gameState.phase == GamePhase.playing)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: gameState.currentPlayer.id == humanPlayer.id
                                      ? Colors.green.withValues(alpha: 0.8)
                                      : Colors.orange.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  gameState.currentPlayer.id == humanPlayer.id
                                      ? 'Votre tour'
                                      : 'Tour de ${gameState.currentPlayer.name}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Mains des autres joueurs
                      Expanded(
                        flex: 2,
                        child: _buildOpponentHands(gameState, humanPlayer, provider),
                      ),

                      // Table centrale (deck, défausse)
                      CenterTable(
                        gameState: gameState,
                        isMyTurn: isMyTurn,
                        hasDrawn: hasDrawn,
                        isCompactMode: isCompactMode,
                        onDrawCard: provider.drawCard,
                        onTakeFromDiscard: provider.takeFromDiscard,
                        reactionTimeTotalMs: provider.reactionTimeMs,
                      ),

                      // Main du joueur
                      Expanded(
                        flex: 3,
                        child: PlayerHandWidget(
                          player: humanPlayer,
                          isHuman: true,
                          isActive: isMyTurn || gameState.phase == GamePhase.reaction,
                          onCardTap: (index) =>
                              _handleCardTap(provider, gameState, index),
                          cardSize: isCompactMode ? CardSize.small : CardSize.medium,
                        ),
                      ),

                      // Contrôles du jeu
                      GameControls(
                        gameState: gameState,
                        currentPlayer: humanPlayer,
                        onDrawCard: provider.drawCard,
                        onDiscardDrawn: provider.discardDrawnCard,
                        onCallDutch: provider.callDutch,
                        onSkipSpecialPower: provider.skipSpecialPower,
                        compact: isCompactMode,
                      ),
                    ],
                  ),
                ),

                // Timer de réaction
                if (gameState.phase == GamePhase.reaction && gameState.lastSpiedCard != null)
                  Positioned(
                    top: 100,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'MATCH !',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${(gameState.reactionTimeRemaining / 1000).toStringAsFixed(1)}s',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                PresenceCheckOverlay(
                  active: provider.presenceCheckActive,
                  deadlineMs: provider.presenceCheckDeadlineMs,
                  reason: provider.presenceCheckReason,
                  onConfirm: provider.confirmPresence,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOpponentHands(
    GameState gameState,
    Player humanPlayer,
    MultiplayerGameProvider provider,
  ) {
    final opponents = gameState.players.where((p) => p.id != humanPlayer.id).toList();

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: opponents.length,
      itemBuilder: (context, index) {
        final opponent = opponents[index];
        final isCurrentPlayer = gameState.currentPlayer.id == opponent.id;
        final presence = provider.presenceById[opponent.id];
        final isSpectator = presence != null && presence['isSpectator'] == true;

        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isCurrentPlayer
                ? Colors.white.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isCurrentPlayer ? Colors.yellow : Colors.white.withValues(alpha: 0.2),
              width: 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PlayerAvatar(
                    player: opponent,
                    isActive: isCurrentPlayer,
                    compactMode: true,
                    size: 28,
                  ),
                  const SizedBox(width: 6),
                  _presenceDot(presence),
                ],
              ),
              if (isSpectator)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Spectateur',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 5),
              Text(
                '${opponent.hand.length} cartes',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _presenceDot(Map<String, dynamic>? presence) {
    Color color = Colors.grey;
    if (presence != null) {
      final isSpectator = presence['isSpectator'] == true;
      final connected = presence['connected'] == true;
      final focused = presence['focused'] == true;

      if (isSpectator) {
        color = Colors.blueGrey;
      } else if (!connected) {
        color = Colors.red;
      } else if (!focused) {
        color = Colors.orange;
      } else {
        color = Colors.green;
      }
    }

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  void _handleCardTap(MultiplayerGameProvider provider, GameState gameState, int index) {
    // Gestion des clics sur les cartes selon la phase du jeu
    if (gameState.phase == GamePhase.reaction) {
      // Tenter un match
      provider.attemptMatch(index);
    } else if (gameState.phase == GamePhase.playing &&
        gameState.drawnCard != null &&
        gameState.currentPlayer.id == provider.playerId) {
      provider.replaceCard(index);
    } else if (gameState.isWaitingForSpecialPower) {
      // Utiliser un pouvoir spécial
      // (implémentation simplifiée, peut être améliorée)
      if (gameState.pendingSwap != null) {
        provider.completeSwap(index);
      }
    }
  }
}
