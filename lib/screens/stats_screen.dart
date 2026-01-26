import 'package:flutter/material.dart';
import '../services/stats_service.dart';
import '../widgets/responsive_dialog.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;

    return DefaultTabController(
      length: 3, // 3 Slots
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('Statistiques',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: const TabBar(
            indicatorColor: Colors.amber,
            labelColor: Colors.amber,
            unselectedLabelColor: Colors.white60,
            tabs: [
              Tab(text: "Profil 1"),
              Tab(text: "Profil 2"),
              Tab(text: "Profil 3"),
            ],
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1a3a28), Color(0xFF0d1f15)],
            ),
          ),
          child: TabBarView(
            children: [
              _buildStatsPage(1, topPadding),
              _buildStatsPage(2, topPadding),
              _buildStatsPage(3, topPadding),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsPage(int slotId, double topPadding) {
    return FutureBuilder<Map<String, dynamic>>(
      future: StatsService.getStats(slotId: slotId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.amber));
        }

        if (snapshot.hasError) {
          return Center(
              child: Text("Erreur : ${snapshot.error}",
                  style: const TextStyle(color: Colors.red)));
        }

        final stats = snapshot.data ?? {};

        return ListView(
          padding: EdgeInsets.fromLTRB(16, topPadding + 100, 16, 20),
          children: [
            _buildSummaryCards(stats),
            const SizedBox(height: 20),
            _buildPieChartPlaceholder(stats),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Historique",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.delete_forever,
                      color: Colors.redAccent, size: 20),
                  onPressed: () => _confirmReset(context, slotId),
                  tooltip: "Effacer ce profil",
                )
              ],
            ),
            const SizedBox(height: 10),
            _buildHistoryList(stats['history'] ?? []),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCards(Map<String, dynamic> stats) {
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
                child: _StatCard(
                    title: "Parties",
                    value: "$played",
                    icon: Icons.sports_esports,
                    color: Colors.blue)),
            const SizedBox(width: 10),
            Expanded(
                child: _StatCard(
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
                child: _StatCard(
                    title: "Win Rate",
                    value: "${winRate.toStringAsFixed(1)}%",
                    icon: Icons.pie_chart,
                    color: Colors.green)),
            const SizedBox(width: 10),
            Expanded(
                child: _StatCard(
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
                child: _StatCard(
                    title: "Série",
                    value: "$winStreak",
                    icon: Icons.local_fire_department,
                    color: Colors.deepOrange)),
            const SizedBox(width: 10),
            Expanded(
                child: _StatCard(
                    title: "Record Série",
                    value: "$bestWinStreak",
                    icon: Icons.whatshot,
                    color: Colors.orange)),
          ],
        ),
      ],
    );
  }

  Widget _buildPieChartPlaceholder(Map<String, dynamic> stats) {
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
              style: TextStyle(color: Colors.white70)),
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

  Widget _buildHistoryList(List<dynamic> history) {
    if (history.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(20),
              child: Text("Aucune partie jouée",
                  style: TextStyle(color: Colors.white38))));
    }

    final groups = _groupHistory(history);
    return Column(
      children: groups.map((group) {
        if (group.isTournament) {
          return _buildTournamentHistoryTile(group);
        }
        return _buildMatchHistoryTile(
          group.matches.first,
          onTap: () => _showMatchHistory(group.matches.first),
        );
      }).toList(),
    );
  }

  Widget _buildMatchHistoryTile(Map<String, dynamic> match,
      {VoidCallback? onTap, String? subtitleOverride}) {
    final rank = match['rank'] ?? 4;
    final outcome = _outcomeForRank(rank);
    final score = match['score'] ?? 0;
    final mmrChange = match['mmrChange'] ?? 0;
    final streakBonus = match['streakBonus'] ?? 0;
    final streakMultiplierRaw = match['streakMultiplier'] ?? 1.0;
    final streakMultiplier = streakMultiplierRaw is num
        ? streakMultiplierRaw.toDouble()
        : 1.0;
    final date = _parseDate(match);
    final dateStr = subtitleOverride ?? _formatDate(date);
    final rpDisplay = _rpDisplay(mmrChange);
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
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(dateStr,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text("$score pts",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            Text(
              rpDisplay.text,
              style: TextStyle(
                color: rpDisplay.color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (streakBonus > 0 && streakMultiplier > 1.0)
              Text(
                "Combo x${streakMultiplier.toStringAsFixed(1)} (+$streakBonus RP)",
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTournamentHistoryTile(_HistoryGroup group) {
    final finalPosition = _tournamentFinalPosition(group.matches);
    final outcome = _outcomeForRank(finalPosition == 0 ? 4 : finalPosition);
    final dateStr = _formatDate(group.date);
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
        onTap: () => _showTournamentDetails(group),
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
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle:
            Text(subtitle, style: const TextStyle(color: Colors.white54)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
      ),
    );
  }

  void _showTournamentDetails(_HistoryGroup group) {
    final matches = List<Map<String, dynamic>>.from(group.matches);
    matches.sort((a, b) =>
        (a['tournamentRound'] ?? 1).compareTo(b['tournamentRound'] ?? 1));

    final finalPosition = _tournamentFinalPosition(matches);
    final title = finalPosition > 0
        ? "Tournoi • Classement #$finalPosition"
        : "Tournoi";

    showDialog(
      context: context,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: const Color(0xFF1a3a28),
        builder: (context, metrics) {
          final maxHeight = metrics.contentHeight * 0.7;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: TextStyle(
                      color: Colors.white, fontSize: metrics.font(16)),
                  textAlign: TextAlign.center),
              SizedBox(height: metrics.space(12)),
              SizedBox(
                height: maxHeight,
                child: ListView.builder(
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final match = matches[index];
                    final round = match['tournamentRound'] ?? (index + 1);
                    final dateStr = _formatDate(_parseDate(match));
                    final subtitle = "Manche $round • $dateStr";
                    return _buildMatchHistoryTile(
                      match,
                      subtitleOverride: subtitle,
                      onTap: () => _showMatchHistory(match, round: round),
                    );
                  },
                ),
              ),
              SizedBox(height: metrics.space(8)),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Fermer",
                    style: TextStyle(color: Colors.white70)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showMatchHistory(Map<String, dynamic> match, {int? round}) {
    final actionsRaw = match['actionHistory'];
    final actions = actionsRaw is List
        ? actionsRaw.map((e) => e.toString()).toList()
        : <String>[];
    final orderedActions = actions.reversed.toList();
    final title = round == null
        ? "Historique de la partie"
        : "Historique • Manche $round";

    showDialog(
      context: context,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: const Color(0xFF1a3a28),
        builder: (context, metrics) {
          final maxHeight = metrics.contentHeight * 0.6;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: TextStyle(
                      color: Colors.white, fontSize: metrics.font(16)),
                  textAlign: TextAlign.center),
              SizedBox(height: metrics.space(12)),
              SizedBox(
                height: maxHeight,
                child: orderedActions.isEmpty
                    ? const Center(
                        child: Text(
                          "Aucun historique disponible",
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.separated(
                        itemCount: orderedActions.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: Colors.white12),
                        itemBuilder: (context, index) {
                          return Text(
                            orderedActions[index],
                            style: const TextStyle(color: Colors.white70),
                          );
                        },
                      ),
              ),
              SizedBox(height: metrics.space(8)),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Fermer",
                    style: TextStyle(color: Colors.white70)),
              ),
            ],
          );
        },
      ),
    );
  }

  List<_HistoryGroup> _groupHistory(List<dynamic> history) {
    final matches = history
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final tournamentGroups = <String, List<Map<String, dynamic>>>{};
    final groups = <_HistoryGroup>[];

    for (final match in matches) {
      final isTournament = match['gameMode'] == 'tournament' ||
          match['isTournament'] == true ||
          match['tournamentId'] != null ||
          match['tournamentRound'] != null;
      if (isTournament) {
        final id = (match['tournamentId'] ?? match['date']).toString();
        tournamentGroups.putIfAbsent(id, () => []).add(match);
      } else {
        groups.add(_HistoryGroup(
          isTournament: false,
          tournamentId: null,
          matches: [match],
          date: _parseDate(match),
        ));
      }
    }

    for (final entry in tournamentGroups.entries) {
      final groupMatches = List<Map<String, dynamic>>.from(entry.value);
      groupMatches.sort((a, b) =>
          (a['tournamentRound'] ?? 1).compareTo(b['tournamentRound'] ?? 1));
      final date = groupMatches
          .map(_parseDate)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      groups.add(_HistoryGroup(
        isTournament: true,
        tournamentId: entry.key,
        matches: groupMatches,
        date: date,
      ));
    }

    groups.sort((a, b) => b.date.compareTo(a.date));
    return groups;
  }

  DateTime _parseDate(Map<String, dynamic> match) {
    return DateTime.tryParse(match['date'] ?? "") ?? DateTime.now();
  }

  String _formatDate(DateTime date) {
    return "${date.day}/${date.month} ${date.hour}h${date.minute.toString().padLeft(2, '0')}";
  }

  _OutcomeStyle _outcomeForRank(int rank) {
    switch (rank) {
      case 1:
        return const _OutcomeStyle(
          icon: Icons.emoji_events,
          color: Colors.amber,
          label: "Victoire",
        );
      case 2:
        return const _OutcomeStyle(
          icon: Icons.sentiment_satisfied,
          color: Colors.lightGreenAccent,
          label: "2ème place",
        );
      case 3:
        return const _OutcomeStyle(
          icon: Icons.sentiment_neutral,
          color: Colors.orange,
          label: "3ème place",
        );
      default:
        return const _OutcomeStyle(
          icon: Icons.sentiment_dissatisfied,
          color: Colors.redAccent,
          label: "Défaite",
        );
    }
  }

  _RpDisplay _rpDisplay(int mmrChange) {
    if (mmrChange == 0) {
      return const _RpDisplay(text: "Mode Manuel", color: Colors.white54);
    }
    final text = mmrChange > 0 ? "+$mmrChange RP" : "$mmrChange RP";
    final color =
        mmrChange > 0 ? Colors.greenAccent : Colors.redAccent;
    return _RpDisplay(text: text, color: color);
  }

  int _tournamentFinalPosition(List<Map<String, dynamic>> matches) {
    if (matches.isEmpty) return 0;
    final sorted = List<Map<String, dynamic>>.from(matches)
      ..sort((a, b) =>
          (a['tournamentRound'] ?? 1).compareTo(b['tournamentRound'] ?? 1));
    final maxRoundRaw = sorted.last['tournamentRound'] ?? 1;
    final maxRound =
        maxRoundRaw is num ? maxRoundRaw.toInt() : 1;
    final playerCounts = sorted
        .map((m) => m['totalPlayers'])
        .whereType<num>()
        .map((n) => n.toInt())
        .toList();
    final initialPlayers = playerCounts.isNotEmpty
        ? playerCounts.reduce((a, b) => a > b ? a : b)
        : 4;
    final basePosition = (initialPlayers + 1) - maxRound;
    final lastRankRaw = sorted.last['rank'] ?? 0;
    final lastRank =
        lastRankRaw is num ? lastRankRaw.toInt() : 0;
    final isFinalRound = maxRound >= initialPlayers - 1;
    if (isFinalRound && lastRank == 1) return 1;
    if (isFinalRound && lastRank == 2) return 2;
    if (basePosition < 1) return 1;
    if (basePosition > initialPlayers) return initialPlayers;
    return basePosition;
  }

  void _confirmReset(BuildContext context, int slotId) {
    showDialog(
      context: context,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: const Color(0xFF1a3a28),
        builder: (context, metrics) {
          final titleSize = metrics.font(18);
          final bodySize = metrics.font(14);
          final gap = metrics.space(12);
          final buttonSize = metrics.font(16);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Réinitialiser Profil $slotId ?",
                  style: TextStyle(color: Colors.white, fontSize: titleSize),
                  textAlign: TextAlign.center),
              SizedBox(height: gap),
              Text("Tout l'historique sera effacé.",
                  style: TextStyle(color: Colors.white70, fontSize: bodySize),
                  textAlign: TextAlign.center),
              SizedBox(height: gap),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text("Annuler",
                          style: TextStyle(fontSize: buttonSize))),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await StatsService.resetStats(slotId: slotId);
                      setState(() {});
                    },
                    child: Text("Effacer",
                        style: TextStyle(
                            color: Colors.red, fontSize: buttonSize)),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HistoryGroup {
  final bool isTournament;
  final String? tournamentId;
  final List<Map<String, dynamic>> matches;
  final DateTime date;

  const _HistoryGroup({
    required this.isTournament,
    required this.tournamentId,
    required this.matches,
    required this.date,
  });
}

class _OutcomeStyle {
  final IconData icon;
  final Color color;
  final String label;

  const _OutcomeStyle({
    required this.icon,
    required this.color,
    required this.label,
  });
}

class _RpDisplay {
  final String text;
  final Color color;

  const _RpDisplay({
    required this.text,
    required this.color,
  });
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard(
      {required this.title,
      required this.value,
      required this.icon,
      required this.color});

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
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }
}
