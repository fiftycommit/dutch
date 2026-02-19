import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/interfaces/i_stats_service.dart';
import '../../models/game_settings.dart';
import '../game/rp_calculator.dart';

/// Implémentation concrète du service de statistiques
/// Principe SOLID: DIP - Implémente l'interface IStatsService
class StatsServiceImpl implements IStatsService {
  static const String _statsKeyPrefix = 'game_stats_slot_';

  String _getKey(int slotId) => '$_statsKeyPrefix$slotId';

  @override
  Future<Map<String, dynamic>> getStats({int slotId = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    String? statsJson = prefs.getString(_getKey(slotId));

    if (statsJson == null) {
      return _getEmptyStats();
    }

    try {
      return jsonDecode(statsJson);
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Stats JSON decode error: $e');
      return _getEmptyStats();
    }
  }

  Map<String, dynamic> _getEmptyStats() {
    return {
      "gamesPlayed": 0,
      "gamesWon": 0,
      "bestScore": null,
      "totalScore": 0,
      "mmr": 0,
      "winStreak": 0,
      "bestWinStreak": 0,
      "dutchCalls": 0,
      "dutchWins": 0,
      "history": [],
    };
  }

  @override
  Future<void> saveGameResult({
    required int playerRank,
    required int score,
    required bool calledDutch,
    required bool wonDutch,
    bool hasEmptyHand = false,
    int slotId = 1,
    bool isSBMM = false,
    int totalPlayers = 4,
    bool isTournament = false,
    int tournamentRound = 1,
    String? tournamentId,
    List<String>? actionHistory,
    String? gameLog,
    String? scoreDetail,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> stats = await getStats(slotId: slotId);

    stats["gamesPlayed"] = (stats["gamesPlayed"] ?? 0) + 1;

    if (playerRank == 1) {
      stats["gamesWon"] = (stats["gamesWon"] ?? 0) + 1;
    }

    int winStreak = stats["winStreak"] ?? 0;
    if (playerRank == 1) {
      winStreak += 1;
    } else {
      winStreak = 0;
    }
    stats["winStreak"] = winStreak;

    int bestWinStreak = stats["bestWinStreak"] ?? 0;
    if (winStreak > bestWinStreak) {
      bestWinStreak = winStreak;
    }
    stats["bestWinStreak"] = bestWinStreak;

    int? currentBest = stats["bestScore"];
    if (currentBest == null || score < currentBest) {
      stats["bestScore"] = score;
    }
    stats["totalScore"] = (stats["totalScore"] ?? 0) + score;

    if (calledDutch) {
      stats["dutchCalls"] = (stats["dutchCalls"] ?? 0) + 1;
      if (wonDutch) {
        stats["dutchWins"] = (stats["dutchWins"] ?? 0) + 1;
      }
    }

    int currentMMR = stats["mmr"] ?? 0;
    int mmrChange = 0;
    int streakBonus = 0;
    double streakMultiplier = 1.0;

    if (isSBMM) {
      RPResult rpResult = RPCalculator.calculateRP(
        playerRank: playerRank,
        currentMMR: currentMMR,
        calledDutch: calledDutch,
        hasEmptyHand: hasEmptyHand,
        isEliminated: calledDutch && playerRank != 1,
        totalPlayers: totalPlayers,
        isTournament: isTournament,
        tournamentRound: tournamentRound,
        winStreak: winStreak,
      );
      
      mmrChange = rpResult.totalChange;
      streakBonus = rpResult.streakBonus;
      streakMultiplier = rpResult.streakMultiplier;

      int newMMR = currentMMR + mmrChange;
      if (newMMR < 0) newMMR = 0;

      stats["mmr"] = newMMR;
    }

    List<dynamic> history = List.from(stats["history"] ?? []);
    history.insert(0, {
      "date": DateTime.now().toIso8601String(),
      "score": score,
      "rank": playerRank,
      "dutch": calledDutch,
      "mmrChange": mmrChange,
      "gameMode": isTournament ? "tournament" : "quick",
      "tournamentId": isTournament ? tournamentId : null,
      "tournamentRound": isTournament ? tournamentRound : null,
      "totalPlayers": totalPlayers,
      "actionHistory": actionHistory ?? [],
      "gameLog": gameLog,
      "scoreDetail": scoreDetail,
      "winStreak": winStreak,
      "streakBonus": streakBonus,
      "streakMultiplier": streakMultiplier,
    });

    if (history.length > 20) history = history.sublist(0, 20);
    stats["history"] = history;

    await prefs.setString(_getKey(slotId), jsonEncode(stats));
  }

  @override
  Future<void> resetStats({int slotId = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_getKey(slotId));
  }

  @override
  Future<Difficulty> getRecommendedDifficulty({int slotId = 1}) async {
    Map<String, dynamic> stats = await getStats(slotId: slotId);
    int mmr = stats["mmr"] ?? 0;

    if (mmr < 300) {
      return Difficulty.easy;
    } else if (mmr < 600) {
      return Difficulty.medium;
    } else {
      return Difficulty.hard;
    }
  }

  @override
  String getRankName(int mmr) {
    return RPCalculator.getRankName(mmr);
  }

  @override
  Future<void> recordAiTelemetry(Map<String, dynamic> telemetry, {int slotId = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'ai_telemetry_slot_$slotId';
    
    // Récupérer l'historique existant
    final existingJson = prefs.getString(key);
    List<Map<String, dynamic>> history = [];
    
    if (existingJson != null) {
      try {
        final decoded = jsonDecode(existingJson);
        if (decoded is List) {
          history = decoded.cast<Map<String, dynamic>>();
        }
      } catch (_) {}
    }
    
    // Ajouter la nouvelle entrée avec timestamp
    telemetry['timestamp'] = DateTime.now().toIso8601String();
    history.insert(0, telemetry);
    
    // Garder seulement les 50 dernières parties
    if (history.length > 50) {
      history = history.sublist(0, 50);
    }
    
    await prefs.setString(key, jsonEncode(history));
  }
}
