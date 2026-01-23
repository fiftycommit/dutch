import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_settings.dart';

class StatsService {
  static const String _statsKeyPrefix = 'game_stats_slot_';

  static String _getKey(int slotId) => '$_statsKeyPrefix$slotId';

  static Future<Map<String, dynamic>> getStats({int slotId = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    String? statsJson = prefs.getString(_getKey(slotId));

    if (statsJson == null) {
      return _getEmptyStats();
    }

    try {
      return jsonDecode(statsJson);
    } catch (e) {
      return _getEmptyStats();
    }
  }

  static Map<String, dynamic> _getEmptyStats() {
    return {
      "gamesPlayed": 0,
      "gamesWon": 0,
      "bestScore": null,
      "totalScore": 0,
      "mmr": 0,
      "dutchCalls": 0,
      "dutchWins": 0,
      "history": [],
    };
  }

  static Future<void> saveGameResult({
    required int playerRank,
    required int score,
    required bool calledDutch,
    required bool wonDutch,
    int slotId = 1,
    bool isSBMM = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> stats = await getStats(slotId: slotId);

    stats["gamesPlayed"] = (stats["gamesPlayed"] ?? 0) + 1;

    if (playerRank == 1) {
      stats["gamesWon"] = (stats["gamesWon"] ?? 0) + 1;
    }


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

    if (isSBMM) {
      switch (playerRank) {
        case 1:
          mmrChange = 50;
          if (calledDutch) {
            mmrChange += 30;
          }
          break;
        case 2:
          mmrChange = 25;
          break;
        case 3:
          mmrChange = -15;
          break;
        case 4:
          mmrChange = -30;
          if (calledDutch && !wonDutch) {
            mmrChange -= 30;
          }
          break;
      }

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
    });

    if (history.length > 20) history = history.sublist(0, 20);
    stats["history"] = history;

    await prefs.setString(_getKey(slotId), jsonEncode(stats));
  }

  static Future<void> resetStats({int slotId = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_getKey(slotId));
  }

  static Future<Difficulty> getRecommendedDifficulty({int slotId = 1}) async {
    Map<String, dynamic> stats = await getStats(slotId: slotId);
    int mmr = stats["mmr"] ?? 0;

    if (mmr < 150) {
      return Difficulty.easy;
    } else if (mmr < 450) {
      return Difficulty.medium;
    } else {
      return Difficulty.hard;
    }
  }

  static String getRankName(int mmr) {
    if (mmr < 150) return "Bronze";
    if (mmr < 450) return "Argent";
    return "Or";
  }
}
