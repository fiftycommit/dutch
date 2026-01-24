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

    return Column(
      children: history.map((match) {
        int rank = match['rank'] ?? 4;
        bool isWin = rank == 1;

        int score = match['score'] ?? 0;
        int mmrChange = match['mmrChange'] ?? 0;

        DateTime date =
            DateTime.tryParse(match['date'] ?? "") ?? DateTime.now();
        String dateStr =
            "${date.day}/${date.month} ${date.hour}h${date.minute.toString().padLeft(2, '0')}";

        IconData icon;
        Color iconColor;
        String resultText;

        switch (rank) {
          case 1:
            icon = Icons.emoji_events;
            iconColor = Colors.amber;
            resultText = "Victoire";
            break;
          case 2:
            icon = Icons.sentiment_satisfied;
            iconColor = Colors.lightGreenAccent;
            resultText = "2ème place";
            break;
          case 3:
            icon = Icons.sentiment_neutral;
            iconColor = Colors.orange;
            resultText = "3ème place";
            break;
          default:
            icon = Icons.sentiment_dissatisfied;
            iconColor = Colors.redAccent;
            resultText = "Défaite";
        }


        String rpText;
        Color rpColor;

        if (mmrChange == 0) {
          // Mode Manuel
          rpText = "Mode Manuel";
          rpColor = Colors.white54;
        } else {
          // Mode SBMM
          rpText = mmrChange > 0 ? "+$mmrChange RP" : "$mmrChange RP";
          rpColor = mmrChange > 0 ? Colors.greenAccent : Colors.redAccent;
        }

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
            leading: Icon(icon, color: iconColor),
            title: Row(
              children: [
                Text(resultText,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "#$rank",
                    style: TextStyle(
                      color: iconColor,
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
                  rpText,
                  style: TextStyle(
                    color: rpColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
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
