import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/player_learning_data.dart';
import '../../services/learning/player_learning_service.dart';
import '../../utils/ui_constants.dart';

class AiProfileScreen extends StatefulWidget {
  final int slotId;

  const AiProfileScreen({
    super.key,
    required this.slotId,
  });

  @override
  State<AiProfileScreen> createState() => _AiProfileScreenState();
}

class _AiProfileScreenState extends State<AiProfileScreen> {
  final PlayerLearningService _service = PlayerLearningService();

  PlayerProfile? _profile;
  List<PlayerGameRecord> _history = const [];
  String? _clientId;

  Timer? _refreshTimer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clientId = prefs.getString('multiplayer_client_id');
      final profile = await _service.getProfile(slotId: widget.slotId);
      final history = await _service.getHistory(slotId: widget.slotId);
      if (!mounted) return;
      setState(() {
        _clientId = clientId;
        _profile = profile;
        _history = history;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  double _num(Map<String, dynamic> map, String key, double fallback) {
    final v = map[key];
    if (v is num) return v.toDouble();
    return fallback;
  }

  double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  String _mmrTier(int mmr) {
    if (mmr >= 900) return 'Platine';
    if (mmr >= 600) return 'Or';
    if (mmr >= 300) return 'Argent';
    return 'Bronze';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MON PROFIL IA',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1a3a28),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/'),
        ),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1a3a28), Color(0xFF0d1f15)],
          ),
        ),
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.amber),
              )
            : _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final profile = _profile;
    if (profile == null) {
      return const Center(
        child: Text('Profil indisponible', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final sbmmHistory = _history.where((g) => g.usedSBMM).toList();
    if (sbmmHistory.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ClientIdCard(clientId: _clientId),
          const SizedBox(height: 12),
          _InfoCard(
            title: 'Slot',
            value: 'J${widget.slotId}',
            subtitle: '${profile.gamesAnalyzed} parties analysées',
          ),
          const SizedBox(height: 12),
          const _InfoCard(
            title: 'Profil SBMM',
            value: 'Inactif',
            subtitle: 'Lance une partie en mode SBMM pour activer le profil IA.',
          ),
        ],
      );
    }

    final params = profile.learnedParameters;

    final aggressiveness = _clamp01(_num(params, 'aggressiveness', 0.5));
    final caution = _clamp01(_num(params, 'caution', 0.5));
    final dutchQuality = _clamp01(_num(params, 'dutchQuality', 0.5));
    final powerDefensive = _clamp01(_num(params, 'powerDefensiveRate', 0.5));
    final powerOffensive = _clamp01(_num(params, 'powerOffensiveRate', 0.5));
    final memoryAccuracy = _clamp01(_num(params, 'memoryAccuracy', 0.7));
    final memoryRetention = _clamp01(_num(params, 'memoryRetention', 0.7));
    final adaptability = _clamp01(_num(params, 'adaptability', 0.5));
    final decisionSpeed = _num(params, 'decisionSpeed', 2000.0);
    final targetingStrategy = params['targetingStrategy'] ?? 'balanced';

    final last10 = sbmmHistory.take(10).toList().reversed.toList();
    final lastRecord = sbmmHistory.isNotEmpty ? sbmmHistory.first : null;
    final before = lastRecord?.profileBefore;
    final after = lastRecord?.profileAfter;

    final deltas = <_MetricDelta>[
      _MetricDelta(
        label: 'Agressif',
        before: before == null ? null : _num(before, 'aggressiveness', 0.5),
        after: after == null ? null : _num(after, 'aggressiveness', 0.5),
        isPercent: true,
      ),
      _MetricDelta(
        label: 'Prudent',
        before: before == null ? null : _num(before, 'caution', 0.5),
        after: after == null ? null : _num(after, 'caution', 0.5),
        isPercent: true,
      ),
      _MetricDelta(
        label: 'Mémoire',
        before: before == null ? null : _num(before, 'memoryAccuracy', 0.7),
        after: after == null ? null : _num(after, 'memoryAccuracy', 0.7),
        isPercent: true,
      ),
      _MetricDelta(
        label: 'Adaptabilité',
        before: before == null ? null : _num(before, 'adaptability', 0.5),
        after: after == null ? null : _num(after, 'adaptability', 0.5),
        isPercent: true,
      ),
      _MetricDelta(
        label: 'Pouvoirs off.',
        before: before == null ? null : _num(before, 'powerOffensiveRate', 0.5),
        after: after == null ? null : _num(after, 'powerOffensiveRate', 0.5),
        isPercent: true,
      ),
    ];

    List<double> series(String key, double fallback) {
      return last10
          .map((g) => _clamp01(_num(g.profileAfter ?? const {}, key, fallback)))
          .toList();
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: Colors.amber,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ClientIdCard(clientId: _clientId),
          const SizedBox(height: 12),
          _InfoCard(
            title: 'Slot',
            value: 'J${widget.slotId}',
            subtitle: '${profile.gamesAnalyzed} parties analysées',
          ),
          const SizedBox(height: 12),
          _AdaptationCard(
            mmr: profile.mmr,
            mmrTier: _mmrTier(profile.mmr),
            usedSBMM: lastRecord?.usedSBMM,
            lastUpdate: profile.lastUpdatedAt,
            lastGameTime: lastRecord?.endTime,
            deltas: deltas,
          ),
          const SizedBox(height: 12),
          _BarsCard(
            title: 'Style de jeu',
            values: {
              'Agressif': aggressiveness,
              'Prudent': caution,
              'Adaptabilité': adaptability,
            },
          ),
          const SizedBox(height: 12),
          _BarsCard(
            title: 'Mémoire & Précision',
            values: {
              'Mémoire (match)': memoryAccuracy,
              'Rétention': memoryRetention,
              'Dutch (précision)': dutchQuality,
            },
          ),
          const SizedBox(height: 12),
          _BarsCard(
            title: 'Pouvoirs (usage quand dispo)',
            values: {
              'Défensif (7/8)': powerDefensive,
              'Offensif (9/10/V/J)': powerOffensive,
            },
          ),
          const SizedBox(height: 12),
          _InfoCard(
            title: 'Ciblage',
            value: targetingStrategy == 'leader' ? '🎯 Leader' : targetingStrategy == 'weak' ? '🎯 Faible' : '🎯 Équilibré',
            subtitle: 'Vitesse: ${(decisionSpeed / 1000).toStringAsFixed(1)}s',
          ),
          const SizedBox(height: 12),
          _LineChartCard(
            title: 'Évolution (10 dernières parties)',
            series: {
              'Agressif': series('aggressiveness', 0.5),
              'Mémoire': series('memoryAccuracy', 0.7),
              'Adaptabilité': series('adaptability', 0.5),
            },
          ),
          const SizedBox(height: 12),
          _HistoryCard(history: sbmmHistory),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;

  const _InfoCard({
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

class _ClientIdCard extends StatelessWidget {
  final String? clientId;

  const _ClientIdCard({
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
                  value ?? 'Non initialisé (joue une partie multi ou relance l’app)',
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

class _BarsCard extends StatelessWidget {
  final String title;
  final Map<String, double> values;

  const _BarsCard({
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
                child: _ValueBar(label: e.key, value: e.value),
              )),
        ],
      ),
    );
  }
}

class _AdaptationCard extends StatelessWidget {
  final int mmr;
  final String mmrTier;
  final bool? usedSBMM;
  final DateTime? lastUpdate;
  final DateTime? lastGameTime;
  final List<_MetricDelta> deltas;

  const _AdaptationCard({
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
              children: deltas.map((d) => _DeltaRow(delta: d)).toList(),
            )
          else if (usedSBMM != true)
            const Text(
              'Profil SBMM uniquement. Lance une partie en mode SBMM pour activer l’adaptation.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          else
            const Text(
              'Pas encore assez de données pour mesurer l’adaptation.',
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

class _DeltaRow extends StatelessWidget {
  final _MetricDelta delta;

  const _DeltaRow({required this.delta});

  @override
  Widget build(BuildContext context) {
    final before = delta.before;
    final after = delta.after;
    final change = delta.delta;
    final hasValue = before != null && after != null;
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
            hasValue ? _fmtValue(before!, delta.isPercent) : '--',
            style: const TextStyle(color: AppColors.textDisabled, fontSize: 12),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward, size: 12, color: Colors.white30),
          const SizedBox(width: 8),
          Text(
            hasValue ? _fmtValue(after!, delta.isPercent) : '--',
            style: const TextStyle(color: AppColors.textDisabled, fontSize: 12),
          ),
          const SizedBox(width: 12),
          Text(
            hasValue ? '$sign${_fmtDelta(change!, delta.isPercent)}' : '--',
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

class _MetricDelta {
  final String label;
  final double? before;
  final double? after;
  final bool isPercent;

  const _MetricDelta({
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

class _ValueBar extends StatelessWidget {
  final String label;
  final double value;

  const _ValueBar({
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

class _LineChartCard extends StatelessWidget {
  final String title;
  final Map<String, List<double>> series;

  const _LineChartCard({
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
              painter: _MiniLineChartPainter(series: series),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: series.keys
                .map((k) => _LegendItem(label: k, color: _MiniLineChartPainter.colorForKey(k)))
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

class _MiniLineChartPainter extends CustomPainter {
  final Map<String, List<double>> series;

  _MiniLineChartPainter({
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
  bool shouldRepaint(covariant _MiniLineChartPainter oldDelegate) {
    return oldDelegate.series != series;
  }
}

class _HistoryCard extends StatelessWidget {
  final List<PlayerGameRecord> history;

  const _HistoryCard({
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
