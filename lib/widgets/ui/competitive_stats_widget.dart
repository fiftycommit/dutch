import 'package:flutter/material.dart';
import '../../services/multiplayer/competitive_service.dart';
import '../../utils/ui_constants.dart';

class CompetitiveStatsWidget extends StatelessWidget {
  final CompetitiveStats stats;
  final bool compact;

  const CompetitiveStatsWidget({
    super.key,
    required this.stats,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompactView();
    }
    return _buildFullView();
  }

  Widget _buildCompactView() {
    final tierColor = Color(CompetitiveService.getTierColor(stats.tier));
    final tierIcon = CompetitiveService.getTierIcon(stats.tier);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            tierColor.withValues(alpha: 0.3),
            tierColor.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tierColor, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tierIcon,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(width: 8),
          Text(
            '${stats.mmr} MMR',
            style: TextStyle(
              color: tierColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            stats.tier,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullView() {
    final tierColor = Color(CompetitiveService.getTierColor(stats.tier));
    final tierIcon = CompetitiveService.getTierIcon(stats.tier);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.gradientBottom,
            tierColor.withValues(alpha: 0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tierColor, width: 3),
        boxShadow: [
          BoxShadow(
            color: tierColor.withValues(alpha: 0.3),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    tierIcon,
                    style: const TextStyle(fontSize: 40),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stats.tier,
                        style: TextStyle(
                          color: tierColor,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Rang #${stats.rank}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tierColor, width: 2),
                ),
                child: Column(
                  children: [
                    Text(
                      '${stats.mmr}',
                      style: TextStyle(
                        color: tierColor,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'MMR',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white24),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                'Victoires',
                '${stats.wins}',
                Colors.green,
                Icons.emoji_events,
              ),
              _buildStatItem(
                'Défaites',
                '${stats.losses}',
                Colors.red,
                Icons.close,
              ),
              _buildStatItem(
                'Win Rate',
                '${stats.winRate.toStringAsFixed(1)}%',
                Colors.amber,
                Icons.percent,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                'Parties',
                '${stats.gamesPlayed}',
                Colors.blue,
                Icons.sports_esports,
              ),
              _buildStatItem(
                'Série actuelle',
                '${stats.winStreak}',
                Colors.orange,
                Icons.local_fire_department,
              ),
              _buildStatItem(
                'Meilleure série',
                '${stats.bestWinStreak}',
                Colors.purple,
                Icons.star,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class CompetitiveMatchResult extends StatelessWidget {
  final int mmrChange;
  final CompetitiveStats newStats;
  final int playerRank;
  final int totalPlayers;

  const CompetitiveMatchResult({
    super.key,
    required this.mmrChange,
    required this.newStats,
    required this.playerRank,
    required this.totalPlayers,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = mmrChange >= 0;
    final tierColor = Color(CompetitiveService.getTierColor(newStats.tier));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.gradientBottom,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tierColor, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            playerRank == 1 ? '🏆 VICTOIRE !' : '📊 PARTIE TERMINÉE',
            style: TextStyle(
              color: playerRank == 1 ? Colors.amber : Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'MMR: ${newStats.mmr - mmrChange}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 18,
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                color: isPositive ? Colors.green : Colors.red,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                '${isPositive ? '+' : ''}$mmrChange',
                style: TextStyle(
                  color: isPositive ? Colors.green : Colors.red,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '→ ${newStats.mmr}',
                style: TextStyle(
                  color: tierColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${newStats.tier} • Rang #${newStats.rank}',
            style: TextStyle(
              color: tierColor,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Classement: $playerRank/$totalPlayers',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
