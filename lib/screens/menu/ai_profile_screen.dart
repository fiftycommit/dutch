import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/player_learning_data.dart';
import '../../services/learning/player_learning_service.dart';
import '../../services/ui/stats_service.dart';
import '../../utils/ui_constants.dart';
import 'ai_profile_widgets.dart';

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
  int _rp = 0;

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
      final stats = await StatsService.getStats(slotId: widget.slotId);
      final rp = (stats['mmr'] ?? 0) as int;
      if (!mounted) return;
      setState(() {
        _clientId = clientId;
        _profile = profile;
        _history = history;
        _rp = rp;
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
        backgroundColor: AppColors.backgroundMedium,
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
            colors: [AppColors.backgroundMedium, AppColors.backgroundDark],
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
          ClientIdCard(clientId: _clientId),
          const SizedBox(height: 12),
          InfoCard(
            title: 'Slot',
            value: 'J${widget.slotId}',
            subtitle: '${profile.gamesAnalyzed} parties analysées',
          ),
          const SizedBox(height: 12),
          const InfoCard(
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

    final deltas = <MetricDelta>[
      MetricDelta(
        label: 'Agressif',
        before: before == null ? null : _num(before, 'aggressiveness', 0.5),
        after: after == null ? null : _num(after, 'aggressiveness', 0.5),
        isPercent: true,
      ),
      MetricDelta(
        label: 'Prudent',
        before: before == null ? null : _num(before, 'caution', 0.5),
        after: after == null ? null : _num(after, 'caution', 0.5),
        isPercent: true,
      ),
      MetricDelta(
        label: 'Mémoire',
        before: before == null ? null : _num(before, 'memoryAccuracy', 0.7),
        after: after == null ? null : _num(after, 'memoryAccuracy', 0.7),
        isPercent: true,
      ),
      MetricDelta(
        label: 'Adaptabilité',
        before: before == null ? null : _num(before, 'adaptability', 0.5),
        after: after == null ? null : _num(after, 'adaptability', 0.5),
        isPercent: true,
      ),
      MetricDelta(
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
          ClientIdCard(clientId: _clientId),
          const SizedBox(height: 12),
          InfoCard(
            title: 'Slot',
            value: 'J${widget.slotId}',
            subtitle: '${profile.gamesAnalyzed} parties analysées',
          ),
          const SizedBox(height: 12),
          AdaptationCard(
            mmr: _rp,
            mmrTier: _mmrTier(_rp),
            usedSBMM: lastRecord?.usedSBMM,
            lastUpdate: profile.lastUpdatedAt,
            lastGameTime: lastRecord?.endTime,
            deltas: deltas,
          ),
          const SizedBox(height: 12),
          BarsCard(
            title: 'Style de jeu',
            values: {
              'Agressif': aggressiveness,
              'Prudent': caution,
              'Adaptabilité': adaptability,
            },
          ),
          const SizedBox(height: 12),
          BarsCard(
            title: 'Mémoire & Précision',
            values: {
              'Mémoire (match)': memoryAccuracy,
              'Rétention': memoryRetention,
              'Dutch (précision)': dutchQuality,
            },
          ),
          const SizedBox(height: 12),
          BarsCard(
            title: 'Pouvoirs (usage quand dispo)',
            values: {
              'Défensif (7/8)': powerDefensive,
              'Offensif (9/10/V/J)': powerOffensive,
            },
          ),
          const SizedBox(height: 12),
          InfoCard(
            title: 'Ciblage',
            value: targetingStrategy == 'leader' ? '🎯 Leader' : targetingStrategy == 'weak' ? '🎯 Faible' : '🎯 Équilibré',
            subtitle: 'Vitesse: ${(decisionSpeed / 1000).toStringAsFixed(1)}s',
          ),
          const SizedBox(height: 12),
          LineChartCard(
            title: 'Évolution (10 dernières parties)',
            series: {
              'Agressif': series('aggressiveness', 0.5),
              'Mémoire': series('memoryAccuracy', 0.7),
              'Adaptabilité': series('adaptability', 0.5),
            },
          ),
          const SizedBox(height: 12),
          HistoryCard(history: sbmmHistory),
        ],
      ),
    );
  }
}
