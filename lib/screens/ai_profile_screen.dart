import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/player_learning_data.dart';
import '../services/player_learning_service.dart';

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
        child: Text('Profil indisponible', style: TextStyle(color: Colors.white70)),
      );
    }

    final params = profile.learnedParameters;

    final aggressiveness = _clamp01(_num(params, 'aggressiveness', 0.5));
    final caution = _clamp01(_num(params, 'caution', 0.5));
    final powerUsageRate = _clamp01(_num(params, 'powerUsageRate', 0.5));
    final memoryAccuracy = _clamp01(_num(params, 'memoryAccuracy', 0.7));
    final riskTolerance = _clamp01(_num(params, 'riskTolerance', 0.5));

    final last10 = _history.take(10).toList().reversed.toList();

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
          _BarsCard(
            title: 'Paramètres actuels',
            values: {
              'Mémoire': memoryAccuracy,
              'Pouvoirs': powerUsageRate,
              'Risque': riskTolerance,
              'Agressif': aggressiveness,
              'Prudent': caution,
            },
          ),
          const SizedBox(height: 12),
          _LineChartCard(
            title: 'Évolution (10 dernières parties)',
            series: {
              'Mémoire': series('memoryAccuracy', 0.7),
              'Pouvoirs': series('powerUsageRate', 0.5),
              'Risque': series('riskTolerance', 0.5),
            },
          ),
          const SizedBox(height: 12),
          _HistoryCard(history: _history),
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
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
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
                Text(
                  value ?? 'Non initialisé (joue une partie multi ou relance l’app)',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
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
            Text(label, style: const TextStyle(color: Colors.white70)),
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
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
            const Text('Aucune partie enregistrée', style: TextStyle(color: Colors.white60)),
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
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                  Text(
                    'Rank ${g.finalRank}/${g.numberOfPlayers}',
                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${g.finalScore} pts',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
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
