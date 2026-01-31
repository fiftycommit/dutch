import '../../models/game_state.dart';
import '../../models/player.dart';
import '../../screens/shared/unified_results_screen.dart' as shared;
import 'rp_calculator.dart';

class RPResultHelper {
  static shared.PlayerRPResult? build({
    required GameState gameState,
    required Player player,
    required int rank,
    required int? currentMMR,
    int winStreak = 0,
    RPResult? overrideResult,
  }) {
    if (currentMMR == null || player.isSpectator) return null;

    final totalPlayers =
        gameState.players.where((p) => !p.isSpectator).length;
    final calledDutch = gameState.dutchCallerId == player.id;
    final isWinner = rank == 1;
    final isEliminated = calledDutch && !isWinner;
    final hasEmptyHand = player.hand.isEmpty;
    final isTournament = gameState.gameMode == GameMode.tournament;
    final tournamentRound = isTournament ? gameState.tournamentRound : 1;

    final rpResult = overrideResult ??
        RPCalculator.calculateRP(
          playerRank: rank,
          currentMMR: currentMMR,
          calledDutch: calledDutch,
          hasEmptyHand: hasEmptyHand,
          isEliminated: isEliminated,
          totalPlayers: totalPlayers,
          isTournament: isTournament,
          tournamentRound: tournamentRound,
          winStreak: winStreak,
        );

    final streakText = rpResult.streakBonus > 0
        ? 'Combo x${rpResult.streakMultiplier.toStringAsFixed(1)}'
        : null;

    return shared.PlayerRPResult(
      rpChange: rpResult.totalChange,
      streakText: streakText,
    );
  }
}
