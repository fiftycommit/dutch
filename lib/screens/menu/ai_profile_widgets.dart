import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/player_learning_data.dart';
import '../../utils/ui_constants.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════

class MetricDelta {
  final String label;
  final double? before;
  final double? after;
  final bool isPercent;

  const MetricDelta({
    required this.label,
    required this.before,
    required this.after,
    required this.isPercent,
  });

  double? get delta {
    if (before == null || after == null) return null;
    return after! - before!;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CARD WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;

  const InfoCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.psychology, color: Colors.amber),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title: $value',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppColors.textDisabled, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ClientIdCard extends StatelessWidget {
  final String? clientId;

  const ClientIdCard({
    super.key,
    required this.clientId,
  });

  @override
  Widget build(BuildContext context) {
    final value = clientId;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.perm_identity, color: Colors.amber),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'clientId',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value ?? 'Non initialisé (joue une partie multi ou relance l\'app)',
                  style: const TextStyle(color: AppColors.textDisabled, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Copier',
            onPressed: value == null
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: value));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('clientId copié')),
                    );
                  },
            icon: Icon(
              Icons.copy,
              color: value == null ? Colors.white30 : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class BarsCard extends StatelessWidget {
  final String title;
  final Map<String, double> values;

  const BarsCard({
    super.key,
    required this.title,
    required this.values,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...values.entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ValueBar(label: e.key, value: e.value),
              )),
        ],
      ),
    );
  }
}

class ValueBar extends StatelessWidget {
  final String label;
  final double value;

  const ValueBar({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary)),
            Text('${(value * 100).round()}%',
                style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 10,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
          ),
        ),
      ],
    );
  }
}

class AdaptationCard extends StatelessWidget {
  final int mmr;
  final String mmrTier;
  final bool? usedSBMM;
  final DateTime? lastUpdate;
  final DateTime? lastGameTime;
  final List<MetricDelta> deltas;

  const AdaptationCard({
    super.key,
    required this.mmr,
    required this.mmrTier,
    required this.usedSBMM,
    required this.lastUpdate,
    required this.lastGameTime,
    required this.deltas,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = deltas.any((d) => d.before != null && d.after != null);
    final sbmmLabel = usedSBMM == null ? 'n/a' : (usedSBMM! ? 'oui' : 'non');
    final updateLabel = lastUpdate == null ? 'inconnu' : _fmt(lastUpdate!);
    final gameLabel = lastGameTime == null ? 'inconnu' : _fmt(lastGameTime!);
    final showDeltas = usedSBMM == true && hasData;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Adaptation des bots',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'MMR: $mmr ($mmrTier)  •  SBMM: $sbmmLabel',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'MAJ profil: $updateLabel  •  Dernière partie: $gameLabel',
            style: const TextStyle(color: AppColors.textDisabled, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (showDeltas)
            Column(
              children: deltas.map((d) => DeltaRow(delta: d)).toList(),
            )
          else if (usedSBMM != true)
            const Text(
              'Profil SBMM uniquement. Lance une partie en mode SBMM pour activer l\'adaptation.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          else
            const Text(
              'Pas encore assez de données pour mesurer l\'adaptation.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) {
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d/$m $h:$min';
  }
}

class DeltaRow extends StatelessWidget {
  final MetricDelta delta;

  const DeltaRow({super.key, required this.delta});

  @override
  Widget build(BuildContext context) {
    final before = delta.before;
    final after = delta.after;
    final change = delta.delta;
    final hasValue = before != null && after != null;
    final beforeValue = before ?? 0;
    final afterValue = after ?? 0;
    final changeValue = change ?? 0;
    final sign = (change ?? 0) >= 0 ? '+' : '';
    final textColor = !hasValue
        ? AppColors.textDisabled
        : (change ?? 0) >= 0
            ? Colors.lightGreenAccent
            : Colors.redAccent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              delta.label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          Text(
            hasValue ? _fmtValue(beforeValue, delta.isPercent) : '--',
            style: const TextStyle(color: AppColors.textDisabled, fontSize: 12),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward, size: 12, color: Colors.white30),
          const SizedBox(width: 8),
          Text(
            hasValue ? _fmtValue(afterValue, delta.isPercent) : '--',
            style: const TextStyle(color: AppColors.textDisabled, fontSize: 12),
          ),
          const SizedBox(width: 12),
          Text(
            hasValue ? '$sign${_fmtDelta(changeValue, delta.isPercent)}' : '--',
            style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _fmtValue(double v, bool percent) {
    if (percent) return '${(v * 100).round()}%';
    return v.toStringAsFixed(2);
  }

  String _fmtDelta(double v, bool percent) {
    if (percent) return '${(v * 100).round()}%';
    return v.toStringAsFixed(2);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHART WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class LineChartCard extends StatelessWidget {
  final String title;
  final Map<String, List<double>> series;

  const LineChartCard({
    super.key,
    required this.title,
    required this.series,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: CustomPaint(
              painter: MiniLineChartPainter(series: series),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: series.keys
                .map((k) => _LegendItem(label: k, color: MiniLineChartPainter.colorForKey(k)))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendItem({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}

class MiniLineChartPainter extends CustomPainter {
  final Map<String, List<double>> series;

  MiniLineChartPainter({
    required this.series,
  });

  static Color colorForKey(String key) {
    switch (key) {
      case 'Mémoire':
        return const Color(0xFF63b3ed);
      case 'Pouvoirs':
        return const Color(0xFFf6ad55);
      case 'Risque':
        return const Color(0xFFfc8181);
      default:
        return const Color(0xFF68d391);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), bgPaint);
    }

    series.forEach((name, values) {
      if (values.isEmpty) return;

      final linePaint = Paint()
        ..color = colorForKey(name)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      final path = Path();
      for (int i = 0; i < values.length; i++) {
        final x = values.length == 1
            ? size.width / 2
            : (i / (values.length - 1)) * size.width;
        final y = (1 - values[i]) * size.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, linePaint);
    });
  }

  @override
  bool shouldRepaint(covariant MiniLineChartPainter oldDelegate) {
    return oldDelegate.series != series;
  }
}

class HistoryCard extends StatelessWidget {
  final List<PlayerGameRecord> history;

  const HistoryCard({
    super.key,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dernières parties',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (history.isEmpty)
            const Text('Aucune partie enregistrée', style: TextStyle(color: AppColors.textDisabled)),
          ...history.take(6).map((g) {
            final date = g.endTime.toLocal();
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                  Text(
                    'Rank ${g.finalRank}/${g.numberOfPlayers}',
                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${g.finalScore} pts',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
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

// ═══════════════════════════════════════════════════════════════════════════
// BOT MATCHUP CARD
// ═══════════════════════════════════════════════════════════════════════════

class BotMatchupCard extends StatelessWidget {
  final List<BotMatchupRecord> matchups;

  const BotMatchupCard({
    super.key,
    required this.matchups,
  });

  static const _diffLabels = {
    'hard': 'Difficile',
    'difficile': 'Difficile',
    'platinum': 'Difficile', // legacy
    'easy': 'Bronze',
    'medium': 'Argent',
    'mix': 'Mix',
  };

  static const _diffColors = {
    'hard': Colors.purple,
    'difficile': Colors.purple,
    'platinum': Colors.purple, // legacy
    'easy': Colors.brown,
    'medium': Colors.grey,
    'mix': Colors.teal,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.sports_kabaddi, color: Colors.amber, size: 18),
              SizedBox(width: 8),
              Text(
                'Performance vs Bots',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (matchups.isEmpty)
            const Text('Aucune donnée. Joue des parties pour voir tes stats vs bots.',
                style: TextStyle(color: AppColors.textDisabled, fontSize: 12))
          else ...[
            // Résumé global
            _buildSummary(),
            const SizedBox(height: 12),
            // Winrate par difficulté
            _buildPerDifficultyStats(),
            const SizedBox(height: 12),
            // 5 dernières parties
            const Text('Derniers matchups',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            const SizedBox(height: 6),
            ...matchups.take(5).map(_buildMatchupRow),
          ],
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final total = matchups.length;
    final wins = matchups.where((m) => m.playerWon).length;
    final winRate = total > 0 ? (wins / total * 100).round() : 0;
    final boostedCount = matchups.where((m) => m.wasBoostedSBMM).length;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$winRate% winrate',
                style: TextStyle(
                  color: winRate >= 50 ? Colors.lightGreenAccent : Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                '$wins/$total parties gagnées',
                style: const TextStyle(color: AppColors.textDisabled, fontSize: 12),
              ),
            ],
          ),
        ),
        if (boostedCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
            ),
            child: Text(
              '$boostedCount boosté${boostedCount > 1 ? 's' : ''}',
              style: const TextStyle(color: Colors.orange, fontSize: AppFontSizes.small, fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }

  Widget _buildPerDifficultyStats() {
    // Grouper par difficulté
    final byDiff = <String, List<BotMatchupRecord>>{};
    for (final m in matchups) {
      byDiff.putIfAbsent(m.difficulty, () => []).add(m);
    }

    if (byDiff.length <= 1) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: byDiff.entries.map((e) {
        final diff = e.key;
        final records = e.value;
        final wins = records.where((m) => m.playerWon).length;
        final wr = (wins / records.length * 100).round();
        final color = _diffColors[diff] ?? Colors.white;
        final label = _diffLabels[diff] ?? diff;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$label: $wr% ($wins/${records.length})',
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMatchupRow(BotMatchupRecord m) {
    final date = m.timestamp.toLocal();
    final dateStr = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
    final diffLabel = _diffLabels[m.difficulty] ?? m.difficulty;
    final diffColor = _diffColors[m.difficulty] ?? Colors.white;
    final won = m.playerWon;
    final bestBotScore = m.bots.isNotEmpty
        ? m.bots.map((b) => b.botScore).reduce((a, b) => a < b ? a : b)
        : 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(dateStr,
                style: const TextStyle(color: AppColors.textDisabled, fontSize: AppFontSizes.small)),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: diffColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(diffLabel,
                style: TextStyle(color: diffColor, fontSize: AppFontSizes.small, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Icon(
            won ? Icons.emoji_events : Icons.close,
            color: won ? Colors.amber : Colors.redAccent,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            '${m.playerRank}/${m.numberOfPlayers}',
            style: TextStyle(
              color: won ? Colors.lightGreenAccent : Colors.redAccent,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
          const Spacer(),
          Text(
            '${m.playerScore} vs $bestBotScore',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: AppFontSizes.small),
          ),
          if (m.wasBoostedSBMM) ...[
            const SizedBox(width: 6),
            const Icon(Icons.bolt, color: Colors.orange, size: 12),
          ],
        ],
      ),
    );
  }
}
