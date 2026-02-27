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

    final totalPlayers = gameState.players.where((p) => !p.isSpectator).length;
    final calledDutch = gameState.dutchCallerId == player.id;
    final isWinner = rank == 1;
    final isEliminated = calledDutch && !isWinner;
    // En multi, les cartes adversaires sont hidden (isHidden=true).
    // Une main toute-hidden ne veut PAS dire qu'elle est vide : on ne sait juste pas.
    // On ne considère la main vide que si elle est réellement vide (pas de cartes du tout).
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
