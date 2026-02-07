import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/ui/stats_service.dart';
import '../../widgets/dialogs/responsive_dialog.dart';
import '../../utils/tournament_labels.dart';
import '../../utils/ui_constants.dart';
import 'stats_models.dart';
import 'stats_helpers.dart';
import 'stats_widgets.dart';

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
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.go('/'),
          ),
          bottom: const TabBar(
            indicatorColor: Colors.amber,
            labelColor: Colors.amber,
            unselectedLabelColor: AppColors.textDisabled,
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
              colors: [AppColors.backgroundMedium, AppColors.backgroundDark],
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
            SummaryCards(stats: stats),
            const SizedBox(height: 20),
            DutchEfficiencyCard(stats: stats),
            const SizedBox(height: 20),
            WinrateByPlayersCard(stats: stats),
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

  Widget _buildHistoryList(List<dynamic> history) {
    if (history.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(20),
              child: Text("Aucune partie jouée",
                  style: TextStyle(color: Colors.white38))));
    }

    final groups = StatsHelpers.groupHistory(history);
    return Column(
      children: groups.map((group) {
        if (group.isTournament) {
          return TournamentHistoryTile(
            group: group,
            onTap: () => _showTournamentDetails(group),
          );
        }
        return MatchHistoryTile(
          match: group.matches.first,
          onTap: () => _showMatchHistory(group.matches.first),
        );
      }).toList(),
    );
  }

  void _showTournamentDetails(HistoryGroup group) {
    final matches = List<Map<String, dynamic>>.from(group.matches);
    matches.sort((a, b) =>
        (a['tournamentRound'] ?? 1).compareTo(b['tournamentRound'] ?? 1));
    final totalRounds = StatsHelpers.tournamentTotalRounds(matches);

    final finalPosition = StatsHelpers.tournamentFinalPosition(matches);
    final title =
        finalPosition > 0 ? "Tournoi • Classement #$finalPosition" : "Tournoi";

    showDialog(
      context: context,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: AppColors.backgroundMedium,
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
                    final round = StatsHelpers.roundValue(match['tournamentRound'], index + 1);
                    final dateStr = StatsHelpers.formatDate(StatsHelpers.parseDate(match));
                    final subtitle =
                        "${tournamentStageLabel(round, totalRounds: totalRounds)} • $dateStr";
                    return MatchHistoryTile(
                      match: match,
                      subtitleOverride: subtitle,
                      onTap: () => _showMatchHistory(match, round: round, totalRounds: totalRounds),
                    );
                  },
                ),
              ),
              SizedBox(height: metrics.space(8)),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Fermer",
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showMatchHistory(
    Map<String, dynamic> match, {
    int? round,
    int? totalRounds,
  }) {
    final actionsRaw = match['actionHistory'];
    final actions = actionsRaw is List
        ? actionsRaw.map((e) => e.toString()).toList()
        : <String>[];
    final orderedActions = actions.reversed.toList();
    final title = round == null
        ? "Historique de la partie"
        : "Historique • ${tournamentStageLabel(round, totalRounds: totalRounds ?? kTournamentTotalRounds)}";

    showDialog(
      context: context,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: AppColors.backgroundMedium,
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
                          style: TextStyle(color: AppColors.textDisabled),
                        ),
                      )
                    : ListView.separated(
                        itemCount: orderedActions.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: Colors.white12),
                        itemBuilder: (context, index) {
                          return Text(
                            orderedActions[index],
                            style: const TextStyle(color: AppColors.textSecondary),
                          );
                        },
                      ),
              ),
              SizedBox(height: metrics.space(8)),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Fermer",
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmReset(BuildContext context, int slotId) {
    showDialog(
      context: context,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: AppColors.backgroundMedium,
        builder: (context, metrics) {
          final titleSize = metrics.font(18);
          final bodySize = metrics.font(14);
          final gap = metrics.space(12);
          final buttonSize = metrics.font(16);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icône d'avertissement
              Icon(Icons.warning_amber_rounded, 
                   color: Colors.orange, 
                   size: metrics.font(48)),
              SizedBox(height: gap),
              Text("⚠️ Réinitialiser Profil $slotId ?",
                  style: TextStyle(color: Colors.white, fontSize: titleSize, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              SizedBox(height: gap),
              Container(
                padding: EdgeInsets.all(metrics.space(12)),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withAlpha(100)),
                ),
                child: Column(
                  children: [
                    Text("Cette action est irréversible !",
                        style: TextStyle(color: Colors.red.shade300, fontSize: bodySize, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center),
                    SizedBox(height: gap / 2),
                    Text("Tout l'historique de ce profil sera définitivement effacé :",
                        style: TextStyle(color: AppColors.textSecondary, fontSize: bodySize),
                        textAlign: TextAlign.center),
                    SizedBox(height: gap / 2),
                    Text("• Statistiques de parties\n• Points de classement (RP)\n• Historique des tournois",
                        style: TextStyle(color: AppColors.textSecondary, fontSize: bodySize - 1),
                        textAlign: TextAlign.left),
                  ],
                ),
              ),
              SizedBox(height: gap * 1.5),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: AppColors.textDisabled),
                        padding: EdgeInsets.symmetric(vertical: metrics.space(12)),
                      ),
                      child: Text("Annuler", style: TextStyle(fontSize: buttonSize)),
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        // Deuxième confirmation
                        _showFinalConfirmation(context, slotId);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: metrics.space(12)),
                      ),
                      child: Text("Effacer", style: TextStyle(fontSize: buttonSize)),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  void _showFinalConfirmation(BuildContext context, int slotId) {
    showDialog(
      context: context,
      builder: (ctx) => ResponsiveDialog(
        backgroundColor: const Color(0xFF2d1a1a),
        builder: (context, metrics) {
          final titleSize = metrics.font(18);
          final bodySize = metrics.font(14);
          final gap = metrics.space(12);
          final buttonSize = metrics.font(16);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_forever, color: Colors.red, size: metrics.font(48)),
              SizedBox(height: gap),
              Text("Dernière chance !",
                  style: TextStyle(color: Colors.red.shade300, fontSize: titleSize, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              SizedBox(height: gap),
              Text("Appuyez sur \"Confirmer la suppression\" pour effacer définitivement le Profil $slotId.",
                  style: TextStyle(color: AppColors.textSecondary, fontSize: bodySize),
                  textAlign: TextAlign.center),
              SizedBox(height: gap * 1.5),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: AppColors.textDisabled),
                        padding: EdgeInsets.symmetric(vertical: metrics.space(12)),
                      ),
                      child: Text("Annuler", style: TextStyle(fontSize: buttonSize)),
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await StatsService.resetStats(slotId: slotId);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Profil $slotId réinitialisé'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          setState(() {});
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: metrics.space(12)),
                      ),
                      child: Text("Confirmer", style: TextStyle(fontSize: buttonSize)),
                    ),
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
