import 'package:flutter/material.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../utils/screen_utils.dart';
import 'game_action_button.dart';

class GameControls extends StatelessWidget {
  final GameState gameState;
  final Player currentPlayer;
  final VoidCallback onDrawCard;
  final VoidCallback onDiscardDrawn;
  final VoidCallback onCallDutch;
  final VoidCallback onSkipSpecialPower;
  final bool compact;

  const GameControls({
    super.key,
    required this.gameState,
    required this.currentPlayer,
    required this.onDrawCard,
    required this.onDiscardDrawn,
    required this.onCallDutch,
    required this.onSkipSpecialPower,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isMyTurn = gameState.currentPlayer.id == currentPlayer.id &&
        gameState.phase == GamePhase.playing;
    final hasDrawn = gameState.drawnCard != null;
    final isSpecial = gameState.isWaitingForSpecialPower &&
        gameState.currentPlayer.id == currentPlayer.id;
    final gap = ScreenUtils.spacing(context, compact ? 8 : 12);

    if (isSpecial) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Pouvoir spécial",
            style: TextStyle(
              color: Colors.white70,
              fontSize: ScreenUtils.scaleFont(context, compact ? 11 : 13),
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ScreenUtils.spacing(context, compact ? 6 : 8)),
          SizedBox(
            height: compact ? 36 : 44,
            child: GameActionButton(
              label: "PASSER",
              color: Colors.blueGrey,
              onTap: onSkipSpecialPower,
              compact: compact,
            ),
          ),
        ],
      );
    }

    if (!isMyTurn) {
      return const SizedBox.shrink();
    }

    final canCallDutch = gameState.dutchCallerId == null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: SizedBox(
            height: compact ? 36 : 46,
            child: GameActionButton(
              label: hasDrawn ? "JETER" : "PIOCHER",
              color: hasDrawn ? Colors.redAccent : Colors.green,
              onTap: hasDrawn ? onDiscardDrawn : onDrawCard,
              compact: compact,
              withPulse: true,
            ),
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          child: SizedBox(
            height: compact ? 36 : 46,
            child: hasDrawn
                ? Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(compact ? 6 : 10),
                      border: Border.all(color: Colors.blueAccent),
                    ),
                    child: Text(
                      "GARDER\n(Clique main)",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 9 : 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : GameActionButton(
                    label: "DUTCH",
                    color: Colors.amber.shade700,
                    onTap: onCallDutch,
                    compact: compact,
                    withPulse: true,
                    enabled: canCallDutch,
                  ),
          ),
        ),
      ],
    );
  }
}
