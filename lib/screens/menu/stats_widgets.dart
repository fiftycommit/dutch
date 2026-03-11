import 'package:flutter/material.dart';
import '../../utils/ui_constants.dart';
import 'stats_models.dart';
import 'stats_helpers.dart';

/// Carte de statistique individuelle (parties, victoires, winrate, etc.)
class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          Text(title,
              style: const TextStyle(color: AppColors.textDisabled, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Grille de résumé (6 cartes stat)
class SummaryCards extends StatelessWidget {
  final Map<String, dynamic> stats;

  const SummaryCards({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    int played = stats['gamesPlayed'] ?? 0;
    int won = stats['gamesWon'] ?? 0;
    int best = stats['bestScore'] ?? 999;
    if (best == 999 && stats['bestScore'] == null) best = 0;
    int winStreak = stats['winStreak'] ?? 0;
    int bestWinStreak = stats['bestWinStreak'] ?? 0;
    double winRate = played > 0 ? (won / played * 100) : 0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: StatCard(
                    title: "Parties",
                    value: "$played",
                    icon: Icons.sports_esports,
                    color: Colors.blue)),
            const SizedBox(width: 10),
            Expanded(
                child: StatCard(
                    title: "Victoires",
                    value: "$won",
                    icon: Icons.emoji_events,
                    color: Colors.amber)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: StatCard(
                    title: "Win Rate",
                    value: "${winRate.toStringAsFixed(1)}%",
                    icon: Icons.pie_chart,
                    color: Colors.green)),
            const SizedBox(width: 10),
            Expanded(
                child: StatCard(
                    title: "Meilleur Score",
                    value: "$best",
                    icon: Icons.star,
                    color: Colors.purple)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: StatCard(
                    title: "Série",
                    value: "$winStreak",
                    icon: Icons.local_fire_department,
                    color: Colors.deepOrange)),
            const SizedBox(width: 10),
            Expanded(
                child: StatCard(
                    title: "Record Série",
                    value: "$bestWinStreak",
                    icon: Icons.whatshot,
                    color: Colors.orange)),
          ],
        ),
      ],
    );
  }
}

/// Efficacité Dutch
class DutchEfficiencyCard extends StatelessWidget {
  final Map<String, dynamic> stats;

  const DutchEfficiencyCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    int calls = stats['dutchCalls'] ?? 0;
    int wins = stats['dutchWins'] ?? 0;
    double successRate = calls > 0 ? (wins / calls * 100) : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white10, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          const Text("Efficacité DUTCH",
              style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          Text("${successRate.toStringAsFixed(1)}%",
              style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 32,
                  fontWeight: FontWeight.bold)),
          Text("$wins réussis sur $calls tentés",
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Winrate par nombre de joueurs
class WinrateByPlayersCard extends StatelessWidget {
  final Map<String, dynamic> stats;

  const WinrateByPlayersCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final rawHistory = stats['history'] ?? [];
    final history = rawHistory is List ? rawHistory : <dynamic>[];
    final buckets = <int, WinrateBucket>{
      2: WinrateBucket(),
      3: WinrateBucket(),
      4: WinrateBucket(),
      5: WinrateBucket(),
      6: WinrateBucket(),
    };

    for (final match in history) {
      if (match is! Map) continue;
      final totalPlayersRaw = match['totalPlayers'];
      if (totalPlayersRaw is! num) continue;
      final totalPlayers = totalPlayersRaw.toInt();
      final bucket = buckets[totalPlayers];
      if (bucket == null) continue;
      bucket.played += 1;
      final rank = match['rank'];
      if (rank == 1) {
        bucket.won += 1;
      }
    }

    final hasData = buckets.values.any((bucket) => bucket.played > 0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white10, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Winrate par nombre de joueurs",
              style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          if (!hasData)
            const Text("Pas encore assez de données",
                style: TextStyle(color: Colors.white38, fontSize: 12))
          else
            ...buckets.entries.map((entry) {
              final count = entry.key;
              final bucket = entry.value;
              if (bucket.played == 0) {
                return const SizedBox.shrink();
              }
              final rate = bucket.winRate;
              final rateLabel = "${(rate * 100).toStringAsFixed(1)}%";
              final recordLabel = "${bucket.won}/${bucket.played}";
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("$count joueurs",
                            style:
                                const TextStyle(color: Colors.white70)),
                        Text("$rateLabel · $recordLabel",
                            style:
                                const TextStyle(color: Colors.white54)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: rate,
                      minHeight: 6,
                      backgroundColor: Colors.white12,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.green),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// Tuile d'historique pour une partie rapide
class MatchHistoryTile extends StatelessWidget {
  final Map<String, dynamic> match;
  final VoidCallback? onTap;
  final String? subtitleOverride;

  const MatchHistoryTile({
    super.key,
    required this.match,
    this.onTap,
    this.subtitleOverride,
  });

  @override
  Widget build(BuildContext context) {
    final rank = match['rank'] ?? 4;
    final outcome = StatsHelpers.outcomeForRank(rank);
    final score = match['score'] ?? 0;
    final mmrChange = match['mmrChange'] ?? 0;
    final streakBonus = match['streakBonus'] ?? 0;
    final streakMultiplierRaw = match['streakMultiplier'] ?? 1.0;
    final streakMultiplier =
        streakMultiplierRaw is num ? streakMultiplierRaw.toDouble() : 1.0;
    final date = StatsHelpers.parseDate(match);
    final dateStr = subtitleOverride ?? StatsHelpers.formatDate(date);
    final rpDisplay = StatsHelpers.rpDisplay(mmrChange);
    final isWin = rank == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
          color: isWin
              ? Colors.green.withValues(alpha: 0.2)
              : Colors.red.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isWin
                  ? Colors.green.withValues(alpha: 0.5)
                  : Colors.red.withValues(alpha: 0.5))),
      child: ListTile(
        onTap: onTap,
        leading: Icon(outcome.icon, color: outcome.color),
        title: Row(
          children: [
            Text(outcome.label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: outcome.color.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                "#$rank",
                style: TextStyle(
                  color: outcome.color,
                  fontSize: AppFontSizes.small,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(dateStr,
            style: const TextStyle(color: AppColors.textDisabled, fontSize: 12)),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (match['scoreDetail'] != null)
              Tooltip(
                message: match['scoreDetail'] as String,
                triggerMode: TooltipTriggerMode.tap,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.red, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      "$score pts",
                      style: TextStyle(
                        color: Colors.red.shade300,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                "$score pts",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
              ),
            Text(
              rpDisplay.text,
              style: TextStyle(
                color: rpDisplay.color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
            ),
            if (streakBonus > 0 && streakMultiplier > 1.0)
              Text(
                "Combo x${streakMultiplier.toStringAsFixed(1)} (+$streakBonus RP)",
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: AppFontSizes.small,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

/// Tuile d'historique pour un tournoi
class TournamentHistoryTile extends StatelessWidget {
  final HistoryGroup group;
  final VoidCallback? onTap;

  const TournamentHistoryTile({
    super.key,
    required this.group,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final finalPosition = StatsHelpers.tournamentFinalPosition(group.matches);
    final outcome = StatsHelpers.outcomeForRank(finalPosition == 0 ? 4 : finalPosition);
    final dateStr = StatsHelpers.formatDate(group.date);
    final roundsLabel = "${group.matches.length} manches";
    final subtitle = "$dateStr • $roundsLabel";
    final isWin = finalPosition == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
          color: isWin
              ? Colors.green.withValues(alpha: 0.2)
              : Colors.red.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isWin
                  ? Colors.green.withValues(alpha: 0.5)
                  : Colors.red.withValues(alpha: 0.5))),
      child: ListTile(
        onTap: onTap,
        leading: Icon(outcome.icon, color: outcome.color),
        title: Row(
          children: [
            const Text("Tournoi",
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: outcome.color.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                "#$finalPosition",
                style: TextStyle(
                  color: outcome.color,
                  fontSize: AppFontSizes.small,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textDisabled)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textDisabled),
      ),
    );
  }
}
