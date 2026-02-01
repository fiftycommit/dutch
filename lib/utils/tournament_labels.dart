const int kTournamentTotalRounds = 3;

String tournamentStageLabel(int round, {int totalRounds = kTournamentTotalRounds}) {
  int safeTotalRounds = totalRounds < 1 ? 1 : totalRounds;
  int safeRound = round;
  if (safeRound < 1) safeRound = 1;
  if (safeRound > safeTotalRounds) safeRound = safeTotalRounds;

  final remaining = safeTotalRounds - safeRound;
  final denominator = 1 << remaining;

  if (denominator <= 1) return "Finale";
  if (denominator == 2) return "1/2 finale";
  return "1/$denominator de finale";
}
