import 'package:flutter/material.dart';
import '../../utils/ui_constants.dart';
import 'stats_models.dart';

/// Logique utilitaire pour l'écran de statistiques.
/// Extraite de StatsScreen pour respecter SRP.
class StatsHelpers {
  static List<HistoryGroup> groupHistory(List<dynamic> history) {
    final matches = history
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final tournamentGroups = <String, List<Map<String, dynamic>>>{};
    final groups = <HistoryGroup>[];

    for (final match in matches) {
      final isTournament = match['gameMode'] == 'tournament' ||
          match['isTournament'] == true ||
          match['tournamentId'] != null ||
          match['tournamentRound'] != null;
      if (isTournament) {
        final id = (match['tournamentId'] ?? match['date']).toString();
        tournamentGroups.putIfAbsent(id, () => []).add(match);
      } else {
        groups.add(HistoryGroup(
          isTournament: false,
          tournamentId: null,
          matches: [match],
          date: parseDate(match),
        ));
      }
    }

    for (final entry in tournamentGroups.entries) {
      final groupMatches = List<Map<String, dynamic>>.from(entry.value);
      groupMatches.sort((a, b) =>
          (a['tournamentRound'] ?? 1).compareTo(b['tournamentRound'] ?? 1));
      final date =
          groupMatches.map(parseDate).reduce((a, b) => a.isAfter(b) ? a : b);
      groups.add(HistoryGroup(
        isTournament: true,
        tournamentId: entry.key,
        matches: groupMatches,
        date: date,
      ));
    }

    groups.sort((a, b) => b.date.compareTo(a.date));
    return groups;
  }

  static DateTime parseDate(Map<String, dynamic> match) {
    return DateTime.tryParse(match['date'] ?? "") ?? DateTime.now();
  }

  static String formatDate(DateTime date) {
    return "${date.day}/${date.month} ${date.hour}h${date.minute.toString().padLeft(2, '0')}";
  }

  static OutcomeStyle outcomeForRank(int rank) {
    switch (rank) {
      case 1:
        return const OutcomeStyle(
          icon: Icons.emoji_events,
          color: Colors.amber,
          label: "Victoire",
        );
      case 2:
        return const OutcomeStyle(
          icon: Icons.sentiment_satisfied,
          color: Colors.lightGreenAccent,
          label: "2ème place",
        );
      case 3:
        return const OutcomeStyle(
          icon: Icons.sentiment_neutral,
          color: Colors.orange,
          label: "3ème place",
        );
      default:
        return const OutcomeStyle(
          icon: Icons.sentiment_dissatisfied,
          color: Colors.redAccent,
          label: "Défaite",
        );
    }
  }

  static RpDisplay rpDisplay(int mmrChange) {
    if (mmrChange == 0) {
      return const RpDisplay(text: "Mode Manuel", color: AppColors.textDisabled);
    }
    final text = mmrChange > 0 ? "+$mmrChange RP" : "$mmrChange RP";
    final color = mmrChange > 0 ? Colors.greenAccent : Colors.redAccent;
    return RpDisplay(text: text, color: color);
  }

  static int tournamentFinalPosition(List<Map<String, dynamic>> matches) {
    if (matches.isEmpty) return 0;
    final sorted = List<Map<String, dynamic>>.from(matches)
      ..sort((a, b) =>
          (a['tournamentRound'] ?? 1).compareTo(b['tournamentRound'] ?? 1));
    final lastRankRaw = sorted.last['rank'] ?? 0;
    final lastRank = lastRankRaw is num ? lastRankRaw.toInt() : 0;
    return lastRank;
  }

  static int tournamentTotalRounds(List<Map<String, dynamic>> matches) {
    if (matches.isEmpty) return 1;
    final playerCounts = matches
        .map((m) => m['totalPlayers'])
        .whereType<num>()
        .map((n) => n.toInt())
        .toList();
    int initialPlayers;
    if (playerCounts.isNotEmpty) {
      initialPlayers = playerCounts.reduce((a, b) => a > b ? a : b);
    } else {
      final maxRound = matches
          .map((m) => roundValue(m['tournamentRound'], 1))
          .reduce((a, b) => a > b ? a : b);
      initialPlayers = maxRound + 1;
    }
    if (initialPlayers < 2) return 1;
    return initialPlayers - 1;
  }

  static int roundValue(dynamic raw, int fallback) {
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? fallback;
    return fallback;
  }
}
