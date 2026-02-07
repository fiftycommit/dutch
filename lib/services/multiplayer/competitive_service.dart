import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CompetitiveStats {
  final int mmr;
  final int wins;
  final int losses;
  final int gamesPlayed;
  final int winStreak;
  final int bestWinStreak;
  final int rank;
  final String tier;
  final DateTime lastPlayed;

  CompetitiveStats({
    required this.mmr,
    required this.wins,
    required this.losses,
    required this.gamesPlayed,
    required this.winStreak,
    required this.bestWinStreak,
    required this.rank,
    required this.tier,
    required this.lastPlayed,
  });

  factory CompetitiveStats.fromJson(Map<String, dynamic> json) {
    return CompetitiveStats(
      mmr: json['mmr'] ?? 0,
      wins: json['wins'] ?? 0,
      losses: json['losses'] ?? 0,
      gamesPlayed: json['gamesPlayed'] ?? 0,
      winStreak: json['winStreak'] ?? 0,
      bestWinStreak: json['bestWinStreak'] ?? 0,
      rank: json['rank'] ?? 0,
      tier: json['tier'] ?? 'Bronze',
      lastPlayed: json['lastPlayed'] != null
          ? DateTime.parse(json['lastPlayed'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mmr': mmr,
      'wins': wins,
      'losses': losses,
      'gamesPlayed': gamesPlayed,
      'winStreak': winStreak,
      'bestWinStreak': bestWinStreak,
      'rank': rank,
      'tier': tier,
      'lastPlayed': lastPlayed.toIso8601String(),
    };
  }

  double get winRate => gamesPlayed > 0 ? (wins / gamesPlayed) * 100 : 0.0;
}

class CompetitiveService {
  static const String _keyPrefix = 'competitive_stats_';
  static const int _startingMMR = 1000;
  static const int _kFactor = 32;

  /// Récupère les stats compétitives d'un joueur
  static Future<CompetitiveStats> getStats(String playerId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_keyPrefix$playerId';
    final jsonString = prefs.getString(key);

    if (jsonString == null) {
      return CompetitiveStats(
        mmr: _startingMMR,
        wins: 0,
        losses: 0,
        gamesPlayed: 0,
        winStreak: 0,
        bestWinStreak: 0,
        rank: 0,
        tier: 'Bronze',
        lastPlayed: DateTime.now(),
      );
    }

    return CompetitiveStats.fromJson(json.decode(jsonString));
  }

  /// Sauvegarde les stats compétitives
  static Future<void> saveStats(String playerId, CompetitiveStats stats) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_keyPrefix$playerId';
    await prefs.setString(key, json.encode(stats.toJson()));
  }

  /// Calcule le changement de MMR basé sur le résultat de la partie
  static int calculateMMRChange({
    required int playerMMR,
    required int playerRank,
    required int totalPlayers,
    required List<int> opponentMMRs,
  }) {
    // Calcul de l'expected score basé sur la formule Elo
    double expectedScore = 0.0;
    for (final opponentMMR in opponentMMRs) {
      expectedScore += 1 / (1 + pow(10, (opponentMMR - playerMMR) / 400));
    }
    expectedScore /= opponentMMRs.length;

    // Score réel basé sur le classement
    // 1er = 1.0, 2e = 0.66, 3e = 0.33, 4e = 0.0
    double actualScore = (totalPlayers - playerRank) / (totalPlayers - 1);

    // Changement de MMR
    int change = (_kFactor * (actualScore - expectedScore)).round();

    // Bonus pour victoire
    if (playerRank == 1) {
      change += 10;
    }

    // Pénalité pour dernière place
    if (playerRank == totalPlayers) {
      change -= 5;
    }

    return change;
  }

  /// Met à jour les stats après une partie compétitive
  static Future<CompetitiveStats> updateAfterGame({
    required String playerId,
    required int playerRank,
    required int totalPlayers,
    required List<int> opponentMMRs,
  }) async {
    final stats = await getStats(playerId);

    final mmrChange = calculateMMRChange(
      playerMMR: stats.mmr,
      playerRank: playerRank,
      totalPlayers: totalPlayers,
      opponentMMRs: opponentMMRs,
    );

    final newMMR = (stats.mmr + mmrChange).clamp(0, 3000);
    final won = playerRank == 1;

    final newStats = CompetitiveStats(
      mmr: newMMR,
      wins: stats.wins + (won ? 1 : 0),
      losses: stats.losses + (won ? 0 : 1),
      gamesPlayed: stats.gamesPlayed + 1,
      winStreak: won ? stats.winStreak + 1 : 0,
      bestWinStreak: won
          ? (stats.winStreak + 1 > stats.bestWinStreak
              ? stats.winStreak + 1
              : stats.bestWinStreak)
          : stats.bestWinStreak,
      rank: _calculateRank(newMMR),
      tier: _getTier(newMMR),
      lastPlayed: DateTime.now(),
    );

    await saveStats(playerId, newStats);
    return newStats;
  }

  /// Calcule le rang global basé sur le MMR
  static int _calculateRank(int mmr) {
    // Simulation simple - dans un vrai système, ce serait basé sur tous les joueurs
    if (mmr >= 2000) return 1;
    if (mmr >= 1800) return 2;
    if (mmr >= 1600) return 5;
    if (mmr >= 1400) return 10;
    if (mmr >= 1200) return 25;
    if (mmr >= 1000) return 50;
    return 100;
  }

  /// Détermine le tier basé sur le MMR
  static String _getTier(int mmr) {
    if (mmr >= 2200) return 'Diamant';
    if (mmr >= 1900) return 'Platine';
    if (mmr >= 1600) return 'Or';
    if (mmr >= 1300) return 'Argent';
    return 'Bronze';
  }

  /// Récupère la couleur associée au tier
  static int getTierColor(String tier) {
    switch (tier) {
      case 'Diamant':
        return 0xFF00D9FF;
      case 'Platine':
        return 0xFF00FF88;
      case 'Or':
        return 0xFFFFD700;
      case 'Argent':
        return 0xFFC0C0C0;
      default:
        return 0xFFCD7F32; // Bronze
    }
  }

  /// Récupère l'icône associée au tier
  static String getTierIcon(String tier) {
    switch (tier) {
      case 'Diamant':
        return '💎';
      case 'Platine':
        return '🏆';
      case 'Or':
        return '🥇';
      case 'Argent':
        return '🥈';
      default:
        return '🥉'; // Bronze
    }
  }

  /// Réinitialise les stats compétitives
  static Future<void> resetStats(String playerId) async {
    final newStats = CompetitiveStats(
      mmr: _startingMMR,
      wins: 0,
      losses: 0,
      gamesPlayed: 0,
      winStreak: 0,
      bestWinStreak: 0,
      rank: 0,
      tier: 'Bronze',
      lastPlayed: DateTime.now(),
    );
    await saveStats(playerId, newStats);
  }
}

// Fonction pow manquante
double pow(num x, num exponent) {
  if (exponent == 0) return 1.0;
  if (exponent == 1) return x.toDouble();
  
  double result = 1.0;
  int exp = exponent.abs().toInt();
  double base = x.toDouble();
  
  for (int i = 0; i < exp; i++) {
    result *= base;
  }
  
  if (exponent < 0) {
    return 1.0 / result;
  }
  return result;
}
